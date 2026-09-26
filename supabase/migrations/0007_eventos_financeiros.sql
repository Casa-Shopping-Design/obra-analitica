-- Eventos financeiros por linha: cada recebimento, cada pagamento e cada parte do rateio de um título
-- vira uma linha no staging, e o que não tem obra vai para o centro "Despesas sem obra" do tenant.
-- Contrato: docs/financeiro/contrato_dados.md, seção 3.1. Decisão: docs/decisoes/0002-eventos-financeiros.md.

-- Data de referência das views. Testes e reprocessamento fixam o dia por set_config; o usuário da API
-- não alcança set_config porque pg_catalog não é exposto.
create function app.data_referencia() returns date
language sql stable security invoker set search_path = '' as $$
  select coalesce(nullif(current_setting('app.data_referencia', true), '')::date,
                  (now() at time zone 'America/Sao_Paulo')::date)
$$;
revoke execute on function app.data_referencia() from public, anon;
grant execute on function app.data_referencia() to authenticated, service_role;

-- Centro de custo da empresa: recebe título e parcela sem obra cadastrada. Gerente não tem vínculo com ele,
-- então só diretor e financeiro o enxergam pela regra de app.obras_permitidas().
alter table app.centro_custo add column tipo text not null default 'obra' check (tipo in ('obra', 'empresa'));
alter table app.centro_custo alter column id_origem drop not null;
alter table app.centro_custo add constraint centro_custo_tipo_origem
  check ((tipo = 'obra' and id_origem is not null) or (tipo = 'empresa' and id_origem is null));
create unique index centro_custo_empresa_unico on app.centro_custo (tenant_id) where tipo = 'empresa';
create index centro_custo_tenant_tipo on app.centro_custo (tenant_id, tipo);

insert into app.centro_custo (tenant_id, id_origem, nome, tipo)
select id, null, 'Despesas sem obra', 'empresa' from app.tenant
on conflict (tenant_id) where tipo = 'empresa' do nothing;

-- Auditoria comum das tabelas de complemento manual (0011 e 0012 usam os mesmos gatilhos).
create table app.auditoria_alteracao (
  id bigserial primary key,
  tenant_id uuid not null,
  tabela text not null,
  registro_id text not null,
  operacao text not null check (operacao in ('insert', 'update', 'delete')),
  antes jsonb,
  depois jsonb,
  autor uuid,
  alterado_em timestamptz not null default now()
);
create index auditoria_alteracao_registro on app.auditoria_alteracao (tenant_id, tabela, registro_id, alterado_em desc);

alter table app.auditoria_alteracao enable row level security;
alter table app.auditoria_alteracao force row level security;
create policy leitura_diretor_financeiro on app.auditoria_alteracao
  for select to authenticated
  using (tenant_id = (select app.tenant_atual()) and (select app.perfil_atual()) in ('diretor', 'financeiro'));
grant select on app.auditoria_alteracao to authenticated;

-- security definer porque o usuário não tem insert na auditoria; TG_ARGV traz as colunas da chave.
create function app.registrar_auditoria() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  linha jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
begin
  insert into app.auditoria_alteracao (tenant_id, tabela, registro_id, operacao, antes, depois, autor)
  values (
    (linha ->> 'tenant_id')::uuid,
    tg_table_schema || '.' || tg_table_name,
    (select string_agg(linha ->> chave.coluna, '|' order by chave.posicao)
     from unnest(tg_argv) with ordinality as chave(coluna, posicao)),
    lower(tg_op),
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end,
    auth.uid()
  );
  return null;
end $$;
revoke execute on function app.registrar_auditoria() from public, anon, authenticated;

-- O autor mandado pelo usuário logado é sempre trocado pelo do JWT. Sem JWT (carregador ou dono
-- do banco) o valor informado fica, para a carga poder gravar mapeamentos iniciais.
create function app.definir_autor() returns trigger
language plpgsql security invoker set search_path = '' as $$
declare
  ajuste jsonb := '{}'::jsonb;
begin
  if auth.uid() is not null or current_user in ('authenticated', 'anon') then
    ajuste := jsonb_build_object('autor', auth.uid());
  end if;
  if to_jsonb(new) ? 'atualizado_em' then
    ajuste := ajuste || jsonb_build_object('atualizado_em', now());
  end if;
  new := jsonb_populate_record(new, ajuste);
  return new;
end $$;
revoke execute on function app.definir_autor() from public, anon, authenticated;

-- Única implementação da situação da parcela; 0011 e 0012 chamam esta função.
create function app.situacao_parcela(p_saldo numeric, p_valor_recebido numeric, p_vencimento date,
                                     p_contrato_distratado boolean, p_referencia date) returns text
language sql immutable security invoker set search_path = '' as $$
  select case
    when coalesce(p_saldo, 0) > 0 and p_contrato_distratado then 'cancelada_distrato'
    when coalesce(p_saldo, 0) > 0 and p_vencimento < p_referencia then 'vencida'
    when coalesce(p_saldo, 0) > 0 then 'a_vencer'
    when coalesce(p_valor_recebido, 0) > 0 then 'quitada'
    else 'baixada_sem_recebimento'
  end
