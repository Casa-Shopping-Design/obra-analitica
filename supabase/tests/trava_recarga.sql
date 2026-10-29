-- Trava por tenant nas recargas do staging (migration 0041): staging.recarregar e staging.recarregar_precos
-- tomam a mesma trava consultiva das outras recargas, e a trava fica na transação. Cria os próprios dados.
begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

insert into app.tenant (id, razao_social) values ('0e000000-0000-4000-8000-0000000000f1', 'Construtora Trava');

-- A chave de 64 bits fica em pg_locks partida em classid (32 bits altos) e objid (32 bits baixos).
create function pg_temp.travas_da_recarga(p_tenant uuid) returns bigint language sql as $$
  select count(*)
  from pg_locks l, hashtextextended('recarga:' || p_tenant::text, 0) as chave
  where l.locktype = 'advisory' and l.pid = pg_backend_pid() and l.objsubid = 1
    and l.classid::bigint = (chave >> 32) & 4294967295
    and l.objid::bigint = chave & 4294967295
$$;

select matches(
  pg_get_functiondef('staging.recarregar(uuid)'::regprocedure),
  'pg_advisory_xact_lock\(hashtextextended\(''recarga:'' \|\| p_tenant::text, 0\)\)',
  'staging.recarregar toma a trava com a chave das outras recargas'
);
select matches(
  pg_get_functiondef('staging.recarregar_precos(uuid)'::regprocedure),
  'pg_advisory_xact_lock\(hashtextextended\(''recarga:'' \|\| p_tenant::text, 0\)\)',
  'staging.recarregar_precos toma a trava com a chave das outras recargas'
);

select is(pg_temp.travas_da_recarga('0e000000-0000-4000-8000-0000000000f1'), 0::bigint,
  'antes da recarga a sessão não tem a trava do tenant');

select staging.recarregar_precos('0e000000-0000-4000-8000-0000000000f1');
select is(pg_temp.travas_da_recarga('0e000000-0000-4000-8000-0000000000f1'), 1::bigint,
  'recarregar_precos deixa a trava do tenant presa na transação');

select staging.recarregar('0e000000-0000-4000-8000-0000000000f1');
select is(pg_temp.travas_da_recarga('0e000000-0000-4000-8000-0000000000f1'), 1::bigint,
  'recarregar na mesma transação reentra na trava sem travar nem duplicar');

select ok(
  not has_function_privilege('anon', 'staging.recarregar(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'staging.recarregar(uuid)', 'execute')
    and not has_function_privilege('public', 'staging.recarregar(uuid)', 'execute'),
  'staging.recarregar segue revogada de anon, authenticated e public'
);
select ok(
  not has_function_privilege('anon', 'staging.recarregar_precos(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'staging.recarregar_precos(uuid)', 'execute')
    and not has_function_privilege('public', 'staging.recarregar_precos(uuid)', 'execute'),
  'staging.recarregar_precos segue revogada de anon, authenticated e public'
);

select * from finish();
rollback;
