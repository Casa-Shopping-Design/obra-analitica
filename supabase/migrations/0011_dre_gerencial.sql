-- DRE gerencial, receitas e despesas. Conta da origem vira categoria gerencial só por mapeamento
-- explícito; o que não tem mapeamento aparece como pendência e nunca cai numa categoria em silêncio.
-- Receita e custo reconhecidos ficam indisponíveis até o financeiro validar o critério.
-- Contrato: docs/financeiro/contrato_dados.md, seção 3.2. Decisão: docs/decisoes/0005-dre-gerencial.md.

-- Lista global de categorias; sem tenant e sem escrita pela API.
create table app.categoria_gerencial (
  codigo text primary key,
  nome text not null,
  grupo_dre text not null check (grupo_dre in ('receita_bruta', 'deducao_receita', 'custo_imovel', 'despesa_comercial',
                                               'despesa_administrativa', 'resultado_financeiro', 'fora_do_resultado')),
  natureza text not null check (natureza in ('entrada', 'saida')),
  ordem integer not null
);

insert into app.categoria_gerencial (codigo, nome, grupo_dre, natureza, ordem) values
  ('venda_imoveis', 'Venda de imóveis', 'receita_bruta', 'entrada', 10),
  ('tributos_receita', 'Tributos sobre a receita', 'deducao_receita', 'saida', 20),
  ('terreno', 'Terreno', 'custo_imovel', 'saida', 30),
  ('materiais', 'Materiais', 'custo_imovel', 'saida', 31),
  ('mao_de_obra', 'Mão de obra', 'custo_imovel', 'saida', 32),
  ('empreiteiros', 'Empreiteiros', 'custo_imovel', 'saida', 33),
  ('projetos', 'Projetos', 'custo_imovel', 'saida', 34),
  ('licencas_taxas', 'Licenças e taxas', 'custo_imovel', 'saida', 35),
  ('outros_custos_obra', 'Outros custos de obra', 'custo_imovel', 'saida', 36),
  ('corretagem', 'Corretagem', 'despesa_comercial', 'saida', 40),
  ('marketing', 'Marketing', 'despesa_comercial', 'saida', 41),
  ('despesas_administrativas', 'Despesas administrativas', 'despesa_administrativa', 'saida', 50),
  ('despesas_financeiras', 'Despesas financeiras', 'resultado_financeiro', 'saida', 60),
  ('receitas_financeiras', 'Receitas financeiras', 'resultado_financeiro', 'entrada', 61),
  ('devolucao_distrato', 'Devolução de distrato', 'fora_do_resultado', 'saida', 70),
  ('credito_producao_entrada', 'Crédito à produção (entrada)', 'fora_do_resultado', 'entrada', 71),
  ('amortizacao_credito_producao', 'Amortização de crédito à produção', 'fora_do_resultado', 'saida', 72),
  ('aporte_socios', 'Aporte dos sócios', 'fora_do_resultado', 'entrada', 73),
  ('transferencia', 'Transferência entre contas', 'fora_do_resultado', 'saida', 74);

alter table app.categoria_gerencial enable row level security;
alter table app.categoria_gerencial force row level security;
create policy leitura_autenticado on app.categoria_gerencial
  for select to authenticated
  using ((select auth.uid()) is not null);
grant select on app.categoria_gerencial to authenticated;

-- Mapeamento por tenant da conta da origem para a categoria. Autor sempre do JWT, histórico na auditoria.
create table app.mapa_conta_origem (
  tenant_id uuid not null references app.tenant(id) on delete cascade,
  tipo_origem text not null check (tipo_origem in ('titulo_pagar', 'parcela_receber', 'orcamento')),
  conta_origem text not null,
  categoria_codigo text not null references app.categoria_gerencial(codigo),
  observacao text,
  autor uuid not null,
  atualizado_em timestamptz not null default now(),
  primary key (tenant_id, tipo_origem, conta_origem)
);
create index mapa_conta_origem_categoria on app.mapa_conta_origem (categoria_codigo);

-- Título só em categoria de saída, parcela só em entrada, orçamento só em custo do imóvel: assim toda
-- conta mapeada cai numa linha do DRE com o sinal certo.
create function app.validar_mapa_conta_origem() returns trigger
language plpgsql security invoker set search_path = '' as $$
declare
  v_grupo text;
  v_natureza text;
begin
  select c.grupo_dre, c.natureza into v_grupo, v_natureza
  from app.categoria_gerencial c where c.codigo = new.categoria_codigo;
  if (new.tipo_origem = 'titulo_pagar' and v_natureza is distinct from 'saida')
     or (new.tipo_origem = 'parcela_receber' and v_natureza is distinct from 'entrada')
     or (new.tipo_origem = 'orcamento' and v_grupo is distinct from 'custo_imovel') then
    raise exception 'categoria % não serve para %', new.categoria_codigo, new.tipo_origem using errcode = '23514';
  end if;
  return new;
end $$;
revoke execute on function app.validar_mapa_conta_origem() from public, anon, authenticated;

create trigger definir_autor before insert or update on app.mapa_conta_origem
  for each row execute function app.definir_autor();
create trigger validar_categoria before insert or update on app.mapa_conta_origem
  for each row execute function app.validar_mapa_conta_origem();
create trigger registrar_auditoria after insert or update or delete on app.mapa_conta_origem
  for each row execute function app.registrar_auditoria('tenant_id', 'tipo_origem', 'conta_origem');

alter table app.mapa_conta_origem enable row level security;
alter table app.mapa_conta_origem force row level security;
create policy leitura_tenant on app.mapa_conta_origem
  for select to authenticated
  using (tenant_id = (select app.tenant_atual()));
create policy inclusao_diretor_financeiro on app.mapa_conta_origem
  for insert to authenticated
  with check (tenant_id = (select app.tenant_atual()) and (select app.perfil_atual()) in ('diretor', 'financeiro'));
create policy alteracao_diretor_financeiro on app.mapa_conta_origem
  for update to authenticated
  using (tenant_id = (select app.tenant_atual()) and (select app.perfil_atual()) in ('diretor', 'financeiro'))
  with check (tenant_id = (select app.tenant_atual()) and (select app.perfil_atual()) in ('diretor', 'financeiro'));
create policy exclusao_diretor_financeiro on app.mapa_conta_origem
  for delete to authenticated
  using (tenant_id = (select app.tenant_atual()) and (select app.perfil_atual()) in ('diretor', 'financeiro'));
grant select, insert, update, delete on app.mapa_conta_origem to authenticated;

-- Critério de reconhecimento por tenant (centro nulo) ou por obra. Sem linha vale nao_definido.
create table app.criterio_reconhecimento (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenant(id) on delete cascade,
  centro_custo_id uuid references app.centro_custo(id) on delete cascade,
  metodo text not null default 'nao_definido' check (metodo in ('nao_definido', 'percentual_conclusao')),
  base_fracao_vendida text not null default 'unidades' check (base_fracao_vendida in ('unidades')),
  validado_por uuid,
  validado_em timestamptz,
  observacao text,
  autor uuid not null,
  atualizado_em timestamptz not null default now(),
  constraint criterio_reconhecimento_unico unique nulls not distinct (tenant_id, centro_custo_id)
);
create index criterio_reconhecimento_obra on app.criterio_reconhecimento (centro_custo_id);