$$;
revoke execute on function app.situacao_parcela(numeric, numeric, date, boolean, date) from public, anon;
grant execute on function app.situacao_parcela(numeric, numeric, date, boolean, date) to authenticated, service_role;

create index registro_tenant_carregado on raw.registro (tenant_id, carregado_em desc);

-- security definer porque raw não é legível pelo usuário; devolve só o carimbo do tenant de quem chama.
create function app.situacao_carga()
returns table (data_referencia date, ultima_carga_em timestamptz, horas_desde_carga numeric(9,1), desatualizada boolean)
language sql stable security definer set search_path = '' as $$
  select app.data_referencia(),
         u.ultima,
         round(extract(epoch from now() - u.ultima) / 3600, 1)::numeric(9,1),
         u.ultima is null or now() - u.ultima > interval '26 hours'
  from (select max(r.carregado_em) as ultima from raw.registro r where r.tenant_id = app.tenant_atual()) u
$$;
revoke execute on function app.situacao_carga() from public, anon;
grant execute on function app.situacao_carga() to authenticated;

-- Contrato de venda: financiamento e crédito associativo; todas as unidades do contrato em tabela própria.
alter table staging.contrato_venda
  add column valor_financiado numeric(18,2),
  add column credito_associativo boolean;
create index contrato_venda_obra_data on staging.contrato_venda (tenant_id, centro_custo_id, data_venda);

create table staging.contrato_unidade (
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  contrato_id_origem integer not null,
  sequencia integer not null,
  unidade_id_origem integer not null,
  principal boolean not null,
  primary key (tenant_id, contrato_id_origem, sequencia)
);
create index contrato_unidade_obra on staging.contrato_unidade (tenant_id, centro_custo_id);
create index contrato_unidade_unidade on staging.contrato_unidade (tenant_id, unidade_id_origem);

-- Parcela: valor_recebido passa a ser a soma dos recebimentos; parcela de obra não cadastrada vai para a empresa.
alter table staging.parcela_receber
  add column data_emissao date,
  add column numero_parcela text,
  add column conta_origem text,
  add column id_origem_obra integer,
  add column motivo_sem_obra text,
  add column valor_baixado_sem_caixa numeric(18,2) not null default 0;

create table staging.recebimento (
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  contrato_id_origem integer not null,
  parcela_id_origem integer not null,
  sequencia integer not null,
  data_recebimento date not null,
  valor numeric(18,2) not null,
  origem text not null,
  tipo_condicao text,
  tipo_operacao_origem text,
  tipo_baixa text not null check (tipo_baixa in ('recebimento', 'estorno', 'baixa_sem_caixa')),
  primary key (tenant_id, contrato_id_origem, parcela_id_origem, sequencia)
);
create index recebimento_obra_data on staging.recebimento (tenant_id, centro_custo_id, data_recebimento);

-- Título: o cabeçalho deixa de ser lido pelo usuário; obra, valor e pagamento vêm das apropriações.
alter table staging.titulo_pagar alter column centro_custo_id drop not null;
alter table staging.titulo_pagar
  add column empresa_id_origem integer,
  add column data_emissao date,
  add column valor_pago numeric(18,2) not null default 0,
  add column ajuste_baixa numeric(18,2) not null default 0,
  add column quantidade_apropriacoes integer not null default 1;
alter table staging.titulo_pagar alter column quantidade_apropriacoes drop default;
revoke select on staging.titulo_pagar from authenticated;

create table staging.titulo_pagar_apropriacao (
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  titulo_id_origem integer not null,
  sequencia_obra integer not null,
  sequencia_conta integer not null,
  id_origem_obra integer,
  motivo_sem_obra text check (motivo_sem_obra in ('sem_rateio_na_origem', 'rateio_sem_valor', 'obra_nao_cadastrada')),
  conta_origem text,
  percentual numeric(9,6) not null,
  principal boolean not null,
  valor_original numeric(18,2) not null,
  valor_pago numeric(18,2) not null,
  ajuste_baixa numeric(18,2) not null,
  saldo numeric(18,2) not null,
  vencimento date not null,
  data_competencia date,
  data_ultimo_pagamento date,
  primary key (tenant_id, titulo_id_origem, sequencia_obra, sequencia_conta)
);
create index apropriacao_obra_vencimento on staging.titulo_pagar_apropriacao (tenant_id, centro_custo_id, vencimento);
create index apropriacao_obra_competencia on staging.titulo_pagar_apropriacao (tenant_id, centro_custo_id, data_competencia);
create index apropriacao_conta on staging.titulo_pagar_apropriacao (tenant_id, conta_origem);

create table staging.pagamento (
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  titulo_id_origem integer not null,
  sequencia_pagamento integer not null,
  sequencia_obra integer not null,
  sequencia_conta integer not null,
  data_pagamento date not null,
  valor numeric(18,2) not null,
  conta_origem text,
  primary key (tenant_id, titulo_id_origem, sequencia_pagamento, sequencia_obra, sequencia_conta)
);
create index pagamento_obra_data on staging.pagamento (tenant_id, centro_custo_id, data_pagamento);

