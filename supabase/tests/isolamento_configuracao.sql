-- Isolamento da configuração por cliente (docs/financeiro/configuracao.md, seção 5): só diretor e financeiro
-- gravam, o valor de uma obra não aparece para quem só vê outra, outro tenant fica invisível e o histórico
-- guarda o autor do JWT.
begin;
create extension if not exists pgtap with schema extensions;
select plan(44);

insert into app.tenant (id, razao_social) values
  ('7f000000-0000-4000-8000-00000000000a', 'Construtora Configuração A'),
  ('7f000000-0000-4000-8000-00000000000b', 'Construtora Configuração B');

insert into app.centro_custo (id, tenant_id, id_origem, nome, tipo) values
  ('7d000000-0000-4000-8000-0000000000a1', '7f000000-0000-4000-8000-00000000000a', 9101, 'Obra Config 1', 'obra'),
  ('7d000000-0000-4000-8000-0000000000a2', '7f000000-0000-4000-8000-00000000000a', 9102, 'Obra Config 2', 'obra'),
  ('7d000000-0000-4000-8000-0000000000ae', '7f000000-0000-4000-8000-00000000000a', null, 'Despesas sem obra', 'empresa'),
  ('7d000000-0000-4000-8000-0000000000b1', '7f000000-0000-4000-8000-00000000000b', 9101, 'Obra Config B1', 'obra');

insert into auth.users (id, email) values
  ('7b000000-0000-4000-8000-00000000d00a', 'diretor.config@teste.invalid'),
  ('7b000000-0000-4000-8000-00000000f00a', 'financeiro.config@teste.invalid'),
  ('7b000000-0000-4000-8000-00000000c0a1', 'gerente1.config@teste.invalid'),
  ('7b000000-0000-4000-8000-00000000c0a2', 'gerente2.config@teste.invalid'),
  ('7b000000-0000-4000-8000-00000000e00a', 'leitura.config@teste.invalid'),
  ('7b000000-0000-4000-8000-00000000d00b', 'diretorb.config@teste.invalid');

insert into app.usuario_tenant (user_id, tenant_id, perfil) values
  ('7b000000-0000-4000-8000-00000000d00a', '7f000000-0000-4000-8000-00000000000a', 'diretor'),
  ('7b000000-0000-4000-8000-00000000f00a', '7f000000-0000-4000-8000-00000000000a', 'financeiro'),
  ('7b000000-0000-4000-8000-00000000c0a1', '7f000000-0000-4000-8000-00000000000a', 'gerente_obra'),
  ('7b000000-0000-4000-8000-00000000c0a2', '7f000000-0000-4000-8000-00000000000a', 'gerente_obra'),
  ('7b000000-0000-4000-8000-00000000e00a', '7f000000-0000-4000-8000-00000000000a', 'leitura'),
  ('7b000000-0000-4000-8000-00000000d00b', '7f000000-0000-4000-8000-00000000000b', 'diretor');

insert into app.usuario_centro_custo (user_id, tenant_id, centro_custo_id) values
  ('7b000000-0000-4000-8000-00000000c0a1', '7f000000-0000-4000-8000-00000000000a', '7d000000-0000-4000-8000-0000000000a1'),
  ('7b000000-0000-4000-8000-00000000c0a2', '7f000000-0000-4000-8000-00000000000a', '7d000000-0000-4000-8000-0000000000a2'),
  ('7b000000-0000-4000-8000-00000000e00a', '7f000000-0000-4000-8000-00000000000a', '7d000000-0000-4000-8000-0000000000a1');

-- Um código sem mapa em cada obra do tenant A, para a pendência por obra.
insert into raw.registro (tenant_id, endpoint, payload, hash_registro)
select '7f000000-0000-4000-8000-00000000000a', 'units', x, md5(x::text)
from jsonb_array_elements('[{"id": 91011, "enterpriseId": 9101, "commercialStock": "Z"},
                            {"id": 91012, "enterpriseId": 9101, "commercialStock": "W"},
                            {"id": 91021, "enterpriseId": 9102, "commercialStock": "Y"}]'::jsonb) x;
