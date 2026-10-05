-- DRE de viabilidade por obra: o estudo digitado (em versões), a alíquota de imposto informada e a view que
-- põe lado a lado viabilidade, apropriado, a apropriar, a contratar e tendência (ver docs/decisoes/0016).
-- Só diretor e financeiro leem; a escrita passa por função, porque a API REST não recebe grant de insert.

-- Uma linha por versão. Nada se altera nem se apaga: gravar de novo cria outra versão e a anterior fica
-- como substituída, e é isso que serve de auditoria (quem gravou e quando, em criado_por e criado_em).
create table app.estudo_viabilidade (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenant(id) on delete cascade,
  centro_custo_id uuid not null references app.centro_custo(id) on delete cascade,
  versao integer not null check (versao > 0),
  descricao text check (length(descricao) <= 120),
  data_base date not null,
  situacao text not null check (situacao in ('vigente', 'substituida')),
  -- Nulo só quando a carga da demo grava direto na tabela.
  criado_por uuid,
  criado_em timestamptz not null default now(),
  unique (tenant_id, centro_custo_id, versao)
);
create unique index estudo_viabilidade_vigente_idx
  on app.estudo_viabilidade (tenant_id, centro_custo_id) where situacao = 'vigente';

-- tenant_id e centro_custo_id repetidos para a política não precisar de junção com o estudo.
create table app.estudo_viabilidade_linha (
  estudo_id uuid not null references app.estudo_viabilidade(id) on delete cascade,
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  linha text not null check (linha in (
    'vgv_bruto', 'impostos', 'custo_terreno', 'custo_projetos', 'custo_licenciamento', 'custo_construcao',
    'assistencia_tecnica', 'juros_financiamento', 'estoque', 'despesas_comerciais', 'despesas_administrativas')),
  valor numeric(14, 2) not null check (valor >= 0 and valor <= 99999999999.99),
  primary key (estudo_id, linha)
);
create index estudo_viabilidade_linha_obra_idx on app.estudo_viabilidade_linha (tenant_id, centro_custo_id);

-- Também só cresce. A vigente é a de maior vigencia_inicio até hoje e, no empate, a gravada por último.
create table app.aliquota_imposto_obra (
  id bigint generated always as identity primary key,
  tenant_id uuid not null references app.tenant(id) on delete cascade,
  centro_custo_id uuid not null references app.centro_custo(id) on delete cascade,
  vigencia_inicio date not null,
  aliquota numeric(7, 6) not null check (aliquota >= 0 and aliquota <= 0.2),
  criado_por uuid,
  criado_em timestamptz not null default now()
);
create index aliquota_imposto_obra_vigencia_idx
  on app.aliquota_imposto_obra (tenant_id, centro_custo_id, vigencia_inicio desc, criado_em desc);

-- Mesma regra nas três: leitura de diretor e financeiro nas obras permitidas, com o segundo fator, e
-- nenhuma política de escrita. O select em volta das funções vira initplan e roda uma vez por consulta.
do $$
declare t text;
begin
  foreach t in array array['estudo_viabilidade', 'estudo_viabilidade_linha', 'aliquota_imposto_obra'] loop
    execute format('alter table app.%I enable row level security', t);
    execute format('alter table app.%I force row level security', t);
    execute format($p$create policy leitura_diretoria on app.%I for select to authenticated
      using (tenant_id = (select app.tenant_atual())
             and centro_custo_id in (select app.obras_permitidas())
             and (select app.perfil_atual()) in ('diretor', 'financeiro'))$p$, t);
    execute format($p$create policy segundo_fator on app.%I as restrictive for all to authenticated
      using ((select app.segundo_fator_cumprido()))$p$, t);
    execute format('revoke all on table app.%I from public, anon, authenticated', t);
    execute format('grant select on table app.%I to authenticated', t);
  end loop;
end $$;
revoke all on sequence app.aliquota_imposto_obra_id_seq from public, anon, authenticated;

