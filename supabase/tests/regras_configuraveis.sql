-- Regras de negócio por cliente (docs/financeiro/configuracao.md, seções 2.5 e 3): cada parâmetro lido pelas
-- migrations 0011 a 0013 com números conhecidos para cada valor e com a obra sobrepondo o tenant;
-- subcategorias e rótulos; fluxo consolidado; meta automática; isolamento. Nível staging; cada caso limpa
-- o tenant R.
begin;
create extension if not exists pgtap with schema extensions;
select plan(101);

insert into app.tenant (id, razao_social) values
  ('7d000000-0000-4000-8000-00000000000a', 'Construtora Teste Regras R'),
  ('7d000000-0000-4000-8000-00000000000b', 'Construtora Teste Regras S');

insert into app.centro_custo (id, tenant_id, id_origem, nome, tipo) values
  ('7d100000-0000-4000-8000-0000000000a1', '7d000000-0000-4000-8000-00000000000a', 9001, 'Obra Regras 1', 'obra'),
  ('7d100000-0000-4000-8000-0000000000a2', '7d000000-0000-4000-8000-00000000000a', 9002, 'Obra Regras 2', 'obra'),
  ('7d100000-0000-4000-8000-0000000000ae', '7d000000-0000-4000-8000-00000000000a', null, 'Despesas sem obra', 'empresa'),
  ('7d100000-0000-4000-8000-0000000000b1', '7d000000-0000-4000-8000-00000000000b', 9001, 'Obra Regras S1', 'obra');

insert into auth.users (id, email) values
  ('7d200000-0000-4000-8000-00000000d00a', 'diretor.regras@teste.invalid'),
  ('7d200000-0000-4000-8000-00000000f00a', 'financeiro.regras@teste.invalid'),
  ('7d200000-0000-4000-8000-00000000c00a', 'gerente.regras@teste.invalid'),
  ('7d200000-0000-4000-8000-00000000d00b', 'diretorb.regras@teste.invalid');
insert into app.usuario_tenant (user_id, tenant_id, perfil) values
  ('7d200000-0000-4000-8000-00000000d00a', '7d000000-0000-4000-8000-00000000000a', 'diretor'),
  ('7d200000-0000-4000-8000-00000000f00a', '7d000000-0000-4000-8000-00000000000a', 'financeiro'),
  ('7d200000-0000-4000-8000-00000000c00a', '7d000000-0000-4000-8000-00000000000a', 'gerente_obra'),
  ('7d200000-0000-4000-8000-00000000d00b', '7d000000-0000-4000-8000-00000000000b', 'diretor');
insert into app.usuario_centro_custo (user_id, tenant_id, centro_custo_id) values
  ('7d200000-0000-4000-8000-00000000c00a', '7d000000-0000-4000-8000-00000000000a', '7d100000-0000-4000-8000-0000000000a1');

-- Gravação no nível staging como o carregador; os gatilhos da 0007 normalizam situação e origem pelo mapa.
create function pg_temp.contrato(p_centro uuid, p_id integer, p_valor numeric, p_data_venda date,
                                 p_unidade integer default null, p_data_repasse date default null) returns void
language sql as $$
  insert into staging.contrato_venda (tenant_id, centro_custo_id, id_origem, numero, data_venda, valor, situacao,
    banco_repasse, data_repasse, unidade_id_origem)
  select cc.tenant_id, cc.id, p_id, 'C-' || p_id, p_data_venda, p_valor, '1',
         case when p_data_repasse is not null then 'Banco' end, p_data_repasse, p_unidade
  from app.centro_custo cc where cc.id = p_centro;
  insert into staging.contrato_unidade (tenant_id, centro_custo_id, contrato_id_origem, sequencia, unidade_id_origem, principal)
  select cc.tenant_id, cc.id, p_id, 1, p_unidade, true
  from app.centro_custo cc where cc.id = p_centro and p_unidade is not null;
$$;

create function pg_temp.parcela(p_centro uuid, p_contrato integer, p_parcela integer, p_condicao text,
                                p_vencimento date, p_saldo numeric) returns void
language sql as $$
  insert into staging.parcela_receber (tenant_id, centro_custo_id, id_origem, contrato_id_origem, vencimento,
    valor_original, saldo, saldo_corrigido, tipo_condicao, valor_recebido)
  select cc.tenant_id, cc.id, p_parcela, p_contrato, p_vencimento, p_saldo, p_saldo, p_saldo, p_condicao, 0
  from app.centro_custo cc where cc.id = p_centro;
$$;

create function pg_temp.titulo(p_centro uuid, p_titulo integer, p_conta text, p_competencia date, p_vencimento date,
                               p_valor numeric, p_pago_em date default null) returns void
language sql as $$
  insert into staging.titulo_pagar_apropriacao (tenant_id, centro_custo_id, titulo_id_origem, sequencia_obra,
    sequencia_conta, conta_origem, percentual, principal, valor_original, valor_pago, ajuste_baixa, saldo, vencimento,
    data_competencia, data_ultimo_pagamento)
  select cc.tenant_id, cc.id, p_titulo, 1, 1, p_conta, 1, true, p_valor,
         case when p_pago_em is null then 0 else p_valor end, 0,
         case when p_pago_em is null then p_valor else 0 end, p_vencimento, p_competencia, p_pago_em
  from app.centro_custo cc where cc.id = p_centro;
  insert into staging.pagamento (tenant_id, centro_custo_id, titulo_id_origem, sequencia_pagamento, sequencia_obra,
    sequencia_conta, conta_origem, data_pagamento, valor)
  select cc.tenant_id, cc.id, p_titulo, 1, 1, 1, p_conta, p_pago_em, p_valor
  from app.centro_custo cc where cc.id = p_centro and p_pago_em is not null;
$$;

create function pg_temp.unidade(p_centro uuid, p_id integer, p_situacao text, p_area numeric, p_valor_sugerido numeric,
                                p_data_entrega date default null) returns void
language sql as $$
  insert into staging.unidade (tenant_id, centro_custo_id, id_origem, nome, tipologia, area_privativa, situacao, data_entrega)
  select cc.tenant_id, cc.id, p_id, 'Unidade ' || p_id, 'apartamento', p_area, p_situacao, p_data_entrega
  from app.centro_custo cc where cc.id = p_centro;
  insert into staging.unidade_valor (tenant_id, centro_custo_id, unidade_id_origem, valor_sugerido)
  select cc.tenant_id, cc.id, p_id, p_valor_sugerido
  from app.centro_custo cc where cc.id = p_centro and p_valor_sugerido is not null;
$$;

create function pg_temp.orcamento(p_centro uuid, p_codigo text, p_valor numeric) returns void language sql as $$
  insert into staging.item_orcamento (tenant_id, centro_custo_id, codigo, descricao, valor_total)
  select cc.tenant_id, cc.id, p_codigo, 'Item ' || p_codigo, p_valor from app.centro_custo cc where cc.id = p_centro;
$$;

create function pg_temp.mapa(p_tipo text, p_conta text, p_categoria text) returns void language sql as $$
  insert into app.mapa_conta_origem (tenant_id, tipo_origem, conta_origem, categoria_codigo, autor)
  values ('7d000000-0000-4000-8000-00000000000a', p_tipo, p_conta, p_categoria, '7d200000-0000-4000-8000-00000000d00a')
$$;

-- Parâmetros de uma vez numa instrução: as frações da simulação são conferidas no fim de cada instrução.
create function pg_temp.parametros(p_valores jsonb, p_centro uuid default null) returns void language sql as $$
  insert into app.parametro_valor (tenant_id, centro_custo_id, codigo, valor, observacao, autor)
  select '7d000000-0000-4000-8000-00000000000a', p_centro, v.key, v.value, 'caso de teste',
         '7d200000-0000-4000-8000-00000000d00a'
  from jsonb_each(p_valores) v
  on conflict on constraint parametro_valor_unico do update set valor = excluded.valor
$$;

create function pg_temp.limpar() returns void
language plpgsql as $$
declare
  t text;
