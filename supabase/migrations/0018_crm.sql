-- CRM de vendas como segunda origem, opcional por tenant (ver docs/decisoes/0006).
-- O carregador grava em raw.registro com endpoint 'crm/...' e já descarta dado pessoal por lista
-- de campos permitidos. Aqui só entra o que liga o CRM à obra e ao contrato do ERP.

-- O CRM devolve data vazia, '0000-00-00' e número como texto; um registro torto vira nulo em vez
-- de derrubar a recarga inteira do tenant.
create or replace function staging.data_crm(p_texto text) returns date
language plpgsql immutable set search_path = '' as $$
begin
  if p_texto is null or p_texto !~ '^\d{4}-\d{2}-\d{2}' or left(p_texto, 4) = '0000' then
    return null;
  end if;
  return left(p_texto, 10)::date;
exception when others then
  return null;
end $$;

create or replace function staging.momento_crm(p_texto text) returns timestamp
language plpgsql immutable set search_path = '' as $$
begin
  if p_texto is null or p_texto !~ '^\d{4}-\d{2}-\d{2}' or left(p_texto, 4) = '0000' then
    return null;
  end if;
  return p_texto::timestamp;
exception when others then
  return null;
end $$;

create or replace function staging.numero_crm(p_texto text) returns numeric
language plpgsql immutable set search_path = '' as $$
begin
  if p_texto is null or p_texto !~ '^-?\d{1,20}(\.\d{1,10})?$' then
    return null;
  end if;
  return p_texto::numeric;
exception when others then
  return null;
end $$;

-- Código interno vem como texto; só vira chave quando é número que cabe em integer.
create or replace function staging.inteiro_crm(p_texto text) returns integer
language sql immutable set search_path = '' as $$
  select case when btrim(p_texto) ~ '^\d{1,9}$' then btrim(p_texto)::integer end
$$;

revoke execute on function staging.data_crm(text), staging.momento_crm(text), staging.numero_crm(text),
  staging.inteiro_crm(text) from public, anon, authenticated;

-- unidade_id_origem e contrato_id_origem são as chaves do ERP; id_origem é o id do CRM.
create table staging.reserva (
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  id_origem integer not null,
  contrato_id_origem integer,
  unidade_id_origem integer,
  unidade text,
  situacao text,
  vendida boolean not null default false,
  data_cadastro date,
  data_venda date,
  data_cancelamento date,
  valor_contrato numeric,
  primary key (tenant_id, id_origem)
);
create index reserva_obra_cadastro_idx on staging.reserva (tenant_id, centro_custo_id, data_cadastro);
create index reserva_contrato_idx on staging.reserva (tenant_id, contrato_id_origem);

create table staging.repasse (
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  id_origem integer not null,
  reserva_id_origem integer,
  contrato_id_origem integer,
  unidade_id_origem integer,
  situacao text,
  banco text,
  data_assinatura date,
  data_recurso_liberado date,
  valor_financiado numeric,
  data_alteracao_situacao timestamp,
  primary key (tenant_id, id_origem)
);
create index repasse_obra_idx on staging.repasse (tenant_id, centro_custo_id);
create index repasse_contrato_idx on staging.repasse (tenant_id, contrato_id_origem);
-- O repasse sem reserva ligada procura o contrato do ERP pelo número.
create index if not exists contrato_venda_numero_idx on staging.contrato_venda (tenant_id, numero, data_venda desc);

-- Lead só entra contado por dia, obra, origem, mídia e situação; o lead individual fica no raw,
-- sem nome, contato nem documento, e não sai de lá.
create table staging.lead_diario (
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  dia date not null,
  origem text not null,
  midia text not null,
  situacao text not null,
  motivo_cancelamento text not null,
  leads integer not null,
  primary key (tenant_id, centro_custo_id, dia, origem, midia, situacao, motivo_cancelamento)
);

do $$
declare t text;
begin
  foreach t in array array['reserva', 'repasse', 'lead_diario'] loop
    execute format('alter table staging.%I enable row level security', t);
    execute format('alter table staging.%I force row level security', t);
    execute format($p$create policy leitura_por_obra on staging.%I for select to authenticated
      using (tenant_id = app.tenant_atual() and centro_custo_id in (select app.obras_permitidas()))$p$, t);
    execute format('grant select on staging.%I to authenticated', t);
  end loop;
end $$;