-- Quem valida é quem liga o percentual de conclusão; o valor mandado pelo cliente é ignorado.
-- Obra de outro tenant ou centro que não é obra não recebem critério próprio.
create function app.registrar_validacao_criterio() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  if new.centro_custo_id is not null and not exists (
    select 1 from app.centro_custo cc
    where cc.id = new.centro_custo_id and cc.tenant_id = new.tenant_id and cc.tipo = 'obra'
  ) then
    raise exception 'critério só vale para obra do mesmo tenant' using errcode = '23514';
  end if;
  if new.metodo = 'nao_definido' then
    new.validado_por := null;
    new.validado_em := null;
  elsif tg_op = 'INSERT' or old.metodo is distinct from new.metodo then
    new.validado_por := auth.uid();
    new.validado_em := now();
  else
    new.validado_por := old.validado_por;
    new.validado_em := old.validado_em;
  end if;
  return new;
end $$;
revoke execute on function app.registrar_validacao_criterio() from public, anon, authenticated;

create trigger definir_autor before insert or update on app.criterio_reconhecimento
  for each row execute function app.definir_autor();
create trigger registrar_validacao before insert or update on app.criterio_reconhecimento
  for each row execute function app.registrar_validacao_criterio();
create trigger registrar_auditoria after insert or update or delete on app.criterio_reconhecimento
  for each row execute function app.registrar_auditoria('id');

alter table app.criterio_reconhecimento enable row level security;
alter table app.criterio_reconhecimento force row level security;
create policy leitura_por_obra on app.criterio_reconhecimento
  for select to authenticated
  using (tenant_id = (select app.tenant_atual())
         and (centro_custo_id is null or centro_custo_id in (select app.obras_permitidas())));
create policy inclusao_diretor_financeiro on app.criterio_reconhecimento
  for insert to authenticated
  with check (tenant_id = (select app.tenant_atual())
              and (centro_custo_id is null or centro_custo_id in (select app.obras_permitidas()))
              and (select app.perfil_atual()) in ('diretor', 'financeiro'));
create policy alteracao_diretor_financeiro on app.criterio_reconhecimento
  for update to authenticated
  using (tenant_id = (select app.tenant_atual())
         and (centro_custo_id is null or centro_custo_id in (select app.obras_permitidas()))
         and (select app.perfil_atual()) in ('diretor', 'financeiro'))
  with check (tenant_id = (select app.tenant_atual())
              and (centro_custo_id is null or centro_custo_id in (select app.obras_permitidas()))
              and (select app.perfil_atual()) in ('diretor', 'financeiro'));
grant select, insert, update on app.criterio_reconhecimento to authenticated;

-- Índices das junções novas: unidades por obra (fração vendida) e conta da parcela (classificação).
create index unidade_obra on staging.unidade (tenant_id, centro_custo_id);
create index parcela_receber_conta on staging.parcela_receber (tenant_id, conta_origem);
create index pagamento_conta on staging.pagamento (tenant_id, conta_origem);

-- Apoio das views abaixo. Precisa de grant porque view com security_invoker confere o privilégio de
-- quem consulta em cada objeto lido; não expõe nada além da apropriação que o usuário já lê.
create view marts.apropriacao_classificada with (security_invoker = true) as
select a.tenant_id, a.centro_custo_id, a.titulo_id_origem, a.sequencia_obra, a.sequencia_conta, a.conta_origem,
       a.valor_original, a.valor_pago, a.ajuste_baixa, a.saldo, a.vencimento, a.data_competencia,
       m.categoria_codigo, c.nome as categoria_nome, c.grupo_dre
from staging.titulo_pagar_apropriacao a
left join app.mapa_conta_origem m
  on m.tenant_id = a.tenant_id and m.tipo_origem = 'titulo_pagar' and m.conta_origem = a.conta_origem
left join app.categoria_gerencial c on c.codigo = m.categoria_codigo;

-- Carteira por parcela, sem dado do comprador.
create view marts.carteira_recebiveis with (security_invoker = true) as
with referencia as (
  select app.data_referencia() as ref
)
select p.tenant_id, p.centro_custo_id, p.contrato_id_origem, c.numero as contrato_numero,
       c.unidade_id_origem, u.nome as unidade, p.id_origem as parcela_id_origem, p.numero_parcela, p.tipo_condicao,
       case p.origem when 'repasse' then 'financiamento' else 'direta' end as origem,
       p.vencimento,
       p.valor_original::numeric(18,2) as valor_original,
       p.valor_recebido::numeric(18,2) as valor_recebido,
       s.saldo,
       p.data_recebimento as data_ultimo_recebimento,
       s.situacao,
       coalesce(p.valor_recebido, 0) > 0 and s.saldo > 0 as parcial,
       case when s.situacao = 'vencida' then r.ref - p.vencimento end as dias_atraso,
       case when c.id_origem is null then null
            when c.situacao = '1' then 'ativo'
            when c.situacao = '3' then 'distratado'
            else 'outra' end as situacao_contrato,
       p.inadimplente as inadimplente_origem
from staging.parcela_receber p
cross join referencia r
left join staging.contrato_venda c on c.tenant_id = p.tenant_id and c.id_origem = p.contrato_id_origem
left join staging.unidade u on u.tenant_id = c.tenant_id and u.id_origem = c.unidade_id_origem
cross join lateral (
  select coalesce(p.saldo_corrigido, p.saldo, 0)::numeric(18,2) as saldo,
         app.situacao_parcela(coalesce(p.saldo_corrigido, p.saldo, 0), p.valor_recebido, p.vencimento,
                              coalesce(c.situacao = '3', false), r.ref) as situacao
) s;

-- Somas sem linha dão zero: a carteira existe e está vazia naquele recorte.
create view marts.resumo_receitas_obra with (security_invoker = true) as
with referencia as (
  select app.data_referencia() as ref,
         (date_trunc('month', app.data_referencia()) + interval '1 month')::date as proximo_mes
), carteira as (
  select k.tenant_id, k.centro_custo_id,
    sum(k.valor_recebido) filter (where k.origem = 'direta') as recebido_direto,
    sum(k.valor_recebido) filter (where k.origem = 'financiamento') as recebido_financiamento,
    sum(k.saldo) filter (where k.situacao = 'vencida' and k.origem = 'direta') as vencido_direto,
    sum(k.saldo) filter (where k.situacao = 'vencida' and k.origem = 'financiamento') as vencido_financiamento,
    sum(k.saldo) filter (where k.situacao = 'a_vencer' and k.origem = 'direta') as a_vencer_direto,
    sum(k.saldo) filter (where k.situacao = 'a_vencer' and k.origem = 'financiamento') as a_vencer_financiamento,
    sum(k.saldo) filter (where k.situacao = 'a_vencer' and k.origem = 'direta'
                           and date_trunc('month', k.vencimento) = r.proximo_mes) as previsto_proximo_mes_direto,
    sum(k.saldo) filter (where k.situacao = 'a_vencer' and k.origem = 'financiamento'
                           and date_trunc('month', k.vencimento) = r.proximo_mes) as previsto_proximo_mes_financiamento,
    sum(k.saldo) filter (where k.situacao = 'cancelada_distrato') as saldo_distratado
  from marts.carteira_recebiveis k
  cross join referencia r
  group by k.tenant_id, k.centro_custo_id
), contrato as (
  select c.tenant_id, c.centro_custo_id,
    sum(c.valor) filter (where c.situacao = '1') as vgv_contratado_ativo,
    count(*) filter (where c.situacao = '1') as contratos_ativos,
    count(*) filter (where c.situacao = '3') as contratos_distratados
  from staging.contrato_venda c
  group by c.tenant_id, c.centro_custo_id
)
select cc.tenant_id, cc.id as centro_custo_id, cc.nome as obra, cc.tipo as tipo_centro,
  coalesce(ct.vgv_contratado_ativo, 0)::numeric(18,2) as vgv_contratado_ativo,
  coalesce(ct.contratos_ativos, 0)::integer as contratos_ativos,
  coalesce(ct.contratos_distratados, 0)::integer as contratos_distratados,
  coalesce(k.recebido_direto, 0)::numeric(18,2) as recebido_direto,
  coalesce(k.recebido_financiamento, 0)::numeric(18,2) as recebido_financiamento,
  coalesce(k.vencido_direto, 0)::numeric(18,2) as vencido_direto,
  coalesce(k.vencido_financiamento, 0)::numeric(18,2) as vencido_financiamento,
  coalesce(k.a_vencer_direto, 0)::numeric(18,2) as a_vencer_direto,
  coalesce(k.a_vencer_financiamento, 0)::numeric(18,2) as a_vencer_financiamento,
  coalesce(k.previsto_proximo_mes_direto, 0)::numeric(18,2) as previsto_proximo_mes_direto,
  coalesce(k.previsto_proximo_mes_financiamento, 0)::numeric(18,2) as previsto_proximo_mes_financiamento,
  coalesce(k.saldo_distratado, 0)::numeric(18,2) as saldo_distratado,
  r.ref as data_referencia