begin
  perform set_config('session_replication_role', 'replica', true);
  foreach t in array array['app.parametro_valor', 'app.criterio_reconhecimento', 'app.mapa_conta_origem',
    'app.categoria_tenant', 'app.rotulo_personalizado', 'app.projecao_mensal', 'app.meta_mensal',
    'app.versao_planejamento', 'app.premissa_distribuicao_custo_mes', 'app.premissa_distribuicao_custo',
    'app.liberacao_financiamento', 'app.medicao_bancaria', 'app.operacao_credito_obra',
    'app.etapa_financiamento_contrato', 'app.auditoria_alteracao', 'staging.recebimento', 'staging.parcela_receber',
    'staging.contrato_unidade', 'staging.contrato_venda', 'staging.pagamento', 'staging.titulo_pagar_apropriacao',
    'staging.item_orcamento', 'staging.unidade_valor', 'staging.unidade'] loop
    execute format('delete from %s where tenant_id = %L', t, '7d000000-0000-4000-8000-00000000000a');
  end loop;
  perform set_config('session_replication_role', 'origin', true);
end $$;

-- Reconhecimento: obra R1 com 4 unidades (áreas 50, 50, 100 e 200; valores 100, 100, 200 e 600 mil),
-- a unidade de 200 m² vendida em janeiro por 800 mil, orçamento de 1 milhão com 200 mil de terreno e
-- custo lançado de 200 mil de terreno em janeiro e 100 mil de materiais em fevereiro.
select set_config('app.data_referencia', '2026-02-15', true);
select pg_temp.unidade('7d100000-0000-4000-8000-0000000000a1', 9101, 'D', 50, 100000.00);
select pg_temp.unidade('7d100000-0000-4000-8000-0000000000a1', 9102, 'D', 50, 100000.00);
select pg_temp.unidade('7d100000-0000-4000-8000-0000000000a1', 9103, 'D', 100, 200000.00);
select pg_temp.unidade('7d100000-0000-4000-8000-0000000000a1', 9104, 'V', 200, 600000.00);
select pg_temp.contrato('7d100000-0000-4000-8000-0000000000a1', 8101, 800000.00, '2026-01-10', 9104);
select pg_temp.orcamento('7d100000-0000-4000-8000-0000000000a1', 'T', 200000.00);
select pg_temp.orcamento('7d100000-0000-4000-8000-0000000000a1', 'E', 800000.00);
select pg_temp.mapa('orcamento', 'T', 'terreno');
select pg_temp.mapa('orcamento', 'E', 'materiais');
select pg_temp.mapa('titulo_pagar', '2.09.001', 'terreno');
select pg_temp.mapa('titulo_pagar', '2.01.001', 'materiais');
select pg_temp.titulo('7d100000-0000-4000-8000-0000000000a1', 7101, '2.09.001', '2026-01-05', '2026-01-20', 200000.00);
select pg_temp.titulo('7d100000-0000-4000-8000-0000000000a1', 7102, '2.01.001', '2026-02-05', '2026-02-20', 100000.00);
insert into app.criterio_reconhecimento (tenant_id, metodo, autor, validado_por) values
  ('7d000000-0000-4000-8000-00000000000a', 'percentual_conclusao', '7d200000-0000-4000-8000-00000000f00a',
   '7d200000-0000-4000-8000-00000000f00a');

create function pg_temp.reconhecimento() returns table (competencia date, poc numeric, fracao numeric,
  receita numeric, custo numeric, base text) language sql as $$
  select r.competencia, r.poc, r.fracao_vendida, r.receita_reconhecida_acumulada, r.custo_reconhecido_acumulado,
         r.base_fracao_vendida
  from marts.reconhecimento_obra_mensal r where r.centro_custo_id = '7d100000-0000-4000-8000-0000000000a1'
  order by r.competencia
$$;

select results_eq(
  $$select * from pg_temp.reconhecimento()$$,
  $$values ('2026-01-01'::date, 0.200000::numeric, 0.250000::numeric, 160000.00::numeric, 50000.00::numeric, 'unidades'),
           ('2026-02-01'::date, 0.300000, 0.250000, 240000.00, 75000.00, 'unidades')$$,
  'base unidades (padrão): uma de quatro unidades vendida, custo reconhecido 25% do incorrido'
);
select pg_temp.parametros('{"reconhecimento.base_fracao_vendida": "area_privativa"}');
select results_eq(
  $$select competencia, fracao, custo, base from pg_temp.reconhecimento()$$,
  $$values ('2026-01-01'::date, 0.500000::numeric, 100000.00::numeric, 'area_privativa'),
           ('2026-02-01'::date, 0.500000, 150000.00, 'area_privativa')$$,
  'base área privativa: 200 de 400 m² vendidos'
);
select pg_temp.parametros('{"reconhecimento.base_fracao_vendida": "valor_tabela"}');
select results_eq(
  $$select competencia, fracao, receita, custo from pg_temp.reconhecimento()$$,
  $$values ('2026-01-01'::date, 0.600000::numeric, 160000.00::numeric, 120000.00::numeric),
           ('2026-02-01'::date, 0.600000, 240000.00, 180000.00)$$,
  'base valor de tabela: 600 mil de 1 milhão; a receita não depende da base'
);
select pg_temp.parametros('{"reconhecimento.base_fracao_vendida": "area_privativa"}');
select pg_temp.parametros('{"reconhecimento.base_fracao_vendida": "valor_tabela"}', '7d100000-0000-4000-8000-0000000000a1');
select results_eq(
  $$select competencia, fracao, base from pg_temp.reconhecimento()$$,
  $$values ('2026-01-01'::date, 0.600000::numeric, 'valor_tabela'), ('2026-02-01'::date, 0.600000, 'valor_tabela')$$,
  'base: valor da obra vence o do tenant'
);
select is(
  (select reconhecimento__base_fracao_vendida from app.parametros_obra
    where centro_custo_id = '7d100000-0000-4000-8000-0000000000a2'),
  'area_privativa', 'base: obra sem valor próprio fica com o do tenant'
);
delete from app.parametro_valor where tenant_id = '7d000000-0000-4000-8000-00000000000a';
update staging.unidade set area_privativa = null where tenant_id = '7d000000-0000-4000-8000-00000000000a' and id_origem = 9101;
select pg_temp.parametros('{"reconhecimento.base_fracao_vendida": "area_privativa"}');
select results_eq(
  $$select disponivel, motivo from marts.reconhecimento_obra_mensal
    where centro_custo_id = '7d100000-0000-4000-8000-0000000000a1' order by competencia$$,
  $$values (false, 'area_privativa_ausente'), (false, 'area_privativa_ausente')$$,
  'base área privativa: unidade sem área deixa o reconhecimento indisponível com o motivo'
);
update staging.unidade set area_privativa = 50 where tenant_id = '7d000000-0000-4000-8000-00000000000a' and id_origem = 9101;
delete from app.parametro_valor where tenant_id = '7d000000-0000-4000-8000-00000000000a';

-- Terreno fora do percentual: incorrido 0 e 100 mil sobre total de 800 mil; o custo reconhecido segue
-- com o terreno da unidade vendida.
select pg_temp.parametros('{"reconhecimento.incluir_terreno": false}');
select results_eq(
  $$select competencia, custo_incorrido_acumulado, custo_total_estimado, poc, receita_reconhecida_acumulada,
           custo_reconhecido_acumulado
    from marts.reconhecimento_obra_mensal where centro_custo_id = '7d100000-0000-4000-8000-0000000000a1' order by 1$$,
  $$values ('2026-01-01'::date, 0.00::numeric(18,2), 800000.00::numeric(18,2), 0.000000::numeric(9,6), 0.00::numeric(18,2),
            50000.00::numeric(18,2)),
           ('2026-02-01'::date, 100000.00, 800000.00, 0.125000, 100000.00, 75000.00)$$,
  'sem terreno: percentual e receita sem o terreno, custo reconhecido com ele'
);
select pg_temp.parametros('{"reconhecimento.incluir_terreno": true}', '7d100000-0000-4000-8000-0000000000a1');
select results_eq(
  $$select competencia, custo_incorrido_acumulado, custo_total_estimado, poc
    from marts.reconhecimento_obra_mensal where centro_custo_id = '7d100000-0000-4000-8000-0000000000a1' order by 1$$,
  $$values ('2026-01-01'::date, 200000.00::numeric(18,2), 1000000.00::numeric(18,2), 0.200000::numeric(9,6)),
           ('2026-02-01'::date, 300000.00, 1000000.00, 0.300000)$$,
  'terreno: obra com terreno vence o tenant sem terreno'
);
delete from app.parametro_valor where tenant_id = '7d000000-0000-4000-8000-00000000000a';

