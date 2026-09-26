-- Revisão independente das migrations 0007, 0011, 0012 e 0013 com casos próprios, valores calculados à mão
-- e diferentes dos de docs/financeiro/casos_teste.md. Tudo roda numa transação que termina em rollback,
-- com tenants e UUIDs próprios, e cada consulta filtra pelo próprio tenant: passa em banco limpo e com a demo.
-- As contas de cada número estão em docs/financeiro/revisao.md, seção "Casos independentes".
begin;
select * from no_plan();

\set tr 'a1000000-0000-4000-8000-000000000001'
\set tx 'a1000000-0000-4000-8000-000000000002'
\set ud 'b1000000-0000-4000-8000-000000000001'
\set ug 'b1000000-0000-4000-8000-000000000002'
\set ul 'b1000000-0000-4000-8000-000000000003'
\set uf 'b1000000-0000-4000-8000-000000000004'
\set ux 'b1000000-0000-4000-8000-000000000005'
\set oa 'c1000000-0000-4000-8000-000000000001'
\set ob 'c1000000-0000-4000-8000-000000000002'
\set oc 'c1000000-0000-4000-8000-000000000003'
\set od 'c1000000-0000-4000-8000-000000000004'
\set ox 'c1000000-0000-4000-8000-000000000005'

-- Montagem, como dono do banco

insert into app.tenant (id, razao_social) values (:'tr', 'Tenant sintetico da revisao R'), (:'tx', 'Tenant sintetico da revisao X');
insert into auth.users (id, email) values
  (:'ud', 'diretor.revisao@exemplo.invalid'), (:'ug', 'gerente.revisao@exemplo.invalid'),
  (:'ul', 'leitura.revisao@exemplo.invalid'), (:'uf', 'financeiro.revisao@exemplo.invalid'),
  (:'ux', 'diretor.outro@exemplo.invalid');
-- O tenant X usa os mesmos id_origem de obra, contrato, parcela e título: junção sem tenant misturaria os dois.
insert into app.centro_custo (id, tenant_id, id_origem, nome) values
  (:'oa', :'tr', 9101, 'Obra Revisao A'), (:'ob', :'tr', 9102, 'Obra Revisao B'),
  (:'oc', :'tr', 9103, 'Obra Revisao C'), (:'od', :'tr', 9104, 'Obra Revisao D'),
  (:'ox', :'tx', 9101, 'Obra Revisao X');
insert into app.usuario_tenant (user_id, tenant_id, perfil) values
  (:'ud', :'tr', 'diretor'), (:'ug', :'tr', 'gerente_obra'), (:'ul', :'tr', 'leitura'),
  (:'uf', :'tr', 'financeiro'), (:'ux', :'tx', 'diretor');
insert into app.usuario_centro_custo (user_id, tenant_id, centro_custo_id) values
  (:'ug', :'tr', :'oa'), (:'ul', :'tr', :'ob');

create function pg_temp.parcela(p_obra int, p_contrato int, p_parcela int, p_tipo text, p_vencimento date,
  p_original numeric, p_saldo numeric, p_recebimentos jsonb, p_conta text default '1.01.001') returns jsonb
language sql as $$
  select jsonb_build_object('companyId', 1, 'projectId', p_obra, 'clientId', 1, 'clientName', 'Comprador Ficticio Revisao',
    'billId', p_contrato, 'installmentId', p_parcela, 'installmentNumber', p_parcela || '/9', 'dueDate', p_vencimento,
    'issueDate', p_vencimento, 'originalAmount', p_original, 'balanceAmount', p_saldo, 'correctedBalanceAmount', p_saldo,
    'defaulterSituation', 'N', 'paymentTerm', jsonb_build_object('id', p_tipo),
    'receiptsCategories', jsonb_build_array(jsonb_build_object('financialCategoryId', p_conta, 'financialCategoryRate', 100)),
    'receipts', p_recebimentos)
$$;

create function pg_temp.venda(p_obra int, p_id int, p_data date, p_situacao text, p_distrato date, p_valor numeric,
  p_unidade int, p_condicoes jsonb, p_data_financiamento date default null) returns jsonb
language sql as $$
  select jsonb_build_object('id', p_id, 'enterpriseId', p_obra, 'number', 'R-' || p_id, 'contractDate', p_data,
    'situation', p_situacao, 'cancellationDate', p_distrato, 'value', p_valor,
    'financialInstitutionNumber', case when p_data_financiamento is not null then '104' end,
    'financialInstitutionDate', p_data_financiamento, 'associativeCredit', 'N',
    'customers', jsonb_build_array(jsonb_build_object('id', 1, 'main', true, 'name', 'Comprador Ficticio Revisao')),
    'units', jsonb_build_array(jsonb_build_object('id', p_unidade, 'main', true)), 'paymentConditions', p_condicoes)
$$;

create function pg_temp.unidade(p_obra int, p_id int, p_situacao text, p_valor numeric, p_entrega date) returns jsonb
language sql as $$
  select jsonb_build_object('id', p_id, 'enterpriseId', p_obra, 'name', 'U-' || p_id, 'propertyType', '2Q',
    'privateArea', 50, 'commercialStock', p_situacao, 'deliveryDate', p_entrega, 'saleValuePrice', p_valor,
    'saleValueDate', '2026-09-01')
$$;

create function pg_temp.gravar(p_tenant uuid, p_endpoint text, p_payloads jsonb[]) returns void
language sql as $$
  insert into raw.registro (tenant_id, endpoint, payload, hash_registro)
  select p_tenant, p_endpoint, p, md5(p::text) from unnest(p_payloads) p
$$;

select pg_temp.gravar(:'tr', 'units', array[
  pg_temp.unidade(9101, 910101, 'V', 1, '2027-06-30'), pg_temp.unidade(9101, 910102, 'V', 1, '2027-06-30'),
  pg_temp.unidade(9101, 910103, 'D', 300000, '2027-06-30'), pg_temp.unidade(9101, 910104, 'D', 320000, '2027-06-30'),
  pg_temp.unidade(9102, 910201, 'V', 1, '2026-10-31'), pg_temp.unidade(9102, 910202, 'D', 250000, '2026-10-31'),
  pg_temp.unidade(9104, 910401, 'V', 1, '2027-12-31'), pg_temp.unidade(9104, 910402, 'D', 200000, '2027-12-31'),
  pg_temp.unidade(9104, 910403, 'D', 200000, '2027-12-31'), pg_temp.unidade(9104, 910404, 'D', 200000, '2027-12-31')]);

select pg_temp.gravar(:'tr', 'sales', array[
  pg_temp.venda(9101, 7001, '2026-03-10', '1', null, 500000, 910101,
    '[{"conditionType":"AT","totalValue":50000},{"conditionType":"PM","totalValue":150000},{"conditionType":"FI","totalValue":300000}]'),
  pg_temp.venda(9101, 7002, '2026-06-05', '1', null, 400000, 910102,
    '[{"conditionType":"AT","totalValue":100000},{"conditionType":"FI","totalValue":300000}]', '2026-08-01'),
  pg_temp.venda(9101, 7003, '2026-04-01', '3', '2026-09-15', 350000, 910103,
    '[{"conditionType":"AT","totalValue":35000},{"conditionType":"PM","totalValue":315000}]'),
  pg_temp.venda(9102, 7004, '2026-01-20', '1', null, 250000, 910201, '[{"conditionType":"PM","totalValue":250000}]'),
  pg_temp.venda(9104, 7401, '2026-08-10', '1', null, 200000, 910401, '[{"conditionType":"AT","totalValue":200000}]'),
  pg_temp.venda(9104, 7402, '2026-09-05', '3', '2026-10-20', 300000, 910402, '[{"conditionType":"AT","totalValue":300000}]')]);

