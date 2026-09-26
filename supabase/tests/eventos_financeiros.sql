-- Casos C02, C03 (staging), C05, C06, C07, C08 e C11 de docs/financeiro/casos_teste.md, mais as
-- reconciliações R1, R5 e R8. Cada caso limpa o raw do tenant A, grava os payloads e recarrega.
begin;
create extension if not exists pgtap with schema extensions;
select plan(67);

insert into app.tenant (id, razao_social) values
  ('7e000000-0000-4000-8000-00000000000a', 'Construtora Teste Financeiro A'),
  ('7e000000-0000-4000-8000-00000000000b', 'Construtora Teste Financeiro B');

insert into app.centro_custo (id, tenant_id, id_origem, nome, tipo) values
  ('7c000000-0000-4000-8000-0000000000a1', '7e000000-0000-4000-8000-00000000000a', 9001, 'Obra Teste 1', 'obra'),
  ('7c000000-0000-4000-8000-0000000000a2', '7e000000-0000-4000-8000-00000000000a', 9002, 'Obra Teste 2', 'obra'),
  ('7c000000-0000-4000-8000-0000000000ae', '7e000000-0000-4000-8000-00000000000a', null, 'Despesas sem obra', 'empresa'),
  ('7c000000-0000-4000-8000-0000000000b1', '7e000000-0000-4000-8000-00000000000b', 9001, 'Obra Teste B1', 'obra');

create function pg_temp.gravar_raw(p_endpoint text, p_payloads jsonb) returns void
language sql as $$
  insert into raw.registro (tenant_id, endpoint, payload, hash_registro)
  select '7e000000-0000-4000-8000-00000000000a', p_endpoint, x, md5(x::text)
  from jsonb_array_elements(p_payloads) x
  on conflict do nothing
$$;

create function pg_temp.payloads_c02() returns void language sql as $$
  select pg_temp.gravar_raw('sales', '[{"id": 5101, "enterpriseId": 9001, "number": "T1-5101", "contractDate": "2026-01-01",
    "situation": "1", "value": 2000.00, "units": [{"id": 90011, "main": true}]}]');
  select pg_temp.gravar_raw('income', '[
    {"projectId": 9001, "billId": 5101, "installmentId": 1, "dueDate": "2026-01-10", "issueDate": "2026-01-01",
     "originalAmount": 1000.00, "balanceAmount": 0, "correctedBalanceAmount": 0, "paymentTerm": {"id": "PM"},
     "receipts": [{"paymentDate": "2026-02-05", "amount": 400.00}, {"paymentDate": "2026-03-07", "amount": 600.00}]},
    {"projectId": 9001, "billId": 5101, "installmentId": 2, "dueDate": "2026-02-10", "issueDate": "2026-01-01",
     "originalAmount": 1000.00, "balanceAmount": 700.00, "correctedBalanceAmount": 700.00, "paymentTerm": {"id": "PM"},
     "receipts": [{"paymentDate": "2026-02-10", "amount": 300.00}]}]');
  select pg_temp.gravar_raw('outcome', '[{"billId": 7101, "companyId": 1, "creditorName": "Fornecedor Teste",
    "dueDate": "2026-02-20", "issueDate": "2026-02-01", "originalAmount": 1000.00, "balanceAmount": 250.00,
    "buildingsCosts": [{"buildingId": 9001, "amount": 1000.00}],
    "payments": [{"paymentDate": "2026-02-20", "amount": 500.00}, {"paymentDate": "2026-03-10", "amount": 250.00}]}]');
$$;

create function pg_temp.payloads_c08(p_segundo_pagamento boolean) returns void language sql as $$
  select pg_temp.gravar_raw('outcome', jsonb_build_array(
    jsonb_build_object('billId', 7801, 'dueDate', '2026-03-20', 'issueDate', '2026-02-01', 'originalAmount', 1000.00,
      'balanceAmount', case when p_segundo_pagamento then 0 else 899.95 end,
      'buildingsCosts', '[{"buildingId": 9001, "amount": 500.00}, {"buildingId": 9002, "amount": 500.00}]'::jsonb,
      'payments', case when p_segundo_pagamento
        then '[{"paymentDate": "2026-02-10", "amount": 100.05}, {"paymentDate": "2026-03-10", "amount": 899.95}]'::jsonb
        else '[{"paymentDate": "2026-02-10", "amount": 100.05}]'::jsonb end),
    '{"billId": 7802, "dueDate": "2026-02-15", "issueDate": "2026-02-05", "originalAmount": 800.00, "balanceAmount": 0,
      "payments": [{"paymentDate": "2026-02-15", "amount": 800.00}]}'::jsonb,
    '{"billId": 7803, "dueDate": "2026-03-05", "issueDate": "2026-02-10", "originalAmount": 50.00, "balanceAmount": 50.00,
      "buildingsCosts": [{"buildingId": 9999, "amount": 50.00}], "payments": []}'::jsonb));
$$;

create function pg_temp.recarregar() returns void language sql as $$
  select staging.recarregar('7e000000-0000-4000-8000-00000000000a')
$$;

-- C02 recebimento e pagamento parciais
select pg_temp.payloads_c02();
select pg_temp.recarregar();
select set_config('app.data_referencia', '2026-03-15', true);

