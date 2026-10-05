-- Gestão de imposto (migration 0034) com o caso feito à mão da etapa 11 do plano APO. Cria os próprios dados.
--   Obra Norte: duas unidades vendidas por 1000 e duas em estoque por 500; mapa do ERP do mês passado com receita
--   apropriada de 1000; parcela direta de 600 recebida; alíquota de 4% desde três meses atrás, com uma de 2% mais
--   antiga e uma de 10% que só vale no mês que vem; estudo com impostos de 112.
--   Obra Sul: estudo, sem alíquota. Tenant vizinho com uma obra com estudo e alíquota, para provar o isolamento.
begin;
create extension if not exists pgtap with schema extensions;
select plan(15);

create temporary table referencia on commit drop as
select m::date as mes_0,
  (m - interval '6 months')::date as menos_6,
  (m - interval '3 months')::date as menos_3,
  (m - interval '1 month')::date as menos_1,
  (m + interval '1 month')::date as mais_1
from date_trunc('month', current_date) as m;
grant select on referencia to authenticated;

insert into app.tenant (id, razao_social) values
  ('0e000000-0000-4000-8000-0000000000f1', 'Construtora imposto'),
  ('0e000000-0000-4000-8000-0000000000f2', 'Construtora imposto vizinha');

insert into app.centro_custo (id, tenant_id, id_origem, nome) values
  ('0c000000-0000-4000-8000-0000000000f1', '0e000000-0000-4000-8000-0000000000f1', 971, 'Obra Norte'),
  ('0c000000-0000-4000-8000-0000000000f2', '0e000000-0000-4000-8000-0000000000f1', 972, 'Obra Sul'),
  ('0c000000-0000-4000-8000-0000000000f3', '0e000000-0000-4000-8000-0000000000f2', 971, 'Obra vizinha');

insert into auth.users (id, email) values
  ('0a000000-0000-4000-8000-00000000f0d1', 'diretor.imposto@teste.invalid'),
  ('0a000000-0000-4000-8000-00000000f0a1', 'leitura.imposto@teste.invalid'),
  ('0a000000-0000-4000-8000-00000000f0c1', 'gerente.imposto@teste.invalid'),
  ('0a000000-0000-4000-8000-00000000f0d2', 'diretor.imposto.vizinho@teste.invalid');

insert into app.usuario_tenant (user_id, tenant_id, perfil) values
  ('0a000000-0000-4000-8000-00000000f0d1', '0e000000-0000-4000-8000-0000000000f1', 'diretor'),
  ('0a000000-0000-4000-8000-00000000f0a1', '0e000000-0000-4000-8000-0000000000f1', 'leitura'),
  ('0a000000-0000-4000-8000-00000000f0c1', '0e000000-0000-4000-8000-0000000000f1', 'gerente_obra'),
  ('0a000000-0000-4000-8000-00000000f0d2', '0e000000-0000-4000-8000-0000000000f2', 'diretor');

insert into app.usuario_centro_custo (user_id, tenant_id, centro_custo_id) values
  ('0a000000-0000-4000-8000-00000000f0a1', '0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f1'),
  ('0a000000-0000-4000-8000-00000000f0c1', '0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f1');

-- Obra Norte
insert into staging.unidade (tenant_id, centro_custo_id, id_origem, nome, situacao) values
  ('0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f1', 1, 'N-1', 'V'),
  ('0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f1', 2, 'N-2', 'V'),
  ('0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f1', 3, 'N-3', 'D'),
  ('0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f1', 4, 'N-4', 'D');
insert into staging.unidade_valor (tenant_id, centro_custo_id, unidade_id_origem, valor_sugerido) values
  ('0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f1', 3, 500),
  ('0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f1', 4, 500);
insert into staging.contrato_venda (tenant_id, centro_custo_id, id_origem, data_venda, valor, situacao, unidade_id_origem)
select '0e000000-0000-4000-8000-0000000000f1'::uuid, '0c000000-0000-4000-8000-0000000000f1'::uuid, id_origem, data_venda,
  1000, '1', unidade
from referencia, lateral (values (10, menos_3 + 4, 1), (11, menos_1 + 4, 2)) as c (id_origem, data_venda, unidade);
insert into staging.parcela_receber (tenant_id, centro_custo_id, id_origem, contrato_id_origem, vencimento,
                                     valor_original, saldo, tipo_condicao)
select '0e000000-0000-4000-8000-0000000000f1'::uuid, '0c000000-0000-4000-8000-0000000000f1'::uuid, 1, 10, menos_1 + 5,
  600, 0, 'PM'
from referencia;
insert into staging.recebimento (tenant_id, centro_custo_id, contrato_id_origem, parcela_id_origem, sequencia,
                                 data_recebimento, valor)
