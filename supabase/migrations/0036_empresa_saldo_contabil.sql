-- Empresa (SPE ou holding) e o balancete mensal por empresa vindo do ERP, base do Fontes e Usos, da DRE
-- societária e do custo incorrido (ver docs/decisoes/0019). O saldo entra com sinal: devedor positivo,
-- credor negativo. Cada mês chega em duas passagens do balancete, com e sem o zeramento da apuração,
-- e a linha do staging só existe quando as duas chegaram.

create table app.empresa (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenant(id) on delete cascade,
  id_origem integer not null,
  nome text not null,
  nome_fantasia text,
  unique (tenant_id, id_origem)
);

-- A obra liga à empresa por (tenant_id, empresa_id) = (tenant_id, id_origem); a 0001 já criou a coluna.
create index centro_custo_empresa_idx on app.centro_custo (tenant_id, empresa_id);

-- Plano de contas por empresa, da resposta mais recente do balancete. As sintéticas entram porque o mapa
-- aceita prefixo sintético e as analíticas abaixo dele herdam a linha.
create table staging.plano_conta (
  tenant_id uuid not null references app.tenant(id) on delete cascade,
  empresa_id uuid not null references app.empresa(id) on delete cascade,
  conta text not null,
  conta_reduzida integer,
  nome text not null,
  analitica boolean not null,
  grupo text check (grupo in ('ativo', 'passivo', 'receita', 'despesa', 'transitoria')),
  primary key (tenant_id, empresa_id, conta)
);

-- Só contas analíticas. As colunas sem sufixo vêm da passagem com zeramento (posição patrimonial real);
-- as _sem_zeramento vêm da passagem que ignora a apuração (resultado e custo acumulados desde o início).
create table staging.saldo_contabil_empresa_mensal (
  tenant_id uuid not null references app.tenant(id) on delete cascade,
  empresa_id uuid not null references app.empresa(id) on delete cascade,
  conta text not null,
  competencia date not null check (competencia = date_trunc('month', competencia)::date),
  saldo_anterior numeric not null,
  debito numeric not null,
  credito numeric not null,
  saldo_final numeric not null,
  saldo_anterior_sem_zeramento numeric not null,
  debito_sem_zeramento numeric not null,
  credito_sem_zeramento numeric not null,
  saldo_final_sem_zeramento numeric not null,
  primary key (tenant_id, empresa_id, conta, competencia)
);
create index saldo_contabil_empresa_mensal_competencia_idx
  on staging.saldo_contabil_empresa_mensal (tenant_id, empresa_id, competencia);

-- Mesmo molde de obras_permitidas: lê como dona e as políticas não entram em recursão. Diretor e
-- financeiro veem todas; leitura vê a empresa que tem obra e cujas obras estão todas entre as dele;
-- gerente de obra nunca, porque F&U e DRE são da empresa, não da obra. Holding sem obra só abre para
-- diretor e financeiro.
create function app.empresas_permitidas() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select e.id
  from app.empresa e
  where e.tenant_id = app.tenant_atual()
    and (
      app.perfil_atual() in ('diretor', 'financeiro')
      or (
        app.perfil_atual() = 'leitura'
        and exists (
          select 1 from app.centro_custo cc
          where cc.tenant_id = e.tenant_id and cc.empresa_id = e.id_origem
        )
        and not exists (
          select 1 from app.centro_custo cc
          where cc.tenant_id = e.tenant_id and cc.empresa_id = e.id_origem
            and cc.id not in (select app.obras_permitidas())
        )
      )
    )
$$;

revoke execute on function app.empresas_permitidas() from public, anon;
grant execute on function app.empresas_permitidas() to authenticated;

-- Leitura pelas empresas permitidas, com a restritiva do segundo fator (0022) e nenhuma política de
-- escrita: só a carga grava, como dona do banco. O select em volta das funções vira initplan.
alter table app.empresa enable row level security;
alter table app.empresa force row level security;
create policy leitura_empresa on app.empresa for select to authenticated
  using (tenant_id = (select app.tenant_atual()) and id in (select app.empresas_permitidas()));
create policy segundo_fator on app.empresa as restrictive for all to authenticated
  using ((select app.segundo_fator_cumprido()));
revoke all on table app.empresa from public, anon, authenticated;
grant select on table app.empresa to authenticated;

alter table staging.saldo_contabil_empresa_mensal enable row level security;
alter table staging.saldo_contabil_empresa_mensal force row level security;
create policy leitura_empresa on staging.saldo_contabil_empresa_mensal for select to authenticated
  using (tenant_id = (select app.tenant_atual()) and empresa_id in (select app.empresas_permitidas()));
create policy segundo_fator on staging.saldo_contabil_empresa_mensal as restrictive for all to authenticated
  using ((select app.segundo_fator_cumprido()));