select results_eq(
  $$select contrato_id_origem, parcela_id_origem, sequencia, data_recebimento, valor, tipo_baixa, origem
    from staging.recebimento where tenant_id = '7e000000-0000-4000-8000-00000000000a' order by 1, 2, 3$$,
  $$values (5101, 1, 1, '2026-02-05'::date, 400.00::numeric(18,2), 'recebimento', 'direta'),
           (5101, 1, 2, '2026-03-07'::date, 600.00::numeric(18,2), 'recebimento', 'direta'),
           (5101, 2, 1, '2026-02-10'::date, 300.00::numeric(18,2), 'recebimento', 'direta')$$,
  'C02: um evento por recebimento, inclusive o segundo da mesma parcela'
);
select results_eq(
  $$select id_origem, valor_recebido, data_recebimento from staging.parcela_receber
    where contrato_id_origem = 5101 order by 1$$,
  $$values (1, 1000.00::numeric, '2026-03-07'::date), (2, 300.00::numeric, '2026-02-10'::date)$$,
  'C02: parcela soma os recebimentos e guarda a data do último'
);
select results_eq(
  $$select centro_custo_id, valor_pago, ajuste_baixa, data_pagamento, quantidade_apropriacoes
    from staging.titulo_pagar where id_origem = 7101$$,
  $$values ('7c000000-0000-4000-8000-0000000000a1'::uuid, 750.00::numeric(18,2), 0.00::numeric(18,2), '2026-03-10'::date, 1)$$,
  'C02: cabeçalho do título com o pago somado e a data do último pagamento'
);
select results_eq(
  $$select centro_custo_id, percentual, valor_original, valor_pago, saldo, data_competencia, principal
    from staging.titulo_pagar_apropriacao where titulo_id_origem = 7101$$,
  $$values ('7c000000-0000-4000-8000-0000000000a1'::uuid, 1.000000::numeric(9,6), 1000.00::numeric(18,2),
            750.00::numeric(18,2), 250.00::numeric(18,2), '2026-02-01'::date, true)$$,
  'C02: apropriação única com competência na emissão'
);
select results_eq(
  $$select sequencia_pagamento, data_pagamento, valor from staging.pagamento where titulo_id_origem = 7101 order by 1$$,
  $$values (1, '2026-02-20'::date, 500.00::numeric(18,2)), (2, '2026-03-10'::date, 250.00::numeric(18,2))$$,
  'C02: um evento por pagamento'
);
select results_eq(
  $$select competencia, entrada_direta_realizada, entrada_direta_vencida, saida_realizada, saida_vencida, saldo_mes, saldo_acumulado
    from marts.fluxo_caixa_mensal where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' order by 1$$,
  $$values ('2026-02-01'::date, 700.00, 700.00, 500.00, 250.00, -50.00, -50.00),
           ('2026-03-01'::date, 600.00, 0.00, 250.00, 0.00, 350.00, 300.00)$$,
  'C02: fluxo de fevereiro e março pelo dia do dinheiro, nada em janeiro'
);
select results_eq(
  $$select recebido_direto, vencido_direto, pago, a_pagar, custo_lancado, ajuste_baixa, caixa_atual, exposicao_maxima, orcamento_carregado
    from marts.posicao_financeira_obra where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'$$,
  $$values (1300.00, 700.00, 750.00, 250.00, 1000.00, 0.00, 550.00, 50.00, false)$$,
  'C02: posição da obra com recebimento e pagamento parciais'
);
select results_eq(
  $$select unidade_id_origem, valor_financiado, credito_associativo from staging.contrato_venda where id_origem = 5101$$,
  $$values (90011, null::numeric(18,2), null::boolean)$$,
  'C02: contrato sem condições nem crédito associativo fica com nulo, não zero'
);
select results_eq(
  $$select sequencia, unidade_id_origem, principal from staging.contrato_unidade where contrato_id_origem = 5101$$,
  $$values (1, 90011, true)$$,
  'C02: unidade do contrato marcada como principal'
);
-- R1
select is(
  (select sum(valor) from staging.recebimento where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'
     and tipo_baixa in ('recebimento', 'estorno')),
  (select recebido_direto + recebido_repasse from marts.posicao_financeira_obra
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'),
  'R1: recebido da posição igual à soma dos recebimentos'
);
select is(
  (select sum(entrada_direta_realizada + repasse_realizado) from marts.fluxo_caixa_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'),
  1300.00::numeric,
  'R1: realizado do fluxo igual à soma dos recebimentos'
);

-- C03 competência diferente da data de pagamento, parte de staging
delete from raw.registro where tenant_id = '7e000000-0000-4000-8000-00000000000a';
select pg_temp.gravar_raw('outcome', '[{"billId": 7201, "dueDate": "2026-02-15", "issueDate": "2026-01-20",
  "originalAmount": 5000.00, "balanceAmount": 0, "buildingsCosts": [{"buildingId": 9001, "amount": 5000.00}],
  "paymentsCategories": [{"financialCategoryId": "2.01.001", "financialCategoryRate": 100}],
  "payments": [{"paymentDate": "2026-02-14", "amount": 5000.00}]}]');
select pg_temp.recarregar();
select set_config('app.data_referencia', '2026-03-10', true);

select results_eq(
  $$select data_competencia, conta_origem, vencimento from staging.titulo_pagar_apropriacao where titulo_id_origem = 7201$$,
  $$values ('2026-01-20'::date, '2.01.001', '2026-02-15'::date)$$,
  'C03: competência na emissão e conta da lista de categorias'
);
select results_eq(
  $$select competencia, saida_realizada from marts.fluxo_caixa_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' order by 1$$,
  $$values ('2026-02-01'::date, 5000.00)$$,
  'C03: caixa só em fevereiro, no dia do pagamento'
);
select results_eq(
  $$select conta_origem from staging.pagamento where titulo_id_origem = 7201$$,
  $$values ('2.01.001')$$,
  'C03: pagamento carrega a conta da apropriação'
);

-- C05 parcela vencida fora da previsão (nível staging)
delete from raw.registro where tenant_id = '7e000000-0000-4000-8000-00000000000a';
select pg_temp.recarregar();
insert into staging.contrato_venda (tenant_id, centro_custo_id, id_origem, data_venda, valor, situacao) values
  ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1', 5401, '2025-10-01', 200000.00, '1');
insert into staging.parcela_receber (tenant_id, centro_custo_id, id_origem, contrato_id_origem, vencimento,
  valor_original, saldo, saldo_corrigido, tipo_condicao, valor_recebido) values
  ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1', 1, 5401, '2026-03-10', 2000.00, 2000.00, 2000.00, 'PM', 0),
  ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1', 2, 5401, '2026-04-10', 2000.00, 2000.00, 2000.00, 'PM', 0),
  ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1', 3, 5401, '2026-03-01', 100000.00, 100000.00, 100000.00, 'FI', 0);
select set_config('app.data_referencia', '2026-03-20', true);

select results_eq(
  $$select competencia, entrada_direta_vencida, repasse_vencido, entrada_direta_prevista, repasse_previsto, saldo_mes
    from marts.fluxo_caixa_mensal where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' order by 1$$,
  $$values ('2026-03-01'::date, 2000.00, 100000.00, 0::numeric, 0::numeric, 0::numeric),
           ('2026-04-01'::date, 0::numeric, 0::numeric, 2000.00, 0::numeric, 2000.00)$$,
  'C05: vencida fica fora do saldo; a vencer entra no mês do vencimento'
);
select results_eq(
  $$select vencido_direto, repasse_atrasado, a_receber_direto from marts.posicao_financeira_obra
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'$$,
  $$values (2000.00, 100000.00, 2000.00)$$,
  'C05: posição separa vencido de a receber'
);

-- C06 virada de dezembro para janeiro
delete from staging.parcela_receber where tenant_id = '7e000000-0000-4000-8000-00000000000a';
delete from staging.contrato_venda where tenant_id = '7e000000-0000-4000-8000-00000000000a';
insert into staging.contrato_venda (tenant_id, centro_custo_id, id_origem, data_venda, valor, situacao) values
  ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1', 5501, '2026-06-01', 100000.00, '1');
insert into staging.parcela_receber (tenant_id, centro_custo_id, id_origem, contrato_id_origem, vencimento,
  valor_original, saldo, saldo_corrigido, tipo_condicao, valor_recebido)
select '7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1', n, 5501, v, s, s, s, 'PM', 0
from (values (1, '2026-12-10'::date, 800.00), (2, '2026-12-20'::date, 1000.00), (3, '2027-01-10'::date, 1500.00),
             (4, '2027-01-31'::date, 500.00), (5, '2027-02-01'::date, 700.00)) as p(n, v, s);
select set_config('app.data_referencia', '2026-12-15', true);

select is(app.data_referencia(), '2026-12-15'::date, 'C06: data de referência fixada pelo teste');
select results_eq(
  $$select competencia, entrada_direta_vencida, entrada_direta_prevista from marts.fluxo_caixa_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' order by 1$$,
  $$values ('2026-12-01'::date, 800.00, 1000.00), ('2027-01-01'::date, 0::numeric, 2000.00),
           ('2027-02-01'::date, 0::numeric, 700.00)$$,
  'C06: janeiro de 2027 recebe as parcelas 3 e 4 como previstas'
);
select is(
  (select entrada_direta_prevista from marts.fluxo_caixa_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'
      and competencia = (date_trunc('month', app.data_referencia()) + interval '1 month')::date),
  2000.00::numeric,
  'C06: próximo mês de dezembro é janeiro do ano seguinte'
);
select is(app.situacao_parcela(1000.00, 0, '2026-12-20', false, '2026-12-20'), 'a_vencer',
  'C06: o próprio dia do vencimento ainda é a vencer');
select is(app.situacao_parcela(1000.00, 0, '2026-12-20', false, '2026-12-21'), 'vencida',
  'C06: um dia depois está vencida');
select set_config('app.data_referencia', '2026-12-21', true);
select is(
  (select entrada_direta_vencida from marts.fluxo_caixa_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' and competencia = '2026-12-01'),
  1800.00::numeric,
  'C06: em 21/12 a parcela de 20/12 passa para vencida'
);
select set_config('app.data_referencia', '', true);
select is(app.data_referencia(), (now() at time zone 'America/Sao_Paulo')::date,
  'C06: sem valor fixado, a referência é hoje em São Paulo');

-- C07 distrato, estorno e renegociação
delete from raw.registro where tenant_id = '7e000000-0000-4000-8000-00000000000a';
select pg_temp.gravar_raw('sales', '[
  {"id": 5601, "enterpriseId": 9001, "contractDate": "2025-10-01", "situation": "3", "cancellationDate": "2026-05-10", "value": 250000.00, "units": [{"id": 90601, "main": true}]},
  {"id": 5602, "enterpriseId": 9001, "contractDate": "2026-03-01", "situation": "1", "value": 100000.00, "units": [{"id": 90602, "main": true}]},
  {"id": 5603, "enterpriseId": 9001, "contractDate": "2026-01-15", "situation": "1", "value": 120000.00, "units": [{"id": 90603, "main": true}]}]');
select pg_temp.gravar_raw('income', '[
  {"projectId": 9001, "billId": 5601, "installmentId": 1, "paymentTerm": {"id": "AT"}, "dueDate": "2025-10-01", "originalAmount": 25000.00,
   "balanceAmount": 0, "correctedBalanceAmount": 0, "receipts": [{"paymentDate": "2025-10-01", "amount": 25000.00}]},
  {"projectId": 9001, "billId": 5601, "installmentId": 2, "paymentTerm": {"id": "PM"}, "dueDate": "2026-06-10", "originalAmount": 5000.00,
   "balanceAmount": 5000.00, "correctedBalanceAmount": 5000.00, "receipts": []},
  {"projectId": 9001, "billId": 5602, "installmentId": 1, "paymentTerm": {"id": "PM"}, "dueDate": "2026-04-10", "originalAmount": 3000.00,
   "balanceAmount": 3000.00, "correctedBalanceAmount": 3000.00,
   "receipts": [{"paymentDate": "2026-04-10", "amount": 3000.00}, {"paymentDate": "2026-04-20", "amount": -3000.00}]},
  {"projectId": 9001, "billId": 5603, "installmentId": 1, "paymentTerm": {"id": "PM"}, "dueDate": "2026-03-10", "originalAmount": 4000.00,
   "balanceAmount": 0, "correctedBalanceAmount": 0, "receipts": []},
  {"projectId": 9001, "billId": 5603, "installmentId": 2, "paymentTerm": {"id": "PM"}, "dueDate": "2026-07-10", "originalAmount": 2000.00,
   "balanceAmount": 2000.00, "correctedBalanceAmount": 2000.00, "receipts": []},
  {"projectId": 9001, "billId": 5603, "installmentId": 3, "paymentTerm": {"id": "PM"}, "dueDate": "2026-08-10", "originalAmount": 2000.00,
   "balanceAmount": 2000.00, "correctedBalanceAmount": 2000.00, "receipts": []}]');
select pg_temp.gravar_raw('outcome', '[{"billId": 7601, "dueDate": "2026-06-01", "issueDate": "2026-05-20", "originalAmount": 10000.00,
  "balanceAmount": 10000.00, "paymentsCategories": [{"financialCategoryId": "2.09.001", "financialCategoryRate": 100}], "payments": []}]');
select pg_temp.recarregar();
select set_config('app.data_referencia', '2026-06-15', true);

select results_eq(
  $$select sequencia, valor, tipo_baixa from staging.recebimento where contrato_id_origem = 5602 order by 1$$,
  $$values (1, 3000.00::numeric(18,2), 'recebimento'), (2, -3000.00::numeric(18,2), 'estorno')$$,
  'C07: estorno é recebimento negativo'
);
select results_eq(
  $$select valor_recebido, data_recebimento from staging.parcela_receber where contrato_id_origem = 5602$$,
  $$values (0.00::numeric, '2026-04-20'::date)$$,
  'C07: parcela estornada fica com recebido zero'
);
select results_eq(
  $$select p.contrato_id_origem, p.id_origem,
           app.situacao_parcela(coalesce(p.saldo_corrigido, p.saldo), p.valor_recebido, p.vencimento,
                                c.situacao = '3', app.data_referencia())
    from staging.parcela_receber p
    join staging.contrato_venda c on c.tenant_id = p.tenant_id and c.id_origem = p.contrato_id_origem
    where p.tenant_id = '7e000000-0000-4000-8000-00000000000a' order by 1, 2$$,
  $$values (5601, 1, 'quitada'), (5601, 2, 'cancelada_distrato'), (5602, 1, 'vencida'),
           (5603, 1, 'baixada_sem_recebimento'), (5603, 2, 'a_vencer'), (5603, 3, 'a_vencer')$$,
  'C07: situação de cada parcela'
);
select results_eq(
  $$select competencia, entrada_direta_realizada, entrada_direta_vencida, entrada_direta_prevista
    from marts.fluxo_caixa_mensal where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' order by 1$$,
  $$values ('2025-10-01'::date, 25000.00, 0::numeric, 0::numeric),
           ('2026-04-01'::date, 0.00, 3000.00, 0::numeric),
           ('2026-07-01'::date, 0::numeric, 0::numeric, 2000.00),
           ('2026-08-01'::date, 0::numeric, 0::numeric, 2000.00)$$,
  'C07: recebido do distratado fica no realizado, saldo dele sai; renegociada não aparece'
);
select results_eq(
  $$select recebido_direto, vencido_direto, a_receber_direto from marts.posicao_financeira_obra
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'$$,
  $$values (25000.00, 3000.00, 4000.00)$$,
  'C07: posição da obra sem contar o estorno nem a parcela renegociada'
);
select results_eq(
  $$select centro_custo_id, motivo_sem_obra, percentual, saldo, conta_origem, data_competencia
    from staging.titulo_pagar_apropriacao where titulo_id_origem = 7601$$,
  $$values ('7c000000-0000-4000-8000-0000000000ae'::uuid, 'sem_rateio_na_origem', 1.000000::numeric(9,6),
            10000.00::numeric(18,2), '2.09.001', '2026-05-20'::date)$$,
  'C07: devolução de distrato sem obra vai para Despesas sem obra'
);
select results_eq(
  $$select competencia, saida_vencida from marts.fluxo_caixa_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000ae'$$,
  $$values ('2026-06-01'::date, 10000.00)$$,
  'C07: devolução vencida entra na saída do centro da empresa'
);

-- C08 rateio com resíduo de centavo e despesa sem obra
delete from raw.registro where tenant_id = '7e000000-0000-4000-8000-00000000000a';
select pg_temp.payloads_c08(false);
select pg_temp.recarregar();
select set_config('app.data_referencia', '2026-02-28', true);

select results_eq(
  $$select centro_custo_id, sequencia_obra, principal, percentual, valor_original, valor_pago, ajuste_baixa, saldo
    from staging.titulo_pagar_apropriacao where titulo_id_origem = 7801 order by sequencia_obra$$,
  $$values ('7c000000-0000-4000-8000-0000000000a1'::uuid, 1, true, 0.500000::numeric(9,6), 500.00::numeric(18,2),
            50.02::numeric(18,2), 0.00::numeric(18,2), 449.98::numeric(18,2)),
           ('7c000000-0000-4000-8000-0000000000a2'::uuid, 2, false, 0.500000::numeric(9,6), 500.00::numeric(18,2),
            50.03::numeric(18,2), 0.00::numeric(18,2), 449.97::numeric(18,2))$$,
  'C08: resíduo do centavo fica na apropriação principal'
);
select results_eq(
  $$select centro_custo_id, data_pagamento, valor from staging.pagamento where titulo_id_origem = 7801 order by sequencia_obra$$,
  $$values ('7c000000-0000-4000-8000-0000000000a1'::uuid, '2026-02-10'::date, 50.02::numeric(18,2)),
           ('7c000000-0000-4000-8000-0000000000a2'::uuid, '2026-02-10'::date, 50.03::numeric(18,2))$$,
  'C08: pagamento rateado entre as duas obras'
);
select results_eq(
  $$select centro_custo_id, valor_pago, quantidade_apropriacoes from staging.titulo_pagar where id_origem = 7801$$,
  $$values ('7c000000-0000-4000-8000-0000000000a1'::uuid, 100.05::numeric(18,2), 2)$$,
  'C08: cabeçalho aponta para a obra principal'
);
select results_eq(
  $$select titulo_id_origem, centro_custo_id, motivo_sem_obra, id_origem_obra, valor_pago, saldo
    from staging.titulo_pagar_apropriacao where titulo_id_origem in (7802, 7803) order by 1$$,
  $$values (7802, '7c000000-0000-4000-8000-0000000000ae'::uuid, 'sem_rateio_na_origem', null::integer,
            800.00::numeric(18,2), 0.00::numeric(18,2)),
           (7803, '7c000000-0000-4000-8000-0000000000ae'::uuid, 'obra_nao_cadastrada', 9999,
            0.00::numeric(18,2), 50.00::numeric(18,2))$$,
  'C08: título sem rateio e título de obra desconhecida ficam na empresa'
);
select results_eq(
  $$select centro_custo_id, saida_realizada from marts.fluxo_caixa_mensal
    where tenant_id = '7e000000-0000-4000-8000-00000000000a' and competencia = '2026-02-01' order by saida_realizada$$,
  $$values ('7c000000-0000-4000-8000-0000000000a1'::uuid, 50.02), ('7c000000-0000-4000-8000-0000000000a2'::uuid, 50.03),
           ('7c000000-0000-4000-8000-0000000000ae'::uuid, 800.00)$$,
  'C08: saída realizada de fevereiro por centro'
);
select results_eq(
  $$select centro_custo_id, saida_prevista from marts.fluxo_caixa_mensal
    where tenant_id = '7e000000-0000-4000-8000-00000000000a' and competencia = '2026-03-01' order by saida_prevista$$,
  $$values ('7c000000-0000-4000-8000-0000000000ae'::uuid, 50.00), ('7c000000-0000-4000-8000-0000000000a2'::uuid, 449.97),
           ('7c000000-0000-4000-8000-0000000000a1'::uuid, 449.98)$$,
  'C08: saída prevista de março por centro'
);
select is(
  (select sum(saida_realizada) from marts.fluxo_caixa_mensal where tenant_id = '7e000000-0000-4000-8000-00000000000a'),
  (select sum(valor) from staging.pagamento where tenant_id = '7e000000-0000-4000-8000-00000000000a'),
  'R8: saída realizada de todos os centros igual à soma dos pagamentos do tenant'
);
select is(
  (select sum(valor) from staging.pagamento where tenant_id = '7e000000-0000-4000-8000-00000000000a'),
  900.05::numeric,
  'C08: soma dos pagamentos do tenant é 900,05 (50,02 + 50,03 + 800,00)'
);
select results_eq(
  $$select pago, a_pagar, custo_lancado from marts.posicao_financeira_obra
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'$$,
  $$values (50.02, 449.98, 500.00)$$,
  'C08: posição de T1 só com a fatia dela'
);
select is(
  (select count(*) from marts.posicao_financeira_obra where centro_custo_id = '7c000000-0000-4000-8000-0000000000ae'),
  0::bigint,
  'C08: Despesas sem obra fica fora da posição por obra'
);
-- R5: por título, partes somam o que a origem mandou
select is(
  (select count(*) from (
     select r.payload->>'billId' as titulo
     from raw.registro r
     left join (select titulo_id_origem, sum(valor_original) as original, sum(saldo) as saldo
                from staging.titulo_pagar_apropriacao where tenant_id = '7e000000-0000-4000-8000-00000000000a'
                group by 1) a on a.titulo_id_origem = (r.payload->>'billId')::int
     left join (select titulo_id_origem, sum(valor) as pago
                from staging.pagamento where tenant_id = '7e000000-0000-4000-8000-00000000000a'
                group by 1) p on p.titulo_id_origem = (r.payload->>'billId')::int
     where r.tenant_id = '7e000000-0000-4000-8000-00000000000a' and r.endpoint = 'outcome'
       and (a.original is distinct from (r.payload->>'originalAmount')::numeric
            or a.saldo is distinct from (r.payload->>'balanceAmount')::numeric
            or coalesce(p.pago, 0) <> coalesce((select sum((x->>'amount')::numeric)
                                                 from jsonb_array_elements(r.payload->'payments') x), 0))
   ) divergentes),
  0::bigint,
  'R5: valor original, saldo e pagamentos de cada título batem com a origem'
);

-- C08 variante com o segundo pagamento: título quitado fecha centavo a centavo em cada obra
delete from raw.registro where tenant_id = '7e000000-0000-4000-8000-00000000000a';
select pg_temp.payloads_c08(true);
select pg_temp.recarregar();

select results_eq(
  $$select sequencia_pagamento, sequencia_obra, valor from staging.pagamento where titulo_id_origem = 7801 order by 1, 2$$,
  $$values (1, 1, 50.02::numeric(18,2)), (1, 2, 50.03::numeric(18,2)), (2, 1, 449.98::numeric(18,2)), (2, 2, 449.97::numeric(18,2))$$,
  'C08 variante: segundo pagamento completa cada obra'
);
select results_eq(
  $$select sequencia_obra, valor_pago, saldo from staging.titulo_pagar_apropriacao where titulo_id_origem = 7801 order by 1$$,
  $$values (1, 500.00::numeric(18,2), 0.00::numeric(18,2)), (2, 500.00::numeric(18,2), 0.00::numeric(18,2))$$,
  'C08 variante: saldo zero nas duas apropriações'
);

-- Rateio por obra e por conta ao mesmo tempo (percentuais 2/3 e 1/3 vezes 50% e 50%)
delete from raw.registro where tenant_id = '7e000000-0000-4000-8000-00000000000a';
select pg_temp.gravar_raw('outcome', '[{"billId": 7810, "dueDate": "2026-03-20", "issueDate": "2026-02-01",
  "originalAmount": 100.01, "balanceAmount": 100.01,
  "buildingsCosts": [{"buildingId": 9001, "amount": 200.00}, {"buildingId": 9002, "amount": 100.00}],
  "paymentsCategories": [{"financialCategoryId": "2.01.001", "financialCategoryRate": 50},
                         {"financialCategoryId": "2.01.002", "financialCategoryRate": 50}], "payments": []}]');