select '0e000000-0000-4000-8000-0000000000f1'::uuid, '0c000000-0000-4000-8000-0000000000f1'::uuid, 10, 1, 1, menos_1 + 5, 600
from referencia;
insert into staging.item_orcamento (tenant_id, centro_custo_id, codigo, descricao, valor_total) values
  ('0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f1', '01', 'Construção', 1600);
insert into staging.mapa_imobiliario_mensal (tenant_id, centro_custo_id, competencia, unidades, vgv, poc, recebido_acumulado,
                                             custo_orcado, custo_incorrido_acumulado, custo_acumulado, custo_a_incorrer,
                                             receita_acumulada)
select '0e000000-0000-4000-8000-0000000000f1'::uuid, '0c000000-0000-4000-8000-0000000000f1'::uuid, menos_1, 4, 3000, 50, 600,
  1600, 800, 500, 800, 1000
from referencia;
insert into app.aliquota_imposto_obra (tenant_id, centro_custo_id, vigencia_inicio, aliquota)
select '0e000000-0000-4000-8000-0000000000f1'::uuid, '0c000000-0000-4000-8000-0000000000f1'::uuid, vigencia, aliquota
from referencia, lateral (values (menos_6, 0.02), (menos_3, 0.04), (mais_1, 0.10)) as a (vigencia, aliquota);
insert into app.estudo_viabilidade (id, tenant_id, centro_custo_id, versao, descricao, data_base, situacao)
select '0d000000-0000-4000-8000-0000000000f1', '0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f1',
  1, 'Estudo de lançamento', menos_3, 'vigente'
from referencia;
insert into app.estudo_viabilidade_linha (estudo_id, tenant_id, centro_custo_id, linha, valor)
select '0d000000-0000-4000-8000-0000000000f1', '0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f1',
  linha, valor
from (values
  ('vgv_bruto', 2800), ('impostos', 112), ('custo_terreno', 300), ('custo_projetos', 50), ('custo_licenciamento', 30),
  ('custo_construcao', 1500), ('assistencia_tecnica', 40), ('juros_financiamento', 60), ('estoque', 0),
  ('despesas_comerciais', 100), ('despesas_administrativas', 80)
) as l (linha, valor);

-- Obra Sul, com estudo e sem alíquota
insert into staging.unidade (tenant_id, centro_custo_id, id_origem, nome, situacao) values
  ('0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f2', 5, 'S-1', 'V');
insert into staging.contrato_venda (tenant_id, centro_custo_id, id_origem, data_venda, valor, situacao, unidade_id_origem)
select '0e000000-0000-4000-8000-0000000000f1'::uuid, '0c000000-0000-4000-8000-0000000000f2'::uuid, 20, menos_3 + 4, 1000, '1', 5
from referencia;
insert into app.estudo_viabilidade (id, tenant_id, centro_custo_id, versao, descricao, data_base, situacao)
select '0d000000-0000-4000-8000-0000000000f2', '0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f2',
  1, 'Estudo de lançamento', menos_3, 'vigente'
from referencia;
insert into app.estudo_viabilidade_linha (estudo_id, tenant_id, centro_custo_id, linha, valor) values
  ('0d000000-0000-4000-8000-0000000000f2', '0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f2',
   'vgv_bruto', 1000),
  ('0d000000-0000-4000-8000-0000000000f2', '0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f2',
   'impostos', 40);

-- Obra vizinha, com estudo e alíquota, sem movimento
insert into app.aliquota_imposto_obra (tenant_id, centro_custo_id, vigencia_inicio, aliquota)
select '0e000000-0000-4000-8000-0000000000f2'::uuid, '0c000000-0000-4000-8000-0000000000f3'::uuid, menos_3, 0.05
from referencia;
insert into app.estudo_viabilidade (id, tenant_id, centro_custo_id, versao, descricao, data_base, situacao)
select '0d000000-0000-4000-8000-0000000000f3', '0e000000-0000-4000-8000-0000000000f2', '0c000000-0000-4000-8000-0000000000f3',
  1, 'Estudo de lançamento', menos_3, 'vigente'
from referencia;
insert into app.estudo_viabilidade_linha (estudo_id, tenant_id, centro_custo_id, linha, valor) values
  ('0d000000-0000-4000-8000-0000000000f3', '0e000000-0000-4000-8000-0000000000f2', '0c000000-0000-4000-8000-0000000000f3',
   'vgv_bruto', 500);

-- Estrutura e permissões

