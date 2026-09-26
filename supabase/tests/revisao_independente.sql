-- Revisão independente das migrations 0007, 0011, 0012 e 0013 com casos próprios, valores calculados à mão
-- e diferentes dos de docs/financeiro/casos_teste.md. Tudo roda numa transação que termina em rollback,
-- com tenants e UUIDs próprios, e cada consulta filtra pelo próprio tenant: passa em banco limpo e com a demo.
-- As contas de cada número estão em docs/financeiro/revisao.md, seções "Casos independentes" e "Rodada 2".
begin;
select plan(218);

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
insert into app.criterio_reconhecimento (tenant_id, centro_custo_id, metodo, autor, validado_por)
values (:'tr', :'od', 'percentual_conclusao', '00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000000');

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

-- Rodada 2: configuração por cliente. Tenant C próprio, com as obras E e F, para que cada parâmetro mexa
-- num número conhecido. Contas em docs/financeiro/revisao.md, seção "Rodada 2".

\set tc 'a1000000-0000-4000-8000-000000000003'
\set cd 'b1000000-0000-4000-8000-000000000011'
\set cf 'b1000000-0000-4000-8000-000000000012'
\set cg 'b1000000-0000-4000-8000-000000000013'
\set cl 'b1000000-0000-4000-8000-000000000014'
\set oe 'c1000000-0000-4000-8000-000000000011'
\set of 'c1000000-0000-4000-8000-000000000012'

reset role;
select set_config('request.jwt.claims', '', true);
select set_config('app.data_referencia', '2026-11-20', true);

insert into app.tenant (id, razao_social) values (:'tc', 'Tenant sintetico da revisao C');
insert into auth.users (id, email) values
  (:'cd', 'diretor.c@exemplo.invalid'), (:'cf', 'financeiro.c@exemplo.invalid'),
  (:'cg', 'gerente.c@exemplo.invalid'), (:'cl', 'leitura.c@exemplo.invalid');
insert into app.centro_custo (id, tenant_id, id_origem, nome) values
  (:'oe', :'tc', 9201, 'Obra Revisao E'), (:'of', :'tc', 9202, 'Obra Revisao F');
insert into app.usuario_tenant (user_id, tenant_id, perfil) values
  (:'cd', :'tc', 'diretor'), (:'cf', :'tc', 'financeiro'), (:'cg', :'tc', 'gerente_obra'), (:'cl', :'tc', 'leitura');
insert into app.usuario_centro_custo (user_id, tenant_id, centro_custo_id) values (:'cg', :'tc', :'oe'), (:'cl', :'tc', :'of');

create function pg_temp.unidade_c(p_obra int, p_id int, p_situacao text, p_area numeric, p_valor numeric, p_entrega date)
returns jsonb language sql as $$
  select jsonb_build_object('id', p_id, 'enterpriseId', p_obra, 'name', 'U-' || p_id, 'propertyType', '2Q',
    'privateArea', p_area, 'commercialStock', p_situacao, 'deliveryDate', p_entrega, 'saleValuePrice', p_valor,
    'saleValueDate', '2026-09-01')
$$;

create function pg_temp.titulo_c(p_id int, p_obra int, p_conta text, p_valor numeric, p_emissao date, p_vencimento date,
  p_saldo numeric, p_pagamentos jsonb) returns jsonb
language sql as $$
  select jsonb_build_object('companyId', 1, 'creditorName', 'Fornecedor Ficticio', 'billId', p_id,
    'dueDate', p_vencimento, 'issueDate', p_emissao, 'originalAmount', p_valor, 'balanceAmount', p_saldo,
    'buildingsCosts', jsonb_build_array(jsonb_build_object('buildingId', p_obra, 'amount', p_valor)),
    'payments', p_pagamentos,
    'paymentsCategories', jsonb_build_array(jsonb_build_object('financialCategoryId', p_conta, 'financialCategoryRate', 100)))
$$;

select pg_temp.gravar(:'tc', 'units', array[
  pg_temp.unidade_c(9201, 920101, 'V', 40, 100000, '2027-06-30'), pg_temp.unidade_c(9201, 920102, 'V', 80, 300000, '2027-06-30'),
  pg_temp.unidade_c(9201, 920103, 'D', 80, 200000, '2027-06-30'), pg_temp.unidade_c(9201, 920104, 'D', 100, 500000, '2027-06-30'),
  pg_temp.unidade_c(9202, 920201, 'V', 50, 200000, '2027-03-31'), pg_temp.unidade_c(9202, 920202, 'D', 50, 250000, '2027-03-31'),
  pg_temp.unidade_c(9202, 920203, 'Z', 50, 180000, '2027-03-31')]);

select pg_temp.gravar(:'tc', 'sales', array[
  pg_temp.venda(9201, 7101, '2026-08-10', '1', null, 100000, 920101, '[{"conditionType":"AT","totalValue":100000}]'),
  pg_temp.venda(9201, 7102, '2026-09-10', '1', null, 300000, 920102,
    '[{"conditionType":"AT","totalValue":60000},{"conditionType":"FI","totalValue":240000}]', '2026-10-01'),
  pg_temp.venda(9202, 7201, '2026-05-15', '1', null, 200000, 920201,
    '[{"conditionType":"AT","totalValue":20000},{"conditionType":"PM","totalValue":80000},{"conditionType":"SF","totalValue":40000},{"conditionType":"FI","totalValue":60000}]'),
  pg_temp.venda(9202, 7202, '2026-06-01', '9', null, 150000, 920202, '[{"conditionType":"PM","totalValue":150000}]')]);

select pg_temp.gravar(:'tc', 'income', array[
  pg_temp.parcela(9201, 7101, 1, 'AT', '2026-08-10', 100000, 0, '[{"paymentDate":"2026-08-10","amount":100000}]'),
  pg_temp.parcela(9201, 7102, 1, 'AT', '2026-09-10', 60000, 0, '[{"paymentDate":"2026-09-10","amount":60000}]'),
  pg_temp.parcela(9201, 7102, 2, 'FI', '2027-01-15', 240000, 240000, '[]'),
  pg_temp.parcela(9202, 7201, 1, 'AT', '2026-05-15', 20000, 0, '[{"paymentDate":"2026-05-15","amount":20000}]'),
  pg_temp.parcela(9202, 7201, 2, 'PM', '2026-10-15', 40000, 40000, '[]'),
  pg_temp.parcela(9202, 7201, 3, 'PM', '2026-12-15', 40000, 40000, '[]'),
  pg_temp.parcela(9202, 7201, 4, 'SF', '2027-02-10', 40000, 40000, '[]'),
  pg_temp.parcela(9202, 7201, 5, 'FI', '2027-03-10', 60000, 60000, '[]')]);

select pg_temp.gravar(:'tc', 'outcome', array[
  pg_temp.titulo_c(8101, 9201, '2.06.001', 40000, '2026-03-05', '2026-03-10', 0, '[{"paymentDate":"2026-03-10","amount":40000}]'),
  pg_temp.titulo_c(8102, 9201, '2.01.001', 60000, '2026-09-05', '2026-10-05', 60000, '[]'),
  pg_temp.titulo_c(8103, 9201, '2.88.001', 20000, '2026-10-01', '2026-12-10', 20000, '[]'),
  pg_temp.titulo_c(8201, 9202, '2.01.003', 10000, null, '2026-12-05', 10000, '[]'),
  pg_temp.titulo_c(8202, 9202, '2.01.001', 300000, '2026-11-02', '2027-01-15', 300000, '[]')]);

select pg_temp.gravar(:'tc', 'building-cost-estimation-items', array[
  '{"buildingId":9201,"wbsCode":"01","description":"Terreno E","totalPrice":40000,"percentComplete":100}'::jsonb,
  '{"buildingId":9201,"wbsCode":"02","description":"Obra E","totalPrice":160000,"percentComplete":30}',
  '{"buildingId":9202,"wbsCode":"02","description":"Obra F","totalPrice":250000,"percentComplete":10}']);

