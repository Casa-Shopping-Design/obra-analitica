-- Financiamento do comprador, crédito à produção, medição do banco e liberações como complemento manual.
-- A origem não traz nada disso; o financeiro cadastra com fonte e documento, e o histórico fica na auditoria.
-- Contrato: docs/financeiro/contrato_dados.md, seção 3.3. Decisão: docs/decisoes/0006-financiamento-medicoes.md.
-- Lê só o staging da 0007; não depende da 0011.

-- Regra única de elegibilidade do financiamento do comprador; as views desta migration e da 0013 chamam aqui.
create function app.classificar_financiamento(p_etapa text, p_pendencia boolean, p_data_financiamento_origem date)
returns text
language sql immutable security invoker set search_path = '' as $$
  select case
    when (p_etapa in ('elegivel', 'liberado') and not coalesce(p_pendencia, false))
      or p_data_financiamento_origem is not null then 'financiamento_elegivel'
    else 'financiamento_pendente'
  end
$$;
revoke execute on function app.classificar_financiamento(text, boolean, date) from public, anon;
grant execute on function app.classificar_financiamento(text, boolean, date) to authenticated, service_role;

create table app.operacao_credito_obra (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  modalidade text not null check (modalidade in ('credito_producao', 'plano_empresario', 'credito_associativo', 'outra')),
  instituicao text not null check (btrim(instituicao) <> ''),
  numero_contrato text,
  valor_contratado numeric(18,2) not null check (valor_contratado > 0),
  percentual_retencao numeric(9,6) check (percentual_retencao >= 0 and percentual_retencao < 1),
  data_contratacao date,
  situacao text not null default 'ativa' check (situacao in ('ativa', 'encerrada', 'cancelada')),
  observacao text,
  fonte text not null check (btrim(fonte) <> ''),
  referencia_documento text,
  autor uuid not null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  -- alvo das chaves compostas de medição e liberação, que impedem ligar uma operação de outra obra
  unique (tenant_id, centro_custo_id, id)
);
create index operacao_credito_obra_obra on app.operacao_credito_obra (tenant_id, centro_custo_id);

create table app.etapa_financiamento_contrato (
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  contrato_id_origem integer not null,
  etapa text not null check (etapa in ('contratacao', 'aprovacao', 'elegivel', 'liberado')),
  pendencia boolean not null default false,
  motivo_pendencia text,
  data_etapa date not null,
  data_prevista_liberacao date,
  observacao text,
  fonte text not null check (btrim(fonte) <> ''),
  referencia_documento text,
  autor uuid not null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  primary key (tenant_id, contrato_id_origem),
  constraint etapa_motivo_pendencia check (not pendencia or btrim(coalesce(motivo_pendencia, '')) <> '')
);
create index etapa_financiamento_contrato_obra on app.etapa_financiamento_contrato (tenant_id, centro_custo_id);

create table app.medicao_bancaria (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  operacao_credito_id uuid not null,
  numero integer not null check (numero >= 1),
  data_vistoria date not null,
  avanco_fisico_informado numeric(9,6) not null check (avanco_fisico_informado >= 0 and avanco_fisico_informado <= 1),
  data_apresentacao date,
  situacao text not null check (situacao in ('apresentada', 'aprovada', 'reprovada')),
  data_aprovacao date,
  valor_medido numeric(18,2) check (valor_medido >= 0),
  valor_elegivel numeric(18,2) check (valor_elegivel >= 0),
  valor_retido numeric(18,2) check (valor_retido >= 0),
  fonte text not null check (btrim(fonte) <> ''),
  referencia_documento text,
  autor uuid not null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (operacao_credito_id, numero),
  unique (tenant_id, centro_custo_id, id),
  constraint medicao_aprovada_com_data check (situacao <> 'aprovada' or data_aprovacao is not null),
  foreign key (tenant_id, centro_custo_id, operacao_credito_id)
    references app.operacao_credito_obra (tenant_id, centro_custo_id, id)
);
create index medicao_bancaria_obra on app.medicao_bancaria (tenant_id, centro_custo_id);

