-- Estoque e ritmo de vendas por obra, carteira somada, alertas por obra e simulação da venda do estoque.
-- Tudo roda como quem consulta (security invoker): o RLS de staging decide quais obras entram em cada soma,
-- então o gerente vê a carteira do tamanho das obras dele.

-- Estoque por tipologia a preço de hoje. Estoque é disponível, reservada e proposta, como no VGV da 0011.
create view marts.estoque_tipologia with (security_invoker = true) as
select tenant_id, centro_custo_id, coalesce(tipologia, 'Sem tipologia') as tipologia,
  count(*) filter (where situacao = 'disponivel') as disponiveis,
  count(*) filter (where situacao = 'reservada') as reservadas,
  count(*) filter (where situacao = 'proposta') as propostas,
  count(*) filter (where situacao = 'vendida') as vendidas,
  count(*) filter (where situacao = 'indisponivel') as fora_de_venda,
  count(*) as total,
  coalesce(sum(valor) filter (where situacao in ('disponivel', 'reservada', 'proposta')), 0) as valor_estoque,
  round(avg(valor) filter (where situacao in ('disponivel', 'reservada', 'proposta')), 2) as preco_medio_estoque,
  round(
    sum(valor) filter (where situacao in ('disponivel', 'reservada', 'proposta') and area_privativa > 0)
    / nullif(sum(area_privativa) filter (where situacao in ('disponivel', 'reservada', 'proposta') and area_privativa > 0
                                          and valor is not null), 0),
    2) as preco_m2_estoque
from marts.mapa_unidades
group by 1, 2, 3;

-- Uma linha por obra: quanto sobra para vender, em quanto tempo no ritmo recente e quanto falta para a entrega.
-- O ritmo é o mesmo da cobertura do orçamento (0015), para as duas telas não darem prazos diferentes.
create view marts.estoque_obra with (security_invoker = true) as
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
  greatest(meses_ate_entrega, 0)::integer as meses_ate_entrega
from base;

-- A carteira soma as obras que o usuário vê. A exposição máxima da carteira não é a soma das exposições:
-- cada obra tem o pior mês num momento, então ela sai do saldo acumulado das obras juntas.
create view marts.posicao_carteira with (security_invoker = true) as
with saldo as (
  select tenant_id, competencia, sum(saldo_mes) as saldo_mes
  from marts.fluxo_caixa_mensal
  group by 1, 2
), acumulado as (
  select tenant_id, competencia,
    sum(saldo_mes) over (partition by tenant_id order by competencia) as saldo_acumulado
  from saldo
), pior_mes as (
  select distinct on (tenant_id) tenant_id, competencia, saldo_acumulado
  from acumulado
  order by tenant_id, saldo_acumulado, competencia
), soma as (
  select tenant_id,
    count(*) as obras,
    sum(vgv_total) as vgv_total,
    sum(vgv_vendido) as vgv_vendido,
    sum(estoque_a_vender) as estoque_a_vender,
    sum(caixa_atual) as caixa_atual,
    sum(resultado_projetado) as resultado_projetado,
    sum(vencido_direto) as vencido_direto,
    sum(repasse_atrasado) as repasse_atrasado,
    sum(a_receber_direto) as a_receber_direto,
    sum(a_receber_repasse) as a_receber_repasse,
    sum(a_pagar) as a_pagar,
    sum(estouro_orcamento) as estouro_orcamento,
    sum(exposicao_maxima) as soma_exposicao_obras
  from marts.posicao_financeira_obra
  group by 1
)
select s.tenant_id, s.obras, s.vgv_total, s.vgv_vendido,
  case when s.vgv_total > 0 then round(s.vgv_vendido / s.vgv_total, 4) end as pct_vgv_vendido,
  s.estoque_a_vender, s.caixa_atual, s.resultado_projetado, s.vencido_direto, s.repasse_atrasado,
  s.a_receber_direto, s.a_receber_repasse, s.a_pagar, s.estouro_orcamento,
  greatest(-coalesce(p.saldo_acumulado, 0), 0) as exposicao_maxima,
  case when p.saldo_acumulado < 0 then p.competencia end as mes_exposicao_maxima,
  s.soma_exposicao_obras
from soma s
left join pior_mes p on p.tenant_id = s.tenant_id;