select staging.recarregar('7f000000-0000-4000-8000-00000000000a');

create function pg_temp.entrar(p_usuario text) returns void language sql as $$
  select set_config('request.jwt.claims', format('{"sub": "%s", "role": "authenticated"}', p_usuario), true)
$$;

-- Financeiro grava no tenant e numa obra, com autor falso que o gatilho troca
select pg_temp.entrar('7b000000-0000-4000-8000-00000000f00a');
set local role authenticated;
select lives_ok(
  $$insert into app.parametro_valor (tenant_id, codigo, valor, autor)
    values ('7f000000-0000-4000-8000-00000000000a', 'caixa.receber_vencido', '"mes_referencia"', '7b000000-0000-4000-8000-00000000d00a')$$,
  'financeiro grava valor do tenant');
select lives_ok(
  $$insert into app.parametro_valor (tenant_id, centro_custo_id, codigo, valor, autor)
    values ('7f000000-0000-4000-8000-00000000000a', '7d000000-0000-4000-8000-0000000000a2', 'caixa.fracao_recuperacao_vencido',
            '0.4', '7b000000-0000-4000-8000-00000000d00a')$$,
  'financeiro grava valor da obra 2');
select throws_ok(
  $$insert into app.parametro_valor (tenant_id, codigo, valor, autor)
    values ('7f000000-0000-4000-8000-00000000000b', 'caixa.receber_vencido', '"mes_referencia"', '7b000000-0000-4000-8000-00000000f00a')$$,
  '42501', null, 'financeiro não grava no tenant B');
reset role;
select is(
  (select autor from app.parametro_valor where tenant_id = '7f000000-0000-4000-8000-00000000000a' and codigo = 'caixa.receber_vencido'),
  '7b000000-0000-4000-8000-00000000f00a'::uuid, 'autor gravado é o do JWT, não o mandado');
select results_eq(
  $$select operacao, autor from app.auditoria_alteracao where tabela = 'app.parametro_valor'
      and tenant_id = '7f000000-0000-4000-8000-00000000000a' order by alterado_em, id$$,
  $$values ('insert', '7b000000-0000-4000-8000-00000000f00a'::uuid), ('insert', '7b000000-0000-4000-8000-00000000f00a'::uuid)$$,
  'histórico com o autor do JWT'
);

-- Diretor grava na obra 1, altera e grava mapa e rótulo
select pg_temp.entrar('7b000000-0000-4000-8000-00000000d00a');
set local role authenticated;
select lives_ok(
  $$insert into app.parametro_valor (tenant_id, centro_custo_id, codigo, valor, autor)
    values ('7f000000-0000-4000-8000-00000000000a', '7d000000-0000-4000-8000-0000000000a1', 'caixa.fracao_recuperacao_vencido',
            '0.8', '7b000000-0000-4000-8000-00000000d00a')$$,
  'diretor grava valor da obra 1');
select lives_ok(
  $$update app.parametro_valor set valor = '0.9'
    where centro_custo_id = '7d000000-0000-4000-8000-0000000000a1' and codigo = 'caixa.fracao_recuperacao_vencido'$$,
  'diretor altera valor da obra 1');
select lives_ok(
  $$update app.mapa_codigo_origem set valor = 'vendida', observacao = 'Código de vendida no piloto'
    where tenant_id = '7f000000-0000-4000-8000-00000000000a' and dominio = 'situacao_unidade' and codigo_origem = 'R'$$,
  'diretor remapeia código');
select lives_ok(
  $$insert into app.mapa_codigo_origem (tenant_id, dominio, codigo_origem, valor)
    values ('7f000000-0000-4000-8000-00000000000a', 'situacao_unidade', 'Z', 'disponivel')$$,
  'diretor mapeia código novo');