revoke all on table staging.saldo_contabil_empresa_mensal from public, anon, authenticated;
grant select on table staging.saldo_contabil_empresa_mensal to authenticated;

-- O plano traz nome e código de toda conta do grupo; fica com diretor e financeiro, que são quem mapeia.
alter table staging.plano_conta enable row level security;
alter table staging.plano_conta force row level security;
create policy leitura_diretoria on staging.plano_conta for select to authenticated
  using (tenant_id = (select app.tenant_atual()) and (select app.perfil_atual()) in ('diretor', 'financeiro'));
create policy segundo_fator on staging.plano_conta as restrictive for all to authenticated
  using ((select app.segundo_fator_cumprido()));
revoke all on table staging.plano_conta from public, anon, authenticated;
grant select on table staging.plano_conta to authenticated;

-- Saldo do balancete com sinal: o ERP manda valor absoluto e o tipo D ou C.
create function staging.saldo_origem(p_saldo jsonb) returns numeric
language sql immutable set search_path = '' as $$
  select case when p_saldo ->> 'type' = 'C' then -1 else 1 end
         * coalesce(staging.numero_origem(p_saldo ->> 'value'), 0)
$$;

-- Recarrega empresa, vínculo obra-empresa, plano de contas e saldo mensal a partir do raw dos endpoints
-- companies, cost-centers e trial-balance. O carregador acrescenta initialPeriod e desconsiderClosingBalance
-- a cada registro do balancete; a chave de origem é (companyId, account, initialPeriod, desconsiderClosingBalance)
-- e vale o registro mais recente de cada chave. O mês de uma empresa só entra quando as duas passagens chegaram.
-- Upsert pela chave primária: repetir a carga não duplica e um registro novo no raw substitui o antigo.
-- O(n log n) nos registros do balancete pelo distinct on; uma instrução por tabela, sem laço.
create function staging.recarregar_contabil(p_tenant uuid) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_sem_empresa integer;
begin
  -- Mesma trava das outras recargas: duas ao mesmo tempo bateriam na chave primária.
  perform pg_advisory_xact_lock(hashtextextended('recarga:' || p_tenant::text, 0));

  insert into app.empresa (tenant_id, id_origem, nome, nome_fantasia)
  select p_tenant, v.id_origem, v.nome, v.nome_fantasia
  from (
    select distinct on ((r.payload ->> 'id')::integer)
      (r.payload ->> 'id')::integer as id_origem,
      coalesce(nullif(btrim(r.payload ->> 'name'), ''), 'Empresa ' || (r.payload ->> 'id')) as nome,
      nullif(btrim(r.payload ->> 'tradeName'), '') as nome_fantasia
    from raw.registro r
    where r.tenant_id = p_tenant and r.endpoint = 'companies' and r.payload ->> 'id' ~ '^\d{1,9}$'
    order by (r.payload ->> 'id')::integer, r.id desc
  ) v
  on conflict (tenant_id, id_origem) do update
    set nome = excluded.nome, nome_fantasia = excluded.nome_fantasia;

  update app.centro_custo cc
  set empresa_id = v.empresa_origem
  from (
    select distinct on ((r.payload ->> 'id')::integer)
      (r.payload ->> 'id')::integer as id_origem,
      (r.payload ->> 'idCompany')::integer as empresa_origem
    from raw.registro r
    where r.tenant_id = p_tenant and r.endpoint = 'cost-centers'
      and r.payload ->> 'id' ~ '^\d{1,9}$' and r.payload ->> 'idCompany' ~ '^\d{1,9}$'
    order by (r.payload ->> 'id')::integer, r.id desc
  ) v
  where cc.tenant_id = p_tenant and cc.id_origem = v.id_origem
    and cc.empresa_id is distinct from v.empresa_origem;

  select count(distinct (r.payload ->> 'companyId')::integer) into v_sem_empresa
  from raw.registro r
  where r.tenant_id = p_tenant and r.endpoint = 'trial-balance' and r.payload ->> 'companyId' ~ '^\d{1,9}$'
    and not exists (
      select 1 from app.empresa e
      where e.tenant_id = p_tenant and e.id_origem = (r.payload ->> 'companyId')::integer
    );
  if v_sem_empresa > 0 then
    raise notice '% empresas do balancete não estão em companies e ficaram fora', v_sem_empresa;
  end if;

  insert into staging.plano_conta (tenant_id, empresa_id, conta, conta_reduzida, nome, analitica, grupo)
  select p_tenant, e.id, v.conta,
    case when v.payload ->> 'reducedCode' ~ '^\d{1,9}$' then (v.payload ->> 'reducedCode')::integer end,
    coalesce(nullif(btrim(v.payload ->> 'accountName'), ''), v.conta),
    v.payload ->> 'accountType' = 'ANALYTICAL',
    case v.payload ->> 'accountGroup'
      when 'ASSETS' then 'ativo'
      when 'LIABILITIES' then 'passivo'
      when 'INCOME' then 'receita'
      when 'EXPENSES' then 'despesa'
      when 'TRANSITION' then 'transitoria'
    end
  from (
    select distinct on ((r.payload ->> 'companyId')::integer, r.payload ->> 'account')
      (r.payload ->> 'companyId')::integer as empresa_origem, r.payload ->> 'account' as conta, r.payload
    from raw.registro r
    where r.tenant_id = p_tenant and r.endpoint = 'trial-balance'
      and r.payload ->> 'companyId' ~ '^\d{1,9}$'
      and nullif(btrim(r.payload ->> 'account'), '') is not null
    order by (r.payload ->> 'companyId')::integer, r.payload ->> 'account', r.id desc
  ) v
  join app.empresa e on e.tenant_id = p_tenant and e.id_origem = v.empresa_origem
  on conflict (tenant_id, empresa_id, conta) do update
    set conta_reduzida = excluded.conta_reduzida, nome = excluded.nome,
        analitica = excluded.analitica, grupo = excluded.grupo;

  insert into staging.saldo_contabil_empresa_mensal
    (tenant_id, empresa_id, conta, competencia,
     saldo_anterior, debito, credito, saldo_final,
     saldo_anterior_sem_zeramento, debito_sem_zeramento, credito_sem_zeramento, saldo_final_sem_zeramento)
  with registro as (
    select distinct on (b.empresa_origem, b.conta, b.competencia, b.sem_zeramento)
      b.empresa_origem, b.conta, b.competencia, b.sem_zeramento, b.payload
    from (
      select (r.payload ->> 'companyId')::integer as empresa_origem,
        r.payload ->> 'account' as conta,
        date_trunc('month', staging.data_origem(r.payload ->> 'initialPeriod'))::date as competencia,
        lower(r.payload ->> 'desconsiderClosingBalance') = 'true' as sem_zeramento,
        r.id, r.payload
      from raw.registro r
      where r.tenant_id = p_tenant and r.endpoint = 'trial-balance'
        and r.payload ->> 'companyId' ~ '^\d{1,9}$'
        and nullif(btrim(r.payload ->> 'account'), '') is not null
        and staging.data_origem(r.payload ->> 'initialPeriod') is not null
        and lower(r.payload ->> 'desconsiderClosingBalance') in ('true', 'false')
    ) b
    order by b.empresa_origem, b.conta, b.competencia, b.sem_zeramento, b.id desc
  ), mes_completo as (
    select empresa_origem, competencia
    from registro
    group by empresa_origem, competencia
    having bool_or(sem_zeramento) and bool_or(not sem_zeramento)
  ), analitica as (
    select r.*
    from registro r
    join mes_completo m on m.empresa_origem = r.empresa_origem and m.competencia = r.competencia
    where r.payload ->> 'accountType' = 'ANALYTICAL'
  ), com as (
    select * from analitica where not sem_zeramento
  ), sem as (
    select * from analitica where sem_zeramento
  )
  select p_tenant, e.id,
    coalesce(c.conta, s.conta),
    coalesce(c.competencia, s.competencia),
    coalesce(staging.saldo_origem(c.payload -> 'balances' -> 'previous'), 0),
    coalesce(staging.numero_origem(c.payload ->> 'debit'), 0),
    coalesce(staging.numero_origem(c.payload ->> 'credit'), 0),
    coalesce(staging.saldo_origem(c.payload -> 'balances' -> 'current'), 0),
    coalesce(staging.saldo_origem(s.payload -> 'balances' -> 'previous'), 0),
    coalesce(staging.numero_origem(s.payload ->> 'debit'), 0),
    coalesce(staging.numero_origem(s.payload ->> 'credit'), 0),
    coalesce(staging.saldo_origem(s.payload -> 'balances' -> 'current'), 0)
  from com c
  full join sem s on s.empresa_origem = c.empresa_origem and s.conta = c.conta and s.competencia = c.competencia
  join app.empresa e on e.tenant_id = p_tenant and e.id_origem = coalesce(c.empresa_origem, s.empresa_origem)
  on conflict (tenant_id, empresa_id, conta, competencia) do update
    set saldo_anterior = excluded.saldo_anterior,
        debito = excluded.debito,
        credito = excluded.credito,
        saldo_final = excluded.saldo_final,
        saldo_anterior_sem_zeramento = excluded.saldo_anterior_sem_zeramento,
        debito_sem_zeramento = excluded.debito_sem_zeramento,
        credito_sem_zeramento = excluded.credito_sem_zeramento,
        saldo_final_sem_zeramento = excluded.saldo_final_sem_zeramento;
end $$;

revoke execute on function staging.saldo_origem(jsonb), staging.recarregar_contabil(uuid)
  from public, anon, authenticated;
