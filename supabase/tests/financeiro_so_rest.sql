-- Caminho só REST (migration 0040): a pagar, pago, a receber, recebido e orçamento saem de bills, parcelas,
-- rateio, extrato, parcelas a receber por título e itens por planilha. Cobre rateio entre obras, campo ausente,
-- a obra com Bulk que não recebe o REST, a recarga repetida sem duplicar e os privilégios da função.
begin;
create extension if not exists pgtap with schema extensions;
select plan(31);

insert into app.tenant (id, razao_social) values ('0e000000-0000-4000-8000-0000000000c4', 'Construtora Só REST');
insert into app.centro_custo (id, tenant_id, id_origem, nome) values
  ('0c000000-0000-4000-8000-0000000000c1', '0e000000-0000-4000-8000-0000000000c4', 41, 'Obra Norte'),
  ('0c000000-0000-4000-8000-0000000000c2', '0e000000-0000-4000-8000-0000000000c4', 42, 'Obra Sul'),
  ('0c000000-0000-4000-8000-0000000000c3', '0e000000-0000-4000-8000-0000000000c4', 43, 'Obra com Bulk');

-- A pagar pelo REST. 5001: rateio 60/40 entre Norte e Sul, parcela 1 quitada, parcela 2 paga em parte.
-- 5002: metade na Norte e metade numa obra fora do painel. 5003: uma obra, sem percentual, parcela sem valor
-- nem situação. 5004: sem data nenhuma. 5009: rateio na obra com Bulk. 7001: mesmo título que veio pelo Bulk.
insert into raw.registro (tenant_id, endpoint, payload, hash_registro, chave_origem) values
  ('0e000000-0000-4000-8000-0000000000c4', 'bills',
   '{"id": 5001, "totalInvoiceAmount": 1000.0, "issueDate": "2026-07-01", "installmentsNumber": 2, "status": "S"}', 'b5001', '5001'),
  ('0e000000-0000-4000-8000-0000000000c4', 'bills', '{"id": 5002, "totalInvoiceAmount": 800}', 'b5002', '5002'),
  ('0e000000-0000-4000-8000-0000000000c4', 'bills', '{"id": 5003, "totalInvoiceAmount": "", "issueDate": "2026-08-01"}', 'b5003', '5003'),
  ('0e000000-0000-4000-8000-0000000000c4', 'bills', '{"id": 5004, "totalInvoiceAmount": 50}', 'b5004', '5004'),
  ('0e000000-0000-4000-8000-0000000000c4', 'bills', '{"id": 5005, "totalInvoiceAmount": 100, "issueDate": "2026-08-01"}', 'b5005', '5005'),
  ('0e000000-0000-4000-8000-0000000000c4', 'bills', '{"id": 5009, "totalInvoiceAmount": 70, "issueDate": "2026-08-01"}', 'b5009', '5009'),
  ('0e000000-0000-4000-8000-0000000000c4', 'bills', '{"id": 7001, "totalInvoiceAmount": 999, "issueDate": "2026-08-01"}', 'b7001', '7001'),
  ('0e000000-0000-4000-8000-0000000000c4', 'bills/installments',
   '{"billId": 5001, "installmentNumber": 1, "dueDate": "2026-08-10", "amount": 500.0, "situation": "Totalmente paga"}', 'i5001a', '5001'),
  ('0e000000-0000-4000-8000-0000000000c4', 'bills/installments',
   '{"billId": 5001, "installmentNumber": 2, "dueDate": "2026-09-10", "amount": 500.0, "situation": "Parcialmente paga"}', 'i5001b', '5001'),
  ('0e000000-0000-4000-8000-0000000000c4', 'bills/installments',
   '{"billId": 5002, "installmentNumber": 1, "dueDate": "2099-01-10", "amount": 800, "situation": "Não paga"}', 'i5002', '5002'),
  ('0e000000-0000-4000-8000-0000000000c4', 'bills/installments',
   '{"billId": 5003, "installmentNumber": 1, "dueDate": "2026-11-10"}', 'i5003', '5003'),
  ('0e000000-0000-4000-8000-0000000000c4', 'bills/installments', '{"billId": 5004}', 'i5004', '5004'),
  ('0e000000-0000-4000-8000-0000000000c4', 'bills/buildings-cost', '{"billId": 5001, "buildingId": 41, "percentage": 60}', 'r5001a', '5001'),
  ('0e000000-0000-4000-8000-0000000000c4', 'bills/buildings-cost', '{"billId": 5001, "buildingId": 42, "percentage": 40.0}', 'r5001b', '5001'),
  ('0e000000-0000-4000-8000-0000000000c4', 'bills/buildings-cost', '{"billId": 5002, "buildingId": 41, "percentage": 50}', 'r5002a', '5002'),
  ('0e000000-0000-4000-8000-0000000000c4', 'bills/buildings-cost', '{"billId": 5002, "buildingId": 99, "percentage": 50}', 'r5002b', '5002'),
  ('0e000000-0000-4000-8000-0000000000c4', 'bills/buildings-cost', '{"billId": 5003, "buildingId": 42}', 'r5003', '5003'),
  ('0e000000-0000-4000-8000-0000000000c4', 'bills/buildings-cost', '{"billId": 5004, "buildingId": 42, "percentage": 100}', 'r5004', '5004'),
  ('0e000000-0000-4000-8000-0000000000c4', 'bills/buildings-cost', '{"billId": 5005, "buildingId": 41}', 'r5005a', '5005'),
  ('0e000000-0000-4000-8000-0000000000c4', 'bills/buildings-cost', '{"billId": 5005, "buildingId": 42, "percentage": 40}', 'r5005b', '5005'),
  ('0e000000-0000-4000-8000-0000000000c4', 'bills/buildings-cost', '{"billId": 5009, "buildingId": 43, "percentage": 100}', 'r5009', '5009'),
  ('0e000000-0000-4000-8000-0000000000c4', 'bills/buildings-cost', '{"billId": 7001, "buildingId": 41, "percentage": 100}', 'r7001', '7001');