create table app.liberacao_financiamento (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  nivel text not null check (nivel in ('contrato', 'empreendimento', 'lote')),
  operacao_credito_id uuid,
  contrato_id_origem integer,
  medicao_id uuid,
  descricao_lote text,
  valor_previsto numeric(18,2) not null check (valor_previsto > 0),
  data_prevista date not null,
  situacao text not null check (situacao in ('prevista', 'pendente', 'recebida', 'cancelada')),
  motivo text,
  valor_recebido numeric(18,2) check (valor_recebido > 0),
  data_recebimento date,
  vinculo_tipo text check (vinculo_tipo in ('recebimento', 'lancamento_manual')),
  vinculo_chave text,
  fonte text not null check (btrim(fonte) <> ''),
  referencia_documento text,
  autor uuid not null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint liberacao_contrato_por_nivel check (
    (nivel = 'contrato' and contrato_id_origem is not null)
    or (nivel <> 'contrato' and contrato_id_origem is null)),
  constraint liberacao_operacao_por_nivel check (nivel = 'contrato' or operacao_credito_id is not null),
  constraint liberacao_lote_descrito check (nivel <> 'lote' or btrim(coalesce(descricao_lote, '')) <> ''),
  constraint liberacao_motivo check (situacao not in ('pendente', 'cancelada') or btrim(coalesce(motivo, '')) <> ''),
  -- dados de recebimento só existem na liberação recebida, e nela são obrigatórios
  constraint liberacao_recebida_completa check (
    (situacao = 'recebida' and valor_recebido is not null and data_recebimento is not null
       and vinculo_tipo is not null and btrim(coalesce(vinculo_chave, '')) <> '')
    or (situacao <> 'recebida' and valor_recebido is null and data_recebimento is null
       and vinculo_tipo is null and vinculo_chave is null)),
  constraint liberacao_chave_recebimento check (
    vinculo_tipo is distinct from 'recebimento' or vinculo_chave ~ '^[0-9]+\|[0-9]+\|[0-9]+$'),
  -- no nível contrato o dinheiro é a parcela FI do staging; lançamento manual ali duplicaria a entrada
  constraint liberacao_contrato_sem_lancamento check (nivel <> 'contrato' or vinculo_tipo is distinct from 'lancamento_manual'),
  foreign key (tenant_id, centro_custo_id, operacao_credito_id)
    references app.operacao_credito_obra (tenant_id, centro_custo_id, id),
  foreign key (tenant_id, centro_custo_id, medicao_id)
    references app.medicao_bancaria (tenant_id, centro_custo_id, id)
);
create index liberacao_financiamento_obra on app.liberacao_financiamento (tenant_id, centro_custo_id);
create index liberacao_financiamento_operacao on app.liberacao_financiamento (operacao_credito_id);
create index liberacao_financiamento_contrato on app.liberacao_financiamento (tenant_id, contrato_id_origem);
create index liberacao_financiamento_medicao on app.liberacao_financiamento (medicao_id);
-- um recebimento do staging ou um lançamento do extrato liga a uma liberação só
create unique index liberacao_financiamento_vinculo_unico on app.liberacao_financiamento (tenant_id, vinculo_tipo, vinculo_chave)
  where vinculo_chave is not null;

-- Contrato de venda ativo da mesma obra. Etapa e liberação de contrato apontam só para venda real:
-- unidade em estoque não tem contrato, então nunca ganha liberação.
create function app.validar_contrato_financiamento() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  if new.contrato_id_origem is not null and not exists (
    select 1 from staging.contrato_venda c
    where c.tenant_id = new.tenant_id and c.centro_custo_id = new.centro_custo_id
      and c.id_origem = new.contrato_id_origem and c.situacao = '1'
  ) then
    raise exception 'contrato de venda ativo não encontrado na obra' using errcode = '23514';
  end if;
  return new;
end $$;
revoke execute on function app.validar_contrato_financiamento() from public, anon, authenticated;

-- A soma prevista das liberações de uma operação não passa do valor contratado. A linha da operação
-- fica travada até o fim da transação, então duas gravações simultâneas não furam o limite.
-- Liberação recebida conta pelo maior entre previsto e recebido, para valer também
-- liberado_recebido + previsto_aberto <= valor_contratado (R18).
create function app.validar_liberacao() returns trigger
language plpgsql security invoker set search_path = '' as $$
declare
  v_contratado numeric(18,2);
  v_total numeric(18,2);
