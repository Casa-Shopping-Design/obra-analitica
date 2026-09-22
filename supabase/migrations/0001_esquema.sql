-- Esquema base da demo. Mantem a separacao raw / staging / marts / app do MVP.
create schema if not exists raw;
create schema if not exists staging;
create schema if not exists marts;
create schema if not exists app;

-- Controle de tenant e permissoes
create table app.tenant (
  id uuid primary key default gen_random_uuid(),
  razao_social text not null,
  cnpj text,
  conta_origem text,
  status text not null default 'ativo'
);

create table app.centro_custo (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenant(id) on delete cascade,
  id_origem integer not null,
  nome text not null,
  empresa_id integer,
  unique (tenant_id, id_origem)
);

create table app.usuario_tenant (
  user_id uuid not null references auth.users(id) on delete cascade,
  tenant_id uuid not null references app.tenant(id) on delete cascade,
  perfil text not null check (perfil in ('diretor','financeiro','comercial','gerente_obra','leitura')),
  primary key (user_id, tenant_id)
);

create table app.usuario_centro_custo (
  user_id uuid not null references auth.users(id) on delete cascade,
  tenant_id uuid not null references app.tenant(id) on delete cascade,
  centro_custo_id uuid not null references app.centro_custo(id) on delete cascade,
  primary key (user_id, centro_custo_id)
);

-- Camada raw: um payload por registro devolvido pelo ERP de origem
create table raw.registro (
  id bigserial primary key,
  tenant_id uuid not null references app.tenant(id) on delete cascade,
  endpoint text not null,
  payload jsonb not null,
  hash_registro text not null,
  carregado_em timestamptz not null default now(),
  unique (tenant_id, endpoint, hash_registro)
);
create index on raw.registro (tenant_id, endpoint);

-- Funcoes que leem o JWT. Na demo os claims vem de app.usuario_tenant via hook de acesso.
create or replace function app.tenant_atual() returns uuid
language sql stable security definer set search_path = app as $$
  select coalesce(
    (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::uuid,
    (select tenant_id from app.usuario_tenant where user_id = auth.uid() limit 1)
  )
$$;

create or replace function app.perfil_atual() returns text
language sql stable security definer set search_path = app as $$
  select coalesce(
    auth.jwt() -> 'app_metadata' ->> 'perfil',
    (select perfil from app.usuario_tenant where user_id = auth.uid() and tenant_id = app.tenant_atual())
  )
$$;

create or replace function app.obras_permitidas() returns setof uuid
language sql stable security definer set search_path = app as $$
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

grant usage on schema app, staging, marts to authenticated;
grant execute on function app.tenant_atual(), app.perfil_atual(), app.obras_permitidas() to authenticated;

-- RLS nas tabelas de controle: o usuario so ve o proprio tenant
alter table app.centro_custo enable row level security;
alter table app.centro_custo force row level security;
create policy leitura_tenant on app.centro_custo
  for select to authenticated
  using (tenant_id = app.tenant_atual() and id in (select app.obras_permitidas()));
grant select on app.centro_custo to authenticated;
