-- Planejamento: metas e fotografias da projeção em versões que não se alteram, premissa de meses para o
-- custo sem título, fluxo projetado por obra e simulação que não grava.
-- Contrato: docs/financeiro/contrato_dados.md, seções 3.4 e 4. Decisão: docs/decisoes/0007-planejamento-versoes.md.
-- Lê o staging da 0007 e as tabelas e views da 0012; não depende da 0011.

create table app.versao_planejamento (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  tipo text not null check (tipo in ('meta', 'projecao')),
  numero integer not null check (numero >= 1),
  descricao text not null check (btrim(descricao) <> ''),
  data_referencia date not null,
  premissas jsonb not null default '{}'::jsonb,
  autor uuid not null,
  criada_em timestamptz not null default now(),
  unique (tenant_id, centro_custo_id, tipo, numero)
);

create table app.meta_mensal (
  versao_id uuid not null references app.versao_planejamento on delete restrict,
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  competencia date not null check (competencia = date_trunc('month', competencia)::date),
  unidades integer check (unidades >= 0),
  valor_contratado numeric(18,2) check (valor_contratado >= 0),
  fracao_financiada numeric(9,6) check (fracao_financiada >= 0 and fracao_financiada <= 1),
  recebimento_esperado numeric(18,2) check (recebimento_esperado >= 0),
  limite_aporte_proprio numeric(18,2) check (limite_aporte_proprio >= 0),
  primary key (versao_id, competencia)
);
create index meta_mensal_obra on app.meta_mensal (tenant_id, centro_custo_id);

create table app.projecao_mensal (
  versao_id uuid not null references app.versao_planejamento on delete restrict,
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  competencia date not null check (competencia = date_trunc('month', competencia)::date),
  recebido_direto numeric(18,2) not null,
  recebido_financiamento numeric(18,2) not null,
  credito_producao_recebido numeric(18,2) not null,
  previsto_direto numeric(18,2) not null,
  previsto_financiamento_elegivel numeric(18,2) not null,
  previsto_financiamento_pendente numeric(18,2) not null,
  credito_producao_previsto numeric(18,2) not null,
  vencido_a_receber numeric(18,2) not null,
  pago numeric(18,2) not null,
  a_pagar numeric(18,2) not null,
  a_pagar_vencido numeric(18,2) not null,
  custo_sem_titulo_distribuido numeric(18,2) not null,
  total_entradas numeric(18,2) not null,
  total_saidas numeric(18,2) not null,
  saldo_mes numeric(18,2) not null,
  caixa_gerado_acumulado numeric(18,2) not null,
  necessidade_aporte_acumulada numeric(18,2) not null,
  aporte_incremental_mes numeric(18,2) not null,
  caixa_gerado_acumulado_conservador numeric(18,2) not null,
  necessidade_aporte_conservadora numeric(18,2) not null,
  primary key (versao_id, competencia)
);
create index projecao_mensal_obra on app.projecao_mensal (tenant_id, centro_custo_id);

create table app.premissa_distribuicao_custo (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  metodo text not null default 'fracao_mensal' check (metodo in ('fracao_mensal')),
  fonte text not null check (btrim(fonte) <> ''),
  observacao text,
  autor uuid not null,
  criada_em timestamptz not null default now()
);
create index premissa_distribuicao_custo_vigente
  on app.premissa_distribuicao_custo (tenant_id, centro_custo_id, criada_em desc, id desc);

create table app.premissa_distribuicao_custo_mes (
  premissa_id uuid not null references app.premissa_distribuicao_custo on delete restrict,
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  competencia date not null check (competencia = date_trunc('month', competencia)::date),
  fracao numeric(9,6) not null check (fracao > 0 and fracao <= 1),
  primary key (premissa_id, competencia)
);
create index premissa_distribuicao_custo_mes_obra on app.premissa_distribuicao_custo_mes (tenant_id, centro_custo_id);

-- Número, data de referência e hora vêm do banco, nunca do cliente. A hora é a do relógio, não a do
-- início da transação, para duas premissas gravadas na mesma transação terem ordem. O lock por obra e
-- tipo serializa duas gravações simultâneas, que de outro modo pegariam o mesmo número.
create function app.preparar_versao() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(new.tenant_id::text || new.centro_custo_id::text || new.tipo, 0));
  select coalesce(max(v.numero), 0) + 1 into new.numero
  from app.versao_planejamento v
  where v.tenant_id = new.tenant_id and v.centro_custo_id = new.centro_custo_id and v.tipo = new.tipo;
  new.data_referencia := app.data_referencia();
  new.criada_em := clock_timestamp();
  return new;
end $$;
revoke execute on function app.preparar_versao() from public, anon, authenticated;

create function app.preparar_premissa() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  new.criada_em := clock_timestamp();
  return new;
end $$;
revoke execute on function app.preparar_premissa() from public, anon, authenticated;

-- Linha filha só entra em versão (ou premissa) criada na transação corrente: versão de transação já
-- encerrada tem hora anterior ao início desta e não ganha linha nova. TG_ARGV[0] é o tipo de versão
-- exigido; vazio para premissa.
create function app.validar_linha_versao() returns trigger
language plpgsql security invoker set search_path = '' as $$
declare
  v_tenant uuid;
  v_centro uuid;
  v_tipo text;
  v_criada timestamptz;
begin
  if tg_table_name = 'premissa_distribuicao_custo_mes' then
    select p.tenant_id, p.centro_custo_id, '', p.criada_em into v_tenant, v_centro, v_tipo, v_criada
    from app.premissa_distribuicao_custo p where p.id = new.premissa_id;
  else
    select v.tenant_id, v.centro_custo_id, v.tipo, v.criada_em into v_tenant, v_centro, v_tipo, v_criada
    from app.versao_planejamento v where v.id = new.versao_id;
  end if;
  if not found or v_tenant <> new.tenant_id or v_centro <> new.centro_custo_id or v_tipo <> tg_argv[0] then
    raise exception 'linha não corresponde à versão' using errcode = '23514';
  end if;
  if v_criada < now() then
    raise exception 'versão já registrada não recebe linhas novas' using errcode = '23514';
  end if;
  return new;
end $$;
revoke execute on function app.validar_linha_versao() from public, anon, authenticated;

-- Vale também para o dono do banco: versão registrada nunca muda nem some.
create function app.bloquear_alteracao_versao() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  raise exception 'versão registrada não pode ser alterada nem apagada' using errcode = '42501';
end $$;
revoke execute on function app.bloquear_alteracao_versao() from public, anon, authenticated;

create trigger definir_autor before insert on app.versao_planejamento
  for each row execute function app.definir_autor();
create trigger preparar_versao before insert on app.versao_planejamento
  for each row execute function app.preparar_versao();
create trigger registrar_auditoria after insert on app.versao_planejamento
  for each row execute function app.registrar_auditoria('id');
create trigger definir_autor before insert on app.premissa_distribuicao_custo
  for each row execute function app.definir_autor();
create trigger preparar_premissa before insert on app.premissa_distribuicao_custo
  for each row execute function app.preparar_premissa();
create trigger registrar_auditoria after insert on app.premissa_distribuicao_custo
  for each row execute function app.registrar_auditoria('id');
create trigger validar_linha before insert on app.meta_mensal
  for each row execute function app.validar_linha_versao('meta');
create trigger validar_linha before insert on app.projecao_mensal
  for each row execute function app.validar_linha_versao('projecao');
create trigger validar_linha before insert on app.premissa_distribuicao_custo_mes
  for each row execute function app.validar_linha_versao('');