-- Extrato: pagamentos do 5001 (um sem type, só com origem CP e valor negativo) e recebimentos do título a receber
-- 9001, inclusive da parcela 3, que a API de parcelas não devolve mais.
insert into raw.registro (tenant_id, endpoint, payload, hash_registro, chave_origem) values
  ('0e000000-0000-4000-8000-0000000000c4', 'accounts-statements',
   '{"id": 1, "value": 500.0, "date": "2026-08-10", "type": "Expense", "billId": 5001, "installmentNumber": 1}', 'e1', '1'),
  ('0e000000-0000-4000-8000-0000000000c4', 'accounts-statements',
   '{"id": 2, "value": -200.0, "date": "2026-09-12", "statementOrigin": "CP", "billId": 5001, "installmentNumber": 2}', 'e2', '2'),
  ('0e000000-0000-4000-8000-0000000000c4', 'accounts-statements',
   '{"id": 3, "value": 300.0, "date": "2026-09-05", "type": "Income", "billId": 9001, "installmentNumber": 1}', 'e3', '3'),
  ('0e000000-0000-4000-8000-0000000000c4', 'accounts-statements',
   '{"id": 4, "value": 1000.0, "date": "2026-06-05", "type": "Income", "billId": 9001, "installmentNumber": 3}', 'e4', '4'),
  ('0e000000-0000-4000-8000-0000000000c4', 'accounts-statements',
   '{"id": 5, "value": 10.0, "date": "2026-06-05", "type": "Income", "billId": 9001}', 'e5', '5'),
  ('0e000000-0000-4000-8000-0000000000c4', 'accounts-statements',
   '{"id": 6, "value": 77.0, "date": "2026-06-05", "type": "Income", "billId": 5001, "installmentNumber": 1}', 'e6', '6');