select pg_temp.recarregar();
select results_eq(
  $$select sequencia_obra, sequencia_conta, conta_origem, principal, percentual, valor_original
    from staging.titulo_pagar_apropriacao where titulo_id_origem = 7810 order by 1, 2$$,
  $$values (1, 1, '2.01.001', true, 0.333333::numeric(9,6), 33.33::numeric(18,2)),
           (1, 2, '2.01.002', false, 0.333333::numeric(9,6), 33.34::numeric(18,2)),
           (2, 1, '2.01.001', false, 0.166667::numeric(9,6), 16.67::numeric(18,2)),
           (2, 2, '2.01.002', false, 0.166667::numeric(9,6), 16.67::numeric(18,2))$$,
  'rateio por obra e conta soma o valor do título, com o resto na principal'
);

-- Payload com percentual (hipótese rate) usa o percentual no lugar do valor
delete from raw.registro where tenant_id = '7e000000-0000-4000-8000-00000000000a';
select pg_temp.gravar_raw('outcome', '[{"billId": 7811, "dueDate": "2026-03-20", "originalAmount": 1000.00, "balanceAmount": 1000.00,
  "buildingsCosts": [{"buildingId": 9001, "amount": 900.00, "rate": 60}, {"buildingId": 9002, "amount": 100.00, "rate": 40}],
  "payments": []}]');
