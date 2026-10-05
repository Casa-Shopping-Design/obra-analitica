-- Assistente sobre a DRE de viabilidade (plano APO, etapa 13): o SQL das perguntas prontas novas, executado
-- pelo caminho real (marts.executar_consulta, com o JWT de quem pergunta), devolve os números do caso feito
-- à mão da Obra Norte para diretor em aal2 e para leitura em aal1, devolve zero linhas para a gerente da
-- própria obra e nem roda para o diretor que perdeu o segundo fator. O validador do painel recusa antes;
-- este teste prova que o banco segura mesmo se a consulta chegar. Cria os próprios dados, os mesmos de dre_viabilidade.sql.
--   Obra Norte: VGV 3000 (2 vendidas por 1000, 2 em estoque por 500), mapa do mês passado com receita 1000 e
--   custo apropriado 500, parcela de 600 recebida, orçamento 1600 com 800 pago e 300 em aberto, alíquota 4%,
--   estudo com VGV 2800 e impostos 112. Lucro operacional: 528 no estudo, 620 na tendência, margem 0,1964 e
--   0,2153. Imposto a realizar: 40 sobre o vendido a apropriar mais 40 sobre o estoque, 80.
-- As reservas vêm antes das execuções, porque executar_consulta deixa a transação só de leitura.
begin;
create extension if not exists pgtap with schema extensions;
select plan(22);

create temporary table referencia on commit drop as
select m::date as mes_0,
  (m - interval '3 months')::date as menos_3,
  (m - interval '1 month')::date as menos_1,
  (m + interval '1 month')::date as mais_1
from date_trunc('month', current_date) as m;
grant select on referencia to authenticated, anon;

insert into app.tenant (id, razao_social) values
  ('0e000000-0000-4000-8000-0000000013a1', 'Construtora Assistente DRE');

insert into app.centro_custo (id, tenant_id, id_origem, nome) values
  ('0c000000-0000-4000-8000-0000000013a1', '0e000000-0000-4000-8000-0000000013a1', 1301, 'Obra Norte');

insert into auth.users (id, email) values
  ('0a000000-0000-4000-8000-0000000d13a1', 'diretor.assistente.dre@teste.invalid'),
  ('0a000000-0000-4000-8000-0000000e13a1', 'leitura.assistente.dre@teste.invalid'),
  ('0a000000-0000-4000-8000-0000000c13a1', 'gerente.assistente.dre@teste.invalid');

insert into app.usuario_tenant (user_id, tenant_id, perfil) values
  ('0a000000-0000-4000-8000-0000000d13a1', '0e000000-0000-4000-8000-0000000013a1', 'diretor'),
  ('0a000000-0000-4000-8000-0000000e13a1', '0e000000-0000-4000-8000-0000000013a1', 'leitura'),
  ('0a000000-0000-4000-8000-0000000c13a1', '0e000000-0000-4000-8000-0000000013a1', 'gerente_obra');

insert into app.usuario_centro_custo (user_id, tenant_id, centro_custo_id) values
  ('0a000000-0000-4000-8000-0000000e13a1', '0e000000-0000-4000-8000-0000000013a1', '0c000000-0000-4000-8000-0000000013a1'),
  ('0a000000-0000-4000-8000-0000000c13a1', '0e000000-0000-4000-8000-0000000013a1', '0c000000-0000-4000-8000-0000000013a1');

-- Obra Norte, igual a dre_viabilidade.sql
insert into staging.unidade (tenant_id, centro_custo_id, id_origem, nome, situacao) values
  ('0e000000-0000-4000-8000-0000000013a1', '0c000000-0000-4000-8000-0000000013a1', 1, 'N-1', 'V'),
  ('0e000000-0000-4000-8000-0000000013a1', '0c000000-0000-4000-8000-0000000013a1', 2, 'N-2', 'V'),
  ('0e000000-0000-4000-8000-0000000013a1', '0c000000-0000-4000-8000-0000000013a1', 3, 'N-3', 'D'),
  ('0e000000-0000-4000-8000-0000000013a1', '0c000000-0000-4000-8000-0000000013a1', 4, 'N-4', 'D');