-- A receber: contrato 801 da Norte com título 9001; 803 na obra com Bulk.
insert into raw.registro (tenant_id, endpoint, payload, hash_registro, chave_origem) values
  ('0e000000-0000-4000-8000-0000000000c4', 'sales-contracts',
   '{"id": 801, "enterpriseId": 41, "situation": "Emitido", "contractDate": "2026-01-10", "value": 300000, "receivableBillId": 9001}', 'c801', '801'),
  ('0e000000-0000-4000-8000-0000000000c4', 'sales-contracts',
   '{"id": 803, "enterpriseId": 43, "situation": "Emitido", "contractDate": "2026-01-10", "value": 1, "receivableBillId": 9003}', 'c803', '803'),
  ('0e000000-0000-4000-8000-0000000000c4', 'receivable-bills/installments',
   '{"receivableBillId": 9001, "installmentId": 1, "conditionTypeId": "PM", "dueDate": "2020-01-10", "balanceDue": 700.0}', 'p9001a', '9001'),
  ('0e000000-0000-4000-8000-0000000000c4', 'receivable-bills/installments',
   '{"receivableBillId": 9001, "installmentId": 2, "conditionTypeId": "FI", "dueDate": "2099-01-10", "balanceDue": 5000}', 'p9001b', '9001'),
  ('0e000000-0000-4000-8000-0000000000c4', 'receivable-bills/installments',
   '{"receivableBillId": 9001, "installmentId": 4, "dueDate": "2099-02-10"}', 'p9001c', '9001'),
  ('0e000000-0000-4000-8000-0000000000c4', 'receivable-bills/installments', '{"receivableBillId": 9002}', 'p9002', '9002'),
  ('0e000000-0000-4000-8000-0000000000c4', 'receivable-bills/installments',
   '{"receivableBillId": 9003, "installmentId": 1, "conditionTypeId": "PM", "dueDate": "2099-01-10", "balanceDue": 9}', 'p9003', '9003');

-- Orçamento por planilha. Norte: etapa 01 com dois itens na planilha 1 e o mesmo 01.001 na planilha 2.
-- Obra com Bulk: o item do REST fica de fora.
insert into raw.registro (tenant_id, endpoint, payload, hash_registro, chave_origem) values
  ('0e000000-0000-4000-8000-0000000000c4', 'building-cost-estimations/items',
   '{"buildingId": 41, "buildingUnitId": 1, "id": "a", "wbsCode": "01", "description": "Fundação", "totalPrice": 500}', 'o1', '41|1'),
  ('0e000000-0000-4000-8000-0000000000c4', 'building-cost-estimations/items',
   '{"buildingId": 41, "buildingUnitId": 1, "id": "b", "wbsCode": "01.001", "description": "Estaca", "totalPrice": 300}', 'o2', '41|1'),
  ('0e000000-0000-4000-8000-0000000000c4', 'building-cost-estimations/items',
   '{"buildingId": 41, "buildingUnitId": 1, "id": "c", "wbsCode": "01.002", "description": "Bloco", "totalPrice": "200"}', 'o3', '41|1'),
  ('0e000000-0000-4000-8000-0000000000c4', 'building-cost-estimations/items',
   '{"buildingId": 41, "buildingUnitId": 2, "id": "d", "wbsCode": "01.001", "description": "Estaca", "totalPrice": 50}', 'o4', '41|2'),
  ('0e000000-0000-4000-8000-0000000000c4', 'building-cost-estimations/items',
   '{"buildingId": 41, "buildingUnitId": 2, "id": "e", "wbsCode": "", "totalPrice": 1}', 'o5', '41|2'),
  ('0e000000-0000-4000-8000-0000000000c4', 'building-cost-estimations/items',
   '{"buildingId": 43, "buildingUnitId": 1, "id": "f", "wbsCode": "09", "totalPrice": 999}', 'o6', '43|1');

