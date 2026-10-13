-- Realizado contábil das linhas fora do orçamento (migration 0035). Parte do caso da Obra Norte de
-- dre_viabilidade.sql e acrescenta, no mês do mapa, o saldo de três contas mapeadas (terreno 320, projetos 70,
-- despesas comerciais 60), uma conta sem mapa, um saldo de mês anterior e dois registros tortos. O saldo entra
-- pelo raw e pela recarga, como na carga de verdade. A Obra Sul segue sem saldo. Tenant vizinho com saldo
-- próprio na conta de terreno, para provar o isolamento. Cria os próprios dados.
begin;
create extension if not exists pgtap with schema extensions;
select plan(39);

create temporary table referencia on commit drop as
select m::date as mes_0,
  (m - interval '3 months')::date as menos_3,
  (m - interval '1 month')::date as menos_1,
  (m + interval '1 month')::date as mais_1
from date_trunc('month', current_date) as m;
grant select on referencia to authenticated;

insert into app.tenant (id, razao_social) values
  ('0e000000-0000-4000-8000-0000000000b1', 'Construtora Contábil'),
  ('0e000000-0000-4000-8000-0000000000b2', 'Construtora Contábil vizinha');

insert into app.centro_custo (id, tenant_id, id_origem, nome) values
  ('0c000000-0000-4000-8000-0000000000b1', '0e000000-0000-4000-8000-0000000000b1', 991, 'Obra Norte'),
  ('0c000000-0000-4000-8000-0000000000b2', '0e000000-0000-4000-8000-0000000000b1', 992, 'Obra Sul'),
  ('0c000000-0000-4000-8000-0000000000b3', '0e000000-0000-4000-8000-0000000000b2', 991, 'Obra vizinha');

insert into auth.users (id, email) values
  ('0a000000-0000-4000-8000-00000000b0d1', 'diretor.contabil@teste.invalid'),
  ('0a000000-0000-4000-8000-00000000b0a1', 'leitura.contabil@teste.invalid'),
  ('0a000000-0000-4000-8000-00000000b0c1', 'gerente.contabil@teste.invalid'),
  ('0a000000-0000-4000-8000-00000000b0d2', 'diretor.contabil.vizinho@teste.invalid');

insert into app.usuario_tenant (user_id, tenant_id, perfil) values
  ('0a000000-0000-4000-8000-00000000b0d1', '0e000000-0000-4000-8000-0000000000b1', 'diretor'),
  ('0a000000-0000-4000-8000-00000000b0a1', '0e000000-0000-4000-8000-0000000000b1', 'leitura'),
  ('0a000000-0000-4000-8000-00000000b0c1', '0e000000-0000-4000-8000-0000000000b1', 'gerente_obra'),
  ('0a000000-0000-4000-8000-00000000b0d2', '0e000000-0000-4000-8000-0000000000b2', 'diretor');

insert into app.usuario_centro_custo (user_id, tenant_id, centro_custo_id) values
  ('0a000000-0000-4000-8000-00000000b0a1', '0e000000-0000-4000-8000-0000000000b1', '0c000000-0000-4000-8000-0000000000b1'),
  ('0a000000-0000-4000-8000-00000000b0c1', '0e000000-0000-4000-8000-0000000000b1', '0c000000-0000-4000-8000-0000000000b1');

-- Obra Norte, igual ao caso da etapa 2
insert into staging.unidade (tenant_id, centro_custo_id, id_origem, nome, situacao) values
  ('0e000000-0000-4000-8000-0000000000b1', '0c000000-0000-4000-8000-0000000000b1', 1, 'N-1', 'V'),
  ('0e000000-0000-4000-8000-0000000000b1', '0c000000-0000-4000-8000-0000000000b1', 2, 'N-2', 'V'),
  ('0e000000-0000-4000-8000-0000000000b1', '0c000000-0000-4000-8000-0000000000b1', 3, 'N-3', 'D'),
  ('0e000000-0000-4000-8000-0000000000b1', '0c000000-0000-4000-8000-0000000000b1', 4, 'N-4', 'D');
insert into staging.unidade_valor (tenant_id, centro_custo_id, unidade_id_origem, valor_sugerido) values
  ('0e000000-0000-4000-8000-0000000000b1', '0c000000-0000-4000-8000-0000000000b1', 3, 500),
  ('0e000000-0000-4000-8000-0000000000b1', '0c000000-0000-4000-8000-0000000000b1', 4, 500);
