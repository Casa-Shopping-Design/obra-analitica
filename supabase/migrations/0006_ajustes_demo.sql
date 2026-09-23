-- Ajustes antes da demo: search_path vazio nas funções de acesso, RLS nas tabelas de controle,
-- cobertura do orçamento no lugar do falso ponto de equilíbrio e hook que grava os claims no JWT.

-- Mesmo corpo da 0001; muda só o search_path, porque com "app" um objeto homônimo criado
-- em outro schema do caminho poderia ser resolvido no lugar do verdadeiro.
create or replace function app.tenant_atual() returns uuid
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::uuid,
    (select tenant_id from app.usuario_tenant where user_id = auth.uid() limit 1)
  )
$$;

create or replace function app.perfil_atual() returns text
language sql stable security definer set search_path = '' as $$
  select coalesce(
    auth.jwt() -> 'app_metadata' ->> 'perfil',
    (select perfil from app.usuario_tenant where user_id = auth.uid() and tenant_id = app.tenant_atual())
  )
$$;

create or replace function app.obras_permitidas() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select cc.id
  from app.centro_custo cc
  where cc.tenant_id = app.tenant_atual()
    and (
      app.perfil_atual() in ('diretor', 'financeiro')
      or exists (
        select 1 from app.usuario_centro_custo ucc
        where ucc.user_id = auth.uid() and ucc.centro_custo_id = cc.id
      )
    )
$$;

-- Só as políticas de RLS do usuário logado chamam estas funções; anônimo não precisa.
revoke execute on function app.tenant_atual(), app.perfil_atual(), app.obras_permitidas() from public, anon;
grant execute on function app.tenant_atual(), app.perfil_atual(), app.obras_permitidas() to authenticated;

-- As funções acima leem estas tabelas como dono (que ignora RLS), então as políticas não entram em recursão.
alter table app.tenant enable row level security;
alter table app.tenant force row level security;
create policy leitura_proprio_tenant on app.tenant
  for select to authenticated
  using (id = app.tenant_atual());
grant select on app.tenant to authenticated;

alter table app.usuario_tenant enable row level security;
alter table app.usuario_tenant force row level security;
create policy leitura_proprio_vinculo on app.usuario_tenant
  for select to authenticated
  using (user_id = (select auth.uid()));
grant select on app.usuario_tenant to authenticated;

alter table app.usuario_centro_custo enable row level security;
alter table app.usuario_centro_custo force row level security;
create policy leitura_proprio_vinculo on app.usuario_centro_custo
  for select to authenticated
  using (user_id = (select auth.uid()));
grant select on app.usuario_centro_custo to authenticated;

-- Comparar VGV com orçamento mede cobertura, não ponto de equilíbrio (ver docs/decisoes/0001).
-- A coluna de meses volta no PT-06, com a VSO calculada sobre calendário contínuo.
drop view marts.break_even_obra;

create view marts.cobertura_orcamento_obra with (security_invoker = true) as
with orcamento as (
  select tenant_id, centro_custo_id, sum(valor_total) as custo_orcado
  from staging.item_orcamento
  group by 1, 2
), vendas as (
  select tenant_id, centro_custo_id, sum(valor) as vgv_contratado, avg(valor) as ticket_medio
  from staging.contrato_venda
  where situacao = '1'
  group by 1, 2
)
select cc.tenant_id, cc.id as centro_custo_id, cc.nome as obra,
  coalesce(o.custo_orcado, 0) as custo_orcado,
  coalesce(v.vgv_contratado, 0) as vgv_contratado,
  case when o.custo_orcado > 0 then round(coalesce(v.vgv_contratado, 0) / o.custo_orcado, 4) end as pct_cobertura,
  round(v.ticket_medio, 2) as ticket_medio,
  case when v.ticket_medio > 0
       then greatest(0, ceil((coalesce(o.custo_orcado, 0) - v.vgv_contratado) / v.ticket_medio))::integer end as unidades_para_cobrir
from app.centro_custo cc
left join orcamento o on o.tenant_id = cc.tenant_id and o.centro_custo_id = cc.id
left join vendas v on v.tenant_id = cc.tenant_id and v.centro_custo_id = cc.id;

grant select on marts.cobertura_orcamento_obra to authenticated;

-- Custom Access Token Hook: o Auth chama antes de emitir cada JWT. Os claims saem de
-- app.usuario_tenant, que só o servidor grava; user_metadata o próprio usuário edita.
create or replace function app.claims_jwt(event jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  claims jsonb := event -> 'claims';
  vinculo record;
begin
  select ut.tenant_id, ut.perfil into vinculo
  from app.usuario_tenant ut
  where ut.user_id = (event ->> 'user_id')::uuid
  order by ut.tenant_id
  limit 1;

  if found then
    claims := jsonb_set(
      claims,
      '{app_metadata}',
      coalesce(claims -> 'app_metadata', '{}'::jsonb)
        || jsonb_build_object('tenant_id', vinculo.tenant_id, 'perfil', vinculo.perfil)
    );
  end if;

  return jsonb_set(event, '{claims}', claims);
end;
$$;

-- security definer lê a tabela como dono, então supabase_auth_admin precisa só de executar.
grant usage on schema app to supabase_auth_admin;
grant execute on function app.claims_jwt(jsonb) to supabase_auth_admin;
revoke execute on function app.claims_jwt(jsonb) from public, anon, authenticated;
