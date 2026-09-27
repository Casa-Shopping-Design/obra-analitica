-- VGV da obra na posição financeira. Sai do mesmo mapa de unidades que dá o estoque, então
-- vgv_total é sempre vgv_vendido mais estoque_a_vender, sem diferença de arredondamento entre telas.
-- Unidade fora de venda (permuta, bloqueio) não entra: não vai virar receita.

-- create or replace só aceita coluna nova no fim; as antigas ficam na mesma ordem e tipo da 0005.
create or replace view marts.posicao_financeira_obra with (security_invoker = true) as
with fluxo as (
  select tenant_id, centro_custo_id,
    sum(entrada_direta_realizada) as recebido_direto,
    sum(repasse_realizado) as recebido_repasse,
    sum(entrada_direta_prevista) as a_receber_direto,
    sum(repasse_previsto) as a_receber_repasse,
    sum(entrada_direta_vencida) as vencido_direto,
    sum(repasse_vencido) as repasse_atrasado,
    sum(saida_realizada) as pago,
    sum(saida_prevista + saida_vencida) as a_pagar,
    min(saldo_acumulado) as menor_saldo_acumulado
  from marts.fluxo_caixa_mensal
  group by 1, 2
), orcamento as (
  select tenant_id, centro_custo_id, sum(valor_total) as custo_orcado
  from staging.item_orcamento
  group by 1, 2
), unidades as (
  select tenant_id, centro_custo_id,
    sum(valor) filter (where situacao in ('disponivel', 'reservada', 'proposta')) as estoque_a_vender,
    sum(valor) filter (where situacao = 'vendida') as vgv_vendido
  from marts.mapa_unidades
  group by 1, 2
), base as (
  select cc.tenant_id, cc.id as centro_custo_id, cc.nome as obra,
    coalesce(f.recebido_direto, 0) as recebido_direto,
    coalesce(f.recebido_repasse, 0) as recebido_repasse,
    coalesce(f.a_receber_direto, 0) as a_receber_direto,
    coalesce(f.a_receber_repasse, 0) as a_receber_repasse,
    coalesce(f.vencido_direto, 0) as vencido_direto,
    coalesce(f.repasse_atrasado, 0) as repasse_atrasado,
    coalesce(u.estoque_a_vender, 0) as estoque_a_vender,
    coalesce(u.vgv_vendido, 0) as vgv_vendido,
    coalesce(f.pago, 0) as pago,
    coalesce(f.a_pagar, 0) as a_pagar,
    coalesce(o.custo_orcado, 0) as custo_orcado,
    least(coalesce(f.menor_saldo_acumulado, 0), 0) as menor_saldo_acumulado
  from app.centro_custo cc
  left join fluxo f on f.tenant_id = cc.tenant_id and f.centro_custo_id = cc.id
  left join orcamento o on o.tenant_id = cc.tenant_id and o.centro_custo_id = cc.id
  left join unidades u on u.tenant_id = cc.tenant_id and u.centro_custo_id = cc.id
)
select b.tenant_id, b.centro_custo_id, b.obra,
  b.recebido_direto, b.recebido_repasse, b.a_receber_direto, b.a_receber_repasse, b.vencido_direto, b.repasse_atrasado,
  b.estoque_a_vender,
  b.pago, b.a_pagar, b.custo_orcado,
  greatest(b.custo_orcado - b.pago - b.a_pagar, 0) as custo_a_incorrer,
  greatest(b.pago + b.a_pagar - b.custo_orcado, 0) as estouro_orcamento,
  b.recebido_direto + b.recebido_repasse - b.pago as caixa_atual,
  -b.menor_saldo_acumulado as exposicao_maxima,
  b.recebido_direto + b.recebido_repasse + b.a_receber_direto + b.a_receber_repasse + b.vencido_direto
    + b.repasse_atrasado
    - greatest(b.custo_orcado, b.pago + b.a_pagar) as resultado_contratado,
  b.recebido_direto + b.recebido_repasse + b.a_receber_direto + b.a_receber_repasse + b.vencido_direto
    + b.repasse_atrasado
    + b.estoque_a_vender - greatest(b.custo_orcado, b.pago + b.a_pagar) as resultado_projetado,
  b.vgv_vendido,
  b.vgv_vendido + b.estoque_a_vender as vgv_total,
  case when b.vgv_vendido + b.estoque_a_vender > 0
       then round(b.vgv_vendido / (b.vgv_vendido + b.estoque_a_vender), 4) end as pct_vgv_vendido
from base b;
