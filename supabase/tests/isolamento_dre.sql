-- Isolamento dos objetos da migration 0011 (caso C12 na parte do DRE): gerente não vê outra obra nem
-- Despesas sem obra, nem as linhas delas nos consolidados; outro tenant fica invisível; gerente e
-- leitura não gravam mapeamento nem critério; a auditoria guarda cada alteração com o autor do JWT.
begin;
create extension if not exists pgtap with schema extensions;
select plan(53);

insert into app.tenant (id, razao_social) values
  ('7e000000-0000-4000-8000-00000000000a', 'Construtora Teste Financeiro A'),
  ('7e000000-0000-4000-8000-00000000000b', 'Construtora Teste Financeiro B');

insert into app.centro_custo (id, tenant_id, id_origem, nome, tipo) values
  ('7c000000-0000-4000-8000-0000000000a1', '7e000000-0000-4000-8000-00000000000a', 9001, 'Obra Teste 1', 'obra'),
  ('7c000000-0000-4000-8000-0000000000a2', '7e000000-0000-4000-8000-00000000000a', 9002, 'Obra Teste 2', 'obra'),
  ('7c000000-0000-4000-8000-0000000000ae', '7e000000-0000-4000-8000-00000000000a', null, 'Despesas sem obra', 'empresa'),
  ('7c000000-0000-4000-8000-0000000000b1', '7e000000-0000-4000-8000-00000000000b', 9001, 'Obra Teste B1', 'obra'),
  ('7c000000-0000-4000-8000-0000000000be', '7e000000-0000-4000-8000-00000000000b', null, 'Despesas sem obra', 'empresa');

insert into auth.users (id, email) values
  ('7a000000-0000-4000-8000-00000000d00a', 'diretor.financeiro@teste.invalid'),
  ('7a000000-0000-4000-8000-00000000f00a', 'financeiro.financeiro@teste.invalid'),
  ('7a000000-0000-4000-8000-00000000c00a', 'gerente.financeiro@teste.invalid'),
  ('7a000000-0000-4000-8000-00000000e00a', 'leitura.financeiro@teste.invalid'),
  ('7a000000-0000-4000-8000-00000000d00b', 'diretorb.financeiro@teste.invalid');

insert into app.usuario_tenant (user_id, tenant_id, perfil) values
  ('7a000000-0000-4000-8000-00000000d00a', '7e000000-0000-4000-8000-00000000000a', 'diretor'),
  ('7a000000-0000-4000-8000-00000000f00a', '7e000000-0000-4000-8000-00000000000a', 'financeiro'),
  ('7a000000-0000-4000-8000-00000000c00a', '7e000000-0000-4000-8000-00000000000a', 'gerente_obra'),
  ('7a000000-0000-4000-8000-00000000e00a', '7e000000-0000-4000-8000-00000000000a', 'leitura'),
  ('7a000000-0000-4000-8000-00000000d00b', '7e000000-0000-4000-8000-00000000000b', 'diretor');

insert into app.usuario_centro_custo (user_id, tenant_id, centro_custo_id) values
  ('7a000000-0000-4000-8000-00000000c00a', '7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1'),
  ('7a000000-0000-4000-8000-00000000e00a', '7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1');

