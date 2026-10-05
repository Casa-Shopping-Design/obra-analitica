-- DRE de viabilidade (migration 0030) com o caso feito à mão do anexo C.6 do plano APO. Cria os próprios dados.
--   Obra Norte: duas unidades vendidas por 1000 e duas em estoque por 500 (VGV 3000); orçamento 1600; título de
--   800 pago no mês passado e 300 em aberto no mês que vem; parcela direta de 600 recebida; mapa do ERP do mês
--   passado (receita 1000, custo incorrido 800); alíquota de 4%; estudo com VGV 2800 e construção 1500.
--   Obra Sul: uma unidade vendida por 1000; orçamento 500; 200 pago e 100 em aberto; sem mapa e sem alíquota.
--   Tenant vizinho com uma obra, para provar o isolamento.
begin;
create extension if not exists pgtap with schema extensions;
select plan(46);

create temporary table referencia on commit drop as
select m::date as mes_0,
  (m - interval '3 months')::date as menos_3,
  (m - interval '1 month')::date as menos_1,
  (m + interval '1 month')::date as mais_1
from date_trunc('month', current_date) as m;
grant select on referencia to authenticated;

insert into app.tenant (id, razao_social) values
  ('0e000000-0000-4000-8000-0000000000d1', 'Construtora DRE'),
  ('0e000000-0000-4000-8000-0000000000d2', 'Construtora DRE vizinha');

insert into app.centro_custo (id, tenant_id, id_origem, nome) values
  ('0c000000-0000-4000-8000-0000000000d1', '0e000000-0000-4000-8000-0000000000d1', 991, 'Obra Norte'),
  ('0c000000-0000-4000-8000-0000000000d2', '0e000000-0000-4000-8000-0000000000d1', 992, 'Obra Sul'),
  ('0c000000-0000-4000-8000-0000000000d3', '0e000000-0000-4000-8000-0000000000d2', 991, 'Obra vizinha');

insert into auth.users (id, email) values
  ('0a000000-0000-4000-8000-00000000d0d1', 'diretor.dre@teste.invalid'),
  ('0a000000-0000-4000-8000-00000000d0c1', 'gerente.dre@teste.invalid'),
  ('0a000000-0000-4000-8000-00000000d0d2', 'diretor.dre.vizinho@teste.invalid');

insert into app.usuario_tenant (user_id, tenant_id, perfil) values
  ('0a000000-0000-4000-8000-00000000d0d1', '0e000000-0000-4000-8000-0000000000d1', 'diretor'),
  ('0a000000-0000-4000-8000-00000000d0c1', '0e000000-0000-4000-8000-0000000000d1', 'gerente_obra'),
  ('0a000000-0000-4000-8000-00000000d0d2', '0e000000-0000-4000-8000-0000000000d2', 'diretor');

insert into app.usuario_centro_custo (user_id, tenant_id, centro_custo_id) values
  ('0a000000-0000-4000-8000-00000000d0c1', '0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1');

-- Obra Norte
insert into staging.unidade (tenant_id, centro_custo_id, id_origem, nome, situacao) values
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1', 1, 'N-1', 'V'),
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1', 2, 'N-2', 'V'),
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1', 3, 'N-3', 'D'),
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1', 4, 'N-4', 'D');
insert into staging.unidade_valor (tenant_id, centro_custo_id, unidade_id_origem, valor_sugerido) values
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1', 3, 500),
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1', 4, 500);
insert into staging.contrato_venda (tenant_id, centro_custo_id, id_origem, data_venda, valor, situacao, unidade_id_origem)
select '0e000000-0000-4000-8000-0000000000d1'::uuid, '0c000000-0000-4000-8000-0000000000d1'::uuid, id_origem, data_venda,
  1000, '1', unidade
from referencia, lateral (values (10, menos_3 + 4, 1), (11, menos_1 + 4, 2)) as c (id_origem, data_venda, unidade);
insert into staging.parcela_receber (tenant_id, centro_custo_id, id_origem, contrato_id_origem, vencimento,
                                     valor_original, saldo, tipo_condicao)