insert into staging.contrato_venda (tenant_id, centro_custo_id, id_origem, data_venda, valor, situacao, unidade_id_origem)
select '0e000000-0000-4000-8000-0000000000b1'::uuid, '0c000000-0000-4000-8000-0000000000b1'::uuid, id_origem, data_venda,
  1000, '1', unidade
from referencia, lateral (values (10, menos_3 + 4, 1), (11, menos_1 + 4, 2)) as c (id_origem, data_venda, unidade);
insert into staging.parcela_receber (tenant_id, centro_custo_id, id_origem, contrato_id_origem, vencimento,
                                     valor_original, saldo, tipo_condicao)
select '0e000000-0000-4000-8000-0000000000b1'::uuid, '0c000000-0000-4000-8000-0000000000b1'::uuid, 1, 10, menos_1 + 5,
  600, 0, 'PM'
from referencia;
insert into staging.recebimento (tenant_id, centro_custo_id, contrato_id_origem, parcela_id_origem, sequencia,
                                 data_recebimento, valor)
select '0e000000-0000-4000-8000-0000000000b1'::uuid, '0c000000-0000-4000-8000-0000000000b1'::uuid, 10, 1, 1, menos_1 + 5, 600
from referencia;
insert into staging.titulo_pagar (tenant_id, centro_custo_id, id_origem, vencimento, valor_original, saldo, data_pagamento)
select '0e000000-0000-4000-8000-0000000000b1'::uuid, '0c000000-0000-4000-8000-0000000000b1'::uuid, id_origem, vencimento,
  valor, saldo, data_pagamento
from referencia, lateral (values
  (80, menos_1 + 9, 800, 0, menos_1 + 9),
  (81, mais_1 + 9, 300, 300, null)
) as t (id_origem, vencimento, valor, saldo, data_pagamento);
insert into staging.rateio_titulo (tenant_id, titulo_id_origem, centro_custo_id, valor, fracao) values
  ('0e000000-0000-4000-8000-0000000000b1', 80, '0c000000-0000-4000-8000-0000000000b1', 800, 1),
  ('0e000000-0000-4000-8000-0000000000b1', 81, '0c000000-0000-4000-8000-0000000000b1', 300, 1);
insert into staging.pagamento (tenant_id, centro_custo_id, titulo_id_origem, sequencia, data_pagamento, valor)
select '0e000000-0000-4000-8000-0000000000b1'::uuid, '0c000000-0000-4000-8000-0000000000b1'::uuid, 80, 1, menos_1 + 9, 800
from referencia;
insert into staging.item_orcamento (tenant_id, centro_custo_id, codigo, descricao, valor_total) values
  ('0e000000-0000-4000-8000-0000000000b1', '0c000000-0000-4000-8000-0000000000b1', '01', 'Construção', 1600);
insert into staging.mapa_imobiliario_mensal (tenant_id, centro_custo_id, competencia, unidades, vgv, poc, recebido_acumulado,
                                             custo_orcado, custo_incorrido_acumulado, custo_acumulado, custo_a_incorrer,
                                             receita_acumulada)
select '0e000000-0000-4000-8000-0000000000b1'::uuid, '0c000000-0000-4000-8000-0000000000b1'::uuid, menos_1, 4, 3000, 50, 600,
  1600, 800, 500, 800, 1000
from referencia;
insert into app.aliquota_imposto_obra (tenant_id, centro_custo_id, vigencia_inicio, aliquota)
select '0e000000-0000-4000-8000-0000000000b1'::uuid, '0c000000-0000-4000-8000-0000000000b1'::uuid, menos_3, 0.04
from referencia;
insert into app.estudo_viabilidade (id, tenant_id, centro_custo_id, versao, descricao, data_base, situacao)
select '0d000000-0000-4000-8000-0000000000b1', '0e000000-0000-4000-8000-0000000000b1', '0c000000-0000-4000-8000-0000000000b1',
  1, 'Estudo de lançamento', menos_3, 'vigente'
from referencia;
insert into app.estudo_viabilidade_linha (estudo_id, tenant_id, centro_custo_id, linha, valor)
select '0d000000-0000-4000-8000-0000000000b1', '0e000000-0000-4000-8000-0000000000b1', '0c000000-0000-4000-8000-0000000000b1',
  linha, valor