select pg_temp.recarregar();
select results_eq(
  $$select sequencia_obra, valor_original, data_competencia from staging.titulo_pagar_apropriacao
    where titulo_id_origem = 7811 order by 1$$,
  $$values (1, 600.00::numeric(18,2), null::date), (2, 400.00::numeric(18,2), null::date)$$,
  'percentual da origem tem precedência; sem emissão a competência fica nula'
);

-- Percentual em só parte dos itens: vale o valor em todos, para a obra sem percentual não sumir do rateio
delete from raw.registro where tenant_id = '7e000000-0000-4000-8000-00000000000a';
select pg_temp.gravar_raw('outcome', '[{"billId": 7813, "dueDate": "2026-03-20", "originalAmount": 1000.00, "balanceAmount": 1000.00,
  "buildingsCosts": [{"buildingId": 9001, "amount": 700.00, "rate": 100}, {"buildingId": 9002, "amount": 300.00}],
  "payments": []}]');
select pg_temp.recarregar();
select results_eq(
  $$select sequencia_obra, valor_original from staging.titulo_pagar_apropriacao
    where titulo_id_origem = 7813 order by 1$$,
  $$values (1, 700.00::numeric(18,2)), (2, 300.00::numeric(18,2))$$,
  'percentual em só parte dos itens: rateio pelo valor, nenhuma obra some'
);

