-- Posição mensal da DRE (migration 0033) com as mesmas Obra Norte e Obra Sul de dre_viabilidade.sql, caso feito
-- à mão na etapa 9 do plano APO. Cria os próprios dados.
--   Dois meses anteriores inseridos à mão na Obra Norte. No mês -1 a tendência por linha é VGV 2900, impostos 116,
--   terreno 300, projetos 50, licenciamento 30, construção 1500, assistência 40, juros 60, estoque 0, comerciais 100
--   e administrativas 80: VGV líquido 2784, custo de vendas 1980, despesas 180, lucro 624, margem 0,2241. O estudo
--   é o da etapa 2 (VGV 2800, impostos 112): lucro 528 e margem 0,1964. No mês -2 a tendência repete o estudo.
--   Depois a função grava o mês corrente duas vezes e a contagem fica em 22 (onze por obra) nas duas.
begin;
create extension if not exists pgtap with schema extensions;
select plan(34);

create temporary table referencia on commit drop as
select m::date as mes_0,
  (m - interval '3 months')::date as menos_3,
  (m - interval '2 months')::date as menos_2,
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
  ('0a000000-0000-4000-8000-00000000d0e1', 'leitura.dre@teste.invalid'),
  ('0a000000-0000-4000-8000-00000000d0d2', 'diretor.dre.vizinho@teste.invalid');

insert into app.usuario_tenant (user_id, tenant_id, perfil) values
  ('0a000000-0000-4000-8000-00000000d0d1', '0e000000-0000-4000-8000-0000000000d1', 'diretor'),
  ('0a000000-0000-4000-8000-00000000d0c1', '0e000000-0000-4000-8000-0000000000d1', 'gerente_obra'),
  ('0a000000-0000-4000-8000-00000000d0e1', '0e000000-0000-4000-8000-0000000000d1', 'leitura'),
  ('0a000000-0000-4000-8000-00000000d0d2', '0e000000-0000-4000-8000-0000000000d2', 'diretor');

insert into app.usuario_centro_custo (user_id, tenant_id, centro_custo_id) values
  ('0a000000-0000-4000-8000-00000000d0c1', '0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1'),
  ('0a000000-0000-4000-8000-00000000d0e1', '0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1');

-- Obra Norte, igual a dre_viabilidade.sql
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

-- Obra Sul, igual a dre_viabilidade.sql
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

-- Dois meses anteriores da Obra Norte, inseridos à mão. No mês -2 a tendência repete o estudo; no mês -1 ela
-- já anda (VGV 2900 e impostos 116), tudo em a_contratar para a soma fechar com a tendência.
insert into app.posicao_dre_mensal (tenant_id, centro_custo_id, competencia, linha, viabilidade, apropriado, a_apropriar,
                                    a_contratar, tendencia)
select '0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1', menos_2, linha, valor, 0, 0, valor, valor
from referencia, lateral (values
  ('vgv_bruto', 2800), ('impostos', 112), ('custo_terreno', 300), ('custo_projetos', 50), ('custo_licenciamento', 30),
  ('custo_construcao', 1500), ('assistencia_tecnica', 40), ('juros_financiamento', 60), ('estoque', 0),
  ('despesas_comerciais', 100), ('despesas_administrativas', 80)
) as l (linha, valor);
insert into app.posicao_dre_mensal (tenant_id, centro_custo_id, competencia, linha, viabilidade, apropriado, a_apropriar,
                                    a_contratar, tendencia)
select '0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1', menos_1, linha, viabilidade, 0, 0,
  tendencia, tendencia
from referencia, lateral (values
  ('vgv_bruto', 2800, 2900), ('impostos', 112, 116), ('custo_terreno', 300, 300), ('custo_projetos', 50, 50),
  ('custo_licenciamento', 30, 30), ('custo_construcao', 1500, 1500), ('assistencia_tecnica', 40, 40),
  ('juros_financiamento', 60, 60), ('estoque', 0, 0), ('despesas_comerciais', 100, 100), ('despesas_administrativas', 80, 80)
) as l (linha, viabilidade, tendencia);

