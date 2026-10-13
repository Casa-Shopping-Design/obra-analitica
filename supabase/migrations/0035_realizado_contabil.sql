-- Realizado das linhas fora do orçamento (plano APO, etapa 7; ver docs/decisoes/0017): terreno, projetos,
-- licenciamento, assistência técnica, juros, estoque e despesas passam a ter apropriado, vindo do saldo
-- contábil por centro de custo do ERP, com um mapa de conta para linha por construtora.

-- Uma linha por obra, conta e mês, como o ERP consolida o saldo. saldo_final com sinal: devedor positivo.
create table staging.saldo_contabil_mensal (
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  conta text not null,
  competencia date not null,
  debito numeric,
  credito numeric,
  saldo_final numeric not null,
  primary key (tenant_id, centro_custo_id, conta, competencia)
);
-- A DRE acha o último mês de cada obra e junta por ele; na chave primária a competência vem depois da conta.
create index saldo_contabil_mensal_competencia_idx
  on staging.saldo_contabil_mensal (tenant_id, centro_custo_id, competencia desc);

-- Mapa de conta contábil para linha da DRE. VGV, impostos e construção ficam de fora, porque já têm fonte
-- (mapa imobiliário e alíquota) e entrariam duas vezes. Nesta fase o dono do banco cadastra o mapa.
create table app.conta_linha_resultado (
  tenant_id uuid not null references app.tenant(id) on delete cascade,
  conta text not null,
  linha text not null check (linha in (
    'custo_terreno', 'custo_projetos', 'custo_licenciamento', 'assistencia_tecnica', 'juros_financiamento',
    'estoque', 'despesas_comerciais', 'despesas_administrativas')),
  primary key (tenant_id, conta)
);

-- Saldo contábil é dado de resultado: mesma leitura da DRE (0032) e do mapa imobiliário (0034), para diretor,
-- financeiro e leitura, e a restritiva segundo_fator da 0022, que só cobra aal2 de diretor e financeiro.
alter table staging.saldo_contabil_mensal enable row level security;
alter table staging.saldo_contabil_mensal force row level security;
create policy leitura_dre on staging.saldo_contabil_mensal for select to authenticated
  using (tenant_id = (select app.tenant_atual())
         and centro_custo_id in (select app.obras_permitidas())
         and (select app.perfil_atual()) in ('diretor', 'financeiro', 'leitura'));
create policy segundo_fator on staging.saldo_contabil_mensal as restrictive for all to authenticated
  using ((select app.segundo_fator_cumprido()));
revoke all on table staging.saldo_contabil_mensal from public, anon, authenticated;
grant select on table staging.saldo_contabil_mensal to authenticated;

-- O mapa não tem obra, então a leitura é por tenant e perfil.
alter table app.conta_linha_resultado enable row level security;
alter table app.conta_linha_resultado force row level security;
create policy leitura_dre on app.conta_linha_resultado for select to authenticated
  using (tenant_id = (select app.tenant_atual())
         and (select app.perfil_atual()) in ('diretor', 'financeiro', 'leitura'));
create policy segundo_fator on app.conta_linha_resultado as restrictive for all to authenticated
  using ((select app.segundo_fator_cumprido()));
revoke all on table app.conta_linha_resultado from public, anon, authenticated;
grant select on table app.conta_linha_resultado to authenticated;