insert into app.mapa_conta_origem (tenant_id, tipo_origem, conta_origem, categoria_codigo, autor)
select :'tc', t, c, k, '00000000-0000-0000-0000-000000000000'
from (values ('parcela_receber', '1.01.001', 'venda_imoveis'), ('titulo_pagar', '2.06.001', 'terreno'),
             ('titulo_pagar', '2.01.001', 'materiais'), ('titulo_pagar', '2.01.003', 'empreiteiros'),
             ('orcamento', '01', 'terreno'), ('orcamento', '02', 'materiais')) as m(t, c, k);
-- critério do tenant gravado pela carga, sem validador
insert into app.criterio_reconhecimento (tenant_id, metodo, autor)
values (:'tc', 'percentual_conclusao', '00000000-0000-0000-0000-000000000000');

select staging.recarregar(:'tc');
select staging.recarregar_precos(:'tc');

-- Estado do produto, sem nenhum valor gravado

select set_config('request.jwt.claims', json_build_object('sub', :'cd', 'role', 'authenticated')::text, true);
set local role authenticated;

select results_eq(
  format($q$select dominio, codigo_origem, quantidade_registros, valor_envolvido, valor_aplicado
            from marts.pendencia_codigo_origem where tenant_id = %L order by dominio$q$, :'tc'),
  $q$values ('condicao_pagamento', 'SF', 1::bigint, 40000.00::numeric, 'entrada_direta'),
            ('situacao_contrato', '9', 1, 150000.00, 'outro'),
            ('situacao_unidade', 'Z', 1, 180000.00, 'fora_de_venda')$q$,
  'config: os três códigos novos da obra F aparecem na pendência com o valor envolvido e o tratamento em vigor');
select results_eq(
  format($q$select disponiveis, reservadas, vendidas, indisponiveis, total from marts.estoque_atual where centro_custo_id = %L$q$, :'of'),
  $q$values (1::bigint, 0::bigint, 1::bigint, 1::bigint, 1::bigint + 2)$q$,
  'config: situação Z sem mapa conta como indisponível no estoque da obra F');
select results_eq(
  format($q$select vgv_contratado_ativo, contratos_ativos, vencido_direto, a_vencer_direto, a_vencer_financiamento
            from marts.resumo_receitas_obra where centro_custo_id = %L$q$, :'of'),
  $q$values (200000.00::numeric(18,2), 1, 40000.00::numeric(18,2), 80000.00::numeric(18,2), 60000.00::numeric(18,2))$q$,
  'config: contrato 7202 de situação 9 fica fora do VGV; parcela SF conta como entrada direta');
select results_eq(
  format($q$select centro_custo_id, metodo, motivo from app.criterio_reconhecimento_efetivo where tenant_id = %L order by centro_custo_id$q$, :'tc'),
  format($q$values (%L::uuid, 'nao_definido', 'criterio_sem_validador'), (%L::uuid, 'nao_definido', 'criterio_sem_validador')$q$, :'oe', :'of'),
  'config: percentual de conclusão gravado pela carga sem validador não vale no padrão');
select results_eq(
  format($q$select competencia, caixa_gerado_acumulado from marts.fluxo_projetado_mensal
            where centro_custo_id = %L and competencia in ('2026-11-01', '2026-12-01', '2027-01-01') order by 1$q$, :'oe'),
  $q$values ('2026-11-01'::date, 60000.00::numeric(18,2)), ('2026-12-01', 40000.00), ('2027-01-01', 280000.00)$q$,
  'config: obra E no padrão, com os 60 mil vencidos a pagar saindo em novembro');
select results_eq(
  format($q$select competencia, vencido_a_receber, caixa_gerado_acumulado, caixa_gerado_acumulado_conservador
            from marts.fluxo_projetado_mensal where centro_custo_id = %L and competencia in ('2026-11-01', '2027-01-01', '2027-03-01')
            order by 1$q$, :'of'),
  $q$values ('2026-11-01'::date, 40000.00::numeric(18,2), 20000.00::numeric(18,2), 20000.00::numeric(18,2)),
            ('2027-01-01', 0.00, -250000.00, -250000.00), ('2027-03-01', 0.00, -150000.00, -210000.00)$q$,
  'config: obra F no padrão, vencido a receber fora do saldo e FI sem data do banco só no caixa principal');
select results_eq(
  format($q$select competencia, quantidade_obras, caixa_gerado_acumulado, necessidade_aporte_acumulada
            from marts.fluxo_projetado_consolidado where tenant_id = %L
              and competencia in ('2026-03-01', '2026-05-01', '2026-11-01', '2027-01-01', '2027-03-01') order by 1$q$, :'tc'),
  $q$values ('2026-03-01'::date, 1, 40000.00::numeric(18,2) * -1, 40000.00::numeric(18,2)),
            ('2026-05-01', 2, -20000.00, 20000.00), ('2026-11-01', 2, 80000.00, 0.00),
            ('2027-01-01', 2, 30000.00, 0.00), ('2027-03-01', 1, 130000.00, 0.00)$q$,
  'config: consolidado carrega o acumulado da obra E depois do último mês dela (280 mil mais os -150 mil da F em março)');
select is((
  with mensal as (
    select competencia, sum(saldo_mes) as saldo from marts.fluxo_projetado_mensal where tenant_id = :'tc' group by 1
  ), esperado as (select competencia, sum(saldo) over (order by competencia) as acumulado from mensal)
  select count(*) from esperado e
  full join marts.fluxo_projetado_consolidado c on c.tenant_id = :'tc' and c.competencia = e.competencia
  where c.caixa_gerado_acumulado is distinct from e.acumulado), 0::bigint,
  'config: fluxo consolidado do diretor é o acumulado da soma mensal das duas obras, mês a mês');
select results_eq(
  format($q$select competencia, meses_restantes, meta_valor_contratado, meta_unidades, motivo from marts.meta_automatica_mensal
            where centro_custo_id = %L and competencia in ('2026-05-01', '2026-10-01', '2026-11-01', '2027-03-01') order by 1$q$, :'of'),
  $q$values ('2026-05-01'::date, 11, 22727.27::numeric(18,2), 1, null::text), ('2026-10-01', 6, 8333.33, 1, null),
            ('2026-11-01', 5, 10000.00, 1, null), ('2027-03-01', 5, 10000.00, 1, null)$q$,
  'config: meta automática da obra F: falta vender 250 mil de custo menos 200 mil de VGV, em cinco meses até as chaves');
select is((select meta_valor_contratado from marts.meta_automatica_mensal where centro_custo_id = :'oe' and competencia = '2026-11-01'),
  0.00::numeric(18,2), 'config: obra E já vendeu mais que o custo orçado: meta automática zero');
select results_eq(
  format($q$select competencia, meta_unidades, meta_valor_contratado from marts.visao_gerencial_mensal
            where centro_custo_id = %L and competencia = '2026-11-01'$q$, :'of'),
  $q$values ('2026-11-01'::date, null::integer, null::numeric(18,2))$q$,
  'config: com meta manual e sem versão gravada a visão gerencial fica sem meta');
create temp table simulacao_padrao as
select * from marts.simular_fluxo(:'oe', '{"novas_vendas":[{"competencia":"2026-12-01","quantidade":1}]}');
select results_eq(
  $q$select competencia, novas_vendas_valor, entradas_novas_vendas_direta, entradas_novas_vendas_financiamento
     from simulacao_padrao where competencia in ('2026-12-01', '2027-01-01', '2027-04-01', '2028-12-01') order by 1$q$,
  $q$values ('2026-12-01'::date, 350000.00::numeric(18,2), 35000.00::numeric(18,2), 0.00::numeric(18,2)),
            ('2027-01-01', 0.00, 4375.00, 0.00), ('2027-04-01', 0.00, 4375.00, 210000.00), ('2028-12-01', 0.00, 4375.00, 0.00)$q$,
  'config: venda simulada sem composição usa o padrão do produto: 10% de entrada, 30% em 24 vezes, 60% do banco 4 meses depois');
select is((select sum(entradas_novas_vendas_direta + entradas_novas_vendas_financiamento) from simulacao_padrao), 350000.00::numeric,
  'config: a venda simulada com o padrão entra inteira no caixa');

-- Reconhecimento: validação, cobertura, terreno e base da fração vendida

reset role;
select set_config('request.jwt.claims', json_build_object('sub', :'cf', 'role', 'authenticated')::text, true);
set local role authenticated;

