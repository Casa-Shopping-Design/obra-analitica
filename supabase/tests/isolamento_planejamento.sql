-- Caso C12 de docs/financeiro/casos_teste.md na parte das migrations 0012 e 0013: gerente e perfil leitura
-- não gravam nem veem outra obra, outro tenant fica invisível, a simulação de obra não permitida não devolve
-- número, versão registrada não muda e as regras de RLS e de funções valem para todas as tabelas novas.
begin;
create extension if not exists pgtap with schema extensions;
select plan(51);

insert into app.tenant (id, razao_social) values
  ('7e000000-0000-4000-8000-00000000000a', 'Construtora Teste Financeiro A'),
  ('7e000000-0000-4000-8000-00000000000b', 'Construtora Teste Financeiro B');

insert into app.centro_custo (id, tenant_id, id_origem, nome, tipo) values
  ('7c000000-0000-4000-8000-0000000000a1', '7e000000-0000-4000-8000-00000000000a', 9001, 'Obra Teste 1', 'obra'),
  ('7c000000-0000-4000-8000-0000000000a2', '7e000000-0000-4000-8000-00000000000a', 9002, 'Obra Teste 2', 'obra'),
  ('7c000000-0000-4000-8000-0000000000ae', '7e000000-0000-4000-8000-00000000000a', null, 'Despesas sem obra', 'empresa'),
  ('7c000000-0000-4000-8000-0000000000b1', '7e000000-0000-4000-8000-00000000000b', 9001, 'Obra Teste B1', 'obra'),
  ('7c000000-0000-4000-8000-0000000000be', '7e000000-0000-4000-8000-00000000000b', null, 'Despesas sem obra', 'empresa');

insert into auth.users (id, email) values
  ('7a000000-0000-4000-8000-00000000d00a', 'diretor.financeiro@teste.invalid'),
  ('7a000000-0000-4000-8000-00000000f00a', 'financeiro.financeiro@teste.invalid'),
  ('7a000000-0000-4000-8000-00000000c00a', 'gerente.financeiro@teste.invalid'),
  ('7a000000-0000-4000-8000-00000000e00a', 'leitura.financeiro@teste.invalid'),
  ('7a000000-0000-4000-8000-00000000d00b', 'diretorb.financeiro@teste.invalid');

insert into app.usuario_tenant (user_id, tenant_id, perfil) values
  ('7a000000-0000-4000-8000-00000000d00a', '7e000000-0000-4000-8000-00000000000a', 'diretor'),
  ('7a000000-0000-4000-8000-00000000f00a', '7e000000-0000-4000-8000-00000000000a', 'financeiro'),
  ('7a000000-0000-4000-8000-00000000c00a', '7e000000-0000-4000-8000-00000000000a', 'gerente_obra'),
  ('7a000000-0000-4000-8000-00000000e00a', '7e000000-0000-4000-8000-00000000000a', 'leitura'),
  ('7a000000-0000-4000-8000-00000000d00b', '7e000000-0000-4000-8000-00000000000b', 'diretor');

insert into app.usuario_centro_custo (user_id, tenant_id, centro_custo_id) values
  ('7a000000-0000-4000-8000-00000000c00a', '7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1'),
  ('7a000000-0000-4000-8000-00000000e00a', '7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1');

-- Gravação no nível staging como o carregador, com as regras de casos_teste.md ("Como ler").
create function pg_temp.contrato(p_centro uuid, p_id integer, p_valor numeric, p_data_venda date,
                                 p_valor_financiado numeric default null, p_banco text default null,
                                 p_data_repasse date default null, p_unidade integer default null) returns void
language sql as $$
  insert into staging.contrato_venda (tenant_id, centro_custo_id, id_origem, numero, data_venda, valor, situacao,
    banco_repasse, data_repasse, unidade_id_origem, valor_financiado)
  select cc.tenant_id, cc.id, p_id, 'C-' || p_id, p_data_venda, p_valor, '1', p_banco, p_data_repasse, p_unidade,
         p_valor_financiado
  from app.centro_custo cc where cc.id = p_centro;
  insert into staging.contrato_unidade (tenant_id, centro_custo_id, contrato_id_origem, sequencia, unidade_id_origem, principal)
  select cc.tenant_id, cc.id, p_id, 1, p_unidade, true
  from app.centro_custo cc where cc.id = p_centro and p_unidade is not null;