-- Lista de rateio sem valor vai inteira para a empresa
delete from raw.registro where tenant_id = '7e000000-0000-4000-8000-00000000000a';
select pg_temp.gravar_raw('outcome', '[{"billId": 7812, "dueDate": "2026-03-20", "originalAmount": 70.00, "balanceAmount": 70.00,
  "buildingsCosts": [{"buildingId": 9001}], "payments": []}]');
select pg_temp.recarregar();
select results_eq(
  $$select centro_custo_id, motivo_sem_obra, valor_original from staging.titulo_pagar_apropriacao where titulo_id_origem = 7812$$,
  $$values ('7c000000-0000-4000-8000-0000000000ae'::uuid, 'rateio_sem_valor', 70.00::numeric(18,2))$$,
  'rateio sem valor vai para Despesas sem obra com o motivo'
);

-- Desconto na baixa: ajuste separado do saldo e do pago
delete from raw.registro where tenant_id = '7e000000-0000-4000-8000-00000000000a';
select pg_temp.gravar_raw('outcome', '[{"billId": 7813, "dueDate": "2026-02-20", "originalAmount": 1000.00, "balanceAmount": 0,
  "buildingsCosts": [{"buildingId": 9001, "amount": 1000.00}], "payments": [{"paymentDate": "2026-02-20", "amount": 950.00}]}]');