select '0e000000-0000-4000-8000-0000000000d1'::uuid, '0c000000-0000-4000-8000-0000000000d1'::uuid, 1, 10, menos_1 + 5,
  600, 0, 'PM'
from referencia;
insert into staging.recebimento (tenant_id, centro_custo_id, contrato_id_origem, parcela_id_origem, sequencia,
                                 data_recebimento, valor)
select '0e000000-0000-4000-8000-0000000000d1'::uuid, '0c000000-0000-4000-8000-0000000000d1'::uuid, 10, 1, 1, menos_1 + 5, 600
from referencia;
insert into staging.titulo_pagar (tenant_id, centro_custo_id, id_origem, vencimento, valor_original, saldo, data_pagamento)
select '0e000000-0000-4000-8000-0000000000d1'::uuid, '0c000000-0000-4000-8000-0000000000d1'::uuid, id_origem, vencimento,
  valor, saldo, data_pagamento
from referencia, lateral (values
  (80, menos_1 + 9, 800, 0, menos_1 + 9),
  (81, mais_1 + 9, 300, 300, null)
) as t (id_origem, vencimento, valor, saldo, data_pagamento);
insert into staging.rateio_titulo (tenant_id, titulo_id_origem, centro_custo_id, valor, fracao) values
  ('0e000000-0000-4000-8000-0000000000d1', 80, '0c000000-0000-4000-8000-0000000000d1', 800, 1),
  ('0e000000-0000-4000-8000-0000000000d1', 81, '0c000000-0000-4000-8000-0000000000d1', 300, 1);
insert into staging.pagamento (tenant_id, centro_custo_id, titulo_id_origem, sequencia, data_pagamento, valor)
select '0e000000-0000-4000-8000-0000000000d1'::uuid, '0c000000-0000-4000-8000-0000000000d1'::uuid, 80, 1, menos_1 + 9, 800
from referencia;
insert into staging.item_orcamento (tenant_id, centro_custo_id, codigo, descricao, valor_total) values
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1', '01', 'Construção', 1600);
insert into staging.mapa_imobiliario_mensal (tenant_id, centro_custo_id, competencia, unidades, vgv, poc, recebido_acumulado,
                                             custo_orcado, custo_incorrido_acumulado, custo_a_incorrer, receita_acumulada)
select '0e000000-0000-4000-8000-0000000000d1'::uuid, '0c000000-0000-4000-8000-0000000000d1'::uuid, menos_1, 4, 3000, 50, 600,
  1600, 800, 800, 1000
from referencia;
insert into app.aliquota_imposto_obra (tenant_id, centro_custo_id, vigencia_inicio, aliquota)
select '0e000000-0000-4000-8000-0000000000d1'::uuid, '0c000000-0000-4000-8000-0000000000d1'::uuid, menos_3, 0.04
from referencia;
insert into app.estudo_viabilidade (id, tenant_id, centro_custo_id, versao, descricao, data_base, situacao)
select '0d000000-0000-4000-8000-0000000000d1', '0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1',
  1, 'Estudo de lançamento', menos_3, 'vigente'
from referencia;
insert into app.estudo_viabilidade_linha (estudo_id, tenant_id, centro_custo_id, linha, valor)
select '0d000000-0000-4000-8000-0000000000d1', '0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1',
  linha, valor
from (values
  ('vgv_bruto', 2800), ('impostos', 112), ('custo_terreno', 300), ('custo_projetos', 50), ('custo_licenciamento', 30),
  ('custo_construcao', 1500), ('assistencia_tecnica', 40), ('juros_financiamento', 60), ('estoque', 0),
  ('despesas_comerciais', 100), ('despesas_administrativas', 80)
) as l (linha, valor);

