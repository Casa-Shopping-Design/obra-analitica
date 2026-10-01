-- Obra sem data de entrega saía com meses_ate_entrega = 0, porque greatest ignora nulo, e o alerta
-- estoque_apos_entrega disparava para ela. Sem data, o prazo fica nulo, como o catálogo já dizia.
create or replace view marts.estoque_obra with (security_invoker = true) as
with estoque as (
  select tenant_id, centro_custo_id,
    count(*) filter (where situacao in ('disponivel', 'reservada', 'proposta')) as unidades_estoque,
    coalesce(sum(valor) filter (where situacao in ('disponivel', 'reservada', 'proposta')), 0) as valor_estoque,
    count(*) filter (where situacao = 'vendida') as unidades_vendidas
  from marts.mapa_unidades
  group by 1, 2
), entrega as (
  select tenant_id, centro_custo_id, max(data_entrega) as data_entrega
  from staging.unidade
  group by 1, 2
), base as (
  select cc.tenant_id, cc.id as centro_custo_id, cc.nome as obra,
    coalesce(e.unidades_estoque, 0) as unidades_estoque,
    coalesce(e.valor_estoque, 0) as valor_estoque,
    coalesce(e.unidades_vendidas, 0) as unidades_vendidas,
    c.vendas_media_6m,
    en.data_entrega,
    (extract(year from en.data_entrega) * 12 + extract(month from en.data_entrega))
      - (extract(year from current_date) * 12 + extract(month from current_date)) as meses_ate_entrega
  from app.centro_custo cc
  left join estoque e on e.tenant_id = cc.tenant_id and e.centro_custo_id = cc.id
  left join entrega en on en.tenant_id = cc.tenant_id and en.centro_custo_id = cc.id
  left join marts.cobertura_orcamento_obra c on c.tenant_id = cc.tenant_id and c.centro_custo_id = cc.id
)
select tenant_id, centro_custo_id, obra, unidades_estoque, valor_estoque, unidades_vendidas,
  case when unidades_estoque > 0 then round(valor_estoque / unidades_estoque, 2) end as preco_medio_estoque,
  vendas_media_6m,
  -- sem venda líquida positiva no período não há ritmo para projetar; nulo em vez de infinito
  case when unidades_estoque = 0 then 0
       when vendas_media_6m > 0 then round(unidades_estoque / vendas_media_6m, 1) end as meses_para_vender_estoque,
  data_entrega,
  case when meses_ate_entrega is not null then greatest(meses_ate_entrega, 0) end::integer as meses_ate_entrega
from base;