select throws_ok(format($q$insert into app.parametro_valor (tenant_id, codigo, valor) values (%L, 'reconhecimento.exigir_validacao_usuario', 'false')$q$, :'tc'),
  '23514', null, 'config: parâmetro que muda número do financeiro exige observação');
insert into app.parametro_valor (tenant_id, codigo, valor, observacao)
values (:'tc', 'reconhecimento.exigir_validacao_usuario', 'false', 'critério aprovado em reunião');
select results_eq(
  format($q$select metodo, motivo from app.criterio_reconhecimento_efetivo where centro_custo_id = %L$q$, :'oe'),
  $q$values ('percentual_conclusao', null::text)$q$,
  'config: com a validação dispensada o critério da carga passa a valer');
select results_eq(
  format($q$select motivo, poc, cobertura_custo from marts.reconhecimento_obra_mensal where centro_custo_id = %L and competencia = '2026-11-01'$q$, :'oe'),
  $q$values ('custo_sem_categoria', null::numeric(9,6), 0.833333::numeric(9,6))$q$,
  'config: cobertura mínima 1 bloqueia com 20 mil sem categoria em 120 mil, e a cobertura real aparece');
insert into app.parametro_valor (tenant_id, codigo, valor, observacao) values (:'tc', 'reconhecimento.cobertura_minima', '0.9', 'teste');
insert into app.parametro_valor (tenant_id, centro_custo_id, codigo, valor, observacao)
values (:'tc', :'of', 'reconhecimento.cobertura_minima', '0.5', 'teste');
select is((select motivo from marts.reconhecimento_obra_mensal where centro_custo_id = :'oe' and competencia = '2026-11-01'),
  'custo_sem_categoria', 'config: tenant com cobertura 0,9 continua bloqueando 0,833333 (o valor da obra F não vale para a E)');
insert into app.parametro_valor (tenant_id, centro_custo_id, codigo, valor, observacao)
values (:'tc', :'oe', 'reconhecimento.cobertura_minima', '0.8', 'teste');
select results_eq(
  format($q$select motivo, poc, fracao_vendida, receita_reconhecida_acumulada, custo_reconhecido_acumulado, base_fracao_vendida
            from marts.reconhecimento_obra_mensal where centro_custo_id = %L and competencia = '2026-11-01'$q$, :'oe'),
  $q$values (null::text, 0.500000::numeric(9,6), 0.500000::numeric(9,6), 200000.00::numeric(18,2), 50000.00::numeric(18,2), 'unidades')$q$,
  'config: obra E com 0,8 vence o tenant: POC 100/200 mil, receita 400 mil x 0,5, custo 100 mil x 2/4 unidades');
select results_eq(
  format($q$select linha_codigo, valor_periodo from marts.dre_periodo('2026-01-01', '2026-11-30', %L)
            where linha_codigo in ('receita_bruta', 'custo_imovel_vendido', 'resultado_gerencial') order by linha_ordem$q$, :'oe'),
  $q$values ('receita_bruta', 200000.00::numeric(18,2)), ('custo_imovel_vendido', -50000.00), ('resultado_gerencial', 150000.00)$q$,
  'config: DRE da obra E no ano com o reconhecimento liberado pela cobertura');
insert into app.parametro_valor (tenant_id, centro_custo_id, codigo, valor, observacao)
values (:'tc', :'oe', 'reconhecimento.incluir_terreno', 'false', 'teste');
select results_eq(
  format($q$select poc, receita_reconhecida_acumulada, custo_reconhecido_acumulado from marts.reconhecimento_obra_mensal
            where centro_custo_id = %L and competencia = '2026-11-01'$q$, :'oe'),
  $q$values (0.375000::numeric(9,6), 150000.00::numeric(18,2), 50000.00::numeric(18,2))$q$,
  'config: sem terreno o POC é 60/160 mil e a receita cai a 150 mil; o custo reconhecido continua com o terreno');
delete from app.parametro_valor where tenant_id = :'tc' and codigo = 'reconhecimento.incluir_terreno';
insert into app.parametro_valor (tenant_id, codigo, valor, observacao) values (:'tc', 'reconhecimento.base_fracao_vendida', '"area_privativa"', 'teste');
select results_eq(
  format($q$select fracao_vendida, receita_reconhecida_acumulada, custo_reconhecido_acumulado, base_fracao_vendida
            from marts.reconhecimento_obra_mensal where centro_custo_id = %L and competencia = '2026-11-01'$q$, :'oe'),
  $q$values (0.400000::numeric(9,6), 200000.00::numeric(18,2), 40000.00::numeric(18,2), 'area_privativa')$q$,
  'config: área privativa vendida 120 de 300 m²: custo reconhecido 40 mil, receita igual');
insert into app.parametro_valor (tenant_id, centro_custo_id, codigo, valor, observacao)
values (:'tc', :'oe', 'reconhecimento.base_fracao_vendida', '"valor_tabela"', 'teste');
select results_eq(
  format($q$select fracao_vendida, custo_reconhecido_acumulado from marts.reconhecimento_obra_mensal
            where centro_custo_id = %L and competencia = '2026-11-01'$q$, :'oe'),
  $q$values (0.363636::numeric(9,6), 36363.64::numeric(18,2))$q$,
  'config: valor de tabela 400 mil de 1,1 milhão: custo reconhecido 36.363,64');
select results_eq(
  format($q$select centro_custo_id, base_fracao_vendida from app.criterio_reconhecimento_efetivo where tenant_id = %L order by 1$q$, :'tc'),
  format($q$values (%L::uuid, 'valor_tabela'), (%L::uuid, 'area_privativa')$q$, :'oe', :'of'),
  'config: obra E com o valor próprio, obra F com o do tenant');
delete from app.parametro_valor where tenant_id = :'tc' and codigo like 'reconhecimento.%' and codigo <> 'reconhecimento.exigir_validacao_usuario';
select is((select motivo from marts.reconhecimento_obra_mensal where centro_custo_id = :'oe' and competencia = '2026-11-01'),
  'custo_sem_categoria', 'config: excluir os valores volta ao padrão do produto');

-- DRE: competência dos títulos

select results_eq(
  format($q$select titulo_id_origem, data_competencia from marts.apropriacao_classificada where centro_custo_id = %L order by 1$q$, :'of'),
  $q$values (8201, null::date), (8202, '2026-11-02'::date)$q$, 'config: competência pela emissão; título sem emissão fica sem competência');
select is((select valor_periodo from marts.dre_periodo('2026-01-01', '2026-11-30', :'of') where linha_codigo = 'sem_data_competencia'),
  -10000.00::numeric(18,2), 'config: os 10 mil sem emissão caem na linha sem data de competência');
insert into app.parametro_valor (tenant_id, codigo, valor, observacao) values (:'tc', 'dre.competencia_titulo', '"emissao_ou_vencimento"', 'teste');
select results_eq(
  format($q$select titulo_id_origem, data_competencia from marts.apropriacao_classificada where centro_custo_id = %L order by 1$q$, :'of'),
  $q$values (8201, '2026-12-05'::date), (8202, '2026-11-02'::date)$q$, 'config: emissão ou vencimento completa o título sem emissão');
select is((select valor_periodo from marts.dre_periodo('2026-01-01', '2026-11-30', :'of') where linha_codigo = 'sem_data_competencia'),
  0.00::numeric(18,2), 'config: a linha sem data de competência zera');
update app.parametro_valor set valor = '"vencimento"' where tenant_id = :'tc' and codigo = 'dre.competencia_titulo';
select results_eq(
  format($q$select competencia, sum(lancado_competencia) from marts.despesa_mensal where centro_custo_id = %L
            and lancado_competencia <> 0 group by 1 order by 1$q$, :'of'),
  $q$values ('2026-12-01'::date, 10000.00::numeric), ('2027-01-01', 300000.00)$q$,
  'config: pelo vencimento o título de 300 mil sai de novembro e vai para janeiro na despesa mensal');
delete from app.parametro_valor where tenant_id = :'tc' and codigo = 'dre.competencia_titulo';

-- Caixa

