-- Rotas complementares do ERP com caso conhecido: mapa imobiliário lado a lado com o painel, medição
-- física com tarefa que pula medição e medição ainda não aprovada, inadimplência por faixa só da
-- posição mais recente, e isolamento entre tenants e entre obras. Cria os próprios dados.
begin;
create extension if not exists pgtap with schema extensions;
select plan(33);

insert into app.tenant (id, razao_social) values
  ('0e000000-0000-4000-8000-0000000000f1', 'Construtora Complementos'),
  ('0e000000-0000-4000-8000-0000000000f2', 'Construtora Complementos vizinha');

insert into app.centro_custo (id, tenant_id, id_origem, nome) values
  ('0c000000-0000-4000-8000-0000000000f1', '0e000000-0000-4000-8000-0000000000f1', 981, 'Obra Mapa A'),
  ('0c000000-0000-4000-8000-0000000000f2', '0e000000-0000-4000-8000-0000000000f1', 982, 'Obra Mapa B'),
  ('0c000000-0000-4000-8000-0000000000f3', '0e000000-0000-4000-8000-0000000000f2', 981, 'Obra vizinha');

insert into auth.users (id, email) values
  ('0a000000-0000-4000-8000-00000000f0d1', 'diretor.complementos@teste.invalid'),
  ('0a000000-0000-4000-8000-00000000f0e1', 'gerente.complementos@teste.invalid'),
  ('0a000000-0000-4000-8000-00000000f0e2', 'gerente.obra.a@teste.invalid'),
  ('0a000000-0000-4000-8000-00000000f0f1', 'financeiro.complementos@teste.invalid');

insert into app.usuario_tenant (user_id, tenant_id, perfil) values
  ('0a000000-0000-4000-8000-00000000f0d1', '0e000000-0000-4000-8000-0000000000f1', 'diretor'),
  ('0a000000-0000-4000-8000-00000000f0e1', '0e000000-0000-4000-8000-0000000000f1', 'gerente_obra'),
  ('0a000000-0000-4000-8000-00000000f0e2', '0e000000-0000-4000-8000-0000000000f1', 'gerente_obra'),
  ('0a000000-0000-4000-8000-00000000f0f1', '0e000000-0000-4000-8000-0000000000f1', 'financeiro');

insert into app.usuario_centro_custo (user_id, tenant_id, centro_custo_id) values
  ('0a000000-0000-4000-8000-00000000f0e1', '0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f2'),
  ('0a000000-0000-4000-8000-00000000f0e2', '0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f1');

-- Painel da obra A: VGV 600 mil vendido mais 390 mil em estoque; recebido 250 mil até agosto e 60 mil
-- em setembro; custo pago 150 mil em junho, 40 mil em aberto vencendo em agosto e 70 mil em outubro.
insert into staging.unidade (tenant_id, centro_custo_id, id_origem, nome, tipologia, area_privativa, situacao) values
  ('0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f1', 1, '2Q-0101', '2Q', 50, 'V'),
  ('0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f1', 2, '2Q-0102', '2Q', 50, 'D');
insert into staging.unidade_valor (tenant_id, centro_custo_id, unidade_id_origem, valor_sugerido) values
  ('0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f1', 1, 580000),
  ('0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f1', 2, 390000);
insert into staging.contrato_venda (tenant_id, centro_custo_id, id_origem, data_venda, valor, situacao, unidade_id_origem) values
  ('0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f1', 10, '2026-01-10', 600000, '1', 1);
insert into staging.parcela_receber (tenant_id, centro_custo_id, id_origem, contrato_id_origem, vencimento, valor_original, saldo, tipo_condicao) values
  ('0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f1', 1, 10, '2026-07-10', 250000, 0, 'AT'),
  ('0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f1', 2, 10, '2026-09-05', 60000, 0, 'PM');
insert into staging.recebimento (tenant_id, centro_custo_id, contrato_id_origem, parcela_id_origem, sequencia, data_recebimento, valor) values
  ('0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f1', 10, 1, 1, '2026-07-10', 250000),
  ('0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f1', 10, 2, 1, '2026-09-05', 60000);
insert into staging.titulo_pagar (tenant_id, centro_custo_id, id_origem, vencimento, valor_original, saldo, data_pagamento) values
  ('0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f1', 1, '2026-06-15', 150000, 0, '2026-06-15'),
  ('0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f1', 2, '2026-08-20', 40000, 40000, null),
  ('0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f1', 3, '2026-10-10', 70000, 70000, null);
