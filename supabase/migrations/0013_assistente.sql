-- Assistente: tempo máximo por consulta no papel authenticated, ponto único de execução do SQL
-- validado e registro de cada pergunta. Decisões em docs/decisoes/0004-validador-parser.md.

-- O PostgREST aplica as configurações do papel em cada requisição depois de recarregar a configuração.
alter role authenticated set statement_timeout = '8s';
notify pgrst, 'reload config';

-- Chave da assinatura HMAC que o servidor do painel põe em cada SQL validado. Sem ela, qualquer usuário
-- logado chamaria executar_consulta direto pela API com SQL livre, inclusive set_config nos claims que o RLS lê.
-- O valor não fica em migration: João grava pelo editor SQL (docs/decisoes/0004).
create table app.chave_assinatura_consulta (
  id boolean primary key default true check (id),
  chave text not null check (length(chave) >= 32),
  criada_em timestamptz not null default now()
);

-- Sem política e sem grant: só a função abaixo, como dona, lê a chave.
alter table app.chave_assinatura_consulta enable row level security;
alter table app.chave_assinatura_consulta force row level security;
revoke all on app.chave_assinatura_consulta from public, anon, authenticated;

create function app.assinatura_consulta_valida(p_sql text, p_assinatura text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from app.chave_assinatura_consulta k
    where encode(extensions.hmac(p_sql, k.chave, 'sha256'), 'hex') = p_assinatura
  )
$$;

revoke execute on function app.assinatura_consulta_valida(text, text) from public, anon;
grant execute on function app.assinatura_consulta_valida(text, text) to authenticated;

-- A segurança vem do RLS, do papel authenticated sem grant de escrita, da assinatura e do validador
-- na aplicação; esta função só executa, em transação somente leitura.
create function marts.executar_consulta(p_sql text, p_assinatura text) returns jsonb
language plpgsql volatile security invoker set search_path = '' as $$
declare
  consulta refcursor;
  linhas jsonb;
begin
  if auth.uid() is null then
    raise exception 'consulta exige usuário autenticado' using errcode = '42501';
  end if;
  if not app.assinatura_consulta_valida(p_sql, p_assinatura) then
    raise exception 'consulta sem assinatura válida' using errcode = '42501';
  end if;

  set local transaction_read_only = on;
  -- Cursor em vez de execute: o Postgres recusa abrir cursor com mais de um comando, então um segundo
  -- comando escondido no texto (um set local nos claims, por exemplo) não chega a rodar.
  open consulta for execute format('select coalesce(jsonb_agg(l), ''[]''::jsonb) from (%s) l', p_sql);
  fetch consulta into linhas;
  close consulta;
  return linhas;
end;
$$;

revoke execute on function marts.executar_consulta(text, text) from public, anon;
grant execute on function marts.executar_consulta(text, text) to authenticated;

-- Sem chave estrangeira para auth.users: o registro sobrevive à remoção do usuário.
create table app.pergunta_assistente (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid(),
  tenant_id uuid not null default app.tenant_atual() references app.tenant(id) on delete cascade,
  id_requisicao uuid not null,
  pergunta text not null,
  sql_gerado text not null,
  sql_executado text,
  resultado text not null check (resultado in ('ok', 'recusada', 'erro')),
  linhas_devolvidas integer,
  duracao_ms integer,
  tokens_entrada integer,
  tokens_saida integer,
  custo_estimado numeric(12, 6),
  criado_em timestamptz not null default now()
);

create index pergunta_assistente_usuario_criado_idx on app.pergunta_assistente (user_id, criado_em desc);
create index pergunta_assistente_tenant_criado_idx on app.pergunta_assistente (tenant_id, criado_em desc);

-- Sem política de update e delete: o registro não muda depois de gravado.
alter table app.pergunta_assistente enable row level security;
alter table app.pergunta_assistente force row level security;

create policy grava_propria_pergunta on app.pergunta_assistente
  for insert to authenticated
  with check (user_id = (select auth.uid()) and tenant_id = (select app.tenant_atual()));

create policy leitura_pergunta on app.pergunta_assistente
  for select to authenticated
  using (
    tenant_id = (select app.tenant_atual())
    and (user_id = (select auth.uid()) or (select app.perfil_atual()) = 'diretor')
  );

grant select, insert on app.pergunta_assistente to authenticated;