$$;

create function pg_temp.parcela(p_centro uuid, p_contrato integer, p_parcela integer, p_condicao text,
                                p_vencimento date, p_valor numeric, p_saldo numeric,
                                p_recebimentos jsonb default '[]') returns void
language sql as $$
  insert into staging.parcela_receber (tenant_id, centro_custo_id, id_origem, contrato_id_origem, vencimento,
    valor_original, saldo, saldo_corrigido, tipo_condicao, valor_recebido, data_recebimento)
  select cc.tenant_id, cc.id, p_parcela, p_contrato, p_vencimento, p_valor, p_saldo, p_saldo, p_condicao,
         coalesce((select sum((r ->> 'valor')::numeric) from jsonb_array_elements(p_recebimentos) r), 0),
         (select max((r ->> 'data')::date) from jsonb_array_elements(p_recebimentos) r)
  from app.centro_custo cc where cc.id = p_centro;
  insert into staging.recebimento (tenant_id, centro_custo_id, contrato_id_origem, parcela_id_origem, sequencia,
    data_recebimento, valor, origem, tipo_condicao, tipo_baixa)
  select cc.tenant_id, cc.id, p_contrato, p_parcela, r.posicao::integer, (r.item ->> 'data')::date,
         (r.item ->> 'valor')::numeric, case when p_condicao = 'FI' then 'repasse' else 'direta' end, p_condicao,
         case when (r.item ->> 'valor')::numeric < 0 then 'estorno' else 'recebimento' end
  from app.centro_custo cc
  cross join jsonb_array_elements(p_recebimentos) with ordinality as r(item, posicao)
  where cc.id = p_centro;
$$;

create function pg_temp.titulo(p_centro uuid, p_titulo integer, p_vencimento date, p_competencia date,
                               p_valor numeric, p_pagamentos jsonb default '[]') returns void
language sql as $$
  insert into staging.titulo_pagar_apropriacao (tenant_id, centro_custo_id, titulo_id_origem, sequencia_obra,
    sequencia_conta, percentual, principal, valor_original, valor_pago, ajuste_baixa, saldo, vencimento,
    data_competencia, data_ultimo_pagamento)
  select cc.tenant_id, cc.id, p_titulo, 1, 1, 1, true, p_valor, pg.pago, 0, p_valor - pg.pago, p_vencimento,
         p_competencia, pg.ultimo
  from app.centro_custo cc
  cross join (select coalesce(sum((x ->> 'valor')::numeric), 0) as pago, max((x ->> 'data')::date) as ultimo
              from jsonb_array_elements(p_pagamentos) x) pg
  where cc.id = p_centro;
  insert into staging.pagamento (tenant_id, centro_custo_id, titulo_id_origem, sequencia_pagamento, sequencia_obra,
    sequencia_conta, data_pagamento, valor)
  select cc.tenant_id, cc.id, p_titulo, x.posicao::integer, 1, 1, (x.item ->> 'data')::date, (x.item ->> 'valor')::numeric
  from app.centro_custo cc
  cross join jsonb_array_elements(p_pagamentos) with ordinality as x(item, posicao)
  where cc.id = p_centro;
$$;

create function pg_temp.unidade(p_centro uuid, p_id integer, p_situacao text, p_data_entrega date default null,
                                p_valor_sugerido numeric default null) returns void
language sql as $$
  insert into staging.unidade (tenant_id, centro_custo_id, id_origem, nome, tipologia, situacao, data_entrega)
  select cc.tenant_id, cc.id, p_id, 'Unidade ' || p_id, 'apartamento', p_situacao, p_data_entrega
  from app.centro_custo cc where cc.id = p_centro;
  insert into staging.unidade_valor (tenant_id, centro_custo_id, unidade_id_origem, valor_sugerido)
  select cc.tenant_id, cc.id, p_id, p_valor_sugerido
  from app.centro_custo cc where cc.id = p_centro and p_valor_sugerido is not null;