insert into staging.rateio_titulo (tenant_id, titulo_id_origem, centro_custo_id, valor, fracao) values
  ('0e000000-0000-4000-8000-0000000000f1', 1, '0c000000-0000-4000-8000-0000000000f1', 150000, 1),
  ('0e000000-0000-4000-8000-0000000000f1', 2, '0c000000-0000-4000-8000-0000000000f1', 40000, 1),
  ('0e000000-0000-4000-8000-0000000000f1', 3, '0c000000-0000-4000-8000-0000000000f1', 70000, 1);
insert into staging.pagamento (tenant_id, centro_custo_id, titulo_id_origem, sequencia, data_pagamento, valor) values
  ('0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f1', 1, 1, '2026-06-15', 150000);
insert into staging.item_orcamento (tenant_id, centro_custo_id, codigo, descricao, valor_total) values
  ('0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f1', '01', 'Estrutura', 500000);

-- Mapa do ERP: julho e agosto da obra A, um mês torto que não pode entrar e o mapa do tenant vizinho
-- com o mesmo código de obra.
insert into raw.registro (tenant_id, endpoint, payload, hash_registro) values
  ('0e000000-0000-4000-8000-0000000000f1', 'real-estate-map',
   '{"enterpriseData": {"enterpriseId": 981, "monthYear": "07/2026", "units": 2},
     "vgvData": {"vgv": 1000000, "poc": 30},
     "accumulatedReceipts": {"accumulatedReceipt": 250000, "monthlyReceipt": 250000},
     "budgetedAndIncurredCost": {"budgetedCost": 500000, "accumulatedIncurredCost": 150000, "costToIncur": 350000}}',
   'mapa-a-07'),
  ('0e000000-0000-4000-8000-0000000000f1', 'real-estate-map',
   '{"enterpriseData": {"enterpriseId": 981, "monthYear": "08/2026", "units": 2},
     "vgvData": {"vgv": 1000000, "poc": 40},
     "accumulatedReceipts": {"accumulatedReceipt": 300000, "monthlyReceipt": 50000},
     "budgetedAndIncurredCost": {"budgetedCost": 500000, "accumulatedIncurredCost": 200000,
                                 "costToIncur": 300000, "monthlyIncurredCost": 50000},
     "margin": {"accumulatedRevenue": 240000, "accruedCost": 80000, "grossProfit": 160000, "(%)": 0.6667}}',
   'mapa-a-08'),
  ('0e000000-0000-4000-8000-0000000000f1', 'real-estate-map',
   '{"enterpriseData": {"enterpriseId": 981, "monthYear": "2026-08"}, "vgvData": {"vgv": 1}}',
   'mapa-a-torto'),
  ('0e000000-0000-4000-8000-0000000000f2', 'real-estate-map',
   '{"enterpriseData": {"enterpriseId": 981, "monthYear": "08/2026"}, "vgvData": {"vgv": 999}}',
   'mapa-vizinho');

-- Medição da obra A: duas tarefas (valor planejado 1.000 cada) e um agrupador que não pode contar.
-- Julho mede a tarefa 1 pela metade; agosto só mede a tarefa 2; setembro ainda está em aprovação.
insert into raw.registro (tenant_id, endpoint, payload, hash_registro)
select '0e000000-0000-4000-8000-0000000000f1', 'building-projects/progress-logs/items', m::jsonb, md5(m)
from unnest(array[
  '{"buildingId": 981, "measurementNumber": 1, "buildingUnitId": 1, "date": "2026-07-15", "statusApproval": "APROVADA", "consistent": true, "taskId": 1, "summary": false, "plannedQuantity": 100, "cumulativeMeasuredQuantity": 50, "unitPrice": 10}',
  '{"buildingId": 981, "measurementNumber": 1, "buildingUnitId": 1, "date": "2026-07-15", "statusApproval": "APROVADA", "consistent": true, "taskId": 2, "summary": false, "plannedQuantity": 50, "cumulativeMeasuredQuantity": 0, "unitPrice": 20}',
  '{"buildingId": 981, "measurementNumber": 1, "buildingUnitId": 1, "date": "2026-07-15", "statusApproval": "APROVADA", "consistent": true, "taskId": 9, "summary": true, "plannedQuantity": 1, "cumulativeMeasuredQuantity": 1, "unitPrice": 999999}',
  '{"buildingId": 981, "measurementNumber": 2, "buildingUnitId": 1, "date": "2026-08-10", "statusApproval": "APROVADA", "consistent": true, "taskId": 2, "summary": false, "plannedQuantity": 50, "cumulativeMeasuredQuantity": 25, "unitPrice": 20}',
  '{"buildingId": 981, "measurementNumber": 3, "buildingUnitId": 1, "date": "2026-09-05", "statusApproval": "EM_APROVACAO", "consistent": true, "taskId": 1, "summary": false, "plannedQuantity": 100, "cumulativeMeasuredQuantity": 100, "unitPrice": 10}'
]) as m;