select pg_temp.recarregar();
select results_eq(
  $$select pago, a_pagar, custo_lancado, ajuste_baixa from marts.posicao_financeira_obra
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'$$,
  $$values (950.00, 0::numeric, 1000.00, 50.00)$$,
  'desconto obtido aparece em ajuste_baixa, fora do pago e do a pagar'
);

-- Parcela de obra não cadastrada vai para a empresa
delete from raw.registro where tenant_id = '7e000000-0000-4000-8000-00000000000a';
select pg_temp.gravar_raw('income', '[{"projectId": 9999, "billId": 5901, "installmentId": 1, "dueDate": "2026-02-10",
  "originalAmount": 100.00, "balanceAmount": 0, "correctedBalanceAmount": 0, "paymentTerm": {"id": "PM"},
  "installmentNumber": "1/1", "receiptsCategories": [{"financialCategoryId": "1.01.001"}],
  "receipts": [{"paymentDate": "2026-02-10", "amount": 100.00}, {"amount": 5.00}]}]');
select pg_temp.recarregar();
select results_eq(
  $$select centro_custo_id, motivo_sem_obra, id_origem_obra, numero_parcela, conta_origem, valor_recebido
    from staging.parcela_receber where contrato_id_origem = 5901$$,
  $$values ('7c000000-0000-4000-8000-0000000000ae'::uuid, 'obra_nao_cadastrada', 9999, '1/1', '1.01.001', 100.00::numeric)$$,
  'parcela de obra não cadastrada fica na empresa e recebimento sem data fica fora'
);
select is(
  (select centro_custo_id from staging.recebimento where contrato_id_origem = 5901),
  '7c000000-0000-4000-8000-0000000000ae'::uuid,
  'recebimento acompanha o centro da parcela'
);