do $$
declare t text;
begin
  foreach t in array array['contrato_unidade', 'recebimento', 'titulo_pagar_apropriacao', 'pagamento'] loop
    execute format('alter table staging.%I enable row level security', t);
    execute format('alter table staging.%I force row level security', t);
    execute format($p$create policy leitura_por_obra on staging.%I for select to authenticated
      using (tenant_id = (select app.tenant_atual()) and centro_custo_id in (select app.obras_permitidas()))$p$, t);
    execute format('grant select on staging.%I to authenticated', t);
  end loop;
end $$;

-- Recarga do staging a partir do raw, por tenant, apagando e regravando. Uma instrução por grupo de
-- tabelas, sem laço por linha: O(n log n) em registros da origem, pela ordenação das janelas do rateio.
-- jit desligado: o planejador estima 100 itens por lista jsonb, o custo passa do limite do JIT e a
-- compilação levava 2 s numa recarga que executa em menos de 150 ms.
create or replace function staging.recarregar(p_tenant uuid) returns void
language plpgsql security definer set search_path = '' set jit = off as $$
declare
  v_empresa uuid;
  v_recebimentos_sem_data bigint;
  v_pagamentos_sem_data bigint;
  v_titulos_sem_obra bigint;
begin
  insert into app.centro_custo (tenant_id, id_origem, nome, tipo)
  values (p_tenant, null, 'Despesas sem obra', 'empresa')
  on conflict (tenant_id) where tipo = 'empresa' do nothing;
  select cc.id into v_empresa from app.centro_custo cc where cc.tenant_id = p_tenant and cc.tipo = 'empresa';

  delete from staging.unidade where tenant_id = p_tenant;
  delete from staging.contrato_unidade where tenant_id = p_tenant;
  delete from staging.contrato_venda where tenant_id = p_tenant;
  delete from staging.recebimento where tenant_id = p_tenant;
  delete from staging.parcela_receber where tenant_id = p_tenant;
  delete from staging.pagamento where tenant_id = p_tenant;
  delete from staging.titulo_pagar_apropriacao where tenant_id = p_tenant;
  delete from staging.titulo_pagar where tenant_id = p_tenant;
  delete from staging.item_orcamento where tenant_id = p_tenant;

  insert into staging.unidade
  select p_tenant, cc.id, (r.payload->>'id')::int, r.payload->>'name', r.payload->>'propertyType',
         (r.payload->>'privateArea')::numeric, r.payload->>'commercialStock', (r.payload->>'deliveryDate')::date
  from raw.registro r
  join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = (r.payload->>'enterpriseId')::int
  where r.tenant_id = p_tenant and r.endpoint = 'units';

  -- Unidade principal: a marcada como main; sem marcação, a primeira da lista.
  with contrato as (
    select cc.id as centro_custo_id, r.payload as pl, (r.payload->>'id')::int as contrato_id
    from raw.registro r
    join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = (r.payload->>'enterpriseId')::int
    where r.tenant_id = p_tenant and r.endpoint = 'sales'
  ), unidade_contrato as (
    select c.centro_custo_id, c.contrato_id, u.posicao::int as sequencia, (u.item->>'id')::int as unidade_id,
           row_number() over (partition by c.contrato_id
                              order by coalesce(u.item->>'main' = 'true', false) desc, u.posicao) = 1 as principal
    from contrato c
    cross join lateral jsonb_array_elements(
      case when jsonb_typeof(c.pl->'units') = 'array' then c.pl->'units' else '[]'::jsonb end
    ) with ordinality as u(item, posicao)
    where u.item->>'id' is not null
  ), grava_unidades as (
    insert into staging.contrato_unidade (tenant_id, centro_custo_id, contrato_id_origem, sequencia, unidade_id_origem, principal)
    select p_tenant, uc.centro_custo_id, uc.contrato_id, uc.sequencia, uc.unidade_id, uc.principal
    from unidade_contrato uc
  )
  insert into staging.contrato_venda
    (tenant_id, centro_custo_id, id_origem, numero, data_venda, valor, situacao, data_distrato, banco_repasse,
     data_repasse, nome_cliente, unidade_id_origem, valor_financiado, credito_associativo)
  select p_tenant, c.centro_custo_id, c.contrato_id, c.pl->>'number', (c.pl->>'contractDate')::date,
         (c.pl->>'value')::numeric, c.pl->>'situation', (c.pl->>'cancellationDate')::date,
         c.pl->>'financialInstitutionNumber', (c.pl->>'financialInstitutionDate')::date,
         c.pl->'customers'->0->>'name',
         uc.unidade_id,
         case when jsonb_typeof(c.pl->'paymentConditions') = 'array' then
           coalesce((select sum((pc->>'totalValue')::numeric)
                     from jsonb_array_elements(c.pl->'paymentConditions') pc
                     where pc->>'conditionType' = 'FI'), 0)
         end,
         case c.pl->>'associativeCredit' when 'S' then true when 'N' then false end
  from contrato c
  left join unidade_contrato uc on uc.contrato_id = c.contrato_id and uc.principal;

  -- Recebimentos e parcelas numa instrução: a parcela já nasce com a soma dos seus recebimentos.
  with parcela as (
    select r.payload as pl,
           (r.payload->>'billId')::int as contrato_id,
           (r.payload->>'installmentId')::int as parcela_id,
           (r.payload->>'projectId')::int as id_origem_obra,
           coalesce(cc.id, v_empresa) as centro_custo_id,
           case when cc.id is null then 'obra_nao_cadastrada' end as motivo_sem_obra,
           r.payload->'paymentTerm'->>'id' as tipo_condicao
    from raw.registro r
    left join app.centro_custo cc
      on cc.tenant_id = p_tenant and cc.tipo = 'obra' and cc.id_origem = (r.payload->>'projectId')::int
    where r.tenant_id = p_tenant and r.endpoint = 'income'
  ), recebimento_bruto as (
    select p.contrato_id, p.parcela_id, p.centro_custo_id, p.tipo_condicao, x.posicao::int as sequencia,
           (x.item->>'paymentDate')::date as data_recebimento,
           coalesce(x.item->>'netAmount', x.item->>'amount')::numeric as valor,
           x.item->>'operationTypeName' as tipo_operacao_origem
    from parcela p
    cross join lateral jsonb_array_elements(
      case when jsonb_typeof(p.pl->'receipts') = 'array' then p.pl->'receipts' else '[]'::jsonb end
    ) with ordinality as x(item, posicao)
  ), recebimento as (
    select rb.*,
           case when rb.tipo_condicao = 'FI' then 'repasse' else 'direta' end as origem,
           case when rb.valor < 0 then 'estorno' else 'recebimento' end as tipo_baixa
    from recebimento_bruto rb
    where rb.data_recebimento is not null and rb.valor is not null
  ), grava_recebimentos as (
    insert into staging.recebimento
      (tenant_id, centro_custo_id, contrato_id_origem, parcela_id_origem, sequencia, data_recebimento, valor,
       origem, tipo_condicao, tipo_operacao_origem, tipo_baixa)
    select p_tenant, rc.centro_custo_id, rc.contrato_id, rc.parcela_id, rc.sequencia, rc.data_recebimento, rc.valor,
           rc.origem, rc.tipo_condicao, rc.tipo_operacao_origem, rc.tipo_baixa
    from recebimento rc
  ), total_recebido as (
    select rc.contrato_id, rc.parcela_id,
           sum(rc.valor) filter (where rc.tipo_baixa in ('recebimento', 'estorno')) as valor_recebido,
           max(rc.data_recebimento) filter (where rc.tipo_baixa in ('recebimento', 'estorno')) as data_recebimento,
           sum(rc.valor) filter (where rc.tipo_baixa = 'baixa_sem_caixa') as valor_baixado_sem_caixa
    from recebimento rc
    group by rc.contrato_id, rc.parcela_id
  ), grava_parcelas as (
    insert into staging.parcela_receber
      (tenant_id, centro_custo_id, id_origem, contrato_id_origem, vencimento, valor_original, saldo, saldo_corrigido,
       tipo_condicao, inadimplente, data_recebimento, valor_recebido, data_emissao, numero_parcela, conta_origem,
       id_origem_obra, motivo_sem_obra, valor_baixado_sem_caixa)
    select p_tenant, p.centro_custo_id, p.parcela_id, p.contrato_id, (p.pl->>'dueDate')::date,
           (p.pl->>'originalAmount')::numeric, (p.pl->>'balanceAmount')::numeric,
           (p.pl->>'correctedBalanceAmount')::numeric, p.tipo_condicao, p.pl->>'defaulterSituation' = 'S',
           tr.data_recebimento, coalesce(tr.valor_recebido, 0),
           (p.pl->>'issueDate')::date, p.pl->>'installmentNumber',
           case when jsonb_typeof(p.pl->'receiptsCategories') = 'array'
                 and jsonb_array_length(p.pl->'receiptsCategories') = 1
                then p.pl->'receiptsCategories'->0->>'financialCategoryId' end,
           p.id_origem_obra, p.motivo_sem_obra, coalesce(tr.valor_baixado_sem_caixa, 0)
    from parcela p
    left join total_recebido tr on tr.contrato_id = p.contrato_id and tr.parcela_id = p.parcela_id
  )
  select count(*) filter (where rb.data_recebimento is null or rb.valor is null) into v_recebimentos_sem_data
  from recebimento_bruto rb;

  -- Rateio do título por obra e por conta. Cada valor V do título é repartido com round(V * p, 2) e a
  -- apropriação principal fica com o resto, então a soma das partes é sempre V. Pagamentos são
  -- repartidos pelo acumulado, para o título quitado fechar centavo a centavo em cada obra.
  with titulo as (
    select r.payload as pl,
           (r.payload->>'billId')::int as titulo_id,
           (r.payload->>'originalAmount')::numeric as valor_original,
           (r.payload->>'balanceAmount')::numeric as saldo_origem,
           (r.payload->>'dueDate')::date as vencimento,
           (r.payload->>'issueDate')::date as data_emissao,
           case when jsonb_typeof(r.payload->'buildingsCosts') = 'array'
                then jsonb_array_length(r.payload->'buildingsCosts') else 0 end as itens_rateio
    from raw.registro r
    where r.tenant_id = p_tenant and r.endpoint = 'outcome'
  ), obra_bruta as (
    select t.titulo_id, o.posicao::int as sequencia_obra, (o.item->>'buildingId')::int as id_origem_obra,
           (o.item->>'rate')::numeric as taxa, (o.item->>'amount')::numeric as valor
    from titulo t
    cross join lateral jsonb_array_elements(
      case when t.itens_rateio > 0 then t.pl->'buildingsCosts' else '[]'::jsonb end
    ) with ordinality as o(item, posicao)
  ), obra_peso as (
    -- percentual da origem só vale quando todos os itens o trazem; senão um item sem percentual sumiria do rateio
    select ob.titulo_id, ob.sequencia_obra, ob.id_origem_obra,
           case when bool_and(ob.taxa is not null) over (partition by ob.titulo_id) then ob.taxa else ob.valor end as peso
    from obra_bruta ob
  ), obra as (
    select op.titulo_id, op.sequencia_obra, op.id_origem_obra,
           op.peso / sum(op.peso) over (partition by op.titulo_id) as p_obra,
           null::text as motivo_sem_obra
    from obra_peso op
    where op.peso > 0
    union all
    select t.titulo_id, 1, null, 1::numeric,
           case when t.itens_rateio > 0 then 'rateio_sem_valor' else 'sem_rateio_na_origem' end
    from titulo t
    where not exists (select 1 from obra_peso op where op.titulo_id = t.titulo_id and op.peso > 0)
  ), obra_centro as (
    select o.titulo_id, o.sequencia_obra, o.id_origem_obra, o.p_obra,
           coalesce(cc.id, v_empresa) as centro_custo_id,
           coalesce(o.motivo_sem_obra, case when cc.id is null then 'obra_nao_cadastrada' end) as motivo_sem_obra
    from obra o
    left join app.centro_custo cc
      on cc.tenant_id = p_tenant and cc.tipo = 'obra' and cc.id_origem = o.id_origem_obra
  ), conta_bruta as (
    select t.titulo_id, c.posicao::int as sequencia_conta, c.item->>'financialCategoryId' as conta_origem,
           (c.item->>'financialCategoryRate')::numeric as peso
    from titulo t
    cross join lateral jsonb_array_elements(
      case when jsonb_typeof(t.pl->'paymentsCategories') = 'array' then t.pl->'paymentsCategories' else '[]'::jsonb end
    ) with ordinality as c(item, posicao)
  ), conta as (
    select cb.titulo_id, cb.sequencia_conta, cb.conta_origem,
           cb.peso / sum(cb.peso) over (partition by cb.titulo_id) as p_conta
    from conta_bruta cb
    where cb.peso > 0
    union all
    select t.titulo_id, 1, null, 1::numeric
    from titulo t
    where not exists (select 1 from conta_bruta cb where cb.titulo_id = t.titulo_id and cb.peso > 0)
  ), apropriacao as (
    select oc.titulo_id, oc.sequencia_obra, c.sequencia_conta, oc.centro_custo_id, oc.id_origem_obra,
           oc.motivo_sem_obra, c.conta_origem, oc.p_obra * c.p_conta as p,
           row_number() over (partition by oc.titulo_id
                              order by oc.p_obra * c.p_conta desc, oc.sequencia_obra, c.sequencia_conta) = 1 as principal,
           count(*) over (partition by oc.titulo_id) as quantidade
    from obra_centro oc
    join conta c on c.titulo_id = oc.titulo_id
  ), pagamento_bruto as (
    select t.titulo_id, pg.posicao::int as sequencia_pagamento,
           (pg.item->>'paymentDate')::date as data_pagamento,
           coalesce(pg.item->>'netAmount', pg.item->>'amount')::numeric as valor
    from titulo t
    cross join lateral jsonb_array_elements(
      case when jsonb_typeof(t.pl->'payments') = 'array' then t.pl->'payments' else '[]'::jsonb end
    ) with ordinality as pg(item, posicao)
  ), pagamento_valido as (
    select pb.*,
           sum(pb.valor) over (partition by pb.titulo_id order by pb.sequencia_pagamento) as acumulado
    from pagamento_bruto pb
    where pb.data_pagamento is not null and pb.valor is not null
  ), total_pago as (
    select pv.titulo_id, sum(pv.valor) as valor_pago, max(pv.data_pagamento) as data_ultimo_pagamento
    from pagamento_valido pv
    group by pv.titulo_id
  ), titulo_total as (
    select t.titulo_id, t.valor_original, t.vencimento, t.data_emissao, t.pl,
           coalesce(tp.valor_pago, 0) as valor_pago, tp.data_ultimo_pagamento,
           -- sem saldo na origem não há como separar desconto de saldo: o ajuste fica zero
           coalesce(t.valor_original - coalesce(tp.valor_pago, 0) - t.saldo_origem, 0) as ajuste_baixa
    from titulo t
    left join total_pago tp on tp.titulo_id = t.titulo_id
  ), apropriacao_arredondada as (
    select a.*, tt.vencimento, tt.data_emissao, tt.data_ultimo_pagamento, tt.valor_original as original_titulo,
           tt.valor_pago as pago_titulo, tt.ajuste_baixa as ajuste_titulo,
           round(tt.valor_original * a.p, 2) as original_arred,
           round(tt.valor_pago * a.p, 2) as pago_arred,
           round(tt.ajuste_baixa * a.p, 2) as ajuste_arred
    from apropriacao a
    join titulo_total tt on tt.titulo_id = a.titulo_id
  ), apropriacao_valor as (
    select aa.*,
           case when aa.principal then aa.original_titulo - (sum(aa.original_arred) over w - aa.original_arred)
                else aa.original_arred end as valor_original,
           case when aa.principal then aa.pago_titulo - (sum(aa.pago_arred) over w - aa.pago_arred)
                else aa.pago_arred end as valor_pago,
           case when aa.principal then aa.ajuste_titulo - (sum(aa.ajuste_arred) over w - aa.ajuste_arred)
                else aa.ajuste_arred end as ajuste_baixa
    from apropriacao_arredondada aa
    window w as (partition by aa.titulo_id)
  ), grava_apropriacoes as (
    insert into staging.titulo_pagar_apropriacao
      (tenant_id, centro_custo_id, titulo_id_origem, sequencia_obra, sequencia_conta, id_origem_obra, motivo_sem_obra,
       conta_origem, percentual, principal, valor_original, valor_pago, ajuste_baixa, saldo, vencimento,
       data_competencia, data_ultimo_pagamento)
    select p_tenant, av.centro_custo_id, av.titulo_id, av.sequencia_obra, av.sequencia_conta, av.id_origem_obra,
           av.motivo_sem_obra, av.conta_origem, round(av.p, 6), av.principal, av.valor_original, av.valor_pago,
           av.ajuste_baixa, av.valor_original - av.valor_pago - av.ajuste_baixa, av.vencimento, av.data_emissao,
           av.data_ultimo_pagamento
    from apropriacao_valor av
  ), pagamento_arredondado as (
    select pv.titulo_id, pv.sequencia_pagamento, pv.data_pagamento, pv.acumulado, pv.acumulado - pv.valor as anterior,
           a.sequencia_obra, a.sequencia_conta, a.centro_custo_id, a.conta_origem, a.principal,
           round(pv.acumulado * a.p, 2) as acumulado_arred,
           round((pv.acumulado - pv.valor) * a.p, 2) as anterior_arred
    from pagamento_valido pv
    join apropriacao a on a.titulo_id = pv.titulo_id
  ), grava_pagamentos as (
    insert into staging.pagamento
      (tenant_id, centro_custo_id, titulo_id_origem, sequencia_pagamento, sequencia_obra, sequencia_conta,
       data_pagamento, valor, conta_origem)
    select p_tenant, pa.centro_custo_id, pa.titulo_id, pa.sequencia_pagamento, pa.sequencia_obra, pa.sequencia_conta,
           pa.data_pagamento,
           case when pa.principal then pa.acumulado - (sum(pa.acumulado_arred) over w - pa.acumulado_arred)
                else pa.acumulado_arred end
           - case when pa.principal then pa.anterior - (sum(pa.anterior_arred) over w - pa.anterior_arred)
                  else pa.anterior_arred end,
           pa.conta_origem
    from pagamento_arredondado pa
    window w as (partition by pa.titulo_id, pa.sequencia_pagamento)
  ), grava_titulos as (
    insert into staging.titulo_pagar
      (tenant_id, centro_custo_id, id_origem, credor, vencimento, valor_original, saldo, data_pagamento,
       empresa_id_origem, data_emissao, valor_pago, ajuste_baixa, quantidade_apropriacoes)
    select p_tenant, a.centro_custo_id, tt.titulo_id, tt.pl->>'creditorName', tt.vencimento, tt.valor_original,
           (tt.pl->>'balanceAmount')::numeric, tt.data_ultimo_pagamento, (tt.pl->>'companyId')::int, tt.data_emissao,
           tt.valor_pago, tt.ajuste_baixa, a.quantidade
    from titulo_total tt
    join apropriacao a on a.titulo_id = tt.titulo_id and a.principal
    returning centro_custo_id
  )
  select (select count(*) from pagamento_bruto pb where pb.data_pagamento is null or pb.valor is null),
         (select count(*) from grava_titulos gt where gt.centro_custo_id = v_empresa)
  into v_pagamentos_sem_data, v_titulos_sem_obra;

  insert into staging.item_orcamento
  select p_tenant, cc.id, r.payload->>'wbsCode', r.payload->>'description',
         (r.payload->>'totalPrice')::numeric, (r.payload->>'percentComplete')::numeric
  from raw.registro r
  join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = (r.payload->>'buildingId')::int
  where r.tenant_id = p_tenant and r.endpoint = 'building-cost-estimation-items';

  if v_recebimentos_sem_data > 0 or v_pagamentos_sem_data > 0 then
    raise notice 'recebimentos sem data ou valor ignorados: %, pagamentos sem data ou valor ignorados: %',
      v_recebimentos_sem_data, v_pagamentos_sem_data;
  end if;
  if v_titulos_sem_obra > 0 then
    raise notice 'títulos com a parte principal em Despesas sem obra: %', v_titulos_sem_obra;
  end if;
