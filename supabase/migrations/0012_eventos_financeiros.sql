-- Staging por evento financeiro. A 0002 guardava só o primeiro recebimento de cada parcela, só a data
-- do primeiro pagamento de cada título e só a primeira obra do rateio; parcela paga em duas vezes,
-- título pago em duas vezes e título dividido entre obras perdiam parte do valor (ver docs/decisoes/0002).
-- As colunas de data se chamam data_recebimento e data_pagamento, e não "data", pela regra de nomes do CLAUDE.md.

create table staging.recebimento (
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  contrato_id_origem integer not null,
  parcela_id_origem integer not null,
  sequencia integer not null,
  data_recebimento date not null,
  valor numeric not null,
  primary key (tenant_id, centro_custo_id, contrato_id_origem, parcela_id_origem, sequencia)
);
create index on staging.recebimento (tenant_id, centro_custo_id, data_recebimento);

-- centro_custo_id só vem preenchido quando o título é de uma obra só; a divisão entre obras está no rateio.
create table staging.pagamento (
  tenant_id uuid not null,
  centro_custo_id uuid,
  titulo_id_origem integer not null,
  sequencia integer not null,
  data_pagamento date not null,
  valor numeric not null,
  primary key (tenant_id, titulo_id_origem, sequencia)
);
create index on staging.pagamento (tenant_id, centro_custo_id, data_pagamento);

-- fracao é gravada na carga porque o gerente de uma obra só enxerga a linha dela no rateio;
-- calcular a fração na view com sum() over daria 100% para quem vê uma linha só.
create table staging.rateio_titulo (
  tenant_id uuid not null,
  titulo_id_origem integer not null,
  centro_custo_id uuid not null,
  valor numeric not null,
  fracao numeric not null check (fracao >= 0 and fracao <= 1),
  primary key (tenant_id, titulo_id_origem, centro_custo_id)
);
create index on staging.rateio_titulo (tenant_id, centro_custo_id);

alter table staging.titulo_pagar alter column centro_custo_id drop not null;

do $$
declare t text;
begin
  foreach t in array array['recebimento', 'rateio_titulo'] loop
    execute format('alter table staging.%I enable row level security', t);
    execute format('alter table staging.%I force row level security', t);
    execute format($p$create policy leitura_por_obra on staging.%I for select to authenticated
      using (tenant_id = app.tenant_atual() and centro_custo_id in (select app.obras_permitidas()))$p$, t);
    execute format('grant select on staging.%I to authenticated', t);
  end loop;
end $$;

-- Título e pagamento aparecem para quem pode ver pelo menos uma obra do rateio. A política antiga do
-- título filtrava por centro_custo_id, que agora é nulo quando o título é dividido entre obras.
-- Título sem rateio (despesa da empresa) não aparece para ninguém pela API até existir a visão da empresa.
drop policy leitura_por_obra on staging.titulo_pagar;
create policy leitura_por_rateio on staging.titulo_pagar for select to authenticated
  using (
    tenant_id = app.tenant_atual()
    and exists (
      select 1 from staging.rateio_titulo rt
      where rt.tenant_id = titulo_pagar.tenant_id and rt.titulo_id_origem = titulo_pagar.id_origem
        and rt.centro_custo_id in (select app.obras_permitidas())
    )
  );

alter table staging.pagamento enable row level security;
alter table staging.pagamento force row level security;
create policy leitura_por_rateio on staging.pagamento for select to authenticated
  using (
    tenant_id = app.tenant_atual()
    and exists (
      select 1 from staging.rateio_titulo rt
      where rt.tenant_id = pagamento.tenant_id and rt.titulo_id_origem = pagamento.titulo_id_origem
        and rt.centro_custo_id in (select app.obras_permitidas())
    )
  );
grant select on staging.pagamento to authenticated;