-- Recarrega o staging do CRM a partir do raw. Roda depois de staging.recarregar, porque liga
-- reserva e repasse ao contrato do ERP já carregado. O raw acumula uma versão por mudança
-- (hash diferente); vale a de referencia_data mais nova, e ativo = 'N' é registro apagado no CRM.
-- Com contrato ligado, a obra vem do ERP: um empreendimento do CRM pode cobrir mais de uma obra do
-- ERP, e a linha não pode levar dado de contrato para o gerente de outra obra.
-- O(n log n) em registros do CRM pelo distinct on; uma instrução por tabela, junções por índice.
create or replace function staging.recarregar_crm(p_tenant uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  -- Duas recargas do mesmo tenant ao mesmo tempo bateriam na chave primária; a segunda espera.
  perform pg_advisory_xact_lock(hashtextextended('recarga:' || p_tenant::text, 0));
  delete from staging.repasse where tenant_id = p_tenant;
  delete from staging.reserva where tenant_id = p_tenant;
  delete from staging.lead_diario where tenant_id = p_tenant;

  insert into staging.reserva
    (tenant_id, centro_custo_id, id_origem, contrato_id_origem, unidade_id_origem, unidade, situacao,
     vendida, data_cadastro, data_venda, data_cancelamento, valor_contrato)
  with versao as (
    select distinct on ((r.payload->>'idreserva')::integer) r.payload
    from raw.registro r
    where r.tenant_id = p_tenant and r.endpoint = 'crm/reservas' and r.payload->>'idreserva' ~ '^\d{1,9}$'
    order by (r.payload->>'idreserva')::integer, r.payload->>'referencia_data' desc nulls last, r.id desc
  ), vinculo as (
    select distinct on ((r.payload->>'idreserva')::integer)
      (r.payload->>'idreserva')::integer as idreserva, r.payload->>'ativo' as ativo,
      staging.inteiro_crm(r.payload->>'codigointerno') as contrato
    from raw.registro r
    where r.tenant_id = p_tenant and r.endpoint = 'crm/reservas/vinculo_erp' and r.payload->>'idreserva' ~ '^\d{1,9}$'
    order by (r.payload->>'idreserva')::integer, r.payload->>'referencia_data' desc nulls last, r.id desc
  )
  select p_tenant, coalesce(cv.centro_custo_id, cc.id), (v.payload->>'idreserva')::integer, cv.id_origem,
    coalesce(cv.unidade_id_origem, u.id_origem), v.payload->>'unidade', v.payload->>'situacao',
    coalesce(v.payload->>'venda', '') in ('Sim', 'S') or staging.data_crm(v.payload->>'data_venda') is not null,
    staging.data_crm(v.payload->>'data_cad'), staging.data_crm(v.payload->>'data_venda'),
    staging.data_crm(v.payload->>'data_cancelamento'), staging.numero_crm(v.payload->>'valor_contrato')
  from versao v
  left join vinculo vc on vc.idreserva = (v.payload->>'idreserva')::integer and vc.ativo is distinct from 'N'
  left join app.centro_custo cc
    on cc.tenant_id = p_tenant and cc.id_origem = staging.inteiro_crm(v.payload->>'codigointerno_empreendimento')
  -- O vínculo com o ERP é a fonte preferida; o código interno da própria reserva é a segunda.
  left join staging.contrato_venda cv
    on cv.tenant_id = p_tenant
   and cv.id_origem = coalesce(vc.contrato, staging.inteiro_crm(v.payload->>'codigointerno'))
  -- Reserva ainda sem contrato acha a unidade do ERP pelo nome dentro da obra.
  left join lateral (
    select un.id_origem
    from staging.unidade un
    where cv.id_origem is null and un.tenant_id = p_tenant and un.centro_custo_id = cc.id
      and un.nome = v.payload->>'unidade'
    order by un.id_origem
    limit 1
  ) u on true
  where v.payload->>'ativo' is distinct from 'N'
    and coalesce(cv.centro_custo_id, cc.id) is not null;

  insert into staging.repasse
    (tenant_id, centro_custo_id, id_origem, reserva_id_origem, contrato_id_origem, unidade_id_origem,
     situacao, banco, data_assinatura, data_recurso_liberado, valor_financiado, data_alteracao_situacao)
  with versao as (
    select distinct on ((r.payload->>'idrepasse')::integer) r.payload
    from raw.registro r
    where r.tenant_id = p_tenant and r.endpoint = 'crm/repasses' and r.payload->>'idrepasse' ~ '^\d{1,9}$'
    order by (r.payload->>'idrepasse')::integer, r.payload->>'referencia_data' desc nulls last, r.id desc
  )
  select p_tenant, coalesce(cv.centro_custo_id, cn.centro_custo_id, cc.id, rs.centro_custo_id), (v.payload->>'idrepasse')::integer,
    staging.inteiro_crm(v.payload->>'reserva'),
    coalesce(cv.id_origem, cn.id_origem),
    coalesce(cv.unidade_id_origem, cn.unidade_id_origem),
    v.payload->>'situacao', v.payload->>'banco',
    staging.data_crm(v.payload->>'data_assinatura_de_contrato'),
    staging.data_crm(v.payload->>'data_recurso_liberado'),
    coalesce(staging.numero_crm(v.payload->>'valor_financiado'), staging.numero_crm(v.payload->>'valor_previsto')),
    staging.momento_crm(v.payload->>'data_alteracao_status')
  from versao v
  left join app.centro_custo cc
    on cc.tenant_id = p_tenant and cc.id_origem = staging.inteiro_crm(v.payload->>'codigointerno_empreendimento')
  left join staging.reserva rs
    on rs.tenant_id = p_tenant and rs.id_origem = staging.inteiro_crm(v.payload->>'reserva')
  left join staging.contrato_venda cv
    on cv.tenant_id = p_tenant and cv.id_origem = rs.contrato_id_origem
  -- Sem reserva ligada, tenta o número do contrato do repasse contra o número do contrato no ERP.
  left join lateral (
    select c.id_origem, c.centro_custo_id, c.unidade_id_origem
    from staging.contrato_venda c
    where cv.id_origem is null and c.tenant_id = p_tenant and c.numero = v.payload->>'numero_contrato'
    order by c.data_venda desc nulls last
    limit 1
  ) cn on true
  where v.payload->>'ativo' is distinct from 'N'
    and coalesce(cv.centro_custo_id, cn.centro_custo_id, cc.id, rs.centro_custo_id) is not null;

  -- O campo pode listar mais de um empreendimento ("101;102"); o lead conta uma vez em cada obra.
  insert into staging.lead_diario
    (tenant_id, centro_custo_id, dia, origem, midia, situacao, motivo_cancelamento, leads)
  with versao as (
    select distinct on ((r.payload->>'idlead')::integer) r.payload
    from raw.registro r
    where r.tenant_id = p_tenant and r.endpoint = 'crm/leads' and r.payload->>'idlead' ~ '^\d{1,9}$'
    order by (r.payload->>'idlead')::integer, r.payload->>'referencia_data' desc nulls last, r.id desc
  )
  select p_tenant, cc.id, staging.data_crm(v.payload->>'data_cad') as dia,
    coalesce(nullif(v.payload->>'origem_nome', ''), nullif(v.payload->>'origem', ''), 'Não informada'),
    coalesce(nullif(v.payload->>'midia_original', ''), 'Não informada'),
    coalesce(nullif(v.payload->>'situacao', ''), 'Não informada'),
    coalesce(nullif(v.payload->>'motivo_cancelamento', ''), 'Sem cancelamento'),
    count(distinct (v.payload->>'idlead')::integer)
  from versao v
  cross join lateral regexp_split_to_table(coalesce(v.payload->>'codigointerno_empreendimento', ''), '\s*[;,]\s*') as codigo
  join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = staging.inteiro_crm(codigo)
  where v.payload->>'ativo' is distinct from 'N' and staging.data_crm(v.payload->>'data_cad') is not null
  group by 1, 2, 3, 4, 5, 6, 7;
end $$;

revoke execute on function staging.recarregar_crm(uuid) from public, anon, authenticated;

-- Repasse real por obra. Etapa sai das datas do CRM, não do nome da situação, que muda de cliente
-- para cliente: com recurso liberado, liberado; com contrato assinado no banco, assinado; senão, em
-- análise. Atrasado não é etapa, é marca: sem recurso liberado e com a parcela FI já vencida e em
-- aberto no ERP. O valor do ERP segue a regra do fluxo de caixa (saldo corrigido, sem distrato).
-- O(r + p) por obra, com r repasses e p parcelas FI: uma agregação por contrato e uma por obra.
create or replace view marts.repasse_obra with (security_invoker = true) as
with contrato_fi as (
  select p.tenant_id, p.centro_custo_id, p.contrato_id_origem,
    sum(coalesce(p.saldo_corrigido, p.saldo)) filter (where p.vencimento >= current_date) as a_receber,
    sum(coalesce(p.saldo_corrigido, p.saldo)) filter (where p.vencimento < current_date) as vencido
  from staging.parcela_receber p
  left join staging.contrato_venda c on c.tenant_id = p.tenant_id and c.id_origem = p.contrato_id_origem
  where p.origem = 'repasse' and c.situacao is distinct from '3'
  group by 1, 2, 3
), repasse_atual as (
  -- Contrato com mais de um repasse no CRM (um cancelado e outro novo) vale pelo mais recente.
  select distinct on (r.tenant_id, coalesce(r.contrato_id_origem, -r.id_origem)) r.*
  from staging.repasse r
  left join staging.contrato_venda c on c.tenant_id = r.tenant_id and c.id_origem = r.contrato_id_origem
  where c.situacao is distinct from '3'
  order by r.tenant_id, coalesce(r.contrato_id_origem, -r.id_origem), r.data_alteracao_situacao desc nulls last, r.id_origem desc
), repasse_etapa as (
  select r.tenant_id, r.centro_custo_id, r.contrato_id_origem, r.valor_financiado,
    r.data_assinatura, r.data_recurso_liberado,
    case when r.data_recurso_liberado is not null then 'liberado'
         when r.data_assinatura is not null then 'assinado'
         else 'em_analise' end as etapa,
    r.data_recurso_liberado is null and coalesce(f.vencido, 0) > 0 as atrasado,
    coalesce(f.a_receber, 0) + coalesce(f.vencido, 0) as em_aberto_origem
  from repasse_atual r
  left join contrato_fi f on f.tenant_id = r.tenant_id and f.contrato_id_origem = r.contrato_id_origem
), por_obra as (
  select tenant_id, centro_custo_id,
    count(distinct contrato_id_origem) as contratos_com_repasse,
    count(*) filter (where etapa = 'em_analise') as repasses_em_analise,
    coalesce(sum(valor_financiado) filter (where etapa = 'em_analise'), 0) as valor_em_analise,
    count(*) filter (where etapa = 'assinado') as repasses_assinados,
    coalesce(sum(valor_financiado) filter (where etapa = 'assinado'), 0) as valor_assinado,
    count(*) filter (where etapa = 'liberado') as repasses_liberados,
    coalesce(sum(valor_financiado) filter (where etapa = 'liberado'), 0) as valor_liberado,
    count(*) filter (where atrasado) as repasses_atrasados,
    coalesce(sum(valor_financiado) filter (where atrasado), 0) as valor_atrasado,
    round(avg(data_recurso_liberado - data_assinatura)
      filter (where data_recurso_liberado is not null and data_assinatura is not null), 1) as dias_medios_assinatura_liberacao,
    coalesce(sum(em_aberto_origem) filter (where etapa = 'liberado'), 0) as liberado_sem_baixa_origem
  from repasse_etapa
  group by 1, 2
), fi_obra as (
  select tenant_id, centro_custo_id,
    count(*) as contratos_financiados_origem,
    coalesce(sum(a_receber), 0) as a_receber_repasse_origem,
    coalesce(sum(vencido), 0) as repasse_atrasado_origem
  from contrato_fi
  group by 1, 2
), sem_repasse as (
  select f.tenant_id, f.centro_custo_id, count(*) as contratos_sem_repasse
  from contrato_fi f
  where not exists (
    select 1 from staging.repasse r
    where r.tenant_id = f.tenant_id and r.contrato_id_origem = f.contrato_id_origem
  )
  group by 1, 2
)
select cc.tenant_id, cc.id as centro_custo_id, cc.nome as obra,
  coalesce(fo.contratos_financiados_origem, 0) as contratos_financiados_origem,
  p.contratos_com_repasse,
  coalesce(s.contratos_sem_repasse, 0) as contratos_sem_repasse,
  p.repasses_em_analise, p.valor_em_analise,
  p.repasses_assinados, p.valor_assinado,
  p.repasses_liberados, p.valor_liberado,
  p.repasses_atrasados, p.valor_atrasado,
  p.dias_medios_assinatura_liberacao,
  coalesce(fo.a_receber_repasse_origem, 0) as a_receber_repasse_origem,
  coalesce(fo.repasse_atrasado_origem, 0) as repasse_atrasado_origem,
  p.liberado_sem_baixa_origem
from por_obra p
join app.centro_custo cc on cc.tenant_id = p.tenant_id and cc.id = p.centro_custo_id
left join fi_obra fo on fo.tenant_id = p.tenant_id and fo.centro_custo_id = p.centro_custo_id
left join sem_repasse s on s.tenant_id = p.tenant_id and s.centro_custo_id = p.centro_custo_id;

grant select on marts.repasse_obra to authenticated;

-- Funil por obra e mês, só para obra com dado do CRM. Lead e reserva vêm do CRM; venda e distrato
-- vêm do ERP, com a mesma regra da marts.vso_mensal, para o funil fechar com o VSO da tela.
-- Conversão do mês é razão entre contagens do mesmo mês, não coorte: a reserva de março pode vir
-- de lead de janeiro.
-- O(l + s + c + m) por obra: uma agregação por fonte e um calendário de m meses.
create or replace view marts.funil_vendas_mensal with (security_invoker = true) as
with obras_crm as (
  select tenant_id, centro_custo_id from staging.lead_diario
  union
  select tenant_id, centro_custo_id from staging.reserva
), leads as (
  select tenant_id, centro_custo_id, date_trunc('month', dia)::date as competencia, sum(leads) as leads
  from staging.lead_diario
  group by 1, 2, 3
), reservas as (
  select tenant_id, centro_custo_id, date_trunc('month', data_cadastro)::date as competencia, count(*) as reservas
  from staging.reserva
  where data_cadastro is not null
  group by 1, 2, 3
), reservas_canceladas as (
  select tenant_id, centro_custo_id, date_trunc('month', data_cancelamento)::date as competencia,
    count(*) as reservas_canceladas
  from staging.reserva
  where data_cancelamento is not null
  group by 1, 2, 3
), contratos as (
  select tenant_id, centro_custo_id, data_venda,
    case when situacao = '3' then coalesce(data_distrato, data_venda) end as data_cancelamento
  from staging.contrato_venda
  where data_venda is not null and situacao in ('1', '3')
), vendas as (
  select tenant_id, centro_custo_id, date_trunc('month', data_venda)::date as competencia, count(*) as vendas
  from contratos
  group by 1, 2, 3
), distratos as (
  select tenant_id, centro_custo_id, date_trunc('month', data_cancelamento)::date as competencia, count(*) as distratos
  from contratos
  where data_cancelamento is not null
  group by 1, 2, 3
), inicio as (
  select o.tenant_id, o.centro_custo_id, min(e.competencia) as primeiro_mes
  from obras_crm o
  join (
    select tenant_id, centro_custo_id, competencia from leads
    union all select tenant_id, centro_custo_id, competencia from reservas
    union all select tenant_id, centro_custo_id, competencia from vendas
  ) e on e.tenant_id = o.tenant_id and e.centro_custo_id = o.centro_custo_id
  group by 1, 2
), calendario as (
  select i.tenant_id, i.centro_custo_id, competencia::date as competencia
  from inicio i,
  lateral generate_series(i.primeiro_mes, date_trunc('month', current_date), interval '1 month') as competencia
)
select c.tenant_id, c.centro_custo_id, c.competencia,
  coalesce(l.leads, 0)::integer as leads,
  coalesce(r.reservas, 0)::integer as reservas,
  coalesce(rc.reservas_canceladas, 0)::integer as reservas_canceladas,
  coalesce(v.vendas, 0)::integer as vendas,
  coalesce(d.distratos, 0)::integer as distratos,
  case when coalesce(l.leads, 0) > 0 then round(coalesce(r.reservas, 0)::numeric / l.leads, 4) end as conversao_lead_reserva,
  case when coalesce(r.reservas, 0) > 0 then round(coalesce(v.vendas, 0)::numeric / r.reservas, 4) end as conversao_reserva_venda
from calendario c
left join leads l on l.tenant_id = c.tenant_id and l.centro_custo_id = c.centro_custo_id and l.competencia = c.competencia
left join reservas r on r.tenant_id = c.tenant_id and r.centro_custo_id = c.centro_custo_id and r.competencia = c.competencia
left join reservas_canceladas rc
  on rc.tenant_id = c.tenant_id and rc.centro_custo_id = c.centro_custo_id and rc.competencia = c.competencia
left join vendas v on v.tenant_id = c.tenant_id and v.centro_custo_id = c.centro_custo_id and v.competencia = c.competencia
left join distratos d on d.tenant_id = c.tenant_id and d.centro_custo_id = c.centro_custo_id and d.competencia = c.competencia;

grant select on marts.funil_vendas_mensal to authenticated;