-- Bulk na obra 43: título, parcela a receber e item de orçamento.
insert into raw.registro (tenant_id, endpoint, payload, hash_registro, chave_origem) values
  ('0e000000-0000-4000-8000-0000000000c4', 'outcome',
   '{"billId": 7001, "installmentId": 1, "dueDate": "2026-10-01", "originalAmount": 100, "balanceAmount": 100,
     "buildingsCosts": [{"buildingId": 43, "amount": 100}], "payments": []}', 'bo7001', '7001|1'),
  ('0e000000-0000-4000-8000-0000000000c4', 'income',
   '{"billId": 7101, "installmentId": 1, "projectId": 43, "dueDate": "2026-10-01", "originalAmount": 10,
     "balanceAmount": 10, "paymentTerm": {"id": "PM"}, "receipts": []}', 'bi7101', '7101|1'),
  ('0e000000-0000-4000-8000-0000000000c4', 'building-cost-estimation-items',
   '{"id": 1, "buildingId": 43, "wbsCode": "09", "description": "Bulk", "totalPrice": 10}', 'bb1', '1');

select lives_ok($$select staging.recarregar('0e000000-0000-4000-8000-0000000000c4')$$, 'recarga do Bulk passa');
select lives_ok($$select staging.recarregar_financeiro_rest('0e000000-0000-4000-8000-0000000000c4')$$,
  'campo vazio ou ausente no REST não derruba a recarga');

-- Rateio entre obras
select results_eq(
  $$select cc.id_origem, rt.fracao, rt.valor from staging.rateio_titulo rt
    join app.centro_custo cc on cc.id = rt.centro_custo_id
    where rt.tenant_id = '0e000000-0000-4000-8000-0000000000c4' and rt.titulo_id_origem = 5001 order by 1$$,
  $$values (41, 0.6::numeric, 600.0::numeric), (42, 0.4::numeric, 400.0::numeric)$$,
  'título rateado 60/40 vira duas linhas de rateio, e não só a primeira obra');
select results_eq(
  $$select cc.id_origem, rt.fracao from staging.rateio_titulo rt join app.centro_custo cc on cc.id = rt.centro_custo_id
    where rt.tenant_id = '0e000000-0000-4000-8000-0000000000c4' and rt.titulo_id_origem = 5002$$,
  $$values (41, 0.5::numeric)$$,
  'obra fora do painel fica com a parte dela; a Norte não recebe 100%');
select results_eq(
  $$select cc.id_origem, rt.fracao from staging.rateio_titulo rt join app.centro_custo cc on cc.id = rt.centro_custo_id
    where rt.tenant_id = '0e000000-0000-4000-8000-0000000000c4' and rt.titulo_id_origem = 5005$$,
  $$values (42, 0.4::numeric)$$,
  'com uma obra sem percentual, a outra fica com os 40% dela e não com o título inteiro');
select is((select fracao from staging.rateio_titulo where tenant_id = '0e000000-0000-4000-8000-0000000000c4' and titulo_id_origem = 5003),
  1::numeric, 'uma obra só, sem percentual: vale o título inteiro');
select is((select centro_custo_id from staging.titulo_pagar where tenant_id = '0e000000-0000-4000-8000-0000000000c4' and id_origem = 5001),
  null, 'título dividido entre obras fica sem obra única, como no Bulk');
select is((select centro_custo_id from staging.titulo_pagar where tenant_id = '0e000000-0000-4000-8000-0000000000c4' and id_origem = 5003),
  '0c000000-0000-4000-8000-0000000000c2'::uuid, 'título de uma obra só fica com ela');

-- Saldo, vencimento e pagamento
select results_eq(
  $$select valor_original, saldo, vencimento, data_pagamento from staging.titulo_pagar
    where tenant_id = '0e000000-0000-4000-8000-0000000000c4' and id_origem = 5001$$,
  $$values (1000.0::numeric, 300.0::numeric, '2026-09-10'::date, '2026-09-12'::date)$$,
  'parcela quitada não tem saldo, a paga em parte desconta o extrato; vencimento é o da parcela em aberto');
select results_eq(
  $$select saldo, vencimento from staging.titulo_pagar where tenant_id = '0e000000-0000-4000-8000-0000000000c4' and id_origem = 5002$$,
  $$values (800::numeric, '2099-01-10'::date)$$, 'parcela não paga fica com o valor inteiro');
