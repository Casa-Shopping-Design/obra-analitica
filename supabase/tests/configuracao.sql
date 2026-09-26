-- Configuração por cliente (docs/financeiro/configuracao.md, seções 2 e 5, parte da migration 0007):
-- catálogo, resolução obra > tenant > padrão, validação, data de referência pelo fuso do tenant,
-- limite da carga, mapa de códigos da origem com pendências e rótulos personalizados.
begin;
create extension if not exists pgtap with schema extensions;
select plan(89);

insert into app.tenant (id, razao_social) values
  ('7f000000-0000-4000-8000-00000000000a', 'Construtora Configuração A'),
  ('7f000000-0000-4000-8000-00000000000b', 'Construtora Configuração B');

insert into app.centro_custo (id, tenant_id, id_origem, nome, tipo) values
  ('7d000000-0000-4000-8000-0000000000a1', '7f000000-0000-4000-8000-00000000000a', 9101, 'Obra Config 1', 'obra'),
  ('7d000000-0000-4000-8000-0000000000a2', '7f000000-0000-4000-8000-00000000000a', 9102, 'Obra Config 2', 'obra'),
  ('7d000000-0000-4000-8000-0000000000ae', '7f000000-0000-4000-8000-00000000000a', null, 'Despesas sem obra', 'empresa'),
  ('7d000000-0000-4000-8000-0000000000b1', '7f000000-0000-4000-8000-00000000000b', 9101, 'Obra Config B1', 'obra');

-- Gravação como dono do banco: sem JWT o gatilho mantém o autor informado.
create function pg_temp.gravar(p_tenant text, p_centro text, p_codigo text, p_valor jsonb, p_observacao text default null)
returns void language sql as $$
  insert into app.parametro_valor (tenant_id, centro_custo_id, codigo, valor, observacao, autor)
  values (p_tenant::uuid, p_centro::uuid, p_codigo, p_valor, p_observacao, '7b000000-0000-4000-8000-0000000000aa')
  on conflict (tenant_id, centro_custo_id, codigo) do update set valor = excluded.valor, observacao = excluded.observacao
$$;

-- Catálogo
select is((select count(*) from app.parametro), 29::bigint, 'catálogo com os 29 parâmetros da seção 3');
select is((select count(*) from app.parametro where app.erro_valor_parametro(codigo, padrao) is not null), 0::bigint,
  'todo padrão do catálogo passa na própria validação');
