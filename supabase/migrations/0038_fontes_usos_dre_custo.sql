-- Fontes e Usos, DRE societária e custo incorrido por empresa, nos dois modos: acumulado (posição no fim do
-- mês, como a planilha) e período (movimento entre dois meses). Tudo em SQL, security invoker, com o RLS
-- das tabelas valendo (ver docs/decisoes/0019).
--
-- Sinais, por demonstrativo, sobre o saldo com devedor positivo:
--   F&U: crédito menos débito em tudo, exceto o bloco de caixa, que é débito menos crédito; passagem com zeramento.
--   DRE: crédito menos débito, passagem sem zeramento.
--   Custo: débito menos crédito, passagem sem zeramento; o estoque usa a passagem com zeramento.
-- Premissa da carga: onlyAccountsWithMovements=false, então toda conta analítica tem linha em todo mês e o
-- acumulado de um mês é a soma dos saldos finais daquele mês.

-- Valor de cada linha do tipo conta por empresa e mês, nos dois modos, já com o sinal do demonstrativo.
-- O(linhas de saldo) com hash join no mapa efetivo e no catálogo; a agregação cai na chave primária.
create view marts.saldo_linha_mensal with (security_invoker = true) as
select s.tenant_id, s.empresa_id, s.competencia, l.demonstrativo, l.linha,
  sum(case l.demonstrativo
        when 'fontes_usos' then case when l.pai = 'caixa_equivalentes' then 1 else -1 end * (s.debito - s.credito)
        when 'dre' then s.credito_sem_zeramento - s.debito_sem_zeramento
        when 'custo_incorrido' then case when l.linha = 'estoque_imoveis_construcao'
                                         then s.debito - s.credito
                                         else s.debito_sem_zeramento - s.credito_sem_zeramento end
      end) as valor_mes,
  sum(case l.demonstrativo
        when 'fontes_usos' then case when l.pai = 'caixa_equivalentes' then 1 else -1 end * s.saldo_final
        when 'dre' then -s.saldo_final_sem_zeramento
        when 'custo_incorrido' then case when l.linha = 'estoque_imoveis_construcao'
                                         then s.saldo_final
                                         else s.saldo_final_sem_zeramento end
      end) as valor_acumulado
from staging.saldo_contabil_empresa_mensal s
join marts.mapa_conta_efetivo m
  on m.tenant_id = s.tenant_id and m.empresa_id = s.empresa_id and m.conta = s.conta
join marts.linha_relatorio l
  on l.linha = m.linha and l.tipo = 'conta' and l.demonstrativo in ('fontes_usos', 'dre', 'custo_incorrido')
group by s.tenant_id, s.empresa_id, s.competencia, l.demonstrativo, l.linha;

grant select on marts.saldo_linha_mensal to authenticated;

-- Uma linha por empresa, mês e linha do demonstrativo, com todas as linhas presentes (zero quando nada
-- mapeado), para a tabela mês a mês e o assistente. Total e grupo já somam as contas: não somar com elas.
-- O(meses x linhas do catálogo) sobre saldo_linha_mensal.
create view marts.fontes_usos_mensal with (security_invoker = true) as
with mes as (
  select distinct tenant_id, empresa_id, competencia
  from staging.saldo_contabil_empresa_mensal
)
select m.tenant_id, m.empresa_id, e.nome as empresa, m.competencia,
  l.linha, l.rotulo, l.ordem, l.tipo, l.nivel,
  round(coalesce(sum(v.valor_mes), 0), 2) as valor_mes,
  round(coalesce(sum(v.valor_acumulado), 0), 2) as valor_acumulado
from mes m
join app.empresa e on e.id = m.empresa_id and e.tenant_id = m.tenant_id
cross join marts.linha_relatorio l
left join marts.composicao_relatorio c on c.demonstrativo = l.demonstrativo and c.total = l.linha
left join marts.saldo_linha_mensal v
  on v.tenant_id = m.tenant_id and v.empresa_id = m.empresa_id and v.competencia = m.competencia
 and v.demonstrativo = l.demonstrativo and v.linha = c.componente