insert into app.parametro_valor (tenant_id, codigo, valor) values (:'tc', 'caixa.receber_vencido', '"mes_referencia"');
select results_eq(
  format($q$select vencido_a_receber, vencido_recuperacao_prevista, caixa_gerado_acumulado from marts.fluxo_projetado_mensal
            where centro_custo_id = %L and competencia = '2026-11-01'$q$, :'of'),
  $q$values (40000.00::numeric(18,2), 40000.00::numeric(18,2), 60000.00::numeric(18,2))$q$,
  'config: vencido a receber no mês de referência com fração 1 soma os 40 mil');
insert into app.parametro_valor (tenant_id, centro_custo_id, codigo, valor) values (:'tc', :'of', 'caixa.fracao_recuperacao_vencido', '0.25');
select results_eq(
  format($q$select vencido_recuperacao_prevista, caixa_gerado_acumulado from marts.fluxo_projetado_mensal
            where centro_custo_id = %L and competencia = '2026-11-01'$q$, :'of'),
  $q$values (10000.00::numeric(18,2), 30000.00::numeric(18,2))$q$, 'config: fração 0,25 da obra F recupera 10 mil');
select is(
  (select s.carteira_prevista from marts.simular_fluxo(:'of', '{}') s where s.competencia = '2026-11-01')
    - (select s.carteira_prevista from marts.simular_fluxo(:'of', '{"cancelar_contratos": [7201]}') s where s.competencia = '2026-11-01'),
  10000.00::numeric,
  'R2-M1: cancelar o contrato 7201 na simulação tira do mês de referência os 10 mil do vencido recuperado dele');
insert into app.parametro_valor (tenant_id, centro_custo_id, codigo, valor) values (:'tc', :'of', 'caixa.receber_vencido', '"excluir"');
select results_eq(
  format($q$select vencido_recuperacao_prevista, caixa_gerado_acumulado from marts.fluxo_projetado_mensal
            where centro_custo_id = %L and competencia = '2026-11-01'$q$, :'of'),
  $q$values (0.00::numeric(18,2), 20000.00::numeric(18,2))$q$, 'config: obra F com excluir vence o mês de referência do tenant');
select is((select count(*) from marts.fluxo_projetado_mensal f full join marts.simular_fluxo(:'of', '{}') s using (competencia)
           where f.centro_custo_id = :'of' and f.caixa_gerado_acumulado is distinct from s.caixa_gerado_acumulado), 0::bigint,
  'config: simulação vazia acompanha os parâmetros de caixa da obra');
delete from app.parametro_valor where tenant_id = :'tc' and codigo like 'caixa.%';

insert into app.parametro_valor (tenant_id, centro_custo_id, codigo, valor) values (:'tc', :'oe', 'caixa.pagar_vencido', '"excluir"');
select results_eq(
  format($q$select competencia, a_pagar_vencido, caixa_gerado_acumulado from marts.fluxo_projetado_mensal
            where centro_custo_id = %L and competencia in ('2026-11-01', '2027-01-01') order by 1$q$, :'oe'),
  $q$values ('2026-11-01'::date, 60000.00::numeric(18,2), 120000.00::numeric(18,2)), ('2027-01-01', 0.00, 340000.00)$q$,
  'config: pagar vencido excluído deixa os 60 mil só na coluna informativa');
select is((select count(*) from marts.fluxo_projetado_mensal f full join marts.simular_fluxo(:'oe', '{}') s using (competencia)
           where f.centro_custo_id = :'oe' and f.caixa_gerado_acumulado is distinct from s.caixa_gerado_acumulado), 0::bigint,
  'config: simulação vazia da obra E também tira o vencido a pagar');
delete from app.parametro_valor where tenant_id = :'tc' and codigo like 'caixa.%';

insert into app.parametro_valor (tenant_id, centro_custo_id, codigo, valor) values (:'tc', :'of', 'caixa.financiamento_pendente', '"excluir"');
select results_eq(
  format($q$select previsto_financiamento_pendente, total_entradas, caixa_gerado_acumulado, caixa_gerado_acumulado_conservador
            from marts.fluxo_projetado_mensal where centro_custo_id = %L and competencia = '2027-03-01'$q$, :'of'),
  $q$values (60000.00::numeric(18,2), 0.00::numeric(18,2), -210000.00::numeric(18,2), -210000.00::numeric(18,2))$q$,
  'config: financiamento pendente excluído some do caixa principal e o conservador não o desconta duas vezes');
delete from app.parametro_valor where tenant_id = :'tc' and codigo like 'caixa.%';

-- Crédito à produção da obra F, sem retenção informada, com liberações previstas, pendentes e atrasadas
reset role;
select set_config('request.jwt.claims', json_build_object('sub', :'cd', 'role', 'authenticated')::text, true);
set local role authenticated;
insert into app.operacao_credito_obra (tenant_id, centro_custo_id, modalidade, instituicao, valor_contratado, fonte, autor)
values (:'tc', :'of', 'credito_producao', 'Banco Ficticio', 500000, 'contrato ficticio', :'cd');
select id as operacao_f from app.operacao_credito_obra where tenant_id = :'tc' \gset
insert into app.liberacao_financiamento (tenant_id, centro_custo_id, nivel, operacao_credito_id, valor_previsto, data_prevista,
  situacao, motivo, fonte, autor)
values (:'tc', :'of', 'empreendimento', :'operacao_f', 100000, '2027-01-10', 'prevista', null, 'cronograma ficticio', :'cd'),
       (:'tc', :'of', 'empreendimento', :'operacao_f', 50000, '2027-02-10', 'pendente', 'aguarda vistoria', 'cronograma ficticio', :'cd'),
       (:'tc', :'of', 'empreendimento', :'operacao_f', 30000, '2026-10-10', 'prevista', null, 'cronograma ficticio', :'cd'),
       (:'tc', :'of', 'empreendimento', :'operacao_f', 20000, '2026-11-01', 'pendente', 'aguarda vistoria', 'cronograma ficticio', :'cd');
reset role;
select set_config('request.jwt.claims', json_build_object('sub', :'cf', 'role', 'authenticated')::text, true);
set local role authenticated;
select results_eq(
  format($q$select competencia, credito_producao_previsto from marts.fluxo_projetado_mensal
            where centro_custo_id = %L and credito_producao_previsto <> 0 order by 1$q$, :'of'),
  $q$values ('2027-01-01'::date, 100000.00::numeric(18,2))$q$,
  'config: no padrão só a liberação prevista e no prazo entra no caixa');
insert into app.parametro_valor (tenant_id, centro_custo_id, codigo, valor) values (:'tc', :'of', 'caixa.liberacao_pendente', '"incluir"');
select results_eq(
  format($q$select competencia, credito_producao_previsto from marts.fluxo_projetado_mensal
            where centro_custo_id = %L and credito_producao_previsto <> 0 order by 1$q$, :'of'),
  $q$values ('2027-01-01'::date, 100000.00::numeric(18,2)), ('2027-02-01', 50000.00)$q$,
  'config: liberação pendente incluída entra em fevereiro; a pendente atrasada continua fora');
insert into app.parametro_valor (tenant_id, codigo, valor) values (:'tc', 'caixa.liberacao_atrasada', '"mes_referencia"');
select results_eq(
  format($q$select competencia, credito_producao_previsto from marts.fluxo_projetado_mensal
            where centro_custo_id = %L and credito_producao_previsto <> 0 order by 1$q$, :'of'),
  $q$values ('2026-11-01'::date, 50000.00::numeric(18,2)), ('2027-01-01', 100000.00), ('2027-02-01', 50000.00)$q$,
  'config: atrasadas no mês de referência: 30 mil prevista mais 20 mil pendente, porque a obra inclui pendentes');
delete from app.parametro_valor where tenant_id = :'tc' and centro_custo_id = :'of' and codigo = 'caixa.liberacao_pendente';
select is((select credito_producao_previsto from marts.fluxo_projetado_mensal where centro_custo_id = :'of' and competencia = '2026-11-01'),
  30000.00::numeric(18,2), 'config: sem pendentes, só a prevista atrasada de 30 mil vai para novembro');
delete from app.parametro_valor where tenant_id = :'tc' and codigo like 'caixa.%';