select pg_temp.gravar(:'tr', 'income', array[
  -- 7001: entrada paga em duas vezes, PM parcial vencida, PM a vencer no mês e no próximo, FI sem etapa
  pg_temp.parcela(9101, 7001, 1, 'AT', '2026-03-10', 50000, 0,
    '[{"paymentDate":"2026-03-10","amount":20000},{"paymentDate":"2026-04-02","amount":30000}]'),
  pg_temp.parcela(9101, 7001, 2, 'PM', '2026-10-10', 50000, 30000, '[{"paymentDate":"2026-10-12","amount":20000}]'),
  pg_temp.parcela(9101, 7001, 3, 'PM', '2026-12-10', 50000, 50000, '[]'),
  pg_temp.parcela(9101, 7001, 4, 'PM', '2026-11-25', 50000, 50000, '[]'),
  pg_temp.parcela(9101, 7001, 5, 'FI', '2027-02-15', 300000, 300000, '[]'),
  -- 7002: financiamento com data na origem, logo elegível
  pg_temp.parcela(9101, 7002, 1, 'AT', '2026-06-05', 100000, 0, '[{"paymentDate":"2026-06-05","amount":100000}]'),
  pg_temp.parcela(9101, 7002, 2, 'FI', '2026-12-20', 300000, 300000, '[]'),
  -- 7003 distratado: o que foi pago fica, o saldo sai da carteira; a conta 1.77.001 não tem mapeamento
  pg_temp.parcela(9101, 7003, 1, 'AT', '2026-04-01', 35000, 0, '[{"paymentDate":"2026-04-01","amount":35000}]', '1.77.001'),
  pg_temp.parcela(9101, 7003, 2, 'PM', '2026-10-01', 315000, 315000, '[]'),
  -- 7004: estorno seguido de novo pagamento; parcela 2 renegociada em 3 e 4
  pg_temp.parcela(9102, 7004, 1, 'PM', '2026-02-20', 100000, 0,
    '[{"paymentDate":"2026-02-20","amount":100000},{"paymentDate":"2026-02-25","amount":-100000},{"paymentDate":"2026-03-01","amount":100000}]'),
  pg_temp.parcela(9102, 7004, 2, 'PM', '2026-05-20', 150000, 0, '[]'),
  pg_temp.parcela(9102, 7004, 3, 'PM', '2026-12-05', 75000, 75000, '[]'),
  pg_temp.parcela(9102, 7004, 4, 'PM', '2027-01-05', 75000, 75000, '[]'),
  -- obra que não existe no cadastro: vai para "Despesas sem obra"
  pg_temp.parcela(9999, 7999, 1, 'PM', '2026-11-30', 5000, 5000, '[]')]);

select pg_temp.gravar(:'tr', 'outcome', array[
  '{"companyId":1,"creditorName":"Fornecedor Ficticio","billId":8001,"dueDate":"2026-09-10","issueDate":"2026-09-01","originalAmount":1000.00,"balanceAmount":0,"buildingsCosts":[{"buildingId":9101,"amount":100},{"buildingId":9102,"amount":100},{"buildingId":9103,"amount":100}],"payments":[{"paymentDate":"2026-09-10","amount":500.00},{"paymentDate":"2026-10-10","amount":500.00}],"paymentsCategories":[{"financialCategoryId":"2.01.001","financialCategoryRate":100}]}'::jsonb,
  '{"companyId":1,"creditorName":"Fornecedor Ficticio","billId":8002,"dueDate":"2026-10-05","issueDate":"2026-08-20","originalAmount":10000,"balanceAmount":6000,"buildingsCosts":[{"buildingId":9101,"amount":10000}],"payments":[{"paymentDate":"2026-10-05","amount":4000}],"paymentsCategories":[{"financialCategoryId":"2.01.002","financialCategoryRate":100}]}',
  '{"companyId":1,"creditorName":"Fornecedor Ficticio","billId":8003,"dueDate":"2026-12-01","issueDate":"2026-11-05","originalAmount":2000,"balanceAmount":2000,"payments":[],"paymentsCategories":[{"financialCategoryId":"2.04.001","financialCategoryRate":100}]}',
  '{"companyId":1,"creditorName":"Fornecedor Ficticio","billId":8004,"dueDate":"2026-12-15","originalAmount":3000,"balanceAmount":3000,"buildingsCosts":[{"buildingId":9101,"amount":3000}],"payments":[],"paymentsCategories":[{"financialCategoryId":"2.88.001","financialCategoryRate":100}]}',
  '{"companyId":1,"creditorName":"Fornecedor Ficticio","billId":8005,"dueDate":"2026-07-10","issueDate":"2026-07-01","originalAmount":5000,"balanceAmount":0,"buildingsCosts":[{"buildingId":9101,"amount":5000}],"payments":[{"paymentDate":"2026-07-10","amount":4800}],"paymentsCategories":[{"financialCategoryId":"2.01.003","financialCategoryRate":100}]}',
  '{"companyId":1,"creditorName":"Fornecedor Ficticio","billId":8401,"dueDate":"2026-09-15","issueDate":"2026-08-15","originalAmount":20000,"balanceAmount":0,"buildingsCosts":[{"buildingId":9104,"amount":20000}],"payments":[{"paymentDate":"2026-09-15","amount":20000}],"paymentsCategories":[{"financialCategoryId":"2.01.001","financialCategoryRate":100}]}',
  '{"companyId":1,"creditorName":"Fornecedor Ficticio","billId":8402,"dueDate":"2026-10-10","issueDate":"2026-09-10","originalAmount":30000,"balanceAmount":30000,"buildingsCosts":[{"buildingId":9104,"amount":30000}],"payments":[],"paymentsCategories":[{"financialCategoryId":"2.01.003","financialCategoryRate":100}]}']);

select pg_temp.gravar(:'tr', 'building-cost-estimation-items', array[
  '{"buildingId":9101,"wbsCode":"01","description":"Item A","totalPrice":50000,"percentComplete":10}'::jsonb,
  '{"buildingId":9102,"wbsCode":"01","description":"Item B","totalPrice":0,"percentComplete":0}',
  '{"buildingId":9104,"wbsCode":"01","description":"Item D1","totalPrice":60000,"percentComplete":30}',
  '{"buildingId":9104,"wbsCode":"02","description":"Item D2","totalPrice":40000,"percentComplete":30}']);

select pg_temp.gravar(:'tx', 'units', array[pg_temp.unidade(9101, 910101, 'D', 123, '2027-06-30')]);
select pg_temp.gravar(:'tx', 'sales', array[
  pg_temp.venda(9101, 7001, '2026-02-01', '1', null, 999999, 910101, '[{"conditionType":"FI","totalValue":999999}]')]);
select pg_temp.gravar(:'tx', 'income', array[
  pg_temp.parcela(9101, 7001, 1, 'FI', '2026-12-10', 11111, 11111, '[{"paymentDate":"2026-06-01","amount":5555}]')]);