-- Grava uma versão nova do estudo e devolve o número dela. Confere usuário, segundo fator, perfil e obra
-- antes de olhar o conteúdo, para o erro de permissão (42501) nunca depender do que foi mandado.
create function app.gravar_viabilidade(
  p_centro_custo_id uuid,
  p_descricao text,
  p_data_base date,
  p_linhas jsonb
) returns integer
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_tenant uuid := app.tenant_atual();
  v_estudo uuid;
  v_versao integer;
  v_no_dia integer;
begin
  if auth.uid() is null or v_tenant is null then
    raise exception 'gravação exige usuário ligado a uma construtora' using errcode = '42501';
  end if;
  if not app.segundo_fator_cumprido() then
    raise exception 'gravação exige o segundo fator' using errcode = '42501';
  end if;
  if coalesce(app.perfil_atual(), '') not in ('diretor', 'financeiro') then
    raise exception 'só diretor e financeiro gravam o estudo' using errcode = '42501';
  end if;
  -- obras_permitidas já filtra pelo tenant atual, então obra de outro tenant cai aqui.
  if p_centro_custo_id is null or p_centro_custo_id not in (select app.obras_permitidas()) then
    raise exception 'obra fora das permitidas' using errcode = '42501';
  end if;

  if p_linhas is null or jsonb_typeof(p_linhas) <> 'object' then
    raise exception 'linhas precisam ser um objeto' using errcode = '22023';
  end if;
  -- case garante a ordem: converter texto para numeric daria erro de cast em vez de 22023.
  if exists (
    select 1
    from jsonb_each(p_linhas) as par
    where par.key not in (select l.linha from marts.linha_resultado l where l.digitavel)
       or case when jsonb_typeof(par.value) <> 'number' then true
               else (par.value)::numeric < 0 or (par.value)::numeric > 99999999999.99 end
  ) then
    raise exception 'linha fora da lista ou valor inválido' using errcode = '22023';
  end if;
  if length(p_descricao) > 120 then
    raise exception 'descrição acima de 120 caracteres' using errcode = '22023';
  end if;
  if p_data_base is null or p_data_base > current_date then
    raise exception 'data-base ausente ou no futuro' using errcode = '22023';
  end if;

  -- Duas gravações simultâneas da mesma obra pegariam o mesmo número de versão sem a trava.
  perform pg_advisory_xact_lock(hashtextextended('estudo_viabilidade:' || p_centro_custo_id::text, 0));

  select count(*) into v_no_dia
  from app.estudo_viabilidade e
  where e.tenant_id = v_tenant and e.centro_custo_id = p_centro_custo_id
    and e.criado_em >= date_trunc('day', now());
  if v_no_dia >= 20 then
    raise exception 'limite' using errcode = 'P0001';
  end if;

  update app.estudo_viabilidade e
  set situacao = 'substituida'
  where e.tenant_id = v_tenant and e.centro_custo_id = p_centro_custo_id and e.situacao = 'vigente';

  select coalesce(max(e.versao), 0) + 1 into v_versao
  from app.estudo_viabilidade e
  where e.tenant_id = v_tenant and e.centro_custo_id = p_centro_custo_id;

  insert into app.estudo_viabilidade (tenant_id, centro_custo_id, versao, descricao, data_base, situacao, criado_por)
  values (v_tenant, p_centro_custo_id, v_versao, p_descricao, p_data_base, 'vigente', auth.uid())
  returning id into v_estudo;

  -- Linha ausente no JSON vale zero: as onze linhas existem em toda versão.
  insert into app.estudo_viabilidade_linha (estudo_id, tenant_id, centro_custo_id, linha, valor)
  select v_estudo, v_tenant, p_centro_custo_id, l.linha, coalesce((p_linhas ->> l.linha)::numeric, 0)
  from marts.linha_resultado l
  where l.digitavel;

  return v_versao;
end;
$$;