-- Cobertura: 10 mil sem categoria em fevereiro deixam 300 de 310 mil classificados (96,77%).
select pg_temp.titulo('7d100000-0000-4000-8000-0000000000a1', 7103, '9.99.999', '2026-02-10', '2026-02-25', 10000.00);
select results_eq(
  $$select competencia, disponivel, motivo, cobertura_custo from marts.reconhecimento_obra_mensal
    where centro_custo_id = '7d100000-0000-4000-8000-0000000000a1' order by 1$$,
  $$values ('2026-01-01'::date, true, null::text, 1.000000::numeric(9,6)),
           ('2026-02-01'::date, false, 'custo_sem_categoria', 0.967742)$$,
  'cobertura mínima 1 (padrão): qualquer lançamento sem categoria bloqueia; a cobertura real aparece'
);
select pg_temp.parametros('{"reconhecimento.cobertura_minima": 0.95}');
select results_eq(
  $$select competencia, disponivel, receita_reconhecida_acumulada, cobertura_custo from marts.reconhecimento_obra_mensal
    where centro_custo_id = '7d100000-0000-4000-8000-0000000000a1' order by 1$$,
  $$values ('2026-01-01'::date, true, 160000.00::numeric(18,2), 1.000000::numeric(9,6)),
           ('2026-02-01'::date, true, 240000.00, 0.967742)$$,
  'cobertura mínima 95%: 96,77% classificados liberam o percentual de conclusão'
);
select pg_temp.parametros('{"reconhecimento.cobertura_minima": 0.98}', '7d100000-0000-4000-8000-0000000000a1');
select is(
  (select motivo from marts.reconhecimento_obra_mensal
    where centro_custo_id = '7d100000-0000-4000-8000-0000000000a1' and competencia = '2026-02-01'),
  'custo_sem_categoria', 'cobertura: 98% da obra vence os 95% do tenant e bloqueia fevereiro'
);
delete from app.parametro_valor where tenant_id = '7d000000-0000-4000-8000-00000000000a';
delete from staging.titulo_pagar_apropriacao where tenant_id = '7d000000-0000-4000-8000-00000000000a' and titulo_id_origem = 7103;

-- Critério gravado sem validador (carga sem usuário)
delete from app.criterio_reconhecimento where tenant_id = '7d000000-0000-4000-8000-00000000000a';
insert into app.criterio_reconhecimento (tenant_id, metodo, autor) values
  ('7d000000-0000-4000-8000-00000000000a', 'percentual_conclusao', '7d200000-0000-4000-8000-00000000f00a');
select results_eq(
  $$select competencia, metodo, disponivel, motivo from marts.reconhecimento_obra_mensal
    where centro_custo_id = '7d100000-0000-4000-8000-0000000000a1' order by 1$$,
  $$values ('2026-01-01'::date, 'nao_definido', false, 'criterio_sem_validador'),
           ('2026-02-01'::date, 'nao_definido', false, 'criterio_sem_validador')$$,
  'exigir validação (padrão): critério da carga sem validador fica não definido'
);
select results_eq(
  $$select valor_mes, disponivel, motivo from marts.dre_mensal
    where centro_custo_id = '7d100000-0000-4000-8000-0000000000a1' and competencia = '2026-02-01'
      and linha_codigo = 'receita_bruta'$$,
  $$values (null::numeric(18,2), false, 'criterio_sem_validador')$$,
  'exigir validação: o DRE mostra o mesmo motivo'
);
select pg_temp.parametros('{"reconhecimento.exigir_validacao_usuario": false}');
select results_eq(
  $$select competencia, metodo, disponivel, receita_reconhecida_acumulada from marts.reconhecimento_obra_mensal
    where centro_custo_id = '7d100000-0000-4000-8000-0000000000a1' order by 1$$,
  $$values ('2026-01-01'::date, 'percentual_conclusao', true, 160000.00::numeric(18,2)),
           ('2026-02-01'::date, 'percentual_conclusao', true, 240000.00)$$,
  'sem exigir validação: o critério da carga vale'
);
select throws_ok(
  $$select pg_temp.parametros('{"reconhecimento.exigir_validacao_usuario": true}', '7d100000-0000-4000-8000-0000000000a1')$$,
  '23514', null, 'exigir validação é só do tenant: a obra não sobrepõe'
);
select lives_ok(
  $$insert into app.criterio_reconhecimento (tenant_id, centro_custo_id, metodo, autor, validado_por) values
      ('7d000000-0000-4000-8000-00000000000a', '7d100000-0000-4000-8000-0000000000a1', 'nao_definido',
       '7d200000-0000-4000-8000-00000000f00a', '7d200000-0000-4000-8000-00000000f00a')$$,
  'critério da obra gravado'
);
select is(
  (select motivo from marts.reconhecimento_obra_mensal
    where centro_custo_id = '7d100000-0000-4000-8000-0000000000a1' and competencia = '2026-02-01'),
  'criterio_nao_validado', 'critério da obra vence o do tenant mesmo sem exigir validação'
);

-- Competência dos títulos: um sem emissão com vencimento em fevereiro e um emitido em janeiro com
-- vencimento em março.
select pg_temp.limpar();
select set_config('app.data_referencia', '2026-03-15', true);
select pg_temp.mapa('titulo_pagar', '2.01.001', 'materiais');
select pg_temp.titulo('7d100000-0000-4000-8000-0000000000a1', 7201, '2.01.001', null, '2026-02-20', 1000.00);
select pg_temp.titulo('7d100000-0000-4000-8000-0000000000a1', 7202, '2.01.001', '2026-01-05', '2026-03-10', 2000.00);
create function pg_temp.lancado() returns table (competencia date, lancado numeric) language sql as $$
  select d.competencia, sum(d.lancado_competencia) from marts.despesa_mensal d
  where d.centro_custo_id = '7d100000-0000-4000-8000-0000000000a1' and d.lancado_competencia <> 0
  group by 1 order by 1
$$;
create function pg_temp.sem_data() returns numeric language sql as $$
  select d.valor_mes from marts.dre_mensal d
  where d.centro_custo_id = '7d100000-0000-4000-8000-0000000000a1' and d.linha_codigo = 'sem_data_competencia'
$$;
select results_eq($$select * from pg_temp.lancado()$$, $$values ('2026-01-01'::date, 2000.00::numeric)$$,
  'competência pela emissão (padrão): título sem emissão fica sem competência');
select is(pg_temp.sem_data(), -1000.00::numeric, 'competência pela emissão: o DRE mostra os mil sem data');
select pg_temp.parametros('{"dre.competencia_titulo": "emissao_ou_vencimento"}');
select results_eq($$select * from pg_temp.lancado()$$,
  $$values ('2026-01-01'::date, 2000.00::numeric), ('2026-02-01'::date, 1000.00)$$,
  'competência pela emissão ou vencimento: o título sem emissão vai para fevereiro');
select is(pg_temp.sem_data(), 0.00::numeric, 'competência pela emissão ou vencimento: nada fica sem data');
select pg_temp.parametros('{"dre.competencia_titulo": "vencimento"}');
select results_eq($$select * from pg_temp.lancado()$$,
  $$values ('2026-02-01'::date, 1000.00::numeric), ('2026-03-01'::date, 2000.00)$$,
  'competência pelo vencimento: o título de janeiro vai para março');
select is(
  (select sum(valor_mes) from marts.dre_mensal where centro_custo_id = '7d100000-0000-4000-8000-0000000000a1'
     and linha_codigo = 'custo_obra_incorrido' and competencia = '2026-03-01'),
  -2000.00::numeric, 'competência pelo vencimento: o DRE lança o custo em março');
select throws_ok(
  $$select pg_temp.parametros('{"dre.competencia_titulo": "emissao"}', '7d100000-0000-4000-8000-0000000000a1')$$,
  '23514', null, 'competência dos títulos é só do tenant');