begin
  if new.nivel = 'contrato' then
    if new.contrato_id_origem is null then
      raise exception 'liberação de contrato sem contrato' using errcode = '23514';
    end if;
    if not exists (
      select 1 from staging.contrato_venda c
      where c.tenant_id = new.tenant_id and c.centro_custo_id = new.centro_custo_id
        and c.id_origem = new.contrato_id_origem and c.situacao = '1'
    ) then
      raise exception 'contrato de venda ativo não encontrado na obra' using errcode = '23514';
    end if;
  end if;

  if new.medicao_id is not null and not exists (
    select 1 from app.medicao_bancaria m
    where m.id = new.medicao_id and m.operacao_credito_id is not distinct from new.operacao_credito_id
  ) then
    raise exception 'medição de outra operação' using errcode = '23514';
  end if;

  if new.operacao_credito_id is not null then
    select o.valor_contratado into v_contratado
    from app.operacao_credito_obra o
    where o.id = new.operacao_credito_id
    for update;

    select coalesce(sum(case when l.situacao = 'recebida' then greatest(l.valor_previsto, l.valor_recebido)
                             else l.valor_previsto end), 0)
    into v_total
    from app.liberacao_financiamento l
    where l.operacao_credito_id = new.operacao_credito_id and l.situacao <> 'cancelada' and l.id <> new.id;

    if new.situacao <> 'cancelada' then
      v_total := v_total + case when new.situacao = 'recebida' then greatest(new.valor_previsto, new.valor_recebido)
                                else new.valor_previsto end;
    end if;
    if v_total > v_contratado then
      raise exception 'liberações passam do valor contratado da operação' using errcode = '23514';
    end if;
  end if;
  return new;
end $$;
revoke execute on function app.validar_liberacao() from public, anon, authenticated;

-- Reduzir o valor contratado abaixo do que já foi programado quebraria o mesmo limite.
create function app.validar_operacao_credito() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  if new.valor_contratado < (
    select coalesce(sum(case when l.situacao = 'recebida' then greatest(l.valor_previsto, l.valor_recebido)
                             else l.valor_previsto end), 0)
    from app.liberacao_financiamento l
    where l.operacao_credito_id = new.id and l.situacao <> 'cancelada'
  ) then
    raise exception 'valor contratado menor que as liberações da operação' using errcode = '23514';
  end if;
  return new;
end $$;
revoke execute on function app.validar_operacao_credito() from public, anon, authenticated;

create trigger validar_contrato before insert or update on app.etapa_financiamento_contrato
  for each row execute function app.validar_contrato_financiamento();
create trigger validar_liberacao before insert or update on app.liberacao_financiamento
  for each row execute function app.validar_liberacao();
create trigger validar_operacao before update of valor_contratado on app.operacao_credito_obra
  for each row execute function app.validar_operacao_credito();

-- Autor, auditoria e RLS iguais nas quatro tabelas: lê quem vê a obra, grava só diretor e financeiro,
-- ninguém apaga (cancelar é mudar a situação).
do $$
declare
  t text;
  chave text;