-- Inadimplência: posição de 20/09 com três títulos da obra A (um sem centro de custo, achado pelo
-- contrato), um da obra B, a posição velha de 10/09 que não pode entrar e o marcador de posição.
insert into raw.registro (tenant_id, endpoint, payload, hash_registro)
select t, 'defaulters-receivable-bills/by-aging', m::jsonb, md5(t || m)
from (values
  ('0e000000-0000-4000-8000-0000000000f1'::uuid, '{"positionDate": "2026-09-20", "receivableBillId": 501, "costCentersId": [981], "defaulterInstallments": [{"daysOfDelay": 10, "dueDate": "2026-09-10", "correctedValueWithoutAdditions": "1000.00", "correctedValueWithAdditions": "1100.00"}]}'),
  ('0e000000-0000-4000-8000-0000000000f1', '{"positionDate": "2026-09-20", "receivableBillId": 502, "costCentersId": [981], "defaulterInstallments": [{"daysOfDelay": 45, "dueDate": "2026-08-06", "correctedValueWithoutAdditions": "2000.00"}, {"daysOfDelay": 95, "dueDate": "2026-06-17", "correctedValueWithoutAdditions": "3000.00"}]}'),
  ('0e000000-0000-4000-8000-0000000000f1', '{"positionDate": "2026-09-20", "receivableBillId": 10, "defaulterInstallments": [{"daysOfDelay": 200, "dueDate": "2026-03-04", "correctedValueWithoutAdditions": "1.234,56"}]}'),
  ('0e000000-0000-4000-8000-0000000000f1', '{"positionDate": "2026-09-20", "receivableBillId": 601, "costCentersId": [982], "defaulterInstallments": [{"daysOfDelay": 31, "correctedValueWithoutAdditions": "700"}]}'),
  ('0e000000-0000-4000-8000-0000000000f1', '{"positionDate": "2026-09-10", "receivableBillId": 504, "costCentersId": [981], "defaulterInstallments": [{"daysOfDelay": 40, "correctedValueWithoutAdditions": "9999"}]}'),
  ('0e000000-0000-4000-8000-0000000000f1', '{"positionDate": "2026-09-20"}'),
  ('0e000000-0000-4000-8000-0000000000f2', '{"positionDate": "2026-09-20", "receivableBillId": 501, "costCentersId": [981], "defaulterInstallments": [{"daysOfDelay": 5, "correctedValueWithoutAdditions": "5"}]}')
) as d(t, m);

select staging.recarregar_complementos('0e000000-0000-4000-8000-0000000000f1');
select staging.recarregar_complementos('0e000000-0000-4000-8000-0000000000f2');
-- Recarregar de novo não duplica nada.
select staging.recarregar_complementos('0e000000-0000-4000-8000-0000000000f1');

select is(
  (select count(*) from staging.mapa_imobiliario_mensal where tenant_id = '0e000000-0000-4000-8000-0000000000f1'),
  2::bigint,
  'mapa tem julho e agosto; mês em formato torto fica de fora'
);
select is(
  (select row(vgv, poc, recebido_acumulado, custo_orcado, custo_incorrido_acumulado, custo_a_incorrer, lucro_bruto, margem)::text
   from staging.mapa_imobiliario_mensal
   where centro_custo_id = '0c000000-0000-4000-8000-0000000000f1' and competencia = '2026-08-01'),
  '(1000000,40,300000,500000,200000,300000,160000,0.6667)',
  'mapa de agosto com os valores do ERP'
);
select is(
  (select vgv from staging.mapa_imobiliario_mensal where tenant_id = '0e000000-0000-4000-8000-0000000000f2'),
  999::numeric,
  'recarga de um tenant não pega o mapa do outro com o mesmo código de obra'
);

