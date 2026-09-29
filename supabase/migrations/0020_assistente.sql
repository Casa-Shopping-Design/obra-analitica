-- Assistente: tempo máximo por consulta, ponto único de execução do SQL validado, reserva atômica
-- de cada pergunta contra o limite por hora e o teto diário, e registro que só o diretor lê por
-- inteiro. Decisões em docs/decisoes/0004-validador-parser.md e 0008-decisoes-assistente-saude.md.

-- Teto de proteção de todas as telas, não só do assistente. O PostgREST aplica a configuração do
-- papel em cada requisição depois de recarregar a configuração.
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

-- O Supabase já traz o pgcrypto em extensions; a linha só garante a função hmac num banco novo.
create extension if not exists pgcrypto with schema extensions;

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
-- na aplicação; esta função só executa, em transação somente leitura, e confere que a identidade
-- da sessão saiu igual à que entrou.
create function marts.executar_consulta(p_sql text, p_assinatura text) returns jsonb
language plpgsql volatile security invoker set search_path = '' as $$
declare
  consulta refcursor;
  linhas jsonb;
  claims_antes text;
  papel_antes text;
begin
  if auth.uid() is null then
    raise exception 'consulta exige usuário autenticado' using errcode = '42501';
  end if;
  if not app.assinatura_consulta_valida(p_sql, p_assinatura) then
    raise exception 'consulta sem assinatura válida' using errcode = '42501';
  end if;

  set local transaction_read_only = on;
  -- O Postgres arma o cronômetro no início de cada comando, então esta linha não encurta a chamada em
  -- que está (medido: pg_sleep(10) completa). Quem corta esta chamada é o statement_timeout que o PostgREST
  -- põe na transação a partir do papel; a linha cobre o comando seguinte de quem entrar por conexão direta.
  set local statement_timeout = '8s';
  claims_antes := current_setting('request.jwt.claims', true);
  papel_antes := current_setting('role', true);

  -- Cursor em vez de execute: o Postgres recusa abrir cursor com mais de um comando, então um segundo
  -- comando escondido no texto (um set local nos claims, por exemplo) não chega a rodar.
  open consulta for execute format('select coalesce(jsonb_agg(l), ''[]''::jsonb) from (%s) l', p_sql);
  fetch consulta into linhas;
  close consulta;

  -- set_config numa subconsulta passa pelo cursor e pela transação só de leitura. Se os claims ou o
  -- papel saíram diferentes de como entraram, as linhas foram lidas com outro RLS e não saem daqui.
  -- Uma troca restaurada dentro do mesmo comando não é vista aqui: quem barra set_config é a lista
  -- fechada de funções do validador, e só SQL validado ganha assinatura.
  if current_setting('request.jwt.claims', true) is distinct from claims_antes
     or current_setting('role', true) is distinct from papel_antes then
    raise exception 'consulta alterou a identidade da sessão' using errcode = '42501';
  end if;
  return linhas;
end;
$$;

revoke execute on function marts.executar_consulta(text, text) from public, anon;
grant execute on function marts.executar_consulta(text, text) to authenticated;

-- Limites do assistente, iguais para todos os tenants. Linha única, sem grant: só as funções abaixo leem.
create table app.parametro_assistente (
  id boolean primary key default true check (id),
  perguntas_por_hora integer not null default 30 check (perguntas_por_hora > 0),
  teto_diario_usd numeric(12, 6) not null default 5 check (teto_diario_usd >= 0)
);

insert into app.parametro_assistente default values;

alter table app.parametro_assistente enable row level security;
alter table app.parametro_assistente force row level security;
revoke all on app.parametro_assistente from public, anon, authenticated;

-- Sem chave estrangeira para auth.users: o registro sobrevive à remoção do usuário. A linha nasce
-- 'pendente' pela reserva, antes de chamar o modelo, e é fechada uma vez por concluir_pergunta.
create table app.pergunta_assistente (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  tenant_id uuid not null references app.tenant(id) on delete cascade,
  id_requisicao uuid not null,
  pergunta text not null,
  sql_gerado text,
  sql_executado text,
  resultado text not null check (resultado in ('pendente', 'ok', 'recusada', 'erro')),
  linhas_devolvidas integer,
  duracao_ms integer,
  tokens_entrada integer,
  tokens_saida integer,
  custo_estimado numeric(12, 6),
  criado_em timestamptz not null default now()
);

create index pergunta_assistente_usuario_criado_idx on app.pergunta_assistente (user_id, criado_em desc);
create index pergunta_assistente_tenant_criado_idx on app.pergunta_assistente (tenant_id, criado_em desc);

-- Sem política de insert, update e delete: escrita só pelas funções abaixo, que preenchem usuário e
-- tenant a partir do JWT. A leitura direta não alcança as colunas de SQL (grant por coluna).
alter table app.pergunta_assistente enable row level security;
alter table app.pergunta_assistente force row level security;

create policy leitura_pergunta on app.pergunta_assistente
  for select to authenticated
  using (
    tenant_id = (select app.tenant_atual())
    and (user_id = (select auth.uid()) or (select app.perfil_atual()) = 'diretor')
  );

