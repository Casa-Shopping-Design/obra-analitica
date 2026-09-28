-- Fila de eventos das origens. O webhook só avisa quais IDs mudaram; o dado vem da API na carga seguinte.
-- A recepção roda na Vercel com a chave anon, por isso a escrita passa por uma função que confere o token.

create table app.webhook_origem (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenant(id) on delete cascade,
  origem text not null check (origem in ('erp', 'crm')),
  -- Só o SHA-256 do token; o token em claro fica com a origem e com quem cadastrou.
  hash_token text not null unique check (hash_token ~ '^[0-9a-f]{64}$'),
  ativo boolean not null default true,
  criado_em timestamptz not null default now()
);
create index on app.webhook_origem (tenant_id, origem);

create table app.evento_origem (
  id bigserial primary key,
  tenant_id uuid not null references app.tenant(id) on delete cascade,
  origem text not null check (origem in ('erp', 'crm')),
  id_evento text not null check (length(id_evento) between 1 and 128),
  tipo_evento text not null check (length(tipo_evento) between 1 and 64),
  ids jsonb not null check (jsonb_typeof(ids) = 'object'),
  recebido_em timestamptz not null default now(),
  processado_em timestamptz,
  unique (tenant_id, origem, id_evento)
);
-- A carga lê os pendentes por tenant e origem; o limite por minuto conta por tenant, origem e recebimento,
-- para o token do CRM, que viaja na URL e aparece em log, não gastar a cota dos avisos do ERP.
create index on app.evento_origem (tenant_id, origem, processado_em);
create index on app.evento_origem (tenant_id, origem, recebido_em);

-- Sem política: anon e authenticated não leem nem escrevem direto. Só o dono do banco (carga) e a função abaixo.
alter table app.webhook_origem enable row level security;
alter table app.webhook_origem force row level security;
alter table app.evento_origem enable row level security;
alter table app.evento_origem force row level security;
revoke all on table app.webhook_origem, app.evento_origem from public, anon, authenticated;
revoke all on sequence app.evento_origem_id_seq from public, anon, authenticated;

-- Devolve só verdadeiro ou falso: quem chama não fica sabendo se errou o token, o tipo ou os IDs.
-- Limite estourado é outra coisa: lança PT429, que a API REST devolve como HTTP 429, para a origem
-- tentar de novo em vez de tratar o aviso como falha de autenticação.
create or replace function app.registrar_evento_origem(
  p_token text,
  p_origem text,
  p_id_evento text,
  p_tipo_evento text,
  p_ids jsonb
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_recentes integer;
  v_chaves integer;
  v_total_ids integer;
  v_pendentes integer;
begin
  if p_token is null or length(p_token) not between 32 and 256
     or p_origem is null or p_origem not in ('erp', 'crm')
     or p_id_evento is null or p_id_evento !~ '^[A-Za-z0-9._:-]{1,128}$'
     or p_tipo_evento is null or p_tipo_evento !~ '^[A-Z_]{1,64}$' then
    return false;
  end if;

  select w.tenant_id into v_tenant
  from app.webhook_origem w
  where w.hash_token = encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
    and w.origem = p_origem
    and w.ativo;
  if v_tenant is null then
    return false;
  end if;

  if p_origem = 'erp' and not (
    p_tipo_evento in ('RECEIPT_PROCESSED', 'PAYMENT_BILL_UPDATED')
    or exists (
      select 1
      from unnest(array[
        'RECEIVABLE_INSTALLMENT_', 'PAYMENT_INSTALLMENT_', 'PAYMENT_RECEIPT_', 'SALES_CONTRACT_',
        'UNIT_', 'COST_CENTER_', 'BUILDING_COST_ESTIMATION', 'BANK_MOVEMENT_'
      ]) as prefixo
      where starts_with(p_tipo_evento, prefixo)
    )
  ) then
    return false;
  end if;
  if p_origem = 'crm' and p_tipo_evento not in ('RS', 'RP', 'UN', 'EV', 'CV') then
    return false;
  end if;

  if p_ids is null or jsonb_typeof(p_ids) <> 'object' or length(p_ids::text) > 4096 then
    return false;
  end if;
  select count(*) into v_chaves from jsonb_each(p_ids);
  if v_chaves = 0 or v_chaves > 10 then
    return false;
  end if;
  -- Cada valor é inteiro não negativo ou lista de 1 a 100 inteiros; texto, objeto e decimal ficam fora.
  if exists (
    select 1
    from jsonb_each(p_ids) as par
    where par.key !~ '^[A-Za-z_]{1,40}$'
       or not case jsonb_typeof(par.value)
         when 'number' then
           (par.value)::numeric = trunc((par.value)::numeric)
           and (par.value)::numeric between 0 and 9223372036854775807
         when 'array' then
           jsonb_array_length(par.value) between 1 and 100
           and not exists (
             select 1
             from jsonb_array_elements(par.value) as item
             -- case garante a ordem: converter texto para numeric daria erro em vez de falso.
             where case jsonb_typeof(item)
               when 'number' then
                 item::numeric <> trunc(item::numeric)
                 or item::numeric not between 0 and 9223372036854775807
               else true
             end
           )
         else false
       end
  ) then
    return false;
  end if;
  -- Cada ID vira reconsulta na API; um aviso com milhares de IDs gastaria a cota da carga inteira.
  select coalesce(sum(case jsonb_typeof(par.value) when 'array' then jsonb_array_length(par.value) else 1 end), 0)
    into v_total_ids
  from jsonb_each(p_ids) as par;
  if v_total_ids > 100 then
    return false;
  end if;

  -- Reenvio de evento já gravado responde verdadeiro sem contar no limite, para a origem parar de tentar.
  if exists (
    select 1 from app.evento_origem e
    where e.tenant_id = v_tenant and e.origem = p_origem and e.id_evento = p_id_evento
  ) then
    return true;
  end if;

  -- A trava por tenant e origem impede que chamadas simultâneas passem juntas do limite.
  perform pg_advisory_xact_lock(hashtextextended('evento_origem:' || v_tenant::text || ':' || p_origem, 0));
  select count(*) into v_recentes
  from app.evento_origem e
  where e.tenant_id = v_tenant and e.origem = p_origem and e.recebido_em > now() - interval '1 minute';
  if v_recentes >= 600 then
    raise exception 'limite de eventos por minuto' using errcode = 'PT429';
  end if;
  -- Fila parada (carga sem rodar) não cresce sem fim; a carga noturna por data cobre o que ficar fora.
  select count(*) into v_pendentes
  from (
    select 1 from app.evento_origem e
    where e.tenant_id = v_tenant and e.origem = p_origem and e.processado_em is null
    limit 20000
  ) as pendente;
  if v_pendentes >= 20000 then
    raise exception 'fila de eventos cheia' using errcode = 'PT429';
  end if;

  insert into app.evento_origem (tenant_id, origem, id_evento, tipo_evento, ids)
  values (v_tenant, p_origem, p_id_evento, p_tipo_evento, p_ids)
  on conflict (tenant_id, origem, id_evento) do nothing;
  return true;
end;
$$;

revoke execute on function app.registrar_evento_origem(text, text, text, text, jsonb) from public, anon, authenticated;
grant usage on schema app to anon;
grant execute on function app.registrar_evento_origem(text, text, text, text, jsonb) to anon;

-- Com o schema app aberto para anon, função nova nasceria executável pela API. O execute de public é
-- padrão global e o Postgres não deixa tirar só por schema, então sai para toda função nova do dono das
-- migrations; quem precisar concede. O schema public do Supabase tem concessões próprias e não muda.
alter default privileges for role postgres revoke execute on functions from public;
