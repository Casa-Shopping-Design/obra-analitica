-- Execução do SQL do assistente e registro das perguntas: o RLS de quem pergunta continua valendo,
-- escrita direta falha, a reserva conta o limite por hora e o teto diário, o SQL gravado sai só para
-- o diretor e uma consulta que troca os claims no meio não devolve linha. Cria os próprios dados.
-- As reservas e conclusões vêm antes das execuções, porque executar_consulta deixa a transação só de leitura.
begin;
create extension if not exists pgtap with schema extensions;
select plan(44);

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
  not has_function_privilege('anon', 'app.reservar_pergunta(uuid, text)', 'execute')
  and not has_function_privilege('anon', 'app.sql_das_perguntas(bigint[])', 'execute'),
  'anônimo não reserva pergunta nem lê SQL gravado'
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
select is(
  (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'app.parametro_assistente'::regclass),
  true,
  'RLS ligado e forçado em parametro_assistente'
);
select ok(
  not has_table_privilege('authenticated', 'app.parametro_assistente', 'select'),
  'usuário logado não lê os parâmetros do assistente'
);
select ok(
  not has_table_privilege('authenticated', 'app.pergunta_assistente', 'insert')
  and not has_column_privilege('authenticated', 'app.pergunta_assistente', 'sql_executado', 'select')
  and not has_column_privilege('authenticated', 'app.pergunta_assistente', 'sql_gerado', 'select'),
  'usuário logado não insere nem lê as colunas de SQL pela tabela'
);
select has_index('app', 'pergunta_assistente', 'pergunta_assistente_usuario_criado_idx', array['user_id', 'criado_em'],
  'índice do limite por usuário');
select has_index('app', 'pergunta_assistente', 'pergunta_assistente_tenant_criado_idx', array['tenant_id', 'criado_em'],
  'índice do teto por tenant');

-- Sem usuário
set local role authenticated;
select throws_ok(
  format('select marts.executar_consulta(%L, %L)', 'select 1 as n', pg_temp.assinar('select 1 as n')),
  '42501',
  null,
  'sem usuário a consulta falha'
);
select throws_ok(
  $$select app.reservar_pergunta('00000000-0000-4000-8000-000000000000', 'x')$$,
  '42501',
  null,
  'sem usuário a reserva falha'
);

-- Gerente da Aurora: reserva, escrita direta e leitura do próprio registro
reset role;
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-00000000c101", "role": "authenticated"}', true);
set local role authenticated;

select lives_ok(
  $$select set_config('teste.pergunta_gerente',
    app.reservar_pergunta('00000000-0000-4000-8000-000000000001', 'Quanto a Aurora vai receber?')::text, true)$$,
  'gerente reserva a própria pergunta com usuário e tenant preenchidos pelo banco'
);
select throws_ok(
  $$insert into app.pergunta_assistente (user_id, tenant_id, id_requisicao, pergunta, resultado)
    values ('0a000000-0000-4000-8000-00000000c101', '0e000000-0000-4000-8000-0000000000d1',
            '00000000-0000-4000-8000-000000000002', 'x', 'ok')$$,
  '42501',
  null,
  'gerente não grava pergunta direto na tabela'
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
  'registro de pergunta não pode ser alterado direto'
);
select throws_ok(
  $$select sql_executado from app.pergunta_assistente$$,
  '42501',
  null,
  'gerente não lê sql_executado pela tabela'
);
select throws_ok(
  $$select * from app.pergunta_assistente$$,
  '42501',
  null,
  'select * na tabela falha para quem está logado'
);
select is(
  (select resultado from app.pergunta_assistente where id = current_setting('teste.pergunta_gerente')::bigint),
  'pendente',
  'reserva nasce pendente e é legível pelo próprio usuário'
);
select lives_ok(
  format($$select app.concluir_pergunta(%s, 'select 1 as n', 'select 1 as n', 'ok', 1, 12, 100, 20, 0.001)$$,
    current_setting('teste.pergunta_gerente')),
  'gerente conclui a própria reserva'
);
select is(
  (select resultado from app.pergunta_assistente where id = current_setting('teste.pergunta_gerente')::bigint),
  'ok',
  'conclusão grava o resultado'
);
select throws_ok(
  format($$select app.concluir_pergunta(%s, 'x', null, 'erro', null, null, null, null, null)$$,
    current_setting('teste.pergunta_gerente')),
  '42501',
  null,
  'reserva já concluída não é fechada de novo'
);
select is_empty(
  format('select * from app.sql_da_pergunta(%s)', current_setting('teste.pergunta_gerente')),
  'gerente não lê o SQL da própria pergunta pela função'
);
select throws_ok(
  $$select chave from app.chave_assinatura_consulta$$,
  '42501',
  null,
  'usuário logado não lê a chave de assinatura'
);