where l.demonstrativo = 'fontes_usos'
group by m.tenant_id, m.empresa_id, e.nome, m.competencia, l.linha, l.rotulo, l.ordem, l.tipo, l.nivel;

create view marts.dre_societaria_mensal with (security_invoker = true) as
with mes as (
  select distinct tenant_id, empresa_id, competencia
  from staging.saldo_contabil_empresa_mensal
)
select m.tenant_id, m.empresa_id, e.nome as empresa, m.competencia,
  l.linha, l.rotulo, l.ordem, l.tipo, l.nivel,
  round(coalesce(sum(v.valor_mes), 0), 2) as valor_mes,
  round(coalesce(sum(v.valor_acumulado), 0), 2) as valor_acumulado
from mes m
join app.empresa e on e.id = m.empresa_id and e.tenant_id = m.tenant_id
cross join marts.linha_relatorio l
left join marts.composicao_relatorio c on c.demonstrativo = l.demonstrativo and c.total = l.linha
left join marts.saldo_linha_mensal v
  on v.tenant_id = m.tenant_id and v.empresa_id = m.empresa_id and v.competencia = m.competencia
 and v.demonstrativo = l.demonstrativo and v.linha = c.componente
where l.demonstrativo = 'dre'
group by m.tenant_id, m.empresa_id, e.nome, m.competencia, l.linha, l.rotulo, l.ordem, l.tipo, l.nivel;

-- As linhas de indicador ficam de fora: são razões, não valores que se somam mês a mês.
create view marts.custo_incorrido_mensal with (security_invoker = true) as
with mes as (
  select distinct tenant_id, empresa_id, competencia
  from staging.saldo_contabil_empresa_mensal
)
select m.tenant_id, m.empresa_id, e.nome as empresa, m.competencia,
  l.linha, l.rotulo, l.ordem, l.tipo, l.nivel,
  round(coalesce(sum(v.valor_mes), 0), 2) as valor_mes,
  round(coalesce(sum(v.valor_acumulado), 0), 2) as valor_acumulado
from mes m
join app.empresa e on e.id = m.empresa_id and e.tenant_id = m.tenant_id
cross join marts.linha_relatorio l
left join marts.composicao_relatorio c on c.demonstrativo = l.demonstrativo and c.total = l.linha
left join marts.saldo_linha_mensal v
  on v.tenant_id = m.tenant_id and v.empresa_id = m.empresa_id and v.competencia = m.competencia
 and v.demonstrativo = l.demonstrativo and v.linha = c.componente
where l.demonstrativo = 'custo_incorrido' and l.tipo <> 'indicador'
group by m.tenant_id, m.empresa_id, e.nome, m.competencia, l.linha, l.rotulo, l.ordem, l.tipo, l.nivel;

grant select on marts.fontes_usos_mensal, marts.dre_societaria_mensal, marts.custo_incorrido_mensal to authenticated;

-- As três funções devolvem o demonstrativo inteiro, na ordem do catálogo, para uma empresa e um intervalo.
-- Acumulado ignora p_inicio e usa o último mês carregado até p_fim; período soma os meses entre os dois.
-- Empresa que o usuário não enxerga devolve zero linhas. O(meses no intervalo x linhas) por chamada.
create function marts.fontes_usos(p_empresa uuid, p_inicio date, p_fim date, p_acumulado boolean)
returns table (ordem integer, linha text, rotulo text, tipo text, nivel integer, valor numeric)
language sql stable security invoker set search_path = '' as $$
  with fim as (
    select max(s.competencia) as competencia
    from staging.saldo_contabil_empresa_mensal s
    where s.empresa_id = p_empresa and s.competencia <= date_trunc('month', p_fim)::date
  ), valor as (
    select v.linha, sum(case when p_acumulado then v.valor_acumulado else v.valor_mes end) as valor
    from marts.saldo_linha_mensal v, fim
    where v.empresa_id = p_empresa and v.demonstrativo = 'fontes_usos'
      and case when p_acumulado then v.competencia = fim.competencia
               else v.competencia between date_trunc('month', p_inicio)::date and date_trunc('month', p_fim)::date end
    group by v.linha
  )
  select l.ordem, l.linha, l.rotulo, l.tipo, l.nivel, round(coalesce(sum(va.valor), 0), 2) as valor
  from marts.linha_relatorio l
  left join marts.composicao_relatorio c on c.demonstrativo = l.demonstrativo and c.total = l.linha
  left join valor va on va.linha = c.componente
  where l.demonstrativo = 'fontes_usos'
    and exists (select 1 from app.empresa e where e.id = p_empresa)
  group by l.ordem, l.linha, l.rotulo, l.tipo, l.nivel
  order by l.ordem