end $$;
revoke execute on function staging.recarregar(uuid) from public, anon, authenticated;

-- Views de caixa passam a ler os eventos. Nomes, colunas e ordem ficam os da 0005; drop porque o tipo
-- das colunas muda de numeric para a soma de numeric(18,2).
drop view marts.posicao_financeira_obra;
drop view marts.fluxo_caixa_mensal;
drop view marts.consolidado_centro_custo;

-- Receber vencido fica fora do saldo (atraso do comprador ou do banco); pagar vencido entra no mês em que venceu.
create view marts.fluxo_caixa_mensal with (security_invoker = true) as
with referencia as (
  select app.data_referencia() as ref
), movimento as (
  select r.tenant_id, r.centro_custo_id, date_trunc('month', r.data_recebimento)::date as competencia,
         r.origem, 'entrada_realizada' as tipo, r.valor
  from staging.recebimento r
  where r.tipo_baixa in ('recebimento', 'estorno')
  union all
  select p.tenant_id, p.centro_custo_id, date_trunc('month', p.vencimento)::date, p.origem,
         case when p.vencimento < ref.ref then 'entrada_vencida' else 'entrada_prevista' end,
         coalesce(p.saldo_corrigido, p.saldo)
  from staging.parcela_receber p
  cross join referencia ref
  left join staging.contrato_venda c on c.tenant_id = p.tenant_id and c.id_origem = p.contrato_id_origem
  where coalesce(p.saldo_corrigido, p.saldo) > 0 and c.situacao is distinct from '3'
  union all
  select pg.tenant_id, pg.centro_custo_id, date_trunc('month', pg.data_pagamento)::date, null,
         'saida_realizada', pg.valor
  from staging.pagamento pg
  union all
  select a.tenant_id, a.centro_custo_id, date_trunc('month', a.vencimento)::date, null,
         case when a.vencimento < ref.ref then 'saida_vencida' else 'saida_prevista' end, a.saldo
  from staging.titulo_pagar_apropriacao a
  cross join referencia ref
  where a.saldo > 0
), mensal as (
  select tenant_id, centro_custo_id, competencia,
    coalesce(sum(valor) filter (where tipo = 'entrada_realizada' and origem = 'direta'), 0) as entrada_direta_realizada,
    coalesce(sum(valor) filter (where tipo = 'entrada_realizada' and origem = 'repasse'), 0) as repasse_realizado,
    coalesce(sum(valor) filter (where tipo = 'entrada_prevista' and origem = 'direta'), 0) as entrada_direta_prevista,
    coalesce(sum(valor) filter (where tipo = 'entrada_prevista' and origem = 'repasse'), 0) as repasse_previsto,
    coalesce(sum(valor) filter (where tipo = 'entrada_vencida' and origem = 'direta'), 0) as entrada_direta_vencida,
    coalesce(sum(valor) filter (where tipo = 'entrada_vencida' and origem = 'repasse'), 0) as repasse_vencido,
    coalesce(sum(valor) filter (where tipo = 'saida_realizada'), 0) as saida_realizada,
    coalesce(sum(valor) filter (where tipo = 'saida_prevista'), 0) as saida_prevista,
    coalesce(sum(valor) filter (where tipo = 'saida_vencida'), 0) as saida_vencida
  from movimento
  group by 1, 2, 3
)
select m.*,
  m.entrada_direta_realizada + m.repasse_realizado + m.entrada_direta_prevista + m.repasse_previsto
    - m.saida_realizada - m.saida_prevista - m.saida_vencida as saldo_mes,
  sum(m.entrada_direta_realizada + m.repasse_realizado + m.entrada_direta_prevista + m.repasse_previsto
      - m.saida_realizada - m.saida_prevista - m.saida_vencida)
    over (partition by m.tenant_id, m.centro_custo_id order by m.competencia) as saldo_acumulado