-- Custo sem título: premissa com um mês já encerrado
reset role;
select set_config('request.jwt.claims', json_build_object('sub', :'cd', 'role', 'authenticated')::text, true);
set local role authenticated;
select ok(app.registrar_premissa_distribuicao(:'oe', 'cronograma ficticio', null,
  '[{"competencia":"2026-10-01","fracao":0.25},{"competencia":"2026-12-01","fracao":0.75}]') is not null,
  'config: diretor registra premissa com outubro já encerrado');
select results_eq(
  format($q$select competencia, custo_sem_titulo_distribuido from marts.fluxo_projetado_mensal
            where centro_custo_id = %L and custo_sem_titulo_distribuido <> 0 order by 1$q$, :'oe'),
  $q$values ('2026-11-01'::date, 20000.00::numeric(18,2)), ('2026-12-01', 60000.00)$q$,
  'config: 80 mil sem título; a parte de outubro soma em novembro no padrão');
reset role;
select set_config('request.jwt.claims', json_build_object('sub', :'cf', 'role', 'authenticated')::text, true);
set local role authenticated;
insert into app.parametro_valor (tenant_id, centro_custo_id, codigo, valor) values (:'tc', :'oe', 'caixa.custo_sem_titulo_passado', '"ignorar"');
select results_eq(
  format($q$select competencia, custo_sem_titulo_distribuido from marts.fluxo_projetado_mensal
            where centro_custo_id = %L and custo_sem_titulo_distribuido <> 0 order by 1$q$, :'oe'),
  $q$values ('2026-12-01'::date, 60000.00::numeric(18,2))$q$, 'config: ignorar tira os 20 mil de outubro do fluxo');
select results_eq(
  format($q$select custo_sem_titulo_total, custo_sem_titulo_distribuido_total, custo_sem_titulo_nao_distribuido
            from marts.resumo_projecao_obra where centro_custo_id = %L$q$, :'oe'),
  $q$values (80000.00::numeric(18,2), 60000.00::numeric(18,2), 20000.00::numeric(18,2))$q$,
  'config: o ignorado fica como não distribuído no resumo');
delete from app.parametro_valor where tenant_id = :'tc' and codigo like 'caixa.%';

-- Financiamento

select results_eq(
  format($q$select contrato_id_origem, etapa_efetiva from marts.financiamento_contrato where tenant_id = %L order by 1$q$, :'tc'),
  $q$values (7102, 'elegivel'), (7201, null::text)$q$, 'config: data do banco na origem vale como contratação');
insert into app.parametro_valor (tenant_id, codigo, valor, observacao) values (:'tc', 'financiamento.data_origem_significa', '"repasse"', 'teste');
select results_eq(
  format($q$select contrato_id_origem, etapa_efetiva from marts.financiamento_contrato where tenant_id = %L order by 1$q$, :'tc'),
  $q$values (7102, 'liberado'), (7201, null::text)$q$, 'config: com repasse, a data do banco marca o contrato 7102 como liberado');
select results_eq(
  format($q$select competencia, previsto_financiamento_elegivel, caixa_gerado_acumulado from marts.fluxo_projetado_mensal
            where centro_custo_id = %L and competencia >= '2026-11-01' order by 1$q$, :'oe'),
  $q$values ('2026-11-01'::date, 240000.00::numeric(18,2), 280000.00::numeric(18,2)), ('2026-12-01', 0.00, 200000.00)$q$,
  'config: repasse já passado (01/10) é esperado na data de referência: os 240 mil saem de janeiro, entram em novembro e o fluxo acaba em dezembro');
delete from app.parametro_valor where tenant_id = :'tc' and codigo = 'financiamento.data_origem_significa';
select results_eq(
  format($q$select percentual_retencao, retencao_prevista, origem_retencao from marts.saldo_operacao_credito where operacao_credito_id = %L$q$, :'operacao_f'),
  $q$values (null::numeric(9,6), null::numeric(18,2), null::text)$q$, 'config: sem retenção na operação nem padrão, nada é presumido');
insert into app.parametro_valor (tenant_id, codigo, valor) values (:'tc', 'financiamento.retencao_padrao', '0.1');
select results_eq(
  format($q$select percentual_retencao, retencao_prevista, origem_retencao from marts.saldo_operacao_credito where operacao_credito_id = %L$q$, :'operacao_f'),
  $q$values (0.100000::numeric(9,6), 50000.00::numeric(18,2), 'padrao')$q$, 'config: retenção padrão do tenant de 10% sobre 500 mil');
insert into app.parametro_valor (tenant_id, centro_custo_id, codigo, valor) values (:'tc', :'of', 'financiamento.retencao_padrao', '0.2');
select results_eq(
  format($q$select retencao_prevista, saldo_liberavel from marts.saldo_operacao_credito where operacao_credito_id = %L$q$, :'operacao_f'),
  $q$values (100000.00::numeric(18,2), 400000.00::numeric(18,2))$q$, 'config: obra F com 20% vence o tenant');
select throws_ok(format($q$insert into app.parametro_valor (tenant_id, centro_custo_id, codigo, valor) values (%L, %L, 'financiamento.retencao_padrao', '0.6')$q$, :'tc', :'oe'),
  '23514', null, 'config: retenção acima de 50% é recusada');
delete from app.parametro_valor where tenant_id = :'tc' and codigo like 'financiamento.%';

-- Comercial: meta automática

insert into app.parametro_valor (tenant_id, codigo, valor) values (:'tc', 'comercial.meta_metodo', '"automatica"');
select results_eq(
  format($q$select centro_custo_id, meta_unidades, meta_valor_contratado from marts.visao_gerencial_mensal
            where tenant_id = %L and competencia = '2026-11-01' order by 1$q$, :'tc'),
  format($q$values (%L::uuid, 0, 0.00::numeric(18,2)), (%L::uuid, 1, 10000.00)$q$, :'oe', :'of'),
  'config: tenant com meta automática: 10 mil e uma unidade na obra F, zero na E');
insert into app.parametro_valor (tenant_id, centro_custo_id, codigo, valor) values (:'tc', :'oe', 'comercial.meta_metodo', '"manual"');
select results_eq(
  format($q$select centro_custo_id, meta_valor_contratado from marts.visao_gerencial_mensal
            where tenant_id = %L and competencia = '2026-11-01' order by 1$q$, :'tc'),
  format($q$values (%L::uuid, null::numeric(18,2)), (%L::uuid, 10000.00)$q$, :'oe', :'of'),
  'config: obra E manual vence o tenant automático');
select results_eq(
  format($q$select causa_codigo, quantidade, valor, origem_dado from marts.explicacao_desvio
            where centro_custo_id = %L and competencia = '2026-11-01' and causa_codigo like 'vendas%%'$q$, :'of'),
  $q$values ('vendas_abaixo_meta', -1, -10000.00::numeric, 'origem')$q$,
  'config: sem venda em novembro, o desvio compara com a meta automática');
insert into app.parametro_valor (tenant_id, centro_custo_id, codigo, valor) values (:'tc', :'of', 'comercial.meta_base', '"estimativa_conclusao"');
select results_eq(
  format($q$select base_valor, falta_vender, meta_valor_contratado from marts.meta_automatica_mensal
            where centro_custo_id = %L and competencia = '2026-11-01'$q$, :'of'),
  $q$values (310000.00::numeric(18,2), 110000.00::numeric(18,2), 22000.00::numeric(18,2))$q$,
  'config: estimativa até a conclusão usa os 310 mil lançados, acima do orçamento de 250 mil');
delete from app.parametro_valor where tenant_id = :'tc' and codigo = 'comercial.meta_base';
insert into app.parametro_valor (tenant_id, centro_custo_id, codigo, valor) values (:'tc', :'of', 'comercial.meta_horizonte', '"data_propria"');
select is((select count(*) from marts.meta_automatica_mensal where centro_custo_id = :'of' and motivo = 'horizonte_ausente'
           and meta_valor_contratado is null), 7::bigint, 'config: data própria sem data deixa a meta sem valor, com motivo');