select pg_temp.gravar(:'tx', 'outcome', array[
  '{"companyId":1,"creditorName":"Outro","billId":8001,"dueDate":"2026-12-01","originalAmount":777,"balanceAmount":777,"buildingsCosts":[{"buildingId":9101,"amount":777}],"payments":[]}'::jsonb]);

insert into app.mapa_conta_origem (tenant_id, tipo_origem, conta_origem, categoria_codigo, autor)
select :'tr', t, c, k, '00000000-0000-0000-0000-000000000000'
from (values ('parcela_receber', '1.01.001', 'venda_imoveis'), ('titulo_pagar', '2.01.001', 'materiais'),
             ('titulo_pagar', '2.01.002', 'mao_de_obra'), ('titulo_pagar', '2.01.003', 'empreiteiros'),
             ('titulo_pagar', '2.04.001', 'despesas_administrativas')) as m(t, c, k);
-- Só a obra D tem o percentual de conclusão validado; as demais ficam no padrão nao_definido.
insert into app.criterio_reconhecimento (tenant_id, centro_custo_id, metodo, autor)
values (:'tr', :'od', 'percentual_conclusao', '00000000-0000-0000-0000-000000000000');

select set_config('app.data_referencia', '2026-11-20', true);
select staging.recarregar(:'tr');
select staging.recarregar_precos(:'tr');
select staging.recarregar(:'tx');
select staging.recarregar_precos(:'tx');

-- Reprocessamento: a fotografia de cada tabela do staging não muda depois de mais duas recargas

create temp table fotografia_staging as
select t.tabela, (xpath('/row/c/text()', query_to_xml(format(
  'select count(*) || '':'' || coalesce(md5(string_agg(x::text, ''|'' order by x::text)), '''') as c from staging.%I x where tenant_id = %L',
  t.tabela, :'tr'), false, true, '')))[1]::text as assinatura
from unnest(array['unidade', 'contrato_venda', 'contrato_unidade', 'parcela_receber', 'recebimento', 'titulo_pagar',
                  'titulo_pagar_apropriacao', 'pagamento', 'item_orcamento', 'unidade_valor']) as t(tabela);

select staging.recarregar(:'tr');
select staging.recarregar(:'tr');
select staging.recarregar_precos(:'tr');

select is((select count(*) from fotografia_staging f
           where f.assinatura <> (xpath('/row/c/text()', query_to_xml(format(
             'select count(*) || '':'' || coalesce(md5(string_agg(x::text, ''|'' order by x::text)), '''') as c from staging.%I x where tenant_id = %L',
             f.tabela, :'tr'), false, true, '')))[1]::text), 0::bigint,
  'recarregar duas vezes deixa as dez tabelas do staging idênticas, linha a linha');
select is((select count(*) from staging.recebimento where tenant_id = :'tr'), 8::bigint,
  'oito eventos de recebimento: dois da entrada, um parcial, AT de 7002, AT do distrato, três de 7004 (com estorno)');
select is((select count(*) from staging.titulo_pagar_apropriacao where tenant_id = :'tr'), 9::bigint,
  'nove apropriações: três do rateio, uma por título nos outros seis');
select is((select count(*) from staging.contrato_venda where tenant_id = :'tx'), 1::bigint,
  'recarregar o tenant R não mexe no tenant X');

-- Diretor do tenant R

select set_config('request.jwt.claims', json_build_object('sub', :'ud', 'role', 'authenticated')::text, true);
set local role authenticated;

-- Venda contratada, recebido e carteira são números diferentes (obra A)
select results_eq(
  format($q$select vgv_contratado_ativo, contratos_ativos, contratos_distratados, recebido_direto, recebido_financiamento,
                   vencido_direto, a_vencer_direto, a_vencer_financiamento, previsto_proximo_mes_direto,
                   previsto_proximo_mes_financiamento, saldo_distratado
            from marts.resumo_receitas_obra where centro_custo_id = %L$q$, :'oa'),
  $q$values (900000.00::numeric(18,2), 2, 1, 205000.00::numeric(18,2), 0.00::numeric(18,2), 30000.00::numeric(18,2),
             100000.00::numeric(18,2), 600000.00::numeric(18,2), 50000.00::numeric(18,2), 300000.00::numeric(18,2),
             315000.00::numeric(18,2))$q$,
  'obra A: VGV 900 mil, recebido 205 mil (inclui 35 mil do distratado), carteira separada por origem e próximo mês só de dezembro');
select results_eq(
  format($q$select recebido_direto, a_vencer_direto, vencido_direto, previsto_proximo_mes_direto, vgv_contratado_ativo
            from marts.resumo_receitas_obra where centro_custo_id = %L$q$, :'ob'),
  $q$values (100000.00::numeric(18,2), 150000.00::numeric(18,2), 0.00::numeric(18,2), 75000.00::numeric(18,2), 250000.00::numeric(18,2))$q$,
  'obra B: estorno anulado, renegociação sem duplicar a carteira');
select results_eq(
  format($q$select quantidade_obras, vgv_contratado_ativo, recebido_direto, a_vencer_direto, previsto_proximo_mes_direto,
                   previsto_proximo_mes_financiamento
            from marts.resumo_receitas_consolidado where tenant_id = %L$q$, :'tr'),
  $q$values (3, 1350000.00::numeric(18,2), 305000.00::numeric(18,2), 250000.00::numeric(18,2), 125000.00::numeric(18,2),
             300000.00::numeric(18,2))$q$,
  'consolidado de receitas soma A, B e D e deixa de fora a parcela de obra não cadastrada');
select is((select a_vencer_direto from marts.resumo_receitas_obra
           where tenant_id = :'tr' and tipo_centro = 'empresa'), 5000.00::numeric(18,2),
  'parcela de obra não cadastrada aparece no centro Despesas sem obra');

-- Recebimento parcial e situação de cada parcela
select results_eq(
  format($q$select parcela_id_origem, situacao, parcial, valor_recebido, saldo, dias_atraso
            from marts.carteira_recebiveis where centro_custo_id = %L and contrato_id_origem = 7001 order by parcela_id_origem$q$, :'oa'),
  $q$values (1, 'quitada', false, 50000.00::numeric(18,2), 0.00::numeric(18,2), null::integer),
            (2, 'vencida', true, 20000.00::numeric(18,2), 30000.00::numeric(18,2), 41),
            (3, 'a_vencer', false, 0.00::numeric(18,2), 50000.00::numeric(18,2), null),
            (4, 'a_vencer', false, 0.00::numeric(18,2), 50000.00::numeric(18,2), null),
            (5, 'a_vencer', false, 0.00::numeric(18,2), 300000.00::numeric(18,2), null)$q$,
  'contrato 7001: entrada em duas vezes quitada, PM parcial vencida há 41 dias, dias de atraso nulo quando não venceu');
select results_eq(
  format($q$select contrato_id_origem, parcela_id_origem, situacao, valor_recebido, situacao_contrato
            from marts.carteira_recebiveis where tenant_id = %L and contrato_id_origem in (7003, 7004) order by 1, 2$q$, :'tr'),
  $q$values (7003, 1, 'quitada', 35000.00::numeric(18,2), 'distratado'),
            (7003, 2, 'cancelada_distrato', 0.00::numeric(18,2), 'distratado'),
            (7004, 1, 'quitada', 100000.00::numeric(18,2), 'ativo'),
            (7004, 2, 'baixada_sem_recebimento', 0.00::numeric(18,2), 'ativo'),
            (7004, 3, 'a_vencer', 0.00::numeric(18,2), 'ativo'),
            (7004, 4, 'a_vencer', 0.00::numeric(18,2), 'ativo')$q$,
  'distrato mantém o recebido e cancela o saldo; parcela renegociada fica baixada sem recebimento');