from mensal m;

-- Custo a incorrer e estouro usam o custo lançado, que só difere de pago mais a pagar quando há
-- desconto ou juros na baixa. Só obras: "Despesas sem obra" fica fora da posição por obra.
create view marts.posicao_financeira_obra with (security_invoker = true) as
with fluxo as (
  select tenant_id, centro_custo_id,
    sum(entrada_direta_realizada) as recebido_direto,
    sum(repasse_realizado) as recebido_repasse,
    sum(entrada_direta_prevista) as a_receber_direto,
    sum(repasse_previsto) as a_receber_repasse,
    sum(entrada_direta_vencida) as vencido_direto,
    sum(repasse_vencido) as repasse_atrasado,
    sum(saida_realizada) as pago,
    sum(saida_prevista + saida_vencida) as a_pagar,
    min(saldo_acumulado) as menor_saldo_acumulado
  from marts.fluxo_caixa_mensal
  group by 1, 2
), lancado as (
  select tenant_id, centro_custo_id, sum(valor_original) as custo_lancado
  from staging.titulo_pagar_apropriacao
  group by 1, 2
), orcamento as (
  select tenant_id, centro_custo_id, sum(valor_total) as custo_orcado
  from staging.item_orcamento
  group by 1, 2
), estoque as (
  select tenant_id, centro_custo_id, sum(valor) as estoque_a_vender
  from marts.mapa_unidades
  where situacao in ('disponivel', 'reservada', 'proposta')
  group by 1, 2
), base as (
  select cc.tenant_id, cc.id as centro_custo_id, cc.nome as obra,
    coalesce(f.recebido_direto, 0) as recebido_direto,
    coalesce(f.recebido_repasse, 0) as recebido_repasse,
    coalesce(f.a_receber_direto, 0) as a_receber_direto,
    coalesce(f.a_receber_repasse, 0) as a_receber_repasse,
    coalesce(f.vencido_direto, 0) as vencido_direto,
    coalesce(f.repasse_atrasado, 0) as repasse_atrasado,
    coalesce(e.estoque_a_vender, 0) as estoque_a_vender,
    coalesce(f.pago, 0) as pago,
    coalesce(f.a_pagar, 0) as a_pagar,
    coalesce(o.custo_orcado, 0) as custo_orcado,
    coalesce(l.custo_lancado, 0) as custo_lancado,
    o.centro_custo_id is not null as orcamento_carregado,
    least(coalesce(f.menor_saldo_acumulado, 0), 0) as menor_saldo_acumulado
  from app.centro_custo cc
  left join fluxo f on f.tenant_id = cc.tenant_id and f.centro_custo_id = cc.id
  left join lancado l on l.tenant_id = cc.tenant_id and l.centro_custo_id = cc.id
  left join orcamento o on o.tenant_id = cc.tenant_id and o.centro_custo_id = cc.id
  left join estoque e on e.tenant_id = cc.tenant_id and e.centro_custo_id = cc.id
  where cc.tipo = 'obra'
)
select b.tenant_id, b.centro_custo_id, b.obra,
  b.recebido_direto, b.recebido_repasse, b.a_receber_direto, b.a_receber_repasse, b.vencido_direto, b.repasse_atrasado,
  b.estoque_a_vender,
  b.pago, b.a_pagar, b.custo_orcado,
  greatest(b.custo_orcado - b.custo_lancado, 0) as custo_a_incorrer,
  greatest(b.custo_lancado - b.custo_orcado, 0) as estouro_orcamento,
  b.recebido_direto + b.recebido_repasse - b.pago as caixa_atual,
  -b.menor_saldo_acumulado as exposicao_maxima,
  b.recebido_direto + b.recebido_repasse + b.a_receber_direto + b.a_receber_repasse + b.vencido_direto
    + b.repasse_atrasado
    - greatest(b.custo_orcado, b.custo_lancado) as resultado_contratado,
  b.recebido_direto + b.recebido_repasse + b.a_receber_direto + b.a_receber_repasse + b.vencido_direto
    + b.repasse_atrasado
    + b.estoque_a_vender - greatest(b.custo_orcado, b.custo_lancado) as resultado_projetado,
  b.custo_lancado,
  b.custo_lancado - b.pago - b.a_pagar as ajuste_baixa,
  b.orcamento_carregado