begin
  foreach t in array array['operacao_credito_obra', 'etapa_financiamento_contrato', 'medicao_bancaria',
                           'liberacao_financiamento'] loop
    chave := case when t = 'etapa_financiamento_contrato' then '''tenant_id'', ''contrato_id_origem''' else '''id''' end;
    execute format('create trigger definir_autor before insert or update on app.%I
      for each row execute function app.definir_autor()', t);
    execute format('create trigger registrar_auditoria after insert or update or delete on app.%I
      for each row execute function app.registrar_auditoria(%s)', t, chave);
    execute format('alter table app.%I enable row level security', t);
    execute format('alter table app.%I force row level security', t);
    execute format($p$create policy leitura_por_obra on app.%I for select to authenticated
      using (tenant_id = (select app.tenant_atual()) and centro_custo_id in (select app.obras_permitidas()))$p$, t);
    execute format($p$create policy inclusao_diretor_financeiro on app.%I for insert to authenticated
      with check (tenant_id = (select app.tenant_atual()) and centro_custo_id in (select app.obras_permitidas())
                  and (select app.perfil_atual()) in ('diretor', 'financeiro'))$p$, t);
    execute format($p$create policy alteracao_diretor_financeiro on app.%I for update to authenticated
      using (tenant_id = (select app.tenant_atual()) and centro_custo_id in (select app.obras_permitidas())
             and (select app.perfil_atual()) in ('diretor', 'financeiro'))
      with check (tenant_id = (select app.tenant_atual()) and centro_custo_id in (select app.obras_permitidas())
                  and (select app.perfil_atual()) in ('diretor', 'financeiro'))$p$, t);
    execute format('grant select, insert, update on app.%I to authenticated', t);
  end loop;
end $$;

-- Financiamento do comprador por contrato ativo. Não há coluna de liberação agregada por contrato:
-- liberação de empreendimento ou lote nunca é repartida entre unidades.
create view marts.financiamento_contrato with (security_invoker = true) as
with referencia as materialized (
  select app.data_referencia() as ref
), parcela_fi as (
  -- situacao_parcela só decide entre as parcelas com saldo; sem saldo nunca é vencida nem a vencer
  select p.tenant_id, p.contrato_id_origem,
         coalesce(sum(coalesce(p.saldo_corrigido, p.saldo))
                  filter (where coalesce(p.saldo_corrigido, p.saldo) > 0
                            and app.situacao_parcela(coalesce(p.saldo_corrigido, p.saldo), p.valor_recebido,
                                                     p.vencimento, false, r.ref) in ('vencida', 'a_vencer')), 0)
           as saldo_financiamento_aberto,
         coalesce(sum(p.valor_recebido), 0) as recebido_financiamento
  from staging.parcela_receber p
  cross join referencia r
  where p.tipo_condicao = 'FI'
  group by p.tenant_id, p.contrato_id_origem
)
select c.tenant_id, c.centro_custo_id, c.id_origem as contrato_id_origem, c.numero as contrato_numero,
  u.nome as unidade,
  c.valor::numeric(18,2) as valor_contrato,
  c.valor_financiado,
  c.banco_repasse as instituicao_financeira,
  c.data_repasse as data_financiamento_origem,
  c.credito_associativo,
  e.etapa, e.pendencia, e.motivo_pendencia, e.data_etapa, e.data_prevista_liberacao,
  app.classificar_financiamento(e.etapa, e.pendencia, c.data_repasse) as classificacao,
  coalesce(fi.saldo_financiamento_aberto, 0)::numeric(18,2) as saldo_financiamento_aberto,
  coalesce(fi.recebido_financiamento, 0)::numeric(18,2) as recebido_financiamento
from staging.contrato_venda c
left join parcela_fi fi on fi.tenant_id = c.tenant_id and fi.contrato_id_origem = c.id_origem
left join app.etapa_financiamento_contrato e on e.tenant_id = c.tenant_id and e.contrato_id_origem = c.id_origem
left join staging.unidade u on u.tenant_id = c.tenant_id and u.id_origem = c.unidade_id_origem
where c.situacao = '1' and (c.valor_financiado > 0 or fi.contrato_id_origem is not null);

-- Parcela em aberto com a data em que se espera o dinheiro. Para FI vale a data prevista da etapa do
-- financiamento; sem ela, o vencimento. O que ficou para trás da referência sai da projeção.
-- Contrato e etapa entram por junção direta, para o planejador usar hash join e avaliar o filtro de tenant
-- uma vez por consulta. A situação só é calculada nas parcelas com saldo e a classificação só nas FI:
-- O(parcelas em aberto).
create view marts.recebivel_projetado with (security_invoker = true) as
with referencia as materialized (
  select app.data_referencia() as ref
), parcela as (
  select p.tenant_id, p.centro_custo_id, p.contrato_id_origem, p.id_origem as parcela_id_origem,
         case when p.tipo_condicao = 'FI' then 'financiamento' else 'direta' end as origem,
         case when p.tipo_condicao is distinct from 'FI' then 'direta'
              when c.id_origem is null then 'financiamento_pendente'
              else app.classificar_financiamento(e.etapa, e.pendencia, c.data_repasse) end as classe,
         p.vencimento,
         coalesce(p.saldo_corrigido, p.saldo)::numeric(18,2) as saldo,
         app.situacao_parcela(coalesce(p.saldo_corrigido, p.saldo), p.valor_recebido, p.vencimento,
                              coalesce(c.situacao = '3', false), r.ref) as situacao,
         case when p.tipo_condicao = 'FI' then coalesce(e.data_prevista_liberacao, p.vencimento)
              else p.vencimento end as data_prevista,
         r.ref
  from staging.parcela_receber p
  cross join referencia r
  left join staging.contrato_venda c on c.tenant_id = p.tenant_id and c.id_origem = p.contrato_id_origem
  left join app.etapa_financiamento_contrato e on e.tenant_id = p.tenant_id and e.contrato_id_origem = p.contrato_id_origem
  where coalesce(p.saldo_corrigido, p.saldo) > 0
)
select tenant_id, centro_custo_id, contrato_id_origem, parcela_id_origem, origem, classe, vencimento, saldo,
  situacao, data_prevista, data_prevista >= ref as incluida_projecao
from parcela
where situacao in ('vencida', 'a_vencer');

create view marts.saldo_operacao_credito with (security_invoker = true) as
with liberacao as (
  select l.operacao_credito_id,
         coalesce(sum(l.valor_recebido) filter (where l.situacao = 'recebida'), 0) as liberado_recebido,
         coalesce(sum(l.valor_previsto) filter (where l.situacao in ('prevista', 'pendente')), 0) as previsto_aberto
  from app.liberacao_financiamento l
  where l.operacao_credito_id is not null
  group by l.operacao_credito_id
), medicao as (
  select m.operacao_credito_id, coalesce(sum(m.valor_elegivel), 0) as medido_elegivel
  from app.medicao_bancaria m
  where m.situacao = 'aprovada'
  group by m.operacao_credito_id
), base as (
  select o.tenant_id, o.centro_custo_id, o.id as operacao_credito_id, o.modalidade, o.instituicao,
         o.valor_contratado, o.percentual_retencao,
         round(o.valor_contratado * o.percentual_retencao, 2)::numeric(18,2) as retencao_prevista,
         coalesce(l.liberado_recebido, 0)::numeric(18,2) as liberado_recebido,
         coalesce(l.previsto_aberto, 0)::numeric(18,2) as previsto_aberto,
         coalesce(m.medido_elegivel, 0)::numeric(18,2) as medido_elegivel
  from app.operacao_credito_obra o
  left join liberacao l on l.operacao_credito_id = o.id
  left join medicao m on m.operacao_credito_id = o.id
)
select b.tenant_id, b.centro_custo_id, b.operacao_credito_id, b.modalidade, b.instituicao, b.valor_contratado,
  b.percentual_retencao, b.retencao_prevista,
  (b.valor_contratado - coalesce(b.retencao_prevista, 0))::numeric(18,2) as limite_antes_retencao,
  b.liberado_recebido, b.previsto_aberto,
  greatest(b.valor_contratado - coalesce(b.retencao_prevista, 0) - b.liberado_recebido, 0)::numeric(18,2)
    as saldo_liberavel,
  greatest(b.valor_contratado - coalesce(b.retencao_prevista, 0) - b.liberado_recebido - b.previsto_aberto, 0)::numeric(18,2)
    as saldo_nao_programado,
  b.medido_elegivel,
  greatest(b.medido_elegivel - b.liberado_recebido, 0)::numeric(18,2) as elegivel_nao_liberado,
  b.liberado_recebido + b.previsto_aberto > b.valor_contratado - coalesce(b.retencao_prevista, 0) as excede_limite
from base b;

create view marts.liberacao_status with (security_invoker = true) as
select l.id, l.tenant_id, l.centro_custo_id, l.nivel, l.operacao_credito_id, l.contrato_id_origem,
  c.numero as contrato_numero, l.medicao_id, l.descricao_lote, l.valor_previsto, l.data_prevista, l.situacao,
  case when l.situacao = 'prevista' and l.data_prevista < r.ref then 'atrasada' else l.situacao end as situacao_efetiva,
  l.motivo, l.valor_recebido, l.data_recebimento, l.vinculo_tipo, l.vinculo_chave, l.fonte, l.referencia_documento,
  case when l.situacao = 'prevista' and l.data_prevista < r.ref then r.ref - l.data_prevista end as dias_atraso,
  'complemento_manual'::text as origem_dado,
  l.criado_em, l.atualizado_em
from app.liberacao_financiamento l
cross join (select app.data_referencia() as ref offset 0) r
left join staging.contrato_venda c on c.tenant_id = l.tenant_id and c.id_origem = l.contrato_id_origem;

grant select on marts.financiamento_contrato, marts.recebivel_projetado, marts.saldo_operacao_credito,
  marts.liberacao_status to authenticated;