-- Condições de pagamento e crédito associativo do contrato
delete from raw.registro where tenant_id = '7e000000-0000-4000-8000-00000000000a';
select pg_temp.gravar_raw('sales', '[
  {"id": 5701, "enterpriseId": 9001, "situation": "1", "value": 300000.00, "associativeCredit": "S",
   "paymentConditions": [{"conditionType": "AT", "totalValue": 30000.00}, {"conditionType": "FI", "totalValue": 200000.00},
                         {"conditionType": "FI", "totalValue": 70000.00}],
   "units": [{"id": 90701, "main": false}, {"id": 90702, "main": true}]},
  {"id": 5702, "enterpriseId": 9001, "situation": "1", "value": 100000.00, "associativeCredit": "N",
   "paymentConditions": [{"conditionType": "PM", "totalValue": 100000.00}],
   "units": [{"id": 90703}, {"id": 90704}]}]');
select pg_temp.recarregar();
select results_eq(
  $$select id_origem, unidade_id_origem, valor_financiado, credito_associativo from staging.contrato_venda
    where tenant_id = '7e000000-0000-4000-8000-00000000000a' order by 1$$,
  $$values (5701, 90702, 270000.00::numeric(18,2), true), (5702, 90703, 0.00::numeric(18,2), false)$$,
  'valor financiado soma as condições FI; unidade principal é a marcada, senão a primeira'
);
select results_eq(
  $$select contrato_id_origem, sequencia, unidade_id_origem, principal from staging.contrato_unidade
    where tenant_id = '7e000000-0000-4000-8000-00000000000a' order by 1, 2$$,
  $$values (5701, 1, 90701, false), (5701, 2, 90702, true), (5702, 1, 90703, true), (5702, 2, 90704, false)$$,
  'todas as unidades do contrato, uma só principal'
);

-- C11 reprocessamento sem duplicar: C02 e C08 juntos, recarregados duas vezes
delete from raw.registro where tenant_id = '7e000000-0000-4000-8000-00000000000a';
select pg_temp.payloads_c02();
select pg_temp.payloads_c08(false);
select pg_temp.recarregar();
select pg_temp.recarregar();

create temp table contagem_c11 as
select (select count(*) from staging.recebimento where tenant_id = '7e000000-0000-4000-8000-00000000000a') as recebimentos,
       (select count(*) from staging.parcela_receber where tenant_id = '7e000000-0000-4000-8000-00000000000a') as parcelas,
       (select count(*) from staging.titulo_pagar where tenant_id = '7e000000-0000-4000-8000-00000000000a') as titulos,
       (select count(*) from staging.titulo_pagar_apropriacao where tenant_id = '7e000000-0000-4000-8000-00000000000a') as apropriacoes,
       (select count(*) from staging.pagamento where tenant_id = '7e000000-0000-4000-8000-00000000000a') as pagamentos,
       (select sum(valor) from staging.pagamento where tenant_id = '7e000000-0000-4000-8000-00000000000a') as soma_pagamentos,
       (select count(*) from app.centro_custo where tenant_id = '7e000000-0000-4000-8000-00000000000a' and tipo = 'empresa') as empresas;

select results_eq(
  'select recebimentos, parcelas, titulos, apropriacoes, pagamentos, soma_pagamentos, empresas from contagem_c11',
  $$values (3::bigint, 2::bigint, 4::bigint, 5::bigint, 5::bigint, 1650.05::numeric, 1::bigint)$$,
  'C11: contagens e soma depois da segunda recarga'
);