-- Payloads do C08 no tenant A, com um contrato e parcelas em cada obra, e um título do tenant B.
insert into raw.registro (tenant_id, endpoint, payload, hash_registro)
select '7e000000-0000-4000-8000-00000000000a', e, x, md5(e || x::text)
from (values
  ('outcome', '[
    {"billId": 7801, "dueDate": "2026-03-20", "issueDate": "2026-02-01", "originalAmount": 1000.00, "balanceAmount": 899.95,
     "buildingsCosts": [{"buildingId": 9001, "amount": 500.00}, {"buildingId": 9002, "amount": 500.00}],
     "payments": [{"paymentDate": "2026-02-10", "amount": 100.05}]},
    {"billId": 7802, "dueDate": "2026-02-15", "issueDate": "2026-02-05", "originalAmount": 800.00, "balanceAmount": 0,
     "payments": [{"paymentDate": "2026-02-15", "amount": 800.00}]},
    {"billId": 7803, "dueDate": "2026-03-05", "issueDate": "2026-02-10", "originalAmount": 50.00, "balanceAmount": 50.00,
     "buildingsCosts": [{"buildingId": 9999, "amount": 50.00}], "payments": []}]'::jsonb),
  ('sales', '[
    {"id": 5101, "enterpriseId": 9001, "contractDate": "2026-01-05", "situation": "1", "value": 1000.00, "units": [{"id": 90101}]},
    {"id": 5201, "enterpriseId": 9002, "contractDate": "2026-01-05", "situation": "1", "value": 500.00, "units": [{"id": 90201}]}]'::jsonb),
  ('units', '[{"id": 90101, "enterpriseId": 9001, "name": "T1-01"}, {"id": 90201, "enterpriseId": 9002, "name": "T2-01"}]'::jsonb),
  ('income', '[
    {"projectId": 9001, "billId": 5101, "installmentId": 1, "dueDate": "2026-01-10", "originalAmount": 1000.00,
     "balanceAmount": 0, "correctedBalanceAmount": 0, "paymentTerm": {"id": "PM"},
     "receipts": [{"paymentDate": "2026-02-05", "amount": 1000.00}]},
    {"projectId": 9002, "billId": 5201, "installmentId": 1, "dueDate": "2026-01-10", "originalAmount": 500.00,
     "balanceAmount": 0, "correctedBalanceAmount": 0, "paymentTerm": {"id": "PM"},
     "receipts": [{"paymentDate": "2026-02-05", "amount": 500.00}]}]'::jsonb),
  ('building-cost-estimation-items', '[
    {"buildingId": 9001, "wbsCode": "01", "totalPrice": 2000.00}, {"buildingId": 9002, "wbsCode": "01", "totalPrice": 3000.00}]'::jsonb)
) as p(e, lista)
cross join lateral jsonb_array_elements(p.lista) x;
insert into raw.registro (tenant_id, endpoint, payload, hash_registro)
values ('7e000000-0000-4000-8000-00000000000b', 'outcome',
  '{"billId": 7999, "dueDate": "2026-02-10", "issueDate": "2026-02-01", "originalAmount": 100.00, "balanceAmount": 0,
    "buildingsCosts": [{"buildingId": 9001, "amount": 100.00}], "payments": [{"paymentDate": "2026-02-10", "amount": 100.00}]}',
  'c12-tenant-b');

select staging.recarregar('7e000000-0000-4000-8000-00000000000a');
select staging.recarregar('7e000000-0000-4000-8000-00000000000b');
insert into app.mapa_conta_origem (tenant_id, tipo_origem, conta_origem, categoria_codigo, autor) values
  ('7e000000-0000-4000-8000-00000000000b', 'titulo_pagar', '2.01.001', 'materiais', '7a000000-0000-4000-8000-00000000d00b');
insert into app.criterio_reconhecimento (tenant_id, metodo, autor) values
  ('7e000000-0000-4000-8000-00000000000b', 'percentual_conclusao', '7a000000-0000-4000-8000-00000000d00b');
select set_config('app.data_referencia', '2026-02-28', true);

