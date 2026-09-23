-- Tudo que entra e sai de cada obra, pelo dia em que o dinheiro se move.
-- Entradas separadas em direta (comprador paga à construtora) e repasse (banco paga o financiamento).
-- Saídas: títulos pagos, títulos lançados a pagar e o orçamento que ainda não virou título.

-- Recriados porque a versão da 0003 agrupava o realizado pelo vencimento, somava saldo de contrato
-- distratado e, no cenário, empurrava o mês inteiro junto com o repasse.
drop function if exists marts.fluxo_caixa_cenario(integer);
drop view if exists marts.fluxo_caixa_mensal;

-- Regra do saldo projetado, conservadora dos dois lados: a receber vencido não entra no caixa
-- (fica nas colunas de vencido: atraso do comprador ou do banco), a pagar vencido entra no mês em que venceu.
create view marts.fluxo_caixa_mensal with (security_invoker = true) as
with movimento as (
  select p.tenant_id, p.centro_custo_id, date_trunc('month', p.data_recebimento)::date as competencia,
         p.origem, 'entrada_realizada' as tipo, p.valor_recebido as valor
  from staging.parcela_receber p
  where p.data_recebimento is not null and p.valor_recebido > 0
  union all
  select p.tenant_id, p.centro_custo_id, date_trunc('month', p.vencimento)::date, p.origem,
         case when p.vencimento < current_date then 'entrada_vencida' else 'entrada_prevista' end,
         coalesce(p.saldo_corrigido, p.saldo)
  from staging.parcela_receber p
  left join staging.contrato_venda c on c.tenant_id = p.tenant_id and c.id_origem = p.contrato_id_origem
  where coalesce(p.saldo_corrigido, p.saldo) > 0 and c.situacao is distinct from '3'
  union all
  select t.tenant_id, t.centro_custo_id, date_trunc('month', t.data_pagamento)::date, null,
         'saida_realizada', t.valor_original - coalesce(t.saldo, 0)
  from staging.titulo_pagar t
  where t.data_pagamento is not null
  union all
  select t.tenant_id, t.centro_custo_id, date_trunc('month', t.vencimento)::date, null,
         case when t.vencimento < current_date then 'saida_vencida' else 'saida_prevista' end, t.saldo
  from staging.titulo_pagar t
  where t.saldo > 0
), mensal as (
  select tenant_id, centro_custo_id, competencia,
    coalesce(sum(valor) filter (where tipo = 'entrada_realizada' and origem = 'direta'), 0) as entrada_direta_realizada,
    coalesce(sum(valor) filter (where tipo = 'entrada_realizada' and origem = 'repasse'), 0) as repasse_realizado,
    coalesce(sum(valor) filter (where tipo = 'entrada_prevista' and origem = 'direta'), 0) as entrada_direta_prevista,
    coalesce(sum(valor) filter (where tipo = 'entrada_prevista' and origem = 'repasse'), 0) as repasse_previsto,
    coalesce(sum(valor) filter (where tipo = 'entrada_vencida' and origem = 'direta'), 0) as entrada_direta_vencida,
    coalesce(sum(valor) filter (where tipo = 'entrada_vencida' and origem = 'repasse'), 0) as repasse_vencido,
    coalesce(sum(valor) filter (where tipo = 'saida_realizada'), 0) as saida_realizada,
    coalesce(sum(valor) filter (where tipo = 'saida_prevista'), 0) as saida_prevista,
    coalesce(sum(valor) filter (where tipo = 'saida_vencida'), 0) as saida_vencida
  from movimento
  group by 1, 2, 3
)
select m.*,
  m.entrada_direta_realizada + m.repasse_realizado + m.entrada_direta_prevista + m.repasse_previsto
    - m.saida_realizada - m.saida_prevista - m.saida_vencida as saldo_mes,
  sum(m.entrada_direta_realizada + m.repasse_realizado + m.entrada_direta_prevista + m.repasse_previsto
      - m.saida_realizada - m.saida_prevista - m.saida_vencida)
    over (partition by m.tenant_id, m.centro_custo_id order by m.competencia) as saldo_acumulado
from mensal m;

-- Atraso de repasse: só a parte de repasse ainda não recebida anda N meses; o resto fica no lugar.
create function marts.fluxo_caixa_cenario(p_meses_atraso integer default 0)
returns table (centro_custo_id uuid, competencia date, entrada_direta numeric, repasse numeric,
               saida numeric, saldo_acumulado numeric)
language sql stable security invoker set search_path = '' as $$
  with deslocado as (
    select f.centro_custo_id, f.competencia,
           f.entrada_direta_realizada + f.entrada_direta_prevista as entrada_direta,
           f.repasse_realizado as repasse,
           f.saida_realizada + f.saida_prevista + f.saida_vencida as saida
    from marts.fluxo_caixa_mensal f
    union all
    select f.centro_custo_id, (f.competencia + make_interval(months => p_meses_atraso))::date, 0, f.repasse_previsto, 0
    from marts.fluxo_caixa_mensal f
    where f.repasse_previsto > 0
  ), mensal as (
    select d.centro_custo_id, d.competencia, sum(d.entrada_direta) as entrada_direta,
           sum(d.repasse) as repasse, sum(d.saida) as saida
    from deslocado d
    group by 1, 2
  )
  select m.centro_custo_id, m.competencia, m.entrada_direta, m.repasse, m.saida,
         sum(m.entrada_direta + m.repasse - m.saida) over (partition by m.centro_custo_id order by m.competencia)
  from mensal m
  order by 1, 2
$$;

-- Posição da obra hoje e até o fim: quanto entrou, quanto falta entrar (contratado e estoque),
-- quanto saiu, quanto falta sair e quanto dinheiro próprio a obra exige no pior mês.
create view marts.posicao_financeira_obra with (security_invoker = true) as
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
), estoque as (
  select tenant_id, centro_custo_id, sum(valor) as estoque_a_vender
  from marts.mapa_unidades
  where situacao in ('disponivel', 'reservada', 'proposta')
  group by 1, 2
), base as (
  select cc.tenant_id, cc.id as centro_custo_id, cc.nome as obra,
    coalesce(f.recebido_direto, 0) as recebido_direto,
    coalesce(f.recebido_repasse, 0) as recebido_repasse,
    coalesce(f.a_receber_direto, 0) as a_receber_direto,
    coalesce(f.a_receber_repasse, 0) as a_receber_repasse,
    coalesce(f.vencido_direto, 0) as vencido_direto,
    coalesce(f.repasse_atrasado, 0) as repasse_atrasado,
    coalesce(e.estoque_a_vender, 0) as estoque_a_vender,
    coalesce(f.pago, 0) as pago,
    coalesce(f.a_pagar, 0) as a_pagar,
    coalesce(o.custo_orcado, 0) as custo_orcado,
    least(coalesce(f.menor_saldo_acumulado, 0), 0) as menor_saldo_acumulado
  from app.centro_custo cc
  left join fluxo f on f.tenant_id = cc.tenant_id and f.centro_custo_id = cc.id
  left join orcamento o on o.tenant_id = cc.tenant_id and o.centro_custo_id = cc.id
  left join estoque e on e.tenant_id = cc.tenant_id and e.centro_custo_id = cc.id
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
    + b.estoque_a_vender - greatest(b.custo_orcado, b.pago + b.a_pagar) as resultado_projetado
from base b;

grant select on marts.fluxo_caixa_mensal, marts.posicao_financeira_obra to authenticated;
revoke execute on function marts.fluxo_caixa_cenario(integer) from public, anon;
grant execute on function marts.fluxo_caixa_cenario(integer) to authenticated;