select is(
  (select row(competencia_origem, vgv_painel, vgv_origem, diferenca_vgv)::text
   from marts.conferencia_origem where centro_custo_id = '0c000000-0000-4000-8000-0000000000f1'),
  '(2026-08-01,990000,1000000,-10000)',
  'VGV do painel lado a lado com o do ERP no último mês do mapa'
);
select is(
  (select row(custo_incorrido_painel, custo_incorrido_origem, diferenca_custo_incorrido, diferenca_custo_incorrido_pct)::text
   from marts.conferencia_origem where centro_custo_id = '0c000000-0000-4000-8000-0000000000f1'),
  '(190000.00,200000,-10000.00,-0.0500)',
  'custo incorrido do painel: pago até agosto mais aberto que vence até agosto'
);
select is(
  (select row(recebido_painel, recebido_origem, diferenca_recebido)::text
   from marts.conferencia_origem where centro_custo_id = '0c000000-0000-4000-8000-0000000000f1'),
  '(250000.00,300000,-50000.00)',
  'recebido de setembro não entra na conferência de agosto'
);
select is(
  (select row(custo_orcado_painel, custo_orcado_origem, diferenca_custo_orcado)::text
   from marts.conferencia_origem where centro_custo_id = '0c000000-0000-4000-8000-0000000000f1'),
  '(500000,500000,0)',
  'orçado confere'
);
select is(
  (select count(*) from marts.conferencia_origem where tenant_id = '0e000000-0000-4000-8000-0000000000f1'),
  1::bigint,
  'obra sem mapa do ERP não aparece na conferência'
);

select is(
  (select count(*) from staging.medicao_obra where tenant_id = '0e000000-0000-4000-8000-0000000000f1'),
  5::bigint,
  'medição grava todas as tarefas, inclusive agrupador e medição em aprovação'
);
select is(
  (select pct_fisico from marts.execucao_fisica_obra
   where centro_custo_id = '0c000000-0000-4000-8000-0000000000f1' and competencia = '2026-07-01'),
  0.25::numeric,
  'julho: metade da tarefa 1 sobre o planejado das duas, agrupador fora'
);
select is(
  (select pct_fisico from marts.execucao_fisica_obra
   where centro_custo_id = '0c000000-0000-4000-8000-0000000000f1' and competencia = '2026-08-01'),
  0.5::numeric,
  'agosto: tarefa 1 segue com o acumulado de julho e a tarefa 2 entra pela metade'
);
select is(
  (select pct_fisico from marts.execucao_fisica_obra
   where centro_custo_id = '0c000000-0000-4000-8000-0000000000f1' and competencia = '2026-09-01'),
  0.5::numeric,
  'setembro: medição em aprovação não conta'
);
select is(
  (select row(pago_acumulado, pct_financeiro, pct_financeiro_origem, diferenca_financeiro_fisico)::text
   from marts.execucao_fisica_obra
   where centro_custo_id = '0c000000-0000-4000-8000-0000000000f1' and competencia = '2026-08-01'),
  '(150000.00,0.3000,0.4000,-0.2000)',
  'agosto: pago sobre orçado, incorrido do ERP sobre orçado e a diferença contra o físico'
);

select is(
  (select count(*) from staging.inadimplencia where tenant_id = '0e000000-0000-4000-8000-0000000000f1'),
  4::bigint,
  'só a posição mais recente entra; marcador de posição não vira título'
);
select results_eq(
  $$select faixa, titulos, parcelas, valor_atrasado from marts.inadimplencia_faixa
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000f1' order by ordem$$,
  $$values ('1-30', 1, 1, 1000.00::numeric), ('31-90', 0, 0, 0::numeric),
           ('91-180', 1, 2, 5000.00::numeric), ('>180', 1, 1, 1234.56::numeric)$$,
  'faixas da obra A pelo maior atraso do título; título sem centro de custo acha a obra pelo contrato'
);
select is(
  (select row(titulos, valor_atrasado, data_posicao)::text from marts.inadimplencia_faixa
   where centro_custo_id = '0c000000-0000-4000-8000-0000000000f2' and faixa = '31-90'),
  '(1,700,2026-09-20)',
  '31 dias cai em 31-90'
);
select is(
  (select valor_atualizado from staging.inadimplencia where titulo_id_origem = 501
     and tenant_id = '0e000000-0000-4000-8000-0000000000f1'),
  1100.00::numeric,
  'valor com acréscimos preservado'
);