-- Financeiro grava mapeamento e critério; autor e validação vêm do JWT e a auditoria registra tudo
select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000f00a", "role": "authenticated"}', true);
set local role authenticated;
select lives_ok(
  $$insert into app.mapa_conta_origem (tenant_id, tipo_origem, conta_origem, categoria_codigo, autor)
    values ('7e000000-0000-4000-8000-00000000000a', 'titulo_pagar', '2.01.001', 'materiais', '7a000000-0000-4000-8000-00000000d00a')$$,
  'financeiro inclui mapeamento'
);
select lives_ok(
  $$update app.mapa_conta_origem set categoria_codigo = 'mao_de_obra', observacao = 'reclassificado'
    where tenant_id = '7e000000-0000-4000-8000-00000000000a' and conta_origem = '2.01.001'$$,
  'financeiro altera mapeamento'
);
select lives_ok(
  $$insert into app.criterio_reconhecimento (tenant_id, centro_custo_id, metodo)
    values ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a2', 'percentual_conclusao')$$,
  'financeiro liga o percentual de conclusão numa obra'
);
select throws_ok(
  $$insert into app.criterio_reconhecimento (tenant_id, centro_custo_id, metodo)
    values ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000b1', 'percentual_conclusao')$$,
  '23514', null, 'financeiro não cria critério para obra de outro tenant'
);
select throws_ok(
  $$insert into app.mapa_conta_origem (tenant_id, tipo_origem, conta_origem, categoria_codigo)
    values ('7e000000-0000-4000-8000-00000000000b', 'titulo_pagar', '2.03.001', 'corretagem')$$,
  '42501', null, 'financeiro não grava mapeamento de outro tenant'
);
select throws_ok(
  $$insert into app.categoria_gerencial (codigo, nome, grupo_dre, natureza, ordem)
    values ('outros', 'Outros', 'despesa_administrativa', 'saida', 99)$$,
  '42501', null, 'categoria global não aceita escrita pela API'
);
reset role;
select results_eq(
  $$select autor, categoria_codigo, atualizado_em is not null from app.mapa_conta_origem
    where tenant_id = '7e000000-0000-4000-8000-00000000000a'$$,
  $$values ('7a000000-0000-4000-8000-00000000f00a'::uuid, 'mao_de_obra', true)$$,
  'autor do mapeamento é o do JWT, não o mandado'
);
select results_eq(
  $$select operacao, autor, antes ->> 'categoria_codigo', depois ->> 'categoria_codigo' from app.auditoria_alteracao
    where tabela = 'app.mapa_conta_origem' and registro_id = '7e000000-0000-4000-8000-00000000000a|titulo_pagar|2.01.001'
    order by id$$,
  $$values ('insert', '7a000000-0000-4000-8000-00000000f00a'::uuid, null, 'materiais'),
           ('update', '7a000000-0000-4000-8000-00000000f00a'::uuid, 'materiais', 'mao_de_obra')$$,
  'histórico do mapeamento com antes, depois e autor'
);
select results_eq(
  $$select a.operacao, a.autor, (a.depois ->> 'validado_por')::uuid from app.auditoria_alteracao a
    join app.criterio_reconhecimento c on a.registro_id = c.id::text
    where a.tabela = 'app.criterio_reconhecimento' and c.tenant_id = '7e000000-0000-4000-8000-00000000000a'$$,
  $$values ('insert', '7a000000-0000-4000-8000-00000000f00a'::uuid, '7a000000-0000-4000-8000-00000000f00a'::uuid)$$,
  'histórico do critério com quem validou'
);

-- Gerente da obra T1
select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000c00a", "role": "authenticated"}', true);
set local role authenticated;

select is(
  (select count(*) from marts.carteira_recebiveis where centro_custo_id <> '7c000000-0000-4000-8000-0000000000a1')
  + (select count(*) from marts.resumo_receitas_obra where centro_custo_id <> '7c000000-0000-4000-8000-0000000000a1')
  + (select count(*) from marts.recebimento_mensal where centro_custo_id <> '7c000000-0000-4000-8000-0000000000a1')
  + (select count(*) from marts.custo_obra_categoria where centro_custo_id <> '7c000000-0000-4000-8000-0000000000a1')
  + (select count(*) from marts.custo_obra_resumo where centro_custo_id <> '7c000000-0000-4000-8000-0000000000a1')
  + (select count(*) from marts.despesa_mensal where centro_custo_id <> '7c000000-0000-4000-8000-0000000000a1')
  + (select count(*) from marts.reconhecimento_obra_mensal where centro_custo_id <> '7c000000-0000-4000-8000-0000000000a1')
  + (select count(*) from marts.dre_mensal where centro_custo_id <> '7c000000-0000-4000-8000-0000000000a1')
  + (select count(*) from marts.apropriacao_classificada where centro_custo_id <> '7c000000-0000-4000-8000-0000000000a1'),
  0::bigint,
  'gerente não vê outra obra nem Despesas sem obra em nenhuma view nova'
);
select ok((select count(*) from marts.dre_mensal) > 0, 'gerente vê o DRE da própria obra');
select results_eq(
  $$select competencia, valor_mes, quantidade_centros from marts.dre_mensal_consolidado
    where linha_codigo = 'sem_categoria' and competencia = '2026-02-01'$$,
  $$values ('2026-02-01'::date, -500.00::numeric(18,2), 1)$$,
  'consolidado do gerente soma só a parte de T1 do título rateado'
);
select results_eq(
  $$select valor_periodo from marts.dre_periodo('2026-01-01', '2026-02-28') where linha_codigo = 'sem_categoria'$$,
  $$values (-500.00::numeric(18,2))$$,
  'DRE do período do gerente sem as outras obras'
);
select is((select count(*) from marts.dre_periodo('2026-01-01', '2026-02-28', '7c000000-0000-4000-8000-0000000000a2')),
  0::bigint, 'DRE do período de obra alheia volta vazio');
