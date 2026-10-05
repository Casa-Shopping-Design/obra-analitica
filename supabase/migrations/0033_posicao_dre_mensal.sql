-- Posição mensal da DRE de viabilidade gravada pela carga (plano APO, etapa 9; ver docs/decisoes/0018).
-- marts.dre_viabilidade só conhece o hoje. Para a tendência andar no tempo, a carga copia as onze linhas
-- digitáveis de cada obra para a competência corrente, e a view soma os totais por obra e mês.

-- Só as linhas digitáveis entram; os totais saem da view com a composição do anexo C. A chave primária já é
-- o índice da política (tenant e obra) e da agregação por obra e mês.
create table app.posicao_dre_mensal (
  tenant_id uuid not null references app.tenant(id) on delete cascade,
  centro_custo_id uuid not null references app.centro_custo(id) on delete cascade,
  competencia date not null check (competencia = date_trunc('month', competencia)::date),
  linha text not null check (linha in (
    'vgv_bruto', 'impostos', 'custo_terreno', 'custo_projetos', 'custo_licenciamento', 'custo_construcao',
    'assistencia_tecnica', 'juros_financiamento', 'estoque', 'despesas_comerciais', 'despesas_administrativas')),
  viabilidade numeric(14, 2) not null,
  apropriado numeric(14, 2) not null,
  a_apropriar numeric(14, 2) not null,
  a_contratar numeric(14, 2) not null,
  tendencia numeric(14, 2) not null check (tendencia = apropriado + a_apropriar + a_contratar),
  gravado_em timestamptz not null default now(),
  primary key (tenant_id, centro_custo_id, competencia, linha)
);

-- Leitura de diretor, financeiro e leitura nas obras permitidas, com a restritiva do segundo fator (0022) e
-- nenhuma política de escrita: só a carga grava, pela função abaixo, como dona do banco.
alter table app.posicao_dre_mensal enable row level security;
alter table app.posicao_dre_mensal force row level security;
create policy leitura_dre on app.posicao_dre_mensal for select to authenticated
  using (tenant_id = (select app.tenant_atual())
         and centro_custo_id in (select app.obras_permitidas())
         and (select app.perfil_atual()) in ('diretor', 'financeiro', 'leitura'));
create policy segundo_fator on app.posicao_dre_mensal as restrictive for all to authenticated
  using ((select app.segundo_fator_cumprido()));
revoke all on table app.posicao_dre_mensal from public, anon, authenticated;
grant select on table app.posicao_dre_mensal to authenticated;

-- Grava a posição do mês corrente do tenant e devolve quantas linhas gravou. Roda como dona do banco, que
-- passa por fora do RLS, por isso o filtro de tenant é explícito na leitura da view. Uma instrução
-- insert ... select; rodar de novo no mesmo mês sobrescreve a mesma linha em vez de duplicar.
create function app.registrar_posicao_dre(p_tenant uuid) returns integer
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_linhas integer;
begin
  if p_tenant is null then
    raise exception 'tenant ausente' using errcode = '22023';
  end if;

  insert into app.posicao_dre_mensal
    (tenant_id, centro_custo_id, competencia, linha, viabilidade, apropriado, a_apropriar, a_contratar, tendencia, gravado_em)
  select d.tenant_id, d.centro_custo_id, date_trunc('month', current_date)::date, d.linha,
    d.viabilidade, d.apropriado, d.a_apropriar, d.a_contratar, d.tendencia, now()
  from marts.dre_viabilidade d
  join marts.linha_resultado l on l.linha = d.linha
  where d.tenant_id = p_tenant and l.digitavel
  on conflict (tenant_id, centro_custo_id, competencia, linha) do update
    set viabilidade = excluded.viabilidade,
        apropriado = excluded.apropriado,
        a_apropriar = excluded.a_apropriar,
        a_contratar = excluded.a_contratar,
        tendencia = excluded.tendencia,
        gravado_em = excluded.gravado_em;

  get diagnostics v_linhas = row_count;
  return v_linhas;
end;
$$;

revoke execute on function app.registrar_posicao_dre(uuid) from public, anon, authenticated;

-- Uma linha por obra e mês com os totais do estudo e da tendência. A composição é a do anexo C, seção C.2:
-- VGV líquido é VGV bruto menos impostos; custo de vendas soma terreno, projetos, licenciamento, construção,
-- assistência, juros e estoque; despesas somam comerciais e administrativas; lucro operacional é o VGV
-- líquido menos custo de vendas e despesas. As margens são o lucro sobre o VGV líquido da mesma coluna.
-- Sem perfil no corpo: o RLS da tabela decide o que cada um vê, e a carga lê como dona com filtro próprio.
-- O(linhas) com uma passada por obra e mês, agrupada pela chave primária.
create view marts.tendencia_resultado_mensal with (security_invoker = true) as
with soma as (
  select p.tenant_id, p.centro_custo_id, p.competencia,
    coalesce(sum(p.viabilidade) filter (where p.linha = 'vgv_bruto'), 0)
      - coalesce(sum(p.viabilidade) filter (where p.linha = 'impostos'), 0) as vgv_liquido_viabilidade,
    coalesce(sum(p.tendencia) filter (where p.linha = 'vgv_bruto'), 0)
      - coalesce(sum(p.tendencia) filter (where p.linha = 'impostos'), 0) as vgv_liquido_tendencia,
    coalesce(sum(p.viabilidade) filter (where p.linha in (
      'custo_terreno', 'custo_projetos', 'custo_licenciamento', 'custo_construcao',
      'assistencia_tecnica', 'juros_financiamento', 'estoque')), 0) as custo_vendas_viabilidade,
    coalesce(sum(p.tendencia) filter (where p.linha in (
      'custo_terreno', 'custo_projetos', 'custo_licenciamento', 'custo_construcao',
      'assistencia_tecnica', 'juros_financiamento', 'estoque')), 0) as custo_vendas_tendencia,
    coalesce(sum(p.viabilidade) filter (where p.linha in ('despesas_comerciais', 'despesas_administrativas')), 0)
      as despesas_viabilidade,
    coalesce(sum(p.tendencia) filter (where p.linha in ('despesas_comerciais', 'despesas_administrativas')), 0)
      as despesas_tendencia,
    max(p.gravado_em) as gravado_em
  from app.posicao_dre_mensal p
  group by p.tenant_id, p.centro_custo_id, p.competencia
), lucro as (
  select s.*,
    s.vgv_liquido_viabilidade - s.custo_vendas_viabilidade - s.despesas_viabilidade as lucro_operacional_viabilidade,
    s.vgv_liquido_tendencia - s.custo_vendas_tendencia - s.despesas_tendencia as lucro_operacional_tendencia
  from soma s
)
select l.tenant_id, l.centro_custo_id, cc.nome as obra, l.competencia,
  l.vgv_liquido_viabilidade, l.vgv_liquido_tendencia,
  l.custo_vendas_viabilidade, l.custo_vendas_tendencia,
  l.despesas_viabilidade, l.despesas_tendencia,
  l.lucro_operacional_viabilidade, l.lucro_operacional_tendencia,
  round(l.lucro_operacional_viabilidade / nullif(l.vgv_liquido_viabilidade, 0), 4) as margem_operacional_viabilidade,
  round(l.lucro_operacional_tendencia / nullif(l.vgv_liquido_tendencia, 0), 4) as margem_operacional_tendencia,
  l.gravado_em
from lucro l
join app.centro_custo cc on cc.id = l.centro_custo_id and cc.tenant_id = l.tenant_id;

grant select on marts.tendencia_resultado_mensal to authenticated;