insert into app.parametro_valor (tenant_id, centro_custo_id, codigo, valor) values (:'tc', :'of', 'comercial.meta_data_horizonte', '"2027-01-31"');
select results_eq(
  format($q$select competencia, meses_restantes, meta_valor_contratado from marts.meta_automatica_mensal
            where centro_custo_id = %L and competencia >= '2026-11-01' order by 1$q$, :'of'),
  $q$values ('2026-11-01'::date, 3, 16666.67::numeric(18,2)), ('2026-12-01', 3, 16666.67), ('2027-01-01', 3, 16666.66)$q$,
  'config: prazo em janeiro reparte 50 mil em três meses, com o centavo no último');
update app.parametro_valor set valor = '"2026-09-30"' where tenant_id = :'tc' and codigo = 'comercial.meta_data_horizonte';
select results_eq(
  format($q$select competencia, meta_valor_contratado, motivo from marts.meta_automatica_mensal
            where centro_custo_id = %L and competencia >= '2026-09-01' order by 1$q$, :'of'),
  $q$values ('2026-09-01'::date, 50000.00::numeric(18,2), null::text), ('2026-10-01', null, 'horizonte_encerrado'),
            ('2026-11-01', null, 'horizonte_encerrado')$q$,
  'config: prazo já vencido encerra a meta depois de setembro');
select throws_ok(format($q$update app.parametro_valor set valor = '"2026-02-30"' where tenant_id = %L and codigo = 'comercial.meta_data_horizonte'$q$, :'tc'),
  '23514', null, 'config: data inexistente é recusada');
delete from app.parametro_valor where tenant_id = :'tc' and codigo like 'comercial.%';

-- Simulação

insert into app.parametro_valor (tenant_id, codigo, valor) values (:'tc', 'simulacao.desconto', '0.1');
insert into app.parametro_valor (tenant_id, centro_custo_id, codigo, valor)
values (:'tc', :'oe', 'simulacao.desconto', '0.2'), (:'tc', :'oe', 'simulacao.fracao_entrada', '0.2'),
       (:'tc', :'oe', 'simulacao.fracao_parcelas', '0.2'), (:'tc', :'oe', 'simulacao.fracao_financiamento', '0.6'),
       (:'tc', :'oe', 'simulacao.quantidade_parcelas', '4'), (:'tc', :'oe', 'simulacao.meses_ate_liberacao', '2');
select results_eq(
  format($q$select competencia, novas_vendas_valor, entradas_novas_vendas_direta, entradas_novas_vendas_financiamento
            from marts.simular_fluxo(%L, '{"novas_vendas":[{"competencia":"2026-12-01","quantidade":1}]}')
            where competencia between '2026-12-01' and '2027-05-01' order by 1$q$, :'oe'),
  $q$values ('2026-12-01'::date, 280000.00::numeric(18,2), 56000.00::numeric(18,2), 0.00::numeric(18,2)),
            ('2027-01-01', 0.00, 14000.00, 0.00), ('2027-02-01', 0.00, 14000.00, 168000.00),
            ('2027-03-01', 0.00, 14000.00, 0.00), ('2027-04-01', 0.00, 14000.00, 0.00)$q$,
  'config: padrões da obra E: 20% de desconto (vence os 10% do tenant), 20% de entrada, 4 parcelas e banco 2 meses depois');
select throws_ok(format($q$update app.parametro_valor set valor = '0.3' where tenant_id = %L and centro_custo_id = %L and codigo = 'simulacao.fracao_entrada'$q$, :'tc', :'oe'),
  '23514', null, 'config: frações da obra que passam de 100% são recusadas');
delete from app.parametro_valor where tenant_id = :'tc' and centro_custo_id = :'oe' and codigo like 'simulacao.fracao%';
select throws_ok(format($q$insert into app.parametro_valor (tenant_id, centro_custo_id, codigo, valor) values (%L, %L, 'simulacao.fracao_entrada', '0.15')$q$, :'tc', :'of'),
  '23514', null, 'config: uma fração sozinha na obra soma 1,05 com as do produto e é recusada');
delete from app.parametro_valor where tenant_id = :'tc' and codigo like 'simulacao.%';

-- Subcategoria e rótulo não mexem em total

create temp table dre_antes as
select null::uuid as centro_custo_id, linha_codigo, valor_periodo from marts.dre_periodo('2026-01-01', '2026-11-30', null)
union all select :'of'::uuid, linha_codigo, valor_periodo from marts.dre_periodo('2026-01-01', '2026-11-30', :'of');
create temp table custo_antes as select * from marts.custo_obra_categoria where tenant_id = :'tc';
insert into app.categoria_tenant (tenant_id, categoria_codigo, codigo, nome) values (:'tc', 'materiais', 'aco', 'Aço e ferragens');
select id as sub_aco from app.categoria_tenant where tenant_id = :'tc' and codigo = 'aco' \gset
insert into app.categoria_tenant (tenant_id, categoria_codigo, codigo, nome) values (:'tc', 'terreno', 'escritura', 'Escritura');
select id as sub_escritura from app.categoria_tenant where tenant_id = :'tc' and codigo = 'escritura' \gset
select throws_ok(format($q$update app.mapa_conta_origem set subcategoria_id = %L where tenant_id = %L and conta_origem = '2.01.001'$q$, :'sub_escritura', :'tc'),
  '23514', null, 'config: conta de materiais não aceita subcategoria de terreno');
update app.mapa_conta_origem set subcategoria_id = :'sub_aco' where tenant_id = :'tc' and conta_origem = '2.01.001';
insert into app.rotulo_personalizado (tenant_id, contexto, chave, rotulo) values (:'tc', 'linha_dre', 'custo_obra_incorrido', 'Gasto de obra');
select throws_ok(format($q$insert into app.rotulo_personalizado (tenant_id, contexto, chave, rotulo) values (%L, 'linha_dre', 'lucro_liquido', 'Lucro')$q$, :'tc'),
  '23514', null, 'config: rótulo de linha que o DRE não tem é recusado');
select is((select count(*) from (
  select null::uuid, linha_codigo, valor_periodo from marts.dre_periodo('2026-01-01', '2026-11-30', null)
  union all select :'of'::uuid, linha_codigo, valor_periodo from marts.dre_periodo('2026-01-01', '2026-11-30', :'of')
  except select * from dre_antes) d), 0::bigint, 'config: subcategoria e rótulo não mudam nenhuma linha do DRE');
select is((select count(*) from (select * from marts.custo_obra_categoria where tenant_id = :'tc' except select * from custo_antes) d),
  0::bigint, 'config: subcategoria não muda o custo por categoria');

-- Mapa de códigos

insert into app.mapa_codigo_origem (tenant_id, dominio, codigo_origem, valor, rotulo) values (:'tc', 'situacao_unidade', 'Z', 'reservada', 'Reserva comercial');
select results_eq(
  format($q$select disponiveis, reservadas, indisponiveis from marts.estoque_atual where centro_custo_id = %L$q$, :'of'),
  $q$values (1::bigint, 1::bigint, 0::bigint)$q$, 'config: situação de unidade remapeada muda o estoque na hora, sem recarga');
select is((select situacao from marts.mapa_unidades where centro_custo_id = :'of' and unidade_id = 920203), 'reservada',
  'config: o mapa de unidades mostra a situação remapeada');
insert into app.mapa_codigo_origem (tenant_id, dominio, codigo_origem, valor) values (:'tc', 'situacao_contrato', '9', 'ativo'),
  (:'tc', 'condicao_pagamento', 'SF', 'financiamento_comprador');
update app.mapa_codigo_origem set valor = 'entrada_direta' where tenant_id = :'tc' and dominio = 'condicao_pagamento' and codigo_origem = 'FI';
select is((select count(*) from marts.pendencia_codigo_origem where tenant_id = :'tc'), 0::bigint, 'config: códigos mapeados saem da pendência');
select results_eq(
  format($q$select vgv_contratado_ativo, a_vencer_financiamento from marts.resumo_receitas_obra where centro_custo_id = %L$q$, :'of'),
  $q$values (200000.00::numeric(18,2), 60000.00::numeric(18,2))$q$, 'config: contrato e condição só mudam na próxima recarga');
select throws_ok(format($q$insert into app.mapa_codigo_origem (tenant_id, dominio, codigo_origem, valor) values (%L, 'situacao_contrato', '7', 'cancelado')$q$, :'tc'),
  '23514', null, 'config: valor fora do domínio é recusado com a lista dos aceitos');
