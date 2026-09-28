-- Marca e modo de carga ficam fechados para o painel e a marca guarda uma linha por endpoint.
-- Também confere a troca de versão em raw pela chave de origem, com o mesmo delete do carregador.
begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

insert into app.tenant (id, razao_social) values
  ('0e000000-0000-4000-8000-0000000000d1', 'Construtora Marca');

select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'app.marca_carga'::regclass),
  'marca_carga com RLS ligado e forçado'
);
select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'app.modo_carga'::regclass),
  'modo_carga com RLS ligado e forçado'
);
select is(
  (select count(*)::int from pg_policies where schemaname = 'app' and tablename in ('marca_carga', 'modo_carga')),
  0,
  'nenhuma política: só o dono do banco usa as duas tabelas'
);
select ok(
  not has_table_privilege('authenticated', 'app.marca_carga', 'select')
  and not has_table_privilege('anon', 'app.marca_carga', 'select')
  and not has_table_privilege('authenticated', 'app.modo_carga', 'select')
  and not has_table_privilege('anon', 'app.modo_carga', 'select'),
  'authenticated e anon sem privilégio de leitura'
);

insert into app.marca_carga (tenant_id, endpoint, ultima_referencia)
values ('0e000000-0000-4000-8000-0000000000d1', 'income', '2026-09-20');
insert into app.marca_carga (tenant_id, endpoint, ultima_referencia)
values ('0e000000-0000-4000-8000-0000000000d1', 'income', '2026-09-28')
on conflict (tenant_id, endpoint) do update
  set ultima_referencia = excluded.ultima_referencia, atualizado_em = now();

select is(
  (select row(count(*), max(ultima_referencia))::text from app.marca_carga
   where tenant_id = '0e000000-0000-4000-8000-0000000000d1'),
  '(1,2026-09-28)',
  'segunda carga do mesmo endpoint avança a marca sem criar outra linha'
);

select throws_ok(
  $$insert into app.marca_carga (tenant_id, endpoint, ultima_referencia)
    values ('0e000000-0000-4000-8000-0000000000d1', 'outcome', null)$$,
  '23502',
  null,
  'marca sem data de referência é recusada'
);

set local role authenticated;
select throws_ok('select * from app.marca_carga', '42501', null, 'usuário logado recebe permissão negada');
reset role;

-- Caso conhecido da troca de versão: a parcela 7|1 mudou de saldo, a 7|2 não mudou e a 8|1 não veio.
insert into raw.registro (tenant_id, endpoint, payload, hash_registro, chave_origem) values
  ('0e000000-0000-4000-8000-0000000000d1', 'income', '{"billId":7,"installmentId":1,"balanceAmount":100}', 'h71a', '7|1'),
  ('0e000000-0000-4000-8000-0000000000d1', 'income', '{"billId":7,"installmentId":2,"balanceAmount":100}', 'h72', '7|2'),
  ('0e000000-0000-4000-8000-0000000000d1', 'income', '{"billId":8,"installmentId":1,"balanceAmount":50}', 'h81', '8|1'),
  ('0e000000-0000-4000-8000-0000000000d1', 'income', '{"billId":7,"installmentId":1,"balanceAmount":0}', 'h71b', '7|1');

create temp table carga_atual (endpoint text, chave text, hash text);
insert into carga_atual values ('income', '7|1', 'h71b'), ('income', '7|2', 'h72');

delete from raw.registro r
where r.tenant_id = '0e000000-0000-4000-8000-0000000000d1'
  and r.endpoint = 'income'
  and r.chave_origem in (select chave from carga_atual where endpoint = 'income')
  and not exists (
    select 1 from carga_atual c
    where c.endpoint = r.endpoint and c.chave = r.chave_origem and c.hash = r.hash_registro
  );

select is(
  (select string_agg(hash_registro, ',' order by hash_registro) from raw.registro
   where tenant_id = '0e000000-0000-4000-8000-0000000000d1'),
  'h71b,h72,h81',
  'versão antiga da parcela sai, a repetida fica e a que não veio na carga não é tocada'
);

select has_index('raw', 'registro', 'registro_chave_origem_idx', 'índice da chave de origem existe');

select is(
  (select count(*)::int from raw.registro
   where tenant_id = '0e000000-0000-4000-8000-0000000000d1' and chave_origem = '7|1'),
  1,
  'uma linha por chave depois da troca'
);

select * from finish();
rollback;