select lives_ok(
  $$insert into app.rotulo_personalizado (tenant_id, contexto, chave, rotulo, autor)
    values ('7f000000-0000-4000-8000-00000000000a', 'indicador', 'exposicao_maxima', 'Maior aporte', '7b000000-0000-4000-8000-00000000f00a')$$,
  'diretor grava rótulo');
select is((select count(*) from app.auditoria_alteracao where tenant_id = '7f000000-0000-4000-8000-00000000000a'),
  7::bigint, 'diretor vê o histórico do tenant');
reset role;
select results_eq(
  $$select tabela, operacao, autor from app.auditoria_alteracao
    where tenant_id = '7f000000-0000-4000-8000-00000000000a' and tabela in ('app.mapa_codigo_origem', 'app.rotulo_personalizado')
    order by alterado_em, id$$,
  $$values ('app.mapa_codigo_origem', 'update', '7b000000-0000-4000-8000-00000000d00a'::uuid),
           ('app.mapa_codigo_origem', 'insert', '7b000000-0000-4000-8000-00000000d00a'::uuid),
           ('app.rotulo_personalizado', 'insert', '7b000000-0000-4000-8000-00000000d00a'::uuid)$$,
  'mapa e rótulo no histórico com o autor do JWT'
);

-- Gerente da obra 1: lê, não grava
select pg_temp.entrar('7b000000-0000-4000-8000-00000000c0a1');
set local role authenticated;
select throws_ok(
  $$insert into app.parametro_valor (tenant_id, centro_custo_id, codigo, valor, autor)
    values ('7f000000-0000-4000-8000-00000000000a', '7d000000-0000-4000-8000-0000000000a1', 'caixa.pagar_vencido', '"excluir"',
            '7b000000-0000-4000-8000-00000000c0a1')$$,
  '42501', null, 'gerente não grava valor');
update app.parametro_valor set valor = '0.1' where codigo = 'caixa.fracao_recuperacao_vencido';
delete from app.parametro_valor where codigo = 'caixa.receber_vencido';
select throws_ok(
  $$insert into app.mapa_codigo_origem (tenant_id, dominio, codigo_origem, valor)
    values ('7f000000-0000-4000-8000-00000000000a', 'situacao_contrato', '9', 'ativo')$$,
  '42501', null, 'gerente não grava mapa');
update app.mapa_codigo_origem set valor = 'entrada_direta' where codigo_origem = 'FI';
select throws_ok(
  $$insert into app.rotulo_personalizado (tenant_id, contexto, chave, rotulo, autor)
    values ('7f000000-0000-4000-8000-00000000000a', 'categoria', 'marketing', 'Publicidade', '7b000000-0000-4000-8000-00000000c0a1')$$,
  '42501', null, 'gerente não grava rótulo');
select results_eq(
  $$select centro_custo_id, codigo, valor from app.parametro_valor order by centro_custo_id nulls first$$,
  $$values (null::uuid, 'caixa.receber_vencido', '"mes_referencia"'::jsonb),
           ('7d000000-0000-4000-8000-0000000000a1'::uuid, 'caixa.fracao_recuperacao_vencido', '0.9'::jsonb)$$,
  'gerente vê o valor do tenant e o da própria obra; update e delete dele não mudaram nada'
);
select results_eq(
  $$select centro_custo_id, caixa__receber_vencido, caixa__fracao_recuperacao_vencido from app.parametros_obra$$,
  $$values ('7d000000-0000-4000-8000-0000000000a1'::uuid, 'mes_referencia', 0.900000::numeric(9,6))$$,
  'parametros_obra do gerente só tem a obra dele'
);
select is((select count(*) from app.configuracao_efetiva where centro_custo_id = '7d000000-0000-4000-8000-0000000000a2'), 0::bigint,
  'configuração efetiva da obra 2 invisível para o gerente da obra 1');
