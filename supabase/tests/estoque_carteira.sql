-- Estoque, carteira, alertas e simulação de venda (migration 0024) com casos calculados à mão.
-- As datas são relativas ao mês atual: "mais_1" é o mês que vem.
--   Obra Simulada: duas unidades disponíveis de 100 e 200, uma vendida por 1000 com 40% direto e 60% de
--   repasse (parcelas já quitadas, fora do fluxo), entrega em mais_3 e um título de 1000 a pagar em mais_1.
--   Vendendo uma unidade por mês: a de 100 sai em mais_1 (20 em mais_1 e mais_2, repasse de 60 em mais_3);
--   a de 200 sai em mais_2 (80 em mais_2, repasse de 120 em mais_4, dois meses depois da venda).
--   Carteira: Obra Norte paga 1000 em mais_1 e recebe 1000 em mais_3; Obra Sul paga 700 em mais_3 e recebe
--   700 em mais_4. Cada uma exige 1000 e 700 no pior mês; juntas, 1000 em mais_1.
begin;
create extension if not exists pgtap with schema extensions;
select plan(24);

create temporary table referencia on commit drop as
select m::date as mes_0,
  (m + interval '1 month')::date as mais_1,
  (m + interval '2 months')::date as mais_2,
  (m + interval '3 months')::date as mais_3,
  (m + interval '4 months')::date as mais_4
from date_trunc('month', current_date) as m;
grant select on referencia to authenticated;

insert into app.tenant (id, razao_social) values
  ('0e000000-0000-4000-8000-0000000000e1', 'Construtora Simulação'),
  ('0e000000-0000-4000-8000-0000000000f1', 'Construtora Carteira');

insert into app.centro_custo (id, tenant_id, id_origem, nome) values
  ('0c000000-0000-4000-8000-0000000000e1', '0e000000-0000-4000-8000-0000000000e1', 981, 'Obra Simulada'),
  ('0c000000-0000-4000-8000-0000000000f1', '0e000000-0000-4000-8000-0000000000f1', 982, 'Obra Norte'),
  ('0c000000-0000-4000-8000-0000000000f2', '0e000000-0000-4000-8000-0000000000f1', 983, 'Obra Sul');

insert into staging.unidade (tenant_id, centro_custo_id, id_origem, nome, situacao, data_entrega)
select '0e000000-0000-4000-8000-0000000000e1'::uuid, '0c000000-0000-4000-8000-0000000000e1'::uuid, id_origem, nome,
  situacao, mais_3 + 10
from referencia, lateral (values (1, 'S-1', 'D'), (2, 'S-2', 'D'), (3, 'S-3', 'V')) as u (id_origem, nome, situacao);

insert into staging.unidade_valor (tenant_id, centro_custo_id, unidade_id_origem, valor_sugerido) values
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1', 1, 100),
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1', 2, 200);

insert into staging.contrato_venda (tenant_id, centro_custo_id, id_origem, data_venda, valor, situacao, unidade_id_origem)
select '0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1', 10, mes_0, 1000, '1', 3
from referencia;

insert into staging.parcela_receber (tenant_id, centro_custo_id, id_origem, contrato_id_origem, vencimento,
                                     valor_original, saldo, tipo_condicao)
select tenant_id::uuid, centro_custo_id::uuid, id_origem, contrato, vencimento, valor_original, saldo, tipo_condicao
from referencia, lateral (values
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1', 1, 10, mes_0, 400, 0, 'PM'),
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1', 2, 10, mes_0, 600, 0, 'FI'),
  ('0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f1', 1, 20, mais_3 + 5, 1000, 1000, 'PM'),
  ('0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f2', 1, 21, mais_4 + 5, 700, 700, 'PM')
) as p (tenant_id, centro_custo_id, id_origem, contrato, vencimento, valor_original, saldo, tipo_condicao);

