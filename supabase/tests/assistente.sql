-- Execução do SQL do assistente e registro das perguntas: o RLS de quem pergunta continua valendo,
-- escrita falha, sem usuário ou sem assinatura falha, e o registro de uma pessoa não aparece para outra.
-- Cria os próprios dados para não depender do seed.
begin;
create extension if not exists pgtap with schema extensions;
select plan(25);

insert into app.tenant (id, razao_social) values
  ('0e000000-0000-4000-8000-0000000000d1', 'Construtora Assistente A'),
  ('0e000000-0000-4000-8000-0000000000d2', 'Construtora Assistente B');

insert into app.centro_custo (id, tenant_id, id_origem, nome) values
  ('0c000000-0000-4000-8000-0000000000d1', '0e000000-0000-4000-8000-0000000000d1', 961, 'Residencial Aurora'),
  ('0c000000-0000-4000-8000-0000000000d2', '0e000000-0000-4000-8000-0000000000d1', 962, 'Parque das Aguas'),
  ('0c000000-0000-4000-8000-0000000000d3', '0e000000-0000-4000-8000-0000000000d1', 963, 'Torre Comercial Sul'),
  ('0c000000-0000-4000-8000-0000000000d4', '0e000000-0000-4000-8000-0000000000d2', 961, 'Obra de outro tenant');

insert into auth.users (id, email) values
  ('0a000000-0000-4000-8000-00000000d101', 'diretor.assistente@teste.invalid'),
  ('0a000000-0000-4000-8000-00000000c101', 'gerente.assistente@teste.invalid');

insert into app.usuario_tenant (user_id, tenant_id, perfil) values
  ('0a000000-0000-4000-8000-00000000d101', '0e000000-0000-4000-8000-0000000000d1', 'diretor'),
  ('0a000000-0000-4000-8000-00000000c101', '0e000000-0000-4000-8000-0000000000d1', 'gerente_obra');

insert into app.usuario_centro_custo (user_id, tenant_id, centro_custo_id) values
  ('0a000000-0000-4000-8000-00000000c101', '0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1');

insert into staging.parcela_receber (tenant_id, centro_custo_id, id_origem, contrato_id_origem, vencimento, valor_original) values
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1', 1, 1, '2026-01-10', 1000),
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1', 2, 1, '2026-02-10', 1000),
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d2', 1, 2, '2026-01-10', 1000),
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d3', 1, 3, '2026-01-10', 1000),
  ('0e000000-0000-4000-8000-0000000000d2', '0c000000-0000-4000-8000-0000000000d4', 1, 4, '2026-01-10', 1000);

-- Chave só deste teste; a de produção é gravada por João e nunca entra no repositório.
delete from app.chave_assinatura_consulta;
insert into app.chave_assinatura_consulta (chave) values ('chave-local-do-teste-pgtap-0000000000');

create function pg_temp.assinar(p_sql text) returns text language sql as $$
  select encode(extensions.hmac(p_sql, 'chave-local-do-teste-pgtap-0000000000', 'sha256'), 'hex')
$$;
grant execute on function pg_temp.assinar(text) to authenticated;

-- Estrutura e permissões
select has_function('marts', 'executar_consulta', array['text', 'text'], 'executar_consulta existe');
select is(
  (select prosecdef from pg_proc where oid = 'marts.executar_consulta(text, text)'::regprocedure),
  false,
  'executar_consulta roda com o papel de quem chama'
);
select ok(
  not has_function_privilege('anon', 'marts.executar_consulta(text, text)', 'execute'),
  'anônimo não executa consulta'
);
select ok(
  (select setconfig @> array['statement_timeout=8s'] from pg_db_role_setting
   where setrole = 'authenticated'::regrole and setdatabase = 0),
  'papel authenticated tem statement_timeout de 8s'
);
select is(
  (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'app.pergunta_assistente'::regclass),
  true,
  'RLS ligado e forçado em pergunta_assistente'
);
select is(
  (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'app.chave_assinatura_consulta'::regclass),
  true,
  'RLS ligado e forçado em chave_assinatura_consulta'
);
select has_index('app', 'pergunta_assistente', 'pergunta_assistente_usuario_criado_idx', array['user_id', 'criado_em'],
  'índice do limite por usuário');
select has_index('app', 'pergunta_assistente', 'pergunta_assistente_tenant_criado_idx', array['tenant_id', 'criado_em'],
  'índice da leitura por tenant');

-- Sem usuário
set local role authenticated;
select throws_ok(
  format('select marts.executar_consulta(%L, %L)', 'select 1 as n', pg_temp.assinar('select 1 as n')),
  '42501',
  null,
  'sem usuário a consulta falha'
);

-- Gerente da Aurora: registro de perguntas antes das consultas, porque a consulta deixa a transação só de leitura
reset role;
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-00000000c101", "role": "authenticated"}', true);
set local role authenticated;