from (values
  ('vgv_bruto', 2800), ('impostos', 112), ('custo_terreno', 300), ('custo_projetos', 50), ('custo_licenciamento', 30),
  ('custo_construcao', 1500), ('assistencia_tecnica', 40), ('juros_financiamento', 60), ('estoque', 0),
  ('despesas_comerciais', 100), ('despesas_administrativas', 80)
) as l (linha, valor);

-- Obra Sul, sem mapa, sem alíquota e sem saldo contábil
insert into staging.unidade (tenant_id, centro_custo_id, id_origem, nome, situacao) values
  ('0e000000-0000-4000-8000-0000000000b1', '0c000000-0000-4000-8000-0000000000b2', 5, 'S-1', 'V');
insert into staging.contrato_venda (tenant_id, centro_custo_id, id_origem, data_venda, valor, situacao, unidade_id_origem)
select '0e000000-0000-4000-8000-0000000000b1'::uuid, '0c000000-0000-4000-8000-0000000000b2'::uuid, 20, menos_3 + 4, 1000, '1', 5
from referencia;
insert into staging.titulo_pagar (tenant_id, centro_custo_id, id_origem, vencimento, valor_original, saldo, data_pagamento)
select '0e000000-0000-4000-8000-0000000000b1'::uuid, '0c000000-0000-4000-8000-0000000000b2'::uuid, id_origem, vencimento,
  valor, saldo, data_pagamento
from referencia, lateral (values
  (82, menos_1 + 9, 200, 0, menos_1 + 9),
  (83, mais_1 + 9, 100, 100, null)
) as t (id_origem, vencimento, valor, saldo, data_pagamento);
insert into staging.rateio_titulo (tenant_id, titulo_id_origem, centro_custo_id, valor, fracao) values
  ('0e000000-0000-4000-8000-0000000000b1', 82, '0c000000-0000-4000-8000-0000000000b2', 200, 1),
  ('0e000000-0000-4000-8000-0000000000b1', 83, '0c000000-0000-4000-8000-0000000000b2', 100, 1);
insert into staging.pagamento (tenant_id, centro_custo_id, titulo_id_origem, sequencia, data_pagamento, valor)
select '0e000000-0000-4000-8000-0000000000b1'::uuid, '0c000000-0000-4000-8000-0000000000b2'::uuid, 82, 1, menos_1 + 9, 200
from referencia;
insert into staging.item_orcamento (tenant_id, centro_custo_id, codigo, descricao, valor_total) values
  ('0e000000-0000-4000-8000-0000000000b1', '0c000000-0000-4000-8000-0000000000b2', '01', 'Construção', 500);
insert into app.estudo_viabilidade (id, tenant_id, centro_custo_id, versao, descricao, data_base, situacao)
select '0d000000-0000-4000-8000-0000000000b2', '0e000000-0000-4000-8000-0000000000b1', '0c000000-0000-4000-8000-0000000000b2',
  1, 'Estudo de lançamento', menos_3, 'vigente'
from referencia;
insert into app.estudo_viabilidade_linha (estudo_id, tenant_id, centro_custo_id, linha, valor)
select '0d000000-0000-4000-8000-0000000000b2', '0e000000-0000-4000-8000-0000000000b1', '0c000000-0000-4000-8000-0000000000b2',
  linha, valor
from (values
  ('vgv_bruto', 1000), ('impostos', 40), ('custo_terreno', 0), ('custo_projetos', 0), ('custo_licenciamento', 0),
  ('custo_construcao', 500), ('assistencia_tecnica', 0), ('juros_financiamento', 0), ('estoque', 0),
  ('despesas_comerciais', 0), ('despesas_administrativas', 0)
) as l (linha, valor);

-- Mapa de contas dos dois tenants
insert into app.conta_linha_resultado (tenant_id, conta, linha) values
  ('0e000000-0000-4000-8000-0000000000b1', '1.1.05.01', 'custo_terreno'),
  ('0e000000-0000-4000-8000-0000000000b1', '1.1.05.02', 'custo_projetos'),
  ('0e000000-0000-4000-8000-0000000000b1', '4.1.01.01', 'despesas_comerciais'),
  ('0e000000-0000-4000-8000-0000000000b2', '1.1.05.01', 'custo_terreno');