select pg_temp.payloads_c02();
select pg_temp.payloads_c08(false);
select pg_temp.recarregar();
select results_eq(
  $$select (select count(*) from staging.recebimento where tenant_id = '7e000000-0000-4000-8000-00000000000a'),
           (select count(*) from staging.parcela_receber where tenant_id = '7e000000-0000-4000-8000-00000000000a'),
           (select count(*) from staging.titulo_pagar where tenant_id = '7e000000-0000-4000-8000-00000000000a'),
           (select count(*) from staging.titulo_pagar_apropriacao where tenant_id = '7e000000-0000-4000-8000-00000000000a'),
           (select count(*) from staging.pagamento where tenant_id = '7e000000-0000-4000-8000-00000000000a'),
           (select sum(valor) from staging.pagamento where tenant_id = '7e000000-0000-4000-8000-00000000000a'),
           (select count(*) from app.centro_custo where tenant_id = '7e000000-0000-4000-8000-00000000000a' and tipo = 'empresa')$$,
  'select recebimentos, parcelas, titulos, apropriacoes, pagamentos, soma_pagamentos, empresas from contagem_c11',
  'C11: regravar os mesmos payloads e recarregar não muda nada'
);

-- Tenant novo ganha o centro da empresa na primeira recarga
select staging.recarregar('7e000000-0000-4000-8000-00000000000b');
select is(
  (select count(*) from app.centro_custo where tenant_id = '7e000000-0000-4000-8000-00000000000b' and tipo = 'empresa'),
  1::bigint,
  'recarga cria o centro da empresa para tenant que ainda não tinha'
);
select throws_ok(
  $$insert into app.centro_custo (tenant_id, id_origem, nome, tipo)
    values ('7e000000-0000-4000-8000-00000000000a', null, 'Outra empresa', 'empresa')$$,
  '23505', null, 'só um centro da empresa por tenant'
);
select throws_ok(
  $$insert into app.centro_custo (tenant_id, id_origem, nome, tipo)
    values ('7e000000-0000-4000-8000-00000000000a', null, 'Obra sem código', 'obra')$$,
  '23514', null, 'obra precisa de código da origem'
);

-- Carimbo da carga
select is(
  (select desatualizada from app.situacao_carga()),
  true,
  'sem usuário logado não há tenant e a carga aparece desatualizada'
);

-- Estrutura: RLS ligado e forçado nas tabelas novas, com uma política de select
select is(
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'staging' and c.relname in ('contrato_unidade', 'recebimento', 'titulo_pagar_apropriacao', 'pagamento')
      and c.relrowsecurity and c.relforcerowsecurity),
  4::bigint,
  'RLS ligado e forçado nas quatro tabelas novas de staging'
);
select is(
  (select count(*) from pg_policies where schemaname = 'staging'
     and tablename in ('contrato_unidade', 'recebimento', 'titulo_pagar_apropriacao', 'pagamento')),
  4::bigint,
  'uma política por tabela nova'
);
select ok(
  (select c.relrowsecurity and c.relforcerowsecurity from pg_class c
    where c.oid = 'app.auditoria_alteracao'::regclass),
  'RLS ligado e forçado na auditoria'
);
select ok(
  not has_function_privilege('authenticated', 'staging.recarregar(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'app.registrar_auditoria()', 'execute')
  and not has_function_privilege('anon', 'app.data_referencia()', 'execute')
  and not has_function_privilege('anon', 'app.situacao_carga()', 'execute'),
  'funções internas sem execute para quem não deve chamar'
);
select ok(
  has_function_privilege('authenticated', 'app.data_referencia()', 'execute')
  and has_function_privilege('authenticated', 'app.situacao_carga()', 'execute')
  and has_function_privilege('authenticated', 'app.situacao_parcela(numeric, numeric, date, boolean, date)', 'execute'),
  'funções de leitura liberadas para o usuário logado'
);
select ok(
  (select bool_and(coalesce(c.reloptions @> array['security_invoker=true'], false)) from pg_class c
    where c.oid in ('marts.fluxo_caixa_mensal'::regclass, 'marts.posicao_financeira_obra'::regclass,
                    'marts.cobertura_orcamento_obra'::regclass)),
  'views recriadas com security_invoker'
);
select hasnt_view('marts', 'consolidado_centro_custo', 'view antiga consolidado_centro_custo removida');
select is(
  (select array_agg(attname::text order by attnum) from pg_attribute
    where attrelid = 'marts.posicao_financeira_obra'::regclass and attnum > 0 and not attisdropped),
  array['tenant_id', 'centro_custo_id', 'obra', 'recebido_direto', 'recebido_repasse', 'a_receber_direto',
        'a_receber_repasse', 'vencido_direto', 'repasse_atrasado', 'estoque_a_vender', 'pago', 'a_pagar',
        'custo_orcado', 'custo_a_incorrer', 'estouro_orcamento', 'caixa_atual', 'exposicao_maxima',
        'resultado_contratado', 'resultado_projetado', 'custo_lancado', 'ajuste_baixa', 'orcamento_carregado'],
  'posição mantém as 19 colunas na ordem e acrescenta três no fim'
);
select is(
  (select array_agg(attname::text order by attnum) from pg_attribute
    where attrelid = 'marts.fluxo_caixa_mensal'::regclass and attnum > 0 and not attisdropped),
  array['tenant_id', 'centro_custo_id', 'competencia', 'entrada_direta_realizada', 'repasse_realizado',
        'entrada_direta_prevista', 'repasse_previsto', 'entrada_direta_vencida', 'repasse_vencido',
        'saida_realizada', 'saida_prevista', 'saida_vencida', 'saldo_mes', 'saldo_acumulado'],
  'fluxo mantém as 14 colunas na ordem'
);

select * from finish();
rollback;