$$;

create function marts.dre_societaria(p_empresa uuid, p_inicio date, p_fim date, p_acumulado boolean)
returns table (ordem integer, linha text, rotulo text, tipo text, nivel integer, valor numeric, pct_receita_liquida numeric)
language sql stable security invoker set search_path = '' as $$
  with fim as (
    select max(s.competencia) as competencia
    from staging.saldo_contabil_empresa_mensal s
    where s.empresa_id = p_empresa and s.competencia <= date_trunc('month', p_fim)::date
  ), valor as (
    select v.linha, sum(case when p_acumulado then v.valor_acumulado else v.valor_mes end) as valor
    from marts.saldo_linha_mensal v, fim
    where v.empresa_id = p_empresa and v.demonstrativo = 'dre'
      and case when p_acumulado then v.competencia = fim.competencia
               else v.competencia between date_trunc('month', p_inicio)::date and date_trunc('month', p_fim)::date end
    group by v.linha
  ), demonstrativo as (
    select l.ordem, l.linha, l.rotulo, l.tipo, l.nivel, round(coalesce(sum(va.valor), 0), 2) as valor
    from marts.linha_relatorio l
    left join marts.composicao_relatorio c on c.demonstrativo = l.demonstrativo and c.total = l.linha
    left join valor va on va.linha = c.componente
    where l.demonstrativo = 'dre'
      and exists (select 1 from app.empresa e where e.id = p_empresa)
    group by l.ordem, l.linha, l.rotulo, l.tipo, l.nivel
  )
  select d.ordem, d.linha, d.rotulo, d.tipo, d.nivel, d.valor,
    round(d.valor / nullif(max(d.valor) filter (where d.linha = 'receita_liquida') over (), 0), 4) as pct_receita_liquida
  from demonstrativo d
  order by d.ordem
$$;