from app.centro_custo cc
cross join referencia r
left join carteira k on k.tenant_id = cc.tenant_id and k.centro_custo_id = cc.id
left join contrato ct on ct.tenant_id = cc.tenant_id and ct.centro_custo_id = cc.id
where k.centro_custo_id is not null or ct.centro_custo_id is not null;

-- Totais das obras visíveis, uma linha por tenant. "Despesas sem obra" fica fora.
create view marts.resumo_receitas_consolidado with (security_invoker = true) as
select r.tenant_id,
  count(*)::integer as quantidade_obras,
  sum(r.vgv_contratado_ativo)::numeric(18,2) as vgv_contratado_ativo,
  sum(r.contratos_ativos)::integer as contratos_ativos,
  sum(r.contratos_distratados)::integer as contratos_distratados,
  sum(r.recebido_direto)::numeric(18,2) as recebido_direto,
  sum(r.recebido_financiamento)::numeric(18,2) as recebido_financiamento,
  sum(r.vencido_direto)::numeric(18,2) as vencido_direto,
  sum(r.vencido_financiamento)::numeric(18,2) as vencido_financiamento,
  sum(r.a_vencer_direto)::numeric(18,2) as a_vencer_direto,
  sum(r.a_vencer_financiamento)::numeric(18,2) as a_vencer_financiamento,
  sum(r.previsto_proximo_mes_direto)::numeric(18,2) as previsto_proximo_mes_direto,
  sum(r.previsto_proximo_mes_financiamento)::numeric(18,2) as previsto_proximo_mes_financiamento,
  sum(r.saldo_distratado)::numeric(18,2) as saldo_distratado,
  min(r.data_referencia) as data_referencia
from marts.resumo_receitas_obra r
where r.tipo_centro = 'obra'
group by r.tenant_id;

-- Recebido pelo mês do caixa; previsto e em aberto pelo mês do vencimento. Parcela renegociada e
-- parcela de contrato distratado ficam fora do previsto para a renegociação não contar duas vezes.
create view marts.recebimento_mensal with (security_invoker = true) as
with movimento as (
  select r.tenant_id, r.centro_custo_id, date_trunc('month', r.data_recebimento)::date as competencia,
         case r.origem when 'repasse' then 'financiamento' else 'direta' end as origem,
         r.valor as recebido, 0::numeric as previsto_contratual, 0::numeric as saldo_em_aberto
  from staging.recebimento r
  where r.tipo_baixa in ('recebimento', 'estorno')
  union all
  select k.tenant_id, k.centro_custo_id, date_trunc('month', k.vencimento)::date, k.origem,
         0, k.valor_original, case when k.situacao in ('vencida', 'a_vencer') then k.saldo else 0 end
  from marts.carteira_recebiveis k
  where k.situacao not in ('cancelada_distrato', 'baixada_sem_recebimento')
)
select m.tenant_id, m.centro_custo_id, m.competencia, m.origem,
  sum(m.recebido)::numeric(18,2) as recebido,
  sum(m.previsto_contratual)::numeric(18,2) as previsto_contratual,
  sum(m.saldo_em_aberto)::numeric(18,2) as saldo_em_aberto
from movimento m
group by m.tenant_id, m.centro_custo_id, m.competencia, m.origem;

create view marts.recebimento_mensal_consolidado with (security_invoker = true) as
select m.tenant_id, m.competencia, m.origem,
  sum(m.recebido)::numeric(18,2) as recebido,
  sum(m.previsto_contratual)::numeric(18,2) as previsto_contratual,
  sum(m.saldo_em_aberto)::numeric(18,2) as saldo_em_aberto
from marts.recebimento_mensal m
join app.centro_custo cc on cc.id = m.centro_custo_id and cc.tipo = 'obra'
group by m.tenant_id, m.competencia, m.origem;

-- Custo por centro e categoria. Remanescente e estimativa ficam só no resumo, porque por categoria
-- contariam o mesmo real duas vezes quando o orçamento não usa as categorias dos títulos.
create view marts.custo_obra_categoria with (security_invoker = true) as
with referencia as (
  select app.data_referencia() as ref
), movimento as (
  select a.tenant_id, a.centro_custo_id, a.categoria_codigo, 'titulo' as fonte,
         a.valor_original as custo_lancado, 0::numeric as desembolsado,
         case when a.saldo > 0 and a.vencimento < r.ref then a.saldo else 0 end as em_aberto_vencido,
         case when a.saldo > 0 and a.vencimento >= r.ref then a.saldo else 0 end as em_aberto_a_vencer,
         0::numeric as orcamento
  from marts.apropriacao_classificada a
  cross join referencia r
  union all
  select pg.tenant_id, pg.centro_custo_id, m.categoria_codigo, 'pagamento', 0, pg.valor, 0, 0, 0
  from staging.pagamento pg
  left join app.mapa_conta_origem m
    on m.tenant_id = pg.tenant_id and m.tipo_origem = 'titulo_pagar' and m.conta_origem = pg.conta_origem
  union all
  select o.tenant_id, o.centro_custo_id, m.categoria_codigo, 'orcamento', 0, 0, 0, 0, o.valor_total
  from staging.item_orcamento o
  left join app.mapa_conta_origem m
    on m.tenant_id = o.tenant_id and m.tipo_origem = 'orcamento' and m.conta_origem = o.codigo
), agregado as (
  select mv.tenant_id, mv.centro_custo_id, mv.categoria_codigo,
    sum(mv.custo_lancado) as custo_lancado,
    sum(mv.desembolsado) as desembolsado,
    sum(mv.em_aberto_vencido) as em_aberto_vencido,
    sum(mv.em_aberto_a_vencer) as em_aberto_a_vencer,
    sum(mv.orcamento) as orcamento,
    bool_or(bool_or(mv.fonte = 'orcamento')) over (partition by mv.tenant_id, mv.centro_custo_id) as tem_orcamento
  from movimento mv
  group by mv.tenant_id, mv.centro_custo_id, mv.categoria_codigo
)
select g.tenant_id, g.centro_custo_id, cc.tipo as tipo_centro, g.categoria_codigo,
  coalesce(c.nome, 'Sem categoria') as categoria_nome, c.grupo_dre,
  case when g.tem_orcamento then g.orcamento end::numeric(18,2) as orcamento_vigente,
  g.custo_lancado::numeric(18,2) as custo_lancado,
  g.desembolsado::numeric(18,2) as desembolsado,
  g.em_aberto_vencido::numeric(18,2) as em_aberto_vencido,
  g.em_aberto_a_vencer::numeric(18,2) as em_aberto_a_vencer,
  (g.custo_lancado - g.desembolsado - g.em_aberto_vencido - g.em_aberto_a_vencer)::numeric(18,2) as ajuste_baixa
