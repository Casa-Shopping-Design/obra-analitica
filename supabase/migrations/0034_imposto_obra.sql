-- Gestão de imposto por obra (plano APO, etapa 11, anexo D.2): a alíquota informada aplicada sobre as bases da
-- DRE de viabilidade. É estimativa, sem regra de regime; a apuração de verdade fica com o contador.
-- Não cria tabela. A view lê o estudo e a alíquota, que só abrem para diretor, financeiro e leitura nas
-- obras permitidas, e por isso herda a mesma restrição pelo dado, sem perfil no corpo.

-- A 0032 abriu a DRE para o perfil leitura, mas o mapa do ERP seguiu fechado a ele: a DRE e esta view caíam
-- no apropriado pelos títulos e o sócio via receita apropriada e imposto diferentes dos do diretor.
-- O mapa é dado de resultado e passa a abrir para os mesmos três perfis da DRE. A restritiva segundo_fator
-- da 0022 continua na tabela.
drop policy leitura_diretoria on staging.mapa_imobiliario_mensal;
create policy leitura_dre on staging.mapa_imobiliario_mensal for select to authenticated
  using (tenant_id = (select app.tenant_atual())
         and centro_custo_id in (select app.obras_permitidas())
         and (select app.perfil_atual()) in ('diretor', 'financeiro', 'leitura'));

-- Com o mapa aberto ao perfil leitura, a conferência contra o ERP deixaria de depender só do RLS da tabela
-- para ficar com diretor e financeiro. O perfil vai para o corpo da view; sem usuário (dono do banco, carga)
-- a leitura segue como antes, e o anônimo não tem grant nesta view. O resto da 0019 não muda.
create or replace view marts.conferencia_origem with (security_invoker = true) as
with ultimo as (
  select distinct on (tenant_id, centro_custo_id) *
  from staging.mapa_imobiliario_mensal
  where (select auth.uid()) is null or (select app.perfil_atual()) in ('diretor', 'financeiro')
  order by tenant_id, centro_custo_id, competencia desc
), fluxo as (
  select f.tenant_id, f.centro_custo_id,
    sum(f.entrada_direta_realizada + f.repasse_realizado) as recebido,
    sum(f.saida_realizada + f.saida_prevista + f.saida_vencida) as custo_incorrido
  from marts.fluxo_caixa_mensal f
  join ultimo u on u.tenant_id = f.tenant_id and u.centro_custo_id = f.centro_custo_id
  where f.competencia <= u.competencia
  group by 1, 2
), lado_a_lado as (
  select u.tenant_id, u.centro_custo_id, pf.obra, u.competencia as competencia_origem,
    coalesce(pf.vgv_total, 0) as vgv_painel, u.vgv as vgv_origem,
    coalesce(pf.custo_orcado, 0) as custo_orcado_painel, u.custo_orcado as custo_orcado_origem,
    round(coalesce(f.custo_incorrido, 0), 2) as custo_incorrido_painel, u.custo_incorrido_acumulado as custo_incorrido_origem,
    round(coalesce(f.recebido, 0), 2) as recebido_painel, u.recebido_acumulado as recebido_origem
  from ultimo u
  join marts.posicao_financeira_obra pf on pf.tenant_id = u.tenant_id and pf.centro_custo_id = u.centro_custo_id
  left join fluxo f on f.tenant_id = u.tenant_id and f.centro_custo_id = u.centro_custo_id
)
select tenant_id, centro_custo_id, obra, competencia_origem,
  vgv_painel, vgv_origem, vgv_painel - vgv_origem as diferenca_vgv,
  case when vgv_origem <> 0 then round((vgv_painel - vgv_origem) / vgv_origem, 4) end as diferenca_vgv_pct,
  custo_orcado_painel, custo_orcado_origem, custo_orcado_painel - custo_orcado_origem as diferenca_custo_orcado,
  custo_incorrido_painel, custo_incorrido_origem,
  custo_incorrido_painel - custo_incorrido_origem as diferenca_custo_incorrido,
  case when custo_incorrido_origem <> 0
       then round((custo_incorrido_painel - custo_incorrido_origem) / custo_incorrido_origem, 4) end as diferenca_custo_incorrido_pct,
  recebido_painel, recebido_origem, recebido_painel - recebido_origem as diferenca_recebido,
  case when recebido_origem <> 0 then round((recebido_painel - recebido_origem) / recebido_origem, 4) end as diferenca_recebido_pct