select ok(
  (select c.reloptions @> array['security_invoker=true'] from pg_class c where c.oid = 'marts.imposto_obra'::regclass),
  'a view roda como quem consulta'
);
select ok(
  has_table_privilege('authenticated', 'marts.imposto_obra', 'select')
  and not has_table_privilege('anon', 'marts.imposto_obra', 'select')
  and not has_table_privilege('authenticated', 'marts.imposto_obra', 'insert, update, delete'),
  'usuário logado só lê a view e anônimo não lê'
);

-- Diretor com segundo fator

select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000f0d1", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;

select results_eq(
  $$select aliquota, vgv_total, imposto_receita_apropriada, imposto_recebimento, imposto_diferido, imposto_vgv_estoque,
      imposto_receita_a_apropriar, imposto_vgv_total, imposto_a_realizar
    from marts.imposto_obra where centro_custo_id = '0c000000-0000-4000-8000-0000000000f1'$$,
  $$values (0.04::numeric, 3000::numeric, 40::numeric, 24::numeric, -16::numeric, 40::numeric, 40::numeric, 120::numeric,
            80::numeric)$$,
  'Norte: os nove cartões com a alíquota de 4%'
);
select results_eq(
  $$select receita_apropriada, receita_a_apropriar, vgv_estoque, recebido_acumulado, imposto_viabilidade
    from marts.imposto_obra where centro_custo_id = '0c000000-0000-4000-8000-0000000000f1'$$,
  $$values (1000::numeric, 1000::numeric, 1000::numeric, 600::numeric, 112::numeric)$$,
  'Norte: bases do VGV e do recebido, e o imposto do estudo'
);
select is(
  (select aliquota_vigencia_inicio from marts.imposto_obra where centro_custo_id = '0c000000-0000-4000-8000-0000000000f1'),
  (select menos_3 from referencia),
  'Norte: vale a alíquota de maior vigência até hoje, nem a mais antiga nem a futura'
);
select ok(
  (select aliquota_informada_em is not null from marts.imposto_obra
   where centro_custo_id = '0c000000-0000-4000-8000-0000000000f1'),
  'Norte: a view diz quando a alíquota foi informada'
);
select is(
  (select imposto_vgv_total from marts.imposto_obra where centro_custo_id = '0c000000-0000-4000-8000-0000000000f1'),
  (select tendencia from marts.dre_viabilidade
   where centro_custo_id = '0c000000-0000-4000-8000-0000000000f1' and linha = 'impostos'),
  'Norte: imposto sobre o VGV total igual à tendência dos impostos na DRE'
);
select results_eq(
  $$select centro_custo_id from marts.imposto_obra$$,
  $$values ('0c000000-0000-4000-8000-0000000000f1'::uuid)$$,
  'Obra Sul, sem alíquota, não aparece; obra do vizinho também não'
);

-- Perfil leitura, sem segundo fator

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000f0a1", "role": "authenticated", "aal": "aal1"}', true);
set local role authenticated;

select results_eq(
  $$select centro_custo_id, imposto_vgv_total, imposto_a_realizar from marts.imposto_obra$$,
  $$values ('0c000000-0000-4000-8000-0000000000f1'::uuid, 120::numeric, 80::numeric)$$,
  'leitura em aal1 lê o imposto da obra liberada'
);
select is(
  (select count(*) from staging.mapa_imobiliario_mensal),
  1::bigint,
  'leitura lê o mapa da obra liberada, que a DRE usa para o apropriado'
);
select is(
  (select count(*) from marts.conferencia_origem),
  0::bigint,
  'leitura não lê a conferência contra o ERP, que fica com diretor e financeiro'
);

-- Gerente da Obra Norte

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000f0c1", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;

select is((select count(*) from marts.imposto_obra), 0::bigint, 'gerente lê zero linhas, nem da própria obra');

-- Diretor só com a senha

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000f0d1", "role": "authenticated", "aal": "aal1"}', true);
set local role authenticated;

select is((select count(*) from marts.imposto_obra), 0::bigint, 'diretor em aal1 lê zero linhas');

-- Diretor do tenant vizinho

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000f0d2", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;

select results_eq(
  $$select centro_custo_id, aliquota, imposto_vgv_total from marts.imposto_obra$$,
  $$values ('0c000000-0000-4000-8000-0000000000f3'::uuid, 0.05::numeric, 0::numeric)$$,
  'diretor de outro tenant vê só a própria obra'
);

-- Dono do banco, sem RLS

reset role;
select is(
  (select count(*) from marts.imposto_obra
   where tenant_id = '0e000000-0000-4000-8000-0000000000f1'),
  1::bigint,
  'sem filtro de perfil no corpo: o dono do banco lê a obra com alíquota filtrando o tenant'
);

select * from finish();
rollback;