-- Caixa projetado da obra R1 em 15/09/2026: parcela vencida de 10 mil, parcela de outubro de 20 mil,
-- financiamento pendente de 50 mil em novembro, título vencido de 7 mil e outro de 3 mil em outubro,
-- 90 mil sem título repartidos metade em agosto e metade em outubro, e quatro liberações de crédito:
-- prevista em dezembro (40 mil), pendente em janeiro (30 mil), prevista vencida em agosto (15 mil) e
-- pendente vencida em julho (5 mil).
select pg_temp.limpar();
select set_config('app.data_referencia', '2026-09-15', true);
select pg_temp.contrato('7d100000-0000-4000-8000-0000000000a1', 8301, 100000.00, '2026-01-10');
select pg_temp.contrato('7d100000-0000-4000-8000-0000000000a1', 8302, 200000.00, '2026-02-10');
select pg_temp.parcela('7d100000-0000-4000-8000-0000000000a1', 8301, 1, 'PM', '2026-08-10', 10000.00);
select pg_temp.parcela('7d100000-0000-4000-8000-0000000000a1', 8301, 2, 'PM', '2026-10-10', 20000.00);
select pg_temp.parcela('7d100000-0000-4000-8000-0000000000a1', 8302, 3, 'FI', '2026-11-10', 50000.00);
select pg_temp.titulo('7d100000-0000-4000-8000-0000000000a1', 7301, '2.01.001', '2026-08-01', '2026-08-20', 7000.00);
select pg_temp.titulo('7d100000-0000-4000-8000-0000000000a1', 7302, '2.01.001', '2026-09-01', '2026-10-20', 3000.00);
select pg_temp.orcamento('7d100000-0000-4000-8000-0000000000a1', 'X', 100000.00);
insert into app.premissa_distribuicao_custo (id, tenant_id, centro_custo_id, fonte, autor) values
  ('7d300000-0000-4000-8000-000000000001', '7d000000-0000-4000-8000-00000000000a', '7d100000-0000-4000-8000-0000000000a1',
   'cronograma de teste', '7d200000-0000-4000-8000-00000000d00a');
insert into app.premissa_distribuicao_custo_mes (premissa_id, tenant_id, centro_custo_id, competencia, fracao) values
  ('7d300000-0000-4000-8000-000000000001', '7d000000-0000-4000-8000-00000000000a', '7d100000-0000-4000-8000-0000000000a1',
   '2026-08-01', 0.5),
  ('7d300000-0000-4000-8000-000000000001', '7d000000-0000-4000-8000-00000000000a', '7d100000-0000-4000-8000-0000000000a1',
   '2026-10-01', 0.5);
insert into app.operacao_credito_obra (id, tenant_id, centro_custo_id, modalidade, instituicao, valor_contratado, fonte, autor)
values ('7d400000-0000-4000-8000-000000000001', '7d000000-0000-4000-8000-00000000000a',
        '7d100000-0000-4000-8000-0000000000a1', 'credito_producao', 'Banco de teste', 1000000.00, 'contrato de teste',
        '7d200000-0000-4000-8000-00000000d00a');
insert into app.liberacao_financiamento (tenant_id, centro_custo_id, nivel, operacao_credito_id, valor_previsto,
  data_prevista, situacao, motivo, fonte, autor)
select '7d000000-0000-4000-8000-00000000000a', '7d100000-0000-4000-8000-0000000000a1', 'empreendimento',
       '7d400000-0000-4000-8000-000000000001', v, d, s, m, 'cronograma do banco', '7d200000-0000-4000-8000-00000000d00a'
from (values (40000.00, '2026-12-05'::date, 'prevista', null), (30000.00, '2027-01-05', 'pendente', 'aguarda vistoria'),
             (15000.00, '2026-08-05', 'prevista', null), (5000.00, '2026-07-05', 'pendente', 'aguarda vistoria'))
  as l(v, d, s, m);

create function pg_temp.fluxo(p_centro uuid default '7d100000-0000-4000-8000-0000000000a1')
returns table (competencia date, entradas numeric, saidas numeric, credito numeric, custo numeric, acumulado numeric,
               conservador numeric) language sql as $$
  select f.competencia, f.total_entradas, f.total_saidas, f.credito_producao_previsto, f.custo_sem_titulo_distribuido,
         f.caixa_gerado_acumulado, f.caixa_gerado_acumulado_conservador
  from marts.fluxo_projetado_mensal f where f.centro_custo_id = p_centro order by f.competencia
$$;
create function pg_temp.mes(p_competencia date) returns table (entradas numeric, saidas numeric, credito numeric,
  custo numeric, vencido numeric, recuperacao numeric, a_pagar_vencido numeric) language sql as $$
  select f.total_entradas, f.total_saidas, f.credito_producao_previsto, f.custo_sem_titulo_distribuido,
         f.vencido_a_receber, f.vencido_recuperacao_prevista, f.a_pagar_vencido
  from marts.fluxo_projetado_mensal f
  where f.centro_custo_id = '7d100000-0000-4000-8000-0000000000a1' and f.competencia = p_competencia
$$;

select results_eq(
  $$select * from pg_temp.fluxo()$$,
  $$values ('2026-09-01'::date, 0.00::numeric, 52000.00::numeric, 0.00::numeric, 45000.00::numeric, -52000.00::numeric,
            -52000.00::numeric),
           ('2026-10-01'::date, 20000.00, 48000.00, 0.00, 45000.00, -80000.00, -80000.00),
           ('2026-11-01'::date, 50000.00, 0.00, 0.00, 0.00, -30000.00, -80000.00),
           ('2026-12-01'::date, 40000.00, 0.00, 40000.00, 0.00, 10000.00, -40000.00),
           ('2027-01-01'::date, 0.00, 0.00, 0.00, 0.00, 10000.00, -40000.00)$$,
  'caixa no padrão: vencido a receber fora, vencido a pagar e custo de agosto em setembro, pendente no principal'
);

select pg_temp.parametros('{"caixa.receber_vencido": "mes_referencia"}');
select results_eq($$select entradas, vencido, recuperacao from pg_temp.mes('2026-09-01')$$,
  $$values (10000.00::numeric, 10000.00::numeric, 10000.00::numeric)$$,
  'receber vencido no mês de referência: entra inteiro com a fração padrão 1');
select pg_temp.parametros('{"caixa.fracao_recuperacao_vencido": 0.5}', '7d100000-0000-4000-8000-0000000000a1');
select results_eq($$select entradas, recuperacao from pg_temp.mes('2026-09-01')$$,
  $$values (5000.00::numeric, 5000.00::numeric)$$,
  'fração de recuperação 0,5 na obra sobre 1 do tenant: metade do vencido');
select pg_temp.parametros('{"caixa.fracao_recuperacao_vencido": 0.25}');
select results_eq($$select entradas from pg_temp.mes('2026-09-01')$$, $$values (5000.00::numeric)$$,
  'fração de recuperação: 0,5 da obra continua valendo sobre 0,25 do tenant');
select pg_temp.parametros('{"caixa.receber_vencido": "excluir"}', '7d100000-0000-4000-8000-0000000000a1');
select results_eq($$select entradas, recuperacao from pg_temp.mes('2026-09-01')$$,
  $$values (0.00::numeric, 0.00::numeric)$$, 'receber vencido: obra que exclui vence o tenant');
delete from app.parametro_valor where tenant_id = '7d000000-0000-4000-8000-00000000000a';

select pg_temp.parametros('{"caixa.pagar_vencido": "excluir"}');
select results_eq($$select saidas, a_pagar_vencido from pg_temp.mes('2026-09-01')$$,
  $$values (45000.00::numeric, 7000.00::numeric)$$, 'pagar vencido excluído: fica só informativo');
select pg_temp.parametros('{"caixa.pagar_vencido": "mes_referencia"}', '7d100000-0000-4000-8000-0000000000a1');
select results_eq($$select saidas from pg_temp.mes('2026-09-01')$$, $$values (52000.00::numeric)$$,
  'pagar vencido: obra no mês de referência vence o tenant');
delete from app.parametro_valor where tenant_id = '7d000000-0000-4000-8000-00000000000a';