-- Um alerta por linha, só os que dispararam. O texto fica na tela; aqui vão o tipo e os números.
--   estouro_orcamento: valor = estouro, referencia = custo orçado
--   repasse_atrasado: valor = repasse vencido e não pago
--   inadimplencia_alta: valor = vencido do comprador, referencia = fração da carteira direta (limite 5%)
--   pago_a_frente_do_fisico: valor = pontos de diferença, fração (limite 0,10, o mesmo da tela de execução)
--   estoque_apos_entrega: valor = meses para vender o estoque (nulo sem ritmo), referencia = meses até a entrega
create view marts.alertas_obra with (security_invoker = true) as
with ultima_execucao as (
  select distinct on (tenant_id, centro_custo_id) tenant_id, centro_custo_id, diferenca_financeiro_fisico
  from marts.execucao_fisica_obra
  order by tenant_id, centro_custo_id, competencia desc
), base as (
  select p.tenant_id, p.centro_custo_id, p.obra, p.estouro_orcamento, p.custo_orcado, p.repasse_atrasado,
    p.vencido_direto,
    p.vencido_direto / nullif(p.recebido_direto + p.a_receber_direto + p.vencido_direto, 0) as fracao_vencida,
    x.diferenca_financeiro_fisico,
    e.unidades_estoque, e.meses_para_vender_estoque, e.meses_ate_entrega
  from marts.posicao_financeira_obra p
  left join ultima_execucao x on x.tenant_id = p.tenant_id and x.centro_custo_id = p.centro_custo_id
  left join marts.estoque_obra e on e.tenant_id = p.tenant_id and e.centro_custo_id = p.centro_custo_id
)
select b.tenant_id, b.centro_custo_id, b.obra, a.tipo, a.valor, a.referencia
from base b
cross join lateral (values
  ('estouro_orcamento', b.estouro_orcamento, b.custo_orcado, b.estouro_orcamento > 0),
  ('repasse_atrasado', b.repasse_atrasado, null::numeric, b.repasse_atrasado > 0),
  ('inadimplencia_alta', b.vencido_direto, round(b.fracao_vencida, 4), b.fracao_vencida > 0.05),
  ('pago_a_frente_do_fisico', b.diferenca_financeiro_fisico, null, b.diferenca_financeiro_fisico > 0.10),
  ('estoque_apos_entrega', b.meses_para_vender_estoque, b.meses_ate_entrega::numeric,
     b.unidades_estoque > 0 and b.meses_ate_entrega is not null
     and (b.meses_para_vender_estoque is null or b.meses_para_vender_estoque > b.meses_ate_entrega))
) as a (tipo, valor, referencia, disparou)
where a.disparou;

-- Simula vender o estoque da obra a partir do mês que vem, p_unidades_mes por mês, pelo preço de tabela de
-- hoje com p_desconto. Proposta e reserva vendem primeiro, depois a unidade mais barata. Cada venda recebe
-- a parte do banco na proporção que o repasse tem nos contratos ativos da obra; a parte direta entra em
-- parcelas iguais até o mês anterior à entrega (depois da entrega, no mês da venda) e o repasse entra nas
-- chaves, ou dois meses depois da venda de unidade pronta. O saldo de partida é o fluxo da 0012.
-- O(u * m) linhas, com u unidades em estoque (centenas) e m meses até a entrega (dezenas).
create function marts.simular_venda_estoque(p_centro_custo_id uuid, p_unidades_mes numeric, p_desconto numeric default 0)
returns table (competencia date, entrada_direta_simulada numeric, repasse_simulado numeric,
               saldo_acumulado_atual numeric, saldo_acumulado_simulado numeric)