select ok(
  (select bool_and(c.relrowsecurity and c.relforcerowsecurity) from pg_class c
   where c.oid in ('staging.mapa_imobiliario_mensal'::regclass, 'staging.medicao_obra'::regclass,
                   'staging.inadimplencia'::regclass)),
  'RLS ligado e forçado nas três tabelas'
);
select is(
  (select count(*) from pg_policies where schemaname = 'staging'
     and tablename in ('mapa_imobiliario_mensal', 'medicao_obra', 'inadimplencia')
     and permissive = 'PERMISSIVE'),
  3::bigint,
  'uma política permissiva por tabela'
);
select ok(
  (select bool_and(c.reloptions @> array['security_invoker=true']) from pg_class c
   where c.oid in ('marts.conferencia_origem'::regclass, 'marts.execucao_fisica_obra'::regclass,
                   'marts.inadimplencia_faixa'::regclass)),
  'as três views respeitam o RLS de quem consulta'
);
select ok(
  not has_function_privilege('authenticated', 'staging.recarregar_complementos(uuid)', 'execute')
  and not has_function_privilege('anon', 'staging.recarregar_complementos(uuid)', 'execute'),
  'usuário da API não executa a recarga'
);
select ok(
  not has_table_privilege('anon', 'staging.inadimplencia', 'select')
  and not has_table_privilege('anon', 'marts.inadimplencia_faixa', 'select'),
  'anônimo não lê inadimplência'
);

select ok(
  staging.numero_origem('1e200000') is null and staging.numero_origem(repeat('9', 140000)) is null
  and staging.numero_origem('1.234,56') = 1234.56 and staging.numero_origem('1.5e2') = 150,
  'número que estoura o numeric vira nulo; formatos válidos continuam lidos'
);

-- Diretor do tenant 1
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-00000000f0d1", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;

select is((select count(*) from staging.mapa_imobiliario_mensal), 2::bigint, 'diretor não vê mapa de outro tenant');
select is((select count(*) from staging.inadimplencia), 4::bigint, 'diretor não vê inadimplência de outro tenant');
select is(
  (select count(distinct centro_custo_id) from marts.inadimplencia_faixa), 2::bigint,
  'diretor vê a inadimplência das duas obras'
);

-- Gerente da obra B
reset role;
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-00000000f0e1", "role": "authenticated"}', true);
set local role authenticated;

select is(
  (select count(*) from marts.conferencia_origem) + (select count(*) from staging.mapa_imobiliario_mensal),
  0::bigint,
  'gerente da obra B não vê o mapa nem a conferência da obra A'
);
select is(
  (select count(*) from marts.execucao_fisica_obra) + (select count(*) from staging.medicao_obra),
  0::bigint,
  'gerente da obra B não vê a medição da obra A'
);
select results_eq(
  'select distinct centro_custo_id from marts.inadimplencia_faixa',
  $$values ('0c000000-0000-4000-8000-0000000000f2'::uuid)$$,
  'gerente vê a inadimplência só da obra dele'
);
select throws_ok(
  $$select staging.recarregar_complementos('0e000000-0000-4000-8000-0000000000f1')$$,
  '42501',
  null,
  'gerente não consegue recarregar os complementos'
);

-- Gerente da obra A, que tem mapa: a conferência é só de diretor e financeiro, mesmo na obra dele.
reset role;
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-00000000f0e2", "role": "authenticated"}', true);
set local role authenticated;
select is(
  (select count(*) from marts.conferencia_origem) + (select count(*) from staging.mapa_imobiliario_mensal),
  0::bigint,
  'gerente da obra A não lê a conferência nem o mapa da própria obra'
);
select ok(
  (select count(*) > 0 and bool_and(pct_financeiro_origem is null) from marts.execucao_fisica_obra),
  'gerente da obra A vê a execução física sem o percentual que vem do mapa'
);

-- Financeiro do tenant
reset role;
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-00000000f0f1", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;
select is(
  (select count(*) from marts.conferencia_origem where centro_custo_id = '0c000000-0000-4000-8000-0000000000f1'),
  1::bigint,
  'financeiro lê a conferência'
);

select * from finish();
rollback;