create function app.gravar_aliquota_imposto(
  p_centro_custo_id uuid,
  p_vigencia_inicio date,
  p_aliquota numeric
) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_tenant uuid := app.tenant_atual();
begin
  if auth.uid() is null or v_tenant is null then
    raise exception 'gravação exige usuário ligado a uma construtora' using errcode = '42501';
  end if;
  if not app.segundo_fator_cumprido() then
    raise exception 'gravação exige o segundo fator' using errcode = '42501';
  end if;
  if coalesce(app.perfil_atual(), '') not in ('diretor', 'financeiro') then
    raise exception 'só diretor e financeiro gravam a alíquota' using errcode = '42501';
  end if;
  if p_centro_custo_id is null or p_centro_custo_id not in (select app.obras_permitidas()) then
    raise exception 'obra fora das permitidas' using errcode = '42501';
  end if;
  if p_aliquota is null or p_aliquota < 0 or p_aliquota > 0.2 then
    raise exception 'alíquota fora de 0 a 0,2' using errcode = '22023';
  end if;
  if p_vigencia_inicio is null or p_vigencia_inicio > current_date then
    raise exception 'vigência ausente ou no futuro' using errcode = '22023';
  end if;

  insert into app.aliquota_imposto_obra (tenant_id, centro_custo_id, vigencia_inicio, aliquota, criado_por)
  values (v_tenant, p_centro_custo_id, p_vigencia_inicio, p_aliquota, auth.uid());
end;
$$;

revoke execute on function app.gravar_viabilidade(uuid, text, date, jsonb) from public, anon;
revoke execute on function app.gravar_aliquota_imposto(uuid, date, numeric) from public, anon;
grant execute on function app.gravar_viabilidade(uuid, text, date, jsonb) to authenticated;
grant execute on function app.gravar_aliquota_imposto(uuid, date, numeric) to authenticated;

-- Lista fixa das linhas do resultado. Fica em view, e não em tabela, porque não tem tenant.
create view marts.linha_resultado with (security_invoker = true) as
select linha, ordem, nivel, natureza, digitavel, linha_de_total
from (values
  ('vgv_bruto', 10, 0, 'receita', true, false),
  ('impostos', 20, 0, 'deducao', true, false),
  ('vgv_liquido', 30, 0, 'resultado', false, true),
  ('custo_vendas', 40, 0, 'custo', false, true),
  ('custo_empreendimento', 50, 1, 'custo', false, true),
  ('custo_terreno', 51, 2, 'custo', true, false),
  ('custo_projetos', 52, 2, 'custo', true, false),
  ('custo_licenciamento', 53, 2, 'custo', true, false),
  ('custo_construcao', 54, 2, 'custo', true, false),
  ('assistencia_tecnica', 60, 1, 'custo', true, false),
  ('juros_financiamento', 70, 1, 'custo', true, false),
  ('estoque', 80, 1, 'custo', true, false),
  ('resultado_bruto', 90, 0, 'resultado', false, true),
  ('despesas', 100, 0, 'despesa', false, true),
  ('despesas_comerciais', 101, 1, 'despesa', true, false),
  ('despesas_administrativas', 102, 1, 'despesa', true, false),
  ('lucro_operacional', 110, 0, 'resultado', false, true)
) as l (linha, ordem, nivel, natureza, digitavel, linha_de_total);

grant select on marts.linha_resultado to authenticated;

