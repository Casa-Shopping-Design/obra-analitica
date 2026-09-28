-- Rotas complementares do ERP de origem: mapa imobiliário consolidado (conferência do painel contra
-- o ERP), medição física da obra e inadimplência por faixa de atraso. O carregador grava em
-- raw.registro com a lista de campos permitidos; nome do cliente, observação e marca de SPC não entram.

-- Valor da inadimplência vem como texto na API; aceita ponto decimal, notação científica do JSON e o
-- formato brasileiro com vírgula. Texto torto vira nulo em vez de derrubar a recarga do tenant.
create or replace function staging.numero_origem(p_texto text) returns numeric
language plpgsql immutable set search_path = '' as $$
declare
  v_texto text := btrim(p_texto);
begin
  if v_texto is null or length(v_texto) > 40 then
    return null;
  end if;
  if v_texto ~ '^-?\d+(\.\d+)?([eE][-+]?\d{1,2})?$' then
    return v_texto::numeric;
  end if;
  if v_texto ~ '^-?(\d{1,3}(\.\d{3})+|\d+),\d+$' then
    return replace(replace(v_texto, '.', ''), ',', '.')::numeric;
  end if;
  return null;
exception when others then
  return null;
end $$;

create or replace function staging.data_origem(p_texto text) returns date
language plpgsql immutable set search_path = '' as $$
begin
  if p_texto is null or p_texto !~ '^\d{4}-\d{2}-\d{2}' then
    return null;
  end if;
  return left(p_texto, 10)::date;
exception when others then
  return null;
end $$;

revoke execute on function staging.numero_origem(text), staging.data_origem(text) from public, anon, authenticated;

-- Uma linha por obra e mês, como o ERP fecha o mapa. poc em percentual (0 a 100), margem em fração.
create table staging.mapa_imobiliario_mensal (
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  competencia date not null,
  unidades integer,
  vgv numeric,
  poc numeric,
  recebido_mes numeric,
  recebido_acumulado numeric,
  custo_orcado numeric,
  custo_incorrido_mes numeric,
  custo_incorrido_acumulado numeric,
  custo_a_incorrer numeric,
  receita_acumulada numeric,
  custo_acumulado numeric,
  lucro_bruto numeric,
  margem numeric,
  primary key (tenant_id, centro_custo_id, competencia)
);

-- Uma linha por tarefa medida. A quantidade acumulada já soma as medições anteriores da tarefa.
create table staging.medicao_obra (
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  numero_medicao integer not null,
  unidade_construtiva_id integer not null,
  tarefa_id integer not null,
  data_medicao date not null,
  situacao_aprovacao text,
  consistente boolean,
  agrupador boolean not null default false,
  descricao text,
  quantidade_planejada numeric,
  quantidade_medida numeric,
  quantidade_acumulada numeric,
  preco_unitario numeric,
  pct_acumulado numeric,
  primary key (tenant_id, centro_custo_id, numero_medicao, unidade_construtiva_id, tarefa_id)
);
create index medicao_obra_tarefa_idx
  on staging.medicao_obra (tenant_id, centro_custo_id, unidade_construtiva_id, tarefa_id, data_medicao);

-- Um título por linha, sem cliente: a API agrupa por cliente e unidade, mas só o título e os valores entram.
create table staging.inadimplencia (
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  titulo_id_origem bigint not null,
  data_posicao date not null,
  dias_atraso integer not null,
  parcelas_atrasadas integer not null,
  vencimento_mais_antigo date,
  valor_atrasado numeric not null,
  valor_atualizado numeric,
  primary key (tenant_id, titulo_id_origem)
);
create index inadimplencia_obra_idx on staging.inadimplencia (tenant_id, centro_custo_id);