from agregado g
join app.centro_custo cc on cc.id = g.centro_custo_id
left join app.categoria_gerencial c on c.codigo = g.categoria_codigo;

-- Uma linha por centro visível; sem orçamento, tudo que depende dele fica nulo com o motivo.
create view marts.custo_obra_resumo with (security_invoker = true) as
with categoria as (
  select k.tenant_id, k.centro_custo_id,
    sum(k.orcamento_vigente) as orcamento_vigente,
    sum(k.custo_lancado) as custo_lancado,
    sum(k.desembolsado) as desembolsado,
    sum(k.em_aberto_vencido) as em_aberto_vencido,
    sum(k.em_aberto_a_vencer) as em_aberto_a_vencer,
    sum(k.ajuste_baixa) as ajuste_baixa,
    sum(k.custo_lancado) filter (where k.categoria_codigo is not null) as custo_com_categoria
  from marts.custo_obra_categoria k
  group by k.tenant_id, k.centro_custo_id
), base as (
  select cc.tenant_id, cc.id as centro_custo_id, cc.nome as obra, cc.tipo as tipo_centro,
    k.orcamento_vigente,
    coalesce(k.custo_lancado, 0) as custo_lancado,
    coalesce(k.desembolsado, 0) as desembolsado,
    coalesce(k.em_aberto_vencido, 0) as em_aberto_vencido,
    coalesce(k.em_aberto_a_vencer, 0) as em_aberto_a_vencer,
    coalesce(k.ajuste_baixa, 0) as ajuste_baixa,
    coalesce(k.custo_com_categoria, 0) as custo_com_categoria
  from app.centro_custo cc
  left join categoria k on k.tenant_id = cc.tenant_id and k.centro_custo_id = cc.id
)
select b.tenant_id, b.centro_custo_id, b.obra, b.tipo_centro,
  b.orcamento_vigente::numeric(18,2) as orcamento_vigente,
  null::numeric(18,2) as orcamento_original,
  b.custo_lancado::numeric(18,2) as custo_lancado,
  b.desembolsado::numeric(18,2) as desembolsado,
  b.em_aberto_vencido::numeric(18,2) as em_aberto_vencido,
  b.em_aberto_a_vencer::numeric(18,2) as em_aberto_a_vencer,
  b.ajuste_baixa::numeric(18,2) as ajuste_baixa,
  r.remanescente::numeric(18,2) as remanescente_sem_titulo,
  (b.custo_lancado + r.remanescente)::numeric(18,2) as estimativa_conclusao,
  (b.custo_lancado + r.remanescente - b.orcamento_vigente)::numeric(18,2) as desvio,
  null::numeric(18,2) as compromissos_nao_faturados,
  (b.custo_com_categoria / nullif(b.custo_lancado, 0))::numeric(9,6) as cobertura_classificacao,
  case when b.orcamento_vigente is null then 'orcamento_ausente' end as motivo
from base b
-- greatest ignora nulo; sem orçamento o remanescente tem de ficar nulo, não virar zero
cross join lateral (
  select case when b.orcamento_vigente is not null then greatest(b.orcamento_vigente - b.custo_lancado, 0) end as remanescente
) r;

-- Totais por tenant em dois grupos: obras e "Despesas sem obra". Orçamento consolidado só quando
-- todas as obras do grupo têm orçamento; senão fica nulo com o motivo, para não somar parcial.
create view marts.custo_obra_resumo_consolidado with (security_invoker = true) as
with grupo as (
  select r.*, case r.tipo_centro when 'obra' then 'obras' else 'despesas_sem_obra' end as grupo
  from marts.custo_obra_resumo r
), agregado as (
  select g.tenant_id, g.grupo,
    count(*) as quantidade_centros,
    count(*) filter (where g.orcamento_vigente is null) as centros_sem_orcamento,
    sum(g.orcamento_vigente) as orcamento_vigente,
    sum(g.custo_lancado) as custo_lancado,
    sum(g.desembolsado) as desembolsado,
    sum(g.em_aberto_vencido) as em_aberto_vencido,
    sum(g.em_aberto_a_vencer) as em_aberto_a_vencer,
    sum(g.ajuste_baixa) as ajuste_baixa,
    sum(g.remanescente_sem_titulo) as remanescente_sem_titulo,
    sum(g.estimativa_conclusao) as estimativa_conclusao,
    sum(g.desvio) as desvio
  from grupo g
  group by g.tenant_id, g.grupo
), classificado as (
  select k.tenant_id, case k.tipo_centro when 'obra' then 'obras' else 'despesas_sem_obra' end as grupo,
    sum(k.custo_lancado) filter (where k.categoria_codigo is not null) as custo_com_categoria
  from marts.custo_obra_categoria k
  group by 1, 2
)
select a.tenant_id, a.grupo,
  a.quantidade_centros::integer as quantidade_centros,
  case when a.grupo = 'obras' then a.centros_sem_orcamento end::integer as centros_sem_orcamento,
  case when a.grupo = 'obras' and a.centros_sem_orcamento = 0 then a.orcamento_vigente end::numeric(18,2) as orcamento_vigente,
  a.custo_lancado::numeric(18,2) as custo_lancado,
  a.desembolsado::numeric(18,2) as desembolsado,
  a.em_aberto_vencido::numeric(18,2) as em_aberto_vencido,
  a.em_aberto_a_vencer::numeric(18,2) as em_aberto_a_vencer,
  a.ajuste_baixa::numeric(18,2) as ajuste_baixa,
  case when a.grupo = 'obras' and a.centros_sem_orcamento = 0 then a.remanescente_sem_titulo end::numeric(18,2)
    as remanescente_sem_titulo,
  case when a.grupo = 'obras' and a.centros_sem_orcamento = 0 then a.estimativa_conclusao end::numeric(18,2)
    as estimativa_conclusao,
  case when a.grupo = 'obras' and a.centros_sem_orcamento = 0 then a.desvio end::numeric(18,2) as desvio,
  (coalesce(cl.custo_com_categoria, 0) / nullif(a.custo_lancado, 0))::numeric(9,6) as cobertura_classificacao,
  case when a.grupo <> 'obras' or a.centros_sem_orcamento = 0 then null
       when a.centros_sem_orcamento = a.quantidade_centros then 'orcamento_ausente'
       else 'consolidado_parcial' end as motivo
