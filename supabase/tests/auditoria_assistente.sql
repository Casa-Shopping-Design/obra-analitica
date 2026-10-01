-- Trilha do assistente (migration 0025): quem chama concluir_pergunta direto não grava SQL que o servidor não
-- assinou, não marca como 'ok' pergunta que não rodou, e o sql_executado vem de executar_consulta.
-- A execução de verdade fica no fim, porque executar_consulta deixa a transação só de leitura.
begin;
create extension if not exists pgtap with schema extensions;
select plan(26);

insert into app.tenant (id, razao_social) values
  ('0e000000-0000-4000-8000-0000000025a1', 'Construtora Auditoria');

insert into app.centro_custo (id, tenant_id, id_origem, nome) values
  ('0c000000-0000-4000-8000-0000000025a1', '0e000000-0000-4000-8000-0000000025a1', 2501, 'Obra Auditada');

insert into auth.users (id, email) values
  ('0a000000-0000-4000-8000-0000000d25a1', 'diretor.auditoria@teste.invalid'),
  ('0a000000-0000-4000-8000-0000000c25a1', 'gerente.auditoria@teste.invalid');

insert into app.usuario_tenant (user_id, tenant_id, perfil) values
  ('0a000000-0000-4000-8000-0000000d25a1', '0e000000-0000-4000-8000-0000000025a1', 'diretor'),
  ('0a000000-0000-4000-8000-0000000c25a1', '0e000000-0000-4000-8000-0000000025a1', 'gerente_obra');

insert into app.usuario_centro_custo (user_id, tenant_id, centro_custo_id) values
  ('0a000000-0000-4000-8000-0000000c25a1', '0e000000-0000-4000-8000-0000000025a1', '0c000000-0000-4000-8000-0000000025a1');

insert into staging.parcela_receber (tenant_id, centro_custo_id, id_origem, contrato_id_origem, vencimento, valor_original) values
  ('0e000000-0000-4000-8000-0000000025a1', '0c000000-0000-4000-8000-0000000025a1', 1, 1, '2026-01-10', 1000);

-- Chave só deste teste; a de produção é gravada por João e nunca entra no repositório.
delete from app.chave_assinatura_consulta;
insert into app.chave_assinatura_consulta (chave) values ('chave-local-do-teste-auditoria-0000000');

create function pg_temp.assinar(p_texto text) returns text language sql as $$
  select encode(extensions.hmac(p_texto, 'chave-local-do-teste-auditoria-0000000', 'sha256'), 'hex')
$$;
create function pg_temp.assinar_gerado(p_id bigint, p_sql text) returns text language sql as $$
  select pg_temp.assinar(format('sql_gerado:%s:%s', p_id, p_sql))
$$;
grant execute on function pg_temp.assinar(text), pg_temp.assinar_gerado(bigint, text) to authenticated;

-- Estrutura e permissões
select hasnt_function('marts', 'executar_consulta', array['text', 'text'], 'executar_consulta sem id de pergunta saiu');
select has_function('marts', 'executar_consulta', array['bigint', 'text', 'text'], 'executar_consulta recebe o id da pergunta');
select is(
  (select count(*)::integer from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'concluir_pergunta'),
  1,
  'há uma concluir_pergunta só'
);
select ok(
  (select not ('p_sql_executado' = any (proargnames)) and 'p_assinatura_sql_gerado' = any (proargnames)
   from pg_proc where oid = 'app.concluir_pergunta(bigint, text, text, text, integer, integer, integer, integer, numeric)'::regprocedure),
  'concluir_pergunta não recebe mais o sql_executado e pede a assinatura do sql_gerado'
);
select ok(
  (select bool_and(prosecdef and proconfig @> array['search_path=""']) from pg_proc
   where oid in ('app.registrar_sql_executado(bigint, text, text)'::regprocedure,
                 'app.concluir_pergunta(bigint, text, text, text, integer, integer, integer, integer, numeric)'::regprocedure)),
  'registrar e concluir são security definer com search_path vazio'
);
select ok(
  not has_function_privilege('anon', 'app.registrar_sql_executado(bigint, text, text)', 'execute')
  and not has_function_privilege('public', 'app.registrar_sql_executado(bigint, text, text)', 'execute')
  and not has_function_privilege('anon', 'marts.executar_consulta(bigint, text, text)', 'execute')
  and not has_function_privilege('public', 'marts.executar_consulta(bigint, text, text)', 'execute'),
  'anônimo e public não executam nem gravam SQL'
);

-- Diretor reserva uma pergunta que a gerente vai tentar usar
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-0000000d25a1", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;
select set_config('teste.diretor',
  app.reservar_pergunta('00000000-0000-4000-8000-0000000025d1', 'Quanto falta receber?')::text, true);

reset role;
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-0000000c25a1", "role": "authenticated"}', true);
set local role authenticated;
select set_config('teste.p1', app.reservar_pergunta('00000000-0000-4000-8000-0000000025c1', 'Quanto a obra recebeu?')::text, true);
select set_config('teste.p2', app.reservar_pergunta('00000000-0000-4000-8000-0000000025c2', 'Quantas parcelas?')::text, true);
select set_config('teste.p3', app.reservar_pergunta('00000000-0000-4000-8000-0000000025c3', 'Qual o total a receber?')::text, true);