insert into staging.titulo_pagar (tenant_id, centro_custo_id, id_origem, vencimento, valor_original, saldo)
select tenant_id::uuid, centro_custo_id::uuid, id_origem, vencimento, valor, valor
from referencia, lateral (values
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1', 50, mais_1 + 9, 1000),
  ('0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f1', 60, mais_1 + 9, 1000),
  ('0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f2', 61, mais_3 + 9, 700)
) as t (tenant_id, centro_custo_id, id_origem, vencimento, valor);

insert into staging.rateio_titulo (tenant_id, titulo_id_origem, centro_custo_id, valor, fracao) values
  ('0e000000-0000-4000-8000-0000000000e1', 50, '0c000000-0000-4000-8000-0000000000e1', 1000, 1),
  ('0e000000-0000-4000-8000-0000000000f1', 60, '0c000000-0000-4000-8000-0000000000f1', 1000, 1),
  ('0e000000-0000-4000-8000-0000000000f1', 61, '0c000000-0000-4000-8000-0000000000f2', 700, 1);

-- Estoque

select results_eq(
  $$select disponiveis, vendidas, valor_estoque, preco_medio_estoque from marts.estoque_tipologia
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000e1'$$,
  $$values (2::bigint, 1::bigint, 300::numeric, 150::numeric)$$,
  'estoque por tipologia conta a unidade vendida à parte e soma só o estoque'
);
select results_eq(
  $$select unidades_estoque, valor_estoque, meses_ate_entrega from marts.estoque_obra
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000e1'$$,
  $$values (2::bigint, 300::numeric, 3)$$,
  'estoque da obra e meses até a entrega'
);
select is(
  (select meses_para_vender_estoque from marts.estoque_obra where centro_custo_id = '0c000000-0000-4000-8000-0000000000e1'),
  2.0,
  'uma venda por mês no ritmo recente vende duas unidades em dois meses'
);

-- Simulação

select is(
  (select sum(entrada_direta_simulada + repasse_simulado)
     from marts.simular_venda_estoque('0c000000-0000-4000-8000-0000000000e1', 1, 0)),
  300.00,
  'sem desconto, a simulação recebe o valor inteiro do estoque'
);
select is(
  (select entrada_direta_simulada from marts.simular_venda_estoque('0c000000-0000-4000-8000-0000000000e1', 1, 0), referencia
    where competencia = mais_1),
  20.00,
  'parte direta da primeira venda dividida até o mês anterior à entrega'
);
select is(
  (select entrada_direta_simulada from marts.simular_venda_estoque('0c000000-0000-4000-8000-0000000000e1', 1, 0), referencia
    where competencia = mais_2),
  100.00,
  'segunda parcela da primeira venda mais a parte direta inteira da segunda'
);
select is(
  (select repasse_simulado from marts.simular_venda_estoque('0c000000-0000-4000-8000-0000000000e1', 1, 0), referencia
    where competencia = mais_3),
  60.00,
  'repasse da primeira venda nas chaves'
);
select is(
  (select repasse_simulado from marts.simular_venda_estoque('0c000000-0000-4000-8000-0000000000e1', 1, 0), referencia
    where competencia = mais_4),
  120.00,
  'repasse de venda a menos de dois meses da entrega entra dois meses depois da venda'
);
select is(
  (select saldo_acumulado_simulado from marts.simular_venda_estoque('0c000000-0000-4000-8000-0000000000e1', 1, 0), referencia
    where competencia = mais_4),
  -700.00,
  'saldo simulado soma o fluxo atual e o que a venda traz'
);
select is(
  (select saldo_acumulado_atual from marts.simular_venda_estoque('0c000000-0000-4000-8000-0000000000e1', 1, 0), referencia
    where competencia = mais_4),
  -1000.00,
  'saldo atual continua o do fluxo nos meses que só a simulação tem'
);
select is(
  (select repasse_simulado from marts.simular_venda_estoque('0c000000-0000-4000-8000-0000000000e1', 2, 0), referencia
    where competencia = mais_3),
  180.00,
  'duas por mês vendem tudo em mais_1 e os dois repasses caem nas chaves'
);
select is(
  (select sum(entrada_direta_simulada + repasse_simulado)
     from marts.simular_venda_estoque('0c000000-0000-4000-8000-0000000000e1', 1, 0.5)),
  150.00,
  'desconto de 50% corta a receita pela metade'
);
select is(
  (select sum(entrada_direta_simulada + repasse_simulado)
     from marts.simular_venda_estoque('0c000000-0000-4000-8000-0000000000e1', 0, 0)),
  0.00,
  'sem ritmo de venda a simulação não inventa receita'
);
select results_eq(
  $$select r.unidades_estoque, r.mes_ultima_venda, r.receita_simulada, r.exposicao_atual, r.exposicao_simulada,
      r.mes_exposicao_simulada, r.mes_saldo_positivo
    from marts.resumo_venda_estoque('0c000000-0000-4000-8000-0000000000e1', 1, 0) r$$,
  $$select 2, mais_2, 300.00, 1000.00, 980.00, mais_1, null::date from referencia$$,
  'resumo da simulação: última venda, receita e exposição antes e depois'
);
select is(
  (select exposicao_simulada from marts.resumo_venda_estoque('0c000000-0000-4000-8000-0000000000e1', 0, 0)),
  1000.00,
  'sem venda, a exposição simulada é a atual'
);