$$;

-- Limpa o tenant A entre os casos. Versão registrada não se apaga pelas vias normais; o modo réplica
-- desliga os gatilhos só aqui, como o dono faria numa limpeza de teste.
create function pg_temp.limpar() returns void
language plpgsql as $$
declare
  t text;
begin
  perform set_config('session_replication_role', 'replica', true);
  foreach t in array array['app.projecao_mensal', 'app.meta_mensal', 'app.versao_planejamento',
    'app.premissa_distribuicao_custo_mes', 'app.premissa_distribuicao_custo', 'app.liberacao_financiamento',
    'app.medicao_bancaria', 'app.operacao_credito_obra', 'app.etapa_financiamento_contrato',
    'app.auditoria_alteracao', 'staging.recebimento', 'staging.parcela_receber', 'staging.contrato_unidade',
    'staging.contrato_venda', 'staging.pagamento', 'staging.titulo_pagar_apropriacao', 'staging.item_orcamento',
    'staging.unidade_valor', 'staging.unidade'] loop
    execute format('delete from %s where tenant_id = %L', t, '7e000000-0000-4000-8000-00000000000a');
  end loop;
  perform set_config('session_replication_role', 'origin', true);
end $$;

-- Dados nas duas obras do tenant A e na obra do tenant B, gravados pelo dono como o carregador
select set_config('app.data_referencia', '2026-09-15', true);
select pg_temp.unidade('7c000000-0000-4000-8000-0000000000a1', 91301, 'D', null, 200000.00);
select pg_temp.unidade('7c000000-0000-4000-8000-0000000000a2', 92301, 'D', null, 300000.00);
select pg_temp.contrato('7c000000-0000-4000-8000-0000000000a1', 6011, 100000.00, '2026-05-01', 80000.00);
select pg_temp.contrato('7c000000-0000-4000-8000-0000000000a2', 6021, 200000.00, '2026-05-01', 150000.00);
select pg_temp.contrato('7c000000-0000-4000-8000-0000000000b1', 6031, 300000.00, '2026-05-01', 200000.00);
select pg_temp.parcela(c, n, 1, 'FI', '2027-01-10', v, v)
from (values ('7c000000-0000-4000-8000-0000000000a1'::uuid, 6011, 80000.00),
             ('7c000000-0000-4000-8000-0000000000a2'::uuid, 6021, 150000.00),
             ('7c000000-0000-4000-8000-0000000000b1'::uuid, 6031, 200000.00)) x(c, n, v);
select pg_temp.titulo(c, n, '2026-10-10', '2026-09-01', 1000.00)
from (values ('7c000000-0000-4000-8000-0000000000a1'::uuid, 7011), ('7c000000-0000-4000-8000-0000000000a2'::uuid, 7021),
             ('7c000000-0000-4000-8000-0000000000b1'::uuid, 7031)) x(c, n);
insert into app.operacao_credito_obra (id, tenant_id, centro_custo_id, modalidade, instituicao, valor_contratado, fonte, autor)
select id, t, c, 'credito_producao', 'Banco Teste', 500000.00, 'Contrato', '7a000000-0000-4000-8000-00000000d00a'
from (values ('7b000000-0000-4000-8000-0000000000a1'::uuid, '7e000000-0000-4000-8000-00000000000a'::uuid,
              '7c000000-0000-4000-8000-0000000000a1'::uuid),
             ('7b000000-0000-4000-8000-0000000000a2', '7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a2'),
             ('7b000000-0000-4000-8000-0000000000b1', '7e000000-0000-4000-8000-00000000000b', '7c000000-0000-4000-8000-0000000000b1')) x(id, t, c);
insert into app.liberacao_financiamento (tenant_id, centro_custo_id, nivel, operacao_credito_id, valor_previsto,
  data_prevista, situacao, fonte, autor)