select is((select count(distinct grupo) from app.parametro), 9::bigint, 'os nove grupos têm parâmetro');
select results_eq(
  $$select codigo, padrao from app.parametro
    where codigo in ('negocio.fuso_horario', 'alerta.carga_desatualizada_horas', 'reconhecimento.base_fracao_vendida',
                     'dre.competencia_titulo', 'caixa.pagar_vencido', 'financiamento.retencao_padrao', 'exibicao.meses_grafico',
                     'exibicao.periodo_padrao')
    order by codigo$$,
  $$values ('alerta.carga_desatualizada_horas', '26'::jsonb), ('caixa.pagar_vencido', '"mes_referencia"'),
           ('dre.competencia_titulo', '"emissao"'), ('exibicao.meses_grafico', '36'), ('exibicao.periodo_padrao', '"ano_ate_mes"'),
           ('financiamento.retencao_padrao', 'null'), ('negocio.fuso_horario', '"America/Sao_Paulo"'),
           ('reconhecimento.base_fracao_vendida', '"unidades"')$$,
  'padrões reproduzem o comportamento anterior'
);
select is(
  (select sum((padrao #>> '{}')::numeric) from app.parametro
    where codigo in ('simulacao.fracao_entrada', 'simulacao.fracao_parcelas', 'simulacao.fracao_financiamento')),
  1.00, 'frações padrão da simulação somam 1'
);
select is(
  (select count(*) from pg_attribute where attrelid = 'app.parametros_obra'::regclass and attnum > 0 and not attisdropped),
  31::bigint, 'parametros_obra: tenant, centro e uma coluna por parâmetro'
);
select is(
  (select array_agg(attname::text order by attnum) from pg_attribute
    where attrelid = 'app.parametros_tenant'::regclass and attnum > 1 and not attisdropped),
  (select array_agg(attname::text order by attnum) from pg_attribute
    where attrelid = 'app.parametros_obra'::regclass and attnum > 2 and not attisdropped),
  'parametros_tenant tem as mesmas colunas de parâmetro na mesma ordem'
);
select is(format_type(atttypid, atttypmod), 'numeric(9,6)', 'fração tipada como numeric(9,6)')
from pg_attribute where attrelid = 'app.parametros_obra'::regclass and attname = 'reconhecimento__cobertura_minima';
select is(
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'app' and c.relname in ('parametro', 'parametro_valor', 'valor_codigo_origem', 'mapa_codigo_origem',
                                              'rotulo_personalizado')
      and c.relrowsecurity and c.relforcerowsecurity),
  5::bigint, 'RLS ligado e forçado nas cinco tabelas novas'
);
select is(
  (select count(*) from (
     select tablename, cmd from pg_policies
     where schemaname = 'app' and tablename in ('parametro', 'parametro_valor', 'valor_codigo_origem', 'mapa_codigo_origem',
                                                'rotulo_personalizado')
     group by 1, 2 having count(*) > 1) x),
  0::bigint, 'uma política por tabela e ação'
);
select ok(
  (select bool_and(coalesce(c.reloptions @> array['security_invoker=true'], false)) from pg_class c
    where c.oid in ('app.parametros_obra'::regclass, 'app.parametros_tenant'::regclass, 'app.configuracao_efetiva'::regclass,
                    'marts.mapa_unidades'::regclass, 'marts.estoque_atual'::regclass,
                    'marts.pendencia_codigo_origem'::regclass)),
  'views novas e recriadas com security_invoker'
);

-- Resolução obra > tenant > padrão
select results_eq(
  $$select centro_custo_id, caixa__receber_vencido, reconhecimento__cobertura_minima, exibicao__meses_grafico,
           financiamento__retencao_padrao, simulacao__quantidade_parcelas
    from app.parametros_obra where tenant_id = '7f000000-0000-4000-8000-00000000000a' order by centro_custo_id$$,
  $$values ('7d000000-0000-4000-8000-0000000000a1'::uuid, 'excluir', 1.000000::numeric(9,6), 36, null::numeric(9,6), 24),
           ('7d000000-0000-4000-8000-0000000000a2'::uuid, 'excluir', 1.000000, 36, null, 24),
           ('7d000000-0000-4000-8000-0000000000ae'::uuid, 'excluir', 1.000000, 36, null, 24)$$,
  'sem valor gravado, toda obra fica com o padrão'
);
select pg_temp.gravar('7f000000-0000-4000-8000-00000000000a', null, 'caixa.receber_vencido', '"mes_referencia"');
select pg_temp.gravar('7f000000-0000-4000-8000-00000000000a', null, 'exibicao.meses_grafico', '60');
select results_eq(
  $$select tenant_id, caixa__receber_vencido, exibicao__meses_grafico from app.parametros_tenant
    where tenant_id in ('7f000000-0000-4000-8000-00000000000a', '7f000000-0000-4000-8000-00000000000b') order by 1$$,
  $$values ('7f000000-0000-4000-8000-00000000000a'::uuid, 'mes_referencia', 60),
           ('7f000000-0000-4000-8000-00000000000b'::uuid, 'excluir', 36)$$,
  'valor do tenant vale só para o próprio tenant'
);
select pg_temp.gravar('7f000000-0000-4000-8000-00000000000a', '7d000000-0000-4000-8000-0000000000a1',
  'caixa.receber_vencido', '"excluir"');
select results_eq(
  $$select centro_custo_id, caixa__receber_vencido from app.parametros_obra
    where tenant_id = '7f000000-0000-4000-8000-00000000000a' and centro_custo_id <> '7d000000-0000-4000-8000-0000000000ae'
    order by 1$$,
  $$values ('7d000000-0000-4000-8000-0000000000a1'::uuid, 'excluir'), ('7d000000-0000-4000-8000-0000000000a2'::uuid, 'mes_referencia')$$,
  'valor da obra vence o do tenant; a outra obra fica com o do tenant'
);
select is((select caixa__receber_vencido from app.parametros_tenant where tenant_id = '7f000000-0000-4000-8000-00000000000a'),
  'mes_referencia', 'valor da obra não muda o nível do tenant');
select results_eq(
  $$select centro_custo_id, valor, origem, autor from app.configuracao_efetiva
    where tenant_id = '7f000000-0000-4000-8000-00000000000a' and codigo = 'caixa.receber_vencido'
    order by centro_custo_id nulls first$$,
  $$values (null::uuid, '"mes_referencia"'::jsonb, 'tenant', '7b000000-0000-4000-8000-0000000000aa'::uuid),
           ('7d000000-0000-4000-8000-0000000000a1'::uuid, '"excluir"'::jsonb, 'obra', '7b000000-0000-4000-8000-0000000000aa'::uuid),
           ('7d000000-0000-4000-8000-0000000000a2'::uuid, '"mes_referencia"'::jsonb, 'tenant', '7b000000-0000-4000-8000-0000000000aa'::uuid)$$,
  'configuração efetiva diz de onde veio cada valor, só para obras'
);
select results_eq(
  $$select valor, origem, autor from app.configuracao_efetiva
    where tenant_id = '7f000000-0000-4000-8000-00000000000b' and codigo = 'caixa.receber_vencido' and centro_custo_id is null$$,
  $$values ('"excluir"'::jsonb, 'padrao', null::uuid)$$,
  'sem valor gravado a origem é o padrão, sem autor'
);
select is((select count(*) from app.configuracao_efetiva
            where tenant_id = '7f000000-0000-4000-8000-00000000000a' and codigo = 'exibicao.meses_grafico'),
  1::bigint, 'parâmetro só de tenant aparece uma vez, sem linha por obra');
delete from app.parametro_valor
where tenant_id = '7f000000-0000-4000-8000-00000000000a' and centro_custo_id = '7d000000-0000-4000-8000-0000000000a1';
select is((select caixa__receber_vencido from app.parametros_obra where centro_custo_id = '7d000000-0000-4000-8000-0000000000a1'),
  'mes_referencia', 'excluir o valor da obra volta ao do tenant');
delete from app.parametro_valor where tenant_id = '7f000000-0000-4000-8000-00000000000a' and codigo = 'caixa.receber_vencido';
select is((select caixa__receber_vencido from app.parametros_obra where centro_custo_id = '7d000000-0000-4000-8000-0000000000a1'),
  'excluir', 'excluir o valor do tenant volta ao padrão');
select is(
  (select count(*) from app.auditoria_alteracao where tabela = 'app.parametro_valor'
     and tenant_id = '7f000000-0000-4000-8000-00000000000a' and operacao = 'delete'),
  2::bigint, 'volta ao padrão fica no histórico'
);

-- Validação
select throws_ok($$select pg_temp.gravar('7f000000-0000-4000-8000-00000000000a', null, 'exibicao.meses_grafico', '"36"')$$,
  '23514', 'Meses nos gráficos de fluxo precisa ser um número', 'tipo errado');
select throws_ok($$select pg_temp.gravar('7f000000-0000-4000-8000-00000000000a', null, 'exibicao.meses_grafico', '36.5')$$,
  '23514', 'Meses nos gráficos de fluxo precisa ser um número inteiro', 'inteiro com casas decimais');
select throws_ok($$select pg_temp.gravar('7f000000-0000-4000-8000-00000000000a', null, 'exibicao.periodo_padrao', '"semestre"')$$,
  '23514', 'Período inicial dos demonstrativos não aceita a opção semestre', 'opção inexistente');
select throws_ok($$select pg_temp.gravar('7f000000-0000-4000-8000-00000000000a', null, 'exibicao.meses_grafico', '6')$$,
  '23514', 'Meses nos gráficos de fluxo precisa ficar entre 12 e 120', 'abaixo da faixa');
select throws_ok($$select pg_temp.gravar('7f000000-0000-4000-8000-00000000000a', null, 'simulacao.desconto', '0.6')$$,
  '23514', 'Desconto sobre a tabela precisa ficar entre 0 e 0.5', 'acima da faixa');
select throws_ok($$select pg_temp.gravar('7f000000-0000-4000-8000-00000000000a', null, 'caixa.fracao_recuperacao_vencido', '0.1234567')$$,
  '23514', 'Fração do vencido que se espera receber aceita no máximo seis casas decimais', 'fração com mais de seis casas');
select throws_ok($$select pg_temp.gravar('7f000000-0000-4000-8000-00000000000a', null, 'negocio.fuso_horario', '"America/Recife_Norte"')$$,
  '23514', 'Fuso horário não reconhece o fuso America/Recife_Norte', 'fuso inválido');
select throws_ok($$select pg_temp.gravar('7f000000-0000-4000-8000-00000000000a', null, 'caixa.consolidado_compensa_obras', '"sim"')$$,
  '23514', 'Abrir o fluxo pelo consolidado precisa ser sim ou não', 'booleano em texto');
select throws_ok($$select pg_temp.gravar('7f000000-0000-4000-8000-00000000000a', null, 'exibicao.meses_grafico', 'null')$$,
  '23514', 'Meses nos gráficos de fluxo precisa de um valor', 'nulo em parâmetro que exige valor');
select lives_ok($$select pg_temp.gravar('7f000000-0000-4000-8000-00000000000a', null, 'financiamento.retencao_padrao', 'null')$$,
  'nulo aceito onde o catálogo permite');
select throws_ok($$select pg_temp.gravar('7f000000-0000-4000-8000-00000000000a', null, 'comercial.meta_data_horizonte', '"2026-02-30"')$$,
  '23514', 'Data final da meta automática precisa ser uma data válida', 'data inexistente');
select lives_ok($$select pg_temp.gravar('7f000000-0000-4000-8000-00000000000a', null, 'comercial.meta_data_horizonte', '"2028-06-30"')$$,
  'data válida');
select throws_ok(
  $$select pg_temp.gravar('7f000000-0000-4000-8000-00000000000a', '7d000000-0000-4000-8000-0000000000a1', 'exibicao.meses_grafico', '48')$$,
  '23514', 'o parâmetro exibicao.meses_grafico vale para a construtora inteira e não aceita valor por obra',
  'valor por obra em parâmetro só de tenant');
select throws_ok(
  $$select pg_temp.gravar('7f000000-0000-4000-8000-00000000000a', '7d000000-0000-4000-8000-0000000000b1', 'caixa.receber_vencido', '"excluir"')$$,
  '23514', 'valor por obra só vale para uma obra da mesma construtora', 'obra de outro tenant');
select throws_ok(
  $$select pg_temp.gravar('7f000000-0000-4000-8000-00000000000a', '7d000000-0000-4000-8000-0000000000ae', 'caixa.receber_vencido', '"excluir"')$$,
  '23514', 'valor por obra só vale para uma obra da mesma construtora', 'centro Despesas sem obra não recebe valor por obra');
select throws_ok(
  $$select pg_temp.gravar('7f000000-0000-4000-8000-00000000000a', null, 'reconhecimento.base_fracao_vendida', '"area_privativa"')$$,
  '23514', 'o parâmetro reconhecimento.base_fracao_vendida muda números do financeiro; informe a observação',
  'parâmetro que exige validação pede observação');
select lives_ok(
  $$select pg_temp.gravar('7f000000-0000-4000-8000-00000000000a', null, 'reconhecimento.base_fracao_vendida', '"area_privativa"',
    'Validado com o financeiro em 20/09')$$,
  'com observação grava');
select throws_ok($$insert into app.parametro_valor (tenant_id, codigo, valor, autor)
    values ('7f000000-0000-4000-8000-00000000000a', 'parametro.inexistente', '1', '7b000000-0000-4000-8000-0000000000aa')$$,
  '23514', 'o parâmetro parametro.inexistente não existe', 'código fora do catálogo');

-- Frações da simulação somam 1 em cada nível gravado
select throws_ok($$select pg_temp.gravar('7f000000-0000-4000-8000-00000000000a', null, 'simulacao.fracao_entrada', '0.2')$$,
  '23514', 'entrada, parcelas mensais e financiamento da simulação somam 1.100000, e precisam somar 1 (100%)',
  'fração sozinha que desequilibra a soma');
select lives_ok(
  $$insert into app.parametro_valor (tenant_id, centro_custo_id, codigo, valor, autor)
    select '7f000000-0000-4000-8000-00000000000a', null, c, v, '7b000000-0000-4000-8000-0000000000aa'
    from (values ('simulacao.fracao_entrada', '0.2'::jsonb), ('simulacao.fracao_parcelas', '0.2'),
                 ('simulacao.fracao_financiamento', '0.6')) x(c, v)$$,
  'três frações gravadas juntas somando 1');
select throws_ok(
  $$select pg_temp.gravar('7f000000-0000-4000-8000-00000000000a', '7d000000-0000-4000-8000-0000000000a1', 'simulacao.fracao_entrada', '0.3')$$,
  '23514', null, 'obra que sobrepõe uma fração e desequilibra a soma');
select lives_ok(
  $$insert into app.parametro_valor (tenant_id, centro_custo_id, codigo, valor, autor)
    select '7f000000-0000-4000-8000-00000000000a', '7d000000-0000-4000-8000-0000000000a1', c, v, '7b000000-0000-4000-8000-0000000000aa'
    from (values ('simulacao.fracao_entrada', '0.3'::jsonb), ('simulacao.fracao_parcelas', '0.1')) x(c, v)$$,
  'obra sobrepõe duas frações e herda a terceira do tenant, somando 1');
select throws_ok(
  $$update app.parametro_valor set valor = case codigo when 'simulacao.fracao_parcelas' then '0.3'::jsonb else '0.5' end
    where tenant_id = '7f000000-0000-4000-8000-00000000000a' and centro_custo_id is null
      and codigo in ('simulacao.fracao_parcelas', 'simulacao.fracao_financiamento')$$,
  '23514', null, 'tenant equilibrado que desequilibra a obra que herda dele');
select results_eq(
  $$select centro_custo_id, simulacao__fracao_entrada + simulacao__fracao_parcelas + simulacao__fracao_financiamento
    from app.parametros_obra where tenant_id = '7f000000-0000-4000-8000-00000000000a' order by 1$$,
  $$values ('7d000000-0000-4000-8000-0000000000a1'::uuid, 1.000000::numeric), ('7d000000-0000-4000-8000-0000000000a2'::uuid, 1.000000),
           ('7d000000-0000-4000-8000-0000000000ae'::uuid, 1.000000)$$,
  'na resolução as três frações somam 1 em toda obra'
);
select throws_ok(
  $$delete from app.parametro_valor where tenant_id = '7f000000-0000-4000-8000-00000000000a'
    and centro_custo_id = '7d000000-0000-4000-8000-0000000000a1' and codigo = 'simulacao.fracao_parcelas'$$,
  '23514', null, 'voltar ao padrão uma fração só também confere a soma');

-- Data de referência pelo fuso do tenant do JWT
select pg_temp.gravar('7f000000-0000-4000-8000-00000000000a', null, 'negocio.fuso_horario', '"Pacific/Kiritimati"');
select pg_temp.gravar('7f000000-0000-4000-8000-00000000000b', null, 'negocio.fuso_horario', '"Etc/GMT+12"');
select set_config('app.data_referencia', '2026-12-15', true);
select is(app.data_referencia(), '2026-12-15'::date, 'data fixada por set_config vence o fuso');
select set_config('app.data_referencia', '', true);
select set_config('request.jwt.claims', '', true);
select is(app.data_referencia(), (now() at time zone 'America/Sao_Paulo')::date, 'sem JWT vale o fuso padrão');
select set_config('request.jwt.claims',
  '{"sub": "7b000000-0000-4000-8000-0000000000aa", "role": "authenticated", "app_metadata": {"tenant_id": "7f000000-0000-4000-8000-00000000000a", "perfil": "diretor"}}', true);
select is(app.data_referencia(), (now() at time zone 'Pacific/Kiritimati')::date, 'tenant A no fuso próprio');
select app.data_referencia() as dia_a \gset
select set_config('request.jwt.claims',
  '{"sub": "7b000000-0000-4000-8000-0000000000bb", "role": "authenticated", "app_metadata": {"tenant_id": "7f000000-0000-4000-8000-00000000000b", "perfil": "diretor"}}', true);
select is(app.data_referencia(), (now() at time zone 'Etc/GMT+12')::date, 'tenant B no fuso próprio');
select ok(:'dia_a'::date - app.data_referencia() between 1 and 2, 'fusos 26 horas distantes dão dias diferentes');

-- Limite de horas da carga
insert into raw.registro (tenant_id, endpoint, payload, hash_registro, carregado_em)
values ('7f000000-0000-4000-8000-00000000000b', 'units', '{}', 'carga-b', now() - interval '3 hours');
select ok((select not desatualizada and horas_desde_carga = 3.0 from app.situacao_carga()), 'carga de 3 horas dentro do padrão de 26');
select pg_temp.gravar('7f000000-0000-4000-8000-00000000000b', null, 'alerta.carga_desatualizada_horas', '2');
select ok((select desatualizada from app.situacao_carga()), 'com limite de 2 horas a mesma carga fica atrasada');
select set_config('request.jwt.claims', '', true);
select set_config('app.data_referencia', '2026-09-26', true);

-- Mapa de códigos: padrão semeado para tenant novo, sem entrar no histórico
select results_eq(
  $$select dominio, count(*)::int from app.mapa_codigo_origem where tenant_id = '7f000000-0000-4000-8000-00000000000a'
    group by 1 order by 1$$,
  $$values ('condicao_pagamento', 5), ('situacao_contrato', 2), ('situacao_unidade', 7)$$,
  'tenant novo recebe os 14 códigos padrão'
);
select results_eq(
  $$select codigo_origem, valor, rotulo from app.mapa_codigo_origem
    where tenant_id = '7f000000-0000-4000-8000-00000000000a' and codigo_origem in ('FI', 'R', '3') order by 1$$,
  $$values ('3', 'distratado', 'Distratado'), ('FI', 'financiamento_comprador', 'Financiamento'), ('R', 'fora_de_venda', 'Reserva técnica')$$,
  'padrões da seção 2.4'
);
select is((select count(*) from app.auditoria_alteracao
            where tabela = 'app.mapa_codigo_origem' and tenant_id = '7f000000-0000-4000-8000-00000000000a'),
  0::bigint, 'semeadura não entra no histórico');
select throws_ok(
  $$insert into app.mapa_codigo_origem (tenant_id, dominio, codigo_origem, valor)
    values ('7f000000-0000-4000-8000-00000000000a', 'situacao_unidade', 'X', 'alugada')$$,
  '23514', 'o domínio situacao_unidade não aceita o valor alugada; use um destes: disponivel, reservada, proposta, vendida, fora_de_venda',
  'valor fora do domínio');
select throws_ok(
  $$insert into app.mapa_codigo_origem (tenant_id, dominio, codigo_origem, valor)
    values ('7f000000-0000-4000-8000-00000000000a', 'indexador', 'X', 'ativo')$$,
  '23514', null, 'domínio inexistente');

-- Carga com códigos conhecidos e desconhecidos
insert into raw.registro (tenant_id, endpoint, payload, hash_registro)
select '7f000000-0000-4000-8000-00000000000a', e, x, md5(e || x::text)
from (values
  ('units', '[{"id": 91011, "enterpriseId": 9101, "commercialStock": "D"},
              {"id": 91012, "enterpriseId": 9101, "commercialStock": "D"},
              {"id": 91013, "enterpriseId": 9101, "commercialStock": "V"},
              {"id": 91014, "enterpriseId": 9101, "commercialStock": "Z", "saleValuePrice": 150000.00},
              {"id": 91021, "enterpriseId": 9102, "commercialStock": "R"}]'::jsonb),
  ('sales', '[{"id": 6101, "enterpriseId": 9101, "number": "C-6101", "contractDate": "2026-01-05", "situation": "1",
               "value": 300000.00, "units": [{"id": 91013}],
               "paymentConditions": [{"conditionType": "AT", "totalValue": 60000.00}, {"conditionType": "FI", "totalValue": 240000.00}]},
              {"id": 6102, "enterpriseId": 9101, "number": "C-6102", "contractDate": "2026-02-05", "situation": "9",
               "value": 200000.00, "units": [{"id": 91012}]},
              {"id": 6103, "enterpriseId": 9101, "number": "C-6103", "contractDate": "2026-03-05", "situation": "3",
               "value": 100000.00, "units": [{"id": 91011}]}]'),
  ('income', '[{"projectId": 9101, "billId": 6101, "installmentId": 1, "dueDate": "2026-01-10", "originalAmount": 60000.00,
                "balanceAmount": 0, "correctedBalanceAmount": 0, "paymentTerm": {"id": "AT"},
                "receipts": [{"paymentDate": "2026-01-10", "amount": 60000.00}]},
               {"projectId": 9101, "billId": 6101, "installmentId": 2, "dueDate": "2026-12-10", "originalAmount": 240000.00,
                "balanceAmount": 240000.00, "correctedBalanceAmount": 240000.00, "paymentTerm": {"id": "FI"}, "receipts": []},
               {"projectId": 9101, "billId": 6102, "installmentId": 1, "dueDate": "2026-11-10", "originalAmount": 50000.00,
                "balanceAmount": 50000.00, "correctedBalanceAmount": 50000.00, "paymentTerm": {"id": "XX"}, "receipts": []}]')
) as l(e, lista)
cross join lateral jsonb_array_elements(l.lista) x;
select staging.recarregar('7f000000-0000-4000-8000-00000000000a');
select staging.recarregar_precos('7f000000-0000-4000-8000-00000000000a');