select pg_temp.parametros('{"caixa.financiamento_pendente": "excluir"}');
select results_eq(
  $$select competencia, entradas, acumulado, conservador from pg_temp.fluxo() where competencia >= '2026-11-01'$$,
  $$values ('2026-11-01'::date, 0.00::numeric, -80000.00::numeric, -80000.00::numeric),
           ('2026-12-01'::date, 40000.00, -40000.00, -40000.00), ('2027-01-01'::date, 0.00, -40000.00, -40000.00)$$,
  'financiamento pendente excluído: principal igual ao conservador');
select is((select previsto_financiamento_pendente from marts.fluxo_projetado_mensal
            where centro_custo_id = '7d100000-0000-4000-8000-0000000000a1' and competencia = '2026-11-01'),
  50000.00::numeric(18,2), 'financiamento pendente excluído continua na coluna informativa');
select pg_temp.parametros('{"caixa.financiamento_pendente": "incluir"}', '7d100000-0000-4000-8000-0000000000a1');
select results_eq($$select entradas from pg_temp.mes('2026-11-01')$$, $$values (50000.00::numeric)$$,
  'financiamento pendente: obra que inclui vence o tenant');
delete from app.parametro_valor where tenant_id = '7d000000-0000-4000-8000-00000000000a';

select pg_temp.parametros('{"caixa.liberacao_pendente": "incluir"}');
select results_eq(
  $$select competencia, credito from pg_temp.fluxo() where credito <> 0$$,
  $$values ('2026-12-01'::date, 40000.00::numeric), ('2027-01-01'::date, 30000.00)$$,
  'liberação pendente incluída na data prevista; as vencidas continuam fora');
select pg_temp.parametros('{"caixa.liberacao_pendente": "excluir"}', '7d100000-0000-4000-8000-0000000000a1');
select results_eq($$select competencia, credito from pg_temp.fluxo() where credito <> 0$$,
  $$values ('2026-12-01'::date, 40000.00::numeric)$$, 'liberação pendente: obra que exclui vence o tenant');
delete from app.parametro_valor where tenant_id = '7d000000-0000-4000-8000-00000000000a';

select pg_temp.parametros('{"caixa.liberacao_atrasada": "mes_referencia"}');
select results_eq($$select credito, entradas from pg_temp.mes('2026-09-01')$$,
  $$values (15000.00::numeric, 15000.00::numeric)$$, 'liberação vencida no mês de referência: só a prevista');
select pg_temp.parametros('{"caixa.liberacao_pendente": "incluir"}');
select results_eq($$select credito from pg_temp.mes('2026-09-01')$$, $$values (20000.00::numeric)$$,
  'liberação vencida com pendente incluída: prevista e pendente vencidas entram');
select pg_temp.parametros('{"caixa.liberacao_atrasada": "excluir"}', '7d100000-0000-4000-8000-0000000000a1');
select results_eq($$select credito from pg_temp.mes('2026-09-01')$$, $$values (0.00::numeric)$$,
  'liberação vencida: obra que exclui vence o tenant');
delete from app.parametro_valor where tenant_id = '7d000000-0000-4000-8000-00000000000a';

select pg_temp.parametros('{"caixa.custo_sem_titulo_passado": "ignorar"}');
select results_eq($$select competencia, custo from pg_temp.fluxo() where custo <> 0$$,
  $$values ('2026-10-01'::date, 45000.00::numeric)$$, 'custo sem título de agosto ignorado: só outubro');
select results_eq(
  $$select custo_sem_titulo_total, custo_sem_titulo_distribuido_total, custo_sem_titulo_nao_distribuido, exposicao_parcial
    from marts.resumo_projecao_obra where centro_custo_id = '7d100000-0000-4000-8000-0000000000a1'$$,
  $$values (90000.00::numeric(18,2), 45000.00::numeric(18,2), 45000.00::numeric(18,2), true)$$,
  'custo ignorado fica como não distribuído e a exposição parcial');
select pg_temp.parametros('{"caixa.custo_sem_titulo_passado": "mes_referencia"}', '7d100000-0000-4000-8000-0000000000a1');
select results_eq($$select competencia, custo from pg_temp.fluxo() where custo <> 0$$,
  $$values ('2026-09-01'::date, 45000.00::numeric), ('2026-10-01'::date, 45000.00)$$,
  'custo sem título: obra que soma no mês de referência vence o tenant');
delete from app.parametro_valor where tenant_id = '7d000000-0000-4000-8000-00000000000a';

-- R16 com os parâmetros de caixa fora do padrão: a simulação sem premissas repete o fluxo
select pg_temp.parametros('{"caixa.receber_vencido": "mes_referencia", "caixa.fracao_recuperacao_vencido": 0.5,
  "caixa.pagar_vencido": "excluir", "caixa.financiamento_pendente": "excluir", "caixa.liberacao_pendente": "incluir",
  "caixa.liberacao_atrasada": "mes_referencia", "caixa.custo_sem_titulo_passado": "ignorar"}');
select results_eq(
  $$select competencia, caixa_gerado_acumulado, total_entradas, total_saidas
    from marts.simular_fluxo('7d100000-0000-4000-8000-0000000000a1', '{}') order by 1$$,
  $$select competencia, caixa_gerado_acumulado, total_entradas, total_saidas from marts.fluxo_projetado_mensal
    where centro_custo_id = '7d100000-0000-4000-8000-0000000000a1' order by 1$$,
  'R16 com parâmetros de caixa: simulação vazia igual ao fluxo'
);
select results_eq(
  $$select * from pg_temp.fluxo()$$,
  $$values ('2026-09-01'::date, 25000.00::numeric, 0.00::numeric, 20000.00::numeric, 0.00::numeric, 25000.00::numeric,
            25000.00::numeric),
           ('2026-10-01'::date, 20000.00, 48000.00, 0.00, 45000.00, -3000.00, -3000.00),
           ('2026-11-01'::date, 0.00, 0.00, 0.00, 0.00, -3000.00, -3000.00),
           ('2026-12-01'::date, 40000.00, 0.00, 40000.00, 0.00, 37000.00, 37000.00),
           ('2027-01-01'::date, 30000.00, 0.00, 30000.00, 0.00, 67000.00, 67000.00)$$,
  'todos os parâmetros de caixa fora do padrão: números conhecidos'
);
select set_config('request.jwt.claims', '{"sub": "7d200000-0000-4000-8000-00000000f00a", "role": "authenticated"}', true);
set local role authenticated;
select set_config('teste.versao', app.registrar_versao_projecao('7d100000-0000-4000-8000-0000000000a1',
                                                                 'fotografia com parâmetros')::text, true);
select results_eq(
  $$select p.competencia, p.caixa_gerado_acumulado, p.vencido_recuperacao_prevista from app.projecao_mensal p
    where p.versao_id = current_setting('teste.versao')::uuid order by 1$$,
  $$select competencia, caixa_gerado_acumulado, vencido_recuperacao_prevista from marts.fluxo_projetado_mensal
    where centro_custo_id = '7d100000-0000-4000-8000-0000000000a1' order by 1$$,
  'fotografia da projeção guarda a recuperação do vencido'
);
reset role;
delete from app.parametro_valor where tenant_id = '7d000000-0000-4000-8000-00000000000a';

-- Data do banco no contrato: repasse em 01/08 e parcela de financiamento de 60 mil em dezembro
select pg_temp.contrato('7d100000-0000-4000-8000-0000000000a1', 8401, 300000.00, '2026-03-10', null, '2026-08-01');
select pg_temp.parcela('7d100000-0000-4000-8000-0000000000a1', 8401, 4, 'FI', '2026-12-10', 60000.00);
select results_eq(
  $$select f.etapa_efetiva, f.classificacao, r.data_prevista from marts.financiamento_contrato f
    join marts.recebivel_projetado r on r.contrato_id_origem = f.contrato_id_origem and r.tenant_id = f.tenant_id
    where f.tenant_id = '7d000000-0000-4000-8000-00000000000a' and f.contrato_id_origem = 8401$$,
  $$values ('elegivel', 'financiamento_elegivel', '2026-12-10'::date)$$,
  'data do banco como contratação (padrão): elegível, esperado no vencimento'
);
select pg_temp.parametros('{"financiamento.data_origem_significa": "repasse"}');
select results_eq(
  $$select f.etapa_efetiva, f.classificacao, r.data_prevista from marts.financiamento_contrato f
    join marts.recebivel_projetado r on r.contrato_id_origem = f.contrato_id_origem and r.tenant_id = f.tenant_id
    where f.tenant_id = '7d000000-0000-4000-8000-00000000000a' and f.contrato_id_origem = 8401$$,
  $$values ('liberado', 'financiamento_elegivel', '2026-09-15'::date)$$,
  'data do banco como repasse: liberado, esperado já na data de referência'
);
select is(
  (select previsto_financiamento_elegivel from marts.fluxo_projetado_mensal
    where centro_custo_id = '7d100000-0000-4000-8000-0000000000a1' and competencia = '2026-09-01'),
  60000.00::numeric(18,2), 'data do banco como repasse: o fluxo traz os 60 mil para setembro'
);
select throws_ok(
  $$select pg_temp.parametros('{"financiamento.data_origem_significa": "contratacao"}', '7d100000-0000-4000-8000-0000000000a1')$$,
  '23514', null, 'data do banco é só do tenant');