-- Obra Sul
insert into staging.unidade (tenant_id, centro_custo_id, id_origem, nome, situacao) values
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d2', 5, 'S-1', 'V');
insert into staging.contrato_venda (tenant_id, centro_custo_id, id_origem, data_venda, valor, situacao, unidade_id_origem)
select '0e000000-0000-4000-8000-0000000000d1'::uuid, '0c000000-0000-4000-8000-0000000000d2'::uuid, 20, menos_3 + 4, 1000, '1', 5
from referencia;
insert into staging.titulo_pagar (tenant_id, centro_custo_id, id_origem, vencimento, valor_original, saldo, data_pagamento)
select '0e000000-0000-4000-8000-0000000000d1'::uuid, '0c000000-0000-4000-8000-0000000000d2'::uuid, id_origem, vencimento,
  valor, saldo, data_pagamento
from referencia, lateral (values
  (82, menos_1 + 9, 200, 0, menos_1 + 9),
  (83, mais_1 + 9, 100, 100, null)
) as t (id_origem, vencimento, valor, saldo, data_pagamento);
insert into staging.rateio_titulo (tenant_id, titulo_id_origem, centro_custo_id, valor, fracao) values
  ('0e000000-0000-4000-8000-0000000000d1', 82, '0c000000-0000-4000-8000-0000000000d2', 200, 1),
  ('0e000000-0000-4000-8000-0000000000d1', 83, '0c000000-0000-4000-8000-0000000000d2', 100, 1);
insert into staging.pagamento (tenant_id, centro_custo_id, titulo_id_origem, sequencia, data_pagamento, valor)
select '0e000000-0000-4000-8000-0000000000d1'::uuid, '0c000000-0000-4000-8000-0000000000d2'::uuid, 82, 1, menos_1 + 9, 200
from referencia;
insert into staging.item_orcamento (tenant_id, centro_custo_id, codigo, descricao, valor_total) values
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d2', '01', 'Construção', 500);
insert into app.estudo_viabilidade (id, tenant_id, centro_custo_id, versao, descricao, data_base, situacao)
select '0d000000-0000-4000-8000-0000000000d2', '0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d2',
  1, 'Estudo de lançamento', menos_3, 'vigente'
from referencia;
insert into app.estudo_viabilidade_linha (estudo_id, tenant_id, centro_custo_id, linha, valor)
select '0d000000-0000-4000-8000-0000000000d2', '0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d2',
  linha, valor
from (values
  ('vgv_bruto', 1000), ('impostos', 40), ('custo_terreno', 0), ('custo_projetos', 0), ('custo_licenciamento', 0),
  ('custo_construcao', 500), ('assistencia_tecnica', 0), ('juros_financiamento', 0), ('estoque', 0),
  ('despesas_comerciais', 0), ('despesas_administrativas', 0)
) as l (linha, valor);

-- Estrutura e permissões