-- Além das linhas da planilha, duas de tipo indicador: pct_levado_ao_resultado é CMV sobre custo incorrido
-- (não é POC) e taxa_encargos é encargos sociais mais complementares sobre salários. Nas duas, valor é a razão
-- e pct_custo_incorrido fica nulo.
create function marts.custo_incorrido(p_empresa uuid, p_inicio date, p_fim date, p_acumulado boolean)
returns table (ordem integer, linha text, rotulo text, tipo text, nivel integer, valor numeric, pct_custo_incorrido numeric)
language sql stable security invoker set search_path = '' as $$
  with fim as (
    select max(s.competencia) as competencia
    from staging.saldo_contabil_empresa_mensal s
    where s.empresa_id = p_empresa and s.competencia <= date_trunc('month', p_fim)::date
  ), valor as (
    select v.linha, sum(case when p_acumulado then v.valor_acumulado else v.valor_mes end) as valor
    from marts.saldo_linha_mensal v, fim
    where v.empresa_id = p_empresa and v.demonstrativo = 'custo_incorrido'
      and case when p_acumulado then v.competencia = fim.competencia
               else v.competencia between date_trunc('month', p_inicio)::date and date_trunc('month', p_fim)::date end
    group by v.linha
  ), demonstrativo as (
    select l.ordem, l.linha, l.rotulo, l.tipo, l.nivel, round(coalesce(sum(va.valor), 0), 2) as valor
    from marts.linha_relatorio l
    left join marts.composicao_relatorio c on c.demonstrativo = l.demonstrativo and c.total = l.linha
    left join valor va on va.linha = c.componente
    where l.demonstrativo = 'custo_incorrido' and l.tipo <> 'indicador'
      and exists (select 1 from app.empresa e where e.id = p_empresa)
    group by l.ordem, l.linha, l.rotulo, l.tipo, l.nivel
  ), base as (
    select
      max(valor) filter (where linha = 'custo_incorrido') as custo_incorrido,
      max(valor) filter (where linha = 'custo_unidades_vendidas') as custo_unidades_vendidas,
      max(valor) filter (where linha = 'salarios_proventos') as salarios_proventos,
      max(valor) filter (where linha = 'encargos_sociais') as encargos_sociais,
      max(valor) filter (where linha = 'encargos_complementares') as encargos_complementares
    from demonstrativo
  ), linhas as (
    select d.ordem, d.linha, d.rotulo, d.tipo, d.nivel, d.valor,
      round(d.valor / nullif(b.custo_incorrido, 0), 4) as pct_custo_incorrido
    from demonstrativo d cross join base b
    union all
    select l.ordem, l.linha, l.rotulo, l.tipo, l.nivel,
      case l.linha
        when 'pct_levado_ao_resultado' then round(b.custo_unidades_vendidas / nullif(b.custo_incorrido, 0), 4)
        when 'taxa_encargos' then round((b.encargos_sociais + b.encargos_complementares) / nullif(b.salarios_proventos, 0), 4)
      end,
      null::numeric
    from marts.linha_relatorio l cross join base b
    where l.demonstrativo = 'custo_incorrido' and l.tipo = 'indicador'
      and exists (select 1 from demonstrativo)
  )
  select ordem, linha, rotulo, tipo, nivel, valor, pct_custo_incorrido
  from linhas
  order by ordem
$$;

revoke execute on function
  marts.fontes_usos(uuid, date, date, boolean),
  marts.dre_societaria(uuid, date, date, boolean),
  marts.custo_incorrido(uuid, date, date, boolean)
  from public, anon;
grant execute on function
  marts.fontes_usos(uuid, date, date, boolean),
  marts.dre_societaria(uuid, date, date, boolean),
  marts.custo_incorrido(uuid, date, date, boolean)
  to authenticated;

-- Conferência por empresa e mês, no acumulado: saldo líquido do F&U contra o caixa (a diferença só pode vir
-- de conta patrimonial sem mapa), lucros acumulados contra o lucro da DRE (a diferença é ajuste de exercícios
-- anteriores ou dividendo pago, mostrada e não corrigida) e as contas sem mapa com saldo ou movimento no mês.
-- Só diretor e financeiro; sem usuário (dona do banco, carga) lê tudo. O(meses x contas) por empresa.
create view marts.controle_fontes_usos with (security_invoker = true) as
with mes as (
  select distinct tenant_id, empresa_id, competencia
  from staging.saldo_contabil_empresa_mensal
), fontes_usos as (
  select v.tenant_id, v.empresa_id, v.competencia,
    coalesce(sum(v.valor_acumulado) filter (where c.total = 'saldo_liquido'), 0) as saldo_liquido,
    coalesce(sum(v.valor_acumulado) filter (where c.total = 'caixa_equivalentes'), 0) as caixa_equivalentes,
    coalesce(sum(v.valor_acumulado) filter (where c.total = 'grupo_lucros_acumulados'), 0) as lucros_acumulados
  from marts.saldo_linha_mensal v
  join marts.composicao_relatorio c
    on c.demonstrativo = 'fontes_usos' and c.componente = v.linha
   and c.total in ('saldo_liquido', 'caixa_equivalentes', 'grupo_lucros_acumulados')
  where v.demonstrativo = 'fontes_usos'
  group by v.tenant_id, v.empresa_id, v.competencia
), dre as (
  select v.tenant_id, v.empresa_id, v.competencia, sum(v.valor_acumulado) as lucro_liquido
  from marts.saldo_linha_mensal v
  join marts.composicao_relatorio c
    on c.demonstrativo = 'dre' and c.componente = v.linha and c.total = 'lucro_liquido'
  where v.demonstrativo = 'dre'
  group by v.tenant_id, v.empresa_id, v.competencia
), sem_mapa as (
  select s.tenant_id, s.empresa_id, s.competencia,
    count(*)::integer as contas_sem_mapa,
    sum(abs(s.debito - s.credito)) as movimento_sem_mapa
  from staging.saldo_contabil_empresa_mensal s
  join marts.mapa_conta_efetivo m
    on m.tenant_id = s.tenant_id and m.empresa_id = s.empresa_id and m.conta = s.conta
  where m.linha is null
    and (s.saldo_final <> 0 or s.debito <> 0 or s.credito <> 0
         or s.saldo_final_sem_zeramento <> 0 or s.debito_sem_zeramento <> 0 or s.credito_sem_zeramento <> 0)
  group by s.tenant_id, s.empresa_id, s.competencia
)
select m.tenant_id, m.empresa_id, m.competencia,
  round(coalesce(f.saldo_liquido, 0), 2) as saldo_liquido_acumulado,
  round(coalesce(f.caixa_equivalentes, 0), 2) as caixa_equivalentes_acumulado,
  round(coalesce(f.saldo_liquido, 0) - coalesce(f.caixa_equivalentes, 0), 2) as diferenca_identidade,
  round(coalesce(f.lucros_acumulados, 0), 2) as lucros_acumulados,
  round(coalesce(d.lucro_liquido, 0), 2) as lucro_liquido_dre,
  round(coalesce(f.lucros_acumulados, 0) - coalesce(d.lucro_liquido, 0), 2) as ajuste_exercicios_anteriores,
  coalesce(sm.contas_sem_mapa, 0) as contas_sem_mapa,
  round(coalesce(sm.movimento_sem_mapa, 0), 2) as movimento_sem_mapa
