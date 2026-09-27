-- VSO sobre calendário contínuo: mês sem venda aparece com zero, distrato cai no mês do cancelamento
-- e a taxa divide as vendas líquidas pelo estoque que havia no início do mês (ver docs/decisoes/0003).

-- A política leitura_por_obra e as junções abaixo filtram por centro_custo_id, que nessas duas
-- tabelas não tinha índice: a chave começa por tenant_id e segue por id_origem.
create index contrato_venda_obra_data_venda_idx on staging.contrato_venda (tenant_id, centro_custo_id, data_venda);
create index unidade_obra_idx on staging.unidade (tenant_id, centro_custo_id);

-- create or replace só aceita coluna nova no fim; as seis da 0003 ficam na mesma ordem e tipo.
-- O(c + m) por obra, com c contratos e m meses do calendário: uma agregação por mês e uma janela.
create or replace view marts.vso_mensal with (security_invoker = true) as
with contratos as (
  select tenant_id, centro_custo_id, data_venda, valor, situacao,
    -- distrato sem data de cancelamento na origem cai no mês da venda, para não inflar a venda líquida
    case when situacao = '3' then coalesce(data_distrato, data_venda) end as data_cancelamento
  from staging.contrato_venda
  -- mesmo universo de contratos do VGV e da cobertura: ativo ou distratado, nada em outra situação
  where data_venda is not null and situacao in ('1', '3')
), calendario as (
  select tenant_id, centro_custo_id, competencia::date as competencia
  from (
    select tenant_id, centro_custo_id, min(date_trunc('month', data_venda)) as primeiro_mes
    from contratos
    group by 1, 2
  ) inicio,
  lateral generate_series(inicio.primeiro_mes, date_trunc('month', current_date), interval '1 month') as competencia
), vendas as (
  select tenant_id, centro_custo_id, date_trunc('month', data_venda)::date as competencia,
    count(*) as vendas, sum(valor) as vgv_vendido
  from contratos
  group by 1, 2, 3
), distratos as (
  select tenant_id, centro_custo_id, date_trunc('month', data_cancelamento)::date as competencia,
    count(*) as distratos
  from contratos
  where data_cancelamento is not null
  group by 1, 2, 3
), oferta as (
  -- unidade fora de venda (permuta, bloqueio) não é oferta, como no VGV da 0011
  select tenant_id, centro_custo_id, count(*) as unidades_em_oferta
  from staging.unidade
  where situacao in ('D', 'C', 'P', 'V', 'O', 'G')
  group by 1, 2
), mensal as (
  select c.tenant_id, c.centro_custo_id, c.competencia,
    coalesce(v.vendas, 0) as vendas,
    coalesce(d.distratos, 0) as distratos,
    coalesce(v.vgv_vendido, 0) as vgv_vendido,
    coalesce(v.vendas, 0) - coalesce(d.distratos, 0) as vendas_liquidas,
    o.unidades_em_oferta
  from calendario c
  left join vendas v on v.tenant_id = c.tenant_id and v.centro_custo_id = c.centro_custo_id and v.competencia = c.competencia
  left join distratos d on d.tenant_id = c.tenant_id and d.centro_custo_id = c.centro_custo_id and d.competencia = c.competencia
  left join oferta o on o.tenant_id = c.tenant_id and o.centro_custo_id = c.centro_custo_id
), com_estoque as (
  select m.*,
    greatest(0, m.unidades_em_oferta - coalesce(sum(m.vendas_liquidas) over (
      partition by m.tenant_id, m.centro_custo_id order by m.competencia
      rows between unbounded preceding and 1 preceding), 0))::integer as estoque_inicio_mes
  from mensal m
)
select tenant_id, centro_custo_id, competencia, vendas, distratos, vgv_vendido,
  vendas_liquidas, estoque_inicio_mes,
  case when estoque_inicio_mes > 0 then round(vendas_liquidas::numeric / estoque_inicio_mes, 4) end as vso_pct
from com_estoque;

grant select on marts.vso_mensal to authenticated;

-- Mesmas colunas da 0006 na mesma ordem; a média de vendas e os meses entram no fim.
create or replace view marts.cobertura_orcamento_obra with (security_invoker = true) as
with orcamento as (
  select tenant_id, centro_custo_id, sum(valor_total) as custo_orcado
  from staging.item_orcamento
  group by 1, 2
), vendas as (
  select tenant_id, centro_custo_id, sum(valor) as vgv_contratado, avg(valor) as ticket_medio
  from staging.contrato_venda
  where situacao = '1'
  group by 1, 2
), ritmo as (
  -- seis meses do calendário, o atual incluído; mês sem venda entra como zero
  select tenant_id, centro_custo_id, avg(vendas_liquidas) as vendas_media_6m
  from marts.vso_mensal
  where competencia >= (date_trunc('month', current_date) - interval '5 months')::date
  group by 1, 2
), base as (
  select cc.tenant_id, cc.id as centro_custo_id, cc.nome as obra,
    coalesce(o.custo_orcado, 0) as custo_orcado,
    coalesce(v.vgv_contratado, 0) as vgv_contratado,
    case when o.custo_orcado > 0 then round(coalesce(v.vgv_contratado, 0) / o.custo_orcado, 4) end as pct_cobertura,
    round(v.ticket_medio, 2) as ticket_medio,
    case when v.ticket_medio > 0
         then greatest(0, ceil((coalesce(o.custo_orcado, 0) - v.vgv_contratado) / v.ticket_medio))::integer end as unidades_para_cobrir,
    r.vendas_media_6m
  from app.centro_custo cc
  left join orcamento o on o.tenant_id = cc.tenant_id and o.centro_custo_id = cc.id
  left join vendas v on v.tenant_id = cc.tenant_id and v.centro_custo_id = cc.id
  left join ritmo r on r.tenant_id = cc.tenant_id and r.centro_custo_id = cc.id
)
select tenant_id, centro_custo_id, obra, custo_orcado, vgv_contratado, pct_cobertura, ticket_medio,
  unidades_para_cobrir, round(vendas_media_6m, 2) as vendas_media_6m,
  -- sem venda líquida positiva no período não há ritmo para projetar; nulo em vez de infinito
  case when unidades_para_cobrir = 0 then 0
       when vendas_media_6m > 0 then round(unidades_para_cobrir / vendas_media_6m, 1) end as meses_para_cobrir
from base;

grant select on marts.cobertura_orcamento_obra to authenticated;