select is((select count(*) from app.parametros_tenant), 1::bigint, 'gerente vê o nível do próprio tenant');
select is((select valor from app.mapa_codigo_origem where codigo_origem = 'FI'), 'financiamento_comprador',
  'gerente lê o mapa e o update dele não mudou nada');
select is((select count(*) from app.rotulo_personalizado), 1::bigint, 'gerente lê o rótulo do tenant');
select results_eq(
  $$select centro_custo_id, codigo_origem from marts.pendencia_codigo_origem$$,
  $$values ('7d000000-0000-4000-8000-0000000000a1'::uuid, 'W')$$,
  'gerente vê só a pendência da própria obra'
);
select is((select count(*) from app.auditoria_alteracao), 0::bigint, 'gerente não vê o histórico');
select is(app.data_referencia(), (now() at time zone 'America/Sao_Paulo')::date, 'gerente lê a data de referência');
select throws_ok($$insert into app.parametro (codigo, grupo, nome, descricao, tipo, padrao, escopo, ordem)
    values ('exibicao.cor', 'exibicao', 'Cor', 'Cor', 'texto', '"azul"', 'tenant', 999)$$,
  '42501', null, 'catálogo é só leitura');
select throws_ok($$insert into app.valor_codigo_origem (dominio, valor, rotulo, ordem) values ('situacao_unidade', 'alugada', 'Alugada', 99)$$,
  '42501', null, 'valores aceitos do mapa são só leitura');
select throws_ok('select app.gerar_views_parametros()', '42501', null, 'usuário não recria as views de parâmetros');
select throws_ok($$select app.semear_mapa_codigo_origem('7f000000-0000-4000-8000-00000000000b')$$, '42501', null,
  'usuário não semeia o mapa de outro tenant');

-- Gerente da obra 2
reset role;
select pg_temp.entrar('7b000000-0000-4000-8000-00000000c0a2');
set local role authenticated;
select results_eq(
  $$select centro_custo_id, caixa__fracao_recuperacao_vencido from app.parametros_obra$$,
  $$values ('7d000000-0000-4000-8000-0000000000a2'::uuid, 0.400000::numeric(9,6))$$,
  'gerente da obra 2 vê o valor da obra 2 e não o da obra 1'
);
select is((select count(*) from app.parametro_valor where centro_custo_id = '7d000000-0000-4000-8000-0000000000a1'), 0::bigint,
  'valor da obra 1 invisível para o gerente da obra 2');
select results_eq(
  $$select codigo_origem from marts.pendencia_codigo_origem$$,
  $$values ('Y')$$,
  'gerente da obra 2 vê só a pendência da obra 2'
);

-- Leitura
reset role;
select pg_temp.entrar('7b000000-0000-4000-8000-00000000e00a');
set local role authenticated;
select throws_ok(
  $$insert into app.parametro_valor (tenant_id, codigo, valor, autor)
    values ('7f000000-0000-4000-8000-00000000000a', 'exibicao.meses_grafico', '48', '7b000000-0000-4000-8000-00000000e00a')$$,
  '42501', null, 'leitura não grava valor');
select throws_ok(
  $$insert into app.mapa_codigo_origem (tenant_id, dominio, codigo_origem, valor)
    values ('7f000000-0000-4000-8000-00000000000a', 'situacao_contrato', '9', 'ativo')$$,
  '42501', null, 'leitura não grava mapa');
select is((select count(*) from app.parametro), 29::bigint, 'leitura vê o catálogo');

