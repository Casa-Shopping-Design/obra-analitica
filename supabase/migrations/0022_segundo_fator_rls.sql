-- Diretor e financeiro só leem dado com a sessão em aal2. O painel já barra quem está em aal1, mas o token
-- de quem tem só a senha também fala direto com a API do banco, fora do painel.

-- A lista de perfis repete a de painel/lib/supabase/nivel-acesso.ts; mudar uma pede mudar a outra.
-- Usuário sem vínculo não tem perfil e passa: as políticas permissivas já não mostram nada a ele.
create function app.segundo_fator_cumprido() returns boolean
language sql stable security invoker set search_path = '' as $$
  select coalesce(app.perfil_atual() not in ('diretor', 'financeiro'), true)
      or coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
$$;

revoke execute on function app.segundo_fator_cumprido() from public, anon;
grant execute on function app.segundo_fator_cumprido() to authenticated;

-- Restritiva soma com AND à permissiva de cada tabela. O select em volta da função vira initplan e ela
-- roda uma vez por consulta, não uma vez por linha. Tabela sem política permissiva fica como está: ninguém
-- além do dono a lê. O teste segundo_fator_rls.sql acusa tabela nova que ganhe permissiva sem a restritiva.
do $$
declare
  tabela record;
begin
  for tabela in
    select n.nspname as esquema, c.relname as nome
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where c.relkind in ('r', 'p')
      and c.relrowsecurity
      and n.nspname in ('app', 'staging')
      and exists (select 1 from pg_catalog.pg_policy p where p.polrelid = c.oid and p.polpermissive)
    order by n.nspname, c.relname
  loop
    execute format(
      'create policy segundo_fator on %I.%I as restrictive for all to authenticated
         using ((select app.segundo_fator_cumprido()))',
      tabela.esquema, tabela.nome
    );
  end loop;
end;
$$;

-- security definer lê a tabela como dona e passa por fora do RLS, então a conferência entra na consulta.
create or replace function app.sql_das_perguntas(p_ids bigint[]) returns table (id bigint, sql_gerado text, sql_executado text)
language sql stable security definer set search_path = '' as $$
  select p.id, p.sql_gerado, p.sql_executado
  from app.pergunta_assistente p
  where p.id = any (p_ids)
    and p.tenant_id = app.tenant_atual()
    and app.perfil_atual() = 'diretor'
    and app.segundo_fator_cumprido()
$$;