delete from app.parametro_valor where tenant_id = '7d000000-0000-4000-8000-00000000000a';

-- Retenção padrão: operação sem percentual (1 milhão) e outra com 2% (500 mil)
insert into app.operacao_credito_obra (id, tenant_id, centro_custo_id, modalidade, instituicao, valor_contratado,
  percentual_retencao, fonte, autor)
values ('7d400000-0000-4000-8000-000000000002', '7d000000-0000-4000-8000-00000000000a',
        '7d100000-0000-4000-8000-0000000000a1', 'plano_empresario', 'Banco de teste', 500000.00, 0.02, 'contrato de teste',
        '7d200000-0000-4000-8000-00000000d00a');
create function pg_temp.retencao() returns table (valor numeric, percentual numeric, retencao numeric, limite numeric,
  origem text) language sql as $$
  select s.valor_contratado, s.percentual_retencao, s.retencao_prevista, s.limite_antes_retencao, s.origem_retencao
  from marts.saldo_operacao_credito s where s.tenant_id = '7d000000-0000-4000-8000-00000000000a' order by 1 desc
$$;
select results_eq($$select * from pg_temp.retencao()$$,
  $$values (1000000.00::numeric, null::numeric, null::numeric, 1000000.00::numeric, null::text),
           (500000.00, 0.020000, 10000.00, 490000.00, 'operacao')$$,
  'retenção padrão nula: nenhuma retenção presumida');
select pg_temp.parametros('{"financiamento.retencao_padrao": 0.05}');
select results_eq($$select * from pg_temp.retencao()$$,
  $$values (1000000.00::numeric, 0.050000::numeric, 50000.00::numeric, 950000.00::numeric, 'padrao'),
           (500000.00, 0.020000, 10000.00, 490000.00, 'operacao')$$,
  'retenção padrão de 5%: vale só onde a operação não informa');
select pg_temp.parametros('{"financiamento.retencao_padrao": 0.10}', '7d100000-0000-4000-8000-0000000000a1');
select results_eq($$select retencao, limite from pg_temp.retencao() where origem = 'padrao'$$,
  $$values (100000.00::numeric, 900000.00::numeric)$$, 'retenção: 10% da obra vence os 5% do tenant');
delete from app.parametro_valor where tenant_id = '7d000000-0000-4000-8000-00000000000a';

-- Meta automática na obra R2 em 15/09/2026: orçamento de 2 milhões, 2.300.000,10 lançados, venda de 700 mil
-- em julho e de 300 mil em setembro, chaves em dezembro, duas unidades disponíveis de 300 e 500 mil.
select pg_temp.unidade('7d100000-0000-4000-8000-0000000000a2', 9201, 'D', 60, 300000.00, '2026-12-20');
select pg_temp.unidade('7d100000-0000-4000-8000-0000000000a2', 9202, 'D', 60, 500000.00, '2026-11-30');
select pg_temp.unidade('7d100000-0000-4000-8000-0000000000a2', 9203, 'V', 60, null, '2026-12-20');
select pg_temp.unidade('7d100000-0000-4000-8000-0000000000a2', 9204, 'V', 60, null, '2026-12-20');
select pg_temp.contrato('7d100000-0000-4000-8000-0000000000a2', 8501, 700000.00, '2026-07-10', 9203);
select pg_temp.contrato('7d100000-0000-4000-8000-0000000000a2', 8502, 300000.00, '2026-09-05', 9204);
select pg_temp.orcamento('7d100000-0000-4000-8000-0000000000a2', 'Y', 2000000.00);
select pg_temp.titulo('7d100000-0000-4000-8000-0000000000a2', 7501, '2.01.001', '2026-07-01', '2026-07-20', 2300000.10,
                      '2026-07-20');
create function pg_temp.meta() returns table (competencia date, falta numeric, valor numeric, unidades integer, motivo text)
language sql as $$
  select m.competencia, m.falta_vender, m.meta_valor_contratado, m.meta_unidades, m.motivo
  from marts.meta_automatica_mensal m where m.centro_custo_id = '7d100000-0000-4000-8000-0000000000a2' order by 1
$$;
select results_eq($$select * from pg_temp.meta()$$,
  $$values ('2026-07-01'::date, 2000000.00::numeric, 333333.33::numeric, 1, null::text),
           ('2026-08-01'::date, 1300000.00, 260000.00, 1, null), ('2026-09-01'::date, 1300000.00, 325000.00, 1, null),
           ('2026-10-01'::date, 1300000.00, 325000.00, 1, null), ('2026-11-01'::date, 1300000.00, 325000.00, 1, null),
           ('2026-12-01'::date, 1300000.00, 325000.00, 1, null)$$,
  'meta pelo custo orçado até as chaves: 1,3 milhão em quatro meses, venda de setembro conta em outubro');
select is(
  (select ticket_medio_disponivel from marts.meta_automatica_mensal
    where centro_custo_id = '7d100000-0000-4000-8000-0000000000a2' and competencia = '2026-09-01'),
  400000.00::numeric(18,2), 'meta: ticket médio das duas disponíveis');
select pg_temp.parametros('{"comercial.meta_base": "estimativa_conclusao"}');
select results_eq($$select competencia, valor, unidades from pg_temp.meta() where competencia >= '2026-09-01'$$,
  $$values ('2026-09-01'::date, 400000.03::numeric, 2), ('2026-10-01'::date, 400000.03, 2),
           ('2026-11-01'::date, 400000.03, 2), ('2026-12-01'::date, 400000.01, 2)$$,
  'meta pela estimativa até a conclusão: 1.600.000,10 em quatro meses, centavo no último');
select pg_temp.parametros('{"comercial.meta_base": "custo_orcado"}', '7d100000-0000-4000-8000-0000000000a2');
select is((select valor from pg_temp.meta() where competencia = '2026-09-01'), 325000.00::numeric,
  'meta: base da obra vence a do tenant');
delete from app.parametro_valor where tenant_id = '7d000000-0000-4000-8000-00000000000a';
select pg_temp.parametros('{"comercial.meta_horizonte": "data_propria", "comercial.meta_data_horizonte": "2026-10-31"}');
select results_eq($$select competencia, valor from pg_temp.meta()$$,
  $$values ('2026-07-01'::date, 500000.00::numeric), ('2026-08-01'::date, 433333.33),
           ('2026-09-01'::date, 650000.00), ('2026-10-01'::date, 650000.00)$$,
  'meta até data própria em outubro: 1,3 milhão em dois meses');
select pg_temp.parametros('{"comercial.meta_horizonte": "chaves"}', '7d100000-0000-4000-8000-0000000000a2');
select is((select max(competencia) from pg_temp.meta()), '2026-12-01'::date, 'meta: prazo da obra vence o do tenant');
select pg_temp.parametros('{"comercial.meta_horizonte": "data_propria", "comercial.meta_data_horizonte": null}',
                          '7d100000-0000-4000-8000-0000000000a2');
select results_eq($$select competencia, valor, motivo from pg_temp.meta()$$,
  $$values ('2026-07-01'::date, null::numeric, 'horizonte_ausente'), ('2026-08-01'::date, null, 'horizonte_ausente'),
           ('2026-09-01'::date, null, 'horizonte_ausente')$$,
  'meta com data própria em branco: sem meta, com o motivo');