insert into staging.unidade_valor (tenant_id, centro_custo_id, unidade_id_origem, valor_sugerido) values
  ('0e000000-0000-4000-8000-0000000013a1', '0c000000-0000-4000-8000-0000000013a1', 3, 500),
  ('0e000000-0000-4000-8000-0000000013a1', '0c000000-0000-4000-8000-0000000013a1', 4, 500);
insert into staging.contrato_venda (tenant_id, centro_custo_id, id_origem, data_venda, valor, situacao, unidade_id_origem)
select '0e000000-0000-4000-8000-0000000013a1'::uuid, '0c000000-0000-4000-8000-0000000013a1'::uuid, id_origem, data_venda,
  1000, '1', unidade
from referencia, lateral (values (10, menos_3 + 4, 1), (11, menos_1 + 4, 2)) as c (id_origem, data_venda, unidade);
insert into staging.parcela_receber (tenant_id, centro_custo_id, id_origem, contrato_id_origem, vencimento,
                                     valor_original, saldo, tipo_condicao)
select '0e000000-0000-4000-8000-0000000013a1'::uuid, '0c000000-0000-4000-8000-0000000013a1'::uuid, 1, 10, menos_1 + 5,
  600, 0, 'PM'
from referencia;
insert into staging.recebimento (tenant_id, centro_custo_id, contrato_id_origem, parcela_id_origem, sequencia,
                                 data_recebimento, valor)
select '0e000000-0000-4000-8000-0000000013a1'::uuid, '0c000000-0000-4000-8000-0000000013a1'::uuid, 10, 1, 1, menos_1 + 5, 600
from referencia;
insert into staging.titulo_pagar (tenant_id, centro_custo_id, id_origem, vencimento, valor_original, saldo, data_pagamento)
select '0e000000-0000-4000-8000-0000000013a1'::uuid, '0c000000-0000-4000-8000-0000000013a1'::uuid, id_origem, vencimento,
  valor, saldo, data_pagamento
from referencia, lateral (values
  (80, menos_1 + 9, 800, 0, menos_1 + 9),
  (81, mais_1 + 9, 300, 300, null)
) as t (id_origem, vencimento, valor, saldo, data_pagamento);
insert into staging.rateio_titulo (tenant_id, titulo_id_origem, centro_custo_id, valor, fracao) values
  ('0e000000-0000-4000-8000-0000000013a1', 80, '0c000000-0000-4000-8000-0000000013a1', 800, 1),
  ('0e000000-0000-4000-8000-0000000013a1', 81, '0c000000-0000-4000-8000-0000000013a1', 300, 1);
insert into staging.pagamento (tenant_id, centro_custo_id, titulo_id_origem, sequencia, data_pagamento, valor)
select '0e000000-0000-4000-8000-0000000013a1'::uuid, '0c000000-0000-4000-8000-0000000013a1'::uuid, 80, 1, menos_1 + 9, 800
from referencia;
insert into staging.item_orcamento (tenant_id, centro_custo_id, codigo, descricao, valor_total) values
  ('0e000000-0000-4000-8000-0000000013a1', '0c000000-0000-4000-8000-0000000013a1', '01', 'Construção', 1600);
insert into staging.mapa_imobiliario_mensal (tenant_id, centro_custo_id, competencia, unidades, vgv, poc, recebido_acumulado,
                                             custo_orcado, custo_incorrido_acumulado, custo_acumulado, custo_a_incorrer,
                                             receita_acumulada)
select '0e000000-0000-4000-8000-0000000013a1'::uuid, '0c000000-0000-4000-8000-0000000013a1'::uuid, menos_1, 4, 3000, 50, 600,
  1600, 800, 500, 800, 1000
from referencia;
insert into app.aliquota_imposto_obra (tenant_id, centro_custo_id, vigencia_inicio, aliquota)
select '0e000000-0000-4000-8000-0000000013a1'::uuid, '0c000000-0000-4000-8000-0000000013a1'::uuid, menos_3, 0.04
from referencia;
insert into app.estudo_viabilidade (id, tenant_id, centro_custo_id, versao, descricao, data_base, situacao)
select '0d000000-0000-4000-8000-0000000013a1', '0e000000-0000-4000-8000-0000000013a1', '0c000000-0000-4000-8000-0000000013a1',
  1, 'Estudo de lançamento', menos_3, 'vigente'