select is((select count(*) from marts.dre_periodo('2026-01-01', '2026-02-28', '7c000000-0000-4000-8000-0000000000ae')),
  0::bigint, 'DRE do período de Despesas sem obra volta vazio para o gerente');
select results_eq(
  $$select origem, recebido from marts.recebimento_periodo('2026-01-01', '2026-02-28', '7c000000-0000-4000-8000-0000000000a2')$$,
  $$values ('direta', 0.00::numeric(18,2)), ('financiamento', 0.00::numeric(18,2))$$,
  'recebimento de obra alheia sai zerado, sem revelar valor'
);
select is((select count(*) from marts.desembolso_periodo('2026-01-01', '2026-02-28', '7c000000-0000-4000-8000-0000000000ae')),
  0::bigint, 'desembolso de Despesas sem obra volta vazio para o gerente');
select results_eq(
  $$select quantidade_obras, vgv_contratado_ativo, recebido_direto from marts.resumo_receitas_consolidado$$,
  $$values (1, 1000.00::numeric(18,2), 1000.00::numeric(18,2))$$,
  'resumo de receitas consolidado do gerente só com T1'
);
select results_eq(
  $$select competencia, origem, recebido from marts.recebimento_mensal_consolidado$$,
  $$values ('2026-01-01'::date, 'direta', 0.00::numeric(18,2)), ('2026-02-01'::date, 'direta', 1000.00::numeric(18,2))$$,
  'recebimento mensal consolidado do gerente só com T1'
);
select results_eq(
  $$select grupo, quantidade_centros, custo_lancado, orcamento_vigente from marts.custo_obra_resumo_consolidado$$,
  $$values ('obras', 1, 500.00::numeric(18,2), 2000.00::numeric(18,2))$$,
  'custo consolidado do gerente sem o grupo Despesas sem obra e sem T2'
);
select results_eq(
  $$select tipo_origem, conta_origem, valor_envolvido, participacao from marts.pendencia_classificacao
    where tipo_origem = 'titulo_pagar'$$,
  $$values ('titulo_pagar', null::text, 500.00::numeric(18,2), 1.000000::numeric(9,6))$$,
  'pendência do gerente conta só o valor da obra dele'
);
select is((select count(*) from app.criterio_reconhecimento), 0::bigint,
  'gerente não vê o critério de outra obra');
select is((select count(*) from app.mapa_conta_origem), 1::bigint, 'gerente lê o mapeamento do próprio tenant');
select is((select count(*) from app.categoria_gerencial), 19::bigint, 'gerente lê as categorias');
select is((select count(*) from app.auditoria_alteracao), 0::bigint, 'gerente não vê a auditoria');
select throws_ok(
  $$insert into app.mapa_conta_origem (tenant_id, tipo_origem, conta_origem, categoria_codigo)
    values ('7e000000-0000-4000-8000-00000000000a', 'titulo_pagar', '2.03.001', 'corretagem')$$,
  '42501', null, 'gerente não inclui mapeamento'
);
select throws_ok(
  $$insert into app.criterio_reconhecimento (tenant_id, metodo) values ('7e000000-0000-4000-8000-00000000000a', 'percentual_conclusao')$$,
  '42501', null, 'gerente não inclui critério do tenant'
);
select throws_ok(
  $$insert into app.criterio_reconhecimento (tenant_id, centro_custo_id, metodo)
    values ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1', 'percentual_conclusao')$$,
  '42501', null, 'gerente não inclui critério nem na própria obra'
);
select is_empty(
  $$update app.mapa_conta_origem set categoria_codigo = 'materiais' where tenant_id = '7e000000-0000-4000-8000-00000000000a'
    returning conta_origem$$,
  'update do gerente no mapeamento não alcança linha nenhuma'
);
select is_empty(
  $$delete from app.mapa_conta_origem where tenant_id = '7e000000-0000-4000-8000-00000000000a' returning conta_origem$$,
  'delete do gerente no mapeamento não alcança linha nenhuma'
);
reset role;
select is((select categoria_codigo from app.mapa_conta_origem where tenant_id = '7e000000-0000-4000-8000-00000000000a'),
  'mao_de_obra', 'mapeamento intacto depois das tentativas do gerente');