delete from app.parametro_valor where tenant_id = '7d000000-0000-4000-8000-00000000000a';

select is(
  (select meta_unidades from marts.visao_gerencial_mensal
    where centro_custo_id = '7d100000-0000-4000-8000-0000000000a2' and competencia = '2026-09-01'),
  null::integer, 'meta manual (padrão): sem versão de meta, a visão fica sem meta');
select pg_temp.parametros('{"comercial.meta_metodo": "automatica"}');
select results_eq(
  $$select competencia, meta_unidades, meta_valor_contratado, vendas_unidades from marts.visao_gerencial_mensal
    where centro_custo_id = '7d100000-0000-4000-8000-0000000000a2' order by 1$$,
  $$values ('2026-07-01'::date, 1, 333333.33::numeric(18,2), 1), ('2026-08-01'::date, 1, 260000.00, 0),
           ('2026-09-01'::date, 1, 325000.00, 1)$$,
  'meta automática: a visão gerencial usa a meta calculada');
select results_eq(
  $$select competencia, causa_codigo, quantidade, valor, origem_dado from marts.explicacao_desvio
    where centro_custo_id = '7d100000-0000-4000-8000-0000000000a2' and causa_codigo like 'vendas%'$$,
  $$values ('2026-08-01'::date, 'vendas_abaixo_meta', -1, -260000.00::numeric(18,2), 'origem')$$,
  'meta automática: agosto sem venda aparece como desvio');
select pg_temp.parametros('{"comercial.meta_metodo": "manual"}', '7d100000-0000-4000-8000-0000000000a2');
select is(
  (select count(*) from marts.visao_gerencial_mensal
    where centro_custo_id = '7d100000-0000-4000-8000-0000000000a2' and meta_unidades is not null),
  0::bigint, 'meta: obra manual vence o tenant automático');
delete from app.parametro_valor where tenant_id = '7d000000-0000-4000-8000-00000000000a';

-- Fluxo consolidado: R1 vai até janeiro de 2027 e R2 até setembro de 2026
select results_eq(
  $$select competencia, eh_passado, total_entradas, total_saidas, saldo_mes, caixa_gerado_acumulado,
           necessidade_aporte_acumulada, caixa_gerado_acumulado_conservador
    from marts.fluxo_projetado_consolidado where tenant_id = '7d000000-0000-4000-8000-00000000000a' order by 1$$,
  $$select competencia, bool_and(eh_passado), sum(total_entradas), sum(total_saidas), sum(saldo_mes),
           (sum(sum(saldo_mes)) over (order by competencia))::numeric(18,2),
           greatest(-sum(sum(saldo_mes)) over (order by competencia), 0)::numeric(18,2),
           (sum(sum(caixa_gerado_acumulado_conservador) - sum(coalesce(conservador_anterior, 0))) over (order by competencia))::numeric(18,2)
    from (select f.*, lag(f.caixa_gerado_acumulado_conservador) over (partition by f.centro_custo_id order by f.competencia)
                        as conservador_anterior
          from marts.fluxo_projetado_mensal f where f.tenant_id = '7d000000-0000-4000-8000-00000000000a') x
    group by competencia order by 1$$,
  'consolidado: soma mensal das obras e acumulado corrido sobre a soma'
);
select is(
  (select caixa_gerado_acumulado from marts.fluxo_projetado_consolidado
    where tenant_id = '7d000000-0000-4000-8000-00000000000a' and competencia = '2027-01-01'),
  (select sum(f.caixa_gerado_acumulado) from marts.fluxo_projetado_mensal f
    where f.tenant_id = '7d000000-0000-4000-8000-00000000000a'
      and f.competencia = (select max(g.competencia) from marts.fluxo_projetado_mensal g where g.centro_custo_id = f.centro_custo_id)),
  'consolidado: no último mês, o acumulado leva o saldo final da obra que já terminou'
);
select results_eq(
  $$select competencia, quantidade_obras from marts.fluxo_projetado_consolidado
    where tenant_id = '7d000000-0000-4000-8000-00000000000a' and competencia in ('2026-07-01', '2026-09-01', '2027-01-01')
    order by 1$$,
  $$values ('2026-07-01'::date, 1), ('2026-09-01'::date, 2), ('2027-01-01'::date, 1)$$,
  'consolidado: só obras, contadas no mês'
);

-- Padrões da simulação: '{}' devolve as mesmas premissas de antes; venda sem composição usa a da obra
select pg_temp.unidade('7d100000-0000-4000-8000-0000000000a1', 9105, 'D', 60, 100000.00);
select pg_temp.unidade('7d100000-0000-4000-8000-0000000000a1', 9106, 'D', 60, 100000.00);
select is(
  (select distinct premissas from marts.simular_fluxo('7d100000-0000-4000-8000-0000000000a1', '{}')),
  '{"composicao": null, "novas_vendas": [], "custo_campanha": [], "desconto_tabela": 0, "fator_cronograma": 1,
    "cancelar_contratos": [], "deslocamento_cronograma_meses": 0, "atraso_liberacao_bancaria_meses": 0,
    "meses_ate_liberacao_financiamento": null}'::jsonb,
  'simulação vazia: premissas iguais às de antes dos parâmetros'
);
select pg_temp.parametros('{"simulacao.desconto": 0.05, "simulacao.fracao_entrada": 0.2, "simulacao.fracao_parcelas": 0.3,
  "simulacao.fracao_financiamento": 0.5, "simulacao.quantidade_parcelas": 10, "simulacao.meses_ate_liberacao": 2}');
select results_eq(
  $$select competencia, caixa_gerado_acumulado, novas_vendas_valor, premissas - 'novas_vendas'
    from marts.simular_fluxo('7d100000-0000-4000-8000-0000000000a1', '{"novas_vendas": [{"competencia": "2026-10-01", "quantidade": 1}]}')$$,
  $$select competencia, caixa_gerado_acumulado, novas_vendas_valor, premissas - 'novas_vendas'
    from marts.simular_fluxo('7d100000-0000-4000-8000-0000000000a1', '{"novas_vendas": [{"competencia": "2026-10-01", "quantidade": 1}],
      "desconto_tabela": 0.05, "composicao": {"entrada": 0.2, "parcelas_mensais": 0.3, "quantidade_parcelas_mensais": 10,
      "financiamento": 0.5}, "meses_ate_liberacao_financiamento": 2}')$$,
  'simulação: sem composição, desconto e prazo, valem os do tenant'
);
select is(
  (select novas_vendas_valor from marts.simular_fluxo('7d100000-0000-4000-8000-0000000000a1',
     '{"novas_vendas": [{"competencia": "2026-10-01", "quantidade": 1}]}') where competencia = '2026-10-01'),
  95000.00::numeric(18,2), 'simulação: ticket de 100 mil com 5% de desconto do tenant'
);
select pg_temp.parametros('{"simulacao.desconto": 0.1, "simulacao.fracao_entrada": 1, "simulacao.fracao_parcelas": 0,
  "simulacao.fracao_financiamento": 0}', '7d100000-0000-4000-8000-0000000000a1');
select results_eq(
  $$select novas_vendas_valor, entradas_novas_vendas_direta, (premissas -> 'desconto_tabela')::numeric,
           premissas -> 'composicao' ->> 'entrada'
    from marts.simular_fluxo('7d100000-0000-4000-8000-0000000000a1', '{"novas_vendas": [{"competencia": "2026-10-01", "quantidade": 1}]}')
    where competencia = '2026-10-01'$$,
  $$values (90000.00::numeric(18,2), 90000.00::numeric(18,2), 0.1::numeric, '1')$$,
  'simulação: desconto e composição da obra vencem os do tenant'
);
select is(
  (select novas_vendas_valor from marts.simular_fluxo('7d100000-0000-4000-8000-0000000000a1',
     '{"novas_vendas": [{"competencia": "2026-10-01", "quantidade": 1}], "desconto_tabela": 0}') where competencia = '2026-10-01'),
  100000.00::numeric(18,2), 'simulação: premissa informada vence o parâmetro'
);
delete from app.parametro_valor where tenant_id = '7d000000-0000-4000-8000-00000000000a';