from referencia;
insert into app.estudo_viabilidade_linha (estudo_id, tenant_id, centro_custo_id, linha, valor)
select '0d000000-0000-4000-8000-0000000013a1', '0e000000-0000-4000-8000-0000000013a1', '0c000000-0000-4000-8000-0000000013a1',
  linha, valor
from (values
  ('vgv_bruto', 2800), ('impostos', 112), ('custo_terreno', 300), ('custo_projetos', 50), ('custo_licenciamento', 30),
  ('custo_construcao', 1500), ('assistencia_tecnica', 40), ('juros_financiamento', 60), ('estoque', 0),
  ('despesas_comerciais', 100), ('despesas_administrativas', 80)
) as l (linha, valor);

-- A carga grava a posição do mês corrente, para a tendência mensal ter uma linha
select is(app.registrar_posicao_dre('0e000000-0000-4000-8000-0000000013a1'), 11, 'a carga grava as onze linhas da Norte');

-- Chave só deste teste; a de produção é gravada por João e nunca entra no repositório.
delete from app.chave_assinatura_consulta;
insert into app.chave_assinatura_consulta (chave) values ('chave-local-do-teste-assistente-dre-00');

create function pg_temp.assinar(p_sql text) returns text language sql as $$
  select encode(extensions.hmac(p_sql, 'chave-local-do-teste-assistente-dre-00', 'sha256'), 'hex')
$$;
-- Cada execução grava na reserva e deixa a transação só de leitura; o bloco desfaz as duas coisas para a
-- mesma reserva servir a várias consultas do teste.
create function pg_temp.consultar(p_reserva text, p_sql text) returns jsonb language plpgsql as $$
declare
  linhas jsonb;
begin
  begin
    linhas := marts.executar_consulta(current_setting(p_reserva)::bigint, p_sql, pg_temp.assinar(p_sql));
    raise exception using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  return linhas;
end;
$$;
grant execute on function pg_temp.assinar(text), pg_temp.consultar(text, text) to authenticated, anon;

-- O SQL das cinco perguntas prontas de painel/lib/perguntas-prontas.ts, com a Obra Norte no lugar da Parque.
create temporary table pergunta_pronta (id text primary key, sql text) on commit drop;
insert into pergunta_pronta values
  ('tendencia-lucro-obras',
   'select obra, viabilidade, tendencia, desvio, desvio_pct from marts.dre_viabilidade where linha = ''lucro_operacional'' order by desvio'),
  ('linha-mais-desvia-norte',
   'select obra, case linha when ''impostos'' then ''Impostos'' when ''custo_construcao'' then ''Construção'' end as linha, viabilidade, tendencia, desvio from marts.dre_viabilidade where obra ilike ''%norte%'' and linha_de_total = false and desvio_favoravel = false order by abs(desvio) desc limit 3'),
  ('margem-perdida-obras',
   'select obra, margem_operacional_viabilidade, margem_operacional_tendencia, desvio_margem_operacional from marts.dre_resumo_obra order by desvio_margem_operacional'),
  ('receita-a-apropriar-obras',
   'select obra, apropriado, a_apropriar, a_contratar from marts.dre_viabilidade where linha = ''vgv_bruto'' order by obra'),
  ('imposto-a-gerar-obras',
   'select obra, aliquota, imposto_receita_a_apropriar, imposto_vgv_estoque, imposto_a_realizar from marts.imposto_obra order by imposto_a_realizar desc'),
  ('tendencia-mensal',
   'select obra, competencia, lucro_operacional_viabilidade, lucro_operacional_tendencia, margem_operacional_tendencia from marts.tendencia_resultado_mensal order by competencia');
grant select on pergunta_pronta to authenticated, anon;

create function pg_temp.pronta(p_id text) returns text language sql as $$
  select sql from pergunta_pronta where id = p_id
$$;
grant execute on function pg_temp.pronta(text) to authenticated, anon;

-- Reservas: uma por usuário, antes de qualquer execução
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-0000000d13a1", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;
select set_config('teste.reserva_diretor',
  app.reservar_pergunta('00000000-0000-4000-8000-000000001301', 'Qual a tendência do lucro?')::text, true);

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-0000000e13a1", "role": "authenticated", "aal": "aal1"}', true);
set local role authenticated;
select lives_ok(
  $$select set_config('teste.reserva_leitura',
    app.reservar_pergunta('00000000-0000-4000-8000-000000001302', 'Quanto de imposto falta?')::text, true)$$,
  'leitura em aal1 reserva pergunta ao assistente'
);

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-0000000c13a1", "role": "authenticated", "aal": "aal1"}', true);
set local role authenticated;
select set_config('teste.reserva_gerente',
  app.reservar_pergunta('00000000-0000-4000-8000-000000001303', 'Qual a tendência do lucro?')::text, true);