language sql stable security invoker set search_path = '' as $$
  with parametros as (
    select date_trunc('month', current_date)::date as mes_atual,
      least(greatest(coalesce(p_unidades_mes, 0), 0), 100) as ritmo,
      least(greatest(coalesce(p_desconto, 0), 0), 0.5) as desconto
  ), estoque as (
    select m.valor,
      row_number() over (
        order by case m.situacao when 'proposta' then 0 when 'reservada' then 1 else 2 end, m.valor, m.unidade_id
      ) - 1 as ordem
    from marts.mapa_unidades m
    where m.centro_custo_id = p_centro_custo_id
      and m.situacao in ('disponivel', 'reservada', 'proposta')
      and m.valor > 0
  ), obra as (
    select
      (select date_trunc('month', max(u.data_entrega))::date
         from staging.unidade u
        where u.centro_custo_id = p_centro_custo_id) as mes_entrega,
      (select coalesce(sum(pr.valor_original) filter (where pr.origem = 'repasse') / nullif(sum(pr.valor_original), 0), 0)
         from staging.parcela_receber pr
         join staging.contrato_venda c on c.tenant_id = pr.tenant_id and c.id_origem = pr.contrato_id_origem
        where pr.centro_custo_id = p_centro_custo_id and c.situacao = '1') as fracao_repasse
  ), venda as (
    select (pa.mes_atual + make_interval(months => 1 + floor(e.ordem / pa.ritmo)::integer))::date as mes_venda,
      e.valor * (1 - pa.desconto) as valor_venda
    from estoque e
    cross join parametros pa
    where pa.ritmo > 0
  ), prazo as (
    select v.mes_venda, v.valor_venda, o.mes_entrega, o.fracao_repasse,
      greatest(1, coalesce(
        (extract(year from o.mes_entrega) * 12 + extract(month from o.mes_entrega))
        - (extract(year from v.mes_venda) * 12 + extract(month from v.mes_venda)), 1))::integer as parcelas
    from venda v
    cross join obra o
  ), recebimento as (
    select (p.mes_venda + make_interval(months => i))::date as competencia,
      p.valor_venda * (1 - p.fracao_repasse) / p.parcelas as entrada_direta,
      0::numeric as repasse
    from prazo p
    cross join lateral generate_series(0, p.parcelas - 1) as i
    union all
    select greatest(p.mes_entrega, (p.mes_venda + interval '2 months')::date), 0, p.valor_venda * p.fracao_repasse
    from prazo p
    where p.fracao_repasse > 0
  ), simulado as (
    select r.competencia, sum(r.entrada_direta) as entrada_direta, sum(r.repasse) as repasse
    from recebimento r
    group by 1
  ), atual as (
    select f.competencia, f.saldo_mes
    from marts.fluxo_caixa_mensal f
    where f.centro_custo_id = p_centro_custo_id
  ), junto as (
    select coalesce(a.competencia, s.competencia) as competencia,
      coalesce(s.entrada_direta, 0) as entrada_direta,
      coalesce(s.repasse, 0) as repasse,
      coalesce(a.saldo_mes, 0) as saldo_mes
    from atual a
    full join simulado s on s.competencia = a.competencia
  )
  select j.competencia, round(j.entrada_direta, 2), round(j.repasse, 2),
    sum(j.saldo_mes) over janela,
    round(sum(j.saldo_mes + j.entrada_direta + j.repasse) over janela, 2)
  from junto j
  window janela as (order by j.competencia)
  order by j.competencia
$$;

-- Os números que a tela mostra ao lado do gráfico da simulação, tirados da mesma função.
create function marts.resumo_venda_estoque(p_centro_custo_id uuid, p_unidades_mes numeric, p_desconto numeric default 0)
returns table (unidades_estoque integer, mes_ultima_venda date, receita_simulada numeric,
               exposicao_atual numeric, mes_exposicao_atual date,
               exposicao_simulada numeric, mes_exposicao_simulada date,
               mes_saldo_positivo date)
language sql stable security invoker set search_path = '' as $$
  with serie as (
    select * from marts.simular_venda_estoque(p_centro_custo_id, p_unidades_mes, p_desconto)
  ), estoque as (
    select count(*)::integer as unidades
    from marts.mapa_unidades m
    where m.centro_custo_id = p_centro_custo_id
      and m.situacao in ('disponivel', 'reservada', 'proposta')
      and m.valor > 0
  ), pior_atual as (
    select s.competencia, s.saldo_acumulado_atual as saldo from serie s order by s.saldo_acumulado_atual, s.competencia limit 1
  ), pior_simulado as (
    select s.competencia, s.saldo_acumulado_simulado as saldo from serie s order by s.saldo_acumulado_simulado, s.competencia limit 1
  )
  select e.unidades,
    case when e.unidades > 0 and coalesce(p_unidades_mes, 0) > 0
         then (date_trunc('month', current_date)
               + make_interval(months => 1 + floor((e.unidades - 1) / least(p_unidades_mes, 100))::integer))::date end,
    (select coalesce(sum(s.entrada_direta_simulada + s.repasse_simulado), 0) from serie s),
    greatest(-coalesce(pa.saldo, 0), 0),
    case when pa.saldo < 0 then pa.competencia end,
    greatest(-coalesce(ps.saldo, 0), 0),
    case when ps.saldo < 0 then ps.competencia end,
    -- primeiro mês depois do pior mês em que o saldo simulado volta a zero ou mais
    (select min(s.competencia) from serie s
      where ps.saldo < 0 and s.competencia > ps.competencia and s.saldo_acumulado_simulado >= 0)
  from estoque e
  left join pior_atual pa on true
  left join pior_simulado ps on true
$$;

grant select on marts.estoque_tipologia, marts.estoque_obra, marts.posicao_carteira, marts.alertas_obra
  to authenticated;
revoke execute on function marts.simular_venda_estoque(uuid, numeric, numeric) from public, anon;
revoke execute on function marts.resumo_venda_estoque(uuid, numeric, numeric) from public, anon;
grant execute on function marts.simular_venda_estoque(uuid, numeric, numeric) to authenticated;
grant execute on function marts.resumo_venda_estoque(uuid, numeric, numeric) to authenticated;