from agregado a
left join classificado cl on cl.tenant_id = a.tenant_id and cl.grupo = a.grupo;

-- Dois eixos de tempo em colunas separadas: competência do título e data do dinheiro.
create view marts.despesa_mensal with (security_invoker = true) as
with referencia as (
  select app.data_referencia() as ref
), movimento as (
  select a.tenant_id, a.centro_custo_id, date_trunc('month', a.data_competencia)::date as competencia,
         a.categoria_codigo, a.valor_original as lancado_competencia, 0::numeric as pago,
         0::numeric as a_pagar, 0::numeric as vencido
  from marts.apropriacao_classificada a
  where a.data_competencia is not null
  union all
  select pg.tenant_id, pg.centro_custo_id, date_trunc('month', pg.data_pagamento)::date, m.categoria_codigo,
         0, pg.valor, 0, 0
  from staging.pagamento pg
  left join app.mapa_conta_origem m
    on m.tenant_id = pg.tenant_id and m.tipo_origem = 'titulo_pagar' and m.conta_origem = pg.conta_origem
  union all
  select a.tenant_id, a.centro_custo_id, date_trunc('month', a.vencimento)::date, a.categoria_codigo, 0, 0,
         case when a.vencimento >= r.ref then a.saldo else 0 end,
         case when a.vencimento < r.ref then a.saldo else 0 end
  from marts.apropriacao_classificada a
  cross join referencia r
  where a.saldo > 0
)
select mv.tenant_id, mv.centro_custo_id, mv.competencia, mv.categoria_codigo,
  coalesce(c.nome, 'Sem categoria') as categoria_nome, c.grupo_dre,
  sum(mv.lancado_competencia)::numeric(18,2) as lancado_competencia,
  sum(mv.pago)::numeric(18,2) as pago,
  sum(mv.a_pagar)::numeric(18,2) as a_pagar,
  sum(mv.vencido)::numeric(18,2) as vencido
from movimento mv
left join app.categoria_gerencial c on c.codigo = mv.categoria_codigo
group by mv.tenant_id, mv.centro_custo_id, mv.competencia, mv.categoria_codigo, c.nome, c.grupo_dre;

-- Contas vistas no staging sem categoria. A participação é sobre todo o valor visível do mesmo tipo.
create view marts.pendencia_classificacao with (security_invoker = true) as
with lancamento as (
  select a.tenant_id, 'titulo_pagar' as tipo_origem, a.conta_origem, a.valor_original as valor,
         a.categoria_codigo is null as pendente, date_trunc('month', a.data_competencia)::date as competencia
  from marts.apropriacao_classificada a
  union all
  select p.tenant_id, 'parcela_receber', p.conta_origem, p.valor_original,
         m.categoria_codigo is null, date_trunc('month', p.data_emissao)::date
  from staging.parcela_receber p
  left join app.mapa_conta_origem m
    on m.tenant_id = p.tenant_id and m.tipo_origem = 'parcela_receber' and m.conta_origem = p.conta_origem
  union all
  select o.tenant_id, 'orcamento', o.codigo, o.valor_total, m.categoria_codigo is null, null::date
  from staging.item_orcamento o
  left join app.mapa_conta_origem m
    on m.tenant_id = o.tenant_id and m.tipo_origem = 'orcamento' and m.conta_origem = o.codigo
), por_conta as (
  select l.tenant_id, l.tipo_origem, l.conta_origem, bool_or(l.pendente) as pendente,
    count(*) as quantidade_lancamentos,
    sum(l.valor) as valor_envolvido,
    sum(sum(l.valor)) over (partition by l.tenant_id, l.tipo_origem) as valor_tipo,
    min(l.competencia) as primeira_competencia,
    max(l.competencia) as ultima_competencia
  from lancamento l
  group by l.tenant_id, l.tipo_origem, l.conta_origem
)
select pc.tenant_id, pc.tipo_origem, pc.conta_origem,
  pc.quantidade_lancamentos::integer as quantidade_lancamentos,
  pc.valor_envolvido::numeric(18,2) as valor_envolvido,
  (pc.valor_envolvido / nullif(pc.valor_tipo, 0))::numeric(9,6) as participacao,
  pc.primeira_competencia, pc.ultima_competencia
from por_conta pc
where pc.pendente;