-- Perfil leitura
select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000e00a", "role": "authenticated"}', true);
set local role authenticated;
select throws_ok(
  $$insert into app.mapa_conta_origem (tenant_id, tipo_origem, conta_origem, categoria_codigo)
    values ('7e000000-0000-4000-8000-00000000000a', 'titulo_pagar', '2.03.001', 'corretagem')$$,
  '42501', null, 'leitura não inclui mapeamento'
);
select throws_ok(
  $$insert into app.criterio_reconhecimento (tenant_id, metodo) values ('7e000000-0000-4000-8000-00000000000a', 'percentual_conclusao')$$,
  '42501', null, 'leitura não inclui critério'
);
select is_empty(
  $$update app.criterio_reconhecimento set metodo = 'nao_definido' returning id$$,
  'leitura não altera critério'
);
reset role;

-- Diretor do tenant A
select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000d00a", "role": "authenticated"}', true);
set local role authenticated;
select is((select count(distinct centro_custo_id) from marts.dre_mensal), 3::bigint, 'diretor vê T1, T2 e Despesas sem obra no DRE');
select results_eq(
  $$select valor_mes, quantidade_centros from marts.dre_mensal_consolidado where linha_codigo = 'sem_categoria' and competencia = '2026-02-01'$$,
  $$values (-1850.00::numeric(18,2), 3)$$,
  'consolidado do diretor inclui Despesas sem obra'
);
select results_eq(
  $$select grupo, custo_lancado from marts.custo_obra_resumo_consolidado order by grupo$$,
  $$values ('despesas_sem_obra', 850.00::numeric(18,2)), ('obras', 1000.00::numeric(18,2))$$,
  'custo consolidado do diretor com os dois grupos'
);
select is((select count(*) from app.criterio_reconhecimento), 1::bigint, 'diretor vê o critério da obra T2');
select is(
  (select count(*) from app.auditoria_alteracao where tabela in ('app.mapa_conta_origem', 'app.criterio_reconhecimento')),
  3::bigint, 'diretor vê o histórico do tenant'
);
select results_eq(
  $$select disponivel, motivo from marts.reconhecimento_obra_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a2' and competencia = '2026-02-01'$$,
  $$values (false, 'custo_sem_categoria')$$,
  'critério da obra T2 ligado, bloqueado pelo custo sem categoria'
);
select results_eq(
  $$select disponivel, motivo from marts.reconhecimento_obra_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' and competencia = '2026-02-01'$$,
  $$values (false, 'criterio_nao_validado')$$,
  'T1 sem critério próprio nem do tenant'
);
select is(
  (select count(*) from marts.carteira_recebiveis where tenant_id <> '7e000000-0000-4000-8000-00000000000a')
  + (select count(*) from marts.dre_mensal where tenant_id <> '7e000000-0000-4000-8000-00000000000a')
  + (select count(*) from app.mapa_conta_origem where tenant_id <> '7e000000-0000-4000-8000-00000000000a')
  + (select count(*) from app.criterio_reconhecimento where tenant_id <> '7e000000-0000-4000-8000-00000000000a'),
  0::bigint, 'diretor A não vê nada do tenant B'
);
select lives_ok(
  $$delete from app.mapa_conta_origem where tenant_id = '7e000000-0000-4000-8000-00000000000a' and conta_origem = '2.01.001'$$,
  'diretor exclui mapeamento'
);
select is(
  (select count(*) from app.auditoria_alteracao where tabela = 'app.mapa_conta_origem' and operacao = 'delete'
     and autor = '7a000000-0000-4000-8000-00000000d00a'),
  1::bigint, 'exclusão fica no histórico com o autor'
);
select throws_ok(
  $$delete from app.criterio_reconhecimento$$,
  '42501', null, 'critério não se exclui; volta a não definido por alteração'
);
reset role;