-- Recarrega o saldo contábil do tenant a partir do raw. Vale a versão mais recente de cada chave; registro
-- com chave ou saldo que não se lê é descartado, como nas recargas da 0019. O nome dos campos do payload
-- fica só aqui: trocar de ERP mexe nesta função e no carregador, não na DRE.
-- O(n log n) nos registros do endpoint pelo distinct on; uma instrução, sem laço.
create or replace function staging.recarregar_saldo_contabil(p_tenant uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  -- Mesma trava das recargas do CRM e dos complementos: duas recargas do tenant ao mesmo tempo bateriam
  -- na chave primária.
  perform pg_advisory_xact_lock(hashtextextended('recarga:' || p_tenant::text, 0));
  delete from staging.saldo_contabil_mensal where tenant_id = p_tenant;

  insert into staging.saldo_contabil_mensal
    (tenant_id, centro_custo_id, conta, competencia, debito, credito, saldo_final)
  with versao as (
    select distinct on ((r.payload->>'costCenterId')::integer, btrim(r.payload->>'accountId'), r.payload->>'monthYear')
      (r.payload->>'costCenterId')::integer as obra,
      btrim(r.payload->>'accountId') as conta,
      to_date('01/' || (r.payload->>'monthYear'), 'DD/MM/YYYY') as competencia,
      r.payload
    from raw.registro r
    where r.tenant_id = p_tenant and r.endpoint = 'accountancy/accountCostCenterBalance'
      and r.payload->>'costCenterId' ~ '^\d{1,9}$'
      and length(btrim(r.payload->>'accountId')) between 1 and 40
      and r.payload->>'monthYear' ~ '^(0[1-9]|1[0-2])/\d{4}$'
    order by (r.payload->>'costCenterId')::integer, btrim(r.payload->>'accountId'), r.payload->>'monthYear', r.id desc
  ), lido as (
    select v.obra, v.conta, v.competencia,
      staging.numero_origem(v.payload->>'debitBalance') as debito,
      staging.numero_origem(v.payload->>'creditBalance') as credito,
      case upper(btrim(v.payload->>'balanceCarriedForwardType'))
        when 'D' then staging.numero_origem(v.payload->>'balanceCarriedForward')
        when 'C' then -staging.numero_origem(v.payload->>'balanceCarriedForward')
      end as saldo_final
    from versao v
  )
  select p_tenant, cc.id, l.conta, l.competencia, l.debito, l.credito, l.saldo_final
  from lido l
  join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = l.obra
  where l.saldo_final is not null;
end $$;

revoke execute on function staging.recarregar_saldo_contabil(uuid) from public, anon, authenticated;

-- Mesmas colunas e ordem da 0030. Muda só a fonte do apropriado das oito linhas fora do orçamento: soma do
-- saldo_final das contas mapeadas, no último mês carregado da obra. O a contratar dessas linhas vira o que
-- falta para o estudo, nunca negativo, e fonte_realizado marca 'contabil' quando há conta mapeada com saldo.
-- O resto da view (VGV, impostos, construção, totais, percentuais e desvio) segue como na 0030.
-- Sem perfil no corpo: o RLS do saldo e do mapa decide o que cada um vê, e a carga lê como dona com filtro próprio.
create or replace view marts.dre_viabilidade with (security_invoker = true) as
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
    coalesce(m.custo_acumulado, 0) as custo_acumulado
  from staging.mapa_imobiliario_mensal m
  join estudo e on e.tenant_id = m.tenant_id and e.centro_custo_id = m.centro_custo_id
  order by m.tenant_id, m.centro_custo_id, m.competencia desc
), ultimo_saldo as (
  select s.tenant_id, s.centro_custo_id, max(s.competencia) as competencia
  from staging.saldo_contabil_mensal s
  join estudo e on e.tenant_id = s.tenant_id and e.centro_custo_id = s.centro_custo_id
  group by s.tenant_id, s.centro_custo_id
), saldo as (
  select s.tenant_id, s.centro_custo_id, c.linha, sum(s.saldo_final) as apropriado
  from staging.saldo_contabil_mensal s
  join ultimo_saldo u
    on u.tenant_id = s.tenant_id and u.centro_custo_id = s.centro_custo_id and u.competencia = s.competencia
  join app.conta_linha_resultado c on c.tenant_id = s.tenant_id and c.conta = s.conta
  group by s.tenant_id, s.centro_custo_id, c.linha
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
    case when m.competencia is not null then m.custo_acumulado else p.pago end as construcao_apropriado
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
      else coalesce(s.apropriado, 0) end as apropriado,
    case el.linha
      when 'vgv_bruto' then f.vgv_a_apropriar
      when 'impostos' then case when f.aliquota is not null then round(f.aliquota * f.vgv_a_apropriar, 2) else 0 end
      when 'custo_construcao' then f.construcao_a_apropriar
      else 0 end as a_apropriar,
    case el.linha
      when 'vgv_bruto' then f.vgv_a_contratar
      when 'impostos' then case when f.aliquota is not null then round(f.aliquota * f.vgv_a_contratar, 2) else el.valor end
      when 'custo_construcao' then f.construcao_a_contratar
      else greatest(el.valor - coalesce(s.apropriado, 0), 0) end as a_contratar,
    case el.linha
      when 'vgv_bruto' then case when f.com_mapa then 'origem' else 'titulos' end
      when 'impostos' then case when f.aliquota is not null then 'aliquota' else 'sem_fonte' end
      when 'custo_construcao' then case when f.com_mapa then 'origem' else 'titulos' end
      else case when s.apropriado is not null then 'contabil' else 'sem_fonte' end end as fonte_realizado
  from fonte f
  join app.estudo_viabilidade_linha el on el.estudo_id = f.estudo_id
  left join saldo s on s.tenant_id = f.tenant_id and s.centro_custo_id = f.centro_custo_id and s.linha = el.linha
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
