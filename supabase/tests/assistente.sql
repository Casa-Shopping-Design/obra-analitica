-- Prova que a consulta do assistente respeita o RLS de quem pergunta, roda só com assinatura válida,
-- fica somente leitura e para em 500 linhas, e que a auditoria é imutável e separada por usuário e tenant.
-- A auditoria vem antes das execuções porque executar_consulta deixa o resto da transação somente leitura.
begin;
create extension if not exists pgtap with schema extensions;
select plan(28);

insert into app.tenant (id, razao_social) values
  ('0e000000-0000-4000-8000-0000000000c7', 'Construtora Assistente A'),
  ('0e000000-0000-4000-8000-0000000000d7', 'Construtora Assistente B');

insert into app.centro_custo (id, tenant_id, id_origem, nome) values
  ('0c000000-0000-4000-8000-0000000007a1', '0e000000-0000-4000-8000-0000000000c7', 971, 'Obra Assistente A1'),
  ('0c000000-0000-4000-8000-0000000007a2', '0e000000-0000-4000-8000-0000000000c7', 972, 'Obra Assistente A2'),
  ('0c000000-0000-4000-8000-0000000007b1', '0e000000-0000-4000-8000-0000000000d7', 971, 'Obra Assistente B1');

insert into auth.users (id, email) values
  ('0a000000-0000-4000-8000-0000000007d1', 'diretor.assistente@teste.invalid'),
  ('0a000000-0000-4000-8000-0000000007c1', 'gerente.assistente@teste.invalid'),
  ('0a000000-0000-4000-8000-0000000007e1', 'diretor.outro@teste.invalid');

insert into app.usuario_tenant (user_id, tenant_id, perfil) values
  ('0a000000-0000-4000-8000-0000000007d1', '0e000000-0000-4000-8000-0000000000c7', 'diretor'),
  ('0a000000-0000-4000-8000-0000000007c1', '0e000000-0000-4000-8000-0000000000c7', 'gerente_obra'),
  ('0a000000-0000-4000-8000-0000000007e1', '0e000000-0000-4000-8000-0000000000d7', 'diretor');

insert into app.usuario_centro_custo (user_id, tenant_id, centro_custo_id) values
  ('0a000000-0000-4000-8000-0000000007c1', '0e000000-0000-4000-8000-0000000000c7', '0c000000-0000-4000-8000-0000000007a1');

insert into staging.parcela_receber (tenant_id, centro_custo_id, id_origem, contrato_id_origem, vencimento, valor_original) values
  ('0e000000-0000-4000-8000-0000000000c7', '0c000000-0000-4000-8000-0000000007a1', 1, 1, '2026-01-10', 1000),
  ('0e000000-0000-4000-8000-0000000000c7', '0c000000-0000-4000-8000-0000000007a2', 1, 2, '2026-01-10', 1000),
  ('0e000000-0000-4000-8000-0000000000d7', '0c000000-0000-4000-8000-0000000007b1', 1, 3, '2026-01-10', 1000);

-- Usa a chave que já existir no projeto local; cria uma só para o teste quando não houver.
select vault.create_secret('chave-local-do-teste-do-assistente', 'assistente_chave_assinatura')
where not exists (select 1 from vault.secrets where name = 'assistente_chave_assinatura');

create temporary table consulta_assinada (nome text primary key, sql text not null, assinatura text not null);
insert into consulta_assinada (nome, sql, assinatura)
select c.nome, c.sql, encode(extensions.hmac(c.sql, s.decrypted_secret, 'sha256'), 'hex')
from (values
  ('contagem', 'select count(*) as total from staging.parcela_receber'),
  ('somente_leitura', 'select current_setting(''transaction_read_only'') as somente_leitura'),
  ('seiscentas', 'select g from generate_series(1, 600) g'),
  ('insercao', 'insert into app.tenant (razao_social) values (''invasora'')')
) as c(nome, sql)
cross join vault.decrypted_secrets s
where s.name = 'assistente_chave_assinatura';
grant select on consulta_assinada to authenticated, anon;

-- Estrutura e permissões
select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'app.pergunta_assistente'::regclass),
  'auditoria nasce com RLS ligado e forçado'
);
select is(
  (select array_agg(cmd::text order by cmd) from pg_policies where schemaname = 'app' and tablename = 'pergunta_assistente'),
  array['INSERT', 'SELECT'],
  'uma política por ação, só insert e select'
);
select is(
  (select count(*) from pg_policies
   where schemaname = 'app' and tablename = 'pergunta_assistente'
     and (coalesce(qual, '') = 'true' or coalesce(with_check, '') = 'true')),
  0::bigint,
  'nenhuma política com using (true)'
);
select ok(
  exists (
    select 1 from pg_db_role_setting s join pg_roles r on r.oid = s.setrole
    where r.rolname = 'authenticated' and 'statement_timeout=8s' = any(s.setconfig)
  ),
  'papel authenticated com statement_timeout de 8 segundos'
);
select ok(not has_function_privilege('anon', 'marts.executar_consulta(text, text)', 'execute'), 'anônimo não executa consulta');
select ok(has_function_privilege('authenticated', 'marts.executar_consulta(text, text)', 'execute'), 'usuário logado executa consulta');
select ok(not has_function_privilege('anon', 'app.assinatura_consulta_valida(text, text)', 'execute'), 'anônimo não confere assinatura');
select ok(
  (select prosecdef and proconfig @> array['search_path=""'] from pg_proc where oid = 'app.assinatura_consulta_valida(text, text)'::regprocedure),
  'conferência de assinatura é security definer com search_path vazio'
);
select ok(
  (select not prosecdef from pg_proc where oid = 'marts.executar_consulta(text, text)'::regprocedure),
  'execução roda como quem chama'
);

