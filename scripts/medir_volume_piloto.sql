-- Roteiro de medição das consultas das telas no volume do piloto (plano 4.4). Não é pgTAP.
-- Pré-requisito: rodar scripts/gerar_volume_piloto.py no mesmo banco. Sem o tenant do volume, só avisa e sai.
-- Cria um diretor e um gerente (com a Obra Volume 01) dentro da transação, roda cada consulta das telas como
-- authenticated com EXPLAIN (ANALYZE, BUFFERS) três vezes e mostra o tempo de execução da primeira e o menor
-- das outras duas, os Seq Scan com mais de 5 mil linhas lidas e o total por tela. Termina em rollback.
-- As consultas copiam o que painel/lib/consultas/*.ts pede ao PostgREST (mesmos filtros, ordem e limites).
begin;

select count(*) = 1 as tem_volume from app.tenant where razao_social = 'Volume sintético do piloto (revisão)' \gset
\if :tem_volume

select id as tenant from app.tenant where razao_social = 'Volume sintético do piloto (revisão)' \gset
select id as obra from app.centro_custo where tenant_id = :'tenant' and nome = 'Obra Volume 01' \gset

insert into auth.users (id, email) values
  ('d9000000-0000-4000-8000-000000000001', 'diretor.volume@exemplo.invalid'),
  ('d9000000-0000-4000-8000-000000000002', 'gerente.volume@exemplo.invalid');
insert into app.usuario_tenant (user_id, tenant_id, perfil) values
  ('d9000000-0000-4000-8000-000000000001', :'tenant', 'diretor'),
  ('d9000000-0000-4000-8000-000000000002', :'tenant', 'gerente_obra');
insert into app.usuario_centro_custo (user_id, tenant_id, centro_custo_id)
values ('d9000000-0000-4000-8000-000000000002', :'tenant', :'obra');

create temp table consulta_tela (ordem serial, tela text, escopo text, nome text, consulta text);
insert into consulta_tela (tela, escopo, nome, consulta) values
  ('comum', 'todas', 'identidade', 'select perfil, t.razao_social from app.usuario_tenant u join app.tenant t on t.id = u.tenant_id limit 1'),
  ('comum', 'todas', 'situacao_carga', 'select * from app.situacao_carga()'),
  ('comum', 'todas', 'centros_custo', 'select id, nome, tipo from app.centro_custo order by tipo desc, nome'),
  ('visao_geral', 'consolidado', 'posicao', 'select * from marts.posicao_financeira_obra order by obra'),
  ('visao_geral', 'consolidado', 'resumo_receitas', 'select * from marts.resumo_receitas_obra where tipo_centro = ''obra'' order by obra'),
  ('visao_geral', 'consolidado', 'custo_resumo', 'select * from marts.custo_obra_resumo order by tipo_centro desc, obra'),
  ('visao_geral', 'consolidado', 'exposicao_projetada', 'select centro_custo_id, exposicao_maxima_projetada, mes_exposicao_maxima, exposicao_parcial, motivo_distribuicao from marts.resumo_projecao_obra'),
  ('visao_geral', 'consolidado', 'dre_ano', 'select * from marts.dre_periodo({ini}, {mes}, null) order by linha_ordem'),
  ('visao_geral', 'consolidado', 'conta_pendencias', 'select count(*) from marts.pendencia_classificacao'),
  ('dre', 'consolidado', 'dre_periodo', 'select * from marts.dre_periodo({ini}, {mes}, null) order by linha_ordem'),
  ('dre', 'consolidado', 'dre_mensal_consolidado', 'select * from marts.dre_mensal_consolidado where competencia >= {ini} and competencia <= {mes} order by competencia, linha_ordem'),
  ('dre', 'consolidado', 'reconhecimento_mes', 'select * from marts.reconhecimento_obra_mensal where competencia = {mes} order by centro_custo_id'),
  ('dre', 'consolidado', 'pendencias_pagina', 'select * from marts.pendencia_classificacao order by valor_envolvido desc limit 20'),
  ('dre', 'consolidado', 'pendencias_contagem', 'select count(*) from marts.pendencia_classificacao'),
  ('dre', 'obra', 'dre_periodo', 'select * from marts.dre_periodo({ini}, {mes}, {obra}) order by linha_ordem'),
  ('dre', 'obra', 'dre_mensal', 'select * from marts.dre_mensal where centro_custo_id = {obra} and competencia >= {ini} and competencia <= {mes} order by competencia, linha_ordem'),
  ('dre', 'obra', 'reconhecimento_mes', 'select * from marts.reconhecimento_obra_mensal where competencia = {mes} and centro_custo_id = {obra}'),
  ('dre', 'obra', 'pendencias_pagina', 'select * from marts.pendencia_classificacao order by valor_envolvido desc limit 20'),
  ('dre', 'obra', 'pendencias_contagem', 'select count(*) from marts.pendencia_classificacao'),
  ('receitas', 'consolidado', 'resumo_receitas', 'select * from marts.resumo_receitas_obra where tipo_centro = ''obra'' order by obra'),
  ('receitas', 'consolidado', 'resumo_consolidado', 'select * from marts.resumo_receitas_consolidado'),
  ('receitas', 'consolidado', 'recebimento_periodo', 'select * from marts.recebimento_periodo({ini}, {mes}, null)'),
  ('receitas', 'consolidado', 'recebimento_mensal_consolidado', 'select * from marts.recebimento_mensal_consolidado where competencia >= {ini_ev} and competencia <= {fim_ev} order by competencia, origem'),
  ('receitas', 'consolidado', 'carteira_pagina', 'select centro_custo_id, contrato_id_origem, contrato_numero, unidade, parcela_id_origem, numero_parcela, tipo_condicao, origem, vencimento, valor_original, valor_recebido, saldo, data_ultimo_recebimento, situacao, parcial, dias_atraso, situacao_contrato from marts.carteira_recebiveis order by vencimento, contrato_numero, parcela_id_origem limit 50'),
  ('receitas', 'consolidado', 'carteira_contagem', 'select count(*) from marts.carteira_recebiveis'),
  ('receitas', 'obra', 'resumo_receitas', 'select * from marts.resumo_receitas_obra where tipo_centro = ''obra'' and centro_custo_id = {obra}'),
  ('receitas', 'obra', 'recebimento_periodo', 'select * from marts.recebimento_periodo({ini}, {mes}, {obra})'),
  ('receitas', 'obra', 'recebimento_mensal', 'select * from marts.recebimento_mensal where centro_custo_id = {obra} and competencia >= {ini_ev} and competencia <= {fim_ev} order by competencia, origem'),
  ('receitas', 'obra', 'carteira_pagina', 'select * from marts.carteira_recebiveis where centro_custo_id = {obra} order by vencimento, contrato_numero, parcela_id_origem limit 50'),
  ('receitas', 'obra', 'carteira_contagem', 'select count(*) from marts.carteira_recebiveis where centro_custo_id = {obra}'),
  ('receitas', 'obra', 'carteira_vencidas_contagem', 'select count(*) from marts.carteira_recebiveis where centro_custo_id = {obra} and situacao = ''vencida'''),
  ('despesas', 'consolidado', 'custo_resumo', 'select * from marts.custo_obra_resumo order by tipo_centro desc, obra'),
  ('despesas', 'consolidado', 'desembolso_periodo', 'select * from marts.desembolso_periodo({ini}, {mes}, null) order by lancado_competencia desc'),
  ('despesas', 'obra', 'custo_resumo', 'select * from marts.custo_obra_resumo where centro_custo_id = {obra}'),
  ('despesas', 'obra', 'custo_categoria', 'select * from marts.custo_obra_categoria where centro_custo_id = {obra} order by custo_lancado desc'),
  ('despesas', 'obra', 'desembolso_periodo', 'select * from marts.desembolso_periodo({ini}, {mes}, {obra}) order by lancado_competencia desc'),
  ('fluxo', 'consolidado', 'resumo_projecao', 'select * from marts.resumo_projecao_obra order by obra'),
  ('fluxo', 'obra', 'resumo_projecao', 'select * from marts.resumo_projecao_obra where centro_custo_id = {obra}'),
  ('fluxo', 'obra', 'fluxo_projetado', 'select * from marts.fluxo_projetado_mensal where centro_custo_id = {obra} order by centro_custo_id, competencia'),
  ('fluxo', 'obra', 'cenario_atraso_3', 'select * from marts.simular_fluxo({obra}, ''{"atraso_liberacao_bancaria_meses": 3}'') order by competencia'),
  ('simular', 'obra', 'resumo_projecao', 'select * from marts.resumo_projecao_obra where centro_custo_id = {obra}'),
  ('simular', 'obra', 'fluxo_projetado', 'select * from marts.fluxo_projetado_mensal where centro_custo_id = {obra} order by centro_custo_id, competencia'),
  ('simular', 'obra', 'estoque', 'select count(*) from marts.mapa_unidades where centro_custo_id = {obra} and situacao in (''disponivel'', ''reservada'', ''proposta'') and valor is not null'),
  ('simular', 'obra', 'simulacao', 'select * from marts.simular_fluxo({obra}, jsonb_build_object(''novas_vendas'', (select jsonb_agg(jsonb_build_object(''competencia'', (date_trunc(''month'', app.data_referencia()) + make_interval(months => g))::date, ''quantidade'', 2)) from generate_series(1, 12) g), ''desconto_tabela'', 0.05, ''composicao'', jsonb_build_object(''entrada'', 0.1, ''parcelas_mensais'', 0.3, ''quantidade_parcelas_mensais'', 36, ''financiamento'', 0.6), ''meses_ate_liberacao_financiamento'', 4)) order by competencia'),
  ('planejamento', 'consolidado', 'pendencias_pos_entrega', 'select * from marts.pendencias_pos_entrega order by data_entrega'),
  ('planejamento', 'obra', 'visao_gerencial', 'select * from marts.visao_gerencial_mensal where centro_custo_id = {obra} and competencia >= {mes_m6} and competencia <= {mes_p12} order by centro_custo_id, competencia'),
  ('planejamento', 'obra', 'explicacao_desvio', 'select * from marts.explicacao_desvio where centro_custo_id = {obra} and competencia >= {mes_m6} and competencia <= {mes} order by competencia desc, causa_codigo'),
  ('planejamento', 'obra', 'comparativo', 'select * from marts.comparativo_projecao where centro_custo_id = {obra} and competencia >= {mes_m6} and competencia <= {mes_p12} order by centro_custo_id, competencia'),
  ('planejamento', 'obra', 'versoes_projecao', 'select * from app.versao_planejamento where centro_custo_id = {obra} and tipo = ''projecao'' order by numero desc'),
  ('planejamento', 'obra', 'versoes_meta', 'select * from app.versao_planejamento where centro_custo_id = {obra} and tipo = ''meta'' order by numero desc'),
  ('planejamento', 'obra', 'premissa_vigente', 'select * from app.premissa_distribuicao_custo where centro_custo_id = {obra} order by criada_em desc limit 1'),
  ('planejamento', 'obra', 'resumo_projecao', 'select * from marts.resumo_projecao_obra where centro_custo_id = {obra}'),
  ('planejamento', 'obra', 'pendencias_pos_entrega', 'select * from marts.pendencias_pos_entrega where centro_custo_id = {obra} order by data_entrega'),
  ('financiamento', 'obra', 'saldo_operacoes', 'select * from marts.saldo_operacao_credito where centro_custo_id = {obra} order by centro_custo_id, instituicao'),
  ('financiamento', 'obra', 'financiamento_contratos', 'select * from marts.financiamento_contrato where centro_custo_id = {obra} order by classificacao desc, contrato_numero'),
  ('financiamento', 'obra', 'liberacoes', 'select * from marts.liberacao_status where centro_custo_id = {obra} order by data_prevista'),
  ('financiamento', 'obra', 'medicoes', 'select * from app.medicao_bancaria where centro_custo_id = {obra} order by operacao_credito_id, numero'),
  ('financiamento', 'obra', 'historico', 'select * from app.auditoria_alteracao where tabela in (''app.operacao_credito_obra'', ''app.liberacao_financiamento'') and (depois->>''centro_custo_id'' = {obra}::text or antes->>''centro_custo_id'' = {obra}::text) order by alterado_em desc limit 30'),
  ('obra_antiga', 'obra', 'posicao', 'select * from marts.posicao_financeira_obra where centro_custo_id = {obra}'),
  ('obra_antiga', 'obra', 'fluxo_caixa_mensal', 'select * from marts.fluxo_caixa_mensal where centro_custo_id = {obra} order by competencia'),
  ('obra_antiga', 'obra', 'cenario_3', 'select * from marts.fluxo_caixa_cenario(3) where centro_custo_id = {obra} order by competencia'),
  ('unidades', 'obra', 'mapa', 'select * from marts.mapa_unidades where centro_custo_id = {obra} order by tipologia, unidade limit 1000'),
  ('unidades', 'obra', 'estoque_posicao', 'select estoque_a_vender from marts.posicao_financeira_obra where centro_custo_id = {obra}'),
  ('assistente', 'consolidado', 'quando_falta_caixa_fluxo', 'select * from marts.fluxo_projetado_mensal where competencia >= {mes} order by centro_custo_id, competencia'),
  ('assistente', 'consolidado', 'quando_falta_caixa_resumo', 'select * from marts.resumo_projecao_obra order by obra'),
  ('assistente', 'consolidado', 'previsto_proximo_mes_fluxo', 'select * from marts.fluxo_projetado_mensal where competencia >= {prox} and competencia <= {prox} order by centro_custo_id, competencia'),
  ('assistente', 'consolidado', 'meta_do_mes_visao', 'select * from marts.visao_gerencial_mensal where competencia >= {mes} and competencia <= {mes} order by centro_custo_id, competencia'),
  ('assistente', 'consolidado', 'meta_do_mes_desvio', 'select * from marts.explicacao_desvio where competencia >= {mes} and competencia <= {mes} order by competencia desc, causa_codigo');

-- Datas a partir da data de referência do banco, como as telas fazem.
update consulta_tela set consulta = replace(replace(replace(replace(replace(replace(replace(replace(consulta,
  '{obra}', quote_literal(:'obra')),
  '{ini}', quote_literal(date_trunc('year', app.data_referencia())::date)),
  '{mes}', quote_literal(date_trunc('month', app.data_referencia())::date)),
  '{prox}', quote_literal((date_trunc('month', app.data_referencia()) + interval '1 month')::date)),
  '{ini_ev}', quote_literal((date_trunc('month', app.data_referencia()) - interval '11 months')::date)),
  '{fim_ev}', quote_literal((date_trunc('month', app.data_referencia()) + interval '12 months')::date)),
  '{mes_m6}', quote_literal((date_trunc('month', app.data_referencia()) - interval '6 months')::date)),
  '{mes_p12}', quote_literal((date_trunc('month', app.data_referencia()) + interval '12 months')::date));

create temp table medicao_tela (ordem integer, perfil text, rodada integer, execucao_ms numeric, planejamento_ms numeric,
                                linhas bigint, seq_scans text);

do $$
declare
  c record;
  p record;
  plano jsonb;
  rodada integer;
begin
  for p in select * from (values ('diretor', 'd9000000-0000-4000-8000-000000000001'),
                                 ('gerente', 'd9000000-0000-4000-8000-000000000002')) as x(perfil, usuario) loop
    for c in select * from consulta_tela order by ordem loop
      for rodada in 1..3 loop
        perform set_config('request.jwt.claims', json_build_object('sub', p.usuario, 'role', 'authenticated')::text, true);
        execute 'set local role authenticated';
        execute 'explain (analyze, buffers, format json) ' || c.consulta into plano;
        execute 'reset role';
        insert into medicao_tela
        select c.ordem, p.perfil, rodada, (plano -> 0 ->> 'Execution Time')::numeric, (plano -> 0 ->> 'Planning Time')::numeric,
               (plano -> 0 -> 'Plan' ->> 'Actual Rows')::bigint,
               (select string_agg(distinct (n ->> 'Relation Name') || ' ' ||
                        ((n ->> 'Actual Rows')::numeric * (n ->> 'Actual Loops')::numeric
                         + coalesce((n ->> 'Rows Removed by Filter')::numeric, 0) * (n ->> 'Actual Loops')::numeric), ', ')
                from jsonb_path_query(plano, 'strict $.**') n
                where n ->> 'Node Type' = 'Seq Scan'
                  and (n ->> 'Actual Rows')::numeric * (n ->> 'Actual Loops')::numeric
                      + coalesce((n ->> 'Rows Removed by Filter')::numeric, 0) * (n ->> 'Actual Loops')::numeric > 5000);
      end loop;
    end loop;
  end loop;
end $$;

\pset footer off
\echo 'Tempo por consulta (ms): primeira rodada e menor das duas seguintes'
select c.tela, c.escopo, c.nome, m.perfil,
       max(m.execucao_ms) filter (where m.rodada = 1) as primeira_ms,
       min(m.execucao_ms) filter (where m.rodada > 1) as menor_ms,
       min(m.planejamento_ms) filter (where m.rodada > 1) as planejamento_ms,
       max(m.linhas) as linhas,
       max(m.seq_scans) as seq_scans_grandes
from consulta_tela c join medicao_tela m using (ordem)
group by c.ordem, c.tela, c.escopo, c.nome, m.perfil
order by m.perfil, c.ordem;

\echo 'Total por tela (ms, menor rodada): soma sequencial e maior consulta; comum entra em toda tela'
with por_consulta as (
  select c.tela, c.escopo, m.perfil, min(m.execucao_ms + m.planejamento_ms) filter (where m.rodada > 1) as ms
  from consulta_tela c join medicao_tela m using (ordem)
  group by c.ordem, c.tela, c.escopo, m.perfil
), comum as (
  select perfil, sum(ms) as ms, max(ms) as maior from por_consulta where tela = 'comum' group by perfil
)
select t.tela, t.escopo, t.perfil, count(*) as consultas,
       round(sum(t.ms) + cm.ms, 1) as total_sequencial_ms,
       round(greatest(max(t.ms), cm.maior), 1) as maior_consulta_ms
from por_consulta t join comum cm using (perfil)
where t.tela <> 'comum'
group by t.tela, t.escopo, t.perfil, cm.ms, cm.maior
order by t.perfil, t.tela, t.escopo;

\else
\echo 'tenant do volume não encontrado: rode scripts/gerar_volume_piloto.py antes'
\endif

rollback;
