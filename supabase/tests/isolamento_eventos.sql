-- Caso C12 de docs/financeiro/casos_teste.md na parte da migration 0007: gerente não vê outra obra nem
-- Despesas sem obra, outro tenant fica invisível, cabeçalho do título não é legível e a auditoria só
-- aparece para diretor e financeiro.
begin;
create extension if not exists pgtap with schema extensions;
select plan(27);

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
  ('7a000000-0000-4000-8000-00000000d00b', 'diretorb.financeiro@teste.invalid');

insert into app.usuario_tenant (user_id, tenant_id, perfil) values
  ('7a000000-0000-4000-8000-00000000d00a', '7e000000-0000-4000-8000-00000000000a', 'diretor'),
  ('7a000000-0000-4000-8000-00000000f00a', '7e000000-0000-4000-8000-00000000000a', 'financeiro'),
  ('7a000000-0000-4000-8000-00000000c00a', '7e000000-0000-4000-8000-00000000000a', 'gerente_obra'),
  ('7a000000-0000-4000-8000-00000000d00b', '7e000000-0000-4000-8000-00000000000b', 'diretor');

insert into app.usuario_centro_custo (user_id, tenant_id, centro_custo_id) values
  ('7a000000-0000-4000-8000-00000000c00a', '7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1');

-- Payloads do C08 no tenant A e um título do tenant B, gravados pelo dono do banco como o carregador.
insert into raw.registro (tenant_id, endpoint, payload, hash_registro)
select '7e000000-0000-4000-8000-00000000000a', 'outcome', x, md5(x::text)
from jsonb_array_elements('[
  {"billId": 7801, "dueDate": "2026-03-20", "issueDate": "2026-02-01", "originalAmount": 1000.00, "balanceAmount": 899.95,
   "buildingsCosts": [{"buildingId": 9001, "amount": 500.00}, {"buildingId": 9002, "amount": 500.00}],
   "payments": [{"paymentDate": "2026-02-10", "amount": 100.05}]},
  {"billId": 7802, "dueDate": "2026-02-15", "issueDate": "2026-02-05", "originalAmount": 800.00, "balanceAmount": 0,
   "payments": [{"paymentDate": "2026-02-15", "amount": 800.00}]},
  {"billId": 7803, "dueDate": "2026-03-05", "issueDate": "2026-02-10", "originalAmount": 50.00, "balanceAmount": 50.00,
   "buildingsCosts": [{"buildingId": 9999, "amount": 50.00}], "payments": []}]'::jsonb) x;
insert into raw.registro (tenant_id, endpoint, payload, hash_registro)
select '7e000000-0000-4000-8000-00000000000a', 'income', x, md5(x::text)
from jsonb_array_elements('[
  {"projectId": 9001, "billId": 5101, "installmentId": 1, "dueDate": "2026-01-10", "originalAmount": 1000.00,
   "balanceAmount": 0, "correctedBalanceAmount": 0, "paymentTerm": {"id": "PM"},
   "receipts": [{"paymentDate": "2026-02-05", "amount": 1000.00}]},
  {"projectId": 9002, "billId": 5201, "installmentId": 1, "dueDate": "2026-01-10", "originalAmount": 500.00,
   "balanceAmount": 0, "correctedBalanceAmount": 0, "paymentTerm": {"id": "PM"},
   "receipts": [{"paymentDate": "2026-02-05", "amount": 500.00}]}]'::jsonb) x;
insert into raw.registro (tenant_id, endpoint, payload, hash_registro)
values ('7e000000-0000-4000-8000-00000000000b', 'outcome',
  '{"billId": 7999, "dueDate": "2026-02-10", "originalAmount": 100.00, "balanceAmount": 0,
    "buildingsCosts": [{"buildingId": 9001, "amount": 100.00}], "payments": [{"paymentDate": "2026-02-10", "amount": 100.00}]}',
  'c12-tenant-b');

select staging.recarregar('7e000000-0000-4000-8000-00000000000a');
select staging.recarregar('7e000000-0000-4000-8000-00000000000b');
select set_config('app.data_referencia', '2026-02-28', true);

-- Tabela de apoio só deste teste, para provar os gatilhos comuns de autor e auditoria.
create table app.teste_mapa (
  tenant_id uuid not null,
  codigo text not null,
  autor uuid,
  atualizado_em timestamptz,
  primary key (tenant_id, codigo)
);
alter table app.teste_mapa enable row level security;
alter table app.teste_mapa force row level security;
create policy escrita_diretor_financeiro on app.teste_mapa for insert to authenticated
  with check (tenant_id = (select app.tenant_atual()) and (select app.perfil_atual()) in ('diretor', 'financeiro'));
grant insert on app.teste_mapa to authenticated;
create trigger definir_autor before insert or update on app.teste_mapa
  for each row execute function app.definir_autor();
create trigger registrar_auditoria after insert or update or delete on app.teste_mapa
  for each row execute function app.registrar_auditoria('tenant_id', 'codigo');

-- Gerente da obra T1
select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000c00a", "role": "authenticated"}', true);
set local role authenticated;

