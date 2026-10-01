-- Trilha do assistente com o SQL que rodou de verdade. Até a 0023, concluir_pergunta gravava o sql_gerado e o
-- sql_executado que quem chama mandava, e qualquer usuário logado podia chamar a função direto com texto falso.
-- Agora executar_consulta grava o sql_executado na reserva pendente do próprio usuário, e o sql_gerado só entra
-- com a assinatura HMAC do servidor. Decisão em docs/decisoes/0014-auditoria-assistente.md.

-- Security definer porque o papel authenticated não tem update na tabela. Quem chama é executar_consulta, que
-- roda como o usuário; a função confere a assinatura de novo para uma chamada direta não gravar SQL que o
-- servidor não assinou. O sql_executado é gravado uma vez só, na reserva pendente de quem pergunta.
create function app.registrar_sql_executado(p_id_pergunta bigint, p_sql text, p_assinatura text) returns void
language plpgsql volatile security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'consulta exige usuário autenticado' using errcode = '42501';
  end if;
  if not app.segundo_fator_cumprido() then
    raise exception 'pergunta exige o segundo fator' using errcode = '42501';
  end if;
  if not app.assinatura_consulta_valida(p_sql, p_assinatura) then
    raise exception 'consulta sem assinatura válida' using errcode = '42501';
  end if;

  update app.pergunta_assistente
  set sql_executado = p_sql
  where id = p_id_pergunta
    and user_id = auth.uid()
    and resultado = 'pendente'
    and sql_executado is null;

  if not found then
    raise exception 'pergunta não está pendente para este usuário' using errcode = '42501';
  end if;
end;
$$;

revoke execute on function app.registrar_sql_executado(bigint, text, text) from public, anon;
grant execute on function app.registrar_sql_executado(bigint, text, text) to authenticated;

-- A assinatura nova pede o id da pergunta; a antiga sai para ninguém executar sem deixar rastro.
drop function marts.executar_consulta(text, text);

-- Mesmo corpo da 0020, com a gravação na trilha antes de a transação virar somente leitura. Se a consulta
-- falhar, o PostgREST desfaz a transação inteira e a gravação junto: pergunta com erro de execução fica sem
-- sql_executado, e a auditoria refaz o texto a partir do sql_gerado assinado.
create function marts.executar_consulta(p_id_pergunta bigint, p_sql text, p_assinatura text) returns jsonb
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

  perform app.registrar_sql_executado(p_id_pergunta, p_sql, p_assinatura);

  set local transaction_read_only = on;
  -- O cronômetro é armado no início de cada comando, então esta linha não encurta a chamada em que está.
  -- Quem corta esta chamada é o statement_timeout que o PostgREST põe a partir do papel.
  set local statement_timeout = '8s';
  claims_antes := current_setting('request.jwt.claims', true);
  papel_antes := current_setting('role', true);

  -- Cursor em vez de execute: o Postgres recusa abrir cursor com mais de um comando.
  open consulta for execute format('select coalesce(jsonb_agg(l), ''[]''::jsonb) from (%s) l', p_sql);
  fetch consulta into linhas;
  close consulta;

  -- Claims ou papel diferentes na saída querem dizer que as linhas foram lidas com outro RLS.
  if current_setting('request.jwt.claims', true) is distinct from claims_antes
     or current_setting('role', true) is distinct from papel_antes then
    raise exception 'consulta alterou a identidade da sessão' using errcode = '42501';
  end if;
  return linhas;
end;
$$;

revoke execute on function marts.executar_consulta(bigint, text, text) from public, anon;
grant execute on function marts.executar_consulta(bigint, text, text) to authenticated;

-- Os tipos dos parâmetros são os mesmos da 0023, mas o terceiro muda de sentido e de nome, e create or
-- replace não renomeia parâmetro.
drop function app.concluir_pergunta(bigint, text, text, text, integer, integer, integer, integer, numeric);

-- O sql_gerado é a saída do modelo e só o servidor a conhece. Ele assina 'sql_gerado:<id>:<texto>' com a mesma
-- chave das consultas: o prefixo impede que a assinatura sirva em executar_consulta, e o id impede reaproveitar
-- a assinatura em outra pergunta. Sem texto, a assinatura é dispensada e a trilha fica sem sql_gerado.
-- 'ok' exige o sql_executado gravado pela execução, e 'recusada' exige que nada tenha rodado.
create function app.concluir_pergunta(
  p_id bigint,
  p_sql_gerado text,
  p_assinatura_sql_gerado text,
  p_resultado text,
  p_linhas integer,
  p_duracao_ms integer,
  p_tokens_entrada integer,
  p_tokens_saida integer,
  p_custo numeric
) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  teto numeric;
  sql_gerado_gravado text := nullif(p_sql_gerado, '');
begin
  if not app.segundo_fator_cumprido() then
    raise exception 'pergunta exige o segundo fator' using errcode = '42501';
  end if;
  if p_resultado not in ('ok', 'recusada', 'erro') then
    raise exception 'resultado inválido' using errcode = '22023';
  end if;
  if p_custo < 0 then
    raise exception 'custo inválido' using errcode = '22023';
  end if;
  if sql_gerado_gravado is not null
     and not app.assinatura_consulta_valida(format('sql_gerado:%s:%s', p_id, sql_gerado_gravado), p_assinatura_sql_gerado) then
    raise exception 'sql_gerado sem assinatura válida' using errcode = '42501';
  end if;

  select teto_por_pergunta_usd into teto from app.parametro_assistente where id;

  update app.pergunta_assistente
  set sql_gerado = sql_gerado_gravado,
      resultado = p_resultado,
      linhas_devolvidas = p_linhas,
      duracao_ms = p_duracao_ms,
      tokens_entrada = p_tokens_entrada,
      tokens_saida = p_tokens_saida,
      custo_estimado = least(p_custo, teto)
  where id = p_id
    and user_id = auth.uid()
    and resultado = 'pendente'
    and case p_resultado
          when 'ok' then sql_executado is not null
          when 'recusada' then sql_executado is null
          else true
        end;

  if not found then
    raise exception 'pergunta não está pendente para este usuário ou o resultado não confere com a execução'
      using errcode = '42501';
  end if;
end;
$$;

revoke execute on function app.concluir_pergunta(bigint, text, text, text, integer, integer, integer, integer, numeric)
  from public, anon;
grant execute on function app.concluir_pergunta(bigint, text, text, text, integer, integer, integer, integer, numeric)
  to authenticated;