from mes m
left join fontes_usos f on f.tenant_id = m.tenant_id and f.empresa_id = m.empresa_id and f.competencia = m.competencia
left join dre d on d.tenant_id = m.tenant_id and d.empresa_id = m.empresa_id and d.competencia = m.competencia
left join sem_mapa sm on sm.tenant_id = m.tenant_id and sm.empresa_id = m.empresa_id and sm.competencia = m.competencia
where (select auth.uid()) is null or (select app.perfil_atual()) in ('diretor', 'financeiro');

grant select on marts.controle_fontes_usos to authenticated;

-- Contas analíticas com saldo ou movimento em algum mês e sem linha efetiva. Conta nova no ERP aparece aqui
-- no dia seguinte, em vez de sumir do F&U em silêncio. saldo_final é o do último mês carregado da empresa.
create view marts.conta_sem_mapa with (security_invoker = true) as
with ultimo as (
  select tenant_id, empresa_id, max(competencia) as competencia
  from staging.saldo_contabil_empresa_mensal
  group by tenant_id, empresa_id
)
select s.tenant_id, s.empresa_id, s.conta, p.conta_reduzida, p.nome, p.grupo,
  round(coalesce(max(s.saldo_final) filter (where s.competencia = u.competencia), 0), 2) as saldo_final,
  round(sum(abs(s.debito - s.credito)), 2) as movimento
from staging.saldo_contabil_empresa_mensal s
join marts.mapa_conta_efetivo m
  on m.tenant_id = s.tenant_id and m.empresa_id = s.empresa_id and m.conta = s.conta
join ultimo u on u.tenant_id = s.tenant_id and u.empresa_id = s.empresa_id
left join staging.plano_conta p
  on p.tenant_id = s.tenant_id and p.empresa_id = s.empresa_id and p.conta = s.conta
where m.linha is null
  and ((select auth.uid()) is null or (select app.perfil_atual()) in ('diretor', 'financeiro'))
group by s.tenant_id, s.empresa_id, s.conta, p.conta_reduzida, p.nome, p.grupo
having bool_or(s.saldo_final <> 0 or s.debito <> 0 or s.credito <> 0
               or s.saldo_final_sem_zeramento <> 0 or s.debito_sem_zeramento <> 0 or s.credito_sem_zeramento <> 0);

