-- Resumo da DRE de viabilidade somado por tenant, para a faixa de resultado da visão geral (plano APO, etapa 4).
-- Soma só as obras com estudo que quem consulta vê: o RLS do estudo deixa a view vazia para quem não é diretor
-- nem financeiro, sem predicado de perfil aqui.

-- A margem da carteira é o lucro operacional somado sobre o VGV líquido somado, e não a média das margens.
-- O VGV líquido não está em dre_resumo_obra; vem da linha vgv_liquido de dre_viabilidade, uma por obra.
create view marts.dre_resumo_carteira with (security_invoker = true) as
with soma as (
  select r.tenant_id,
    count(*) as obras,
    sum(r.vgv_bruto_tendencia) as vgv_bruto_tendencia,
    sum(r.vgv_vendido) as vgv_vendido,
    sum(r.receita_apropriada) as receita_apropriada,
    sum(r.custo_apropriado) as custo_apropriado,
    sum(r.recebido_acumulado) as recebido_acumulado,
    sum(r.lucro_operacional_viabilidade) as lucro_operacional_viabilidade,
    sum(r.lucro_operacional_tendencia) as lucro_operacional_tendencia,
    sum(l.viabilidade) as vgv_liquido_viabilidade,
    sum(l.tendencia) as vgv_liquido_tendencia
  from marts.dre_resumo_obra r
  join marts.dre_viabilidade l
    on l.tenant_id = r.tenant_id and l.centro_custo_id = r.centro_custo_id and l.linha = 'vgv_liquido'
  group by r.tenant_id
), margem as (
  select s.*,
    round(s.lucro_operacional_viabilidade / nullif(s.vgv_liquido_viabilidade, 0), 4) as margem_operacional_viabilidade,
    round(s.lucro_operacional_tendencia / nullif(s.vgv_liquido_tendencia, 0), 4) as margem_operacional_tendencia
  from soma s
)
select tenant_id, obras, vgv_bruto_tendencia, vgv_vendido,
  round(vgv_vendido / nullif(vgv_bruto_tendencia, 0), 4) as pct_vendido,
  receita_apropriada,
  round(receita_apropriada / nullif(vgv_vendido, 0), 4) as poc,
  custo_apropriado, recebido_acumulado,
  lucro_operacional_viabilidade, lucro_operacional_tendencia,
  margem_operacional_viabilidade, margem_operacional_tendencia,
  margem_operacional_tendencia - margem_operacional_viabilidade as desvio_margem_operacional
from margem;

grant select on marts.dre_resumo_carteira to authenticated;