-- Percentual de conclusão por obra e mês. Fatos (custo incorrido, VGV ativo, unidades vendidas) saem
-- sempre; receita e custo reconhecidos só com o critério validado e sem nenhum motivo de bloqueio.
-- O(M x C) na junção do calendário com os contratos (M meses, C contratos da obra): cerca de 30 mil
-- linhas por tenant no volume do piloto.
create view marts.reconhecimento_obra_mensal with (security_invoker = true) as
with referencia as (
  select date_trunc('month', app.data_referencia())::date as mes_ref
), obra as (
  select cc.tenant_id, cc.id as centro_custo_id
  from app.centro_custo cc
  where cc.tipo = 'obra'
), criterio as (
  select o.tenant_id, o.centro_custo_id, coalesce(co.metodo, ct.metodo, 'nao_definido') as metodo
  from obra o
  left join app.criterio_reconhecimento co on co.tenant_id = o.tenant_id and co.centro_custo_id = o.centro_custo_id
  left join app.criterio_reconhecimento ct on ct.tenant_id = o.tenant_id and ct.centro_custo_id is null
), apropriacao as (
  select a.tenant_id, a.centro_custo_id, date_trunc('month', a.data_competencia)::date as competencia,
         a.categoria_codigo, a.grupo_dre, a.valor_original, a.data_competencia
  from marts.apropriacao_classificada a
  join obra o on o.tenant_id = a.tenant_id and o.centro_custo_id = a.centro_custo_id
), custo_obra as (
  select ap.tenant_id, ap.centro_custo_id,
    sum(ap.valor_original) filter (where ap.grupo_dre = 'custo_imovel') as custo_imovel_total,
    min(ap.competencia) as primeiro_mes,
    min(ap.competencia) filter (where ap.categoria_codigo is null) as primeiro_mes_sem_categoria,
    bool_or(ap.data_competencia is null) as tem_sem_competencia
  from apropriacao ap
  group by ap.tenant_id, ap.centro_custo_id
), custo_mes as (
  select ap.tenant_id, ap.centro_custo_id, ap.competencia, sum(ap.valor_original) as custo_imovel_mes
  from apropriacao ap
  where ap.grupo_dre = 'custo_imovel' and ap.competencia is not null
  group by ap.tenant_id, ap.centro_custo_id, ap.competencia
), orcamento as (
  select io.tenant_id, io.centro_custo_id, sum(io.valor_total) as orcamento_vigente
  from staging.item_orcamento io
  group by io.tenant_id, io.centro_custo_id
), unidades as (
  select u.tenant_id, u.centro_custo_id, count(*) as unidades_obra
  from staging.unidade u
  group by u.tenant_id, u.centro_custo_id
), contrato as (
  select c.tenant_id, c.centro_custo_id, c.id_origem, c.valor, c.situacao, c.data_venda, c.data_distrato
  from staging.contrato_venda c
  join obra o on o.tenant_id = c.tenant_id and o.centro_custo_id = c.centro_custo_id
  where c.data_venda is not null
), inicio as (
  select x.tenant_id, x.centro_custo_id, min(x.mes) as primeiro_mes
  from (
    select c.tenant_id, c.centro_custo_id, date_trunc('month', c.data_venda)::date as mes from contrato c
    union all
    select co.tenant_id, co.centro_custo_id, co.primeiro_mes from custo_obra co where co.primeiro_mes is not null
  ) x
  group by x.tenant_id, x.centro_custo_id
), calendario as (
  select i.tenant_id, i.centro_custo_id, g::date as competencia,
         (g + interval '1 month' - interval '1 day')::date as fim_mes
  from inicio i
  cross join referencia r
  cross join lateral generate_series(i.primeiro_mes, r.mes_ref, interval '1 month') g
), contrato_ativo as (
  -- contrato vale no fim do mês se já foi vendido e não foi distratado até lá
  select k.tenant_id, k.centro_custo_id, k.competencia, c.id_origem, c.valor
  from calendario k
  join contrato c
    on c.tenant_id = k.tenant_id and c.centro_custo_id = k.centro_custo_id and c.data_venda <= k.fim_mes
   and (c.situacao = '1' or (c.situacao = '3' and c.data_distrato > k.fim_mes))
), vgv as (
  select ca.tenant_id, ca.centro_custo_id, ca.competencia, sum(ca.valor) as vgv_ativo_fim_mes
  from contrato_ativo ca
  group by ca.tenant_id, ca.centro_custo_id, ca.competencia
), vendidas as (
  select ca.tenant_id, ca.centro_custo_id, ca.competencia, count(distinct cu.unidade_id_origem) as unidades_vendidas
  from contrato_ativo ca
  join staging.contrato_unidade cu on cu.tenant_id = ca.tenant_id and cu.contrato_id_origem = ca.id_origem
  group by ca.tenant_id, ca.centro_custo_id, ca.competencia
), base as (
  select k.tenant_id, k.centro_custo_id, k.competencia, cr.metodo,
    sum(coalesce(cm.custo_imovel_mes, 0))
      over (partition by k.tenant_id, k.centro_custo_id order by k.competencia) as custo_incorrido_acumulado,
    case when o.orcamento_vigente is not null
         then greatest(o.orcamento_vigente, coalesce(co.custo_imovel_total, 0)) end as custo_total_estimado,
    o.orcamento_vigente,
    coalesce(v.vgv_ativo_fim_mes, 0) as vgv_ativo_fim_mes,
    coalesce(u.unidades_obra, 0) as unidades_obra,
    coalesce(vd.unidades_vendidas, 0) as unidades_vendidas_fim_mes,
    co.primeiro_mes_sem_categoria <= k.competencia as tem_sem_categoria,
    coalesce(co.tem_sem_competencia, false) as tem_sem_competencia
  from calendario k
  join criterio cr on cr.tenant_id = k.tenant_id and cr.centro_custo_id = k.centro_custo_id
  left join custo_obra co on co.tenant_id = k.tenant_id and co.centro_custo_id = k.centro_custo_id
  left join custo_mes cm on cm.tenant_id = k.tenant_id and cm.centro_custo_id = k.centro_custo_id
                        and cm.competencia = k.competencia
  left join orcamento o on o.tenant_id = k.tenant_id and o.centro_custo_id = k.centro_custo_id
  left join unidades u on u.tenant_id = k.tenant_id and u.centro_custo_id = k.centro_custo_id
  left join vgv v on v.tenant_id = k.tenant_id and v.centro_custo_id = k.centro_custo_id and v.competencia = k.competencia
  left join vendidas vd on vd.tenant_id = k.tenant_id and vd.centro_custo_id = k.centro_custo_id
                       and vd.competencia = k.competencia
), motivo as (
  select b.*,
    case
      when b.metodo <> 'percentual_conclusao' then 'criterio_nao_validado'
      when b.orcamento_vigente is null or b.custo_total_estimado <= 0 then 'orcamento_ausente'
      when b.unidades_obra = 0 then 'unidades_ausentes'
      when b.tem_sem_categoria then 'custo_sem_categoria'
      when b.tem_sem_competencia then 'custo_sem_competencia'
    end as motivo
  from base b
), acumulado as (
  -- precisão cheia até o arredondamento final; o teto de 100% vale para a receita
  select mo.*,
    case when mo.custo_total_estimado > 0
         then round(least(mo.vgv_ativo_fim_mes * mo.custo_incorrido_acumulado / mo.custo_total_estimado,
                          mo.vgv_ativo_fim_mes), 2) end as receita_acumulada,
    case when mo.unidades_obra > 0
         then round(mo.custo_incorrido_acumulado * mo.unidades_vendidas_fim_mes / mo.unidades_obra, 2) end
      as custo_acumulado
  from motivo mo
), mensal as (
  select ac.*,
    ac.receita_acumulada - coalesce(lag(ac.receita_acumulada) over w, 0) as receita_mes,
    ac.custo_acumulado - coalesce(lag(ac.custo_acumulado) over w, 0) as custo_mes
  from acumulado ac
  window w as (partition by ac.tenant_id, ac.centro_custo_id order by ac.competencia)
)
select m.tenant_id, m.centro_custo_id, m.competencia, m.metodo,
  m.motivo is null as disponivel,
  m.motivo,
  m.custo_incorrido_acumulado::numeric(18,2) as custo_incorrido_acumulado,
  m.custo_total_estimado::numeric(18,2) as custo_total_estimado,
  case when m.motivo is null then least(m.custo_incorrido_acumulado / m.custo_total_estimado, 1) end::numeric(9,6) as poc,
  m.vgv_ativo_fim_mes::numeric(18,2) as vgv_ativo_fim_mes,
  m.unidades_obra::integer as unidades_obra,
  m.unidades_vendidas_fim_mes::integer as unidades_vendidas_fim_mes,
  case when m.motivo is null then m.unidades_vendidas_fim_mes::numeric / m.unidades_obra end::numeric(9,6) as fracao_vendida,
  case when m.motivo is null then m.receita_acumulada end::numeric(18,2) as receita_reconhecida_acumulada,
  case when m.motivo is null then m.custo_acumulado end::numeric(18,2) as custo_reconhecido_acumulado,
  case when m.motivo is null then m.receita_mes end::numeric(18,2) as receita_reconhecida_mes,
  case when m.motivo is null then m.custo_mes end::numeric(18,2) as custo_reconhecido_mes
from mensal m;