select results_eq(
  $$select valor_original, saldo, vencimento from staging.titulo_pagar
    where tenant_id = '0e000000-0000-4000-8000-0000000000c4' and id_origem = 5003$$,
  $$values (null::numeric, null::numeric, '2026-11-10'::date)$$, 'valor ausente fica nulo em vez de virar zero inventado');
select is((select count(*) from staging.titulo_pagar where tenant_id = '0e000000-0000-4000-8000-0000000000c4' and id_origem = 5004),
  0::bigint, 'título sem data nenhuma fica fora, sem derrubar os outros');
select results_eq(
  $$select sequencia, data_pagamento, valor from staging.pagamento
    where tenant_id = '0e000000-0000-4000-8000-0000000000c4' and titulo_id_origem = 5001 order by sequencia$$,
  $$values (1, '2026-08-10'::date, 500.0::numeric), (2, '2026-09-12'::date, 200.0::numeric)$$,
  'cada pagamento do extrato vira uma linha; origem CP vale sem type e o sinal negativo não inverte o valor');
select is((select count(*) from staging.pagamento where tenant_id = '0e000000-0000-4000-8000-0000000000c4' and titulo_id_origem = 5001),
  2::bigint, 'recebimento com o mesmo número de título não vira pagamento');
select results_eq(
  $$select competencia, saida_realizada from marts.fluxo_caixa_mensal
    where tenant_id = '0e000000-0000-4000-8000-0000000000c4' and centro_custo_id = '0c000000-0000-4000-8000-0000000000c1'
      and saida_realizada <> 0 order by 1$$,
  $$values ('2026-08-01'::date, 300.00::numeric), ('2026-09-01'::date, 120.00::numeric)$$,
  'o fluxo de caixa da Norte leva 60% de cada pagamento, sem mudar a view');

-- Bulk na frente
select is((select count(*) from staging.titulo_pagar where tenant_id = '0e000000-0000-4000-8000-0000000000c4' and id_origem = 5009),
  0::bigint, 'título do REST rateado em obra com Bulk não entra');
select results_eq(
  $$select valor_original, centro_custo_id from staging.titulo_pagar where tenant_id = '0e000000-0000-4000-8000-0000000000c4' and id_origem = 7001$$,
  $$values (100::numeric, '0c000000-0000-4000-8000-0000000000c3'::uuid)$$,
  'título que veio pelos dois caminhos fica com a versão do Bulk');

-- A receber
select results_eq(
  $$select id_origem, contrato_id_origem, vencimento, saldo, valor_original, tipo_condicao, origem, inadimplente,
           data_recebimento, valor_recebido
    from staging.parcela_receber where tenant_id = '0e000000-0000-4000-8000-0000000000c4'
      and centro_custo_id = '0c000000-0000-4000-8000-0000000000c1' order by id_origem$$,
  $$values (1, 801, '2020-01-10'::date, 700.0::numeric, 1000.0::numeric, 'PM', 'direta', true, '2026-09-05'::date, 300.0::numeric),
           (2, 801, '2099-01-10'::date, 5000::numeric, 5000::numeric, 'FI', 'repasse', false, null::date, null::numeric),
           (3, 801, '2026-06-05'::date, 0::numeric, 1000.0::numeric, null, 'direta', false, '2026-06-05'::date, 1000.0::numeric),
           (4, 801, '2099-02-10'::date, 0::numeric, 0::numeric, null, 'direta', false, null::date, null::numeric)$$,
  'parcela liga ao contrato pelo receivableBillId; quitada que só está no extrato entra com o recebido');
select results_eq(
  $$select parcela_id_origem, sequencia, data_recebimento, valor from staging.recebimento
    where tenant_id = '0e000000-0000-4000-8000-0000000000c4' and contrato_id_origem = 801 order by 1, 2$$,
  $$values (1, 1, '2026-09-05'::date, 300.0::numeric), (3, 1, '2026-06-05'::date, 1000.0::numeric)$$,
  'recebimento sem número de parcela e pagamento do a pagar ficam fora do recebido');