-- Alertas

select is(
  (select valor from marts.alertas_obra
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000e1' and tipo = 'estouro_orcamento'),
  1000.00,
  'título lançado sem orçamento aparece como estouro'
);
select is_empty(
  $$select 1 from marts.alertas_obra
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000e1' and tipo = 'estoque_apos_entrega'$$,
  'estoque que acaba antes da entrega não gera alerta'
);

-- Carteira

select results_eq(
  $$select obras, exposicao_maxima, mes_exposicao_maxima, soma_exposicao_obras from marts.posicao_carteira
    where tenant_id = '0e000000-0000-4000-8000-0000000000f1'$$,
  $$select 2::bigint, 1000.00, mais_1, 1700.00 from referencia$$,
  'exposição da carteira sai do saldo das obras juntas, não da soma das exposições'
);

-- Gerente da Obra Norte vê a carteira do tamanho da obra dele

insert into auth.users (id, email) values
  ('0a000000-0000-4000-8000-00000000c0f1', 'gerente.carteira@teste.invalid');
insert into app.usuario_tenant (user_id, tenant_id, perfil) values
  ('0a000000-0000-4000-8000-00000000c0f1', '0e000000-0000-4000-8000-0000000000f1', 'gerente_obra');
insert into app.usuario_centro_custo (user_id, tenant_id, centro_custo_id) values
  ('0a000000-0000-4000-8000-00000000c0f1', '0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f1');

select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-00000000c0f1", "role": "authenticated"}', true);
set local role authenticated;

select results_eq(
  $$select obras, exposicao_maxima from marts.posicao_carteira$$,
  $$values (1::bigint, 1000.00)$$,
  'gerente vê a carteira só com a obra dele'
);
select is_empty(
  $$select 1 from marts.simular_venda_estoque('0c000000-0000-4000-8000-0000000000f2', 1, 0)$$,
  'gerente não simula obra que não é dele'
);
select is_empty(
  $$select 1 from marts.alertas_obra where centro_custo_id <> '0c000000-0000-4000-8000-0000000000f1'$$,
  'gerente não vê alerta de outra obra'
);
select is(
  (select count(*) from marts.estoque_obra),
  1::bigint,
  'gerente vê o estoque só da obra dele'
);

reset role;

select is(
  has_function_privilege('anon', 'marts.simular_venda_estoque(uuid, numeric, numeric)', 'execute'),
  false,
  'anônimo não executa a simulação'
);
select is(
  has_function_privilege('anon', 'marts.resumo_venda_estoque(uuid, numeric, numeric)', 'execute'),
  false,
  'anônimo não executa o resumo da simulação'
);

select * from finish();
rollback;