-- Subcategorias e rótulos
select pg_temp.mapa('titulo_pagar', '2.01.001', 'materiais');
select set_config('request.jwt.claims', '{"sub": "7d200000-0000-4000-8000-00000000f00a", "role": "authenticated"}', true);
set local role authenticated;
select lives_ok(
  $$insert into app.categoria_tenant (id, tenant_id, categoria_codigo, codigo, nome)
    values ('7d500000-0000-4000-8000-000000000001', '7d000000-0000-4000-8000-00000000000a', 'materiais', 'cimento', 'Cimento'),
           ('7d500000-0000-4000-8000-000000000002', '7d000000-0000-4000-8000-00000000000a', 'mao_de_obra', 'pedreiro', 'Pedreiro')$$,
  'financeiro cria subcategorias');
select throws_ok(
  $$insert into app.categoria_tenant (tenant_id, categoria_codigo, codigo, nome)
    values ('7d000000-0000-4000-8000-00000000000a', 'materiais', 'cimento', 'Cimento de novo')$$,
  '23505', null, 'código de subcategoria repetido no tenant');
select throws_ok(
  $$insert into app.categoria_tenant (tenant_id, categoria_codigo, codigo, nome)
    values ('7d000000-0000-4000-8000-00000000000a', 'materiais', 'Cimento Novo', 'Cimento')$$,
  '23514', null, 'código de subcategoria fora do formato');
select lives_ok(
  $$update app.mapa_conta_origem set subcategoria_id = '7d500000-0000-4000-8000-000000000001'
    where tenant_id = '7d000000-0000-4000-8000-00000000000a' and conta_origem = '2.01.001'$$,
  'conta de materiais ligada à subcategoria cimento');
select throws_ok(
  $$update app.mapa_conta_origem set subcategoria_id = '7d500000-0000-4000-8000-000000000002'
    where tenant_id = '7d000000-0000-4000-8000-00000000000a' and conta_origem = '2.01.001'$$,
  '23514', null, 'subcategoria de outra categoria global é recusada');
select throws_ok(
  $$update app.categoria_tenant set categoria_codigo = 'projetos' where id = '7d500000-0000-4000-8000-000000000001'$$,
  '23514', null, 'subcategoria com contas não troca de categoria global');
select lives_ok(
  $$update app.categoria_tenant set ativa = false where id = '7d500000-0000-4000-8000-000000000001'$$,
  'subcategoria desativada');
select throws_ok(
  $$insert into app.mapa_conta_origem (tenant_id, tipo_origem, conta_origem, categoria_codigo, subcategoria_id)
    values ('7d000000-0000-4000-8000-00000000000a', 'titulo_pagar', '2.01.009', 'materiais', '7d500000-0000-4000-8000-000000000001')$$,
  '23514', null, 'subcategoria desativada não recebe conta nova');
select throws_ok(
  $$insert into app.rotulo_personalizado (tenant_id, contexto, chave, rotulo)
    values ('7d000000-0000-4000-8000-00000000000a', 'linha_dre', 'lucro_liquido', 'Lucro')$$,
  '23514', null, 'rótulo para linha que o DRE não tem');
select throws_ok(
  $$insert into app.rotulo_personalizado (tenant_id, contexto, chave, rotulo)
    values ('7d000000-0000-4000-8000-00000000000a', 'categoria', 'cimento', 'Cimento')$$,
  '23514', null, 'rótulo para categoria que não existe');
select lives_ok(
  $$insert into app.rotulo_personalizado (tenant_id, contexto, chave, rotulo)
    values ('7d000000-0000-4000-8000-00000000000a', 'categoria', 'materiais', 'Insumos')$$,
  'rótulo para categoria existente');
reset role;
select results_eq(
  $$select autor, ativa from app.categoria_tenant where id = '7d500000-0000-4000-8000-000000000001'$$,
  $$values ('7d200000-0000-4000-8000-00000000f00a'::uuid, false)$$,
  'autor da subcategoria vem do JWT');
select is(
  (select count(*) from app.auditoria_alteracao where tabela = 'app.categoria_tenant'
     and autor = '7d200000-0000-4000-8000-00000000f00a'),
  3::bigint, 'auditoria registra as duas inclusões e a desativação');
select is(
  (select sum(valor_mes) from marts.dre_mensal where centro_custo_id = '7d100000-0000-4000-8000-0000000000a1'
     and linha_codigo = 'custo_obra_incorrido'),
  -10000.00::numeric, 'subcategoria não muda o DRE: a conta continua somando em materiais');

select set_config('request.jwt.claims', '{"sub": "7d200000-0000-4000-8000-00000000c00a", "role": "authenticated"}', true);
set local role authenticated;
select throws_ok(
  $$insert into app.categoria_tenant (tenant_id, categoria_codigo, codigo, nome)
    values ('7d000000-0000-4000-8000-00000000000a', 'materiais', 'areia', 'Areia')$$,
  '42501', null, 'gerente não cria subcategoria');
select is((select count(*) from app.categoria_tenant), 2::bigint, 'gerente lê as subcategorias do tenant');
reset role;

-- Isolamento: gerente vê só a obra R1 nos parâmetros e nos consolidados; outro tenant não vê nada
select pg_temp.parametros('{"caixa.pagar_vencido": "excluir"}', '7d100000-0000-4000-8000-0000000000a2');
select pg_temp.parametros('{"comercial.meta_metodo": "automatica"}');
select set_config('request.jwt.claims', '{"sub": "7d200000-0000-4000-8000-00000000c00a", "role": "authenticated"}', true);
set local role authenticated;
select results_eq($$select centro_custo_id from app.parametros_obra$$,
  $$values ('7d100000-0000-4000-8000-0000000000a1'::uuid)$$, 'gerente: parâmetros só da própria obra');
select is((select count(*) from app.parametro_valor where centro_custo_id is not null), 0::bigint,
  'gerente não lê o valor gravado para a obra R2');
select is((select count(*) from app.parametros_tenant), 1::bigint, 'gerente lê os parâmetros do próprio tenant');
select results_eq(
  $$select competencia, caixa_gerado_acumulado from marts.fluxo_projetado_consolidado order by 1$$,
  $$select competencia, caixa_gerado_acumulado from marts.fluxo_projetado_mensal
    where centro_custo_id = '7d100000-0000-4000-8000-0000000000a1' order by 1$$,
  'gerente: consolidado é só a própria obra');
select is((select count(distinct centro_custo_id) from marts.meta_automatica_mensal), 1::bigint,
  'gerente: meta automática só da própria obra');
select is((select count(*) from marts.reconhecimento_obra_mensal where centro_custo_id <> '7d100000-0000-4000-8000-0000000000a1'),
  0::bigint, 'gerente: reconhecimento só da própria obra');
select throws_ok(
  $$select pg_temp.parametros('{"caixa.pagar_vencido": "excluir"}', '7d100000-0000-4000-8000-0000000000a1')$$,
  '42501', null, 'gerente não grava parâmetro');
reset role;
select set_config('request.jwt.claims', '{"sub": "7d200000-0000-4000-8000-00000000d00b", "role": "authenticated"}', true);
set local role authenticated;
select is((select count(*) from marts.fluxo_projetado_consolidado where tenant_id = '7d000000-0000-4000-8000-00000000000a'),
  0::bigint, 'outro tenant não vê o consolidado de R');
select is((select count(*) from app.parametros_obra where tenant_id = '7d000000-0000-4000-8000-00000000000a'),
  0::bigint, 'outro tenant não vê os parâmetros de R');
select is((select count(*) from marts.meta_automatica_mensal where tenant_id = '7d000000-0000-4000-8000-00000000000a'),
  0::bigint, 'outro tenant não vê a meta de R');
select is((select count(*) from app.categoria_tenant), 0::bigint, 'outro tenant não vê as subcategorias de R');
select is((select count(*) from app.criterio_reconhecimento_efetivo), 1::bigint, 'outro tenant vê só a própria obra no critério');
reset role;
select set_config('request.jwt.claims', '', true);
set local role anon;
select throws_ok($$select * from marts.fluxo_projetado_consolidado$$, '42501', null, 'anônimo não lê o consolidado');
select throws_ok($$select * from app.categoria_tenant$$, '42501', null, 'anônimo não lê as subcategorias');
reset role;

select * from finish();
rollback;