-- Gerente chama concluir_pergunta direto tentando gravar SQL falso
select throws_ok(
  format($$select app.concluir_pergunta(%s, 'select * from marts.posicao_financeira_obra', null, 'recusada', null, null, null, null, 0)$$,
    current_setting('teste.p1')),
  '42501',
  'sql_gerado sem assinatura válida',
  'sql_gerado sem assinatura não entra na trilha'
);
select throws_ok(
  format($$select app.concluir_pergunta(%1$s, 'select 1 as n', pg_temp.assinar_gerado(%2$s, 'select 1 as n'), 'recusada', null, null, null, null, 0)$$,
    current_setting('teste.p1'), current_setting('teste.p2')),
  '42501',
  'sql_gerado sem assinatura válida',
  'assinatura do sql_gerado de outra pergunta não serve'
);
select throws_ok(
  format($$select app.concluir_pergunta(%s, 'select 1 as n', pg_temp.assinar('select 1 as n'), 'recusada', null, null, null, null, 0)$$,
    current_setting('teste.p1')),
  '42501',
  'sql_gerado sem assinatura válida',
  'assinatura de execução não vale como assinatura do sql_gerado'
);
select throws_ok(
  format($$select app.concluir_pergunta(%s, null, null, 'ok', 3, 10, null, null, 0)$$, current_setting('teste.p1')),
  '42501',
  null,
  'pergunta que não rodou não fecha como ok'
);
select throws_ok(
  format($$select app.registrar_sql_executado(%s, 'select 2 as n', 'assinatura-forjada')$$, current_setting('teste.p1')),
  '42501',
  'consulta sem assinatura válida',
  'sql_executado sem assinatura não entra na trilha'
);
select throws_ok(
  format($$select marts.executar_consulta(%s, 'select 1 as n', pg_temp.assinar('select 1 as n'))$$, current_setting('teste.diretor')),
  '42501',
  'pergunta não está pendente para este usuário',
  'gerente não executa nem grava SQL na pergunta do diretor'
);

reset role;
select results_eq(
  format('select resultado, sql_gerado, sql_executado from app.pergunta_assistente where id = %s', current_setting('teste.p1')),
  $$values ('pendente'::text, null::text, null::text)$$,
  'tentativas não mexeram na reserva'
);
set local role authenticated;

-- Recusada: sql_gerado assinado entra, nada executado
select lives_ok(
  format($$select app.concluir_pergunta(%1$s, 'select payload from raw.registro', pg_temp.assinar_gerado(%1$s, 'select payload from raw.registro'), 'recusada', null, null, 100, 20, 0.01)$$,
    current_setting('teste.p1')),
  'recusada com sql_gerado assinado é concluída'
);
select throws_ok(
  format($$select app.concluir_pergunta(%s, '', null, 'erro', null, null, null, null, 0)$$, current_setting('teste.diretor')),
  '42501',
  null,
  'gerente não conclui a reserva do diretor'
);
reset role;
select results_eq(
  format('select resultado, sql_gerado, sql_executado from app.pergunta_assistente where id = %s', current_setting('teste.p1')),
  $$values ('recusada'::text, 'select payload from raw.registro'::text, null::text)$$,
  'trilha da recusada guarda o sql_gerado assinado e nenhum sql_executado'
);
set local role authenticated;

-- Execução pelo caminho do servidor: sql_executado gravado uma vez, depois concluída como ok
select lives_ok(
  format($$select app.registrar_sql_executado(%s, 'select 1 as n', pg_temp.assinar('select 1 as n'))$$, current_setting('teste.p3')),
  'SQL assinado é gravado na reserva da própria gerente'
);
select throws_ok(
  format($$select app.registrar_sql_executado(%s, 'select 1 as n', pg_temp.assinar('select 1 as n'))$$, current_setting('teste.p3')),
  '42501',
  null,
  'sql_executado é gravado uma vez só'
);
select throws_ok(
  format($$select app.concluir_pergunta(%s, null, null, 'recusada', null, null, null, null, 0)$$, current_setting('teste.p3')),
  '42501',
  null,
  'pergunta que rodou não fecha como recusada'
);
select lives_ok(
  format($$select app.concluir_pergunta(%1$s, 'select 1 as n', pg_temp.assinar_gerado(%1$s, 'select 1 as n'), 'ok', 1, 5, 100, 20, 0.01)$$,
    current_setting('teste.p3')),
  'pergunta executada fecha como ok'
);
reset role;
select results_eq(
  format('select resultado, sql_gerado, sql_executado from app.pergunta_assistente where id = %s', current_setting('teste.p3')),
  $$values ('ok'::text, 'select 1 as n'::text, 'select 1 as n'::text)$$,
  'trilha da ok guarda os dois SQL'
);

-- Diretor em aal1 não grava sql_executado nem na própria reserva
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-0000000d25a1", "role": "authenticated", "aal": "aal1"}', true);
set local role authenticated;
select throws_ok(
  format($$select marts.executar_consulta(%s, 'select 1 as n', pg_temp.assinar('select 1 as n'))$$, current_setting('teste.diretor')),
  '42501',
  'pergunta exige o segundo fator',
  'diretor em aal1 não executa consulta do assistente'
);

-- executar_consulta grava o próprio SQL; a transação fica só de leitura daqui em diante
reset role;
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-0000000c25a1", "role": "authenticated"}', true);
set local role authenticated;
select is(
  marts.executar_consulta(current_setting('teste.p2')::bigint,
    'select count(*) as total from staging.parcela_receber',
    pg_temp.assinar('select count(*) as total from staging.parcela_receber')),
  '[{"total": 1}]'::jsonb,
  'gerente executa a consulta assinada da própria pergunta'
);
reset role;
select is(
  (select sql_executado from app.pergunta_assistente where id = current_setting('teste.p2')::bigint),
  'select count(*) as total from staging.parcela_receber',
  'executar_consulta gravou o SQL que rodou'
);
select is(
  (select resultado from app.pergunta_assistente where id = current_setting('teste.p2')::bigint),
  'pendente',
  'a reserva segue pendente até a conclusão'
);
select is(current_setting('transaction_read_only'), 'on', 'consulta deixa a transação só de leitura');

select * from finish();
rollback;