-- Saldos no raw, no formato do endpoint. A ordem dos inserts importa: a versão de 999 da conta 4.1.01.01
-- vem antes da de 60 e precisa perder para ela.
insert into raw.registro (tenant_id, endpoint, payload, hash_registro)
select '0e000000-0000-4000-8000-0000000000b1', 'accountancy/accountCostCenterBalance',
  jsonb_build_object('costCenterId', 991, 'accountId', conta, 'monthYear', to_char(mes, 'MM/YYYY'),
    'debitBalance', debito, 'creditBalance', credito, 'balanceCarriedForward', saldo, 'balanceCarriedForwardType', tipo),
  'saldo-' || ordem
from referencia, lateral (values
  (1, '1.1.05.01', menos_3, 100, 0, 100, 'D'),
  (2, '4.1.01.01', menos_1, 999, 0, 999, 'D'),
  (3, '1.1.05.01', menos_1, 350, 30, 320, 'D'),
  (4, '1.1.05.02', menos_1, 70, 0, 70, 'D'),
  (5, '4.1.01.01', menos_1, 60, 0, 60, 'D'),
  (6, '2.1.01.01', menos_1, 0, 500, 500, 'C'),
  (7, '9.9.99.99', menos_1, 10, 0, 10, 'X')
) as s (ordem, conta, mes, debito, credito, saldo, tipo)
order by ordem;
insert into raw.registro (tenant_id, endpoint, payload, hash_registro) values
  ('0e000000-0000-4000-8000-0000000000b1', 'accountancy/accountCostCenterBalance',
   '{"costCenterId": 991, "accountId": "1.1.05.01", "monthYear": "13/2026", "debitBalance": 1, "creditBalance": 0,
     "balanceCarriedForward": 1, "balanceCarriedForwardType": "D"}', 'saldo-torto'),
  ('0e000000-0000-4000-8000-0000000000b1', 'accountancy/accountCostCenterBalance',
   '{"costCenterId": 777, "accountId": "1.1.05.01", "monthYear": "01/2026", "debitBalance": 1, "creditBalance": 0,
     "balanceCarriedForward": 1, "balanceCarriedForwardType": "D"}', 'saldo-obra-desconhecida');
insert into raw.registro (tenant_id, endpoint, payload, hash_registro)
select '0e000000-0000-4000-8000-0000000000b2', 'accountancy/accountCostCenterBalance',
  jsonb_build_object('costCenterId', 991, 'accountId', '1.1.05.01', 'monthYear', to_char(menos_1, 'MM/YYYY'),
    'debitBalance', 5000, 'creditBalance', 0, 'balanceCarriedForward', 5000, 'balanceCarriedForwardType', 'D'),
  'saldo-vizinho'
from referencia;

-- Estrutura e permissões