-- Auditoria com a gerente da obra A1
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-0000000007c1", "role": "authenticated"}', true);
set local role authenticated;

select lives_ok(
  $$insert into app.pergunta_assistente (id_requisicao, pergunta, situacao, linhas, duracao_ms)
    values ('0f000000-0000-4000-8000-000000000001', 'Quanto a obra já recebeu?', 'executada', 1, 12)$$,
  'gerente registra a própria pergunta'
);
select is(
  (select user_id::text || '/' || tenant_id::text from app.pergunta_assistente),
  '0a000000-0000-4000-8000-0000000007c1/0e000000-0000-4000-8000-0000000000c7',
  'usuário e tenant vêm do JWT, não do que o painel manda'
);
select throws_ok(
  $$insert into app.pergunta_assistente (user_id, pergunta, situacao) values ('0a000000-0000-4000-8000-0000000007d1', 'forjada', 'executada')$$,
  '42501', null,
  'gerente não grava pergunta em nome de outro usuário'
);
select throws_ok(
  $$insert into app.pergunta_assistente (pergunta, situacao, criado_em) values ('antiga', 'executada', now() - interval '2 hours')$$,
  '42501', null,
  'gerente não escolhe a data do registro para fugir do limite por hora'
);
select throws_ok($$update app.pergunta_assistente set pergunta = 'alterada'$$, '42501', null, 'registro não pode ser alterado');
select throws_ok($$delete from app.pergunta_assistente$$, '42501', null, 'registro não pode ser apagado');

-- Diretor do mesmo tenant
reset role;
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-0000000007d1", "role": "authenticated"}', true);
set local role authenticated;
insert into app.pergunta_assistente (pergunta, situacao) values ('Qual obra estourou o orçamento?', 'recusada');
select is((select count(*) from app.pergunta_assistente), 2::bigint, 'diretor vê as perguntas do próprio tenant');

-- Diretor de outro tenant
reset role;
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-0000000007e1", "role": "authenticated"}', true);
set local role authenticated;
select is((select count(*) from app.pergunta_assistente), 0::bigint, 'diretor não vê pergunta de outro tenant');

-- Volta para a gerente, que não vê a pergunta do diretor
reset role;
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-0000000007c1", "role": "authenticated"}', true);
set local role authenticated;
select is((select count(*) from app.pergunta_assistente), 1::bigint, 'gerente vê só a própria pergunta');

-- Execução com a gerente
select is(
  marts.executar_consulta(
    (select sql from consulta_assinada where nome = 'contagem'),
    (select assinatura from consulta_assinada where nome = 'contagem')
  ),
  '[{"total": 1}]'::jsonb,
  'consulta da gerente respeita o RLS e conta só a obra dela'
);
select is(
  marts.executar_consulta(
    (select sql from consulta_assinada where nome = 'somente_leitura'),
    (select assinatura from consulta_assinada where nome = 'somente_leitura')
  ),
  '[{"somente_leitura": "on"}]'::jsonb,
  'consulta roda em transação somente leitura'
);
select is(
  jsonb_array_length(marts.executar_consulta(
    (select sql from consulta_assinada where nome = 'seiscentas'),
    (select assinatura from consulta_assinada where nome = 'seiscentas')
  )),
  500,
  'consulta para em 500 linhas mesmo quando o SQL pede mais'
);
select throws_ok(
  format('select marts.executar_consulta(%L, %L)',
    (select sql from consulta_assinada where nome = 'insercao'),
    (select assinatura from consulta_assinada where nome = 'insercao')),
  null, null,
  'insert assinado também falha'
);
select throws_ok(
  format('select marts.executar_consulta(%L, null)', (select sql from consulta_assinada where nome = 'contagem')),
  '42501', null,
  'consulta sem assinatura é recusada'
);
select throws_ok(
  format('select marts.executar_consulta(%L, %L)',
    'select count(*) as total from staging.parcela_receber where true',
    (select assinatura from consulta_assinada where nome = 'contagem')),
  '42501', null,
  'assinatura de outra consulta é recusada'
);
select is(app.assinatura_consulta_valida('select 1', repeat('0', 64)), false, 'assinatura inventada não confere');

-- Execução com o diretor
reset role;
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-0000000007d1", "role": "authenticated"}', true);
set local role authenticated;
select is(
  marts.executar_consulta(
    (select sql from consulta_assinada where nome = 'contagem'),
    (select assinatura from consulta_assinada where nome = 'contagem')
  ),
  '[{"total": 2}]'::jsonb,
  'diretor conta as duas obras do próprio tenant e nenhuma do outro'
);

-- Sem usuário
reset role;
select set_config('request.jwt.claims', '{"role": "authenticated"}', true);
set local role authenticated;
select throws_ok(
  format('select marts.executar_consulta(%L, %L)',
    (select sql from consulta_assinada where nome = 'contagem'),
    (select assinatura from consulta_assinada where nome = 'contagem')),
  '42501', null,
  'sem usuário no JWT a consulta é recusada'
);

-- Anônimo
reset role;
select set_config('request.jwt.claims', '{"role": "anon"}', true);
set local role anon;
select throws_ok(
  format('select marts.executar_consulta(%L, %L)',
    (select sql from consulta_assinada where nome = 'contagem'),
    (select assinatura from consulta_assinada where nome = 'contagem')),
  '42501', null,
  'anônimo não chega a executar'
);

reset role;
select * from finish();
rollback;