select is((select count(*) from marts.carteira_recebiveis where tenant_id = :'tr' and centro_custo_id = :'oa'), 9::bigint,
  'carteira da obra A tem as nove parcelas, nenhuma do tenant X com os mesmos ids');
select is((select count(*) from information_schema.columns
           where table_schema = 'marts' and column_name ~ '(cliente|comprador|cpf|nome_)'), 0::bigint,
  'nenhuma coluna de marts guarda nome, CPF ou cliente');

-- Caixa pelo mês do dinheiro; previsto contratual sem a parcela renegociada
select results_eq(
  format($q$select competencia, recebido, previsto_contratual from marts.recebimento_mensal
            where centro_custo_id = %L and origem = 'direta' and competencia <= '2026-05-01' order by competencia$q$, :'ob'),
  $q$values ('2026-02-01'::date, 0.00::numeric(18,2), 100000.00::numeric(18,2)),
            ('2026-03-01', 100000.00, 0.00)$q$,
  'obra B: o estorno zera fevereiro e o novo pagamento cai em março; maio sem previsto porque a parcela foi renegociada');
select is((select sum(previsto_contratual) from marts.recebimento_mensal where centro_custo_id = :'ob'), 250000.00::numeric,
  'obra B: previsto contratual soma o VGV, sem contar a parcela renegociada e as novas duas vezes');
select results_eq(
  format($q$select origem, recebido from marts.recebimento_periodo('2026-04-01', '2026-04-30', %L)$q$, :'oa'),
  $q$values ('direta', 65000.00::numeric(18,2)), ('financiamento', 0.00::numeric(18,2))$q$,
  'abril na obra A: 30 mil da segunda metade da entrada mais 35 mil do contrato depois distratado');
select is((select sum(recebido) from marts.recebimento_mensal where centro_custo_id = :'oa'),
          (select recebido_direto + recebido_repasse from marts.posicao_financeira_obra where centro_custo_id = :'oa'),
  'recebido mensal da obra A bate com a posição financeira (R1 e R4)');
select is((select sum(saldo) from marts.recebivel_projetado where centro_custo_id = :'oa'), 730000.00::numeric,
  'recebível projetado da obra A: 30 mil vencidos, 100 mil diretos e 600 mil de financiamento (R19)');

-- Virada de dezembro para janeiro
select set_config('app.data_referencia', '2026-12-15', true);
select results_eq(
  format($q$select centro_custo_id, previsto_proximo_mes_direto, previsto_proximo_mes_financiamento, vencido_direto
            from marts.resumo_receitas_obra where centro_custo_id in (%L, %L) order by obra$q$, :'oa', :'ob'),
  format($q$values (%L::uuid, 0.00::numeric(18,2), 0.00::numeric(18,2), 130000.00::numeric(18,2)),
                   (%L::uuid, 75000.00, 0.00, 75000.00)$q$, :'oa', :'ob'),
  'em 15/12 o próximo mês é janeiro de 2027: só a parcela de 05/01 entra; as de dezembro viraram vencidas');
select set_config('app.data_referencia', '2026-11-20', true);

-- Despesas: rateio em três obras com resíduo de centavo, competência e pagamento, desconto
select results_eq(
  format($q$select centro_custo_id, principal, valor_original, valor_pago, saldo from staging.titulo_pagar_apropriacao
            where tenant_id = %L and titulo_id_origem = 8001 order by sequencia_obra$q$, :'tr'),
  format($q$values (%L::uuid, true, 333.34::numeric(18,2), 333.34::numeric(18,2), 0.00::numeric(18,2)),
                   (%L::uuid, false, 333.33, 333.33, 0.00), (%L::uuid, false, 333.33, 333.33, 0.00)$q$, :'oa', :'ob', :'oc'),
  'rateio em três partes iguais: o centavo que sobra fica com a primeira obra e cada obra fecha quitada');
select results_eq(
  format($q$select sequencia_pagamento, sequencia_obra, valor from staging.pagamento
            where tenant_id = %L and titulo_id_origem = 8001 order by 1, 2$q$, :'tr'),
  $q$values (1, 1, 166.66::numeric(18,2)), (1, 2, 166.67), (1, 3, 166.67),
            (2, 1, 166.68), (2, 2, 166.66), (2, 3, 166.66)$q$,
  'pagamentos de 500 + 500 repartidos pelo acumulado: 166,66 + 166,68 na obra principal');
select results_eq(
  format($q$select orcamento_vigente, custo_lancado, desembolsado, em_aberto_vencido, em_aberto_a_vencer, ajuste_baixa,
                   remanescente_sem_titulo, estimativa_conclusao, desvio, cobertura_classificacao, motivo
            from marts.custo_obra_resumo where centro_custo_id = %L$q$, :'oa'),
  $q$values (50000.00::numeric(18,2), 18333.34::numeric(18,2), 9133.34::numeric(18,2), 6000.00::numeric(18,2),
             3000.00::numeric(18,2), 200.00::numeric(18,2), 31666.66::numeric(18,2), 50000.00::numeric(18,2),
             0.00::numeric(18,2), 0.836364::numeric(9,6), null::text)$q$,
  'obra A: lançado = pago + em aberto + desconto; estimativa = orçamento, sem somar títulos duas vezes');
select results_eq(
  format($q$select centro_custo_id, orcamento_vigente, remanescente_sem_titulo, estimativa_conclusao, desvio, motivo
            from marts.custo_obra_resumo where centro_custo_id in (%L, %L) order by obra$q$, :'ob', :'oc'),
  format($q$values (%L::uuid, 0.00::numeric(18,2), 0.00::numeric(18,2), 333.33::numeric(18,2), 333.33::numeric(18,2), null::text),
                   (%L::uuid, null, null, null, null, 'orcamento_ausente')$q$, :'ob', :'oc'),
  'orçamento zero dá remanescente zero; sem orçamento tudo fica nulo com o motivo');
select results_eq(
  format($q$select r.remanescente_sem_titulo, p.custo_a_incorrer, p.pago, p.a_pagar, p.custo_lancado, p.ajuste_baixa,
                   p.caixa_atual, p.estoque_a_vender
            from marts.custo_obra_resumo r join marts.posicao_financeira_obra p using (centro_custo_id)
            where centro_custo_id = %L$q$, :'oa'),
  $q$values (31666.66::numeric(18,2), 31666.66::numeric, 9133.34::numeric, 9000.00::numeric, 18333.34::numeric,
             200.00::numeric, 195866.66::numeric, 620000.00::numeric)$q$,
  'posição da obra A concilia com o resumo de custos (R7) e mostra caixa gerado de 195.866,66');
select results_eq(
  format($q$select grupo, quantidade_centros, centros_sem_orcamento, orcamento_vigente, custo_lancado, motivo
            from marts.custo_obra_resumo_consolidado where tenant_id = %L order by grupo$q$, :'tr'),
  $q$values ('despesas_sem_obra', 1, null::integer, null::numeric(18,2), 2000.00::numeric(18,2), null::text),
            ('obras', 4, 1, null, 69000.00, 'consolidado_parcial')$q$,
  'consolidado de custos: despesa sem obra separada; orçamento nulo porque a obra C não tem orçamento');