-- Diretor do mesmo tenant vê as perguntas do tenant e o SQL; não fecha reserva alheia
reset role;
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-00000000d101", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;
select throws_ok(
  format($$select app.concluir_pergunta(%s, 'x', null, 'erro', null, null, null, null, null)$$,
    current_setting('teste.pergunta_gerente')),
  '42501',
  null,
  'diretor não conclui reserva de outro usuário'
);
select set_config('teste.pergunta_diretor',
  app.reservar_pergunta('00000000-0000-4000-8000-000000000004', 'Qual a exposição máxima?')::text, true);
select is((select count(*) from app.pergunta_assistente), 2::bigint, 'diretor vê as perguntas do tenant');
select results_eq(
  format('select sql_executado from app.sql_da_pergunta(%s)', current_setting('teste.pergunta_gerente')),
  $$values ('select 1 as n')$$,
  'diretor lê o SQL executado de pergunta do tenant'
);
select is(
  (select count(*) from app.sql_das_perguntas(array[
    current_setting('teste.pergunta_gerente')::bigint, current_setting('teste.pergunta_diretor')::bigint])),
  2::bigint,
  'diretor lê o SQL de várias perguntas numa chamada'
);

-- Limite por hora: o diretor já tem uma reserva; mais 29 passam, a 31ª é recusada
select lives_ok(
  $$select app.reservar_pergunta(gen_random_uuid(), 'pergunta repetida') from generate_series(1, 29)$$,
  'diretor faz 30 perguntas na hora'
);
select throws_ok(
  $$select app.reservar_pergunta(gen_random_uuid(), 'a trigésima primeira')$$,
  'P0001',
  'limite',
  '31ª pergunta na hora é recusada com a mensagem limite'
);

-- Teto diário do tenant: as 30 perguntas do diretor custaram US$ 6, acima dos US$ 5 do parâmetro
reset role;
update app.pergunta_assistente set custo_estimado = 0.2 where user_id = '0a000000-0000-4000-8000-00000000d101';
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-00000000c101", "role": "authenticated"}', true);
set local role authenticated;
select throws_ok(
  $$select app.reservar_pergunta(gen_random_uuid(), 'mais uma')$$,
  'P0001',
  'teto',
  'tenant que passou do teto diário é recusado com a mensagem teto'
);

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
    'insert into app.pergunta_assistente (user_id, tenant_id, id_requisicao, pergunta, resultado) values (auth.uid(), app.tenant_atual(), gen_random_uuid(), ''x'', ''ok'') returning id',
    pg_temp.assinar('insert into app.pergunta_assistente (user_id, tenant_id, id_requisicao, pergunta, resultado) values (auth.uid(), app.tenant_atual(), gen_random_uuid(), ''x'', ''ok'') returning id')),
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
-- set_config é função, passa pelo cursor e pela transação só de leitura: a função confere os claims depois do fetch.
select throws_ok(
  format('select marts.executar_consulta(%L, %L)',
    'select count(*) as total from staging.parcela_receber where (select set_config(''request.jwt.claims'', ''{"sub": "0a000000-0000-4000-8000-00000000d101", "role": "authenticated", "aal": "aal2"}'', true)) is not null',
    pg_temp.assinar('select count(*) as total from staging.parcela_receber where (select set_config(''request.jwt.claims'', ''{"sub": "0a000000-0000-4000-8000-00000000d101", "role": "authenticated", "aal": "aal2"}'', true)) is not null')),
  '42501',
  null,
  'select assinado que troca os claims por set_config não devolve linha'
);
select is(
  current_setting('request.jwt.claims', true),
  '{"sub": "0a000000-0000-4000-8000-00000000c101", "role": "authenticated"}',
  'claims voltam ao valor da gerente depois da tentativa'
);
-- O statement_timeout da transação (o PostgREST põe o do papel antes de chamar) corta o fetch do cursor com
-- 57014, conferido à mão com pg_sleep; não há caso pgTAP porque query_canceled não é capturado por throws_ok.
select is(current_setting('transaction_read_only'), 'on', 'consulta deixa a transação só de leitura');

select * from finish();
rollback;