reset role;
select set_config('request.jwt.claims', '', true);
select staging.recarregar(:'tc');
select staging.recarregar(:'tr');
select set_config('request.jwt.claims', json_build_object('sub', :'cf', 'role', 'authenticated')::text, true);
set local role authenticated;
select results_eq(
  format($q$select centro_custo_id, vgv_contratado_ativo, contratos_ativos, a_vencer_direto, a_vencer_financiamento
            from marts.resumo_receitas_obra where tenant_id = %L and tipo_centro = 'obra' order by 1$q$, :'tc'),
  format($q$values (%L::uuid, 400000.00::numeric(18,2), 2, 240000.00::numeric(18,2), 0.00::numeric(18,2)),
                   (%L::uuid, 350000.00, 2, 100000.00, 40000.00)$q$, :'oe', :'of'),
  'config: depois da recarga: 7202 ativo soma 150 mil, SF vira financiamento e FI deste tenant vira entrada direta');
select is((select valor_financiado from staging.contrato_venda where tenant_id = :'tc' and id_origem = 7201), 40000.00::numeric,
  'config: valor financiado do contrato 7201 passa a ser só a parcela SF');
reset role;
select set_config('request.jwt.claims', json_build_object('sub', :'ud', 'role', 'authenticated')::text, true);
set local role authenticated;
select is((select origem from marts.carteira_recebiveis where tenant_id = :'tr' and contrato_id_origem = 7002 and parcela_id_origem = 2),
  'financiamento', 'config: o mapa do tenant C não mexe no FI do tenant R');

-- Fuso e limite de horas da carga

reset role;
insert into app.parametro_valor (tenant_id, codigo, valor, autor) values (:'tr', 'negocio.fuso_horario', '"Pacific/Pago_Pago"', :'ud');
update raw.registro set carregado_em = now() - interval '30 hours' where tenant_id = :'tc';
select set_config('request.jwt.claims', json_build_object('sub', :'cf', 'role', 'authenticated')::text, true);
set local role authenticated;
select throws_ok(format($q$insert into app.parametro_valor (tenant_id, codigo, valor) values (%L, 'negocio.fuso_horario', '"America/Sao_Paulox"')$q$, :'tc'),
  '23514', null, 'config: fuso inexistente é recusado');
select throws_ok(format($q$insert into app.parametro_valor (tenant_id, centro_custo_id, codigo, valor) values (%L, %L, 'negocio.fuso_horario', '"UTC"')$q$, :'tc', :'oe'),
  '23514', null, 'config: fuso é da construtora, não da obra');
insert into app.parametro_valor (tenant_id, codigo, valor) values (:'tc', 'negocio.fuso_horario', '"Pacific/Kiritimati"');
select set_config('app.data_referencia', '', true);
select is(app.data_referencia(), (now() at time zone 'Pacific/Kiritimati')::date, 'config: sem data fixada, o dia de referência é o do fuso do tenant');
reset role;
select set_config('request.jwt.claims', json_build_object('sub', :'ud', 'role', 'authenticated')::text, true);
set local role authenticated;
select is(app.data_referencia(), (now() at time zone 'Pacific/Pago_Pago')::date,
  'config: trocar de usuário na mesma transação troca o fuso (a memória do fuso segue os claims)');
select data_referencia as dia_pago_pago from app.situacao_carga() \gset
reset role;
select set_config('request.jwt.claims', json_build_object('sub', :'cd', 'role', 'authenticated')::text, true);
set local role authenticated;
select ok((select data_referencia from app.situacao_carga()) - :'dia_pago_pago'::date between 1 and 2,
  'config: Kiritimati está sempre um ou dois dias à frente de Pago Pago');
select results_eq($q$select horas_desde_carga, desatualizada from app.situacao_carga()$q$,
  $q$values (30.0::numeric(9,1), true)$q$, 'config: carga de 30 horas atrás passa do limite padrão de 26');
reset role;
select set_config('request.jwt.claims', json_build_object('sub', :'cf', 'role', 'authenticated')::text, true);
set local role authenticated;
insert into app.parametro_valor (tenant_id, codigo, valor) values (:'tc', 'alerta.carga_desatualizada_horas', '48');
select is((select desatualizada from app.situacao_carga()), false, 'config: com limite de 48 horas a mesma carga está em dia');
select throws_ok(format($q$update app.parametro_valor set valor = '200' where tenant_id = %L and codigo = 'alerta.carga_desatualizada_horas'$q$, :'tc'),
  '23514', null, 'config: limite acima de 168 horas é recusado');
select throws_ok(format($q$update app.parametro_valor set valor = '"48"' where tenant_id = %L and codigo = 'alerta.carga_desatualizada_horas'$q$, :'tc'),
  '23514', null, 'config: número em texto é recusado');
select set_config('app.data_referencia', '2026-11-20', true);

-- Isolamento e escrita

insert into app.parametro_valor (tenant_id, centro_custo_id, codigo, valor) values (:'tc', :'of', 'caixa.fracao_recuperacao_vencido', '0.3');
insert into app.parametro_valor (tenant_id, codigo, valor) values (:'tc', 'caixa.fracao_recuperacao_vencido', '0.7');
select throws_ok(format($q$insert into app.parametro_valor (tenant_id, codigo, valor) values (%L, 'caixa.pagar_vencido', '"excluir"')$q$, :'tr'),
  '42501', null, 'config: financeiro não grava no tenant R');
select throws_ok(format($q$insert into app.parametro_valor (tenant_id, centro_custo_id, codigo, valor) values (%L, %L, 'caixa.pagar_vencido', '"excluir"')$q$, :'tc', :'oa'),
  '23514', null, 'config: financeiro não grava valor numa obra de outro tenant');
select throws_ok(format($q$insert into app.parametro_valor (tenant_id, codigo, valor) values (%L, 'caixa.pagar_vencido', '"excluir''); drop table app.tenant; --"')$q$, :'tc'),
  '23514', null, 'config: texto com SQL no valor jsonb é só uma opção inexistente');
reset role;
select set_config('request.jwt.claims', json_build_object('sub', :'cg', 'role', 'authenticated')::text, true);
set local role authenticated;
select is((select count(*) from app.parametro_valor where centro_custo_id = :'of'), 0::bigint, 'config: gerente da obra E não lê o valor da obra F');
select results_eq($q$select centro_custo_id, caixa__fracao_recuperacao_vencido from app.parametros_obra$q$,
  format($q$values (%L::uuid, 0.700000::numeric(9,6))$q$, :'oe'), 'config: gerente vê só a obra E, com o valor do tenant');
select is((select count(*) from app.configuracao_efetiva where centro_custo_id = :'of'), 0::bigint,
  'config: a configuração em vigor da obra F não aparece para o gerente da E');
select results_eq(
  format($q$select competencia, quantidade_obras, caixa_gerado_acumulado from marts.fluxo_projetado_consolidado
            where tenant_id = %L and competencia = '2027-01-01'$q$, :'tc'),
  $q$values ('2027-01-01'::date, 1, 200000.00::numeric(18,2))$q$, 'config: consolidado do gerente só tem a obra E, já com a premissa');
select throws_ok(format($q$insert into app.parametro_valor (tenant_id, centro_custo_id, codigo, valor) values (%L, %L, 'caixa.pagar_vencido', '"excluir"')$q$, :'tc', :'oe'),
  '42501', null, 'config: gerente não grava parâmetro nem da própria obra');
update app.parametro_valor set valor = '0.1' where tenant_id = :'tc' and codigo = 'caixa.fracao_recuperacao_vencido' and centro_custo_id is null;
select throws_ok(format($q$insert into app.mapa_codigo_origem (tenant_id, dominio, codigo_origem, valor) values (%L, 'situacao_unidade', 'Q', 'vendida')$q$, :'tc'),
  '42501', null, 'config: gerente não mapeia código');
select throws_ok(format($q$insert into app.rotulo_personalizado (tenant_id, contexto, chave, rotulo) values (%L, 'categoria', 'materiais', 'x')$q$, :'tc'),
  '42501', null, 'config: gerente não grava rótulo');
