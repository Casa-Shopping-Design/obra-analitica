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

-- A rota de saúde roda sem login e o anônimo não lê tabela nenhuma. A função devolve só a data da
-- carga mais atrasada entre os tenants ativos, sem dizer qual; tenant sem carga nenhuma devolve nulo.
-- O(t) em tenants, com uma busca por índice em carga_execucao para cada um.
create function app.saude_carga() returns timestamptz
language sql stable security definer set search_path = '' as $$
  select case when bool_and(u.ultima is not null) then min(u.ultima) end
  from app.tenant t
  left join lateral (
    select max(ce.terminado_em) as ultima
    from app.carga_execucao ce
    where ce.tenant_id = t.id and ce.situacao = 'ok' and ce.endpoint = 'staging'
  ) u on true
  where t.status = 'ativo'
$$;

-- O anônimo passa a enxergar o schema app só para chamar a função acima. Toda função de app
-- já tem execute revogado de public. Função nova em app nasce executável por public e, daqui em
-- diante, pelo anônimo: a migration que a criar revoga no mesmo arquivo. Um "alter default
-- privileges in schema app revoke" não resolveria, porque o default por schema só soma ao global.
-- O teste carga_execucao.sql falha se alguma função de app ficar aberta ao anônimo.
grant usage on schema app to anon;
revoke execute on function app.saude_carga() from public;
grant execute on function app.saude_carga() to anon, authenticated;