grant select on marts.conta_sem_mapa to authenticated;

-- Uma linha por empresa permitida, com a posição acumulada do último mês carregado. Empresa ainda sem
-- balancete aparece com as medidas nulas. Sem perfil no corpo: o RLS de app.empresa decide quem vê.
create view marts.empresa_resumo with (security_invoker = true) as
with periodo as (
  select tenant_id, empresa_id, min(competencia) as primeira_competencia, max(competencia) as ultima_competencia
  from staging.saldo_contabil_empresa_mensal
  group by tenant_id, empresa_id
), fontes_usos as (
  select v.tenant_id, v.empresa_id, v.competencia,
    coalesce(sum(v.valor_acumulado) filter (where c.total = 'saldo_liquido'), 0) as saldo_liquido,
    coalesce(sum(v.valor_acumulado) filter (where c.total = 'caixa_equivalentes'), 0) as caixa_equivalentes,
    coalesce(sum(v.valor_acumulado) filter (where c.total = 'fluxo_operacional'), 0) as fluxo_operacional
  from marts.saldo_linha_mensal v
  join periodo p on p.tenant_id = v.tenant_id and p.empresa_id = v.empresa_id and p.ultima_competencia = v.competencia
  join marts.composicao_relatorio c
    on c.demonstrativo = 'fontes_usos' and c.componente = v.linha
   and c.total in ('saldo_liquido', 'caixa_equivalentes', 'fluxo_operacional')
  where v.demonstrativo = 'fontes_usos'
  group by v.tenant_id, v.empresa_id, v.competencia
), dre as (
  select v.tenant_id, v.empresa_id, sum(v.valor_acumulado) as lucro_liquido
  from marts.saldo_linha_mensal v
  join periodo p on p.tenant_id = v.tenant_id and p.empresa_id = v.empresa_id and p.ultima_competencia = v.competencia
  join marts.composicao_relatorio c
    on c.demonstrativo = 'dre' and c.componente = v.linha and c.total = 'lucro_liquido'
  where v.demonstrativo = 'dre'
  group by v.tenant_id, v.empresa_id
), sem_mapa as (
  select s.tenant_id, s.empresa_id, count(distinct s.conta)::integer as contas_sem_mapa
  from staging.saldo_contabil_empresa_mensal s
  join marts.mapa_conta_efetivo m
    on m.tenant_id = s.tenant_id and m.empresa_id = s.empresa_id and m.conta = s.conta
  where m.linha is null
    and (s.saldo_final <> 0 or s.debito <> 0 or s.credito <> 0
         or s.saldo_final_sem_zeramento <> 0 or s.debito_sem_zeramento <> 0 or s.credito_sem_zeramento <> 0)
  group by s.tenant_id, s.empresa_id
), obras as (
  select tenant_id, empresa_id, count(*)::integer as obras
  from app.centro_custo
  where empresa_id is not null
  group by tenant_id, empresa_id
)
select e.tenant_id, e.id as empresa_id, e.nome, e.nome_fantasia,
  coalesce(o.obras, 0) as obras,
  p.primeira_competencia, p.ultima_competencia,
  round(f.caixa_equivalentes, 2) as caixa_equivalentes,
  round(f.fluxo_operacional, 2) as fluxo_operacional,
  round(d.lucro_liquido, 2) as lucro_liquido,
  round(f.saldo_liquido - f.caixa_equivalentes, 2) as diferenca_identidade,
  coalesce(sm.contas_sem_mapa, 0) as contas_sem_mapa
from app.empresa e
left join obras o on o.tenant_id = e.tenant_id and o.empresa_id = e.id_origem
left join periodo p on p.tenant_id = e.tenant_id and p.empresa_id = e.id
left join fontes_usos f on f.tenant_id = e.tenant_id and f.empresa_id = e.id
left join dre d on d.tenant_id = e.tenant_id and d.empresa_id = e.id
left join sem_mapa sm on sm.tenant_id = e.tenant_id and sm.empresa_id = e.id;

grant select on marts.empresa_resumo to authenticated;