do $$
declare t text;
begin
  foreach t in array array['versao_planejamento', 'meta_mensal', 'projecao_mensal', 'premissa_distribuicao_custo',
                           'premissa_distribuicao_custo_mes'] loop
    execute format('create trigger bloquear_alteracao before update or delete on app.%I
      for each row execute function app.bloquear_alteracao_versao()', t);
    execute format('alter table app.%I enable row level security', t);
    execute format('alter table app.%I force row level security', t);
    execute format($p$create policy leitura_por_obra on app.%I for select to authenticated
      using (tenant_id = (select app.tenant_atual()) and centro_custo_id in (select app.obras_permitidas()))$p$, t);
    execute format($p$create policy inclusao_diretor_financeiro on app.%I for insert to authenticated
      with check (tenant_id = (select app.tenant_atual()) and centro_custo_id in (select app.obras_permitidas())
                  and (select app.perfil_atual()) in ('diretor', 'financeiro'))$p$, t);
    execute format('grant select, insert on app.%I to authenticated', t);
  end loop;
end $$;

-- Leitura das premissas em jsonb. Tipo errado vira erro 22023 com o nome do campo, que o painel traduz.
create function app.premissa_numero(p_valor jsonb, p_campo text) returns numeric
language plpgsql immutable security invoker set search_path = '' as $$
begin
  if p_valor is null or jsonb_typeof(p_valor) = 'null' then
    return null;
  end if;
  if jsonb_typeof(p_valor) <> 'number' then
    raise exception 'premissa inválida: %', p_campo using errcode = '22023';
  end if;
  return (p_valor #>> '{}')::numeric;
end $$;

-- p_padrao nulo torna o campo obrigatório; p_maximo limita meses para o horizonte não explodir.
create function app.premissa_inteiro(p_valor jsonb, p_campo text, p_padrao integer, p_maximo integer) returns integer
language plpgsql immutable security invoker set search_path = '' as $$
declare
  v numeric := app.premissa_numero(p_valor, p_campo);
begin
  if v is null then
    if p_padrao is null then
      raise exception 'premissa inválida: %', p_campo using errcode = '22023';
    end if;
    return p_padrao;
  end if;
  if v <> trunc(v) or v < 0 or v > coalesce(p_maximo, 2147483647) then
    raise exception 'premissa inválida: %', p_campo using errcode = '22023';
  end if;
  return v::integer;
end $$;

create function app.premissa_competencia(p_valor jsonb, p_campo text) returns date
language plpgsql immutable security invoker set search_path = '' as $$
declare
  v date;
begin
  if p_valor is null or jsonb_typeof(p_valor) <> 'string' or (p_valor #>> '{}') !~ '^\d{4}-\d{2}-\d{2}$' then
    raise exception 'premissa inválida: %', p_campo using errcode = '22023';
  end if;
  begin
    v := (p_valor #>> '{}')::date;
  exception when others then
    raise exception 'premissa inválida: %', p_campo using errcode = '22023';
  end;
  if v <> date_trunc('month', v)::date then
    raise exception 'premissa inválida: %', p_campo using errcode = '22023';
  end if;
  return v;
end $$;

revoke execute on function app.premissa_numero(jsonb, text), app.premissa_inteiro(jsonb, text, integer, integer),
  app.premissa_competencia(jsonb, text) from public, anon;
grant execute on function app.premissa_numero(jsonb, text), app.premissa_inteiro(jsonb, text, integer, integer),
  app.premissa_competencia(jsonb, text) to authenticated;

-- Custo sem título por obra: quanto falta lançar do orçamento e se há premissa válida para repartir.
-- Mesma conta de posicao_financeira_obra.custo_a_incorrer, sem passar pelo mapa de unidades.
create view app.custo_sem_titulo_obra with (security_invoker = true) as
with orcamento as (
  select tenant_id, centro_custo_id, sum(valor_total) as orcado
  from staging.item_orcamento
  group by 1, 2
), lancado as (
  select tenant_id, centro_custo_id, sum(valor_original) as lancado
  from staging.titulo_pagar_apropriacao
  group by 1, 2
), premissa as (
  select distinct on (p.tenant_id, p.centro_custo_id) p.tenant_id, p.centro_custo_id, p.id
  from app.premissa_distribuicao_custo p
  order by p.tenant_id, p.centro_custo_id, p.criada_em desc, p.id desc
), soma as (
  select m.premissa_id, sum(m.fracao) as total
  from app.premissa_distribuicao_custo_mes m
  group by 1
)
select cc.tenant_id, cc.id as centro_custo_id,
  case when o.centro_custo_id is not null then greatest(o.orcado - coalesce(l.lancado, 0), 0) end
    as custo_sem_titulo_total,
  case when o.centro_custo_id is not null and s.total = 1 then p.id end as premissa_distribuicao_id,
  case
    when o.centro_custo_id is null then 'orcamento_ausente'
    when p.id is null then 'sem_premissa_distribuicao'
    when s.total is distinct from 1 then 'premissa_invalida'
  end as motivo_distribuicao
from app.centro_custo cc
left join orcamento o on o.tenant_id = cc.tenant_id and o.centro_custo_id = cc.id
left join lancado l on l.tenant_id = cc.tenant_id and l.centro_custo_id = cc.id
left join premissa p on p.tenant_id = cc.tenant_id and p.centro_custo_id = cc.id
left join soma s on s.premissa_id = p.id
where cc.tipo = 'obra';

-- Repartição mensal pela premissa vigente. Mês passado da premissa soma no mês corrente (pergunta P11);
-- o resíduo de centavo vai para o mês de maior fração, empate no mais cedo.
create view app.custo_sem_titulo_mensal with (security_invoker = true) as
with referencia as materialized (
  select date_trunc('month', app.data_referencia())::date as mes_ref
), mes as (
  select o.tenant_id, o.centro_custo_id, o.custo_sem_titulo_total as total,
         greatest(m.competencia, r.mes_ref) as competencia, sum(m.fracao) as fracao
  from app.custo_sem_titulo_obra o
  join app.premissa_distribuicao_custo_mes m on m.premissa_id = o.premissa_distribuicao_id
  cross join referencia r
  where o.custo_sem_titulo_total > 0
  group by 1, 2, 3, 4
), arredondado as (
  select mes.*, round(mes.total * mes.fracao, 2) as parte,
         row_number() over (partition by mes.tenant_id, mes.centro_custo_id order by mes.fracao desc, mes.competencia) = 1
           as principal,
         sum(round(mes.total * mes.fracao, 2)) over (partition by mes.tenant_id, mes.centro_custo_id) as soma_partes
  from mes
)
select a.tenant_id, a.centro_custo_id, a.competencia,
  (case when a.principal then a.parte + a.total - a.soma_partes else a.parte end)::numeric(18,2) as valor
from arredondado a;

-- Versões usadas nas comparações. Original: a primeira projeção registrada no mês de referência; sem
-- nenhuma no mês, a última dos meses anteriores. Meta vigente: a última versão de meta.
create view app.versao_referencia_obra with (security_invoker = true) as
with referencia as materialized (
  select date_trunc('month', app.data_referencia())::date as mes_ref
), original as (
  select distinct on (v.tenant_id, v.centro_custo_id) v.tenant_id, v.centro_custo_id, v.id, v.numero
  from app.versao_planejamento v
  cross join referencia r
  where v.tipo = 'projecao' and v.data_referencia < r.mes_ref + interval '1 month'
  order by v.tenant_id, v.centro_custo_id, (v.data_referencia >= r.mes_ref) desc,
           case when v.data_referencia >= r.mes_ref then v.numero else -v.numero end
), meta as (
  select distinct on (v.tenant_id, v.centro_custo_id) v.tenant_id, v.centro_custo_id, v.id, v.numero
  from app.versao_planejamento v
  where v.tipo = 'meta'
  order by v.tenant_id, v.centro_custo_id, v.numero desc
)
select coalesce(o.tenant_id, m.tenant_id) as tenant_id, coalesce(o.centro_custo_id, m.centro_custo_id) as centro_custo_id,
  o.id as versao_original_id, o.numero as versao_original_numero, m.id as versao_meta_id, m.numero as versao_meta_numero
from original o
full join meta m on m.tenant_id = o.tenant_id and m.centro_custo_id = o.centro_custo_id;

grant select on app.custo_sem_titulo_obra, app.custo_sem_titulo_mensal, app.versao_referencia_obra to authenticated;

-- Meses de p_inicio a p_fim. Existe para declarar a estimativa: generate_series direto numa junção lateral
-- é estimado em mil linhas por chamada, o custo do plano passa do limite do JIT e a compilação custa mais
-- que a consulta.
create function app.meses_entre(p_inicio date, p_fim date) returns setof date
language sql immutable security invoker set search_path = '' rows 2 as $$
  select g::date from generate_series(p_inicio, p_fim, interval '1 month') as g
$$;
revoke execute on function app.meses_entre(date, date) from public, anon;
grant execute on function app.meses_entre(date, date) to authenticated;

-- Fluxo por obra e mês: o realizado pelo dia do dinheiro e o previsto pela data esperada. Entrada vencida
-- fica fora do saldo (informativa em vencido_a_receber); saída vencida entra no mês de referência.
-- O acumulado é caixa gerado pela obra, não saldo bancário.
-- Uma passada só pelos eventos: agrupa por obra e mês e preenche os meses sem movimento até o próximo
-- mês com movimento, então o filtro por obra chega até as tabelas. O(eventos + meses).
create view marts.fluxo_projetado_mensal with (security_invoker = true) as
with referencia as materialized (
  select app.data_referencia() as ref, date_trunc('month', app.data_referencia())::date as mes_ref
), movimento as (
  select r.tenant_id, r.centro_custo_id, date_trunc('month', r.data_recebimento)::date as competencia,
         case when r.origem = 'repasse' then 'recebido_financiamento' else 'recebido_direto' end as tipo,
         r.valor
  from staging.recebimento r
  where r.tipo_baixa in ('recebimento', 'estorno')
  union all
  -- só o crédito à produção lançado à mão soma; ligado a recebimento, o dinheiro já está acima
  select l.tenant_id, l.centro_custo_id, date_trunc('month', l.data_recebimento)::date, 'credito_producao_recebido',
         l.valor_recebido
  from app.liberacao_financiamento l
  where l.situacao = 'recebida' and l.nivel in ('empreendimento', 'lote') and l.vinculo_tipo = 'lancamento_manual'
  union all
  select l.tenant_id, l.centro_custo_id, date_trunc('month', l.data_prevista)::date, 'credito_producao_previsto',
         l.valor_previsto
  from app.liberacao_financiamento l
  cross join referencia ref
  where l.situacao = 'prevista' and l.nivel in ('empreendimento', 'lote') and l.data_prevista >= ref.ref
  union all
  select rp.tenant_id, rp.centro_custo_id,
         case when rp.incluida_projecao then date_trunc('month', rp.data_prevista)::date else ref.mes_ref end,
         case when not rp.incluida_projecao then 'vencido_a_receber'
              when rp.classe = 'direta' then 'previsto_direto'
              when rp.classe = 'financiamento_elegivel' then 'previsto_financiamento_elegivel'
              else 'previsto_financiamento_pendente' end,
         rp.saldo
  from marts.recebivel_projetado rp
  cross join referencia ref
  union all
  select pg.tenant_id, pg.centro_custo_id, date_trunc('month', pg.data_pagamento)::date, 'pago', pg.valor
  from staging.pagamento pg
  union all
  select a.tenant_id, a.centro_custo_id,
         case when a.vencimento >= ref.ref then date_trunc('month', a.vencimento)::date else ref.mes_ref end,
         case when a.vencimento >= ref.ref then 'a_pagar' else 'a_pagar_vencido' end,
         a.saldo
  from staging.titulo_pagar_apropriacao a
  cross join referencia ref
  where a.saldo > 0
  union all
  select d.tenant_id, d.centro_custo_id, d.competencia, 'custo_sem_titulo_distribuido', d.valor
  from app.custo_sem_titulo_mensal d
  union all
  -- o mês de referência existe para toda obra, mesmo sem movimento
  select cc.tenant_id, cc.id, ref.mes_ref, 'calendario', 0
  from app.centro_custo cc
  cross join referencia ref
  where cc.tipo = 'obra'
), mensal as (
  select m.tenant_id, m.centro_custo_id, m.competencia,
    coalesce(sum(m.valor) filter (where m.tipo = 'recebido_direto'), 0) as recebido_direto,
    coalesce(sum(m.valor) filter (where m.tipo = 'recebido_financiamento'), 0) as recebido_financiamento,
    coalesce(sum(m.valor) filter (where m.tipo = 'credito_producao_recebido'), 0) as credito_producao_recebido,
    coalesce(sum(m.valor) filter (where m.tipo = 'previsto_direto'), 0) as previsto_direto,
    coalesce(sum(m.valor) filter (where m.tipo = 'previsto_financiamento_elegivel'), 0) as previsto_financiamento_elegivel,
    coalesce(sum(m.valor) filter (where m.tipo = 'previsto_financiamento_pendente'), 0) as previsto_financiamento_pendente,
    coalesce(sum(m.valor) filter (where m.tipo = 'credito_producao_previsto'), 0) as credito_producao_previsto,
    coalesce(sum(m.valor) filter (where m.tipo = 'vencido_a_receber'), 0) as vencido_a_receber,
    coalesce(sum(m.valor) filter (where m.tipo = 'pago'), 0) as pago,
    coalesce(sum(m.valor) filter (where m.tipo = 'a_pagar'), 0) as a_pagar,
    coalesce(sum(m.valor) filter (where m.tipo = 'a_pagar_vencido'), 0) as a_pagar_vencido,
    coalesce(sum(m.valor) filter (where m.tipo = 'custo_sem_titulo_distribuido'), 0) as custo_sem_titulo_distribuido
  from movimento m
  where m.centro_custo_id in (select cc.id from app.centro_custo cc where cc.tipo = 'obra')
  group by 1, 2, 3
), com_proximo as (
  select me.*, lead(me.competencia) over (partition by me.tenant_id, me.centro_custo_id order by me.competencia) as proximo
  from mensal me
), linha as (
  select c.tenant_id, c.centro_custo_id, g.competencia::date as competencia, g.competencia < ref.mes_ref as eh_passado,
    case when g.competencia = c.competencia then c.recebido_direto else 0 end as recebido_direto,
    case when g.competencia = c.competencia then c.recebido_financiamento else 0 end as recebido_financiamento,
    case when g.competencia = c.competencia then c.credito_producao_recebido else 0 end as credito_producao_recebido,
    case when g.competencia = c.competencia then c.previsto_direto else 0 end as previsto_direto,
    case when g.competencia = c.competencia then c.previsto_financiamento_elegivel else 0 end as previsto_financiamento_elegivel,
    case when g.competencia = c.competencia then c.previsto_financiamento_pendente else 0 end as previsto_financiamento_pendente,
    case when g.competencia = c.competencia then c.credito_producao_previsto else 0 end as credito_producao_previsto,
    case when g.competencia = c.competencia then c.vencido_a_receber else 0 end as vencido_a_receber,
    case when g.competencia = c.competencia then c.pago else 0 end as pago,
    case when g.competencia = c.competencia then c.a_pagar else 0 end as a_pagar,
    case when g.competencia = c.competencia then c.a_pagar_vencido else 0 end as a_pagar_vencido,
    case when g.competencia = c.competencia then c.custo_sem_titulo_distribuido else 0 end as custo_sem_titulo_distribuido
  from com_proximo c
  cross join referencia ref
  cross join lateral app.meses_entre(c.competencia, coalesce((c.proximo - interval '1 month')::date, c.competencia))
    as g(competencia)
), saldo as (
  select li.*,
    li.recebido_direto + li.recebido_financiamento + li.credito_producao_recebido + li.previsto_direto
      + li.previsto_financiamento_elegivel + li.previsto_financiamento_pendente + li.credito_producao_previsto
      as total_entradas,
    li.pago + li.a_pagar + li.a_pagar_vencido + li.custo_sem_titulo_distribuido as total_saidas
  from linha li
), acumulado as (
  select s.*, s.total_entradas - s.total_saidas as saldo_mes,
    sum(s.total_entradas - s.total_saidas) over w as caixa_gerado_acumulado,
    sum(s.total_entradas - s.total_saidas - s.previsto_financiamento_pendente) over w as caixa_gerado_acumulado_conservador
  from saldo s
  window w as (partition by s.tenant_id, s.centro_custo_id order by s.competencia)
)
select a.tenant_id, a.centro_custo_id, a.competencia, a.eh_passado,
  a.recebido_direto::numeric(18,2) as recebido_direto,
  a.recebido_financiamento::numeric(18,2) as recebido_financiamento,
  a.credito_producao_recebido::numeric(18,2) as credito_producao_recebido,
  a.previsto_direto::numeric(18,2) as previsto_direto,
  a.previsto_financiamento_elegivel::numeric(18,2) as previsto_financiamento_elegivel,
  a.previsto_financiamento_pendente::numeric(18,2) as previsto_financiamento_pendente,
  a.credito_producao_previsto::numeric(18,2) as credito_producao_previsto,
  a.vencido_a_receber::numeric(18,2) as vencido_a_receber,
  a.pago::numeric(18,2) as pago,
  a.a_pagar::numeric(18,2) as a_pagar,
  a.a_pagar_vencido::numeric(18,2) as a_pagar_vencido,
  a.custo_sem_titulo_distribuido::numeric(18,2) as custo_sem_titulo_distribuido,
  a.total_entradas::numeric(18,2) as total_entradas,
  a.total_saidas::numeric(18,2) as total_saidas,
  a.saldo_mes::numeric(18,2) as saldo_mes,
  a.caixa_gerado_acumulado::numeric(18,2) as caixa_gerado_acumulado,
  greatest(-a.caixa_gerado_acumulado, 0)::numeric(18,2) as necessidade_aporte_acumulada,
  greatest(greatest(-a.caixa_gerado_acumulado, 0)
           - coalesce(lag(greatest(-a.caixa_gerado_acumulado, 0))
                        over (partition by a.tenant_id, a.centro_custo_id order by a.competencia), 0), 0)::numeric(18,2)
    as aporte_incremental_mes,
  a.caixa_gerado_acumulado_conservador::numeric(18,2) as caixa_gerado_acumulado_conservador,
  greatest(-a.caixa_gerado_acumulado_conservador, 0)::numeric(18,2) as necessidade_aporte_conservadora
from acumulado a;

create view marts.resumo_projecao_obra with (security_invoker = true) as
with pico as (
  select f.tenant_id, f.centro_custo_id, f.competencia, f.necessidade_aporte_acumulada,
         max(f.necessidade_aporte_acumulada) over (partition by f.tenant_id, f.centro_custo_id) as maximo,
         f.necessidade_aporte_conservadora, f.custo_sem_titulo_distribuido, f.vencido_a_receber, f.a_pagar_vencido,
         f.previsto_financiamento_pendente
  from marts.fluxo_projetado_mensal f
), agregado as (
  select p.tenant_id, p.centro_custo_id,
         max(p.maximo) as exposicao_maxima_projetada,
         min(p.competencia) filter (where p.necessidade_aporte_acumulada = p.maximo and p.maximo > 0) as mes_exposicao_maxima,
         max(p.necessidade_aporte_conservadora) as exposicao_maxima_conservadora,
         sum(p.custo_sem_titulo_distribuido) as distribuido,
         sum(p.vencido_a_receber) as vencido_a_receber,
         sum(p.a_pagar_vencido) as a_pagar_vencido,
         sum(p.previsto_financiamento_pendente) as financiamento_pendente_total
  from pico p
  group by 1, 2
)
select cc.tenant_id, cc.id as centro_custo_id, cc.nome as obra, app.data_referencia() as data_referencia,
  a.exposicao_maxima_projetada, a.mes_exposicao_maxima, a.exposicao_maxima_conservadora,
  c.custo_sem_titulo_total::numeric(18,2) as custo_sem_titulo_total,
  a.distribuido::numeric(18,2) as custo_sem_titulo_distribuido_total,
  (c.custo_sem_titulo_total - a.distribuido)::numeric(18,2) as custo_sem_titulo_nao_distribuido,
  c.premissa_distribuicao_id, c.motivo_distribuicao,
  c.custo_sem_titulo_total is null or c.custo_sem_titulo_total - a.distribuido > 0 as exposicao_parcial,
  a.vencido_a_receber::numeric(18,2) as vencido_a_receber,
  a.a_pagar_vencido::numeric(18,2) as a_pagar_vencido,
  a.financiamento_pendente_total::numeric(18,2) as financiamento_pendente_total
from agregado a
join app.centro_custo cc on cc.tenant_id = a.tenant_id and cc.id = a.centro_custo_id
left join app.custo_sem_titulo_obra c on c.tenant_id = a.tenant_id and c.centro_custo_id = a.centro_custo_id;

-- Original contra atual mês a mês. O acumulado de cada lado corre sobre o calendário unido, então num mês
-- que só um dos lados tem o outro repete o último acumulado.
create view marts.comparativo_projecao with (security_invoker = true) as
with referencia as materialized (
  select date_trunc('month', app.data_referencia())::date as mes_ref
), atual as (
  select f.tenant_id, f.centro_custo_id, f.competencia, f.total_entradas, f.total_saidas, f.saldo_mes,
         f.recebido_direto + f.recebido_financiamento + f.credito_producao_recebido as realizado_entradas,
         f.pago as realizado_saidas
  from marts.fluxo_projetado_mensal f
), original as (
  select v.tenant_id, v.centro_custo_id, p.competencia, p.total_entradas, p.total_saidas, p.saldo_mes
  from app.versao_referencia_obra v
  join app.projecao_mensal p on p.versao_id = v.versao_original_id
), juncao as (
  select coalesce(a.tenant_id, o.tenant_id) as tenant_id, coalesce(a.centro_custo_id, o.centro_custo_id) as centro_custo_id,
         coalesce(a.competencia, o.competencia) as competencia,
         a.total_entradas as atual_entradas, a.total_saidas as atual_saidas, a.saldo_mes as atual_saldo,
         a.realizado_entradas, a.realizado_saidas,
         o.total_entradas as original_entradas, o.total_saidas as original_saidas, o.saldo_mes as original_saldo
  from atual a
  full join original o on o.tenant_id = a.tenant_id and o.centro_custo_id = a.centro_custo_id
                      and o.competencia = a.competencia
), acumulado as (
  select j.*, v.versao_original_id, v.versao_original_numero,
         sum(coalesce(j.atual_saldo, 0)) over w as atual_caixa,
         sum(coalesce(j.original_saldo, 0)) over w as original_caixa
  from juncao j
  left join app.versao_referencia_obra v on v.tenant_id = j.tenant_id and v.centro_custo_id = j.centro_custo_id
  window w as (partition by j.tenant_id, j.centro_custo_id order by j.competencia)
)
select a.tenant_id, a.centro_custo_id, a.competencia, a.versao_original_id, a.versao_original_numero,
  case when a.versao_original_id is not null then coalesce(a.original_entradas, 0) end::numeric(18,2) as original_total_entradas,
  case when a.versao_original_id is not null then coalesce(a.original_saidas, 0) end::numeric(18,2) as original_total_saidas,
  case when a.versao_original_id is not null then a.original_caixa end::numeric(18,2) as original_caixa_gerado_acumulado,
  coalesce(a.atual_entradas, 0)::numeric(18,2) as atual_total_entradas,
  coalesce(a.atual_saidas, 0)::numeric(18,2) as atual_total_saidas,
  a.atual_caixa::numeric(18,2) as atual_caixa_gerado_acumulado,
  case when a.competencia <= r.mes_ref then coalesce(a.realizado_entradas, 0) end::numeric(18,2) as realizado_entradas,
  case when a.competencia <= r.mes_ref then coalesce(a.realizado_saidas, 0) end::numeric(18,2) as realizado_saidas,
  case when a.versao_original_id is not null then a.atual_caixa - a.original_caixa end::numeric(18,2)
    as diferenca_caixa_acumulado
from acumulado a
cross join referencia r;

-- Causas de desvio só quando o dado sustenta; mês sem causa comprovada não ganha linha.
create view marts.explicacao_desvio with (security_invoker = true) as
with referencia as materialized (
  select app.data_referencia() as ref, date_trunc('month', app.data_referencia())::date as mes_ref
), obra as (
  select cc.tenant_id, cc.id as centro_custo_id from app.centro_custo cc where cc.tipo = 'obra'
), venda as (
  select c.tenant_id, c.centro_custo_id, date_trunc('month', c.data_venda)::date as competencia,
         count(*) as unidades, sum(c.valor) as valor
  from staging.contrato_venda c
  where c.data_venda is not null
  group by 1, 2, 3
), meta as (
  select mm.tenant_id, mm.centro_custo_id, mm.competencia, mm.unidades, mm.valor_contratado
  from app.versao_referencia_obra v
  join app.meta_mensal mm on mm.versao_id = v.versao_meta_id
  cross join referencia r
  where mm.unidades is not null and mm.competencia <= r.mes_ref
), recebivel as not materialized (
  select rp.tenant_id, rp.centro_custo_id, date_trunc('month', rp.vencimento)::date as competencia,
         count(*) filter (where rp.situacao = 'vencida') as parcelas_vencidas,
         sum(rp.saldo) filter (where rp.situacao = 'vencida') as saldo_vencido,
         count(distinct rp.contrato_id_origem) filter (where rp.classe = 'financiamento_pendente') as contratos_pendentes,
         sum(rp.saldo) filter (where rp.classe = 'financiamento_pendente') as saldo_pendente,
         bool_or(e.contrato_id_origem is not null) filter (where rp.classe = 'financiamento_pendente') as pendente_com_etapa
  from marts.recebivel_projetado rp
  cross join referencia r
  left join app.etapa_financiamento_contrato e
    on e.tenant_id = rp.tenant_id and e.contrato_id_origem = rp.contrato_id_origem
  where rp.vencimento < r.mes_ref + interval '1 month'
  group by 1, 2, 3
), liberacao as (
  select l.tenant_id, l.centro_custo_id, date_trunc('month', l.data_prevista)::date as competencia,
         count(*) as quantidade, sum(l.valor_previsto) as valor
  from app.liberacao_financiamento l
  cross join referencia r
  where l.situacao = 'prevista' and l.data_prevista < r.ref
  group by 1, 2, 3
), pago as (
  select pg.tenant_id, pg.centro_custo_id, date_trunc('month', pg.data_pagamento)::date as competencia,
         sum(pg.valor) as valor
  from staging.pagamento pg
  cross join referencia r
  where pg.data_pagamento < r.mes_ref + interval '1 month'
  group by 1, 2, 3
), causa as (
  select m.tenant_id, m.centro_custo_id, m.competencia,
         case when coalesce(v.unidades, 0) < m.unidades then 'vendas_abaixo_meta' else 'vendas_acima_meta' end as causa_codigo,
         (coalesce(v.unidades, 0) - m.unidades)::integer as quantidade,
         coalesce(v.valor, 0) - m.valor_contratado as valor,
         'versao_planejamento' as origem_dado
  from meta m
  left join venda v on v.tenant_id = m.tenant_id and v.centro_custo_id = m.centro_custo_id and v.competencia = m.competencia
  where coalesce(v.unidades, 0) <> m.unidades
  union all
  select rc.tenant_id, rc.centro_custo_id, rc.competencia, 'parcelas_vencidas_sem_pagamento',
         rc.parcelas_vencidas::integer, rc.saldo_vencido, 'origem'
  from recebivel rc
  where rc.parcelas_vencidas > 0
  union all
  select rc.tenant_id, rc.centro_custo_id, rc.competencia, 'financiamento_nao_elegivel',
         rc.contratos_pendentes::integer, rc.saldo_pendente,
         case when rc.pendente_com_etapa then 'complemento_manual' else 'origem' end
  from recebivel rc
  where rc.contratos_pendentes > 0
  union all
  select li.tenant_id, li.centro_custo_id, li.competencia, 'liberacao_prevista_vencida',
         li.quantidade::integer, li.valor, 'complemento_manual'
  from liberacao li
  union all
  select pg.tenant_id, pg.centro_custo_id, pg.competencia, 'gasto_acima_previsto', null::integer,
         pg.valor - coalesce(p.total_saidas, 0), 'versao_planejamento'
  from pago pg
  join app.versao_referencia_obra v on v.tenant_id = pg.tenant_id and v.centro_custo_id = pg.centro_custo_id
  left join app.projecao_mensal p on p.versao_id = v.versao_original_id and p.competencia = pg.competencia
  where v.versao_original_id is not null and pg.valor > coalesce(p.total_saidas, 0)
)
select c.tenant_id, c.centro_custo_id, c.competencia, c.causa_codigo,
  case c.causa_codigo
    when 'vendas_abaixo_meta' then 'Vendas abaixo da meta do mês'
    when 'vendas_acima_meta' then 'Vendas acima da meta do mês'
    when 'parcelas_vencidas_sem_pagamento' then 'Parcelas que venceram no mês e não foram pagas'
    when 'financiamento_nao_elegivel' then 'Financiamentos de compradores ainda não elegíveis no banco'
    when 'liberacao_prevista_vencida' then 'Liberações do banco previstas para o mês e não recebidas'
    when 'gasto_acima_previsto' then 'Pagamentos do mês acima do previsto na versão original'
  end as causa_descricao,
  c.quantidade, c.valor::numeric(18,2) as valor, c.origem_dado
from causa c
join obra o on o.tenant_id = c.tenant_id and o.centro_custo_id = c.centro_custo_id;

-- Painel do gestor: meta, vendas, entradas, gastos e caixa do mês, contra a versão original.
create view marts.visao_gerencial_mensal with (security_invoker = true) as
with comercial as (
  select c.tenant_id, c.centro_custo_id, date_trunc('month', e.data)::date as competencia,
         count(*) filter (where e.tipo = 'venda') as vendas_unidades,
         coalesce(sum(c.valor) filter (where e.tipo = 'venda'), 0) as vendas_valor,
         count(*) filter (where e.tipo = 'distrato') as distratos_unidades
  from staging.contrato_venda c
  cross join lateral (values ('venda', c.data_venda), ('distrato', c.data_distrato)) as e(tipo, data)
  where e.data is not null
  group by 1, 2, 3
)
select f.tenant_id, f.centro_custo_id, f.competencia,
  mm.unidades as meta_unidades, mm.valor_contratado as meta_valor_contratado, mm.limite_aporte_proprio as meta_limite_aporte,
  coalesce(co.vendas_unidades, 0)::integer as vendas_unidades,
  coalesce(co.vendas_valor, 0)::numeric(18,2) as vendas_valor,
  coalesce(co.distratos_unidades, 0)::integer as distratos_unidades,
  case when v.versao_original_id is not null
       then coalesce(po.recebido_direto + po.previsto_direto, 0) end::numeric(18,2) as entrada_direta_prevista_original,
  f.recebido_direto as entrada_direta_recebida,
  case when v.versao_original_id is not null
       then coalesce(po.recebido_financiamento + po.previsto_financiamento_elegivel + po.previsto_financiamento_pendente
                     + po.credito_producao_recebido + po.credito_producao_previsto, 0) end::numeric(18,2)
    as financiamento_previsto_original,
  (f.recebido_financiamento + f.credito_producao_recebido)::numeric(18,2) as financiamento_recebido,
  case when v.versao_original_id is not null then coalesce(po.total_saidas, 0) end::numeric(18,2) as gastos_previstos_original,
  f.pago as gastos_realizados,
  f.caixa_gerado_acumulado, f.necessidade_aporte_acumulada,
  oa.caixa_gerado_acumulado as caixa_gerado_acumulado_original,
  (f.caixa_gerado_acumulado - oa.caixa_gerado_acumulado)::numeric(18,2) as diferenca_original_atual
from marts.fluxo_projetado_mensal f
left join app.versao_referencia_obra v on v.tenant_id = f.tenant_id and v.centro_custo_id = f.centro_custo_id
left join app.meta_mensal mm on mm.versao_id = v.versao_meta_id and mm.competencia = f.competencia
left join comercial co on co.tenant_id = f.tenant_id and co.centro_custo_id = f.centro_custo_id
                      and co.competencia = f.competencia
left join app.projecao_mensal po on po.versao_id = v.versao_original_id and po.competencia = f.competencia
-- mês fora do intervalo da versão repete o último acumulado dela
left join lateral (
  select p.caixa_gerado_acumulado
  from app.projecao_mensal p
  where p.versao_id = v.versao_original_id and p.competencia <= f.competencia
  order by p.competencia desc
  limit 1
) oa on v.versao_original_id is not null;

-- Acompanhamento gerencial depois da entrega das chaves, não encerramento contábil.
create view marts.pendencias_pos_entrega with (security_invoker = true) as
with referencia as materialized (
  select app.data_referencia() as ref
), entrega as (
  select u.tenant_id, u.centro_custo_id, max(u.data_entrega) as data_entrega
  from staging.unidade u
  group by 1, 2
), recebivel as (
  select rp.tenant_id, rp.centro_custo_id,
         sum(rp.saldo) filter (where rp.situacao = 'vencida') as vencidos,
         sum(rp.saldo) filter (where rp.situacao = 'a_vencer') as a_vencer,
         count(*) as parcelas
  from marts.recebivel_projetado rp
  group by 1, 2
), titulo as (
  select a.tenant_id, a.centro_custo_id, sum(a.saldo) as em_aberto, count(distinct a.titulo_id_origem) as titulos
  from staging.titulo_pagar_apropriacao a
  where a.saldo > 0
  group by 1, 2
), liberacao as (
  select l.tenant_id, l.centro_custo_id, sum(l.valor_previsto) as nao_recebidas
  from app.liberacao_financiamento l
  where l.situacao in ('prevista', 'pendente')
  group by 1, 2
), credito as (
  select o.tenant_id, o.centro_custo_id,
         sum(greatest(o.valor_contratado - coalesce(r.recebido, 0), 0)) as nao_liberado
  from app.operacao_credito_obra o
  left join (
    select l.operacao_credito_id, sum(l.valor_recebido) as recebido
    from app.liberacao_financiamento l
    where l.situacao = 'recebida'
    group by 1
  ) r on r.operacao_credito_id = o.id
  where o.situacao = 'ativa'
  group by 1, 2
)
select cc.tenant_id, cc.id as centro_custo_id, cc.nome as obra, e.data_entrega,
  coalesce(rc.vencidos, 0)::numeric(18,2) as recebiveis_vencidos,
  coalesce(rc.a_vencer, 0)::numeric(18,2) as recebiveis_a_vencer,
  coalesce(rc.parcelas, 0)::integer as parcelas_abertas,
  coalesce(t.em_aberto, 0)::numeric(18,2) as titulos_em_aberto,
  coalesce(t.titulos, 0)::integer as titulos_abertos,
  coalesce(l.nao_recebidas, 0)::numeric(18,2) as liberacoes_nao_recebidas,
  coalesce(cr.nao_liberado, 0)::numeric(18,2) as credito_nao_liberado
from app.centro_custo cc
cross join referencia r
join entrega e on e.tenant_id = cc.tenant_id and e.centro_custo_id = cc.id
left join recebivel rc on rc.tenant_id = cc.tenant_id and rc.centro_custo_id = cc.id
left join titulo t on t.tenant_id = cc.tenant_id and t.centro_custo_id = cc.id
left join liberacao l on l.tenant_id = cc.tenant_id and l.centro_custo_id = cc.id
left join credito cr on cr.tenant_id = cc.tenant_id and cr.centro_custo_id = cc.id
where cc.tipo = 'obra' and e.data_entrega < r.ref;

grant select on marts.fluxo_projetado_mensal, marts.resumo_projecao_obra, marts.comparativo_projecao,
  marts.explicacao_desvio, marts.visao_gerencial_mensal, marts.pendencias_pos_entrega to authenticated;

-- Simulação: parte do fluxo projetado da obra e aplica as premissas sem gravar nada (função stable não
-- escreve). Com '{}' devolve o mesmo caixa gerado acumulado da view. Custo O(meses + vendas x parcelas),
-- mais o fluxo da obra; validação percorre só as listas das premissas.
create function marts.simular_fluxo(p_centro_custo_id uuid, p_premissas jsonb)
returns table (
  competencia date, recebido numeric(18,2), carteira_prevista numeric(18,2), novas_vendas_unidades integer,
  novas_vendas_valor numeric(18,2), entradas_novas_vendas_direta numeric(18,2),
  entradas_novas_vendas_financiamento numeric(18,2), pago numeric(18,2), a_pagar numeric(18,2),
  custo_sem_titulo numeric(18,2), custo_campanha numeric(18,2), total_entradas numeric(18,2),
  total_saidas numeric(18,2), saldo_mes numeric(18,2), caixa_gerado_acumulado numeric(18,2),
  necessidade_aporte_acumulada numeric(18,2), aporte_incremental_mes numeric(18,2), aviso text, premissas jsonb
)
language plpgsql stable security invoker set search_path = '' as $$
#variable_conflict use_column
declare
  v_entrada_json jsonb := coalesce(p_premissas, '{}'::jsonb);
  v_mes_ref date := date_trunc('month', app.data_referencia())::date;
  v_chave text;
  v_vendas jsonb;
  v_quantidade_total bigint;
  v_composicao jsonb;
  v_entrada numeric;
  v_parcelas numeric;
  v_financiamento numeric;
  v_quantidade_parcelas integer;
  v_meses_liberacao integer;
  v_desconto numeric;
  v_atraso integer;
  v_deslocamento integer;
  v_fator numeric;
  v_cancelar integer[];
  v_campanha jsonb;
  v_premissas jsonb;
begin
  if jsonb_typeof(v_entrada_json) <> 'object' then
    raise exception 'premissa inválida: premissas' using errcode = '22023';
  end if;
  select k into v_chave
  from jsonb_object_keys(v_entrada_json) k
  where k not in ('novas_vendas', 'desconto_tabela', 'composicao', 'meses_ate_liberacao_financiamento',
                  'atraso_liberacao_bancaria_meses', 'deslocamento_cronograma_meses', 'fator_cronograma',
                  'cancelar_contratos', 'custo_campanha')
  limit 1;
  if v_chave is not null then
    raise exception 'premissa inválida: %', v_chave using errcode = '22023';
  end if;

  if jsonb_typeof(coalesce(v_entrada_json -> 'novas_vendas', '[]')) <> 'array' then
    raise exception 'premissa inválida: novas_vendas' using errcode = '22023';
  end if;
  -- teto de itens: o formulário já limita, mas a API aceita chamada direta
  if jsonb_array_length(coalesce(v_entrada_json -> 'novas_vendas', '[]')) > 120 then
    raise exception 'premissa inválida: novas_vendas tem mais de 120 itens' using errcode = '22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('competencia', x.competencia, 'quantidade', x.quantidade) order by x.posicao),
                  '[]'::jsonb),
         coalesce(sum(x.quantidade), 0)
  into v_vendas, v_quantidade_total
  from (
    select i.posicao,
           app.premissa_competencia(case when jsonb_typeof(i.item) = 'object' then i.item -> 'competencia' end,
                                    'novas_vendas.competencia') as competencia,
           app.premissa_inteiro(case when jsonb_typeof(i.item) = 'object' then coalesce(i.item -> 'quantidade', 'null') end,
                                'novas_vendas.quantidade', null, 100000) as quantidade
    from jsonb_array_elements(coalesce(v_entrada_json -> 'novas_vendas', '[]')) with ordinality as i(item, posicao)
  ) x;
  if exists (select 1 from jsonb_array_elements(v_vendas) e where (e ->> 'competencia')::date < v_mes_ref) then
    raise exception 'premissa inválida: novas_vendas.competencia' using errcode = '22023';
  end if;

  v_desconto := coalesce(app.premissa_numero(v_entrada_json -> 'desconto_tabela', 'desconto_tabela'), 0);
  if v_desconto < 0 or v_desconto >= 1 then
    raise exception 'premissa inválida: desconto_tabela' using errcode = '22023';
  end if;

  v_composicao := v_entrada_json -> 'composicao';
  if v_composicao is not null and jsonb_typeof(v_composicao) <> 'null' then
    if jsonb_typeof(v_composicao) <> 'object' then
      raise exception 'premissa inválida: composicao' using errcode = '22023';
    end if;
    v_entrada := coalesce(app.premissa_numero(v_composicao -> 'entrada', 'composicao.entrada'), 0);
    v_parcelas := coalesce(app.premissa_numero(v_composicao -> 'parcelas_mensais', 'composicao.parcelas_mensais'), 0);
    v_financiamento := coalesce(app.premissa_numero(v_composicao -> 'financiamento', 'composicao.financiamento'), 0);
    if v_entrada < 0 or v_parcelas < 0 or v_financiamento < 0 or v_entrada + v_parcelas + v_financiamento <> 1 then
      raise exception 'premissa inválida: composicao' using errcode = '22023';
    end if;
    if v_parcelas > 0 then
      v_quantidade_parcelas := app.premissa_inteiro(coalesce(v_composicao -> 'quantidade_parcelas_mensais', 'null'),
                                                    'composicao.quantidade_parcelas_mensais', null, 600);
      if v_quantidade_parcelas < 1 then
        raise exception 'premissa inválida: composicao.quantidade_parcelas_mensais' using errcode = '22023';
      end if;
    end if;
    v_composicao := jsonb_build_object('entrada', v_entrada, 'parcelas_mensais', v_parcelas,
                                       'quantidade_parcelas_mensais', v_quantidade_parcelas,
                                       'financiamento', v_financiamento);
  elsif v_quantidade_total > 0 then
    raise exception 'premissa inválida: composicao' using errcode = '22023';
  else
    v_composicao := null;
    v_entrada := 0; v_parcelas := 0; v_financiamento := 0;
  end if;

  if v_financiamento > 0 then
    v_meses_liberacao := app.premissa_inteiro(coalesce(v_entrada_json -> 'meses_ate_liberacao_financiamento', 'null'),
                                              'meses_ate_liberacao_financiamento', null, 600);
  else
    v_meses_liberacao := app.premissa_inteiro(v_entrada_json -> 'meses_ate_liberacao_financiamento',
                                              'meses_ate_liberacao_financiamento', 0, 600);
  end if;
  v_atraso := app.premissa_inteiro(v_entrada_json -> 'atraso_liberacao_bancaria_meses', 'atraso_liberacao_bancaria_meses', 0, 600);
  v_deslocamento := app.premissa_inteiro(v_entrada_json -> 'deslocamento_cronograma_meses', 'deslocamento_cronograma_meses', 0, 600);
  v_fator := coalesce(app.premissa_numero(v_entrada_json -> 'fator_cronograma', 'fator_cronograma'), 1);
  if v_fator <= 0 then
    raise exception 'premissa inválida: fator_cronograma' using errcode = '22023';
  end if;

  if jsonb_typeof(coalesce(v_entrada_json -> 'cancelar_contratos', '[]')) <> 'array' then
    raise exception 'premissa inválida: cancelar_contratos' using errcode = '22023';
  end if;
  select coalesce(array_agg(distinct app.premissa_numero(c, 'cancelar_contratos')::integer), '{}')
  into v_cancelar
  from jsonb_array_elements(coalesce(v_entrada_json -> 'cancelar_contratos', '[]')) c;
  if exists (select 1 from jsonb_array_elements(coalesce(v_entrada_json -> 'cancelar_contratos', '[]')) c
             where jsonb_typeof(c) <> 'number' or (c #>> '{}')::numeric <> trunc((c #>> '{}')::numeric)) then
    raise exception 'premissa inválida: cancelar_contratos' using errcode = '22023';
  end if;

  if jsonb_typeof(coalesce(v_entrada_json -> 'custo_campanha', '[]')) <> 'array' then
    raise exception 'premissa inválida: custo_campanha' using errcode = '22023';
  end if;
  if jsonb_array_length(v_entrada_json -> 'custo_campanha') > 120 then
    raise exception 'premissa inválida: custo_campanha tem mais de 120 itens' using errcode = '22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('competencia', x.competencia, 'valor', x.valor) order by x.posicao), '[]'::jsonb)
  into v_campanha
  from (
    select i.posicao,
           app.premissa_competencia(case when jsonb_typeof(i.item) = 'object' then i.item -> 'competencia' end,
                                    'custo_campanha.competencia') as competencia,
           app.premissa_numero(case when jsonb_typeof(i.item) = 'object' then i.item -> 'valor' end,
                               'custo_campanha.valor') as valor
    from jsonb_array_elements(coalesce(v_entrada_json -> 'custo_campanha', '[]')) with ordinality as i(item, posicao)
  ) x;
  if exists (select 1 from jsonb_array_elements(v_campanha) e
             where (e ->> 'competencia')::date < v_mes_ref or (e ->> 'valor') is null or (e ->> 'valor')::numeric <= 0) then
    raise exception 'premissa inválida: custo_campanha' using errcode = '22023';
  end if;

  v_premissas := jsonb_build_object(
    'novas_vendas', v_vendas,
    'desconto_tabela', v_desconto,
    'composicao', v_composicao,
    'meses_ate_liberacao_financiamento', case when v_financiamento > 0 or v_entrada_json ? 'meses_ate_liberacao_financiamento'
                                              then v_meses_liberacao end,
    'atraso_liberacao_bancaria_meses', v_atraso,
    'deslocamento_cronograma_meses', v_deslocamento,
    'fator_cronograma', v_fator,
    'cancelar_contratos', to_jsonb(v_cancelar),
    'custo_campanha', v_campanha);

  -- Obra fora das permitidas é invisível pelo RLS: nenhuma linha, sem distinguir de obra inexistente.
  if not exists (select 1 from app.centro_custo cc where cc.id = p_centro_custo_id and cc.tipo = 'obra') then
    return;
  end if;

  return query
  with base as (
    select f.* from marts.fluxo_projetado_mensal f where f.centro_custo_id = p_centro_custo_id
  ), carteira as (
    select (date_trunc('month', rp.data_prevista)
            + make_interval(months => case when rp.origem = 'financiamento' then v_atraso else 0 end))::date as competencia,
           rp.saldo as valor
    from marts.recebivel_projetado rp
    where rp.centro_custo_id = p_centro_custo_id and rp.incluida_projecao
      and not coalesce(rp.contrato_id_origem = any (v_cancelar), false)
    union all
    select (b.competencia + make_interval(months => v_atraso))::date, b.credito_producao_previsto
    from base b
    where b.credito_producao_previsto <> 0
  ), custo as (
    select (b.competencia + make_interval(months => v_deslocamento))::date as competencia,
           round(b.custo_sem_titulo_distribuido * v_fator, 2) as valor
    from base b
    where b.custo_sem_titulo_distribuido <> 0
  ), campanha as (
    select (e ->> 'competencia')::date as competencia, (e ->> 'valor')::numeric as valor
    from jsonb_array_elements(v_campanha) e
  ), estoque as (
    select count(*) as unidades, sum(mu.valor) / nullif(count(*), 0) as ticket
    from marts.mapa_unidades mu
    where mu.centro_custo_id = p_centro_custo_id and mu.situacao in ('disponivel', 'reservada', 'proposta')
      and mu.valor is not null
  ), pedido as (
    select (e ->> 'competencia')::date as competencia, sum((e ->> 'quantidade')::integer) as pedida
    from jsonb_array_elements(v_vendas) e
    group by 1
  ), venda as (
    -- quantidade aplicada: o acumulado pedido limitado ao estoque, na ordem dos meses
    select p.competencia, p.pedida,
           (least(sum(p.pedida) over w, es.unidades) - least(sum(p.pedida) over w - p.pedida, es.unidades))::integer
             as aplicada,
           es.ticket
    from pedido p
    cross join estoque es
    window w as (order by p.competencia)
  ), venda_valor as (
    select v.competencia, v.pedida, v.aplicada,
           coalesce(round(v.aplicada * v.ticket * (1 - v_desconto), 2), 0) as valor
    from venda v
  ), venda_partes as (
    select vv.*, round(vv.valor * v_entrada, 2) as entrada, round(vv.valor * v_financiamento, 2) as financiamento,
           vv.valor - round(vv.valor * v_entrada, 2) - round(vv.valor * v_financiamento, 2) as parcelado
    from venda_valor vv
  ), entrada_nova as (
    -- sem parcelas mensais, o centavo de arredondamento fica na entrada
    select vp.competencia,
           vp.entrada + case when coalesce(v_quantidade_parcelas, 0) = 0 then vp.parcelado else 0 end as direta,
           0::numeric as financiamento
    from venda_partes vp
    union all
    select (vp.competencia + make_interval(months => v_meses_liberacao + v_atraso))::date, 0, vp.financiamento
    from venda_partes vp
    where vp.financiamento <> 0
    union all
    select (vp.competencia + make_interval(months => k.n))::date,
           case when k.n < v_quantidade_parcelas then round(vp.parcelado / v_quantidade_parcelas, 2)
                else vp.parcelado - (v_quantidade_parcelas - 1) * round(vp.parcelado / v_quantidade_parcelas, 2) end,
           0
    from venda_partes vp
    cross join generate_series(1, coalesce(v_quantidade_parcelas, 0)) as k(n)
    where vp.parcelado <> 0
  ), item_mes as (
    select i.competencia,
           coalesce(sum(i.valor) filter (where i.tipo = 'carteira'), 0) as carteira_prevista,
           coalesce(sum(i.valor) filter (where i.tipo = 'custo'), 0) as custo_sem_titulo,
           coalesce(sum(i.valor) filter (where i.tipo = 'campanha'), 0) as custo_campanha,
           coalesce(sum(i.valor) filter (where i.tipo = 'nova_direta'), 0) as nova_direta,
           coalesce(sum(i.valor) filter (where i.tipo = 'nova_financiamento'), 0) as nova_financiamento
    from (
      select c.competencia, 'carteira' as tipo, c.valor from carteira c
      union all select c.competencia, 'custo', c.valor from custo c
      union all select c.competencia, 'campanha', c.valor from campanha c
      union all select en.competencia, 'nova_direta', en.direta from entrada_nova en
      union all select en.competencia, 'nova_financiamento', en.financiamento from entrada_nova en
    ) i
    group by 1
  ), calendario as (
    select g.competencia::date as competencia
    from (select min(x.competencia) as inicio, max(x.competencia) as fim
          from (select b.competencia from base b
                union all select im.competencia from item_mes im
                union all select vv.competencia from venda_valor vv) x) l
    cross join lateral generate_series(l.inicio, l.fim, interval '1 month') as g(competencia)
  ), linha as (
    select cal.competencia,
      coalesce(b.recebido_direto + b.recebido_financiamento + b.credito_producao_recebido, 0) as recebido,
      coalesce(im.carteira_prevista, 0) as carteira_prevista,
      coalesce(vv.aplicada, 0) as novas_vendas_unidades,
      coalesce(vv.valor, 0) as novas_vendas_valor,
      coalesce(im.nova_direta, 0) as nova_direta,
      coalesce(im.nova_financiamento, 0) as nova_financiamento,
      coalesce(b.pago, 0) as pago,
      coalesce(b.a_pagar + b.a_pagar_vencido, 0) as a_pagar,
      coalesce(im.custo_sem_titulo, 0) as custo_sem_titulo,
      coalesce(im.custo_campanha, 0) as custo_campanha,
      case when vv.aplicada < vv.pedida then 'vendas_limitadas_ao_estoque' end as aviso
    from calendario cal
    left join base b on b.competencia = cal.competencia
    left join item_mes im on im.competencia = cal.competencia
    left join venda_valor vv on vv.competencia = cal.competencia
  ), total as (
    select li.*,
      li.recebido + li.carteira_prevista + li.nova_direta + li.nova_financiamento as total_entradas,
      li.pago + li.a_pagar + li.custo_sem_titulo + li.custo_campanha as total_saidas
    from linha li
  ), acumulado as (
    select t.*, sum(t.total_entradas - t.total_saidas) over (order by t.competencia) as caixa
    from total t
  )
  select a.competencia, a.recebido::numeric(18,2), a.carteira_prevista::numeric(18,2), a.novas_vendas_unidades::integer,
    a.novas_vendas_valor::numeric(18,2), a.nova_direta::numeric(18,2), a.nova_financiamento::numeric(18,2),
    a.pago::numeric(18,2), a.a_pagar::numeric(18,2), a.custo_sem_titulo::numeric(18,2), a.custo_campanha::numeric(18,2),
    a.total_entradas::numeric(18,2), a.total_saidas::numeric(18,2), (a.total_entradas - a.total_saidas)::numeric(18,2),
    a.caixa::numeric(18,2), greatest(-a.caixa, 0)::numeric(18,2),
    greatest(greatest(-a.caixa, 0) - coalesce(lag(greatest(-a.caixa, 0)) over (order by a.competencia), 0), 0)::numeric(18,2),
    a.aviso, v_premissas
  from acumulado a
  order by a.competencia;
end $$;
revoke execute on function marts.simular_fluxo(uuid, jsonb) from public, anon;
grant execute on function marts.simular_fluxo(uuid, jsonb) to authenticated;

-- Fotografia do fluxo projetado da obra numa versão nova. Perfil sem escrita recebe 42501 do RLS.
create function app.registrar_versao_projecao(p_centro_custo_id uuid, p_descricao text) returns uuid
language plpgsql volatile security invoker set search_path = '' as $$
declare
  v_tenant uuid;
  v_premissas jsonb;
  v_versao uuid;
begin
  if btrim(coalesce(p_descricao, '')) = '' then
    raise exception 'premissa inválida: descricao' using errcode = '22023';
  end if;
  select cc.tenant_id into v_tenant from app.centro_custo cc where cc.id = p_centro_custo_id and cc.tipo = 'obra';
  if v_tenant is null then
    raise exception 'obra não encontrada' using errcode = '42501';
  end if;
  select jsonb_build_object('premissa_distribuicao_id', c.premissa_distribuicao_id,
                            'motivo_distribuicao', c.motivo_distribuicao)
  into v_premissas
  from app.custo_sem_titulo_obra c
  where c.centro_custo_id = p_centro_custo_id;

  insert into app.versao_planejamento (tenant_id, centro_custo_id, tipo, numero, descricao, data_referencia, premissas, autor)
  values (v_tenant, p_centro_custo_id, 'projecao', 1, p_descricao, app.data_referencia(),
          coalesce(v_premissas, '{}'::jsonb), auth.uid())
  returning id into v_versao;

  insert into app.projecao_mensal (versao_id, tenant_id, centro_custo_id, competencia, recebido_direto,
    recebido_financiamento, credito_producao_recebido, previsto_direto, previsto_financiamento_elegivel,
    previsto_financiamento_pendente, credito_producao_previsto, vencido_a_receber, pago, a_pagar, a_pagar_vencido,
    custo_sem_titulo_distribuido, total_entradas, total_saidas, saldo_mes, caixa_gerado_acumulado,
    necessidade_aporte_acumulada, aporte_incremental_mes, caixa_gerado_acumulado_conservador,
    necessidade_aporte_conservadora)
  select v_versao, f.tenant_id, f.centro_custo_id, f.competencia, f.recebido_direto, f.recebido_financiamento,
    f.credito_producao_recebido, f.previsto_direto, f.previsto_financiamento_elegivel, f.previsto_financiamento_pendente,
    f.credito_producao_previsto, f.vencido_a_receber, f.pago, f.a_pagar, f.a_pagar_vencido,
    f.custo_sem_titulo_distribuido, f.total_entradas, f.total_saidas, f.saldo_mes, f.caixa_gerado_acumulado,
    f.necessidade_aporte_acumulada, f.aporte_incremental_mes, f.caixa_gerado_acumulado_conservador,
    f.necessidade_aporte_conservadora
  from marts.fluxo_projetado_mensal f
  where f.centro_custo_id = p_centro_custo_id;
  return v_versao;
end $$;

create function app.registrar_versao_meta(p_centro_custo_id uuid, p_descricao text, p_metas jsonb) returns uuid
language plpgsql volatile security invoker set search_path = '' as $$
declare
  v_tenant uuid;
  v_versao uuid;
  v_chave text;
begin
  if btrim(coalesce(p_descricao, '')) = '' then
    raise exception 'premissa inválida: descricao' using errcode = '22023';
  end if;
  if jsonb_typeof(p_metas) is distinct from 'array' or jsonb_array_length(p_metas) = 0
     or exists (select 1 from jsonb_array_elements(p_metas) e where jsonb_typeof(e) <> 'object') then
    raise exception 'premissa inválida: metas' using errcode = '22023';
  end if;
  select k into v_chave
  from jsonb_array_elements(p_metas) e cross join lateral jsonb_object_keys(e) k
  where k not in ('competencia', 'unidades', 'valor_contratado', 'fracao_financiada', 'recebimento_esperado',
                  'limite_aporte_proprio')
  limit 1;
  if v_chave is not null then
    raise exception 'premissa inválida: %', v_chave using errcode = '22023';
  end if;
  select cc.tenant_id into v_tenant from app.centro_custo cc where cc.id = p_centro_custo_id and cc.tipo = 'obra';
  if v_tenant is null then
    raise exception 'obra não encontrada' using errcode = '42501';
  end if;

  if exists (
    select 1
    from (select app.premissa_competencia(e -> 'competencia', 'competencia') as competencia,
                 app.premissa_inteiro(e -> 'unidades', 'unidades', 0, null) as unidades,
                 app.premissa_numero(e -> 'valor_contratado', 'valor_contratado') as valor_contratado,
                 app.premissa_numero(e -> 'fracao_financiada', 'fracao_financiada') as fracao_financiada,
                 app.premissa_numero(e -> 'recebimento_esperado', 'recebimento_esperado') as recebimento_esperado,
                 app.premissa_numero(e -> 'limite_aporte_proprio', 'limite_aporte_proprio') as limite_aporte_proprio
          from jsonb_array_elements(p_metas) e) m
    having count(distinct m.competencia) <> count(*)
        or bool_or(m.valor_contratado < 0 or m.recebimento_esperado < 0 or m.limite_aporte_proprio < 0
                   or m.fracao_financiada < 0 or m.fracao_financiada > 1)
  ) then
    raise exception 'premissa inválida: metas' using errcode = '22023';
  end if;

  insert into app.versao_planejamento (tenant_id, centro_custo_id, tipo, numero, descricao, data_referencia, premissas, autor)
  values (v_tenant, p_centro_custo_id, 'meta', 1, p_descricao, app.data_referencia(), '{}'::jsonb, auth.uid())
  returning id into v_versao;

  insert into app.meta_mensal (versao_id, tenant_id, centro_custo_id, competencia, unidades, valor_contratado,
    fracao_financiada, recebimento_esperado, limite_aporte_proprio)
  select v_versao, v_tenant, p_centro_custo_id, (e ->> 'competencia')::date,
         case when jsonb_typeof(e -> 'unidades') = 'number' then (e ->> 'unidades')::integer end,
         case when jsonb_typeof(e -> 'valor_contratado') = 'number' then (e ->> 'valor_contratado')::numeric end,
         case when jsonb_typeof(e -> 'fracao_financiada') = 'number' then (e ->> 'fracao_financiada')::numeric end,
         case when jsonb_typeof(e -> 'recebimento_esperado') = 'number' then (e ->> 'recebimento_esperado')::numeric end,
         case when jsonb_typeof(e -> 'limite_aporte_proprio') = 'number' then (e ->> 'limite_aporte_proprio')::numeric end
  from jsonb_array_elements(p_metas) e;
  return v_versao;
end $$;

create function app.registrar_premissa_distribuicao(p_centro_custo_id uuid, p_fonte text, p_observacao text,
                                                    p_meses jsonb) returns uuid
language plpgsql volatile security invoker set search_path = '' as $$
declare
  v_tenant uuid;
  v_premissa uuid;
begin
  if btrim(coalesce(p_fonte, '')) = '' then
    raise exception 'premissa inválida: fonte' using errcode = '22023';
  end if;
  if jsonb_typeof(p_meses) is distinct from 'array' or jsonb_array_length(p_meses) = 0
     or exists (select 1 from jsonb_array_elements(p_meses) e where jsonb_typeof(e) <> 'object') then
    raise exception 'premissa inválida: meses' using errcode = '22023';
  end if;
  if exists (
    select 1
    from (select app.premissa_competencia(e -> 'competencia', 'competencia') as competencia,
                 app.premissa_numero(e -> 'fracao', 'fracao') as fracao
          from jsonb_array_elements(p_meses) e) m
    having count(distinct m.competencia) <> count(*) or bool_or(m.fracao is null or m.fracao <= 0 or m.fracao > 1)
        or sum(m.fracao) <> 1
  ) then
    raise exception 'premissa inválida: fracao' using errcode = '22023';
  end if;
  select cc.tenant_id into v_tenant from app.centro_custo cc where cc.id = p_centro_custo_id and cc.tipo = 'obra';
  if v_tenant is null then
    raise exception 'obra não encontrada' using errcode = '42501';
  end if;

  insert into app.premissa_distribuicao_custo (tenant_id, centro_custo_id, metodo, fonte, observacao, autor)
  values (v_tenant, p_centro_custo_id, 'fracao_mensal', p_fonte, p_observacao, auth.uid())
  returning id into v_premissa;
  insert into app.premissa_distribuicao_custo_mes (premissa_id, tenant_id, centro_custo_id, competencia, fracao)
  select v_premissa, v_tenant, p_centro_custo_id, (e ->> 'competencia')::date, (e ->> 'fracao')::numeric
  from jsonb_array_elements(p_meses) e;
  return v_premissa;
end $$;

revoke execute on function app.registrar_versao_projecao(uuid, text), app.registrar_versao_meta(uuid, text, jsonb),
  app.registrar_premissa_distribuicao(uuid, text, text, jsonb) from public, anon;
grant execute on function app.registrar_versao_projecao(uuid, text), app.registrar_versao_meta(uuid, text, jsonb),
  app.registrar_premissa_distribuicao(uuid, text, text, jsonb) to authenticated;