select results_eq(
  $$select contrato_id_origem, id_origem, tipo_condicao, origem from staging.parcela_receber
    where tenant_id = '7f000000-0000-4000-8000-00000000000a' order by 1, 2$$,
  $$values (6101, 1, 'AT', 'direta'), (6101, 2, 'FI', 'repasse'), (6102, 1, 'XX', 'direta')$$,
  'origem da parcela vem do mapa; código sem mapa fica direta'
);
select is((select origem from staging.recebimento where tenant_id = '7f000000-0000-4000-8000-00000000000a'), 'direta',
  'recebimento herda a origem da parcela');
select results_eq(
  $$select id_origem, situacao, situacao_normalizada, valor_financiado from staging.contrato_venda
    where tenant_id = '7f000000-0000-4000-8000-00000000000a' order by 1$$,
  $$values (6101, '1', 'ativo', 240000.00::numeric(18,2)), (6102, '9', 'outro', null), (6103, '3', 'distratado', null)$$,
  'situação normalizada pelo mapa e valor financiado pelas condições de financiamento'
);
select results_eq(
  $$select centro_custo_id, dominio, codigo_origem, quantidade_registros, valor_envolvido, valor_aplicado
    from marts.pendencia_codigo_origem where tenant_id = '7f000000-0000-4000-8000-00000000000a' order by dominio$$,
  $$values ('7d000000-0000-4000-8000-0000000000a1'::uuid, 'condicao_pagamento', 'XX', 1::bigint, 50000.00::numeric, 'entrada_direta'),
           ('7d000000-0000-4000-8000-0000000000a1'::uuid, 'situacao_contrato', '9', 1::bigint, 200000.00::numeric, 'outro'),
           ('7d000000-0000-4000-8000-0000000000a1'::uuid, 'situacao_unidade', 'Z', 1::bigint, 150000.00::numeric, 'fora_de_venda')$$,
  'código sem mapa aparece em pendência com quantidade, valor e o que está valendo'
);
select results_eq(
  $$select centro_custo_id, disponiveis, reservadas, propostas, vendidas, indisponiveis, total from marts.estoque_atual
    where tenant_id = '7f000000-0000-4000-8000-00000000000a' order by 1$$,
  $$values ('7d000000-0000-4000-8000-0000000000a1'::uuid, 2::bigint, 0::bigint, 0::bigint, 1::bigint, 1::bigint, 4::bigint),
           ('7d000000-0000-4000-8000-0000000000a2'::uuid, 0::bigint, 0::bigint, 0::bigint, 0::bigint, 1::bigint, 1::bigint)$$,
  'estoque pelo mapa: Z sem mapa e R fora de venda contam como indisponíveis'
);
select results_eq(
  $$select unidade_id, situacao_origem, situacao from marts.mapa_unidades
    where tenant_id = '7f000000-0000-4000-8000-00000000000a' order by 1$$,
  $$values (91011, 'D', 'disponivel'), (91012, 'D', 'disponivel'), (91013, 'V', 'vendida'), (91014, 'Z', 'indisponivel'),
           (91021, 'R', 'indisponivel')$$,
  'mapa de unidades mantém os valores de situação'
);
select results_eq(
  $$select competencia, entrada_direta_prevista, repasse_previsto from marts.fluxo_caixa_mensal
    where centro_custo_id = '7d000000-0000-4000-8000-0000000000a1' and competencia >= '2026-11-01' order by 1$$,
  $$values ('2026-11-01'::date, 50000.00::numeric, 0::numeric), ('2026-12-01'::date, 0::numeric, 240000.00::numeric)$$,
  'fluxo com o mapa padrão: FI no repasse, contrato de código desconhecido fica na carteira'
);