do $$
declare t text;
begin
  foreach t in array array['medicao_obra', 'inadimplencia'] loop
    execute format('alter table staging.%I enable row level security', t);
    execute format('alter table staging.%I force row level security', t);
    execute format($p$create policy leitura_por_obra on staging.%I for select to authenticated
      using (tenant_id = app.tenant_atual() and centro_custo_id in (select app.obras_permitidas()))$p$, t);
    execute format('grant select on staging.%I to authenticated', t);
  end loop;
end $$;

-- O mapa traz margem e lucro da obra e alimenta a conferência, que é só de diretor e financeiro.
-- A regra fica no dado, não só na tela: a API REST e o assistente leem com o JWT do usuário.
alter table staging.mapa_imobiliario_mensal enable row level security;
alter table staging.mapa_imobiliario_mensal force row level security;
create policy leitura_diretoria on staging.mapa_imobiliario_mensal for select to authenticated
  using (tenant_id = app.tenant_atual() and centro_custo_id in (select app.obras_permitidas())
         and app.perfil_atual() in ('diretor', 'financeiro'));
grant select on staging.mapa_imobiliario_mensal to authenticated;

-- Recarrega o staging complementar a partir do raw. Roda depois de staging.recarregar, porque a
-- inadimplência sem centro de custo acha a obra pelo título já carregado em staging.parcela_receber.
-- O(n log n) nos registros de cada endpoint pelo distinct on; uma instrução por tabela, sem laço.
create or replace function staging.recarregar_complementos(p_tenant uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  -- Mesma trava da recarga do CRM: duas recargas do tenant ao mesmo tempo bateriam na chave primária.
  perform pg_advisory_xact_lock(hashtextextended('recarga:' || p_tenant::text, 0));
  delete from staging.mapa_imobiliario_mensal where tenant_id = p_tenant;
  delete from staging.medicao_obra where tenant_id = p_tenant;
  delete from staging.inadimplencia where tenant_id = p_tenant;

  insert into staging.mapa_imobiliario_mensal
    (tenant_id, centro_custo_id, competencia, unidades, vgv, poc, recebido_mes, recebido_acumulado,
     custo_orcado, custo_incorrido_mes, custo_incorrido_acumulado, custo_a_incorrer, receita_acumulada,
     custo_acumulado, lucro_bruto, margem)
  with versao as (
    select distinct on ((r.payload->'enterpriseData'->>'enterpriseId')::integer, r.payload->'enterpriseData'->>'monthYear')
      (r.payload->'enterpriseData'->>'enterpriseId')::integer as obra,
      to_date('01/' || (r.payload->'enterpriseData'->>'monthYear'), 'DD/MM/YYYY') as competencia,
      r.payload
    from raw.registro r
    where r.tenant_id = p_tenant and r.endpoint = 'real-estate-map'
      and r.payload->'enterpriseData'->>'enterpriseId' ~ '^\d{1,9}$'
      and r.payload->'enterpriseData'->>'monthYear' ~ '^(0[1-9]|1[0-2])/\d{4}$'
    order by (r.payload->'enterpriseData'->>'enterpriseId')::integer, r.payload->'enterpriseData'->>'monthYear', r.id desc
  )
  select p_tenant, cc.id, v.competencia,
    case when v.payload->'enterpriseData'->>'units' ~ '^\d{1,9}$' then (v.payload->'enterpriseData'->>'units')::integer end,
    staging.numero_origem(v.payload->'vgvData'->>'vgv'),
    staging.numero_origem(v.payload->'vgvData'->>'poc'),
    staging.numero_origem(v.payload->'accumulatedReceipts'->>'monthlyReceipt'),
    staging.numero_origem(v.payload->'accumulatedReceipts'->>'accumulatedReceipt'),
    staging.numero_origem(v.payload->'budgetedAndIncurredCost'->>'budgetedCost'),
    staging.numero_origem(v.payload->'budgetedAndIncurredCost'->>'monthlyIncurredCost'),
    staging.numero_origem(v.payload->'budgetedAndIncurredCost'->>'accumulatedIncurredCost'),
    staging.numero_origem(v.payload->'budgetedAndIncurredCost'->>'costToIncur'),
    staging.numero_origem(v.payload->'margin'->>'accumulatedRevenue'),
    staging.numero_origem(v.payload->'margin'->>'accruedCost'),
    staging.numero_origem(v.payload->'margin'->>'grossProfit'),
    staging.numero_origem(v.payload->'margin'->>'(%)')
  from versao v
  join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = v.obra;

  -- A API não devolve obra, medição e unidade construtiva nos itens; o carregador acrescenta.
  insert into staging.medicao_obra
    (tenant_id, centro_custo_id, numero_medicao, unidade_construtiva_id, tarefa_id, data_medicao,
     situacao_aprovacao, consistente, agrupador, descricao, quantidade_planejada, quantidade_medida,
     quantidade_acumulada, preco_unitario, pct_acumulado)
  with versao as (
    select distinct on (
        (r.payload->>'buildingId')::integer, (r.payload->>'measurementNumber')::integer,
        staging.numero_origem(r.payload->>'buildingUnitId')::integer, (r.payload->>'taskId')::integer)
      (r.payload->>'buildingId')::integer as obra,
      (r.payload->>'measurementNumber')::integer as numero_medicao,
      staging.numero_origem(r.payload->>'buildingUnitId')::integer as unidade_construtiva_id,
      (r.payload->>'taskId')::integer as tarefa_id,
      r.payload
    from raw.registro r
    where r.tenant_id = p_tenant and r.endpoint = 'building-projects/progress-logs/items'
      and r.payload->>'buildingId' ~ '^\d{1,9}$' and r.payload->>'measurementNumber' ~ '^\d{1,9}$'
      and r.payload->>'buildingUnitId' ~ '^\d{1,9}(\.0+)?$' and r.payload->>'taskId' ~ '^\d{1,9}$'
      and staging.data_origem(r.payload->>'date') is not null
    order by (r.payload->>'buildingId')::integer, (r.payload->>'measurementNumber')::integer,
      staging.numero_origem(r.payload->>'buildingUnitId')::integer, (r.payload->>'taskId')::integer, r.id desc
  )
  select p_tenant, cc.id, v.numero_medicao, v.unidade_construtiva_id, v.tarefa_id,
    staging.data_origem(v.payload->>'date'),
    v.payload->>'statusApproval',
    case lower(v.payload->>'consistent') when 'true' then true when 'false' then false end,
    coalesce(lower(v.payload->>'summary') = 'true', false),
    v.payload->>'description',
    staging.numero_origem(v.payload->>'plannedQuantity'),
    staging.numero_origem(v.payload->>'measuredQuantity'),
    staging.numero_origem(v.payload->>'cumulativeMeasuredQuantity'),
    staging.numero_origem(v.payload->>'unitPrice'),
    staging.numero_origem(v.payload->>'cumulativePercentage')
  from versao v
  join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = v.obra;

  -- Vale só a posição mais recente. O carregador grava um registro só com positionDate a cada leitura
  -- bem-sucedida, então um dia sem inadimplente nenhum zera a posição em vez de repetir a anterior.
  insert into staging.inadimplencia
    (tenant_id, centro_custo_id, titulo_id_origem, data_posicao, dias_atraso, parcelas_atrasadas,
     vencimento_mais_antigo, valor_atrasado, valor_atualizado)
  with posicao as (
    select max(staging.data_origem(r.payload->>'positionDate')) as data_posicao
    from raw.registro r
    where r.tenant_id = p_tenant and r.endpoint = 'defaulters-receivable-bills/by-aging'
  ), versao as (
    select distinct on ((r.payload->>'receivableBillId')::bigint)
      (r.payload->>'receivableBillId')::bigint as titulo, p.data_posicao, r.payload
    from raw.registro r
    cross join posicao p
    where r.tenant_id = p_tenant and r.endpoint = 'defaulters-receivable-bills/by-aging'
      and r.payload->>'receivableBillId' ~ '^\d{1,18}$'
      and staging.data_origem(r.payload->>'positionDate') = p.data_posicao
    order by (r.payload->>'receivableBillId')::bigint, r.id desc
  )
  select p_tenant, coalesce(cc.id, pr.centro_custo_id), v.titulo, v.data_posicao,
    pa.dias_atraso, pa.parcelas, pa.vencimento_mais_antigo, pa.valor_atrasado, pa.valor_atualizado
  from versao v
  cross join lateral (
    select max(case when p->>'daysOfDelay' ~ '^\d{1,9}$' then (p->>'daysOfDelay')::integer end) as dias_atraso,
      count(*)::integer as parcelas,
      min(staging.data_origem(p->>'dueDate')) as vencimento_mais_antigo,
      coalesce(sum(staging.numero_origem(p->>'correctedValueWithoutAdditions')), 0) as valor_atrasado,
      sum(staging.numero_origem(p->>'correctedValueWithAdditions')) as valor_atualizado
    from jsonb_array_elements(
      case when jsonb_typeof(v.payload->'defaulterInstallments') = 'array'
           then v.payload->'defaulterInstallments' else '[]'::jsonb end) as p
  ) pa
  -- Título de mais de um centro de custo fica na obra de menor código, para não contar duas vezes.
  left join lateral (
    select c.id
    from jsonb_array_elements_text(
      case when jsonb_typeof(v.payload->'costCentersId') = 'array' then v.payload->'costCentersId' else '[]'::jsonb end) as e
    join app.centro_custo c
      on c.tenant_id = p_tenant and c.id_origem = case when e ~ '^\d{1,9}$' then e::integer end
    order by c.id_origem
    limit 1
  ) cc on true
  left join lateral (
    select p.centro_custo_id
    from staging.parcela_receber p
    where cc.id is null and p.tenant_id = p_tenant and p.contrato_id_origem = v.titulo
    limit 1
  ) pr on true
  where pa.dias_atraso > 0 and coalesce(cc.id, pr.centro_custo_id) is not null;
end $$;

revoke execute on function staging.recarregar_complementos(uuid) from public, anon, authenticated;

-- Conferência do painel contra o mapa imobiliário do ERP, no último mês que o ERP fechou para a obra.
-- VGV do painel é o de hoje (vendido mais estoque). Recebido e custo incorrido do painel são somados
-- até o fim daquele mês: recebido pela data do recebimento; custo incorrido como o pago até o mês mais
-- os títulos em aberto que vencem até o mês. O ERP apropria custo pela competência do título, então
-- título lançado com vencimento futuro aparece como diferença, e é isso que o controller precisa ver.
-- Só diretor e financeiro recebem linha: a view roda com o RLS de quem consulta e o mapa só abre para eles.
-- O(m) por obra em meses do fluxo; uma agregação por fonte.
create or replace view marts.conferencia_origem with (security_invoker = true) as
with ultimo as (
  select distinct on (tenant_id, centro_custo_id) *
  from staging.mapa_imobiliario_mensal
  order by tenant_id, centro_custo_id, competencia desc
), fluxo as (
  select f.tenant_id, f.centro_custo_id,
    sum(f.entrada_direta_realizada + f.repasse_realizado) as recebido,
    sum(f.saida_realizada + f.saida_prevista + f.saida_vencida) as custo_incorrido
  from marts.fluxo_caixa_mensal f
  join ultimo u on u.tenant_id = f.tenant_id and u.centro_custo_id = f.centro_custo_id
  where f.competencia <= u.competencia
  group by 1, 2
), lado_a_lado as (
  select u.tenant_id, u.centro_custo_id, pf.obra, u.competencia as competencia_origem,
    coalesce(pf.vgv_total, 0) as vgv_painel, u.vgv as vgv_origem,
    coalesce(pf.custo_orcado, 0) as custo_orcado_painel, u.custo_orcado as custo_orcado_origem,
    round(coalesce(f.custo_incorrido, 0), 2) as custo_incorrido_painel, u.custo_incorrido_acumulado as custo_incorrido_origem,
    round(coalesce(f.recebido, 0), 2) as recebido_painel, u.recebido_acumulado as recebido_origem
  from ultimo u
  join marts.posicao_financeira_obra pf on pf.tenant_id = u.tenant_id and pf.centro_custo_id = u.centro_custo_id
  left join fluxo f on f.tenant_id = u.tenant_id and f.centro_custo_id = u.centro_custo_id
)
select tenant_id, centro_custo_id, obra, competencia_origem,
  vgv_painel, vgv_origem, vgv_painel - vgv_origem as diferenca_vgv,
  case when vgv_origem <> 0 then round((vgv_painel - vgv_origem) / vgv_origem, 4) end as diferenca_vgv_pct,
  custo_orcado_painel, custo_orcado_origem, custo_orcado_painel - custo_orcado_origem as diferenca_custo_orcado,
  custo_incorrido_painel, custo_incorrido_origem,
  custo_incorrido_painel - custo_incorrido_origem as diferenca_custo_incorrido,
  case when custo_incorrido_origem <> 0
       then round((custo_incorrido_painel - custo_incorrido_origem) / custo_incorrido_origem, 4) end as diferenca_custo_incorrido_pct,
  recebido_painel, recebido_origem, recebido_painel - recebido_origem as diferenca_recebido,
  case when recebido_origem <> 0 then round((recebido_painel - recebido_origem) / recebido_origem, 4) end as diferenca_recebido_pct
from lado_a_lado;

grant select on marts.conferencia_origem to authenticated;

-- Execução física contra financeira por obra e mês. Físico é o valor medido sobre o valor planejado
-- das tarefas, cada tarefa pela última medição aprovada até o mês; tarefa que não entrou numa medição
-- segue com o acumulado da anterior. Agrupador fica fora, senão conta o valor da tarefa duas vezes.
-- Financeiro é o pago acumulado até o mês sobre o custo orçado; o do ERP vem do mapa imobiliário.
-- pct_financeiro_origem sai nulo para quem não é diretor nem financeiro, porque o mapa não abre para ele.
-- O(m x t) por obra, com m meses e t tarefas: cada versão de tarefa cobre um intervalo de meses.
create or replace view marts.execucao_fisica_obra with (security_invoker = true) as
with medida as (
  select distinct on (tenant_id, centro_custo_id, unidade_construtiva_id, tarefa_id, date_trunc('month', data_medicao))
    tenant_id, centro_custo_id, unidade_construtiva_id, tarefa_id,
    date_trunc('month', data_medicao)::date as competencia,
    quantidade_planejada, least(greatest(coalesce(quantidade_acumulada, 0), 0), quantidade_planejada) as quantidade_acumulada,
    coalesce(preco_unitario, 0) as preco_unitario
  from staging.medicao_obra
  where situacao_aprovacao = 'APROVADA' and consistente is not false and not agrupador
    and quantidade_planejada > 0
  order by tenant_id, centro_custo_id, unidade_construtiva_id, tarefa_id, date_trunc('month', data_medicao),
    data_medicao desc, numero_medicao desc
), vigencia as (
  select m.*,
    lead(m.competencia) over (
      partition by m.tenant_id, m.centro_custo_id, m.unidade_construtiva_id, m.tarefa_id order by m.competencia
    ) as proxima
  from medida m
), calendario as (
  select o.tenant_id, o.centro_custo_id, competencia::date as competencia
  from (
    select tenant_id, centro_custo_id, min(competencia) as primeiro_mes from medida group by 1, 2
  ) o,
  lateral generate_series(o.primeiro_mes, date_trunc('month', current_date), interval '1 month') as competencia
), fisico as (
  select c.tenant_id, c.centro_custo_id, c.competencia,
    sum(v.quantidade_acumulada * v.preco_unitario) as valor_medido,
    sum(v.quantidade_planejada * v.preco_unitario) as valor_planejado
  from calendario c
  join vigencia v
    on v.tenant_id = c.tenant_id and v.centro_custo_id = c.centro_custo_id
   and v.competencia <= c.competencia and (v.proxima is null or v.proxima > c.competencia)
  group by 1, 2, 3
), orcamento as (
  select tenant_id, centro_custo_id, sum(valor_total) as custo_orcado
  from staging.item_orcamento
  group by 1, 2
), pago as (
  select tenant_id, centro_custo_id, competencia, saida_realizada
  from marts.fluxo_caixa_mensal
  where saida_realizada <> 0
)
select f.tenant_id, f.centro_custo_id, f.competencia,
  round(f.valor_medido, 2) as valor_medido,
  round(f.valor_planejado, 2) as valor_planejado,
  case when f.valor_planejado > 0 then round(f.valor_medido / f.valor_planejado, 4) end as pct_fisico,
  coalesce(o.custo_orcado, 0) as custo_orcado,
  coalesce(pa.pago_acumulado, 0) as pago_acumulado,
  case when o.custo_orcado > 0 then round(coalesce(pa.pago_acumulado, 0) / o.custo_orcado, 4) end as pct_financeiro,
  case when m.custo_orcado > 0 then round(m.custo_incorrido_acumulado / m.custo_orcado, 4) end as pct_financeiro_origem,
  case when f.valor_planejado > 0 and o.custo_orcado > 0
       then round(coalesce(pa.pago_acumulado, 0) / o.custo_orcado - f.valor_medido / f.valor_planejado, 4) end as diferenca_financeiro_fisico
from fisico f
left join orcamento o on o.tenant_id = f.tenant_id and o.centro_custo_id = f.centro_custo_id
left join lateral (
  select sum(p.saida_realizada) as pago_acumulado
  from pago p
  where p.tenant_id = f.tenant_id and p.centro_custo_id = f.centro_custo_id and p.competencia <= f.competencia
) pa on true
left join staging.mapa_imobiliario_mensal m
  on m.tenant_id = f.tenant_id and m.centro_custo_id = f.centro_custo_id and m.competencia = f.competencia;

grant select on marts.execucao_fisica_obra to authenticated;

-- Inadimplência por obra e faixa de atraso na última posição carregada, sem cliente identificado.
-- As quatro faixas aparecem sempre, com zero quando não há título, para a tela não esconder faixa vazia.
create or replace view marts.inadimplencia_faixa with (security_invoker = true) as
with faixa as (
  select * from (values
    (1, '1-30', 1, 30), (2, '31-90', 31, 90), (3, '91-180', 91, 180), (4, '>180', 181, null)
  ) as f(ordem, faixa, dias_min, dias_max)
), obra as (
  select tenant_id, centro_custo_id, max(data_posicao) as data_posicao
  from staging.inadimplencia
  group by 1, 2
)
select o.tenant_id, o.centro_custo_id, cc.nome as obra, o.data_posicao, f.ordem, f.faixa,
  count(i.titulo_id_origem)::integer as titulos,
  coalesce(sum(i.parcelas_atrasadas), 0)::integer as parcelas,
  coalesce(sum(i.valor_atrasado), 0) as valor_atrasado,
  coalesce(sum(i.valor_atualizado), 0) as valor_atualizado
from obra o
join app.centro_custo cc on cc.tenant_id = o.tenant_id and cc.id = o.centro_custo_id
cross join faixa f
left join staging.inadimplencia i
  on i.tenant_id = o.tenant_id and i.centro_custo_id = o.centro_custo_id
 and i.dias_atraso >= f.dias_min and (f.dias_max is null or i.dias_atraso <= f.dias_max)
group by o.tenant_id, o.centro_custo_id, cc.nome, o.data_posicao, f.ordem, f.faixa;

grant select on marts.inadimplencia_faixa to authenticated;