from lado_a_lado;

-- Uma linha por obra com estudo vigente e alíquota em vigor. A alíquota vigente segue o mesmo critério da
-- DRE (maior vigencia_inicio até hoje e, no empate, a gravada por último), para os dois números baterem.
-- O custo é o de marts.dre_viabilidade mais uma leitura da posição financeira e uma da alíquota por obra.
create view marts.imposto_obra with (security_invoker = true) as
with dre as (
  select d.tenant_id, d.centro_custo_id, d.obra, d.competencia,
    max(d.apropriado) filter (where d.linha = 'vgv_bruto') as receita_apropriada,
    max(d.a_apropriar) filter (where d.linha = 'vgv_bruto') as receita_a_apropriar,
    max(d.a_contratar) filter (where d.linha = 'vgv_bruto') as vgv_estoque,
    max(d.tendencia) filter (where d.linha = 'vgv_bruto') as vgv_total,
    max(d.viabilidade) filter (where d.linha = 'impostos') as imposto_viabilidade
  from marts.dre_viabilidade d
  where d.linha in ('vgv_bruto', 'impostos')
  group by d.tenant_id, d.centro_custo_id, d.obra, d.competencia
), aliquota as (
  select distinct on (a.tenant_id, a.centro_custo_id)
    a.tenant_id, a.centro_custo_id, a.aliquota, a.vigencia_inicio, a.criado_em
  from app.aliquota_imposto_obra a
  where a.vigencia_inicio <= current_date
  order by a.tenant_id, a.centro_custo_id, a.vigencia_inicio desc, a.criado_em desc, a.id desc
), base as (
  select d.tenant_id, d.centro_custo_id, d.obra, d.competencia,
    a.aliquota, a.vigencia_inicio as aliquota_vigencia_inicio, a.criado_em as aliquota_informada_em,
    d.vgv_total, d.receita_apropriada, d.receita_a_apropriar, d.vgv_estoque,
    p.recebido_direto + p.recebido_repasse as recebido_acumulado,
    d.imposto_viabilidade,
    round(a.aliquota * d.receita_apropriada, 2) as imposto_receita_apropriada,
    round(a.aliquota * (p.recebido_direto + p.recebido_repasse), 2) as imposto_recebimento,
    round(a.aliquota * d.vgv_estoque, 2) as imposto_vgv_estoque,
    round(a.aliquota * d.receita_a_apropriar, 2) as imposto_receita_a_apropriar,
    round(a.aliquota * d.vgv_total, 2) as imposto_vgv_total
  from dre d
  join aliquota a on a.tenant_id = d.tenant_id and a.centro_custo_id = d.centro_custo_id
  join marts.posicao_financeira_obra p on p.tenant_id = d.tenant_id and p.centro_custo_id = d.centro_custo_id
)
select tenant_id, centro_custo_id, obra, competencia,
  aliquota, aliquota_vigencia_inicio, aliquota_informada_em,
  vgv_total, receita_apropriada, receita_a_apropriar, vgv_estoque, recebido_acumulado,
  imposto_receita_apropriada,
  imposto_recebimento,
  -- Sinal do deck: negativo quando o recebido fica abaixo da receita apropriada.
  imposto_recebimento - imposto_receita_apropriada as imposto_diferido,
  imposto_vgv_estoque,
  imposto_receita_a_apropriar,
  imposto_vgv_total,
  imposto_receita_a_apropriar + imposto_vgv_estoque as imposto_a_realizar,
  imposto_viabilidade
from base;

grant select on marts.imposto_obra to authenticated;