-- Gravação direta no staging usa a mesma regra
insert into staging.contrato_venda (tenant_id, centro_custo_id, id_origem, data_venda, valor, situacao) values
  ('7f000000-0000-4000-8000-00000000000a', '7d000000-0000-4000-8000-0000000000a2', 6201, '2026-04-01', 1000.00, '3');
insert into staging.parcela_receber (tenant_id, centro_custo_id, id_origem, contrato_id_origem, vencimento, valor_original,
  tipo_condicao) values
  ('7f000000-0000-4000-8000-00000000000a', '7d000000-0000-4000-8000-0000000000a2', 1, 6201, '2026-10-10', 500.00, 'FI'),
  ('7f000000-0000-4000-8000-00000000000a', '7d000000-0000-4000-8000-0000000000a2', 2, 6201, '2026-11-10', 500.00, 'PM');
select results_eq(
  $$select origem from staging.parcela_receber where contrato_id_origem = 6201 order by id_origem$$,
  $$values ('repasse'), ('direta')$$,
  'parcela gravada sem origem recebe a do mapa'
);
update staging.parcela_receber set tipo_condicao = 'PM' where contrato_id_origem = 6201 and id_origem = 1;
select is((select origem from staging.parcela_receber where contrato_id_origem = 6201 and id_origem = 1), 'direta',
  'trocar a condição recalcula a origem');
