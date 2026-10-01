-- Comparativo entre obras: uma linha por obra com os indicadores que a tela /obras põe lado a lado.
-- Só junta marts que já existem; cada número segue a regra do mart de onde vem, para a tela de
-- comparação não divergir da tela da obra. Roda como quem consulta, então o gerente vê só a obra dele.

-- O(o x m) com o obras e m meses do vso_mensal; o custo real é o dos marts de origem, que já leem por obra.
create view marts.comparativo_obras with (security_invoker = true) as
with vso_12m as (
  -- a conta da 0015 aplicada à janela: vendas líquidas dos 12 meses sobre o estoque no início do primeiro mês
  select distinct on (tenant_id, centro_custo_id) tenant_id, centro_custo_id,
    sum(vendas_liquidas) over obra as vendas_liquidas_12m,
    estoque_inicio_mes as estoque_inicio_12m
  from marts.vso_mensal
  where competencia > date_trunc('month', current_date) - interval '12 months'
  window obra as (partition by tenant_id, centro_custo_id)
  order by tenant_id, centro_custo_id, competencia
), ultima_execucao as (
  -- O calendário da 0019 termina no mês atual, então é o mesmo mês que o alerta pago_a_frente_do_fisico olha.
  -- Filtrar o mês evita somar o pago acumulado de todos os meses só para descartar (300 ms viram 20 na demo).
  select tenant_id, centro_custo_id, competencia, pct_fisico, pct_financeiro, diferenca_financeiro_fisico
  from marts.execucao_fisica_obra
  where competencia = date_trunc('month', current_date)
), alertas as (
  select tenant_id, centro_custo_id, count(*)::integer as alertas
  from marts.alertas_obra
  group by 1, 2
)
select p.tenant_id, p.centro_custo_id, p.obra,
  p.vgv_total, p.vgv_vendido, p.pct_vgv_vendido,
  coalesce(v.vendas_liquidas_12m, 0)::integer as vendas_liquidas_12m,
  v.estoque_inicio_12m,
  case when v.estoque_inicio_12m > 0 then round(v.vendas_liquidas_12m::numeric / v.estoque_inicio_12m, 4) end as vso_12m,
  coalesce(e.unidades_estoque, 0)::integer as unidades_estoque,
  coalesce(e.valor_estoque, 0) as valor_estoque,
  e.meses_para_vender_estoque,
  p.resultado_projetado,
  case when p.vgv_total > 0 then round(p.resultado_projetado / p.vgv_total, 4) end as margem_projetada,
  p.exposicao_maxima,
  p.caixa_atual,
  p.vencido_direto,
  -- mesma fração do alerta inadimplencia_alta da 0024: vencido sobre a carteira direta inteira
  round(p.vencido_direto / nullif(p.recebido_direto + p.a_receber_direto + p.vencido_direto, 0), 4) as pct_inadimplencia,
  p.repasse_atrasado,
  x.competencia as competencia_execucao,
  x.pct_fisico,
  x.pct_financeiro,
  x.diferenca_financeiro_fisico,
  coalesce(a.alertas, 0) as alertas
from marts.posicao_financeira_obra p
left join vso_12m v on v.tenant_id = p.tenant_id and v.centro_custo_id = p.centro_custo_id
left join marts.estoque_obra e on e.tenant_id = p.tenant_id and e.centro_custo_id = p.centro_custo_id
left join ultima_execucao x on x.tenant_id = p.tenant_id and x.centro_custo_id = p.centro_custo_id
left join alertas a on a.tenant_id = p.tenant_id and a.centro_custo_id = p.centro_custo_id;

grant select on marts.comparativo_obras to authenticated;