-- Dezessete linhas por obra com estudo vigente. Apropriado é contábil (receita pelo POC e custo incorrido
-- do mapa imobiliário do ERP); sem mapa, o POC é o pago sobre o orçado e o custo vem dos títulos. A tendência
-- do VGV bruto é sempre o vgv_total da posição, e a da construção é o maior entre orçado, lançado e apropriado.
-- Linha sem fonte de realizado (terreno, projetos, despesas) fica com a tendência igual ao estudo até a
-- etapa que liga o saldo contábil. A junção interna com o estudo faz a view herdar a restrição a diretor e
-- financeiro pelo dado, sem perfil no corpo, o que deixa a carga e o dono do banco lerem com filtro próprio.
-- O(obras x linhas) nos totais; o custo real é a posição financeira, O(n) em parcelas e títulos da obra.
create view marts.dre_viabilidade with (security_invoker = true) as
with composicao (total, componente, sinal) as (
  values
    ('vgv_liquido', 'vgv_bruto', 1), ('vgv_liquido', 'impostos', -1),
    ('custo_empreendimento', 'custo_terreno', 1), ('custo_empreendimento', 'custo_projetos', 1),
    ('custo_empreendimento', 'custo_licenciamento', 1), ('custo_empreendimento', 'custo_construcao', 1),
    ('custo_vendas', 'custo_terreno', 1), ('custo_vendas', 'custo_projetos', 1),
    ('custo_vendas', 'custo_licenciamento', 1), ('custo_vendas', 'custo_construcao', 1),
    ('custo_vendas', 'assistencia_tecnica', 1), ('custo_vendas', 'juros_financiamento', 1),
    ('custo_vendas', 'estoque', 1),
    ('resultado_bruto', 'vgv_bruto', 1), ('resultado_bruto', 'impostos', -1),
    ('resultado_bruto', 'custo_terreno', -1), ('resultado_bruto', 'custo_projetos', -1),
    ('resultado_bruto', 'custo_licenciamento', -1), ('resultado_bruto', 'custo_construcao', -1),
    ('resultado_bruto', 'assistencia_tecnica', -1), ('resultado_bruto', 'juros_financiamento', -1),
    ('resultado_bruto', 'estoque', -1),
    ('despesas', 'despesas_comerciais', 1), ('despesas', 'despesas_administrativas', 1),
    ('lucro_operacional', 'vgv_bruto', 1), ('lucro_operacional', 'impostos', -1),
    ('lucro_operacional', 'custo_terreno', -1), ('lucro_operacional', 'custo_projetos', -1),
    ('lucro_operacional', 'custo_licenciamento', -1), ('lucro_operacional', 'custo_construcao', -1),
    ('lucro_operacional', 'assistencia_tecnica', -1), ('lucro_operacional', 'juros_financiamento', -1),
    ('lucro_operacional', 'estoque', -1),
    ('lucro_operacional', 'despesas_comerciais', -1), ('lucro_operacional', 'despesas_administrativas', -1)
), estudo as (
  select e.tenant_id, e.centro_custo_id, e.id as estudo_id, e.versao, e.data_base
  from app.estudo_viabilidade e
  where e.situacao = 'vigente'
), mapa as (
  select distinct on (m.tenant_id, m.centro_custo_id)
    m.tenant_id, m.centro_custo_id, m.competencia,
    coalesce(m.receita_acumulada, 0) as receita_acumulada,
    coalesce(m.custo_incorrido_acumulado, 0) as custo_incorrido_acumulado
  from staging.mapa_imobiliario_mensal m
  join estudo e on e.tenant_id = m.tenant_id and e.centro_custo_id = m.centro_custo_id
  order by m.tenant_id, m.centro_custo_id, m.competencia desc
), aliquota as (
  select distinct on (a.tenant_id, a.centro_custo_id) a.tenant_id, a.centro_custo_id, a.aliquota
  from app.aliquota_imposto_obra a
  where a.vigencia_inicio <= current_date
  order by a.tenant_id, a.centro_custo_id, a.vigencia_inicio desc, a.criado_em desc, a.id desc
), obra as (
  select e.tenant_id, e.centro_custo_id, p.obra, e.estudo_id, e.versao, e.data_base,
    coalesce(m.competencia, date_trunc('month', current_date)::date) as competencia,
    m.competencia is not null as com_mapa,
    a.aliquota,
    p.vgv_vendido, p.estoque_a_vender, p.pago, p.a_pagar, p.custo_orcado, p.custo_a_incorrer,
    -- least evita a apropriar negativo quando um distrato derruba o vendido abaixo da receita do mapa.
    case when m.competencia is not null then least(m.receita_acumulada, p.vgv_vendido)
         when p.custo_orcado > 0 then round(p.vgv_vendido * least(p.pago / p.custo_orcado, 1), 2)
         else 0 end as vgv_apropriado,
    case when m.competencia is not null then m.custo_incorrido_acumulado else p.pago end as construcao_apropriado
  from estudo e
  join marts.posicao_financeira_obra p on p.tenant_id = e.tenant_id and p.centro_custo_id = e.centro_custo_id
  left join mapa m on m.tenant_id = e.tenant_id and m.centro_custo_id = e.centro_custo_id
  left join aliquota a on a.tenant_id = e.tenant_id and a.centro_custo_id = e.centro_custo_id
), fonte as (
  select o.*,
    o.vgv_vendido - o.vgv_apropriado as vgv_a_apropriar,
    o.estoque_a_vender as vgv_a_contratar,
    case when o.com_mapa then greatest(o.pago + o.a_pagar - o.construcao_apropriado, 0)
         else o.a_pagar end as construcao_a_apropriar,
    case when o.com_mapa then greatest(o.custo_orcado - greatest(o.pago + o.a_pagar, o.construcao_apropriado), 0)
         else o.custo_a_incorrer end as construcao_a_contratar
  from obra o
), digitavel as (
  select f.tenant_id, f.centro_custo_id, el.linha, el.valor as viabilidade,
    case el.linha
      when 'vgv_bruto' then f.vgv_apropriado
      when 'impostos' then case when f.aliquota is not null then round(f.aliquota * f.vgv_apropriado, 2) else 0 end
      when 'custo_construcao' then f.construcao_apropriado
      else 0 end as apropriado,
    case el.linha
      when 'vgv_bruto' then f.vgv_a_apropriar
      when 'impostos' then case when f.aliquota is not null then round(f.aliquota * f.vgv_a_apropriar, 2) else 0 end
      when 'custo_construcao' then f.construcao_a_apropriar
      else 0 end as a_apropriar,
    case el.linha
      when 'vgv_bruto' then f.vgv_a_contratar
      when 'impostos' then case when f.aliquota is not null then round(f.aliquota * f.vgv_a_contratar, 2) else el.valor end
      when 'custo_construcao' then f.construcao_a_contratar
      else el.valor end as a_contratar,
    case el.linha
      when 'vgv_bruto' then case when f.com_mapa then 'origem' else 'titulos' end
      when 'impostos' then case when f.aliquota is not null then 'aliquota' else 'sem_fonte' end
      when 'custo_construcao' then case when f.com_mapa then 'origem' else 'titulos' end
      else 'sem_fonte' end as fonte_realizado
  from fonte f
  join app.estudo_viabilidade_linha el on el.estudo_id = f.estudo_id
), total as (
  select d.tenant_id, d.centro_custo_id, c.total as linha,
    sum(d.viabilidade * c.sinal) as viabilidade,
    sum(d.apropriado * c.sinal) as apropriado,
    sum(d.a_apropriar * c.sinal) as a_apropriar,
    sum(d.a_contratar * c.sinal) as a_contratar,
    'total' as fonte_realizado
  from digitavel d
  join composicao c on c.componente = d.linha
  group by d.tenant_id, d.centro_custo_id, c.total
), medida as (
  select tenant_id, centro_custo_id, linha, fonte_realizado,
    round(viabilidade, 2) as viabilidade, round(apropriado, 2) as apropriado,
    round(a_apropriar, 2) as a_apropriar, round(a_contratar, 2) as a_contratar,
    round(apropriado + a_apropriar + a_contratar, 2) as tendencia
  from (
    select tenant_id, centro_custo_id, linha, viabilidade, apropriado, a_apropriar, a_contratar, fonte_realizado from digitavel
    union all
    select tenant_id, centro_custo_id, linha, viabilidade, apropriado, a_apropriar, a_contratar, fonte_realizado from total
  ) as medidas
), vgv_liquido as (
  select tenant_id, centro_custo_id, viabilidade, tendencia
  from medida
  where linha = 'vgv_liquido'
)
select o.tenant_id, o.centro_custo_id, o.obra, o.competencia,
  o.versao as estudo_versao, o.data_base as estudo_data_base,
  l.linha, r.ordem, r.nivel, r.natureza, r.linha_de_total, l.fonte_realizado,
  l.viabilidade,
  round(l.viabilidade / nullif(v.viabilidade, 0), 4) as pct_viabilidade,
  l.apropriado, l.a_apropriar, l.a_contratar,
  l.a_apropriar + l.a_contratar as a_realizar,
  l.tendencia,
  round(l.tendencia / nullif(v.tendencia, 0), 4) as pct_tendencia,
  l.tendencia - l.viabilidade as desvio,
  round((l.tendencia - l.viabilidade) / nullif(l.viabilidade, 0), 4) as desvio_pct,
  case
    when l.tendencia - l.viabilidade = 0 then null
    when r.natureza in ('receita', 'resultado') then l.tendencia > l.viabilidade
    else l.tendencia < l.viabilidade
  end as desvio_favoravel