select is((select situacao_normalizada from staging.contrato_venda where id_origem = 6201), 'distratado',
  'contrato gravado sem situação normalizada recebe a do mapa');
update staging.contrato_venda set situacao = '1' where id_origem = 6201;
select is((select situacao_normalizada from staging.contrato_venda where id_origem = 6201), 'ativo',
  'trocar a situação recalcula a normalizada');

-- Recarga idempotente
select staging.recarregar('7f000000-0000-4000-8000-00000000000a');
select results_eq(
  $$select (select count(*) from staging.parcela_receber where tenant_id = '7f000000-0000-4000-8000-00000000000a'),
           (select count(*) from staging.parcela_receber where tenant_id = '7f000000-0000-4000-8000-00000000000a' and origem = 'repasse'),
           (select count(*) from staging.contrato_venda where tenant_id = '7f000000-0000-4000-8000-00000000000a')$$,
  $$values (3::bigint, 1::bigint, 3::bigint)$$,
  'rodar a recarga de novo deixa as mesmas linhas e apaga o que foi gravado à mão'
);

-- Remapear FI muda a origem só na próxima recarga
update app.mapa_codigo_origem set valor = 'entrada_direta'
where tenant_id = '7f000000-0000-4000-8000-00000000000a' and dominio = 'condicao_pagamento' and codigo_origem = 'FI';
select is((select origem from staging.parcela_receber where contrato_id_origem = 6101 and id_origem = 2), 'repasse',
  'antes da recarga a parcela continua como estava');