select results_eq(
  format($q$select competencia, categoria_codigo, lancado_competencia, pago, vencido from marts.despesa_mensal
            where centro_custo_id = %L and categoria_codigo = 'mao_de_obra' order by competencia$q$, :'oa'),
  $q$values ('2026-08-01'::date, 'mao_de_obra', 10000.00::numeric(18,2), 0.00::numeric(18,2), 0.00::numeric(18,2)),
            ('2026-10-01', 'mao_de_obra', 0.00, 4000.00, 6000.00)$q$,
  'título emitido em agosto entra na competência de agosto; o pagamento e o vencido ficam em outubro');
select results_eq(
  format($q$select categoria_codigo, lancado_competencia, pago from marts.desembolso_periodo('2026-10-01', '2026-10-31', %L)
            order by categoria_codigo$q$, :'oa'),
  $q$values ('mao_de_obra', 0.00::numeric(18,2), 4000.00::numeric(18,2)), ('materiais', 0.00, 166.68)$q$,
  'desembolso de outubro da obra A pelo dia do pagamento');
select results_eq(
  format($q$select categoria_codigo, categoria_nome, custo_lancado from marts.custo_obra_categoria
            where centro_custo_id = %L and categoria_codigo is null$q$, :'oa'),
  $q$values (null::text, 'Sem categoria', 3000.00::numeric(18,2))$q$,
  'conta 2.88.001 sem mapeamento fica em Sem categoria, nunca em outros custos');
select results_eq(
  format($q$select tipo_origem, conta_origem, quantidade_lancamentos, valor_envolvido, participacao
            from marts.pendencia_classificacao where tenant_id = %L order by tipo_origem, conta_origem$q$, :'tr'),
  $q$values ('orcamento', '01', 3, 110000.00::numeric(18,2), 0.733333::numeric(9,6)),
            ('orcamento', '02', 1, 40000.00, 0.266667),
            ('parcela_receber', '1.77.001', 1, 35000.00, 0.021148),
            ('titulo_pagar', '2.88.001', 1, 3000.00, 0.042254)$q$,
  'pendências de classificação com a participação sobre o total visível do mesmo tipo');

-- DRE: obra D com percentual de conclusão validado, obra A sem critério
select results_eq(
  format($q$select competencia, poc, vgv_ativo_fim_mes, unidades_vendidas_fim_mes, receita_reconhecida_mes, custo_reconhecido_mes
            from marts.reconhecimento_obra_mensal where centro_custo_id = %L order by competencia$q$, :'od'),
  $q$values ('2026-08-01'::date, 0.200000::numeric(9,6), 200000.00::numeric(18,2), 1, 40000.00::numeric(18,2), 5000.00::numeric(18,2)),
            ('2026-09-01', 0.500000, 500000.00, 2, 210000.00, 20000.00),
            ('2026-10-01', 0.500000, 200000.00, 1, -150000.00, -12500.00),
            ('2026-11-01', 0.500000, 200000.00, 1, 0.00, 0.00)$q$,
  'obra D: POC 20% e 50%; o distrato de outubro devolve 150 mil de receita e 12,5 mil de custo');
select results_eq(
  format($q$select linha_codigo, valor_periodo, disponivel from marts.dre_periodo('2026-01-01', '2026-11-30', %L)
            where linha_codigo in ('receita_bruta', 'custo_imovel_vendido', 'resultado_gerencial', 'custo_obra_incorrido')
            order by linha_ordem$q$, :'od'),
  $q$values ('receita_bruta', 100000.00::numeric(18,2), true), ('custo_imovel_vendido', -12500.00, true),
            ('resultado_gerencial', 87500.00, true), ('custo_obra_incorrido', -50000.00, true)$q$,
  'obra D no ano: resultado gerencial 87.500; custo de obra lançado fica fora do resultado');
select results_eq(
  format($q$select linha_codigo, valor_periodo, disponivel, motivo from marts.dre_periodo('2026-01-01', '2026-11-30', %L)
            where linha_codigo in ('receita_bruta', 'deducoes', 'resultado_gerencial', 'sem_data_competencia')
            order by linha_ordem$q$, :'oa'),
  $q$values ('receita_bruta', null::numeric(18,2), false, 'criterio_nao_validado'),
            ('deducoes', 0.00, true, null::text),
            ('resultado_gerencial', null, false, 'criterio_nao_validado'),
            ('sem_data_competencia', -3000.00, true, null)$q$,
  'obra A sem critério: resultado indisponível e nulo, deduções zero conhecido, título sem emissão na linha própria');
select results_eq(
  format($q$select competencia, valor_mes from marts.dre_mensal
            where tenant_id = %L and tipo_centro = 'empresa' and linha_codigo = 'despesas_administrativas'
              and valor_mes <> 0$q$, :'tr'),
  $q$values ('2026-11-01'::date, -2000.00::numeric(18,2))$q$,
  'título sem obra entra no DRE do centro Despesas sem obra pela competência');
select results_eq(
  $q$select disponivel, motivo from marts.dre_periodo('2026-01-01', '2026-11-30', null) where linha_codigo = 'resultado_gerencial'$q$,
  $q$values (false, 'consolidado_parcial')$q$,
  'consolidado do diretor fica parcial: só a obra D tem critério');

-- Fluxo projetado da obra A antes de qualquer complemento
select is((select count(*) from marts.fluxo_projetado_mensal where centro_custo_id = :'oa'), 12::bigint,
  'fluxo da obra A vai de março de 2026 a fevereiro de 2027');
select results_eq(
  format($q$select competencia, recebido_direto, previsto_direto, previsto_financiamento_elegivel,
                   previsto_financiamento_pendente, vencido_a_receber, pago, a_pagar, a_pagar_vencido, caixa_gerado_acumulado
            from marts.fluxo_projetado_mensal where centro_custo_id = %L and competencia >= '2026-10-01' order by competencia$q$, :'oa'),
  $q$values ('2026-10-01'::date, 20000.00::numeric(18,2), 0.00::numeric(18,2), 0.00::numeric(18,2), 0.00::numeric(18,2),
             0.00::numeric(18,2), 4166.68::numeric(18,2), 0.00::numeric(18,2), 0.00::numeric(18,2), 195866.66::numeric(18,2)),
            ('2026-11-01', 0.00, 50000.00, 0.00, 0.00, 30000.00, 0.00, 0.00, 6000.00, 239866.66),
            ('2026-12-01', 0.00, 50000.00, 300000.00, 0.00, 0.00, 0.00, 3000.00, 0.00, 586866.66),
            ('2027-01-01', 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 586866.66),
            ('2027-02-01', 0.00, 0.00, 0.00, 300000.00, 0.00, 0.00, 0.00, 0.00, 886866.66)$q$,
  'obra A: vencido a receber fica fora do saldo, vencido a pagar entra em novembro, FI com data na origem é elegível');
select is((select count(*) from marts.fluxo_projetado_mensal f
           full join marts.simular_fluxo(:'oa', '{}') s using (competencia)
           where f.centro_custo_id = :'oa' and f.caixa_gerado_acumulado is distinct from s.caixa_gerado_acumulado), 0::bigint,
  'simulação sem premissas devolve o mesmo caixa gerado do fluxo projetado (R16)');