-- Diretor do tenant B
reset role;
select pg_temp.entrar('7b000000-0000-4000-8000-00000000d00b');
set local role authenticated;
select is(
  (select count(*) from app.parametro_valor where tenant_id = '7f000000-0000-4000-8000-00000000000a')
  + (select count(*) from app.mapa_codigo_origem where tenant_id = '7f000000-0000-4000-8000-00000000000a')
  + (select count(*) from app.rotulo_personalizado where tenant_id = '7f000000-0000-4000-8000-00000000000a')
  + (select count(*) from app.parametros_obra where tenant_id = '7f000000-0000-4000-8000-00000000000a')
  + (select count(*) from app.parametros_tenant where tenant_id = '7f000000-0000-4000-8000-00000000000a')
  + (select count(*) from app.configuracao_efetiva where tenant_id = '7f000000-0000-4000-8000-00000000000a')
  + (select count(*) from marts.pendencia_codigo_origem where tenant_id = '7f000000-0000-4000-8000-00000000000a')
  + (select count(*) from app.auditoria_alteracao where tenant_id = '7f000000-0000-4000-8000-00000000000a'),
  0::bigint, 'tenant A invisível para o diretor B'
);
select results_eq(
  $$select caixa__receber_vencido, caixa__fracao_recuperacao_vencido from app.parametros_tenant$$,
  $$values ('excluir', 1.000000::numeric(9,6))$$,
  'diretor B vê só o próprio tenant, com o padrão'
);
select is((select count(*) from app.mapa_codigo_origem), 14::bigint, 'diretor B vê o mapa padrão do próprio tenant');
update app.parametro_valor set valor = '"excluir"' where tenant_id = '7f000000-0000-4000-8000-00000000000a';
delete from app.mapa_codigo_origem where tenant_id = '7f000000-0000-4000-8000-00000000000a';
select throws_ok(
  $$insert into app.parametro_valor (tenant_id, centro_custo_id, codigo, valor, autor)
    values ('7f000000-0000-4000-8000-00000000000b', '7d000000-0000-4000-8000-0000000000a1', 'caixa.pagar_vencido', '"excluir"',
            '7b000000-0000-4000-8000-00000000d00b')$$,
  '23514', null, 'diretor B não grava valor na obra do tenant A');
reset role;
select results_eq(
  $$select (select count(*) from app.parametro_valor where tenant_id = '7f000000-0000-4000-8000-00000000000a' and valor = '"excluir"'),
           (select count(*) from app.mapa_codigo_origem where tenant_id = '7f000000-0000-4000-8000-00000000000a')$$,
  $$values (0::bigint, 15::bigint)$$,
  'update e delete do diretor B não alcançaram o tenant A'
);

-- Anônimo
select set_config('request.jwt.claims', '', true);
set local role anon;
select throws_ok('select count(*) from app.parametro', '42501', null, 'anônimo não lê o catálogo');
select throws_ok('select count(*) from app.parametros_obra', '42501', null, 'anônimo não lê a configuração');
select throws_ok('select app.data_referencia()', '42501', null, 'anônimo não chama a data de referência');
reset role;

select ok(
  not has_function_privilege('authenticated', 'app.gerar_views_parametros()', 'execute')
  and not has_function_privilege('authenticated', 'app.semear_mapa_codigo_origem(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'app.semear_tenant_novo()', 'execute')
  and not has_function_privilege('authenticated', 'app.validar_parametro_valor()', 'execute')
  and not has_function_privilege('authenticated', 'app.conferir_composicao_simulacao()', 'execute')
  and not has_function_privilege('authenticated', 'app.validar_mapa_codigo_origem()', 'execute')
  and not has_function_privilege('authenticated', 'staging.normalizar_parcela_receber()', 'execute')
  and not has_function_privilege('authenticated', 'staging.normalizar_contrato_venda()', 'execute')
  and not has_function_privilege('anon', 'app.fuso_horario_atual()', 'execute'),
  'funções internas sem execute para quem não deve chamar'
);
select ok(
  has_function_privilege('authenticated', 'app.erro_valor_parametro(text, jsonb)', 'execute')
  and has_function_privilege('authenticated', 'app.fuso_horario_atual()', 'execute')
  and has_function_privilege('service_role', 'app.data_referencia()', 'execute'),
  'funções de leitura liberadas'
);

select * from finish();
rollback;