-- Gerente da Obra Norte: a consulta chega ao banco e volta vazia
select is(
  pg_temp.consultar('teste.reserva_gerente', pg_temp.pronta('tendencia-lucro-obras')),
  '[]'::jsonb,
  'gerente: tendência do lucro da própria obra volta sem linha'
);
select is(
  pg_temp.consultar('teste.reserva_gerente', pg_temp.pronta('margem-perdida-obras')),
  '[]'::jsonb,
  'gerente: resumo da DRE volta sem linha'
);
select is(
  pg_temp.consultar('teste.reserva_gerente', pg_temp.pronta('imposto-a-gerar-obras')),
  '[]'::jsonb,
  'gerente: imposto volta sem linha'
);
select is(
  pg_temp.consultar('teste.reserva_gerente', pg_temp.pronta('tendencia-mensal')),
  '[]'::jsonb,
  'gerente: tendência mensal volta sem linha'
);
select is(
  pg_temp.consultar('teste.reserva_gerente', 'select sum(tendencia) as soma from marts.dre_viabilidade'),
  '[{"soma": null}]'::jsonb,
  'gerente: a soma da coluna inteira não tem linha para somar'
);
select is(
  (select l ->> 'obra'
   from jsonb_array_elements(pg_temp.consultar('teste.reserva_gerente',
     'select obra, exposicao_maxima from marts.posicao_financeira_obra')) l),
  'Obra Norte',
  'gerente: a posição financeira da própria obra continua respondendo'
);

-- Diretor com segundo fator: os números do caso feito à mão
reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-0000000d13a1", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;

select is(
  (select row(l ->> 'obra', trim_scale((l ->> 'viabilidade')::numeric), trim_scale((l ->> 'tendencia')::numeric), trim_scale((l ->> 'desvio')::numeric),
              trim_scale((l ->> 'desvio_pct')::numeric))::text
   from jsonb_array_elements(pg_temp.consultar('teste.reserva_diretor', pg_temp.pronta('tendencia-lucro-obras'))) l),
  row('Obra Norte', 528::numeric, 620::numeric, 92::numeric, 0.1742::numeric)::text,
  'diretor: lucro operacional 528 no estudo, 620 na tendência, desvio 92 (17,42%)'
);
select is(
  jsonb_array_length(pg_temp.consultar('teste.reserva_diretor', pg_temp.pronta('tendencia-lucro-obras'))),
  1,
  'diretor: uma linha por obra com estudo'
);
select results_eq(
  $$select l ->> 'linha', trim_scale((l ->> 'desvio')::numeric)
    from jsonb_array_elements(pg_temp.consultar('teste.reserva_diretor', pg_temp.pronta('linha-mais-desvia-norte')))
      with ordinality as t (l, n) order by n$$,
  $$values ('Construção', 100::numeric), ('Impostos', 8::numeric)$$,
  'diretor: as linhas desfavoráveis da Norte são construção (100) e impostos (8), nessa ordem'
);
select is(
  (select row(trim_scale((l ->> 'margem_operacional_viabilidade')::numeric), trim_scale((l ->> 'margem_operacional_tendencia')::numeric),
              trim_scale((l ->> 'desvio_margem_operacional')::numeric))::text
   from jsonb_array_elements(pg_temp.consultar('teste.reserva_diretor', pg_temp.pronta('margem-perdida-obras'))) l),
  row(0.1964::numeric, 0.2153::numeric, 0.0189::numeric)::text,
  'diretor: margem 19,64% no estudo e 21,53% na tendência, 1,89 ponto acima'
);
select is(
  (select row(trim_scale((l ->> 'apropriado')::numeric), trim_scale((l ->> 'a_apropriar')::numeric), trim_scale((l ->> 'a_contratar')::numeric))::text
   from jsonb_array_elements(pg_temp.consultar('teste.reserva_diretor', pg_temp.pronta('receita-a-apropriar-obras'))) l),
  row(1000::numeric, 1000::numeric, 1000::numeric)::text,
  'diretor: receita apropriada 1000, vendido a apropriar 1000, estoque a vender 1000'
);
select is(
  (select row(trim_scale((l ->> 'aliquota')::numeric), trim_scale((l ->> 'imposto_receita_a_apropriar')::numeric),
              trim_scale((l ->> 'imposto_vgv_estoque')::numeric), trim_scale((l ->> 'imposto_a_realizar')::numeric))::text
   from jsonb_array_elements(pg_temp.consultar('teste.reserva_diretor', pg_temp.pronta('imposto-a-gerar-obras'))) l),
  row(0.04::numeric, 40::numeric, 40::numeric, 80::numeric)::text,
  'diretor: alíquota 4%, 40 sobre o vendido a apropriar, 40 sobre o estoque, 80 a realizar'
);
select is(
  (select row(trim_scale((l ->> 'lucro_operacional_viabilidade')::numeric), trim_scale((l ->> 'lucro_operacional_tendencia')::numeric),
              trim_scale((l ->> 'margem_operacional_tendencia')::numeric))::text
   from jsonb_array_elements(pg_temp.consultar('teste.reserva_diretor', pg_temp.pronta('tendencia-mensal'))) l),
  row(528::numeric, 620::numeric, 0.2153::numeric)::text,
  'diretor: a posição do mês corrente repete o lucro e a margem da DRE de hoje'
);
select is(
  (select trim_scale((l ->> 'soma')::numeric)
   from jsonb_array_elements(pg_temp.consultar('teste.reserva_diretor', 'select sum(tendencia) as soma from marts.dre_viabilidade')) l),
  (select sum(tendencia) from marts.dre_viabilidade where centro_custo_id = '0c000000-0000-4000-8000-0000000013a1'),
  'diretor: somar a coluna inteira roda e devolve a soma com os totais dentro, por isso o catálogo manda filtrar por linha'
);

