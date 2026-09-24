-- Assistente: execução da consulta validada com o JWT do usuário e auditoria de cada pergunta.
-- A chave de assinatura não entra aqui. João cria no Vault de cada projeto, com o mesmo valor
-- da variável ASSISTENTE_CHAVE_ASSINATURA do servidor do painel:
--   select vault.create_secret('<chave gerada com openssl rand -hex 32>', 'assistente_chave_assinatura');

create extension if not exists pgcrypto with schema extensions;

-- O PostgREST aplica a configuração do papel em cada requisição; vale para toda consulta de usuário logado.
alter role authenticated set statement_timeout = '8s';

create table app.pergunta_assistente (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid(),
  tenant_id uuid not null default app.tenant_atual() references app.tenant(id) on delete cascade,
  id_requisicao uuid,
  pergunta text not null check (char_length(pergunta) between 1 and 2000),
  sql_gerado text check (char_length(sql_gerado) <= 20000),
  sql_executado text check (char_length(sql_executado) <= 20000),
  situacao text not null check (situacao in ('executada', 'recusada', 'falhou')),
  linhas integer check (linhas >= 0),
  duracao_ms integer check (duracao_ms >= 0),
  tokens_entrada integer check (tokens_entrada >= 0),
  tokens_saida integer check (tokens_saida >= 0),
  custo_estimado numeric(12, 6) check (custo_estimado >= 0),
  criado_em timestamptz not null default now()
);

-- O primeiro atende o limite por hora de cada usuário; o segundo, a leitura do diretor e o custo por dia.
create index pergunta_assistente_usuario_idx on app.pergunta_assistente (user_id, criado_em desc);
create index pergunta_assistente_tenant_idx on app.pergunta_assistente (tenant_id, criado_em desc);

alter table app.pergunta_assistente enable row level security;
alter table app.pergunta_assistente force row level security;

create policy registro_propria_pergunta on app.pergunta_assistente
  for insert to authenticated
  with check (user_id = (select auth.uid()) and tenant_id = (select app.tenant_atual()));

create policy leitura_perguntas on app.pergunta_assistente
  for select to authenticated
  using (
    tenant_id = (select app.tenant_atual())
    and (user_id = (select auth.uid()) or (select app.perfil_atual()) = 'diretor')
  );

-- Sem update nem delete: o registro é imutável para o usuário. Quem, quando e de qual tenant
-- vêm dos valores padrão, por isso essas colunas ficam fora da permissão de insert.
revoke all on app.pergunta_assistente from public, anon, authenticated;
grant select on app.pergunta_assistente to authenticated;
grant insert (
  id_requisicao, pergunta, sql_gerado, sql_executado, situacao,
  linhas, duracao_ms, tokens_entrada, tokens_saida, custo_estimado
) on app.pergunta_assistente to authenticated;

-- security definer porque lê a chave no Vault, que o usuário não enxerga. Devolve só verdadeiro ou falso.
create or replace function app.assinatura_consulta_valida(p_sql text, p_assinatura text) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (
      select encode(extensions.hmac(p_sql, s.decrypted_secret, 'sha256'), 'hex') = lower(p_assinatura)
      from vault.decrypted_secrets s
      where s.name = 'assistente_chave_assinatura'
    ),
    false
  )
$$;

revoke execute on function app.assinatura_consulta_valida(text, text) from public, anon;
grant execute on function app.assinatura_consulta_valida(text, text) to authenticated;

-- Só executa. A segurança vem do RLS, do papel authenticated sem grant de escrita, da transação
-- somente leitura e da assinatura: o marts é exposto pela API, e sem ela qualquer usuário logado
-- mandaria SQL próprio direto para cá sem passar pelo validador do painel.
create or replace function marts.executar_consulta(p_sql text, p_assinatura text) returns jsonb
language plpgsql volatile security invoker set search_path = '' as $$
declare
  resultado jsonb;
begin
  if (select auth.uid()) is null or (select app.tenant_atual()) is null then
    raise exception 'usuario sem sessao' using errcode = '42501';
  end if;

  if not app.assinatura_consulta_valida(p_sql, p_assinatura) then
    raise exception 'consulta sem assinatura valida' using errcode = '42501';
  end if;

  set local transaction_read_only = on;

  execute format(
    E'select coalesce(jsonb_agg(linha), ''[]''::jsonb) from (select * from (\n%s\n) consulta limit 500) linha',
    p_sql
  ) into resultado;

  return resultado;
end;
$$;

revoke execute on function marts.executar_consulta(text, text) from public, anon;
grant execute on function marts.executar_consulta(text, text) to authenticated;

notify pgrst, 'reload config';
notify pgrst, 'reload schema';
