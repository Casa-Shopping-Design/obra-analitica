-- Registro de cada execução da carga, por tenant e endpoint. É a única fonte da data "última carga"
-- que as telas e a rota de saúde mostram.

create table app.carga_execucao (
  id bigserial primary key,
  tenant_id uuid not null references app.tenant(id) on delete cascade,
  endpoint text not null,
  iniciado_em timestamptz not null default now(),
  terminado_em timestamptz,
  registros_lidos integer,
  registros_novos integer,
  situacao text not null default 'executando' check (situacao in ('executando', 'ok', 'falha')),
  erro_resumo text,
  duracao_ms integer,
  check ((situacao = 'executando') = (terminado_em is null))
);

create index carga_execucao_tenant_terminado on app.carga_execucao (tenant_id, terminado_em desc);
create index carga_execucao_tenant_iniciado on app.carga_execucao (tenant_id, iniciado_em desc);

-- Só o carregador grava, com o dono do banco; o usuário logado lê as execuções do próprio tenant.
alter table app.carga_execucao enable row level security;
alter table app.carga_execucao force row level security;
create policy leitura_tenant on app.carga_execucao
  for select to authenticated
  using (tenant_id = (select app.tenant_atual()));
grant select on app.carga_execucao to authenticated;

-- A carga só conta como feita quando o staging foi recarregado. O carregador para no primeiro
-- endpoint que falha, então um endpoint "ok" isolado não prova que os números da tela mudaram.
create view marts.ultima_carga with (security_invoker = true) as
select tenant_id, max(terminado_em) as ultima_carga_em
from app.carga_execucao
where situacao = 'ok' and endpoint = 'staging'
group by tenant_id;

grant select on marts.ultima_carga to authenticated;

-- A rota de saúde roda sem login e o anônimo continua fora do schema app: a função fica em public,
-- executável por anon, e devolve só a carga mais atrasada entre os tenants ativos, sem dizer qual, e a
-- situação do staging mais recente. Tenant ativo sem carga nenhuma deixa a data nula.
-- O(t) em tenants, com duas buscas por índice em carga_execucao para cada um.
create function public.ultima_carga() returns table (concluida_em timestamptz, situacao text)
language sql stable security definer set search_path = '' as $$
  with por_tenant as (
    select
      (select max(ce.terminado_em)
       from app.carga_execucao ce
       where ce.tenant_id = t.id and ce.situacao = 'ok' and ce.endpoint = 'staging') as concluida,
      (select ce.situacao
       from app.carga_execucao ce
       where ce.tenant_id = t.id and ce.endpoint = 'staging'
       order by ce.iniciado_em desc
       limit 1) as recente
    from app.tenant t
    where t.status = 'ativo'
  )
  select
    case when bool_and(concluida is not null) then min(concluida) end,
    case
      when bool_or(recente = 'falha') then 'falha'
      when bool_or(recente = 'executando') then 'executando'
      when bool_and(recente = 'ok') then 'ok'
    end
  from por_tenant
$$;

revoke execute on function public.ultima_carga() from public, authenticated;
grant execute on function public.ultima_carga() to anon, authenticated;