select lives_ok(
  $$insert into app.pergunta_assistente (id_requisicao, pergunta, sql_gerado, resultado)
    values ('00000000-0000-4000-8000-000000000001', 'Quanto a Aurora vai receber?', 'select 1', 'ok')$$,
  'gerente grava a própria pergunta com usuário e tenant preenchidos pelo banco'
);
select throws_ok(
  $$insert into app.pergunta_assistente (user_id, id_requisicao, pergunta, sql_gerado, resultado)
    values ('0a000000-0000-4000-8000-00000000d101', '00000000-0000-4000-8000-000000000002', 'x', 'select 1', 'ok')$$,
  '42501',
  null,
  'gerente não grava pergunta em nome de outro usuário'
);
select throws_ok(
  $$insert into app.pergunta_assistente (tenant_id, id_requisicao, pergunta, sql_gerado, resultado)
    values ('0e000000-0000-4000-8000-0000000000d2', '00000000-0000-4000-8000-000000000003', 'x', 'select 1', 'ok')$$,
  '42501',
  null,
  'gerente não grava pergunta em outro tenant'
);
select throws_ok(
  $$delete from app.pergunta_assistente$$,
  '42501',
  null,
  'registro de pergunta não pode ser apagado'
);
select throws_ok(
  $$update app.pergunta_assistente set pergunta = 'alterada'$$,
  '42501',
  null,
  'registro de pergunta não pode ser alterado'
);
select throws_ok(
  $$select chave from app.chave_assinatura_consulta$$,
  '42501',
  null,
  'usuário logado não lê a chave de assinatura'
);

-- Diretor do mesmo tenant grava e vê as perguntas do tenant
reset role;
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-00000000d101", "role": "authenticated"}', true);
set local role authenticated;
insert into app.pergunta_assistente (id_requisicao, pergunta, sql_gerado, resultado)
  values ('00000000-0000-4000-8000-000000000004', 'Qual a exposição máxima?', 'select 1', 'ok');
select is((select count(*) from app.pergunta_assistente), 2::bigint, 'diretor vê as perguntas do tenant');

reset role;
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-00000000c101", "role": "authenticated"}', true);
set local role authenticated;
select is((select count(*) from app.pergunta_assistente), 1::bigint, 'gerente vê só as próprias perguntas');

-- Consultas da gerente
select throws_ok(
  format('select marts.executar_consulta(%L, %L)', 'select 1 as n', 'assinatura-forjada'),
  '42501',
  null,
  'SQL sem assinatura válida não roda'
);
select throws_ok(
  format('select marts.executar_consulta(%L, %L)',
    'select set_config(''request.jwt.claims'', ''{}'', true)',
    pg_temp.assinar('select 1 as n')),
  '42501',
  null,
  'assinatura de outro SQL não serve'
);
select is(
  marts.executar_consulta(
    'select count(*) as total from staging.parcela_receber',
    pg_temp.assinar('select count(*) as total from staging.parcela_receber')),
  '[{"total": 2}]'::jsonb,
  'gerente conta só as parcelas da Aurora pelo executar_consulta'
);
select is(
  marts.executar_consulta(
    'select distinct c.nome from staging.parcela_receber p join app.centro_custo c on c.id = p.centro_custo_id',
    pg_temp.assinar('select distinct c.nome from staging.parcela_receber p join app.centro_custo c on c.id = p.centro_custo_id')),
  '[{"nome": "Residencial Aurora"}]'::jsonb,
  'gerente só enxerga a Aurora'
);
select is(
  marts.executar_consulta(
    'select 1 as n from staging.parcela_receber where false',
    pg_temp.assinar('select 1 as n from staging.parcela_receber where false')),
  '[]'::jsonb,
  'consulta sem linha devolve lista vazia'
);
select throws_ok(
  format('select marts.executar_consulta(%L, %L)',
    'insert into app.pergunta_assistente (id_requisicao, pergunta, sql_gerado, resultado) values (gen_random_uuid(), ''x'', ''x'', ''ok'') returning id',
    pg_temp.assinar('insert into app.pergunta_assistente (id_requisicao, pergunta, sql_gerado, resultado) values (gen_random_uuid(), ''x'', ''x'', ''ok'') returning id')),
  '42601',
  null,
  'insert pelo executar_consulta falha'
);
select throws_ok(
  format('select marts.executar_consulta(%L, %L)',
    'select 1 as n) l; set local request.jwt.claims = ''{"sub": "0a000000-0000-4000-8000-00000000d101"}''; select jsonb_agg(l) from (select * from staging.parcela_receber',
    pg_temp.assinar('select 1 as n) l; set local request.jwt.claims = ''{"sub": "0a000000-0000-4000-8000-00000000d101"}''; select jsonb_agg(l) from (select * from staging.parcela_receber')),
  '42P11',
  null,
  'segundo comando escondido no SQL, trocando os claims, não roda'
);
select is(current_setting('transaction_read_only'), 'on', 'consulta deixa a transação só de leitura');

select * from finish();
rollback;