-- DRE em formato longo por centro e mês. Custo de obra fica na linha informativa 100 e nunca entra
-- nas somas: vai para o estoque e sai pelo custo reconhecido. Não existe linha de lucro líquido.
create view marts.dre_mensal with (security_invoker = true) as
with referencia as (
  select date_trunc('month', app.data_referencia())::date as mes_ref
), titulo as (
  select a.tenant_id, a.centro_custo_id, date_trunc('month', a.data_competencia)::date as competencia,
    coalesce(sum(a.valor_original) filter (where a.grupo_dre = 'deducao_receita'), 0) as deducao,
    coalesce(sum(a.valor_original) filter (where a.grupo_dre = 'despesa_comercial'), 0) as comercial,
    coalesce(sum(a.valor_original) filter (where a.grupo_dre = 'despesa_administrativa'), 0) as administrativa,
    coalesce(sum(a.valor_original) filter (where a.grupo_dre = 'resultado_financeiro'), 0) as financeira,
    coalesce(sum(a.valor_original) filter (where a.grupo_dre = 'custo_imovel'), 0) as custo_obra,
    coalesce(sum(a.valor_original) filter (where a.grupo_dre = 'fora_do_resultado'), 0) as fora,
    coalesce(sum(a.valor_original) filter (where a.categoria_codigo is null), 0) as sem_categoria,
    coalesce(sum(a.valor_original) filter (where a.categoria_codigo is not null), 0) as com_categoria,
    sum(a.valor_original) as total
  from marts.apropriacao_classificada a
  group by a.tenant_id, a.centro_custo_id, date_trunc('month', a.data_competencia)
), parcela as (
  -- só parcela classificada em receita financeira ou fora do resultado; venda vem do reconhecimento
  select p.tenant_id, p.centro_custo_id, date_trunc('month', p.data_emissao)::date as competencia,
    coalesce(sum(p.valor_original) filter (where c.grupo_dre = 'resultado_financeiro'), 0) as receita_financeira,
    coalesce(sum(p.valor_original) filter (where c.grupo_dre = 'fora_do_resultado'), 0) as fora
  from staging.parcela_receber p
  join app.mapa_conta_origem m
    on m.tenant_id = p.tenant_id and m.tipo_origem = 'parcela_receber' and m.conta_origem = p.conta_origem
  join app.categoria_gerencial c on c.codigo = m.categoria_codigo
  where c.grupo_dre in ('resultado_financeiro', 'fora_do_resultado')
  group by p.tenant_id, p.centro_custo_id, date_trunc('month', p.data_emissao)
), reconhecimento as (
  select * from marts.reconhecimento_obra_mensal
), criterio as (
  select cc.tenant_id, cc.id as centro_custo_id, coalesce(co.metodo, ct.metodo, 'nao_definido') as metodo
  from app.centro_custo cc
  left join app.criterio_reconhecimento co on co.tenant_id = cc.tenant_id and co.centro_custo_id = cc.id
  left join app.criterio_reconhecimento ct on ct.tenant_id = cc.tenant_id and ct.centro_custo_id is null
  where cc.tipo = 'obra'
), evento as (
  select t.tenant_id, t.centro_custo_id, t.competencia from titulo t
  union all
  select p.tenant_id, p.centro_custo_id, p.competencia from parcela p
  union all
  select rc.tenant_id, rc.centro_custo_id, rc.competencia from reconhecimento rc
), centro as (
  select e.tenant_id, e.centro_custo_id, min(e.competencia) as primeiro_mes
  from evento e
  group by e.tenant_id, e.centro_custo_id
), calendario as (
  select ce.tenant_id, ce.centro_custo_id, g::date as competencia
  from centro ce
  cross join referencia r
  cross join lateral generate_series(ce.primeiro_mes, r.mes_ref, interval '1 month') g
  where ce.primeiro_mes is not null
), mensal as (
  -- mês de obra antes do primeiro contrato e do primeiro custo: nada a reconhecer, zero se o critério vale
  select k.tenant_id, k.centro_custo_id, cc.tipo as tipo_centro, k.competencia,
    case when cc.tipo = 'empresa' then true
         when rc.centro_custo_id is not null then rc.disponivel
         else cr.metodo = 'percentual_conclusao' end as reconhecido_disponivel,
    case when cc.tipo = 'empresa' then null
         when rc.centro_custo_id is not null then rc.motivo
         when cr.metodo = 'percentual_conclusao' then null
         else 'criterio_nao_validado' end as reconhecido_motivo,
    case when cc.tipo = 'empresa' then 0
         when rc.centro_custo_id is not null then rc.receita_reconhecida_mes
         when cr.metodo = 'percentual_conclusao' then 0 end as receita,
    case when cc.tipo = 'empresa' then 0
         when rc.centro_custo_id is not null then -rc.custo_reconhecido_mes
         when cr.metodo = 'percentual_conclusao' then 0 end as custo_vendido,
    -coalesce(t.deducao, 0) as deducao,
    -coalesce(t.comercial, 0) as comercial,
    -coalesce(t.administrativa, 0) as administrativa,
    coalesce(p.receita_financeira, 0) - coalesce(t.financeira, 0) as financeiro,
    -coalesce(t.custo_obra, 0) as custo_obra,
    coalesce(p.fora, 0) - coalesce(t.fora, 0) as fora,
    -coalesce(t.sem_categoria, 0) as sem_categoria,
    coalesce(t.com_categoria, 0) as valor_com_categoria,
    coalesce(t.total, 0) as valor_total_lancado
  from calendario k
  join app.centro_custo cc on cc.id = k.centro_custo_id
  left join reconhecimento rc on rc.tenant_id = k.tenant_id and rc.centro_custo_id = k.centro_custo_id
                             and rc.competencia = k.competencia
  left join criterio cr on cr.tenant_id = k.tenant_id and cr.centro_custo_id = k.centro_custo_id
  left join titulo t on t.tenant_id = k.tenant_id and t.centro_custo_id = k.centro_custo_id and t.competencia = k.competencia
  left join parcela p on p.tenant_id = k.tenant_id and p.centro_custo_id = k.centro_custo_id and p.competencia = k.competencia
), linha as (
  select m.tenant_id, m.centro_custo_id, m.tipo_centro, m.competencia, l.linha_ordem, l.linha_codigo, l.linha_nome,
         case when l.disponivel then l.valor end as valor_mes, l.disponivel,
         case when not l.disponivel then m.reconhecido_motivo end as motivo,
         m.valor_com_categoria, m.valor_total_lancado
  from mensal m
  cross join lateral (values
    (10, 'receita_bruta', 'Receita bruta reconhecida', m.receita, m.reconhecido_disponivel),
    (20, 'deducoes', 'Deduções e tributos sobre a receita', m.deducao, true),
    (30, 'receita_liquida', 'Receita líquida', m.receita + m.deducao, m.reconhecido_disponivel),
    (40, 'custo_imovel_vendido', 'Custo reconhecido dos imóveis vendidos', m.custo_vendido, m.reconhecido_disponivel),
    (50, 'resultado_bruto', 'Resultado bruto', m.receita + m.deducao + m.custo_vendido, m.reconhecido_disponivel),
    (60, 'despesas_comerciais', 'Despesas comerciais', m.comercial, true),
    (70, 'despesas_administrativas', 'Despesas administrativas', m.administrativa, true),
    (80, 'resultado_financeiro', 'Resultado financeiro', m.financeiro, true),
    (90, 'resultado_gerencial', 'Resultado gerencial do período',
         m.receita + m.deducao + m.custo_vendido + m.comercial + m.administrativa + m.financeiro, m.reconhecido_disponivel),
    (100, 'custo_obra_incorrido', 'Custo de obra lançado no mês (vai para o estoque)', m.custo_obra, true),
    (110, 'fora_do_resultado', 'Movimentos fora do resultado', m.fora, true),
    (120, 'sem_categoria', 'Lançamentos sem categoria', m.sem_categoria, true)
  ) as l(linha_ordem, linha_codigo, linha_nome, valor, disponivel)
), linha_acumulada as (
  select li.*,
    case when bool_and(li.disponivel) over w then sum(li.valor_mes) over w end as valor_acumulado
  from linha li
  window w as (partition by li.tenant_id, li.centro_custo_id, li.linha_codigo order by li.competencia)
), sem_data as (
  -- uma linha por centro do DRE, com zero quando todo lançamento tem data
  select ce.tenant_id, ce.centro_custo_id, cc.tipo as tipo_centro,
    coalesce(p.receita_financeira, 0) + coalesce(p.fora, 0) - coalesce(t.total, 0) as valor,
    coalesce(t.com_categoria, 0) as valor_com_categoria,
    coalesce(t.total, 0) as valor_total_lancado
  from centro ce
  join app.centro_custo cc on cc.id = ce.centro_custo_id
  left join titulo t on t.tenant_id = ce.tenant_id and t.centro_custo_id = ce.centro_custo_id and t.competencia is null
  left join parcela p on p.tenant_id = ce.tenant_id and p.centro_custo_id = ce.centro_custo_id and p.competencia is null
)
select la.tenant_id, la.centro_custo_id, la.tipo_centro, la.competencia, la.linha_codigo, la.linha_ordem, la.linha_nome,
  la.valor_mes::numeric(18,2) as valor_mes,
  la.valor_acumulado::numeric(18,2) as valor_acumulado,
  la.disponivel, la.motivo,
  la.valor_com_categoria::numeric(18,2) as valor_com_categoria,
  la.valor_total_lancado::numeric(18,2) as valor_total_lancado,
  (la.valor_com_categoria / nullif(la.valor_total_lancado, 0))::numeric(9,6) as cobertura