select ok(
  (select bool_and(c.relrowsecurity and c.relforcerowsecurity) from pg_class c
   where c.oid in ('staging.saldo_contabil_mensal'::regclass, 'app.conta_linha_resultado'::regclass)),
  'RLS ligado e forçado nas duas tabelas'
);
select is(
  (select count(*) from pg_policies
   where (schemaname, tablename) in (('staging', 'saldo_contabil_mensal'), ('app', 'conta_linha_resultado'))
     and permissive = 'PERMISSIVE'),
  2::bigint,
  'uma política permissiva por tabela'
);
select is(
  (select count(*) from pg_policies
   where (schemaname, tablename) in (('staging', 'saldo_contabil_mensal'), ('app', 'conta_linha_resultado'))
     and permissive = 'PERMISSIVE' and cmd <> 'SELECT'),
  0::bigint,
  'nenhuma política de insert, update ou delete'
);
select is(
  (select count(*) from pg_policy p
   where p.polrelid in ('staging.saldo_contabil_mensal'::regclass, 'app.conta_linha_resultado'::regclass)
     and p.polname = 'segundo_fator' and not p.polpermissive and p.polcmd = '*'
     and p.polroles = array['authenticated'::regrole::oid]),
  2::bigint,
  'as duas tabelas têm a restritiva do segundo fator'
);
select ok(
  not has_table_privilege('authenticated', 'staging.saldo_contabil_mensal', 'insert, update, delete')
  and not has_table_privilege('authenticated', 'app.conta_linha_resultado', 'insert, update, delete')
  and not has_table_privilege('anon', 'staging.saldo_contabil_mensal', 'select')
  and not has_table_privilege('anon', 'app.conta_linha_resultado', 'select'),
  'usuário logado não escreve nas tabelas pela API e anônimo não lê'
);
select ok(
  not has_function_privilege('anon', 'staging.recarregar_saldo_contabil(uuid)', 'execute')
  and not has_function_privilege('public', 'staging.recarregar_saldo_contabil(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'staging.recarregar_saldo_contabil(uuid)', 'execute'),
  'ninguém além do dono executa a recarga'
);
select ok(
  (select prosecdef and proconfig @> array['search_path=""'] from pg_proc
   where oid = 'staging.recarregar_saldo_contabil(uuid)'::regprocedure),
  'a recarga é security definer com search_path vazio'
);
select throws_ok(
  $$insert into app.conta_linha_resultado (tenant_id, conta, linha)
    values ('0e000000-0000-4000-8000-0000000000b1', '1.1.06.01', 'custo_construcao')$$,
  '23514', null, 'conta mapeada para a construção é recusada pelo check'
);
select throws_ok(
  $$insert into app.conta_linha_resultado (tenant_id, conta, linha)
    values ('0e000000-0000-4000-8000-0000000000b1', '1.1.06.02', 'vgv_bruto')$$,
  '23514', null, 'conta mapeada para o VGV é recusada pelo check'
);

-- Recarga como dono do banco

select lives_ok(
  $$select staging.recarregar_saldo_contabil('0e000000-0000-4000-8000-0000000000b1')$$,
  'recarga do tenant roda'
);
select lives_ok(
  $$select staging.recarregar_saldo_contabil('0e000000-0000-4000-8000-0000000000b2')$$,
  'recarga do vizinho roda'
);
select results_eq(
  $$select conta, competencia, debito, credito, saldo_final from staging.saldo_contabil_mensal
    where tenant_id = '0e000000-0000-4000-8000-0000000000b1' order by competencia, conta$$,
  $$select conta, mes, debito, credito, saldo from referencia, lateral (values
      ('1.1.05.01', menos_3, 100::numeric, 0::numeric, 100::numeric),
      ('1.1.05.01', menos_1, 350::numeric, 30::numeric, 320::numeric),
      ('1.1.05.02', menos_1, 70::numeric, 0::numeric, 70::numeric),
      ('2.1.01.01', menos_1, 0::numeric, 500::numeric, -500::numeric),
      ('4.1.01.01', menos_1, 60::numeric, 0::numeric, 60::numeric)
    ) as s (conta, mes, debito, credito, saldo)$$,
  'cinco saldos: versão mais recente vale, credor fica negativo, mês torto, tipo torto e obra desconhecida saem'
);
select is(
  (select count(*) from staging.saldo_contabil_mensal where tenant_id = '0e000000-0000-4000-8000-0000000000b2'),
  1::bigint,
  'o saldo do vizinho fica na obra do vizinho'
);
select lives_ok(
  $$select staging.recarregar_saldo_contabil('0e000000-0000-4000-8000-0000000000b1')$$,
  'recarga rodada de novo'
);
select is(
  (select count(*) from staging.saldo_contabil_mensal where tenant_id = '0e000000-0000-4000-8000-0000000000b1'),
  5::bigint,
  'a segunda recarga deixa a mesma contagem'
);

-- Diretor com segundo fator

select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000b0d1", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;

select results_eq(
  $$select viabilidade, apropriado, a_contratar, tendencia, desvio, desvio_pct, fonte_realizado from marts.dre_viabilidade
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000b1' and linha = 'custo_terreno'$$,
  $$values (300::numeric, 320::numeric, 0::numeric, 320::numeric, 20::numeric, 0.0667::numeric, 'contabil')$$,
  'Norte, custo_terreno: saldo contábil de 320 passa do estudo e não deixa a contratar negativo'
);
select results_eq(
  $$select viabilidade, apropriado, a_contratar, tendencia, desvio, desvio_pct, fonte_realizado from marts.dre_viabilidade
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000b1' and linha = 'custo_projetos'$$,
  $$values (50::numeric, 70::numeric, 0::numeric, 70::numeric, 20::numeric, 0.4::numeric, 'contabil')$$,
  'Norte, custo_projetos: 70 apropriado, nada a contratar'
);
select results_eq(
  $$select viabilidade, apropriado, a_contratar, tendencia, desvio, desvio_pct, fonte_realizado from marts.dre_viabilidade
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000b1' and linha = 'despesas_comerciais'$$,
  $$values (100::numeric, 60::numeric, 40::numeric, 100::numeric, 0::numeric, 0::numeric, 'contabil')$$,
  'Norte, despesas_comerciais: 60 apropriado e 40 a contratar, tendência igual ao estudo'
);
select results_eq(
  $$select linha, apropriado, a_contratar, tendencia, fonte_realizado from marts.dre_viabilidade
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000b1'
      and linha in ('custo_licenciamento', 'assistencia_tecnica', 'juros_financiamento', 'estoque', 'despesas_administrativas')
    order by ordem$$,
  $$values ('custo_licenciamento', 0::numeric, 30::numeric, 30::numeric, 'sem_fonte'),
           ('assistencia_tecnica', 0::numeric, 40::numeric, 40::numeric, 'sem_fonte'),
           ('juros_financiamento', 0::numeric, 60::numeric, 60::numeric, 'sem_fonte'),
           ('estoque', 0::numeric, 0::numeric, 0::numeric, 'sem_fonte'),
           ('despesas_administrativas', 0::numeric, 80::numeric, 80::numeric, 'sem_fonte')$$,
  'linhas sem conta mapeada seguem sem fonte e com tendência igual ao estudo'
);
select is(
  (select sum(apropriado) from marts.dre_viabilidade
   where centro_custo_id = '0c000000-0000-4000-8000-0000000000b1' and linha_de_total = false
     and linha not in ('vgv_bruto', 'impostos', 'custo_construcao')),
  450::numeric,
  'conta sem mapa (saldo credor de 500) e saldo de mês anterior não entram em linha nenhuma'
);
select results_eq(
  $$select viabilidade, apropriado, a_apropriar, a_contratar, tendencia, desvio, desvio_pct from marts.dre_viabilidade
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000b1' and linha = 'custo_construcao'$$,
  $$values (1500::numeric, 500::numeric, 600::numeric, 500::numeric, 1600::numeric, 100::numeric, 0.0667::numeric)$$,
  'Norte, custo_construcao: não muda com o saldo contábil'
);
select results_eq(
  $$select viabilidade, apropriado, a_apropriar, a_contratar, tendencia, desvio, desvio_pct from marts.dre_viabilidade
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000b1' and linha = 'custo_empreendimento'$$,
  $$values (1880::numeric, 890::numeric, 600::numeric, 530::numeric, 2020::numeric, 140::numeric, 0.0745::numeric)$$,
  'Norte, custo_empreendimento: 320 + 70 + 0 + 500 apropriado, a apropriar segue 600, tendência 2020'
);
select results_eq(
  $$select viabilidade, apropriado, a_apropriar, a_contratar, tendencia, desvio, desvio_pct from marts.dre_viabilidade
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000b1' and linha = 'custo_vendas'$$,
  $$values (1980::numeric, 890::numeric, 600::numeric, 630::numeric, 2120::numeric, 140::numeric, 0.0707::numeric)$$,
  'Norte, custo_vendas: tendência 2120'
);
select results_eq(
  $$select viabilidade, apropriado, a_apropriar, a_contratar, tendencia, desvio, desvio_pct from marts.dre_viabilidade
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000b1' and linha = 'resultado_bruto'$$,
  $$values (708::numeric, 70::numeric, 360::numeric, 330::numeric, 760::numeric, 52::numeric, 0.0734::numeric)$$,
  'Norte, resultado_bruto: 2880 - 2120 = 760'
);
select results_eq(
  $$select viabilidade, apropriado, a_apropriar, a_contratar, tendencia, desvio, desvio_pct from marts.dre_viabilidade
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000b1' and linha = 'despesas'$$,
  $$values (180::numeric, 60::numeric, 0::numeric, 120::numeric, 180::numeric, 0::numeric, 0::numeric)$$,
  'Norte, despesas: 60 apropriado e 120 a contratar'
);
select results_eq(
  $$select viabilidade, apropriado, a_apropriar, a_contratar, tendencia, desvio, desvio_pct from marts.dre_viabilidade
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000b1' and linha = 'lucro_operacional'$$,
  $$values (528::numeric, 10::numeric, 360::numeric, 210::numeric, 580::numeric, 52::numeric, 0.0985::numeric)$$,
  'Norte, lucro_operacional: 760 - 180 = 580'
);
select results_eq(
  $$select linha, desvio_favoravel from marts.dre_viabilidade
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000b1'
      and linha in ('custo_terreno', 'despesas_comerciais', 'lucro_operacional') order by ordem$$,
  $$values ('custo_terreno', false), ('despesas_comerciais', null::boolean), ('lucro_operacional', true)$$,
  'desvio desfavorável no terreno, nulo nas despesas comerciais, favorável no lucro'
);
select results_eq(
  $$select custo_apropriado, lucro_operacional_tendencia, margem_operacional_tendencia from marts.dre_resumo_obra
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000b1'$$,
  $$values (890::numeric, 580::numeric, 0.2014::numeric)$$,
  'o resumo da obra acompanha o custo apropriado e a tendência novos'
);
select results_eq(
  $$select linha, apropriado, a_contratar, tendencia, fonte_realizado from marts.dre_viabilidade
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000b2'
      and linha in ('custo_terreno', 'lucro_operacional') order by ordem$$,
  $$values ('custo_terreno', 0::numeric, 0::numeric, 0::numeric, 'sem_fonte'),
           ('lucro_operacional', 200::numeric, -240::numeric, 460::numeric, 'total')$$,
  'Sul, sem saldo contábil: terreno sem fonte e lucro operacional de 460 como antes'
);
select is(
  (select count(*) from staging.saldo_contabil_mensal) + (select count(*) from app.conta_linha_resultado),
  8::bigint,
  'diretor lê os cinco saldos e as três contas do tenant, nada do vizinho'
);

create temporary table dre_diretor on commit drop as
select linha, apropriado, a_apropriar, a_contratar, tendencia, fonte_realizado
from marts.dre_viabilidade
where centro_custo_id = '0c000000-0000-4000-8000-0000000000b1';

-- Perfil leitura, só com a senha

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000b0a1", "role": "authenticated", "aal": "aal1"}', true);
set local role authenticated;

select set_eq(
  $$select linha, apropriado, a_apropriar, a_contratar, tendencia, fonte_realizado from marts.dre_viabilidade
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000b1'$$,
  $$select linha, apropriado, a_apropriar, a_contratar, tendencia, fonte_realizado from dre_diretor$$,
  'leitura vê na DRE os mesmos números do diretor, com o apropriado contábil'
);
select is(
  (select count(*) from staging.saldo_contabil_mensal) + (select count(*) from app.conta_linha_resultado),
  8::bigint,
  'leitura lê o saldo da obra liberada e o mapa do tenant'
);
select throws_ok(
  $$select staging.recarregar_saldo_contabil('0e000000-0000-4000-8000-0000000000b1')$$,
  '42501', null, 'leitura não executa a recarga'
);

-- Gerente da Obra Norte

reset role;
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-00000000b0c1", "role": "authenticated"}', true);
set local role authenticated;

select is((select count(*) from staging.saldo_contabil_mensal), 0::bigint, 'gerente lê zero linhas do saldo contábil');
select is((select count(*) from app.conta_linha_resultado), 0::bigint, 'gerente lê zero linhas do mapa de contas');
select is((select count(*) from marts.dre_viabilidade), 0::bigint, 'gerente continua sem DRE');

-- Diretor só com a senha

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000b0d1", "role": "authenticated", "aal": "aal1"}', true);
set local role authenticated;

select is(
  (select count(*) from staging.saldo_contabil_mensal) + (select count(*) from app.conta_linha_resultado),
  0::bigint,
  'diretor em aal1 não lê saldo nem mapa de contas'
);

-- Diretor do tenant vizinho

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000b0d2", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;

select results_eq(
  $$select saldo_final from staging.saldo_contabil_mensal$$,
  $$values (5000::numeric)$$,
  'diretor vizinho lê só o saldo da própria obra'
);
select is((select count(*) from app.conta_linha_resultado), 1::bigint, 'diretor vizinho lê só o próprio mapa');

select * from finish();
rollback;