select ok(
  (select bool_and(c.relrowsecurity and c.relforcerowsecurity) from pg_class c
   where c.oid in ('app.estudo_viabilidade'::regclass, 'app.estudo_viabilidade_linha'::regclass,
                   'app.aliquota_imposto_obra'::regclass)),
  'RLS ligado e forçado nas três tabelas'
);
select is(
  (select count(*) from pg_policies where schemaname = 'app'
     and tablename in ('estudo_viabilidade', 'estudo_viabilidade_linha', 'aliquota_imposto_obra')
     and permissive = 'PERMISSIVE'),
  3::bigint,
  'uma política permissiva por tabela'
);
select is(
  (select count(*) from pg_policies where schemaname = 'app'
     and tablename in ('estudo_viabilidade', 'estudo_viabilidade_linha', 'aliquota_imposto_obra')
     and permissive = 'PERMISSIVE' and cmd <> 'SELECT'),
  0::bigint,
  'nenhuma política de insert, update ou delete'
);
select ok(
  not has_table_privilege('authenticated', 'app.estudo_viabilidade', 'insert, update, delete')
  and not has_table_privilege('authenticated', 'app.estudo_viabilidade_linha', 'insert, update, delete')
  and not has_table_privilege('authenticated', 'app.aliquota_imposto_obra', 'insert, update, delete')
  and not has_table_privilege('anon', 'app.estudo_viabilidade', 'select'),
  'usuário logado não escreve nas tabelas pela API e anônimo não lê'
);
select ok(
  (select bool_and(c.reloptions @> array['security_invoker=true']) from pg_class c
   where c.oid in ('marts.linha_resultado'::regclass, 'marts.dre_viabilidade'::regclass, 'marts.dre_resumo_obra'::regclass)),
  'as três views rodam como quem consulta'
);
select ok(
  has_table_privilege('authenticated', 'marts.dre_viabilidade', 'select')
  and has_table_privilege('authenticated', 'marts.dre_resumo_obra', 'select')
  and not has_table_privilege('anon', 'marts.dre_viabilidade', 'select')
  and not has_table_privilege('anon', 'marts.dre_resumo_obra', 'select'),
  'usuário logado lê as views e anônimo não'
);
select ok(
  not has_function_privilege('anon', 'app.gravar_viabilidade(uuid, text, date, jsonb)', 'execute')
  and not has_function_privilege('public', 'app.gravar_viabilidade(uuid, text, date, jsonb)', 'execute')
  and not has_function_privilege('anon', 'app.gravar_aliquota_imposto(uuid, date, numeric)', 'execute')
  and not has_function_privilege('public', 'app.gravar_aliquota_imposto(uuid, date, numeric)', 'execute')
  and has_function_privilege('authenticated', 'app.gravar_viabilidade(uuid, text, date, jsonb)', 'execute')
  and has_function_privilege('authenticated', 'app.gravar_aliquota_imposto(uuid, date, numeric)', 'execute'),
  'só o usuário logado executa as duas funções de gravação'
);
select ok(
  (select bool_and(prosecdef and proconfig @> array['search_path=""']) from pg_proc
   where oid in ('app.gravar_viabilidade(uuid, text, date, jsonb)'::regprocedure,
                 'app.gravar_aliquota_imposto(uuid, date, numeric)'::regprocedure)),
  'as duas funções são security definer com search_path vazio'
);

-- Diretor com segundo fator

select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000d0d1", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;