from medida l
join obra o on o.tenant_id = l.tenant_id and o.centro_custo_id = l.centro_custo_id
join marts.linha_resultado r on r.linha = l.linha
join vgv_liquido v on v.tenant_id = l.tenant_id and v.centro_custo_id = l.centro_custo_id;

grant select on marts.dre_viabilidade to authenticated;

-- Uma linha por obra com estudo, para o cartão da obra e a visão geral. As margens são as frações do lucro
-- operacional sobre o VGV líquido, as mesmas de pct_viabilidade e pct_tendencia na DRE.
create view marts.dre_resumo_obra with (security_invoker = true) as
with pivot as (
  select d.tenant_id, d.centro_custo_id, d.obra, d.competencia, d.estudo_versao,
    max(d.viabilidade) filter (where d.linha = 'vgv_bruto') as vgv_bruto_viabilidade,
    max(d.tendencia) filter (where d.linha = 'vgv_bruto') as vgv_bruto_tendencia,
    max(d.apropriado) filter (where d.linha = 'vgv_bruto') as receita_apropriada,
    max(d.apropriado) filter (where d.linha = 'custo_vendas') as custo_apropriado,
    max(d.viabilidade) filter (where d.linha = 'resultado_bruto') as resultado_bruto_viabilidade,
    max(d.tendencia) filter (where d.linha = 'resultado_bruto') as resultado_bruto_tendencia,
    max(d.viabilidade) filter (where d.linha = 'lucro_operacional') as lucro_operacional_viabilidade,
    max(d.tendencia) filter (where d.linha = 'lucro_operacional') as lucro_operacional_tendencia,
    max(d.pct_viabilidade) filter (where d.linha = 'lucro_operacional') as margem_operacional_viabilidade,
    max(d.pct_tendencia) filter (where d.linha = 'lucro_operacional') as margem_operacional_tendencia
  from marts.dre_viabilidade d
  group by d.tenant_id, d.centro_custo_id, d.obra, d.competencia, d.estudo_versao
)
select v.tenant_id, v.centro_custo_id, v.obra, v.competencia, v.estudo_versao,
  v.vgv_bruto_viabilidade, v.vgv_bruto_tendencia,
  p.vgv_vendido,
  round(p.vgv_vendido / nullif(v.vgv_bruto_tendencia, 0), 4) as pct_vendido,
  v.receita_apropriada,
  round(v.receita_apropriada / nullif(p.vgv_vendido, 0), 4) as poc,
  v.custo_apropriado,
  p.recebido_direto + p.recebido_repasse as recebido_acumulado,
  v.resultado_bruto_viabilidade, v.resultado_bruto_tendencia,
  v.lucro_operacional_viabilidade, v.lucro_operacional_tendencia,
  v.margem_operacional_viabilidade, v.margem_operacional_tendencia,
  v.margem_operacional_tendencia - v.margem_operacional_viabilidade as desvio_margem_operacional
from pivot v
join marts.posicao_financeira_obra p on p.tenant_id = v.tenant_id and p.centro_custo_id = v.centro_custo_id;

grant select on marts.dre_resumo_obra to authenticated;
