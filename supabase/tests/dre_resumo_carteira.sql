-- Resumo da DRE somado por tenant (migration 0031) com as mesmas Obra Norte e Obra Sul de dre_viabilidade.sql,
-- caso feito à mão no anexo C.6 do plano APO. Cria os próprios dados.
--   Soma esperada: VGV de hoje 3000 + 1000, vendido 2000 + 1000, receita apropriada 1000 + 400, custo apropriado
--   500 + 200 (o da Norte é o apropriado ao resultado do mapa), recebido 600 + 0, lucro operacional 528 + 460 no estudo e 620 + 460 na tendência, sobre VGV
--   líquido de 2688 + 960 no estudo e 2880 + 960 na tendência.
--   O tenant vizinho ganha um estudo, para provar que cada diretor só soma as próprias obras.
begin;
create extension if not exists pgtap with schema extensions;
select plan(13);

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
                                             custo_orcado, custo_incorrido_acumulado, custo_acumulado, custo_a_incorrer,
                                             receita_acumulada)
select '0e000000-0000-4000-8000-0000000000d1'::uuid, '0c000000-0000-4000-8000-0000000000d1'::uuid, menos_1, 4, 3000, 50, 600,
  1600, 800, 500, 800, 1000
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

-- Obra vizinha, de outro tenant, com estudo
insert into app.estudo_viabilidade (id, tenant_id, centro_custo_id, versao, descricao, data_base, situacao)
select '0d000000-0000-4000-8000-0000000000d3', '0e000000-0000-4000-8000-0000000000d2', '0c000000-0000-4000-8000-0000000000d3',
  1, 'Estudo de lançamento', menos_3, 'vigente'
from referencia;
insert into app.estudo_viabilidade_linha (estudo_id, tenant_id, centro_custo_id, linha, valor)
select '0d000000-0000-4000-8000-0000000000d3', '0e000000-0000-4000-8000-0000000000d2', '0c000000-0000-4000-8000-0000000000d3',
  linha, valor
from (values
  ('vgv_bruto', 100), ('impostos', 0), ('custo_terreno', 0), ('custo_projetos', 0), ('custo_licenciamento', 0),
  ('custo_construcao', 0), ('assistencia_tecnica', 0), ('juros_financiamento', 0), ('estoque', 0),
  ('despesas_comerciais', 0), ('despesas_administrativas', 0)
) as l (linha, valor);

-- Estrutura e permissões

select ok(
  (select c.reloptions @> array['security_invoker=true'] from pg_class c where c.oid = 'marts.dre_resumo_carteira'::regclass),
  'a view roda como quem consulta'
);
select ok(
  has_table_privilege('authenticated', 'marts.dre_resumo_carteira', 'select')
  and not has_table_privilege('anon', 'marts.dre_resumo_carteira', 'select'),
  'usuário logado lê a view e anônimo não'
);
select is(
  (select array_agg(column_name::text order by ordinal_position) from information_schema.columns
   where table_schema = 'marts' and table_name = 'dre_resumo_carteira'),
  array['tenant_id', 'obras', 'vgv_bruto_tendencia', 'vgv_vendido', 'pct_vendido', 'receita_apropriada', 'poc',
        'custo_apropriado', 'recebido_acumulado', 'lucro_operacional_viabilidade', 'lucro_operacional_tendencia',
        'margem_operacional_viabilidade', 'margem_operacional_tendencia', 'desvio_margem_operacional'],
  'colunas na ordem do plano'
);
select ok(
  pg_get_viewdef('marts.dre_resumo_carteira'::regclass) !~ '(perfil_atual|tenant_atual)',
  'sem predicado de perfil nem de tenant no corpo'
);

-- Diretor com segundo fator

select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000d0d1", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;

select is(
  (select count(*) from marts.dre_resumo_carteira),
  1::bigint,
  'diretor lê uma linha, a do próprio tenant'
);
select results_eq(
  $$select obras, vgv_bruto_tendencia, vgv_vendido, pct_vendido from marts.dre_resumo_carteira$$,
  $$values (2::bigint, 4000::numeric, 3000::numeric, 0.75::numeric)$$,
  'duas obras, VGV de hoje 4000 e 75% vendido'
);
select results_eq(
  $$select receita_apropriada, poc, custo_apropriado, recebido_acumulado from marts.dre_resumo_carteira$$,
  $$values (1400::numeric, 0.4667::numeric, 700::numeric, 600::numeric)$$,
  'receita apropriada 1400, POC 1400 sobre 3000, custo apropriado 700 e recebido 600'
);
select results_eq(
  $$select lucro_operacional_viabilidade, lucro_operacional_tendencia from marts.dre_resumo_carteira$$,
  $$values (988::numeric, 1080::numeric)$$,
  'lucro operacional 988 no estudo e 1080 na tendência'
);
select results_eq(
  $$select margem_operacional_viabilidade, margem_operacional_tendencia, desvio_margem_operacional
    from marts.dre_resumo_carteira$$,
  $$values (0.2708::numeric, 0.2813::numeric, 0.0105::numeric)$$,
  'margem 988 sobre 3648 no estudo e 1080 sobre 3840 na tendência, sem média das margens das obras'
);
select is(
  (select lucro_operacional_tendencia from marts.dre_resumo_carteira),
  (select sum(lucro_operacional_tendencia) from marts.dre_resumo_obra),
  'a soma bate com o resumo por obra'
);

-- Gerente da Obra Norte

reset role;
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-00000000d0c1", "role": "authenticated"}', true);
set local role authenticated;

select is((select count(*) from marts.dre_resumo_carteira), 0::bigint, 'gerente lê zero linhas');

-- Diretor só com a senha

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000d0d1", "role": "authenticated", "aal": "aal1"}', true);
set local role authenticated;

select is((select count(*) from marts.dre_resumo_carteira), 0::bigint, 'diretor em aal1 lê zero linhas');

-- Diretor do tenant vizinho

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000d0d2", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;

select results_eq(
  $$select tenant_id, obras from marts.dre_resumo_carteira$$,
  $$values ('0e000000-0000-4000-8000-0000000000d2'::uuid, 1::bigint)$$,
  'diretor do tenant vizinho soma só a própria obra'
);

select * from finish();
rollback;
