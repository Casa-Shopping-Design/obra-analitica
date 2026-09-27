-- VSO com casos conhecidos. As datas são relativas ao mês atual porque o calendário da view vai
-- até hoje: "mes_0" é o mês corrente, "mes_2" é dois meses atrás.
--   Obra Leste: 10 unidades em oferta e uma fora de venda; uma venda em mes_2, nenhuma em mes_1, uma em mes_0.
--   Obra Oeste: 5 unidades; duas vendas em mes_3, uma delas distratada em mes_0; uma venda em mes_1
--   distratada sem data de cancelamento na origem.
--   Obra Antiga: seis vendas oito meses atrás e nada depois.
--   Obra Vazia: sem contrato.
begin;
create extension if not exists pgtap with schema extensions;
select plan(23);

create temporary table referencia on commit drop as
select m::date as mes_0,
  (m - interval '1 month')::date as mes_1,
  (m - interval '2 months')::date as mes_2,
  (m - interval '3 months')::date as mes_3,
  (m - interval '8 months')::date as mes_8
from date_trunc('month', current_date) as m;

insert into app.tenant (id, razao_social) values
  ('0e000000-0000-4000-8000-0000000000d1', 'Construtora VSO');

insert into app.centro_custo (id, tenant_id, id_origem, nome) values
  ('0c000000-0000-4000-8000-0000000000d1', '0e000000-0000-4000-8000-0000000000d1', 971, 'Obra Leste'),
  ('0c000000-0000-4000-8000-0000000000d2', '0e000000-0000-4000-8000-0000000000d1', 972, 'Obra Oeste'),
  ('0c000000-0000-4000-8000-0000000000d3', '0e000000-0000-4000-8000-0000000000d1', 973, 'Obra Antiga'),
  ('0c000000-0000-4000-8000-0000000000d4', '0e000000-0000-4000-8000-0000000000d1', 974, 'Obra Vazia');

insert into staging.unidade (tenant_id, centro_custo_id, id_origem, nome, situacao)
select '0e000000-0000-4000-8000-0000000000d1'::uuid, '0c000000-0000-4000-8000-0000000000d1'::uuid, n, 'L-' || n, 'D'
from generate_series(1, 10) as n
union all
select '0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1', 11, 'L-11', 'X'
union all
select '0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d2', 20 + n, 'O-' || n, 'D'
from generate_series(1, 5) as n;

insert into staging.item_orcamento (tenant_id, centro_custo_id, codigo, valor_total) values
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1', '01', 1000000),
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d2', '01', 1000000);

insert into staging.contrato_venda (tenant_id, centro_custo_id, id_origem, data_venda, valor, situacao, data_distrato)
select '0e000000-0000-4000-8000-0000000000d1'::uuid, obra::uuid, id_origem, data_venda, valor, situacao, data_distrato
from referencia, lateral (values
  ('0c000000-0000-4000-8000-0000000000d1', 1, mes_2 + 4, 200000, '1', null::date),
  ('0c000000-0000-4000-8000-0000000000d1', 2, mes_0, 200000, '1', null),
  ('0c000000-0000-4000-8000-0000000000d2', 3, mes_3 + 9, 300000, '3', mes_0),
  ('0c000000-0000-4000-8000-0000000000d2', 4, mes_3 + 19, 300000, '1', null),
  ('0c000000-0000-4000-8000-0000000000d2', 5, mes_1 + 2, 300000, '3', null)
) as c (obra, id_origem, data_venda, valor, situacao, data_distrato)
union all
select '0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d3', 30 + n, mes_8 + n, 250000, '1', null
from referencia, generate_series(1, 6) as n;

select is(
  (select count(*) from marts.vso_mensal where centro_custo_id = '0c000000-0000-4000-8000-0000000000d1'),
  3::bigint,
  'mês sem venda entre duas vendas aparece no calendário'
);

select is(
  (select vendas from marts.vso_mensal v, referencia r
   where v.centro_custo_id = '0c000000-0000-4000-8000-0000000000d1' and v.competencia = r.mes_1),
  0::bigint,
  'mês sem venda tem zero vendas'
);

select is(
  (select avg(vendas) from marts.vso_mensal where centro_custo_id = '0c000000-0000-4000-8000-0000000000d1'),
  2::numeric / 3,
  'média inclui o mês zerado: duas vendas em três meses'
);

select is(
  (select array_agg(estoque_inicio_mes order by competencia) from marts.vso_mensal
   where centro_custo_id = '0c000000-0000-4000-8000-0000000000d1'),
  array[10, 9, 9],
  'estoque no início do mês desconta as vendas líquidas anteriores; unidade fora de venda não conta'
);

select is(
  (select array_agg(vso_pct order by competencia) from marts.vso_mensal
   where centro_custo_id = '0c000000-0000-4000-8000-0000000000d1'),
  array[0.1, 0, 0.1111]::numeric[],
  'VSO é venda líquida sobre o estoque do início do mês'
);