select results_eq(
  $$select viabilidade, apropriado, a_apropriar, a_contratar, tendencia, desvio, desvio_pct from marts.dre_viabilidade
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000d1' and linha = 'vgv_bruto'$$,
  $$values (2800::numeric, 1000::numeric, 1000::numeric, 1000::numeric, 3000::numeric, 200::numeric, 0.0714::numeric)$$,
  'Norte, vgv_bruto: apropriado do mapa, a apropriar do vendido, a contratar do estoque'
);
select results_eq(
  $$select viabilidade, apropriado, a_apropriar, a_contratar, tendencia, desvio, desvio_pct from marts.dre_viabilidade
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000d1' and linha = 'impostos'$$,
  $$values (112::numeric, 40::numeric, 40::numeric, 40::numeric, 120::numeric, 8::numeric, 0.0714::numeric)$$,
  'Norte, impostos: 4% de cada coluna do VGV'
);
select results_eq(
  $$select viabilidade, apropriado, a_apropriar, a_contratar, tendencia, desvio, desvio_pct from marts.dre_viabilidade
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000d1' and linha = 'vgv_liquido'$$,
  $$values (2688::numeric, 960::numeric, 960::numeric, 960::numeric, 2880::numeric, 192::numeric, 0.0714::numeric)$$,
  'Norte, vgv_liquido: VGV bruto menos impostos'
);
select results_eq(
  $$select viabilidade, apropriado, a_apropriar, a_contratar, tendencia, desvio, desvio_pct from marts.dre_viabilidade
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000d1' and linha = 'custo_terreno'$$,
  $$values (300::numeric, 0::numeric, 0::numeric, 300::numeric, 300::numeric, 0::numeric, 0::numeric)$$,
  'Norte, custo_terreno: sem fonte de realizado, tendência igual ao estudo'
);
select results_eq(
  $$select viabilidade, apropriado, a_apropriar, a_contratar, tendencia, desvio, desvio_pct from marts.dre_viabilidade
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000d1' and linha = 'custo_construcao'$$,
  $$values (1500::numeric, 800::numeric, 300::numeric, 500::numeric, 1600::numeric, 100::numeric, 0.0667::numeric)$$,
  'Norte, custo_construcao: incorrido do mapa, lançado menos incorrido, orçado menos lançado'
);
select results_eq(
  $$select viabilidade, apropriado, a_apropriar, a_contratar, tendencia, desvio, desvio_pct from marts.dre_viabilidade
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000d1' and linha = 'custo_empreendimento'$$,
  $$values (1880::numeric, 800::numeric, 300::numeric, 880::numeric, 1980::numeric, 100::numeric, 0.0532::numeric)$$,
  'Norte, custo_empreendimento: terreno, projetos, licenciamento e construção'
);
select results_eq(
  $$select viabilidade, apropriado, a_apropriar, a_contratar, tendencia, desvio, desvio_pct from marts.dre_viabilidade
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000d1' and linha = 'custo_vendas'$$,
  $$values (1980::numeric, 800::numeric, 300::numeric, 980::numeric, 2080::numeric, 100::numeric, 0.0505::numeric)$$,
  'Norte, custo_vendas: empreendimento mais assistência, juros e estoque'
);
select results_eq(
  $$select viabilidade, apropriado, a_apropriar, a_contratar, tendencia, desvio, desvio_pct from marts.dre_viabilidade
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000d1' and linha = 'resultado_bruto'$$,
  $$values (708::numeric, 160::numeric, 660::numeric, -20::numeric, 800::numeric, 92::numeric, 0.1299::numeric)$$,
  'Norte, resultado_bruto: VGV bruto menos impostos e custo de vendas'
);
select results_eq(
  $$select viabilidade, apropriado, a_apropriar, a_contratar, tendencia, desvio, desvio_pct from marts.dre_viabilidade
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000d1' and linha = 'despesas'$$,
  $$values (180::numeric, 0::numeric, 0::numeric, 180::numeric, 180::numeric, 0::numeric, 0::numeric)$$,
  'Norte, despesas: comerciais mais administrativas, sem realizado'
);
select results_eq(
  $$select viabilidade, apropriado, a_apropriar, a_contratar, tendencia, desvio, desvio_pct from marts.dre_viabilidade
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000d1' and linha = 'lucro_operacional'$$,
  $$values (528::numeric, 160::numeric, 660::numeric, -200::numeric, 620::numeric, 92::numeric, 0.1742::numeric)$$,
  'Norte, lucro_operacional: resultado bruto menos despesas'
);
select results_eq(
  $$select linha, pct_viabilidade, pct_tendencia from marts.dre_viabilidade
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000d1'
      and linha in ('custo_construcao', 'resultado_bruto', 'lucro_operacional') order by ordem$$,
  $$values ('custo_construcao', 0.5580::numeric, 0.5556::numeric), ('resultado_bruto', 0.2634::numeric, 0.2778::numeric),
           ('lucro_operacional', 0.1964::numeric, 0.2153::numeric)$$,
  'percentuais sobre o VGV líquido da mesma coluna'
);
select results_eq(
  $$select linha, desvio_favoravel from marts.dre_viabilidade
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000d1'
      and linha in ('vgv_bruto', 'impostos', 'custo_terreno', 'custo_construcao', 'resultado_bruto') order by ordem$$,
  $$values ('vgv_bruto', true), ('impostos', false), ('custo_terreno', null::boolean), ('custo_construcao', false),
           ('resultado_bruto', true)$$,
  'desvio favorável depende da natureza da linha e fica nulo sem desvio'
);
select is(
  (select count(*) from marts.dre_viabilidade where centro_custo_id = '0c000000-0000-4000-8000-0000000000d1'),
  17::bigint,
  'dezessete linhas por obra'
);
select results_eq(
  $$select linha, fonte_realizado from marts.dre_viabilidade
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000d1'
      and linha in ('vgv_bruto', 'impostos', 'vgv_liquido', 'custo_terreno', 'custo_construcao') order by ordem$$,
  $$values ('vgv_bruto', 'origem'), ('impostos', 'aliquota'), ('vgv_liquido', 'total'), ('custo_terreno', 'sem_fonte'),
           ('custo_construcao', 'origem')$$,
  'fonte do realizado por linha na obra com mapa e alíquota'
);
select is(
  (select row(competencia, estudo_versao, a_realizar)::text from marts.dre_viabilidade
   where centro_custo_id = '0c000000-0000-4000-8000-0000000000d1' and linha = 'vgv_bruto'),
  (select row(menos_1, 1, 2000.00)::text from referencia),
  'competência é o mês do último mapa e a realizar soma a apropriar com a contratar'
);
select results_eq(
  $$select pct_vendido, poc, custo_apropriado, recebido_acumulado, margem_operacional_viabilidade, margem_operacional_tendencia,
      desvio_margem_operacional
    from marts.dre_resumo_obra where centro_custo_id = '0c000000-0000-4000-8000-0000000000d1'$$,
  $$values (0.6667::numeric, 0.5::numeric, 800::numeric, 600::numeric, 0.1964::numeric, 0.2153::numeric, 0.0189::numeric)$$,
  'resumo da Norte: vendido sobre a tendência, POC, custo apropriado, recebido e margens'
);
select results_eq(
  $$select vgv_bruto_viabilidade, vgv_bruto_tendencia, vgv_vendido, receita_apropriada, resultado_bruto_viabilidade,
      resultado_bruto_tendencia, lucro_operacional_viabilidade, lucro_operacional_tendencia
    from marts.dre_resumo_obra where centro_custo_id = '0c000000-0000-4000-8000-0000000000d1'$$,
  $$values (2800::numeric, 3000::numeric, 2000::numeric, 1000::numeric, 708::numeric, 800::numeric, 528::numeric, 620::numeric)$$,
  'resumo da Norte repete os valores da DRE'
);
select results_eq(
  $$select linha, apropriado, a_apropriar, a_contratar, tendencia, fonte_realizado from marts.dre_viabilidade
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000d2'
      and linha in ('vgv_bruto', 'impostos', 'custo_construcao') order by ordem$$,
  $$values ('vgv_bruto', 400::numeric, 600::numeric, 0::numeric, 1000::numeric, 'titulos'),
           ('impostos', 0::numeric, 0::numeric, 40::numeric, 40::numeric, 'sem_fonte'),
           ('custo_construcao', 200::numeric, 100::numeric, 200::numeric, 500::numeric, 'titulos')$$,
  'Sul, sem mapa e sem alíquota: POC próprio de 40%, impostos sem fonte, construção pelos títulos'
);
select results_eq(
  $$select viabilidade, tendencia, desvio, desvio_pct, desvio_favoravel from marts.dre_viabilidade
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000d2' and linha = 'lucro_operacional'$$,
  $$values (460::numeric, 460::numeric, 0::numeric, 0::numeric, null::boolean)$$,
  'Sul, lucro_operacional: 460 nas duas colunas, sem desvio'
);
select is(
  (select competencia from marts.dre_viabilidade
   where centro_custo_id = '0c000000-0000-4000-8000-0000000000d2' and linha = 'vgv_bruto'),
  (select mes_0 from referencia),
  'obra sem mapa usa o mês corrente como competência'
);
select is(
  (select count(distinct centro_custo_id) from marts.dre_viabilidade),
  2::bigint,
  'diretor vê as duas obras do tenant e nenhuma do vizinho'
);

