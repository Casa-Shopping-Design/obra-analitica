-- Unidade e contrato no formato real da API (migration 0039). Unidade: valor sugerido em evaluation, tabela em
-- specialValues[].tablePricesId, entrega prevista quando falta a efetiva, campos vazios ou ausentes sem derrubar
-- a recarga, e o formato antigo ainda aceito. Contrato: sem Bulk de vendas, vem do REST sales-contracts, com a
-- situação por extenso; obra que tem Bulk não recebe o REST.
begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

insert into app.tenant (id, razao_social) values ('0e000000-0000-4000-8000-0000000000b1', 'Construtora Unidades');
insert into app.centro_custo (id, tenant_id, id_origem, nome) values
  ('0c000000-0000-4000-8000-0000000000b1', '0e000000-0000-4000-8000-0000000000b1', 31, 'Obra Unidades'),
  ('0c000000-0000-4000-8000-0000000000b2', '0e000000-0000-4000-8000-0000000000b1', 32, 'Obra com Bulk');

insert into raw.registro (tenant_id, endpoint, payload, hash_registro, chave_origem) values
  ('0e000000-0000-4000-8000-0000000000b1', 'units', '{
     "id": 501, "enterpriseId": 31, "name": "Apto 101", "propertyType": "Apto", "commercialStock": "D",
     "privateArea": 58.4, "deliveryDate": null, "scheduledDeliveryDate": "2027-03-01", "indexerId": 0,
     "evaluation": {"saleValuePrice": 120000.0, "saleValueDate": "2026-01-10"},
     "specialValues": [{"indexedQuantity": 0.0}, {"tablePricesId": 9, "indexedQuantity": 265000.0}]
   }', 'u501', '501'),
  ('0e000000-0000-4000-8000-0000000000b1', 'units', '{
     "id": 502, "enterpriseId": 31, "name": "", "propertyType": "", "commercialStock": "V",
     "privateArea": "", "deliveryDate": "2026-09-23", "evaluation": null, "specialValues": null, "indexerId": 4
   }', 'u502', '502'),
  ('0e000000-0000-4000-8000-0000000000b1', 'units', '{
     "id": 503, "enterpriseId": 31, "name": "SALA-0102", "commercialStock": "D", "privateArea": 40,
     "deliveryDate": "2026-12-01", "saleValuePrice": 300000, "saleValueDate": "2026-02-01", "tablePricesID": 7,
     "indexerId": 1
   }', 'u503', '503'),
  ('0e000000-0000-4000-8000-0000000000b1', 'units', '{
     "id": 504, "enterpriseId": "obra sem código", "name": "Fora", "commercialStock": "D"
   }', 'u504', '504');

insert into raw.registro (tenant_id, endpoint, payload, hash_registro, chave_origem) values
  ('0e000000-0000-4000-8000-0000000000b1', 'sales-contracts', '{
     "id": 2019, "enterpriseId": 31, "number": "C-2019", "situation": "Emitido", "contractDate": "2026-10-01",
     "value": 175000.0, "totalSellingValue": 140000.0, "cancellationDate": null,
     "financialInstitutionNumber": null, "financialInstitutionDate": null,
     "salesContractUnits": [{"id": 9001}, {"id": 501, "main": true}]
   }', 'c2019', '2019'),
  ('0e000000-0000-4000-8000-0000000000b1', 'sales-contracts', '{
     "id": 2020, "enterpriseId": 31, "number": "C-2020", "situation": "Cancelado", "contractDate": "2026-08-01",
     "value": 90000, "cancellationDate": "2026-09-15", "financialInstitutionNumber": "104",
     "financialInstitutionDate": "2026-08-20", "salesContractUnits": [{"id": 502}]
   }', 'c2020', '2020'),
  ('0e000000-0000-4000-8000-0000000000b1', 'sales-contracts', '{
     "id": 2021, "enterpriseId": 31, "situation": "Autorizado", "issueDate": "2026-09-30", "totalSellingValue": 80000
   }', 'c2021', '2021'),
  ('0e000000-0000-4000-8000-0000000000b1', 'sales-contracts', '{
     "id": 3001, "enterpriseId": 32, "situation": "Emitido", "contractDate": "2026-07-01", "value": 1
   }', 'c3001', '3001'),
  ('0e000000-0000-4000-8000-0000000000b1', 'sales', '{
     "id": 3002, "enterpriseId": 32, "number": "B-3002", "situation": "1", "contractDate": "2026-07-01",
     "value": 250000, "customers": [], "units": [{"id": 777}]
   }', 's3002', '3002');