-- Perfil leitura, só com a senha, vinculado à Obra Norte
reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-0000000e13a1", "role": "authenticated", "aal": "aal1"}', true);
set local role authenticated;

select is(
  (select row(l ->> 'obra', trim_scale((l ->> 'tendencia')::numeric))::text
   from jsonb_array_elements(pg_temp.consultar('teste.reserva_leitura', pg_temp.pronta('tendencia-lucro-obras'))) l),
  row('Obra Norte', 620::numeric)::text,
  'leitura em aal1: lê a tendência do lucro da obra liberada'
);
select is(
  (select trim_scale((l ->> 'imposto_a_realizar')::numeric)
   from jsonb_array_elements(pg_temp.consultar('teste.reserva_leitura', pg_temp.pronta('imposto-a-gerar-obras'))) l),
  80::numeric,
  'leitura em aal1: lê o imposto a realizar'
);
select is(
  jsonb_array_length(pg_temp.consultar('teste.reserva_leitura', pg_temp.pronta('tendencia-mensal'))),
  1,
  'leitura em aal1: lê a tendência mensal'
);

-- Diretor que perdeu o segundo fator: a reserva é dele, mas a consulta nem roda
reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-0000000d13a1", "role": "authenticated", "aal": "aal1"}', true);
set local role authenticated;

select throws_ok(
  format('select marts.executar_consulta(%s, %L, %L)', current_setting('teste.reserva_diretor'),
    pg_temp.pronta('tendencia-lucro-obras'), pg_temp.assinar(pg_temp.pronta('tendencia-lucro-obras'))),
  '42501',
  null,
  'diretor em aal1 não executa a consulta da própria reserva'
);
select throws_ok(
  $$select app.reservar_pergunta('00000000-0000-4000-8000-000000001304', 'outra')$$,
  '42501',
  null,
  'diretor em aal1 não reserva pergunta nova'
);

-- Anônimo
reset role;
set local role anon;
select throws_ok(
  format('select marts.executar_consulta(%s, %L, %L)', current_setting('teste.reserva_diretor'),
    pg_temp.pronta('tendencia-lucro-obras'), pg_temp.assinar(pg_temp.pronta('tendencia-lucro-obras'))),
  '42501',
  null,
  'anônimo não executa consulta'
);

select * from finish();
rollback;
