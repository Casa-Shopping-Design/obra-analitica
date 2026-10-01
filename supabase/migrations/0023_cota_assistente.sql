-- Cota do assistente: reservar e concluir pergunta passam a exigir o segundo fator de diretor e financeiro,
-- como as tabelas desde a 0022, e o custo gravado por pergunta ganha teto. As duas funções são security
-- definer e passam por fora da política restritiva, então a conferência entra no corpo delas.

-- US$ 0,25: as três chamadas da rota somam no máximo 10 mil tokens de saída (US$ 0,10) e a entrada fica bem
-- abaixo de 75 mil tokens (US$ 0,15); inflar o custo não trava o tenant mais depressa que perguntas de verdade.
alter table app.parametro_assistente
  add column if not exists teto_por_pergunta_usd numeric(12, 6) not null default 0.25
  check (teto_por_pergunta_usd > 0);

create or replace function app.reservar_pergunta(p_id_requisicao uuid, p_pergunta text) returns bigint
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
  if not app.segundo_fator_cumprido() then
    raise exception 'pergunta exige o segundo fator' using errcode = '42501';
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

-- Custo acima do teto é gravado no teto, e não recusado: recusar deixaria a resposta legítima sem registro e a
-- reserva aberta sem custo. Os tokens ficam como vieram, para a auditoria refazer a conta.
create or replace function app.concluir_pergunta(
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
declare
  teto numeric;
begin
  if not app.segundo_fator_cumprido() then
    raise exception 'pergunta exige o segundo fator' using errcode = '42501';
  end if;
  if p_resultado not in ('ok', 'recusada', 'erro') then
    raise exception 'resultado inválido' using errcode = '22023';
  end if;
  -- Custo negativo abateria o gasto do dia e abriria espaço acima do teto diário.
  if p_custo < 0 then
    raise exception 'custo inválido' using errcode = '22023';
  end if;

  select teto_por_pergunta_usd into teto from app.parametro_assistente where id;

  update app.pergunta_assistente
  set sql_gerado = p_sql_gerado,
      sql_executado = p_sql_executado,
      resultado = p_resultado,
      linhas_devolvidas = p_linhas,
      duracao_ms = p_duracao_ms,
      tokens_entrada = p_tokens_entrada,
      tokens_saida = p_tokens_saida,
      custo_estimado = least(p_custo, teto)
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