select t, c, 'empreendimento', o, 100000.00, '2026-11-10', 'prevista', 'Cronograma', '7a000000-0000-4000-8000-00000000d00a'
from (values ('7e000000-0000-4000-8000-00000000000a'::uuid, '7c000000-0000-4000-8000-0000000000a1'::uuid,
              '7b000000-0000-4000-8000-0000000000a1'::uuid),
             ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a2', '7b000000-0000-4000-8000-0000000000a2'),
             ('7e000000-0000-4000-8000-00000000000b', '7c000000-0000-4000-8000-0000000000b1', '7b000000-0000-4000-8000-0000000000b1')) x(t, c, o);

-- Diretor do tenant B grava uma versão na obra dele
select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000d00b", "role": "authenticated"}', true);
set local role authenticated;
select isnt(app.registrar_versao_projecao('7c000000-0000-4000-8000-0000000000b1', 'Projeção B'), null,
  'diretor B registra versão na obra dele');
reset role;

-- Financeiro do tenant A grava versão e meta em T1 e T2
select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000f00a", "role": "authenticated"}', true);
set local role authenticated;
select isnt(app.registrar_versao_projecao('7c000000-0000-4000-8000-0000000000a1', 'Projeção T1'), null, 'financeiro registra versão em T1');
select isnt(app.registrar_versao_projecao('7c000000-0000-4000-8000-0000000000a2', 'Projeção T2'), null, 'financeiro registra versão em T2');
select isnt(app.registrar_versao_meta('7c000000-0000-4000-8000-0000000000a2', 'Meta T2',
  '[{"competencia": "2026-09-01", "unidades": 1}]'), null, 'financeiro registra meta em T2');
select results_eq(
  $$select autor from app.versao_planejamento where descricao = 'Projeção T1'$$,
  $$values ('7a000000-0000-4000-8000-00000000f00a'::uuid)$$,
  'autor da versão é o do JWT'
);
reset role;

-- Gerente da obra T1
select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000c00a", "role": "authenticated"}', true);
set local role authenticated;
select results_eq(
  $$select distinct centro_custo_id from marts.fluxo_projetado_mensal$$,
  $$values ('7c000000-0000-4000-8000-0000000000a1'::uuid)$$,
  'gerente vê fluxo projetado só de T1'
);
select is(
  (select count(*) from marts.financiamento_contrato where centro_custo_id <> '7c000000-0000-4000-8000-0000000000a1')
  + (select count(*) from marts.recebivel_projetado where centro_custo_id <> '7c000000-0000-4000-8000-0000000000a1')
  + (select count(*) from marts.saldo_operacao_credito where centro_custo_id <> '7c000000-0000-4000-8000-0000000000a1')
  + (select count(*) from marts.liberacao_status where centro_custo_id <> '7c000000-0000-4000-8000-0000000000a1')
  + (select count(*) from marts.resumo_projecao_obra where centro_custo_id <> '7c000000-0000-4000-8000-0000000000a1')
  + (select count(*) from marts.comparativo_projecao where centro_custo_id <> '7c000000-0000-4000-8000-0000000000a1')
  + (select count(*) from marts.visao_gerencial_mensal where centro_custo_id <> '7c000000-0000-4000-8000-0000000000a1')
  + (select count(*) from marts.explicacao_desvio where centro_custo_id <> '7c000000-0000-4000-8000-0000000000a1')
  + (select count(*) from marts.pendencias_pos_entrega where centro_custo_id <> '7c000000-0000-4000-8000-0000000000a1')
  + (select count(*) from app.versao_planejamento where centro_custo_id <> '7c000000-0000-4000-8000-0000000000a1')
  + (select count(*) from app.meta_mensal)
  + (select count(*) from app.projecao_mensal where centro_custo_id <> '7c000000-0000-4000-8000-0000000000a1')
  + (select count(*) from app.custo_sem_titulo_obra where centro_custo_id <> '7c000000-0000-4000-8000-0000000000a1')
  + (select count(*) from app.versao_referencia_obra where centro_custo_id <> '7c000000-0000-4000-8000-0000000000a1'),
  0::bigint,
  'gerente não vê nenhuma linha de T2 nem do tenant B nas views e tabelas novas'
);
select is((select count(*) from marts.financiamento_contrato), 1::bigint, 'gerente vê o financiamento de T1');
select is((select count(*) from marts.liberacao_status), 1::bigint, 'gerente vê a liberação de T1');
select is((select count(*) from app.versao_planejamento), 1::bigint, 'gerente vê a versão de T1');
select is((select count(*) from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000a2', '{}')), 0::bigint,
  'simulação de T2 pelo gerente devolve zero linhas');
select is((select count(*) from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000a2',
  '{"novas_vendas": [{"competencia": "2026-10-01", "quantidade": 1}], "composicao": {"entrada": 1}}')), 0::bigint,
  'simulação de venda em T2 pelo gerente não usa o estoque nem o preço de T2');
