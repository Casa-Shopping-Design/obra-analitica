-- Preço das unidades. O valor em reais muda todo mês até a venda: a tabela guarda
-- quantidade indexada e o índice do mês converte em reais. Depois da venda vale o contrato.

create table staging.indice_valor (
  tenant_id uuid not null,
  indexador_id_origem integer not null,
  nome text,
  referencia date not null,
  valor numeric(18, 6) not null,
  percentual numeric(9, 4),
  primary key (tenant_id, indexador_id_origem, referencia)
);

create table staging.tabela_preco (
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  id_origem integer not null,
  versao integer not null,
  nome text,
  nome_versao text,
  vigencia_inicio date not null,
  vigencia_fim date,
  indexador_id_origem integer,
  data_base date,
  primary key (tenant_id, id_origem, versao)
);
create index on staging.tabela_preco (tenant_id, centro_custo_id, vigencia_inicio desc, versao desc);

create table staging.tabela_preco_unidade (
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  tabela_id_origem integer not null,
  versao integer not null,
  unidade_id_origem integer not null,
  quantidade_indexada numeric(18, 6) not null,
  primary key (tenant_id, tabela_id_origem, versao, unidade_id_origem)
);

-- valor sugerido que o cadastro da unidade traz; só entra quando não há tabela vigente
create table staging.unidade_valor (
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  unidade_id_origem integer not null,
  valor_sugerido numeric,
  data_valor_sugerido date,
  indexador_id_origem integer,
  tabela_id_origem integer,
  primary key (tenant_id, unidade_id_origem)
);

create index on staging.contrato_venda (tenant_id, unidade_id_origem, data_venda desc) where situacao = '1';