from base b;

create or replace view marts.cobertura_orcamento_obra with (security_invoker = true) as
with orcamento as (
  select tenant_id, centro_custo_id, sum(valor_total) as custo_orcado
  from staging.item_orcamento
  group by 1, 2
), vendas as (
  select tenant_id, centro_custo_id, sum(valor) as vgv_contratado, avg(valor) as ticket_medio
  from staging.contrato_venda
  where situacao = '1'
  group by 1, 2
)
select cc.tenant_id, cc.id as centro_custo_id, cc.nome as obra,
  coalesce(o.custo_orcado, 0) as custo_orcado,
  coalesce(v.vgv_contratado, 0) as vgv_contratado,
  case when o.custo_orcado > 0 then round(coalesce(v.vgv_contratado, 0) / o.custo_orcado, 4) end as pct_cobertura,
  round(v.ticket_medio, 2) as ticket_medio,
  case when v.ticket_medio > 0
       then greatest(0, ceil((coalesce(o.custo_orcado, 0) - v.vgv_contratado) / v.ticket_medio))::integer end as unidades_para_cobrir
from app.centro_custo cc
left join orcamento o on o.tenant_id = cc.tenant_id and o.centro_custo_id = cc.id
left join vendas v on v.tenant_id = cc.tenant_id and v.centro_custo_id = cc.id
where cc.tipo = 'obra';

grant select on marts.fluxo_caixa_mensal, marts.posicao_financeira_obra, marts.cobertura_orcamento_obra to authenticated;