select is((select count(*) from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000b1', '{}')), 0::bigint,
  'simulação de obra de outro tenant devolve zero linhas');
select ok((select count(*) > 0 from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000a1', '{}')),
  'gerente simula a obra dele');
select throws_ok(
  $$select app.registrar_versao_projecao('7c000000-0000-4000-8000-0000000000a1', 'teste')$$,
  '42501', null, 'gerente não registra versão'
);
select throws_ok(
  $$select app.registrar_versao_meta('7c000000-0000-4000-8000-0000000000a1', 'teste', '[{"competencia": "2026-10-01", "unidades": 1}]')$$,
  '42501', null, 'gerente não registra meta'
);
select throws_ok(
  $$select app.registrar_premissa_distribuicao('7c000000-0000-4000-8000-0000000000a1', 'teste', null,
      '[{"competencia": "2026-10-01", "fracao": 1}]')$$,
  '42501', null, 'gerente não registra premissa de meses'
);
select throws_ok(
  $$select app.registrar_versao_projecao('7c000000-0000-4000-8000-0000000000a2', 'teste')$$,
  '42501', 'obra não encontrada', 'gerente não registra versão em obra que não vê'
);
select throws_ok(
  $$insert into app.liberacao_financiamento (tenant_id, centro_custo_id, nivel, operacao_credito_id, valor_previsto,
      data_prevista, situacao, fonte)
    values ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1', 'empreendimento',
            '7b000000-0000-4000-8000-0000000000a1', 1000.00, '2026-12-10', 'prevista', 'teste')$$,
  '42501', null, 'gerente não grava liberação em T1'
);
select throws_ok(
  $$insert into app.operacao_credito_obra (tenant_id, centro_custo_id, modalidade, instituicao, valor_contratado, fonte)
    values ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1', 'outra', 'Banco', 1.00, 'teste')$$,
  '42501', null, 'gerente não grava operação de crédito'
);
select throws_ok(
  $$insert into app.etapa_financiamento_contrato (tenant_id, centro_custo_id, contrato_id_origem, etapa, data_etapa, fonte)
    values ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1', 6011, 'elegivel', '2026-09-01', 'teste')$$,
  '42501', null, 'gerente não grava etapa de financiamento'
);
select throws_ok(
  $$insert into app.versao_planejamento (tenant_id, centro_custo_id, tipo, numero, descricao, data_referencia, autor)
    values ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1', 'projecao', 9, 'x',
            '2026-09-15', '7a000000-0000-4000-8000-00000000c00a')$$,
  '42501', null, 'gerente não grava versão direto na tabela'
);
update app.operacao_credito_obra set valor_contratado = 1.00 where id = '7b000000-0000-4000-8000-0000000000a1';
select throws_ok(
  $$delete from app.liberacao_financiamento$$, '42501', null, 'gerente não apaga liberação'
);
select is((select count(*) from app.auditoria_alteracao), 0::bigint, 'gerente não vê auditoria');
reset role;
select is((select valor_contratado from app.operacao_credito_obra where id = '7b000000-0000-4000-8000-0000000000a1'),
  500000.00::numeric(18,2), 'update do gerente não alterou nada');