select is((select count(*) from marts.simular_fluxo(:'oa', '{}')), 12::bigint, 'simulação sem premissas tem os mesmos 12 meses');
select results_eq(
  format($q$select exposicao_maxima_projetada, mes_exposicao_maxima, custo_sem_titulo_total, motivo_distribuicao, exposicao_parcial
            from marts.resumo_projecao_obra where centro_custo_id = %L$q$, :'oc'),
  $q$values (333.33::numeric, '2026-10-01'::date, null::numeric(18,2), 'orcamento_ausente', true)$q$,
  'obra C só paga a parte do rateio: aporte de 333,33 em outubro, exposição parcial por falta de orçamento');
select results_eq(
  format($q$select custo_sem_titulo_total, custo_sem_titulo_distribuido_total, custo_sem_titulo_nao_distribuido,
                   motivo_distribuicao, exposicao_parcial
            from marts.resumo_projecao_obra where centro_custo_id = %L$q$, :'oa'),
  $q$values (31666.66::numeric(18,2), 0.00::numeric(18,2), 31666.66::numeric(18,2), 'sem_premissa_distribuicao', true)$q$,
  'obra A sem premissa: o custo sem título fica num total separado (R15)');

-- Premissa de meses com resíduo de centavo; outubro já passou e soma em novembro
select ok(app.registrar_premissa_distribuicao(:'oa', 'cronograma ficticio da revisao', null,
  '[{"competencia":"2026-10-01","fracao":0.333333},{"competencia":"2026-12-01","fracao":0.333333},{"competencia":"2027-01-01","fracao":0.333334}]')
  is not null, 'diretor registra a premissa de meses');
select results_eq(
  format($q$select competencia, custo_sem_titulo_distribuido, caixa_gerado_acumulado from marts.fluxo_projetado_mensal
            where centro_custo_id = %L and custo_sem_titulo_distribuido <> 0 order by competencia$q$, :'oa'),
  $q$values ('2026-11-01'::date, 10555.54::numeric(18,2), 229311.12::numeric(18,2)),
            ('2026-12-01', 10555.54, 565755.58), ('2027-01-01', 10555.58, 555200.00)$q$,
  'custo sem título: 10.555,54 em novembro e dezembro e o centavo de resíduo em janeiro, a maior fração');
select results_eq(
  format($q$select custo_sem_titulo_nao_distribuido, exposicao_parcial from marts.resumo_projecao_obra where centro_custo_id = %L$q$, :'oa'),
  $q$values (0.00::numeric(18,2), false)$q$, 'com a premissa, nada fica sem distribuir');

select ok(app.registrar_versao_projecao(:'oa', 'versao um da revisao') is not null, 'registra a versão 1 da projeção');
select is((select count(*) from app.projecao_mensal p join app.versao_planejamento v on v.id = p.versao_id
           where v.centro_custo_id = :'oa' and v.numero = 1), 12::bigint, 'a versão 1 guarda os 12 meses');

-- Financiamento: etapa, operação de crédito, medição e liberações
select throws_ok(format($q$insert into app.etapa_financiamento_contrato (tenant_id, centro_custo_id, contrato_id_origem, etapa,
  data_etapa, fonte, autor) values (%L, %L, 7003, 'elegivel', '2026-11-01', 'teste', %L)$q$, :'tr', :'oa', :'ud'),
  '23514', null, 'contrato distratado não recebe etapa de financiamento');
insert into app.etapa_financiamento_contrato (tenant_id, centro_custo_id, contrato_id_origem, etapa, data_etapa,
  data_prevista_liberacao, fonte, autor)
values (:'tr', :'oa', 7001, 'elegivel', '2026-11-10', '2027-03-15', 'carta ficticia do banco', '00000000-0000-0000-0000-000000000000');
select is((select autor from app.etapa_financiamento_contrato where contrato_id_origem = 7001 and tenant_id = :'tr'), :'ud'::uuid,
  'autor mandado pelo cliente é trocado pelo do JWT');
select results_eq(
  format($q$select contrato_id_origem, classificacao from marts.financiamento_contrato where centro_custo_id = %L order by 1$q$, :'oa'),
  $q$values (7001, 'financiamento_elegivel'), (7002, 'financiamento_elegivel')$q$,
  'etapa elegível e data na origem tornam os dois financiamentos elegíveis');
select results_eq(
  format($q$select competencia, previsto_financiamento_elegivel, previsto_financiamento_pendente from marts.fluxo_projetado_mensal
            where centro_custo_id = %L and competencia >= '2027-02-01' order by competencia$q$, :'oa'),
  $q$values ('2027-02-01'::date, 0.00::numeric(18,2), 0.00::numeric(18,2)), ('2027-03-01', 300000.00, 0.00)$q$,
  'FI do contrato 7001 passa a entrar na data prevista da liberação, março de 2027');

insert into app.operacao_credito_obra (tenant_id, centro_custo_id, modalidade, instituicao, valor_contratado,
  percentual_retencao, fonte, autor)
values (:'tr', :'oa', 'credito_producao', 'Banco Ficticio', 1000000, 0.05, 'contrato ficticio', :'ud');
select id as operacao from app.operacao_credito_obra where tenant_id = :'tr' \gset
select sum(total_entradas) as entradas_antes from marts.fluxo_projetado_mensal where centro_custo_id = :'oa' \gset
insert into app.medicao_bancaria (tenant_id, centro_custo_id, operacao_credito_id, numero, data_vistoria,
  avanco_fisico_informado, situacao, data_aprovacao, valor_elegivel, fonte, autor)
values (:'tr', :'oa', :'operacao', 1, '2026-11-01', 0.4, 'aprovada', '2026-11-10', 400000, 'RAE ficticio', :'ud');
select is((select sum(total_entradas) from marts.fluxo_projetado_mensal where centro_custo_id = :'oa'), :'entradas_antes'::numeric,
  'medição aprovada sem liberação recebida não muda nenhuma entrada do fluxo');
insert into app.liberacao_financiamento (tenant_id, centro_custo_id, nivel, contrato_id_origem, valor_previsto, data_prevista,
  situacao, fonte, autor)
values (:'tr', :'oa', 'contrato', 7001, 300000, '2027-03-15', 'prevista', 'carta ficticia', :'ud');
select is((select sum(total_entradas) from marts.fluxo_projetado_mensal where centro_custo_id = :'oa'), :'entradas_antes'::numeric,
  'liberação de nível contrato não soma: o dinheiro é a parcela FI');
select throws_ok(format($q$insert into app.liberacao_financiamento (tenant_id, centro_custo_id, nivel, contrato_id_origem,
  valor_previsto, data_prevista, situacao, fonte, autor) values (%L, %L, 'contrato', 7003, 1000, '2027-01-01', 'prevista', 'x', %L)$q$,
  :'tr', :'oa', :'ud'), '23514', null, 'contrato distratado não ganha liberação');
select throws_ok(format($q$insert into app.liberacao_financiamento (tenant_id, centro_custo_id, nivel, contrato_id_origem,
  valor_previsto, data_prevista, situacao, fonte, autor) values (%L, %L, 'contrato', 910104, 1000, '2027-01-01', 'prevista', 'x', %L)$q$,
  :'tr', :'oa', :'ud'), '23514', null, 'unidade em estoque, sem contrato, não ganha liberação');
insert into app.liberacao_financiamento (tenant_id, centro_custo_id, nivel, operacao_credito_id, medicao_id, valor_previsto,
  data_prevista, situacao, valor_recebido, data_recebimento, vinculo_tipo, vinculo_chave, fonte, autor)