select lives_ok($$select staging.recarregar('0e000000-0000-4000-8000-0000000000b1')$$,
  'campo vazio, nulo ou ausente não derruba a recarga');
select lives_ok($$select staging.recarregar_precos('0e000000-0000-4000-8000-0000000000b1')$$,
  'a recarga de preços também passa');

select is((select count(*) from staging.unidade where tenant_id = '0e000000-0000-4000-8000-0000000000b1'), 3::bigint,
  'unidade com obra que não é código fica de fora sem erro');
select is((select data_entrega from staging.unidade where id_origem = 501 and tenant_id = '0e000000-0000-4000-8000-0000000000b1'),
  '2027-03-01'::date, 'sem data efetiva vale a prevista');
select is((select data_entrega from staging.unidade where id_origem = 502 and tenant_id = '0e000000-0000-4000-8000-0000000000b1'),
  '2026-09-23'::date, 'com data efetiva vale a efetiva');
select is((select nome from staging.unidade where id_origem = 502 and tenant_id = '0e000000-0000-4000-8000-0000000000b1'),
  'Unidade 502', 'unidade sem nome ganha o código');
select is((select area_privativa from staging.unidade where id_origem = 502 and tenant_id = '0e000000-0000-4000-8000-0000000000b1'),
  null, 'área vazia vira nula, não erro');

select results_eq(
  $$select valor_sugerido, data_valor_sugerido, indexador_id_origem, tabela_id_origem
    from staging.unidade_valor where tenant_id = '0e000000-0000-4000-8000-0000000000b1' and unidade_id_origem = 501$$,
  $$values (120000.0::numeric, '2026-01-10'::date, null::integer, 9)$$,
  'formato da API: valor em evaluation, tabela no primeiro specialValues que tem tablePricesId, indexador 0 é nenhum'
);
select results_eq(
  $$select valor_sugerido, tabela_id_origem from staging.unidade_valor
    where tenant_id = '0e000000-0000-4000-8000-0000000000b1' and unidade_id_origem = 502$$,
  $$values (null::numeric, null::integer)$$,
  'sem evaluation nem specialValues a unidade fica sem valor de cadastro'
);
select results_eq(
  $$select valor_sugerido, data_valor_sugerido, indexador_id_origem, tabela_id_origem
    from staging.unidade_valor where tenant_id = '0e000000-0000-4000-8000-0000000000b1' and unidade_id_origem = 503$$,
  $$values (300000::numeric, '2026-02-01'::date, 1, 7)$$,
  'formato antigo, com tudo no nível da unidade, segue aceito'
);

select is((select count(*) from staging.unidade_valor where tenant_id = '0e000000-0000-4000-8000-0000000000b1'), 3::bigint,
  'um valor por unidade carregada');
select lives_ok($$select staging.recarregar('0e000000-0000-4000-8000-0000000000b1')$$, 'recarregar de novo não duplica nem falha');

select results_eq(
  $$select id_origem, situacao, valor, data_venda, data_distrato, banco_repasse, unidade_id_origem, nome_cliente
    from staging.contrato_venda where tenant_id = '0e000000-0000-4000-8000-0000000000b1' and id_origem in (2019, 2020, 2021)
    order by id_origem$$,
  $$values (2019, '1', 175000.0::numeric, '2026-10-01'::date, null::date, null::text, 501, null::text),
           (2020, '3', 90000::numeric, '2026-08-01'::date, '2026-09-15'::date, '104', 502, null),
           (2021, '0', 80000::numeric, '2026-09-30'::date, null, null, null, null)$$,
  'sem Bulk o contrato vem do REST: emitido é venda, cancelado é distrato, autorizado ainda não; unidade principal'
);
select results_eq(
  $$select id_origem, valor from staging.contrato_venda
    where tenant_id = '0e000000-0000-4000-8000-0000000000b1'
      and centro_custo_id = '0c000000-0000-4000-8000-0000000000b2'$$,
  $$values (3002, 250000::numeric)$$,
  'obra que tem contrato pelo Bulk não recebe o REST'
);

select * from finish();
rollback;