-- Perfil leitura vinculado a T1: lê e não grava
select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000e00a", "role": "authenticated"}', true);
set local role authenticated;
select is((select count(*) from marts.saldo_operacao_credito), 1::bigint, 'leitura vê a operação de T1');
select throws_ok(
  $$insert into app.medicao_bancaria (tenant_id, centro_custo_id, operacao_credito_id, numero, data_vistoria,
      avanco_fisico_informado, situacao, fonte)
    values ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1',
            '7b000000-0000-4000-8000-0000000000a1', 1, '2026-09-01', 0.1, 'apresentada', 'teste')$$,
  '42501', null, 'leitura não grava medição'
);
select throws_ok(
  $$select app.registrar_versao_projecao('7c000000-0000-4000-8000-0000000000a1', 'teste')$$,
  '42501', null, 'leitura não registra versão'
);
update app.liberacao_financiamento set situacao = 'cancelada', motivo = 'x';
reset role;
select is((select count(*) from app.liberacao_financiamento where situacao = 'cancelada'), 0::bigint,
  'update da leitura não alterou nada');

-- Diretor do tenant A
select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000d00a", "role": "authenticated"}', true);
set local role authenticated;
select is((select count(distinct centro_custo_id) from marts.fluxo_projetado_mensal), 2::bigint,
  'diretor vê o fluxo projetado das duas obras, sem Despesas sem obra');
select is((select count(*) from marts.financiamento_contrato where tenant_id <> '7e000000-0000-4000-8000-00000000000a')
  + (select count(*) from app.versao_planejamento where tenant_id <> '7e000000-0000-4000-8000-00000000000a'),
  0::bigint, 'diretor A não vê o tenant B');
select throws_ok($$update app.versao_planejamento set descricao = 'x'$$, '42501', null, 'diretor não altera versão');
select throws_ok($$delete from app.meta_mensal$$, '42501', null, 'diretor não apaga meta');
select throws_ok($$delete from app.premissa_distribuicao_custo$$, '42501', null, 'diretor não apaga premissa');
select throws_ok(
  $$insert into app.liberacao_financiamento (tenant_id, centro_custo_id, nivel, operacao_credito_id, valor_previsto,
      data_prevista, situacao, fonte)
    values ('7e000000-0000-4000-8000-00000000000b', '7c000000-0000-4000-8000-0000000000b1', 'empreendimento',
            '7b000000-0000-4000-8000-0000000000b1', 1000.00, '2026-12-10', 'prevista', 'teste')$$,
  '42501', null, 'diretor A não grava no tenant B'
);
select throws_ok(
  $$insert into app.liberacao_financiamento (tenant_id, centro_custo_id, nivel, operacao_credito_id, valor_previsto,
      data_prevista, situacao, fonte)
    values ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1', 'empreendimento',
            '7b000000-0000-4000-8000-0000000000b1', 1000.00, '2026-12-10', 'prevista', 'teste')$$,
  '23503', null, 'liberação não liga a operação de outro tenant'
);
select lives_ok(
  $$update app.liberacao_financiamento set data_prevista = '2026-12-10', fonte = 'Cronograma revisado'
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a2'$$,
  'diretor ajusta a liberação de T2'
);
select results_eq(
  $$select autor, fonte from app.liberacao_financiamento where centro_custo_id = '7c000000-0000-4000-8000-0000000000a2'$$,
  $$values ('7a000000-0000-4000-8000-00000000d00a'::uuid, 'Cronograma revisado')$$,
  'autor passa a ser quem alterou'
);
select is((select count(*) from app.auditoria_alteracao where tabela = 'app.liberacao_financiamento' and operacao = 'update'),
  1::bigint, 'diretor vê a alteração na auditoria');
reset role;

