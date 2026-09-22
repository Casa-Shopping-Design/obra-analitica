-- Marts: views comuns com security_invoker, entao o RLS das tabelas de staging vale aqui.
-- Sao estas views que o painel consulta e que entram no catalogo do assistente.

create or replace view marts.consolidado_centro_custo with (security_invoker = true) as
select
  cc.tenant_id,
  cc.id as centro_custo_id,
  cc.nome as obra,
  (select coalesce(sum(valor), 0) from staging.contrato_venda c where c.centro_custo_id = cc.id and c.situacao = '1') as receita_contratada,
  (select coalesce(sum(valor_recebido), 0) from staging.parcela_receber p where p.centro_custo_id = cc.id) as receita_recebida,
  (select coalesce(sum(saldo_corrigido), 0) from staging.parcela_receber p where p.centro_custo_id = cc.id) as saldo_a_receber,
  (select coalesce(sum(valor_total), 0) from staging.item_orcamento o where o.centro_custo_id = cc.id) as custo_orcado,
  (select coalesce(sum(valor_original), 0) from staging.titulo_pagar t where t.centro_custo_id = cc.id and t.data_pagamento is not null) as custo_realizado,
  (select coalesce(sum(saldo), 0) from staging.titulo_pagar t where t.centro_custo_id = cc.id) as saldo_a_pagar
from app.centro_custo cc;

create or replace view marts.fluxo_caixa_mensal with (security_invoker = true) as
with receber as (
  select tenant_id, centro_custo_id, date_trunc('month', vencimento)::date as competencia, origem,
         sum(valor_original) as previsto, sum(coalesce(valor_recebido, 0)) as realizado
  from staging.parcela_receber
  group by 1, 2, 3, 4
), pagar as (
  select tenant_id, centro_custo_id, date_trunc('month', vencimento)::date as competencia,
         sum(valor_original) as previsto, sum(case when data_pagamento is not null then valor_original else 0 end) as realizado
  from staging.titulo_pagar
  group by 1, 2, 3
)
select
  coalesce(r.tenant_id, p.tenant_id) as tenant_id,
  coalesce(r.centro_custo_id, p.centro_custo_id) as centro_custo_id,
  coalesce(r.competencia, p.competencia) as competencia,
  sum(case when r.origem = 'direta' then r.previsto else 0 end) as receita_direta_prevista,
  sum(case when r.origem = 'direta' then r.realizado else 0 end) as receita_direta_realizada,
  sum(case when r.origem = 'repasse' then r.previsto else 0 end) as repasse_previsto,
  sum(case when r.origem = 'repasse' then r.realizado else 0 end) as repasse_realizado,
  max(coalesce(p.previsto, 0)) as desembolso_previsto,
  max(coalesce(p.realizado, 0)) as desembolso_realizado
from receber r
full join pagar p on p.tenant_id = r.tenant_id and p.centro_custo_id = r.centro_custo_id and p.competencia = r.competencia
group by 1, 2, 3;

create or replace view marts.vso_mensal with (security_invoker = true) as
select tenant_id, centro_custo_id, date_trunc('month', data_venda)::date as competencia,
       count(*) filter (where situacao = '1') as vendas,
       count(*) filter (where situacao = '3') as distratos,
       sum(valor) filter (where situacao = '1') as vgv_vendido
from staging.contrato_venda
group by 1, 2, 3;

create or replace view marts.estoque_atual with (security_invoker = true) as
select tenant_id, centro_custo_id, tipologia,
       count(*) filter (where situacao = 'D') as disponiveis,
       count(*) filter (where situacao = 'R') as reservadas,
       count(*) filter (where situacao = 'V') as vendidas,
       count(*) as total
from staging.unidade
group by 1, 2, 3;

create or replace view marts.break_even_obra with (security_invoker = true) as
with base as (
  select cc.tenant_id, cc.id as centro_custo_id, cc.nome as obra,
    (select coalesce(sum(valor_total), 0) from staging.item_orcamento o where o.centro_custo_id = cc.id) as custo_total,
    (select coalesce(sum(valor), 0) from staging.contrato_venda c where c.centro_custo_id = cc.id and c.situacao = '1') as vgv_vendido,
    (select avg(valor) from staging.contrato_venda c where c.centro_custo_id = cc.id and c.situacao = '1') as ticket_medio,
    (select avg(vendas) from marts.vso_mensal v where v.centro_custo_id = cc.id and v.competencia >= (current_date - interval '6 months')) as vso_media_6m
  from app.centro_custo cc
)
select *,
  case when custo_total > 0 then round(vgv_vendido / custo_total, 4) end as pct_atingido,
  case when ticket_medio > 0 then greatest(0, ceil((custo_total - vgv_vendido) / ticket_medio)) end as unidades_faltantes,
  case when vso_media_6m > 0 and ticket_medio > 0
       then round(greatest(0, (custo_total - vgv_vendido) / ticket_medio) / vso_media_6m, 1) end as meses_para_break_even
from base;

-- Cenario de atraso de repasse: desloca a curva de repasse ainda nao realizada em N meses.
create or replace function marts.fluxo_caixa_cenario(p_meses_atraso integer default 0)
returns table (centro_custo_id uuid, competencia date, receita_direta numeric, repasse numeric, desembolso numeric)
language sql stable security invoker as $$
  select centro_custo_id,
         case when repasse_realizado = 0 and repasse_previsto > 0
              then (competencia + (p_meses_atraso || ' months')::interval)::date
              else competencia end,
         sum(receita_direta_prevista), sum(repasse_previsto), sum(desembolso_previsto)
  from marts.fluxo_caixa_mensal
  group by 1, 2
  order by 1, 2
$$;

grant select on all tables in schema marts to authenticated;
grant execute on function marts.fluxo_caixa_cenario(integer) to authenticated;
