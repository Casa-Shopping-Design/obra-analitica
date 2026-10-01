-- Repasse por banco e leads por origem, para a tela de vendas e para o assistente.

-- Parcela de financiamento é minoria entre as parcelas do tenant, e repasse_obra e repasse_banco só leem essa.
create index if not exists parcela_receber_repasse_idx on staging.parcela_receber (tenant_id, contrato_id_origem)
  where origem = 'repasse';

-- Repasse por obra e banco. Etapa, atraso e repasse atual seguem a regra da marts.repasse_obra (0018),
-- copiada aqui sem mudança: a soma dos bancos fecha com a obra, e o teste repasse_banco.sql confere.
-- Quem mudar a regra lá muda aqui também.
-- Parado em análise conta o repasse sem assinatura cuja situação no CRM não muda há mais de 60 dias;
-- a data é data_alteracao_situacao, porque o staging não guarda quando o repasse entrou em análise.
-- Sem essa data o repasse não entra na conta de parados.
-- O(r + p) por obra, com r repasses e p parcelas FI: uma agregação por contrato e uma por obra e banco.
create view marts.repasse_banco with (security_invoker = true) as
with contrato_fi as (
  select p.tenant_id, p.centro_custo_id, p.contrato_id_origem,
    sum(coalesce(p.saldo_corrigido, p.saldo)) filter (where p.vencimento < current_date) as vencido
  from staging.parcela_receber p
  left join staging.contrato_venda c on c.tenant_id = p.tenant_id and c.id_origem = p.contrato_id_origem
  where p.origem = 'repasse' and c.situacao is distinct from '3'
  group by 1, 2, 3
), repasse_atual as (
  select distinct on (r.tenant_id, coalesce(r.contrato_id_origem, -r.id_origem)) r.*
  from staging.repasse r
  left join staging.contrato_venda c on c.tenant_id = r.tenant_id and c.id_origem = r.contrato_id_origem
  where c.situacao is distinct from '3'
  order by r.tenant_id, coalesce(r.contrato_id_origem, -r.id_origem), r.data_alteracao_situacao desc nulls last, r.id_origem desc
), repasse_etapa as (
  select r.tenant_id, r.centro_custo_id, r.contrato_id_origem, r.valor_financiado,
    coalesce(nullif(btrim(r.banco), ''), 'Não informado') as banco,
    r.data_assinatura, r.data_recurso_liberado, r.data_alteracao_situacao,
    case when r.data_recurso_liberado is not null then 'liberado'
         when r.data_assinatura is not null then 'assinado'
         else 'em_analise' end as etapa,
    r.data_recurso_liberado is null and coalesce(f.vencido, 0) > 0 as atrasado
  from repasse_atual r
  left join contrato_fi f on f.tenant_id = r.tenant_id and f.contrato_id_origem = r.contrato_id_origem
)
select e.tenant_id, e.centro_custo_id, cc.nome as obra, e.banco,
  count(distinct e.contrato_id_origem) as contratos_com_repasse,
  count(*) filter (where e.etapa = 'em_analise') as repasses_em_analise,
  coalesce(sum(e.valor_financiado) filter (where e.etapa = 'em_analise'), 0) as valor_em_analise,
  count(*) filter (where e.etapa = 'assinado') as repasses_assinados,
  coalesce(sum(e.valor_financiado) filter (where e.etapa = 'assinado'), 0) as valor_assinado,
  count(*) filter (where e.etapa = 'liberado') as repasses_liberados,
  coalesce(sum(e.valor_financiado) filter (where e.etapa = 'liberado'), 0) as valor_liberado,
  count(*) filter (where e.atrasado) as repasses_atrasados,
  coalesce(sum(e.valor_financiado) filter (where e.atrasado), 0) as valor_atrasado,
  round(avg(e.data_recurso_liberado - e.data_assinatura)
    filter (where e.data_recurso_liberado is not null and e.data_assinatura is not null), 1) as dias_medios_assinatura_liberacao,
  count(*) filter (where e.etapa = 'em_analise' and e.data_alteracao_situacao < current_date - 60) as repasses_parados_analise,
  coalesce(sum(e.valor_financiado) filter (where e.etapa = 'em_analise' and e.data_alteracao_situacao < current_date - 60), 0)
    as valor_parado_analise
from repasse_etapa e
join app.centro_custo cc on cc.tenant_id = e.tenant_id and cc.id = e.centro_custo_id
group by e.tenant_id, e.centro_custo_id, cc.nome, e.banco;

-- Leads dos últimos 12 meses (o mês atual e os 11 anteriores, a mesma janela do funil da tela) por
-- obra, origem e mídia. Descartado é o lead com motivo de cancelamento ou com situação de descarte,
-- cancelamento ou perda; o nome da situação muda de cliente para cliente, o motivo não.
-- O lead não se liga à reserva no staging, então não há conversão por origem.
-- Motivo principal é o mais frequente entre os descartados com motivo; no empate, o primeiro em
-- ordem alfabética.
-- O(l log l) por obra, com l linhas diárias no período: duas agregações e uma ordenação por motivo.
create view marts.leads_origem with (security_invoker = true) as
-- Sem materializar, o filtro por obra da tela desce até a chave primária de lead_diario nas duas leituras.
with periodo as not materialized (
  select l.tenant_id, l.centro_custo_id, l.origem, l.midia, l.motivo_cancelamento, l.leads,
    l.motivo_cancelamento <> 'Sem cancelamento' or l.situacao ~* '(descart|cancel|perdid)' as descartado
  from staging.lead_diario l
  where l.dia >= (date_trunc('month', current_date) - interval '11 months')::date
), por_origem as (
  select tenant_id, centro_custo_id, origem, midia,
    sum(leads) as leads,
    coalesce(sum(leads) filter (where descartado), 0) as leads_descartados
  from periodo
  group by 1, 2, 3, 4
), motivo_principal as (
  select distinct on (tenant_id, centro_custo_id, origem, midia)
    tenant_id, centro_custo_id, origem, midia, motivo_cancelamento, leads
  from (
    select tenant_id, centro_custo_id, origem, midia, motivo_cancelamento, sum(leads) as leads
    from periodo
    where descartado and motivo_cancelamento <> 'Sem cancelamento'
    group by 1, 2, 3, 4, 5
  ) m
  order by tenant_id, centro_custo_id, origem, midia, leads desc, motivo_cancelamento
)
select o.tenant_id, o.centro_custo_id, cc.nome as obra, o.origem, o.midia,
  o.leads::integer as leads,
  o.leads_descartados::integer as leads_descartados,
  round(o.leads_descartados::numeric / nullif(o.leads, 0), 4) as pct_descartados,
  m.motivo_cancelamento as motivo_principal_descarte,
  m.leads::integer as leads_motivo_principal
from por_origem o
join app.centro_custo cc on cc.tenant_id = o.tenant_id and cc.id = o.centro_custo_id
left join motivo_principal m
  on m.tenant_id = o.tenant_id and m.centro_custo_id = o.centro_custo_id and m.origem = o.origem and m.midia = o.midia;

grant select on marts.repasse_banco, marts.leads_origem to authenticated;