-- Estrutura e permissões

select ok(
  (select c.relrowsecurity and c.relforcerowsecurity from pg_class c where c.oid = 'app.posicao_dre_mensal'::regclass),
  'RLS ligado e forçado na posição mensal'
);
select results_eq(
  $$select policyname::text collate "default", permissive::text, cmd::text from pg_policies
    where schemaname = 'app' and tablename = 'posicao_dre_mensal' order by policyname$$,
  $$values ('leitura_dre', 'PERMISSIVE', 'SELECT'), ('segundo_fator', 'RESTRICTIVE', 'ALL')$$,
  'uma permissiva de leitura e a restritiva do segundo fator, nenhuma de escrita'
);
select ok(
  not has_table_privilege('authenticated', 'app.posicao_dre_mensal', 'insert, update, delete')
  and not has_table_privilege('anon', 'app.posicao_dre_mensal', 'select')
  and has_table_privilege('authenticated', 'app.posicao_dre_mensal', 'select'),
  'usuário logado só lê a tabela e anônimo não lê'
);
select ok(
  not has_function_privilege('anon', 'app.registrar_posicao_dre(uuid)', 'execute')
  and not has_function_privilege('public', 'app.registrar_posicao_dre(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'app.registrar_posicao_dre(uuid)', 'execute'),
  'ninguém além da dona do banco executa a gravação da posição'
);
select ok(
  (select prosecdef and proconfig @> array['search_path=""'] from pg_proc
   where oid = 'app.registrar_posicao_dre(uuid)'::regprocedure),
  'a gravação é security definer com search_path vazio'
);
select ok(
  (select c.reloptions @> array['security_invoker=true'] from pg_class c
   where c.oid = 'marts.tendencia_resultado_mensal'::regclass),
  'a view roda como quem consulta'
);
select ok(
  has_table_privilege('authenticated', 'marts.tendencia_resultado_mensal', 'select')
  and not has_table_privilege('anon', 'marts.tendencia_resultado_mensal', 'select'),
  'usuário logado lê a view e anônimo não'
);
select throws_ok(
  $$insert into app.posicao_dre_mensal (tenant_id, centro_custo_id, competencia, linha, viabilidade, apropriado, a_apropriar,
      a_contratar, tendencia)
    select '0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d2', menos_1, 'vgv_bruto', 1000, 400,
      600, 0, 999
    from referencia$$,
  '23514', null, 'tendência diferente da soma das três colunas é recusada'
);
select throws_ok(
  $$insert into app.posicao_dre_mensal (tenant_id, centro_custo_id, competencia, linha, viabilidade, apropriado, a_apropriar,
      a_contratar, tendencia)
    select '0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d2', menos_1 + 15, 'vgv_bruto', 1000, 0,
      0, 1000, 1000
    from referencia$$,
  '23514', null, 'competência fora do primeiro dia do mês é recusada'
);

-- A carga grava o mês corrente, como dona do banco

select is(app.registrar_posicao_dre('0e000000-0000-4000-8000-0000000000d1'), 22, 'primeira gravação: onze linhas por obra');
select is(
  (select count(*) from app.posicao_dre_mensal p, referencia r
   where p.tenant_id = '0e000000-0000-4000-8000-0000000000d1' and p.competencia = r.mes_0),
  22::bigint,
  'o mês corrente tem 22 linhas depois da primeira gravação'
);
select is(app.registrar_posicao_dre('0e000000-0000-4000-8000-0000000000d2'), 0, 'tenant sem estudo não grava nada');
select is(
  (select count(*) from app.posicao_dre_mensal where tenant_id = '0e000000-0000-4000-8000-0000000000d2'),
  0::bigint,
  'a gravação de um tenant não toca o outro'
);
select results_eq(
  $$select p.linha, p.viabilidade, p.apropriado, p.a_apropriar, p.a_contratar, p.tendencia
    from app.posicao_dre_mensal p, referencia r
    where p.centro_custo_id = '0c000000-0000-4000-8000-0000000000d1' and p.competencia = r.mes_0
      and p.linha in ('vgv_bruto', 'impostos', 'custo_construcao') order by p.linha$$,
  $$values ('custo_construcao', 1500::numeric, 500::numeric, 600::numeric, 500::numeric, 1600::numeric),
           ('impostos', 112::numeric, 40::numeric, 40::numeric, 40::numeric, 120::numeric),
           ('vgv_bruto', 2800::numeric, 1000::numeric, 1000::numeric, 1000::numeric, 3000::numeric)$$,
  'a posição copia as colunas da DRE de viabilidade'
);

-- Alíquota nova entre as duas gravações: a segunda sobrescreve a linha em vez de duplicar
insert into app.aliquota_imposto_obra (tenant_id, centro_custo_id, vigencia_inicio, aliquota)
select '0e000000-0000-4000-8000-0000000000d1'::uuid, '0c000000-0000-4000-8000-0000000000d1'::uuid, mes_0, 0.05
from referencia;
select is(app.registrar_posicao_dre('0e000000-0000-4000-8000-0000000000d1'), 22, 'segunda gravação: as mesmas 22 linhas');
select is(
  (select count(*) from app.posicao_dre_mensal p, referencia r
   where p.tenant_id = '0e000000-0000-4000-8000-0000000000d1' and p.competencia = r.mes_0),
  22::bigint,
  'rodar de novo no mesmo mês não duplica'
);
select is(
  (select p.tendencia from app.posicao_dre_mensal p, referencia r
   where p.centro_custo_id = '0c000000-0000-4000-8000-0000000000d1' and p.competencia = r.mes_0 and p.linha = 'impostos'),
  150::numeric,
  'a segunda gravação atualiza a linha: 5% de 3000'
);
select results_eq(
  $$select centro_custo_id, count(distinct competencia) from app.posicao_dre_mensal
    where tenant_id = '0e000000-0000-4000-8000-0000000000d1' group by centro_custo_id order by centro_custo_id$$,
  $$values ('0c000000-0000-4000-8000-0000000000d1'::uuid, 3::bigint), ('0c000000-0000-4000-8000-0000000000d2'::uuid, 1::bigint)$$,
  'Norte com três competências e Sul só com a corrente'
);

-- Diretor com segundo fator

select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000d0d1", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;

select throws_ok(
  $$select app.registrar_posicao_dre('0e000000-0000-4000-8000-0000000000d1')$$,
  '42501', null, 'usuário logado não executa a gravação da posição'
);
select is(
  (select row(vgv_liquido_viabilidade, vgv_liquido_tendencia, custo_vendas_viabilidade, custo_vendas_tendencia,
              despesas_viabilidade, despesas_tendencia, lucro_operacional_viabilidade, lucro_operacional_tendencia,
              margem_operacional_viabilidade, margem_operacional_tendencia)::text
   from marts.tendencia_resultado_mensal t, referencia r
   where t.centro_custo_id = '0c000000-0000-4000-8000-0000000000d1' and t.competencia = r.menos_1),
  row(2688.00, 2784.00, 1980.00, 1980.00, 180.00, 180.00, 528.00, 624.00, 0.1964, 0.2241)::text,
  'Norte, mês -1: VGV líquido 2784, custo 1980, despesas 180, lucro 624 e margem 0,2241 na tendência; 528 e 0,1964 no estudo'
);
select is(
  (select row(lucro_operacional_viabilidade, lucro_operacional_tendencia, margem_operacional_tendencia)::text
   from marts.tendencia_resultado_mensal t, referencia r
   where t.centro_custo_id = '0c000000-0000-4000-8000-0000000000d1' and t.competencia = r.menos_2),
  row(528.00, 528.00, 0.1964)::text,
  'Norte, mês -2: tendência igual ao estudo'
);
select is(
  (select row(vgv_liquido_viabilidade, vgv_liquido_tendencia, custo_vendas_viabilidade, custo_vendas_tendencia,
              despesas_viabilidade, despesas_tendencia, lucro_operacional_viabilidade, lucro_operacional_tendencia,
              margem_operacional_viabilidade, margem_operacional_tendencia)::text
   from marts.tendencia_resultado_mensal t, referencia r
   where t.centro_custo_id = '0c000000-0000-4000-8000-0000000000d1' and t.competencia = r.mes_0),
  row(2688.00, 2850.00, 1980.00, 2080.00, 180.00, 180.00, 528.00, 590.00, 0.1964, 0.2070)::text,
  'Norte, mês corrente: os totais da DRE de hoje com a alíquota de 5% (VGV líquido 2850, lucro 590)'
);
select is(
  (select row(obra, vgv_liquido_tendencia, custo_vendas_tendencia, despesas_tendencia, lucro_operacional_tendencia,
              margem_operacional_viabilidade, margem_operacional_tendencia)::text
   from marts.tendencia_resultado_mensal t, referencia r
   where t.centro_custo_id = '0c000000-0000-4000-8000-0000000000d2' and t.competencia = r.mes_0),
  row('Obra Sul', 960.00, 500.00, 0.00, 460.00, 0.4792, 0.4792)::text,
  'Sul, mês corrente: lucro 460 sobre VGV líquido 960 nas duas colunas'
);
select is((select count(*) from marts.tendencia_resultado_mensal), 4::bigint, 'diretor vê as quatro linhas de obra e mês');
select is((select count(*) from app.posicao_dre_mensal), 44::bigint, 'diretor lê as 44 linhas do tenant');

-- Perfil leitura, só com a senha, vinculado à Obra Norte

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000d0e1", "role": "authenticated", "aal": "aal1"}', true);
set local role authenticated;

select results_eq(
  $$select obra, count(*) from marts.tendencia_resultado_mensal group by obra$$,
  $$values ('Obra Norte', 3::bigint)$$,
  'leitura em aal1 vê os três meses da obra liberada e nada da outra'
);
select is((select count(*) from app.posicao_dre_mensal), 33::bigint, 'leitura lê as linhas da obra liberada');
select throws_ok(
  $$select app.registrar_posicao_dre('0e000000-0000-4000-8000-0000000000d1')$$,
  '42501', null, 'leitura não executa a gravação da posição'
);

-- Gerente da Obra Norte

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000d0c1", "role": "authenticated", "aal": "aal1"}', true);
set local role authenticated;

select is(
  (select count(*) from app.posicao_dre_mensal) + (select count(*) from marts.tendencia_resultado_mensal),
  0::bigint,
  'gerente lê zero linhas da posição e da tendência'
);

-- Diretor só com a senha

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000d0d1", "role": "authenticated", "aal": "aal1"}', true);
set local role authenticated;

select is(
  (select count(*) from app.posicao_dre_mensal) + (select count(*) from marts.tendencia_resultado_mensal),
  0::bigint,
  'diretor em aal1 não lê a posição'
);

-- Diretor do tenant vizinho

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000d0d2", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;

select is(
  (select count(*) from app.posicao_dre_mensal) + (select count(*) from marts.tendencia_resultado_mensal),
  0::bigint,
  'diretor de outro tenant não lê a posição'
);

-- Anônimo

reset role;
set local role anon;
select throws_ok('select count(*) from app.posicao_dre_mensal', '42501', null, 'anônimo não lê a tabela');
select throws_ok('select count(*) from marts.tendencia_resultado_mensal', '42501', null, 'anônimo não lê a view');
select throws_ok(
  $$select app.registrar_posicao_dre('0e000000-0000-4000-8000-0000000000d1')$$,
  '42501', null, 'anônimo não executa a gravação da posição'
);

select * from finish();
rollback;