-- O índice não é apagado na recarga: a API só devolve o último valor, a série é o histórico das cargas.
create or replace function staging.recarregar_precos(p_tenant uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  insert into staging.indice_valor (tenant_id, indexador_id_origem, nome, referencia, valor, percentual)
  select p_tenant, (r.payload->>'id')::int, r.payload->>'name', (r.payload->'lastValue'->>'date')::date,
         (r.payload->'lastValue'->>'value')::numeric, (r.payload->'lastValue'->>'percentage')::numeric
  from raw.registro r
  where r.tenant_id = p_tenant and r.endpoint = 'indexers' and r.payload->'lastValue'->>'date' is not null
  on conflict (tenant_id, indexador_id_origem, referencia)
    do update set valor = excluded.valor, percentual = excluded.percentual, nome = excluded.nome;

  delete from staging.tabela_preco_unidade where tenant_id = p_tenant;
  delete from staging.tabela_preco where tenant_id = p_tenant;
  insert into staging.tabela_preco
  select p_tenant, cc.id, (r.payload->>'id')::int, (r.payload->>'version')::int, r.payload->>'tableName',
         r.payload->>'tableVersionName', (r.payload->>'startOfTerm')::date, (r.payload->>'endOfTerm')::date,
         (r.payload->'paymentConditions'->0->'indexer'->>'id')::int, (r.payload->'paymentConditions'->0->>'baseDate')::date
  from raw.registro r
  join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = (r.payload->>'enterpriseId')::int
  where r.tenant_id = p_tenant and r.endpoint = 'price-tables'
  on conflict do nothing;

  insert into staging.tabela_preco_unidade
  select p_tenant, cc.id, (r.payload->>'id')::int, (r.payload->>'version')::int,
         (item->>'id')::int, (item->>'indexedQuantity')::numeric
  from raw.registro r
  join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = (r.payload->>'enterpriseId')::int
  cross join lateral jsonb_array_elements(r.payload->'units') as item
  where r.tenant_id = p_tenant and r.endpoint = 'price-tables' and item->>'indexedQuantity' is not null
  on conflict do nothing;

  delete from staging.unidade_valor where tenant_id = p_tenant;
  insert into staging.unidade_valor
  select p_tenant, cc.id, (r.payload->>'id')::int, (r.payload->>'saleValuePrice')::numeric,
         (r.payload->>'saleValueDate')::date, (r.payload->>'indexerId')::int, (r.payload->>'tablePricesID')::int
  from raw.registro r
  join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = (r.payload->>'enterpriseId')::int
  where r.tenant_id = p_tenant and r.endpoint = 'units';
end $$;
revoke execute on function staging.recarregar_precos(uuid) from public, anon, authenticated;

-- RLS: índice é do tenant inteiro; o resto segue a regra única tenant + obra.
alter table staging.indice_valor enable row level security;
alter table staging.indice_valor force row level security;
create policy leitura_tenant on staging.indice_valor for select to authenticated
  using (tenant_id = app.tenant_atual());
grant select on staging.indice_valor to authenticated;

do $$
declare t text;
begin
  foreach t in array array['tabela_preco','tabela_preco_unidade','unidade_valor'] loop
    execute format('alter table staging.%I enable row level security', t);
    execute format('alter table staging.%I force row level security', t);
    execute format($p$create policy leitura_por_obra on staging.%I for select to authenticated
      using (tenant_id = app.tenant_atual() and centro_custo_id in (select app.obras_permitidas()))$p$, t);
    execute format('grant select on staging.%I to authenticated', t);
  end loop;
end $$;

-- Mapa de disponibilidade: uma linha por unidade com o valor que vale hoje e de onde ele veio.
-- Ordem de preferência do valor: contrato (vendida) > tabela vigente x índice do mês > valor sugerido do cadastro.
create or replace view marts.mapa_unidades with (security_invoker = true) as
with indice_atual as (
  select distinct on (tenant_id, indexador_id_origem) tenant_id, indexador_id_origem, nome, referencia, valor
  from staging.indice_valor
  where referencia <= current_date
  order by tenant_id, indexador_id_origem, referencia desc
), tabela_vigente as (
  select distinct on (tenant_id, centro_custo_id) *
  from staging.tabela_preco
  where vigencia_inicio <= current_date and (vigencia_fim is null or vigencia_fim >= current_date)
  order by tenant_id, centro_custo_id, vigencia_inicio desc, versao desc
), contrato_ativo as (
  select distinct on (tenant_id, unidade_id_origem) tenant_id, unidade_id_origem, valor, data_venda
  from staging.contrato_venda
  where situacao = '1'
  order by tenant_id, unidade_id_origem, data_venda desc
), base as (
  select
    u.tenant_id, u.centro_custo_id, u.id_origem as unidade_id, u.nome as unidade, u.tipologia, u.area_privativa,
    u.situacao as situacao_origem,
    case u.situacao
      when 'D' then 'disponivel' when 'C' then 'reservada' when 'P' then 'proposta'
      when 'V' then 'vendida' when 'O' then 'vendida' when 'G' then 'vendida'
      else 'indisponivel'
    end as situacao,
    tv.nome as tabela, tv.nome_versao as tabela_versao,
    tpu.quantidade_indexada, ia.nome as indice, ia.referencia as indice_referencia, ia.valor as indice_valor,
    ca.valor as valor_contrato, ca.data_venda,
    round(tpu.quantidade_indexada * ia.valor, 2) as valor_tabela,
    uv.valor_sugerido, uv.data_valor_sugerido
  from staging.unidade u
  left join contrato_ativo ca on ca.tenant_id = u.tenant_id and ca.unidade_id_origem = u.id_origem
  left join tabela_vigente tv on tv.tenant_id = u.tenant_id and tv.centro_custo_id = u.centro_custo_id
  left join staging.tabela_preco_unidade tpu
    on tpu.tenant_id = tv.tenant_id and tpu.tabela_id_origem = tv.id_origem and tpu.versao = tv.versao
   and tpu.unidade_id_origem = u.id_origem
  left join indice_atual ia on ia.tenant_id = tv.tenant_id and ia.indexador_id_origem = tv.indexador_id_origem
  left join staging.unidade_valor uv on uv.tenant_id = u.tenant_id and uv.unidade_id_origem = u.id_origem
)
select
  b.*,
  coalesce(case when b.situacao = 'vendida' then b.valor_contrato end, b.valor_tabela, b.valor_sugerido) as valor,
  case
    when b.situacao = 'vendida' and b.valor_contrato is not null then 'contrato'
    when b.valor_tabela is not null then 'tabela'
    when b.valor_sugerido is not null then 'cadastro'
  end as origem_valor,
  round(coalesce(case when b.situacao = 'vendida' then b.valor_contrato end, b.valor_tabela, b.valor_sugerido)
        / nullif(b.area_privativa, 0), 2) as valor_m2
from base b;

grant select on marts.mapa_unidades to authenticated;