select is((select count(*) from staging.parcela_receber where tenant_id = '0e000000-0000-4000-8000-0000000000c4' and contrato_id_origem = 803),
  0::bigint, 'obra com Bulk de a receber não recebe parcela do REST');
select is((select count(*) from staging.parcela_receber where tenant_id = '0e000000-0000-4000-8000-0000000000c4'
  and centro_custo_id = '0c000000-0000-4000-8000-0000000000c3'), 1::bigint, 'a parcela do Bulk continua lá');
select is((select count(*) from marts.fluxo_caixa_mensal where tenant_id = '0e000000-0000-4000-8000-0000000000c4'
  and centro_custo_id = '0c000000-0000-4000-8000-0000000000c1' and repasse_previsto = 5000),
  1::bigint, 'repasse previsto do REST chega no fluxo de caixa');

-- Orçamento
select results_eq(
  $$select codigo, descricao, valor_total from staging.item_orcamento
    where tenant_id = '0e000000-0000-4000-8000-0000000000c4' and centro_custo_id = '0c000000-0000-4000-8000-0000000000c1' order by 1$$,
  $$values ('01.001', 'Estaca', 350::numeric), ('01.002', 'Bloco', 200::numeric)$$,
  'etapa não soma de novo, código vazio fica fora e o mesmo código nas duas planilhas é somado');
select results_eq(
  $$select codigo, valor_total from staging.item_orcamento
    where tenant_id = '0e000000-0000-4000-8000-0000000000c4' and centro_custo_id = '0c000000-0000-4000-8000-0000000000c3'$$,
  $$values ('09', 10::numeric)$$, 'obra com orçamento pelo Bulk fica só com ele');

-- Recarga repetida
select lives_ok($$select staging.recarregar('0e000000-0000-4000-8000-0000000000c4');
                 select staging.recarregar_financeiro_rest('0e000000-0000-4000-8000-0000000000c4')$$,
  'segunda recarga passa');
select results_eq(
  $$select (select count(*) from staging.titulo_pagar where tenant_id = '0e000000-0000-4000-8000-0000000000c4'),
           (select count(*) from staging.rateio_titulo where tenant_id = '0e000000-0000-4000-8000-0000000000c4'),
           (select count(*) from staging.pagamento where tenant_id = '0e000000-0000-4000-8000-0000000000c4'),
           (select count(*) from staging.parcela_receber where tenant_id = '0e000000-0000-4000-8000-0000000000c4'),
           (select count(*) from staging.recebimento where tenant_id = '0e000000-0000-4000-8000-0000000000c4'),
           (select count(*) from staging.item_orcamento where tenant_id = '0e000000-0000-4000-8000-0000000000c4')$$,
  $$values (5::bigint, 7::bigint, 2::bigint, 5::bigint, 2::bigint, 3::bigint)$$,
  'recarregar de novo não duplica nada');
select lives_ok($$select staging.recarregar_financeiro_rest('0e000000-0000-4000-8000-0000000000c4')$$,
  'chamar o REST duas vezes seguidas também não falha');
select is((select count(*) from staging.pagamento where tenant_id = '0e000000-0000-4000-8000-0000000000c4'),
  2::bigint, 'e não duplica: o REST não entra em cima dele mesmo');

-- Privilégios
select ok(
  not has_function_privilege('anon', 'staging.recarregar_financeiro_rest(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'staging.recarregar_financeiro_rest(uuid)', 'execute')
  and not has_function_privilege('public', 'staging.recarregar_financeiro_rest(uuid)', 'execute'),
  'só o carregador executa a recarga');
select ok(
  (select prosecdef and proconfig = array['search_path=""'] from pg_proc
   where oid = 'staging.recarregar_financeiro_rest(uuid)'::regprocedure),
  'security definer com search_path vazio');
select is((select count(*) from staging.titulo_pagar where tenant_id = '0e000000-0000-4000-8000-0000000000c4'
  and centro_custo_id is null), 1::bigint, 'só o título com mais de uma obra do painel fica sem obra única');

select * from finish();
rollback;