revoke all on app.pergunta_assistente from public, anon, authenticated;
grant select (id, user_id, tenant_id, id_requisicao, pergunta, resultado, linhas_devolvidas, duracao_ms, criado_em)
  on app.pergunta_assistente to authenticated;

-- Reserva a pergunta antes de o servidor pagar o modelo. O bloqueio por usuário serializa perguntas
-- simultâneas: a segunda espera a primeira gravar e a conta como pendente. O teto diário do tenant
-- é conferido no mesmo passo. Duas buscas por índice: (user_id, criado_em) e (tenant_id, criado_em).
create function app.reservar_pergunta(p_id_requisicao uuid, p_pergunta text) returns bigint
language plpgsql volatile security definer set search_path = '' as $$
declare
  usuario uuid := auth.uid();
  tenant uuid := app.tenant_atual();
  parametro app.parametro_assistente;
  perguntas_na_hora integer;
  gasto_no_dia numeric;
  inicio_do_dia timestamptz;
  id_reservado bigint;
begin
  if usuario is null or tenant is null then
    raise exception 'pergunta exige usuário ligado a uma construtora' using errcode = '42501';
  end if;
  if p_pergunta is null or length(p_pergunta) = 0 then
    raise exception 'pergunta vazia' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtext('pergunta_assistente'), hashtext(usuario::text));

  select * into parametro from app.parametro_assistente where id;

  select count(*) into perguntas_na_hora
  from app.pergunta_assistente
  where user_id = usuario and criado_em >= now() - interval '1 hour';
  if perguntas_na_hora >= parametro.perguntas_por_hora then
    raise exception 'limite' using errcode = 'P0001';
  end if;

  -- Dia corrente em Brasília, onde o piloto opera.
  inicio_do_dia := date_trunc('day', now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo';
  select coalesce(sum(custo_estimado), 0) into gasto_no_dia
  from app.pergunta_assistente
  where tenant_id = tenant and criado_em >= inicio_do_dia;
  if gasto_no_dia >= parametro.teto_diario_usd then
    raise exception 'teto' using errcode = 'P0001';
  end if;

  insert into app.pergunta_assistente (user_id, tenant_id, id_requisicao, pergunta, resultado)
  values (usuario, tenant, p_id_requisicao, p_pergunta, 'pendente')
  returning id into id_reservado;
  return id_reservado;
end;
$$;

revoke execute on function app.reservar_pergunta(uuid, text) from public, anon;
grant execute on function app.reservar_pergunta(uuid, text) to authenticated;

-- Fecha a reserva uma vez só, e só a de quem a abriu. Reserva já fechada ou de outro usuário falha.
create function app.concluir_pergunta(
  p_id bigint,
  p_sql_gerado text,
  p_sql_executado text,
  p_resultado text,
  p_linhas integer,
  p_duracao_ms integer,
  p_tokens_entrada integer,
  p_tokens_saida integer,
  p_custo numeric
) returns void
language plpgsql volatile security definer set search_path = '' as $$
begin
  if p_resultado not in ('ok', 'recusada', 'erro') then
    raise exception 'resultado inválido' using errcode = '22023';
  end if;

  update app.pergunta_assistente
  set sql_gerado = p_sql_gerado,
      sql_executado = p_sql_executado,
      resultado = p_resultado,
      linhas_devolvidas = p_linhas,
      duracao_ms = p_duracao_ms,
      tokens_entrada = p_tokens_entrada,
      tokens_saida = p_tokens_saida,
      custo_estimado = p_custo
  where id = p_id and user_id = auth.uid() and resultado = 'pendente';

  if not found then
    raise exception 'pergunta não está pendente para este usuário' using errcode = '42501';
  end if;
end;
$$;

revoke execute on function app.concluir_pergunta(bigint, text, text, text, integer, integer, integer, integer, numeric)
  from public, anon;
grant execute on function app.concluir_pergunta(bigint, text, text, text, integer, integer, integer, integer, numeric)
  to authenticated;

-- O SQL gravado sai só para o diretor do tenant. A versão em lote atende o histórico da tela numa chamada;
-- quem não é diretor recebe zero linhas, e não erro, para a tela não distinguir perfil pelo código.
create function app.sql_das_perguntas(p_ids bigint[]) returns table (id bigint, sql_gerado text, sql_executado text)
language sql stable security definer set search_path = '' as $$
  select p.id, p.sql_gerado, p.sql_executado
  from app.pergunta_assistente p
  where p.id = any (p_ids)
    and p.tenant_id = app.tenant_atual()
    and app.perfil_atual() = 'diretor'
$$;

create function app.sql_da_pergunta(p_id bigint) returns table (sql_gerado text, sql_executado text)
language sql stable security definer set search_path = '' as $$
  select s.sql_gerado, s.sql_executado from app.sql_das_perguntas(array[p_id]) s
$$;

revoke execute on function app.sql_das_perguntas(bigint[]), app.sql_da_pergunta(bigint) from public, anon;
grant execute on function app.sql_das_perguntas(bigint[]), app.sql_da_pergunta(bigint) to authenticated;