select is(
  (select row(vendas, distratos)::text from marts.vso_mensal v, referencia r
   where v.centro_custo_id = '0c000000-0000-4000-8000-0000000000d2' and v.competencia = r.mes_3),
  '(2,0)',
  'contrato distratado depois conta como venda no mês da venda'
);

select is(
  (select row(vendas, distratos, vendas_liquidas)::text from marts.vso_mensal v, referencia r
   where v.centro_custo_id = '0c000000-0000-4000-8000-0000000000d2' and v.competencia = r.mes_0),
  '(0,1,-1)',
  'distrato conta no mês do cancelamento'
);

select is(
  (select row(vendas, distratos)::text from marts.vso_mensal v, referencia r
   where v.centro_custo_id = '0c000000-0000-4000-8000-0000000000d2' and v.competencia = r.mes_1),
  '(1,1)',
  'distrato sem data de cancelamento cai no mês da venda'
);

select is(
  (select vgv_vendido from marts.vso_mensal v, referencia r
   where v.centro_custo_id = '0c000000-0000-4000-8000-0000000000d2' and v.competencia = r.mes_3),
  600000::numeric,
  'VGV vendido do mês soma todos os contratos assinados nele'
);

select is(
  (select array_agg(estoque_inicio_mes order by competencia) from marts.vso_mensal
   where centro_custo_id = '0c000000-0000-4000-8000-0000000000d2'),
  array[5, 3, 3, 3],
  'unidade distratada volta ao estoque no mês seguinte ao cancelamento'
);

select is(
  (select vso_pct from marts.vso_mensal v, referencia r
   where v.centro_custo_id = '0c000000-0000-4000-8000-0000000000d2' and v.competencia = r.mes_0),
  -0.3333::numeric,
  'mês com mais distrato que venda tem VSO negativa'
);

select is(
  (select count(*) from marts.vso_mensal where centro_custo_id = '0c000000-0000-4000-8000-0000000000d3'),
  9::bigint,
  'calendário vai do primeiro contrato até o mês atual'
);

select is(
  (select vso_pct from marts.vso_mensal v, referencia r
   where v.centro_custo_id = '0c000000-0000-4000-8000-0000000000d3' and v.competencia = r.mes_8),
  null::numeric,
  'sem unidade em oferta não há denominador e a taxa fica nula'
);

select is(
  (select count(*) from marts.vso_mensal where centro_custo_id = '0c000000-0000-4000-8000-0000000000d4'),
  0::bigint,
  'obra sem contrato não tem calendário'
);

select is(
  (select vendas_media_6m from marts.cobertura_orcamento_obra where centro_custo_id = '0c000000-0000-4000-8000-0000000000d1'),
  0.67::numeric,
  'média de seis meses usa o calendário disponível com zeros'
);

select is(
  (select row(unidades_para_cobrir, meses_para_cobrir)::text from marts.cobertura_orcamento_obra
   where centro_custo_id = '0c000000-0000-4000-8000-0000000000d1'),
  '(3,4.5)',
  'meses para cobrir divide as unidades que faltam pela média sem arredondar antes'
);

select is(
  (select row(vendas_media_6m, unidades_para_cobrir, meses_para_cobrir)::text from marts.cobertura_orcamento_obra
   where centro_custo_id = '0c000000-0000-4000-8000-0000000000d2'),
  '(0.25,3,12.0)',
  'distrato reduz o ritmo de vendas líquidas'
);

select is(
  (select row(vendas_media_6m, meses_para_cobrir)::text from marts.cobertura_orcamento_obra
   where centro_custo_id = '0c000000-0000-4000-8000-0000000000d3'),
  '(0.00,0)',
  'obra já coberta tem zero meses mesmo sem venda recente'
);

select is(
  (select row(vendas_media_6m, meses_para_cobrir)::text from marts.cobertura_orcamento_obra
   where centro_custo_id = '0c000000-0000-4000-8000-0000000000d4'),
  '(,)',
  'obra sem venda não tem ritmo nem projeção'
);

select ok(
  (select 'security_invoker=true' = any(reloptions) from pg_class where oid = 'marts.vso_mensal'::regclass),
  'vso_mensal respeita o RLS de quem consulta'
);

select ok(
  (select 'security_invoker=true' = any(reloptions) from pg_class where oid = 'marts.cobertura_orcamento_obra'::regclass),
  'cobertura_orcamento_obra respeita o RLS de quem consulta'
);

select has_index('staging', 'contrato_venda', 'contrato_venda_obra_data_venda_idx',
  array['tenant_id', 'centro_custo_id', 'data_venda'], 'contratos têm índice pela obra, usado pela política e pela VSO');

select has_index('staging', 'unidade', 'unidade_obra_idx',
  array['tenant_id', 'centro_custo_id'], 'unidades têm índice pela obra, usado pela política e pela oferta');

select * from finish();
rollback;