-- Diretor do tenant B
select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000d00b", "role": "authenticated"}', true);
set local role authenticated;
select is(
  (select count(*) from marts.fluxo_projetado_mensal where tenant_id = '7e000000-0000-4000-8000-00000000000a')
  + (select count(*) from marts.financiamento_contrato where tenant_id = '7e000000-0000-4000-8000-00000000000a')
  + (select count(*) from marts.liberacao_status where tenant_id = '7e000000-0000-4000-8000-00000000000a')
  + (select count(*) from marts.recebivel_projetado where tenant_id = '7e000000-0000-4000-8000-00000000000a')
  + (select count(*) from marts.saldo_operacao_credito where tenant_id = '7e000000-0000-4000-8000-00000000000a')
  + (select count(*) from marts.resumo_projecao_obra where tenant_id = '7e000000-0000-4000-8000-00000000000a')
  + (select count(*) from marts.visao_gerencial_mensal where tenant_id = '7e000000-0000-4000-8000-00000000000a')
  + (select count(*) from app.versao_planejamento where tenant_id = '7e000000-0000-4000-8000-00000000000a')
  + (select count(*) from app.projecao_mensal where tenant_id = '7e000000-0000-4000-8000-00000000000a'),
  0::bigint, 'tenant A invisível para o diretor B'
);
select is((select count(*) from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000a1', '{}')), 0::bigint,
  'diretor B não simula obra do tenant A');
select is((select count(*) from marts.financiamento_contrato), 1::bigint, 'diretor B vê o próprio financiamento');
select is((select numero from app.versao_planejamento), 1, 'numeração de versão é por obra, não global');
reset role;

-- Anônimo
select set_config('request.jwt.claims', '', true);
set local role anon;
select throws_ok('select count(*) from marts.fluxo_projetado_mensal', '42501', null, 'anônimo não lê o fluxo projetado');
select throws_ok($$select * from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000a1', '{}')$$, '42501', null,
  'anônimo não simula');
select throws_ok('select count(*) from app.liberacao_financiamento', '42501', null, 'anônimo não lê liberações');
reset role;

-- Estrutura: RLS forçado, uma política por ação, funções de gatilho fora do alcance do usuário
select is(
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'app' and c.relname in ('operacao_credito_obra', 'etapa_financiamento_contrato', 'medicao_bancaria',
     'liberacao_financiamento', 'versao_planejamento', 'meta_mensal', 'projecao_mensal', 'premissa_distribuicao_custo',
     'premissa_distribuicao_custo_mes') and c.relrowsecurity and c.relforcerowsecurity),
  9::bigint, 'as nove tabelas novas têm RLS ligado e forçado'
);
select is(
  (select count(*) from (select tablename, cmd from pg_policies
     where schemaname = 'app' and tablename in ('operacao_credito_obra', 'etapa_financiamento_contrato', 'medicao_bancaria',
       'liberacao_financiamento', 'versao_planejamento', 'meta_mensal', 'projecao_mensal', 'premissa_distribuicao_custo',
       'premissa_distribuicao_custo_mes') and permissive = 'PERMISSIVE'
     group by 1, 2 having count(*) > 1) x),
  0::bigint, 'uma política permissiva por tabela e ação'
);
select is(
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('marts', 'app') and c.relkind = 'v'
     and c.relname in ('financiamento_contrato', 'recebivel_projetado', 'saldo_operacao_credito', 'liberacao_status',
       'fluxo_projetado_mensal', 'resumo_projecao_obra', 'comparativo_projecao', 'explicacao_desvio',
       'visao_gerencial_mensal', 'pendencias_pos_entrega', 'custo_sem_titulo_obra', 'custo_sem_titulo_mensal',
       'versao_referencia_obra')
     and not coalesce(c.reloptions @> array['security_invoker=true'], false)),
  0::bigint, 'todas as views novas com security_invoker'
);
select is(
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app' and p.proname in ('validar_contrato_financiamento', 'validar_liberacao', 'validar_operacao_credito',
     'preparar_versao', 'preparar_premissa', 'validar_linha_versao', 'bloquear_alteracao_versao')
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))),
  0::bigint, 'funções de gatilho não são executáveis pelo usuário'
);
select is(
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('app', 'marts') and p.proname in ('classificar_financiamento', 'premissa_numero', 'premissa_inteiro',
     'premissa_competencia', 'simular_fluxo', 'registrar_versao_projecao', 'registrar_versao_meta',
     'registrar_premissa_distribuicao', 'validar_contrato_financiamento', 'validar_liberacao', 'validar_operacao_credito',
     'preparar_versao', 'preparar_premissa', 'validar_linha_versao', 'bloquear_alteracao_versao')
     and (p.prosecdef or not coalesce(p.proconfig @> array['search_path=""'], false) or has_function_privilege('anon', p.oid, 'execute'))),
  0::bigint, 'funções novas são security invoker, com search_path vazio e fora do alcance do anônimo'
);

select * from finish();
rollback;