select staging.recarregar('7f000000-0000-4000-8000-00000000000a');
select is((select origem from staging.parcela_receber where contrato_id_origem = 6101 and id_origem = 2), 'direta',
  'FI remapeado vira entrada direta na recarga');
select is((select valor_financiado from staging.contrato_venda where id_origem = 6101), 0.00::numeric(18,2),
  'valor financiado acompanha o mapa');
select results_eq(
  $$select entrada_direta_prevista, repasse_previsto from marts.fluxo_caixa_mensal
    where centro_custo_id = '7d000000-0000-4000-8000-0000000000a1' and competencia = '2026-12-01'$$,
  $$values (240000.00::numeric, 0::numeric)$$,
  'fluxo passa a mostrar a parcela como entrada direta'
);
select is(
  (select count(*) from app.auditoria_alteracao where tabela = 'app.mapa_codigo_origem' and operacao = 'update'
     and registro_id = '7f000000-0000-4000-8000-00000000000a|condicao_pagamento|FI'),
  1::bigint, 'remapeamento fica no histórico com a chave do código'
);

-- Mapear os códigos pendentes tira da pendência e muda os números
insert into app.mapa_codigo_origem (tenant_id, dominio, codigo_origem, valor, observacao) values
  ('7f000000-0000-4000-8000-00000000000a', 'condicao_pagamento', 'XX', 'financiamento_comprador', 'Financiamento associativo'),
  ('7f000000-0000-4000-8000-00000000000a', 'situacao_contrato', '9', 'distratado', 'Distrato em análise'),
  ('7f000000-0000-4000-8000-00000000000a', 'situacao_unidade', 'Z', 'disponivel', 'Liberada para venda');