-- Diretor do tenant B
select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000d00b", "role": "authenticated"}', true);
set local role authenticated;
select is(
  (select count(*) from marts.carteira_recebiveis where tenant_id = '7e000000-0000-4000-8000-00000000000a')
  + (select count(*) from marts.resumo_receitas_obra where tenant_id = '7e000000-0000-4000-8000-00000000000a')
  + (select count(*) from marts.recebimento_mensal where tenant_id = '7e000000-0000-4000-8000-00000000000a')
  + (select count(*) from marts.custo_obra_categoria where tenant_id = '7e000000-0000-4000-8000-00000000000a')
  + (select count(*) from marts.custo_obra_resumo where tenant_id = '7e000000-0000-4000-8000-00000000000a')
  + (select count(*) from marts.despesa_mensal where tenant_id = '7e000000-0000-4000-8000-00000000000a')
  + (select count(*) from marts.pendencia_classificacao where tenant_id = '7e000000-0000-4000-8000-00000000000a')
  + (select count(*) from marts.reconhecimento_obra_mensal where tenant_id = '7e000000-0000-4000-8000-00000000000a')
  + (select count(*) from marts.dre_mensal where tenant_id = '7e000000-0000-4000-8000-00000000000a')
  + (select count(*) from marts.dre_mensal_consolidado where tenant_id = '7e000000-0000-4000-8000-00000000000a')
  + (select count(*) from marts.resumo_receitas_consolidado where tenant_id = '7e000000-0000-4000-8000-00000000000a')
  + (select count(*) from marts.recebimento_mensal_consolidado where tenant_id = '7e000000-0000-4000-8000-00000000000a')
  + (select count(*) from marts.custo_obra_resumo_consolidado where tenant_id = '7e000000-0000-4000-8000-00000000000a')
  + (select count(*) from app.mapa_conta_origem where tenant_id = '7e000000-0000-4000-8000-00000000000a')
  + (select count(*) from app.criterio_reconhecimento where tenant_id = '7e000000-0000-4000-8000-00000000000a')
  + (select count(*) from app.auditoria_alteracao where tenant_id = '7e000000-0000-4000-8000-00000000000a'),
  0::bigint,
  'tenant A invisível para o diretor B em toda view e tabela nova'
);
select results_eq(
  $$select linha_codigo, valor_periodo, motivo from marts.dre_periodo('2026-01-01', '2026-02-28')
    where linha_codigo in ('sem_categoria', 'receita_bruta') order by linha_ordem$$,
  $$values ('receita_bruta', null::numeric(18,2), 'orcamento_ausente'), ('sem_categoria', -100.00::numeric(18,2), null)$$,
  'diretor B vê só o próprio DRE; obra B1 sem orçamento deixa a receita indisponível'
);
select is((select count(*) from marts.dre_periodo('2026-01-01', '2026-02-28', '7c000000-0000-4000-8000-0000000000a1')),
  0::bigint, 'diretor B não lê o DRE de obra do tenant A pelo id');
select throws_ok(
  $$update app.criterio_reconhecimento set tenant_id = '7e000000-0000-4000-8000-00000000000a'$$,
  '42501', null, 'diretor B não move o próprio critério para outro tenant'
);
reset role;

-- Anônimo
select set_config('request.jwt.claims', '', true);
set local role anon;
select throws_ok('select count(*) from marts.dre_mensal', '42501', null, 'anônimo não lê o DRE');
select throws_ok('select count(*) from app.categoria_gerencial', '42501', null, 'anônimo não lê as categorias');
select throws_ok($$select * from marts.dre_periodo('2026-01-01', '2026-02-28')$$, '42501', null,
  'anônimo não executa a função de período');
select throws_ok('select count(*) from app.mapa_conta_origem', '42501', null, 'anônimo não lê o mapeamento');
reset role;

select * from finish();
rollback;