from linha_acumulada la
union all
select sd.tenant_id, sd.centro_custo_id, sd.tipo_centro, null::date, 'sem_data_competencia', 130,
  'Lançamentos sem data de competência',
  sd.valor::numeric(18,2), sd.valor::numeric(18,2), true, null::text,
  sd.valor_com_categoria::numeric(18,2), sd.valor_total_lancado::numeric(18,2),
  (sd.valor_com_categoria / nullif(sd.valor_total_lancado, 0))::numeric(9,6)
from sem_data sd;

-- Soma dos centros que o RLS libera. Um centro indisponível deixa a linha do mês indisponível.
create view marts.dre_mensal_consolidado with (security_invoker = true) as
select d.tenant_id, d.competencia, d.linha_codigo, d.linha_ordem, d.linha_nome,
  case when bool_and(d.disponivel) then sum(d.valor_mes) end::numeric(18,2) as valor_mes,
  case when bool_and(d.valor_acumulado is not null) then sum(d.valor_acumulado) end::numeric(18,2) as valor_acumulado,
  bool_and(d.disponivel) as disponivel,
  case when bool_and(d.disponivel) then null
       when bool_and(not d.disponivel) and count(distinct d.motivo) = 1 then min(d.motivo)
       else 'consolidado_parcial' end as motivo,
  sum(d.valor_com_categoria)::numeric(18,2) as valor_com_categoria,
  sum(d.valor_total_lancado)::numeric(18,2) as valor_total_lancado,
  (sum(d.valor_com_categoria) / nullif(sum(d.valor_total_lancado), 0))::numeric(9,6) as cobertura,
  count(distinct d.centro_custo_id)::integer as quantidade_centros
from marts.dre_mensal d
group by d.tenant_id, d.competencia, d.linha_codigo, d.linha_ordem, d.linha_nome;

-- Funções de período: centro nulo é o consolidado do que o usuário enxerga. Numa obra só, o motivo
-- é o do mês indisponível mais recente, porque a mesma obra pode ter motivos diferentes ao longo do tempo.
create function marts.dre_periodo(p_inicio date, p_fim date, p_centro_custo_id uuid default null)
returns table (linha_codigo text, linha_ordem integer, linha_nome text, valor_periodo numeric(18,2),
               disponivel boolean, motivo text, cobertura numeric(9,6))
language sql stable security invoker set search_path = '' as $$
  select d.linha_codigo, d.linha_ordem, d.linha_nome,
    case when bool_and(d.disponivel) then sum(d.valor_mes) end::numeric(18,2),
    bool_and(d.disponivel),
    case when bool_and(d.disponivel) then null
         when p_centro_custo_id is not null
           then (array_agg(d.motivo order by d.competencia desc) filter (where not d.disponivel))[1]
         when bool_and(not d.disponivel) and count(distinct d.motivo) = 1 then min(d.motivo)
         else 'consolidado_parcial' end,
    (sum(d.valor_com_categoria) / nullif(sum(d.valor_total_lancado), 0))::numeric(9,6)
  from marts.dre_mensal d
  where (p_centro_custo_id is null or d.centro_custo_id = p_centro_custo_id)
    and (d.competencia is null
         or d.competencia between date_trunc('month', p_inicio)::date and date_trunc('month', p_fim)::date)
  group by d.linha_codigo, d.linha_ordem, d.linha_nome
  order by d.linha_ordem
$$;

create function marts.recebimento_periodo(p_inicio date, p_fim date, p_centro_custo_id uuid default null)
returns table (origem text, recebido numeric(18,2), previsto_contratual numeric(18,2))
language sql stable security invoker set search_path = '' as $$
  select o.origem,
    coalesce(sum(r.recebido), 0)::numeric(18,2),
    coalesce(sum(r.previsto_contratual), 0)::numeric(18,2)
  from (values ('direta'), ('financiamento')) as o(origem)
  left join marts.recebimento_mensal r
    on r.origem = o.origem
   and (p_centro_custo_id is null or r.centro_custo_id = p_centro_custo_id)
   and r.competencia between date_trunc('month', p_inicio)::date and date_trunc('month', p_fim)::date
  group by o.origem
  order by o.origem
$$;

create function marts.desembolso_periodo(p_inicio date, p_fim date, p_centro_custo_id uuid default null)
returns table (categoria_codigo text, categoria_nome text, grupo_dre text, lancado_competencia numeric(18,2),
               pago numeric(18,2))
language sql stable security invoker set search_path = '' as $$
  select d.categoria_codigo, d.categoria_nome, d.grupo_dre,
    sum(d.lancado_competencia)::numeric(18,2),
    sum(d.pago)::numeric(18,2)
  from marts.despesa_mensal d
  left join app.categoria_gerencial c on c.codigo = d.categoria_codigo
  where (p_centro_custo_id is null or d.centro_custo_id = p_centro_custo_id)
    and d.competencia between date_trunc('month', p_inicio)::date and date_trunc('month', p_fim)::date
  group by d.categoria_codigo, d.categoria_nome, d.grupo_dre, c.ordem
  order by c.ordem nulls last
$$;

revoke execute on function marts.dre_periodo(date, date, uuid), marts.recebimento_periodo(date, date, uuid),
  marts.desembolso_periodo(date, date, uuid) from public, anon;
grant execute on function marts.dre_periodo(date, date, uuid), marts.recebimento_periodo(date, date, uuid),
  marts.desembolso_periodo(date, date, uuid) to authenticated;

grant select on marts.apropriacao_classificada, marts.carteira_recebiveis, marts.resumo_receitas_obra,
  marts.resumo_receitas_consolidado, marts.recebimento_mensal, marts.recebimento_mensal_consolidado,
  marts.custo_obra_categoria, marts.custo_obra_resumo, marts.custo_obra_resumo_consolidado, marts.despesa_mensal,
  marts.pendencia_classificacao, marts.reconhecimento_obra_mensal, marts.dre_mensal, marts.dre_mensal_consolidado
  to authenticated;