select results_eq(
  'select distinct centro_custo_id from marts.fluxo_caixa_mensal',
  $$values ('7c000000-0000-4000-8000-0000000000a1'::uuid)$$,
  'gerente vê fluxo só da obra vinculada'
);
select is((select count(*) from staging.pagamento), 1::bigint, 'gerente vê um pagamento, a parte de T1');
select is((select count(*) from app.centro_custo), 1::bigint, 'gerente vê um centro de custo');
select is((select count(*) from staging.titulo_pagar_apropriacao where centro_custo_id <> '7c000000-0000-4000-8000-0000000000a1'),
  0::bigint, 'gerente não vê apropriação de outra obra nem da empresa');
select is((select count(*) from staging.recebimento), 1::bigint, 'gerente vê só o recebimento de T1');
select is((select count(*) from marts.posicao_financeira_obra), 1::bigint, 'gerente vê a posição de uma obra');
select is((select count(*) from app.auditoria_alteracao), 0::bigint, 'gerente não vê auditoria');
select throws_ok(
  $$insert into app.teste_mapa (tenant_id, codigo) values ('7e000000-0000-4000-8000-00000000000a', 'g')$$,
  '42501', null, 'gerente não grava onde só diretor e financeiro gravam'
);
select throws_ok('select staging.recarregar(''7e000000-0000-4000-8000-00000000000a'')', '42501', null,
  'usuário logado não executa a recarga');
select ok((select ultima_carga_em is not null and not desatualizada from app.situacao_carga()),
  'carimbo da carga do próprio tenant');

-- Financeiro grava com autor falso; o gatilho troca pelo do JWT e registra a auditoria
reset role;
select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000f00a", "role": "authenticated"}', true);
set local role authenticated;
select lives_ok(
  $$insert into app.teste_mapa (tenant_id, codigo, autor)
    values ('7e000000-0000-4000-8000-00000000000a', '2.01.001', '7a000000-0000-4000-8000-00000000d00a')$$,
  'financeiro grava'
);
reset role;
select is((select autor from app.teste_mapa where codigo = '2.01.001'), '7a000000-0000-4000-8000-00000000f00a'::uuid,
  'autor gravado é o do JWT, não o mandado');
select ok((select atualizado_em is not null from app.teste_mapa where codigo = '2.01.001'), 'atualizado_em preenchido');
select results_eq(
  $$select tabela, registro_id, operacao, autor from app.auditoria_alteracao
    where tenant_id = '7e000000-0000-4000-8000-00000000000a'$$,
  $$values ('app.teste_mapa', '7e000000-0000-4000-8000-00000000000a|2.01.001', 'insert',
            '7a000000-0000-4000-8000-00000000f00a'::uuid)$$,
  'auditoria com a chave composta e o autor'
);

-- Diretor do tenant A
select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000d00a", "role": "authenticated"}', true);
set local role authenticated;

select throws_ok('select * from staging.titulo_pagar', '42501', null, 'cabeçalho do título não é legível pelo usuário');
select is((select count(*) from app.centro_custo), 3::bigint, 'diretor vê T1, T2 e Despesas sem obra');
select is((select count(*) from marts.posicao_financeira_obra), 2::bigint, 'posição do diretor só com as obras');
select is((select count(distinct centro_custo_id) from marts.fluxo_caixa_mensal), 3::bigint,
  'fluxo do diretor inclui Despesas sem obra');
select is((select count(*) from marts.fluxo_caixa_mensal where tenant_id <> '7e000000-0000-4000-8000-00000000000a'),
  0::bigint, 'diretor não vê fluxo de outro tenant');
select is((select count(*) from staging.pagamento where tenant_id <> '7e000000-0000-4000-8000-00000000000a'),
  0::bigint, 'diretor não vê pagamento de outro tenant');
select is((select count(*) from app.auditoria_alteracao), 1::bigint, 'diretor vê a auditoria do tenant');
select throws_ok(
  $$insert into staging.pagamento (tenant_id, centro_custo_id, titulo_id_origem, sequencia_pagamento, sequencia_obra,
    sequencia_conta, data_pagamento, valor)
    values ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1', 1, 1, 1, 1, '2026-01-01', 1)$$,
  '42501', null, 'usuário não escreve no staging'
);
select throws_ok(
  $$insert into app.auditoria_alteracao (tenant_id, tabela, registro_id, operacao)
    values ('7e000000-0000-4000-8000-00000000000a', 'x', 'x', 'insert')$$,
  '42501', null, 'usuário não escreve na auditoria'
);

-- Diretor do tenant B
reset role;
select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000d00b", "role": "authenticated"}', true);
set local role authenticated;

select is((select count(*) from staging.pagamento), 1::bigint, 'diretor B vê só o pagamento do tenant B');
select is(
  (select count(*) from marts.fluxo_caixa_mensal where tenant_id = '7e000000-0000-4000-8000-00000000000a')
  + (select count(*) from staging.titulo_pagar_apropriacao where tenant_id = '7e000000-0000-4000-8000-00000000000a')
  + (select count(*) from staging.recebimento where tenant_id = '7e000000-0000-4000-8000-00000000000a')
  + (select count(*) from marts.posicao_financeira_obra where tenant_id = '7e000000-0000-4000-8000-00000000000a'),
  0::bigint,
  'tenant A invisível para o diretor B'
);
select is((select count(*) from app.auditoria_alteracao), 0::bigint, 'diretor B não vê auditoria do tenant A');

-- Anônimo
reset role;
select set_config('request.jwt.claims', '', true);
set local role anon;
select throws_ok('select count(*) from marts.fluxo_caixa_mensal', '42501', null, 'anônimo não lê o fluxo');

select * from finish();
rollback;