reset role;
select set_config('request.jwt.claims', json_build_object('sub', :'cl', 'role', 'authenticated')::text, true);
set local role authenticated;
select is((select caixa__fracao_recuperacao_vencido from app.parametros_obra where centro_custo_id = :'of'), 0.300000::numeric(9,6),
  'config: leitura da obra F vê o valor dela, e o update do gerente não mudou o do tenant');
select is((select valor::text from app.parametro_valor where tenant_id = :'tc' and codigo = 'caixa.fracao_recuperacao_vencido' and centro_custo_id is null),
  '0.7', 'config: update do gerente passou por zero linhas');
select throws_ok(format($q$insert into app.categoria_tenant (tenant_id, categoria_codigo, codigo, nome) values (%L, 'materiais', 'x', 'x')$q$, :'tc'),
  '42501', null, 'config: leitura não cria subcategoria');
delete from app.parametro_valor where tenant_id = :'tc';
select is((select count(*) from app.parametro_valor where tenant_id = :'tc' and codigo = 'caixa.fracao_recuperacao_vencido'), 2::bigint,
  'config: exclusão pela leitura passa por zero linhas');
reset role;
select set_config('request.jwt.claims', json_build_object('sub', :'ux', 'role', 'authenticated')::text, true);
set local role authenticated;
select is((select count(*) from app.parametro_valor where tenant_id = :'tc') + (select count(*) from app.mapa_codigo_origem where tenant_id = :'tc')
        + (select count(*) from app.categoria_tenant where tenant_id = :'tc') + (select count(*) from app.rotulo_personalizado where tenant_id = :'tc')
        + (select count(*) from app.configuracao_efetiva where tenant_id = :'tc') + (select count(*) from app.parametros_obra where tenant_id = :'tc')
        + (select count(*) from marts.pendencia_codigo_origem where tenant_id = :'tc') + (select count(*) from marts.fluxo_projetado_consolidado where tenant_id = :'tc'),
  0::bigint, 'config: outro tenant não vê nada da configuração do tenant C');
select throws_ok('select app.gerar_views_parametros()', '42501', null, 'config: usuário não recria as views de parâmetros');
select throws_ok(format($q$select app.semear_mapa_codigo_origem(%L)$q$, :'tc'), '42501', null, 'config: usuário não semeia o mapa de outro tenant');
select throws_ok($q$insert into app.parametro (codigo, grupo, nome, descricao, tipo, padrao, escopo, ordem) values ('exibicao.x', 'exibicao', 'x', 'x', 'texto', '"x"', 'tenant', 9999)$q$,
  '42501', null, 'config: catálogo é só leitura para o usuário');
reset role;
select set_config('request.jwt.claims', '', true);
set local role anon;
select throws_ok('select app.fuso_horario_atual()', '42501', null, 'config: anônimo não chama o fuso');
select throws_ok('select count(*) from app.parametro', '42501', null, 'config: anônimo não lê o catálogo');
reset role;

select is((select count(*) from app.auditoria_alteracao where tenant_id = :'tc' and autor = :'cf'
           and tabela in ('app.parametro_valor', 'app.mapa_codigo_origem', 'app.categoria_tenant', 'app.rotulo_personalizado')),
  (select count(*) from app.auditoria_alteracao where tenant_id = :'tc'
           and tabela in ('app.parametro_valor', 'app.mapa_codigo_origem', 'app.categoria_tenant', 'app.rotulo_personalizado')),
  'config: todo registro de histórico da configuração do tenant C tem o financeiro como autor');
select ok((select count(distinct tabela) from app.auditoria_alteracao where tenant_id = :'tc' and autor = :'cf') >= 4,
  'config: o histórico cobre parâmetros, códigos, subcategorias e rótulos');

-- Catálogo do banco

select is((select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'app' and c.relname in ('parametro', 'parametro_valor', 'mapa_codigo_origem', 'rotulo_personalizado',
                                                     'categoria_tenant', 'valor_codigo_origem')
             and c.relrowsecurity and c.relforcerowsecurity), 6::bigint,
  'config: as seis tabelas novas com RLS ligado e forçado');
select is((select count(*) from (select tablename, cmd from pg_policies where schemaname = 'app'
           and tablename in ('parametro', 'parametro_valor', 'mapa_codigo_origem', 'rotulo_personalizado', 'categoria_tenant', 'valor_codigo_origem')
           and permissive = 'PERMISSIVE' group by 1, 2 having count(*) > 1 or cmd = 'ALL') x), 0::bigint,
  'config: uma política permissiva por tabela e ação, nenhuma ALL');
select is((select count(*) from pg_policies where schemaname in ('app', 'staging', 'marts')
           and (btrim(coalesce(qual, '')) = 'true' or btrim(coalesce(with_check, '')) = 'true')), 0::bigint,
  'config: nenhuma política using (true) ou with check (true)');
select is((select count(*) from pg_policies where schemaname = 'app'
           and tablename in ('parametro_valor', 'mapa_codigo_origem', 'rotulo_personalizado', 'categoria_tenant')
           and cmd <> 'SELECT'
           and not (coalesce(qual, '') || coalesce(with_check, '')) ~ 'perfil_atual\(\).*diretor.*financeiro'), 0::bigint,
  'config: toda escrita nas tabelas novas exige diretor ou financeiro pelo perfil_atual');
select is((select count(*) from pg_policies where schemaname = 'app' and (coalesce(qual, '') || coalesce(with_check, '')) ~ 'user_metadata'),
  0::bigint, 'config: nenhuma política lê user_metadata');
select ok(not has_table_privilege('authenticated', 'app.parametro', 'INSERT, UPDATE, DELETE')
          and not has_table_privilege('authenticated', 'app.valor_codigo_origem', 'INSERT, UPDATE, DELETE'),
  'config: catálogo e valores aceitos sem escrita para authenticated');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname in ('app', 'staging', 'marts') and p.prosecdef
             and not coalesce(p.proconfig, '{}') @> array['search_path=""']), 0::bigint,
  'config: toda função security definer com search_path vazio');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'app' and p.proname in ('gerar_views_parametros', 'semear_mapa_codigo_origem', 'semear_tenant_novo',
                                                    'validar_parametro_valor', 'conferir_composicao_simulacao', 'validar_mapa_codigo_origem')
             and (has_function_privilege('authenticated', p.oid, 'EXECUTE') or has_function_privilege('anon', p.oid, 'EXECUTE'))),
  0::bigint, 'config: funções internas da configuração sem execute para authenticated e anon');
select ok(has_function_privilege('authenticated', 'app.fuso_horario_atual()', 'EXECUTE')
          and not has_function_privilege('anon', 'app.fuso_horario_atual()', 'EXECUTE'),
  'config: fuso do tenant só para usuário logado');
select is((select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname in ('app', 'marts') and c.relkind = 'v'
             and not coalesce(c.reloptions, '{}') @> array['security_invoker=true']), 0::bigint,
  'config: todas as views de app e marts com security_invoker');

-- Injeção pelo catálogo: o código tem formato fixo e o gerador de views só usa %I e %L
select throws_ok($q$insert into app.parametro (codigo, grupo, nome, descricao, tipo, padrao, escopo, ordem)
                    values ('exibicao.x"; drop table app.tenant; --', 'exibicao', 'x', 'x', 'texto', '"x"', 'tenant', 9998)$q$,
  '23514', null, 'config: código de parâmetro fora do formato é recusado até para o dono do banco');
insert into app.parametro (codigo, grupo, nome, descricao, tipo, padrao, escopo, ordem)
values ('exibicao.teste_revisao', 'exibicao', 'Teste''); drop table app.tenant; --', 'x', 'texto',
        to_jsonb('x''); drop table app.tenant; --'::text), 'tenant', 9997);
select lives_ok('select app.gerar_views_parametros()', 'config: gerador de views aceita o parâmetro novo');
select is((select exibicao__teste_revisao from app.parametros_tenant where tenant_id = :'tc'), 'x''); drop table app.tenant; --',
  'config: o texto do padrão volta como literal na coluna nova');
select ok(to_regclass('app.tenant') is not null and (select count(*) from app.tenant where id = :'tc') = 1,
  'config: nada do texto foi executado');

select * from finish();
rollback;