select :'tr', :'oa', 'empreendimento', :'operacao', m.id, 300000, '2026-11-05', 'recebida', 300000, '2026-11-05',
       'lancamento_manual', 'EXT-REVISAO-1', 'extrato ficticio', :'ud'
from app.medicao_bancaria m where m.operacao_credito_id = :'operacao';
insert into app.liberacao_financiamento (tenant_id, centro_custo_id, nivel, operacao_credito_id, valor_previsto,
  data_prevista, situacao, fonte, autor)
values (:'tr', :'oa', 'empreendimento', :'operacao', 600000, '2027-01-10', 'prevista', 'cronograma ficticio', :'ud');
select throws_ok(format($q$insert into app.liberacao_financiamento (tenant_id, centro_custo_id, nivel, operacao_credito_id,
  valor_previsto, data_prevista, situacao, fonte, autor) values (%L, %L, 'empreendimento', %L, 150000, '2027-02-10', 'prevista', 'x', %L)$q$,
  :'tr', :'oa', :'operacao', :'ud'), '23514', null, 'liberação que passaria de 1 milhão contratado é recusada');
select throws_ok(format($q$insert into app.liberacao_financiamento (tenant_id, centro_custo_id, nivel, operacao_credito_id,
  valor_previsto, data_prevista, situacao, valor_recebido, data_recebimento, vinculo_tipo, vinculo_chave, fonte, autor)
  values (%L, %L, 'empreendimento', %L, 10000, '2026-11-06', 'recebida', 10000, '2026-11-06', 'lancamento_manual', 'EXT-REVISAO-1', 'x', %L)$q$,
  :'tr', :'oa', :'operacao', :'ud'), '23505', null, 'o mesmo lançamento do extrato não liga a duas liberações');
select results_eq(
  format($q$select valor_contratado, retencao_prevista, limite_antes_retencao, liberado_recebido, previsto_aberto, saldo_liberavel,
                   saldo_nao_programado, medido_elegivel, elegivel_nao_liberado, excede_limite
            from marts.saldo_operacao_credito where operacao_credito_id = %L$q$, :'operacao'),
  $q$values (1000000.00::numeric(18,2), 50000.00::numeric(18,2), 950000.00::numeric(18,2), 300000.00::numeric(18,2),
             600000.00::numeric(18,2), 650000.00::numeric(18,2), 50000.00::numeric(18,2), 400000.00::numeric(18,2),
             100000.00::numeric(18,2), false)$q$,
  'operação: retenção de 5%, 300 mil liberados, 600 mil programados, 100 mil medidos e ainda não liberados');
select results_eq(
  format($q$select competencia, credito_producao_recebido, credito_producao_previsto from marts.fluxo_projetado_mensal
            where centro_custo_id = %L and (credito_producao_recebido <> 0 or credito_producao_previsto <> 0) order by 1$q$, :'oa'),
  $q$values ('2026-11-01'::date, 300000.00::numeric(18,2), 0.00::numeric(18,2)), ('2027-01-01', 0.00, 600000.00)$q$,
  'crédito à produção: recebido pelo lançamento manual em novembro e previsto em janeiro');

-- Versões preservadas
select ok(app.registrar_versao_projecao(:'oa', 'versao dois da revisao') is not null, 'registra a versão 2 da projeção');
select results_eq(
  format($q$select v.numero, p.caixa_gerado_acumulado from app.projecao_mensal p join app.versao_planejamento v on v.id = p.versao_id
            where v.centro_custo_id = %L and p.competencia = '2026-11-01' order by v.numero$q$, :'oa'),
  $q$values (1, 229311.12::numeric(18,2)), (2, 529311.12)$q$,
  'a versão 1 continua com o caixa de antes da liberação; a 2 soma os 300 mil');
select results_eq(
  format($q$select versao_original_numero, original_caixa_gerado_acumulado, atual_caixa_gerado_acumulado, diferenca_caixa_acumulado
            from marts.comparativo_projecao where centro_custo_id = %L and competencia = '2026-11-01'$q$, :'oa'),
  $q$values (1, 229311.12::numeric(18,2), 529311.12::numeric(18,2), 300000.00::numeric(18,2))$q$,
  'comparativo usa a primeira versão do mês como original');
select throws_ok(format($q$update app.versao_planejamento set descricao = 'x' where centro_custo_id = %L$q$, :'oa'),
  '42501', null, 'versão não aceita alteração');
select throws_ok(format($q$delete from app.projecao_mensal where centro_custo_id = %L$q$, :'oa'),
  '42501', null, 'linha de versão não pode ser apagada');

-- Nova venda simulada: 1 unidade em dezembro e 3 pedidas em janeiro com só 1 no estoque
create temp table simulacao_revisao as
select * from marts.simular_fluxo(:'oa', '{"novas_vendas":[{"competencia":"2026-12-01","quantidade":1},{"competencia":"2027-01-01","quantidade":3}],"desconto_tabela":0.10,"composicao":{"entrada":0.1,"parcelas_mensais":0.3,"quantidade_parcelas_mensais":3,"financiamento":0.6},"meses_ate_liberacao_financiamento":2}');
select results_eq(
  $q$select competencia, novas_vendas_unidades, novas_vendas_valor, entradas_novas_vendas_direta,
            entradas_novas_vendas_financiamento, aviso
     from simulacao_revisao where competencia between '2026-12-01' and '2027-04-01' order by competencia$q$,
  $q$values ('2026-12-01'::date, 1, 279000.00::numeric(18,2), 27900.00::numeric(18,2), 0.00::numeric(18,2), null::text),
            ('2027-01-01', 1, 279000.00, 55800.00, 0.00, 'vendas_limitadas_ao_estoque'),
            ('2027-02-01', 0, 0.00, 55800.00, 167400.00, null),
            ('2027-03-01', 0, 0.00, 55800.00, 167400.00, null),
            ('2027-04-01', 0, 0.00, 27900.00, 0.00, null)$q$,
  'ticket 310 mil com 10% de desconto: entrada no mês, três parcelas nos meses seguintes e financiamento dois meses depois');
select is((select sum(novas_vendas_valor) - sum(entradas_novas_vendas_direta + entradas_novas_vendas_financiamento)
           from simulacao_revisao), 0.00::numeric, 'todo real vendido na simulação entra no caixa (R17)');
select is((select premissas -> 'composicao' ->> 'financiamento' from simulacao_revisao limit 1), '0.6',
  'as premissas voltam no resultado');
select throws_ok(format($q$select * from marts.simular_fluxo(%L, '{"desconto_tabela":1.5}')$q$, :'oa'), '22023', null,
  'premissa fora do intervalo vira erro 22023');

-- Mapeamento feito pelo financeiro tira a conta da pendência
reset role;
select set_config('request.jwt.claims', json_build_object('sub', :'uf', 'role', 'authenticated')::text, true);
set local role authenticated;
select throws_ok(format($q$insert into app.mapa_conta_origem (tenant_id, tipo_origem, conta_origem, categoria_codigo)
  values (%L, 'titulo_pagar', '2.88.001', 'venda_imoveis')$q$, :'tr'), '23514', null,
  'título não pode ser mapeado para categoria de entrada');
insert into app.mapa_conta_origem (tenant_id, tipo_origem, conta_origem, categoria_codigo)
values (:'tr', 'titulo_pagar', '2.88.001', 'outros_custos_obra');
select is((select count(*) from marts.pendencia_classificacao where tenant_id = :'tr' and tipo_origem = 'titulo_pagar'), 0::bigint,
  'depois do mapeamento a conta sai da pendência');