select staging.recarregar('7f000000-0000-4000-8000-00000000000a');
select is((select count(*) from marts.pendencia_codigo_origem where tenant_id = '7f000000-0000-4000-8000-00000000000a'),
  0::bigint, 'sem pendência depois de mapear');
select is((select origem from staging.parcela_receber where contrato_id_origem = 6102), 'repasse',
  'código novo mapeado como financiamento vai para o repasse');
select is((select situacao_normalizada from staging.contrato_venda where id_origem = 6102), 'distratado',
  'contrato de código novo mapeado como distratado');
select is(
  (select count(*) from marts.fluxo_caixa_mensal where centro_custo_id = '7d000000-0000-4000-8000-0000000000a1'
     and competencia = '2026-11-01'),
  0::bigint, 'parcela do contrato distratado sai da carteira projetada'
);
select results_eq(
  $$select disponiveis, indisponiveis from marts.estoque_atual where centro_custo_id = '7d000000-0000-4000-8000-0000000000a1'$$,
  $$values (3::bigint, 0::bigint)$$,
  'unidade remapeada entra no estoque disponível sem recarga'
);
update app.mapa_codigo_origem set valor = 'fora_de_venda'
where tenant_id = '7f000000-0000-4000-8000-00000000000a' and dominio = 'situacao_unidade' and codigo_origem = 'D';
select results_eq(
  $$select disponiveis, indisponiveis from marts.estoque_atual where centro_custo_id = '7d000000-0000-4000-8000-0000000000a1'$$,
  $$values (1::bigint, 2::bigint)$$,
  'D remapeado para fora de venda muda o estoque'
);
select is(
  (select sum(valor) from marts.mapa_unidades where centro_custo_id = '7d000000-0000-4000-8000-0000000000a1'
     and situacao in ('disponivel', 'reservada', 'proposta')),
  150000.00::numeric, 'mapa de unidades segue o remapeamento no valor a vender'
);
select is((select count(*) from app.mapa_codigo_origem where tenant_id = '7f000000-0000-4000-8000-00000000000b'), 14::bigint,
  'mapa de um tenant não mexe no do outro');