-- Gerente da Obra Norte

reset role;
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-00000000d0c1", "role": "authenticated"}', true);
set local role authenticated;

select is(
  (select count(*) from marts.dre_viabilidade) + (select count(*) from app.estudo_viabilidade)
    + (select count(*) from marts.dre_resumo_obra) + (select count(*) from app.aliquota_imposto_obra),
  0::bigint,
  'gerente não lê a DRE nem o estudo da própria obra'
);
select throws_ok(
  $$select app.gravar_viabilidade('0c000000-0000-4000-8000-0000000000d1', 'Tentativa', current_date, '{"vgv_bruto": 1}')$$,
  '42501', null, 'gerente não grava o estudo'
);
select throws_ok(
  $$select app.gravar_aliquota_imposto('0c000000-0000-4000-8000-0000000000d1', current_date, 0.05)$$,
  '42501', null, 'gerente não grava a alíquota'
);

-- Diretor só com a senha

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000d0d1", "role": "authenticated", "aal": "aal1"}', true);
set local role authenticated;

select is(
  (select count(*) from marts.dre_viabilidade) + (select count(*) from app.estudo_viabilidade),
  0::bigint,
  'diretor em aal1 não lê a DRE'
);
select throws_ok(
  $$select app.gravar_viabilidade('0c000000-0000-4000-8000-0000000000d1', 'Tentativa', current_date, '{"vgv_bruto": 1}')$$,
  '42501', null, 'diretor em aal1 não grava o estudo'
);