select is((select count(*) from app.auditoria_alteracao where tenant_id = :'tr' and tabela = 'app.mapa_conta_origem'
           and autor = :'uf'), 1::bigint, 'o mapeamento fica na auditoria com o autor do JWT');

-- Gerente com a obra A
reset role;
select set_config('request.jwt.claims', json_build_object('sub', :'ug', 'role', 'authenticated',
  'user_metadata', json_build_object('perfil', 'diretor', 'tenant_id', :'tx'))::text, true);
set local role authenticated;
select is((select count(*) from marts.posicao_financeira_obra), 1::bigint,
  'gerente vê só a obra A, mesmo com perfil de diretor no user_metadata');
select is((select count(*) from marts.resumo_receitas_obra), 1::bigint, 'gerente: resumo de receitas só da obra A');
select is((select count(*) from marts.carteira_recebiveis where centro_custo_id <> :'oa'), 0::bigint,
  'gerente: carteira sem a parcela da empresa nem de outras obras');
select is((select count(*) from marts.custo_obra_resumo), 1::bigint, 'gerente: custos só da obra A, sem Despesas sem obra');
select is((select count(*) from marts.custo_obra_resumo_consolidado where grupo = 'despesas_sem_obra'), 0::bigint,
  'gerente: consolidado de custos sem o grupo de despesas sem obra');
select is((select max(quantidade_centros) from marts.dre_mensal_consolidado), 1,
  'gerente: DRE consolidado com um centro só');
select is((select valor_periodo from marts.dre_periodo('2026-01-01', '2026-11-30', null) where linha_codigo = 'despesas_administrativas'),
  0.00::numeric(18,2), 'gerente: despesa administrativa sem obra não entra no consolidado dele');
select results_eq(format($q$select origem, recebido from marts.recebimento_periodo('2026-01-01', '2026-12-31', %L)$q$, :'ob'),
  $q$values ('direta', 0.00::numeric(18,2)), ('financiamento', 0.00::numeric(18,2))$q$,
  'gerente: função de período de outra obra devolve zero');
select is((select count(*) from marts.desembolso_periodo('2026-01-01', '2026-12-31', :'oc')), 0::bigint,
  'gerente: desembolso de outra obra sem linhas');
select is((select count(*) from marts.simular_fluxo(:'ob', '{}')), 0::bigint, 'gerente: simulação de outra obra sem linhas');
select is((select count(*) from marts.fluxo_projetado_mensal where centro_custo_id = :'oc'), 0::bigint,
  'gerente: fluxo projetado de outra obra invisível');
select is((select count(*) from marts.liberacao_status), 3::bigint, 'gerente lê as três liberações da própria obra');
select throws_ok(format($q$insert into app.operacao_credito_obra (tenant_id, centro_custo_id, modalidade, instituicao,
  valor_contratado, fonte) values (%L, %L, 'outra', 'x', 1, 'x')$q$, :'tr', :'oa'), '42501', null, 'gerente não grava operação');
select throws_ok(format($q$select app.registrar_versao_projecao(%L, 'tentativa')$q$, :'oa'), '42501', null,
  'gerente não registra versão');
select throws_ok(format($q$insert into app.mapa_conta_origem (tenant_id, tipo_origem, conta_origem, categoria_codigo)
  values (%L, 'titulo_pagar', '9.99', 'materiais')$q$, :'tr'), '42501', null, 'gerente não mapeia conta');

-- Leitura com a obra B
reset role;
select set_config('request.jwt.claims', json_build_object('sub', :'ul', 'role', 'authenticated')::text, true);
set local role authenticated;
select is((select string_agg(obra, ',') from marts.posicao_financeira_obra), 'Obra Revisao B', 'leitura vê só a obra B');
select throws_ok(format($q$select app.registrar_premissa_distribuicao(%L, 'x', null, '[{"competencia":"2026-12-01","fracao":1}]')$q$,
  :'ob'), '42501', null, 'leitura não registra premissa');
select is((select count(*) from marts.dre_mensal where tipo_centro = 'empresa'), 0::bigint, 'leitura não vê o centro empresa');

-- Diretor de outro tenant, com os mesmos ids de origem
reset role;
select set_config('request.jwt.claims', json_build_object('sub', :'ux', 'role', 'authenticated')::text, true);
set local role authenticated;
select is((select count(*) from marts.carteira_recebiveis where tenant_id = :'tr')
        + (select count(*) from marts.posicao_financeira_obra where tenant_id = :'tr')
        + (select count(*) from marts.dre_mensal where tenant_id = :'tr')
        + (select count(*) from marts.custo_obra_resumo_consolidado where tenant_id = :'tr')
        + (select count(*) from app.liberacao_financiamento where tenant_id = :'tr')
        + (select count(*) from app.versao_planejamento where tenant_id = :'tr'), 0::bigint,
  'outro tenant não vê nada do tenant R em detalhes, totais, consolidados e complementos');
select is((select count(*) from marts.simular_fluxo(:'oa', '{}')), 0::bigint, 'outro tenant: simulação da obra A sem linhas');
select results_eq($q$select contrato_id_origem, saldo, valor_recebido from marts.carteira_recebiveis$q$,
  $q$values (7001, 11111.00::numeric(18,2), 5555.00::numeric(18,2))$q$,
  'outro tenant vê só a própria parcela, sem mistura pelo id de origem repetido');
select is((select sum(valor_periodo) from marts.dre_periodo('2026-01-01', '2026-12-31', :'oa')), null::numeric,
  'outro tenant: DRE da obra A sem valor');
select throws_ok(format($q$insert into app.mapa_conta_origem (tenant_id, tipo_origem, conta_origem, categoria_codigo)
  values (%L, 'titulo_pagar', '9.99', 'materiais')$q$, :'tr'), '42501', null, 'outro tenant não grava no tenant R');

-- Anônimo
reset role;
select set_config('request.jwt.claims', '', true);
set local role anon;
select throws_ok('select count(*) from marts.posicao_financeira_obra', '42501', null, 'anônimo não lê marts');
select throws_ok(format($q$select * from marts.simular_fluxo(%L, '{}')$q$, :'oa'), '42501', null, 'anônimo não simula');
select throws_ok('select * from app.situacao_carga()', '42501', null, 'anônimo não lê a situação da carga');
select throws_ok('select count(*) from app.centro_custo', '42501', null, 'anônimo não lê centros de custo');

-- Nova recarga não apaga o complemento manual nem muda o staging
reset role;
select set_config('request.jwt.claims', '', true);
select staging.recarregar(:'tr');
select is((select count(*) from app.liberacao_financiamento where tenant_id = :'tr')
        + (select count(*) from app.projecao_mensal where tenant_id = :'tr'), 28::bigint,
  'recarga preserva as 3 liberações e as 25 linhas das duas versões (12 meses na 1, 13 na 2)');
select throws_ok(format($q$update app.versao_planejamento set descricao = 'x' where tenant_id = %L$q$, :'tr'),
  '42501', 'versão registrada não pode ser alterada nem apagada', 'nem o dono do banco altera uma versão registrada');
select is((select count(*) from staging.titulo_pagar_apropriacao where tenant_id = :'tr'), 9::bigint,
  'terceira recarga continua com nove apropriações');

select * from finish();
rollback;