-- Rótulo personalizado
select lives_ok(
  $$insert into app.rotulo_personalizado (tenant_id, contexto, chave, rotulo, autor)
    values ('7f000000-0000-4000-8000-00000000000a', 'linha_dre', 'resultado_gerencial', 'Resultado da operação',
            '7b000000-0000-4000-8000-0000000000aa')$$,
  'rótulo próprio grava');
select throws_ok(
  $$insert into app.rotulo_personalizado (tenant_id, contexto, chave, rotulo, autor)
    values ('7f000000-0000-4000-8000-00000000000a', 'tela', 'dre', 'DRE', '7b000000-0000-4000-8000-0000000000aa')$$,
  '23514', null, 'contexto fora da lista');
select throws_ok(
  $$insert into app.rotulo_personalizado (tenant_id, contexto, chave, rotulo, autor)
    values ('7f000000-0000-4000-8000-00000000000a', 'categoria', 'marketing', '   ', '7b000000-0000-4000-8000-0000000000aa')$$,
  '23514', null, 'rótulo em branco');
select is(
  (select count(*) from app.auditoria_alteracao where tabela = 'app.rotulo_personalizado'
     and registro_id = '7f000000-0000-4000-8000-00000000000a|linha_dre|resultado_gerencial'),
  1::bigint, 'rótulo no histórico');

-- Tenant criado depois da migration também recebe o padrão
insert into app.tenant (id, razao_social) values ('7f000000-0000-4000-8000-00000000000c', 'Construtora Configuração C');
select is((select count(*) from app.mapa_codigo_origem where tenant_id = '7f000000-0000-4000-8000-00000000000c'), 14::bigint,
  'gatilho semeia o tenant novo');

-- Depois de uma transação, o cache local do fuso volta como texto vazio; a data de referência não pode quebrar
select set_config('app.data_referencia', '', true), set_config('request.jwt.claims', '', true),
       set_config('app.fuso_claims', '', true), set_config('app.fuso_valor', '', true);
select lives_ok($$select app.data_referencia()$$, 'cache do fuso vazio, como no início de uma nova transação, recalcula o fuso');

select * from finish();
rollback;