-- Mesmo cabeçalho da 0002. Cada lista do payload vira uma linha por elemento, com a posição na lista
-- como sequência. Lista ausente ou que não seja array vira lista vazia, para um registro torto não
-- derrubar a carga inteira. O(n) em eventos, uma instrução por tabela, sem laço.
create or replace function staging.recarregar(p_tenant uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  titulos_sem_obra integer;
begin
  delete from staging.unidade where tenant_id = p_tenant;
  insert into staging.unidade
  select p_tenant, cc.id, (r.payload->>'id')::int, r.payload->>'name', r.payload->>'propertyType',
         (r.payload->>'privateArea')::numeric, r.payload->>'commercialStock', (r.payload->>'deliveryDate')::date
  from raw.registro r
  join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = (r.payload->>'enterpriseId')::int
  where r.tenant_id = p_tenant and r.endpoint = 'units';

  delete from staging.contrato_venda where tenant_id = p_tenant;
  insert into staging.contrato_venda
  select p_tenant, cc.id, (r.payload->>'id')::int, r.payload->>'number', (r.payload->>'contractDate')::date,
         (r.payload->>'value')::numeric, r.payload->>'situation', (r.payload->>'cancellationDate')::date,
         r.payload->>'financialInstitutionNumber', (r.payload->>'financialInstitutionDate')::date,
         r.payload->'customers'->0->>'name', (r.payload->'units'->0->>'id')::int
  from raw.registro r
  join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = (r.payload->>'enterpriseId')::int
  where r.tenant_id = p_tenant and r.endpoint = 'sales';

  -- data_recebimento e valor_recebido da parcela viram o último recebimento e a soma de todos;
  -- o valor de cada evento fica em staging.recebimento.
  delete from staging.parcela_receber where tenant_id = p_tenant;
  insert into staging.parcela_receber
    (tenant_id, centro_custo_id, id_origem, contrato_id_origem, vencimento, valor_original, saldo,
     saldo_corrigido, tipo_condicao, inadimplente, data_recebimento, valor_recebido)
  select p_tenant, cc.id, (r.payload->>'installmentId')::int, (r.payload->>'billId')::int,
         (r.payload->>'dueDate')::date, (r.payload->>'originalAmount')::numeric, (r.payload->>'balanceAmount')::numeric,
         (r.payload->>'correctedBalanceAmount')::numeric, r.payload->'paymentTerm'->>'id',
         r.payload->>'defaulterSituation' = 'S',
         rc.ultimo_recebimento, rc.total_recebido
  from raw.registro r
  join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = (r.payload->>'projectId')::int
  cross join lateral (
    select max((e->>'paymentDate')::date) as ultimo_recebimento, sum((e->>'amount')::numeric) as total_recebido
    from jsonb_array_elements(case when jsonb_typeof(r.payload->'receipts') = 'array'
                                   then r.payload->'receipts' else '[]'::jsonb end) e
  ) rc
  where r.tenant_id = p_tenant and r.endpoint = 'income';

  delete from staging.recebimento where tenant_id = p_tenant;
  insert into staging.recebimento
    (tenant_id, centro_custo_id, contrato_id_origem, parcela_id_origem, sequencia, data_recebimento, valor)
  select p_tenant, cc.id, (r.payload->>'billId')::int, (r.payload->>'installmentId')::int, rc.sequencia,
         (rc.evento->>'paymentDate')::date, (rc.evento->>'amount')::numeric
  from raw.registro r
  join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = (r.payload->>'projectId')::int
  cross join lateral jsonb_array_elements(case when jsonb_typeof(r.payload->'receipts') = 'array'
                                               then r.payload->'receipts' else '[]'::jsonb end)
    with ordinality as rc(evento, sequencia)
  where r.tenant_id = p_tenant and r.endpoint = 'income'
    and rc.evento->>'paymentDate' is not null and rc.evento->>'amount' is not null;

  delete from staging.pagamento where tenant_id = p_tenant;
  delete from staging.rateio_titulo where tenant_id = p_tenant;
  delete from staging.titulo_pagar where tenant_id = p_tenant;

  -- A fração divide pelo total apropriado no título, inclusive a parte de obra que não está em
  -- app.centro_custo; assim uma obra nunca recebe a parte de outra. Mesma obra repetida no payload é somada.
  insert into staging.rateio_titulo (tenant_id, titulo_id_origem, centro_custo_id, valor, fracao)
  with apropriacao as (
    select (r.payload->>'billId')::int as titulo_id_origem, (bc->>'buildingId')::int as obra_id_origem,
           (bc->>'amount')::numeric as valor,
           sum((bc->>'amount')::numeric) over (partition by r.id) as total_apropriado
    from raw.registro r
    cross join lateral jsonb_array_elements(case when jsonb_typeof(r.payload->'buildingsCosts') = 'array'
                                                 then r.payload->'buildingsCosts' else '[]'::jsonb end) bc
    where r.tenant_id = p_tenant and r.endpoint = 'outcome'
  )
  select p_tenant, a.titulo_id_origem, cc.id, sum(a.valor), sum(a.valor) / max(a.total_apropriado)
  from apropriacao a
  join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = a.obra_id_origem
  group by a.titulo_id_origem, cc.id
  having max(a.total_apropriado) > 0;

  -- data_pagamento do título vira a do último pagamento; o valor de cada um fica em staging.pagamento.
  insert into staging.titulo_pagar
    (tenant_id, centro_custo_id, id_origem, credor, vencimento, valor_original, saldo, data_pagamento)
  with obra_unica as (
    select titulo_id_origem, (array_agg(centro_custo_id))[1] as centro_custo_id
    from staging.rateio_titulo
    where tenant_id = p_tenant
    group by titulo_id_origem
    having count(*) = 1
  )
  select p_tenant, ou.centro_custo_id, (r.payload->>'billId')::int, r.payload->>'creditorName',
         (r.payload->>'dueDate')::date, (r.payload->>'originalAmount')::numeric,
         (r.payload->>'balanceAmount')::numeric, pg.ultimo_pagamento
  from raw.registro r
  left join obra_unica ou on ou.titulo_id_origem = (r.payload->>'billId')::int
  cross join lateral (
    select max((e->>'paymentDate')::date) as ultimo_pagamento
    from jsonb_array_elements(case when jsonb_typeof(r.payload->'payments') = 'array'
                                   then r.payload->'payments' else '[]'::jsonb end) e
  ) pg
  where r.tenant_id = p_tenant and r.endpoint = 'outcome';

  insert into staging.pagamento (tenant_id, centro_custo_id, titulo_id_origem, sequencia, data_pagamento, valor)
  select p_tenant, t.centro_custo_id, t.id_origem, pg.sequencia,
         (pg.evento->>'paymentDate')::date, (pg.evento->>'amount')::numeric
  from raw.registro r
  join staging.titulo_pagar t on t.tenant_id = p_tenant and t.id_origem = (r.payload->>'billId')::int
  cross join lateral jsonb_array_elements(case when jsonb_typeof(r.payload->'payments') = 'array'
                                               then r.payload->'payments' else '[]'::jsonb end)
    with ordinality as pg(evento, sequencia)
  where r.tenant_id = p_tenant and r.endpoint = 'outcome'
    and pg.evento->>'paymentDate' is not null and pg.evento->>'amount' is not null;

  select count(*) into titulos_sem_obra
  from staging.titulo_pagar t
  where t.tenant_id = p_tenant
    and not exists (
      select 1 from staging.rateio_titulo rt
      where rt.tenant_id = t.tenant_id and rt.titulo_id_origem = t.id_origem
    );
  raise notice '% títulos a pagar sem obra ficaram fora das views por obra', titulos_sem_obra;

  delete from staging.item_orcamento where tenant_id = p_tenant;
  insert into staging.item_orcamento
  select p_tenant, cc.id, r.payload->>'wbsCode', r.payload->>'description',
         (r.payload->>'totalPrice')::numeric, (r.payload->>'percentComplete')::numeric
  from raw.registro r
  join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = (r.payload->>'buildingId')::int
  where r.tenant_id = p_tenant and r.endpoint = 'building-cost-estimation-items';
end $$;

revoke execute on function staging.recarregar(uuid) from public, anon, authenticated;

-- Mesmas colunas, na mesma ordem e tipo, da 0005; o painel e posicao_financeira_obra não mudam.
-- Entrada realizada cai no mês de cada recebimento. Saída realizada cai no mês de cada pagamento,
-- multiplicada pela fração da obra no rateio; título sem rateio não entra em obra nenhuma.
-- Previsto e vencido seguem a regra da 0005, com a saída também distribuída pelo rateio.
-- A saída é arredondada em centavos por obra e mês; sem isso a fração do rateio deixa vinte casas decimais.
create or replace view marts.fluxo_caixa_mensal with (security_invoker = true) as
with movimento as (
  select rc.tenant_id, rc.centro_custo_id, date_trunc('month', rc.data_recebimento)::date as competencia,
         p.origem, 'entrada_realizada' as tipo, rc.valor
  from staging.recebimento rc
  join staging.parcela_receber p
    on p.tenant_id = rc.tenant_id and p.contrato_id_origem = rc.contrato_id_origem and p.id_origem = rc.parcela_id_origem
  union all
  select p.tenant_id, p.centro_custo_id, date_trunc('month', p.vencimento)::date, p.origem,
         case when p.vencimento < current_date then 'entrada_vencida' else 'entrada_prevista' end,
         coalesce(p.saldo_corrigido, p.saldo)
  from staging.parcela_receber p
  left join staging.contrato_venda c on c.tenant_id = p.tenant_id and c.id_origem = p.contrato_id_origem
  where coalesce(p.saldo_corrigido, p.saldo) > 0 and c.situacao is distinct from '3'
  union all
  select rt.tenant_id, rt.centro_custo_id, date_trunc('month', pg.data_pagamento)::date, null,
         'saida_realizada', pg.valor * rt.fracao
  from staging.pagamento pg
  join staging.rateio_titulo rt on rt.tenant_id = pg.tenant_id and rt.titulo_id_origem = pg.titulo_id_origem
  union all
  select rt.tenant_id, rt.centro_custo_id, date_trunc('month', t.vencimento)::date, null,
         case when t.vencimento < current_date then 'saida_vencida' else 'saida_prevista' end, t.saldo * rt.fracao
  from staging.titulo_pagar t
  join staging.rateio_titulo rt on rt.tenant_id = t.tenant_id and rt.titulo_id_origem = t.id_origem
  where t.saldo > 0
), mensal as (
  select tenant_id, centro_custo_id, competencia,
    coalesce(sum(valor) filter (where tipo = 'entrada_realizada' and origem = 'direta'), 0) as entrada_direta_realizada,
    coalesce(sum(valor) filter (where tipo = 'entrada_realizada' and origem = 'repasse'), 0) as repasse_realizado,
    coalesce(sum(valor) filter (where tipo = 'entrada_prevista' and origem = 'direta'), 0) as entrada_direta_prevista,
    coalesce(sum(valor) filter (where tipo = 'entrada_prevista' and origem = 'repasse'), 0) as repasse_previsto,
    coalesce(sum(valor) filter (where tipo = 'entrada_vencida' and origem = 'direta'), 0) as entrada_direta_vencida,
    coalesce(sum(valor) filter (where tipo = 'entrada_vencida' and origem = 'repasse'), 0) as repasse_vencido,
    round(coalesce(sum(valor) filter (where tipo = 'saida_realizada'), 0), 2) as saida_realizada,
    round(coalesce(sum(valor) filter (where tipo = 'saida_prevista'), 0), 2) as saida_prevista,
    round(coalesce(sum(valor) filter (where tipo = 'saida_vencida'), 0), 2) as saida_vencida
  from movimento
  group by 1, 2, 3
)
select m.*,
  m.entrada_direta_realizada + m.repasse_realizado + m.entrada_direta_prevista + m.repasse_previsto
    - m.saida_realizada - m.saida_prevista - m.saida_vencida as saldo_mes,
  sum(m.entrada_direta_realizada + m.repasse_realizado + m.entrada_direta_prevista + m.repasse_previsto
      - m.saida_realizada - m.saida_prevista - m.saida_vencida)
    over (partition by m.tenant_id, m.centro_custo_id order by m.competencia) as saldo_acumulado
from mensal m;