-- Diretor do tenant vizinho

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000d0d2", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;

select is(
  (select count(*) from marts.dre_viabilidade) + (select count(*) from app.estudo_viabilidade),
  0::bigint,
  'diretor de outro tenant não lê a DRE'
);
select throws_ok(
  $$select app.gravar_viabilidade('0c000000-0000-4000-8000-0000000000d1', 'Tentativa', current_date, '{"vgv_bruto": 1}')$$,
  '42501', null, 'diretor de outro tenant não grava na Obra Norte'
);

-- Diretor com segundo fator grava uma versão nova

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000d0d1", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;

select throws_ok(
  $$select app.gravar_viabilidade('0c000000-0000-4000-8000-0000000000d1', 'Tentativa', current_date, '{"lucro_liquido": 1}')$$,
  '22023', null, 'linha fora da lista é recusada'
);
select throws_ok(
  $$select app.gravar_viabilidade('0c000000-0000-4000-8000-0000000000d1', 'Tentativa', current_date, '{"vgv_bruto": -1}')$$,
  '22023', null, 'valor negativo é recusado'
);
select throws_ok(
  $$select app.gravar_viabilidade('0c000000-0000-4000-8000-0000000000d1', 'Tentativa', current_date, '{"vgv_bruto": "2900"}')$$,
  '22023', null, 'valor em texto é recusado'
);
select throws_ok(
  $$select app.gravar_viabilidade('0c000000-0000-4000-8000-0000000000d1', 'Tentativa', current_date + 1, '{"vgv_bruto": 2900}')$$,
  '22023', null, 'data-base no futuro é recusada'
);
select is(
  app.gravar_viabilidade('0c000000-0000-4000-8000-0000000000d1', 'Revisão', current_date,
    '{"vgv_bruto": 2900, "impostos": 116, "custo_terreno": 300, "custo_projetos": 50, "custo_licenciamento": 30,
      "custo_construcao": 1500, "assistencia_tecnica": 40, "juros_financiamento": 60, "estoque": 0,
      "despesas_comerciais": 100, "despesas_administrativas": 80}'),
  2,
  'diretor em aal2 grava a versão 2'
);
select results_eq(
  $$select versao, situacao, criado_por from app.estudo_viabilidade
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000d1' order by versao$$,
  $$values (1, 'substituida', null::uuid), (2, 'vigente', '0a000000-0000-4000-8000-00000000d0d1'::uuid)$$,
  'a versão 1 vira substituída e a 2 fica vigente com quem gravou'
);
select is(
  (select viabilidade from marts.dre_viabilidade
   where centro_custo_id = '0c000000-0000-4000-8000-0000000000d1' and linha = 'vgv_bruto'),
  2900::numeric,
  'a DRE passa a mostrar o VGV da versão 2'
);
select throws_ok(
  $$select app.gravar_aliquota_imposto('0c000000-0000-4000-8000-0000000000d1', current_date, 0.3)$$,
  '22023', null, 'alíquota acima de 0,2 é recusada'
);
select lives_ok(
  $$select app.gravar_aliquota_imposto('0c000000-0000-4000-8000-0000000000d1', current_date, 0.05)$$,
  'diretor em aal2 grava alíquota nova'
);
select is(
  (select tendencia from marts.dre_viabilidade
   where centro_custo_id = '0c000000-0000-4000-8000-0000000000d1' and linha = 'impostos'),
  150::numeric,
  'a alíquota mais recente passa a valer: 5% de 3000'
);

select * from finish();
rollback;
