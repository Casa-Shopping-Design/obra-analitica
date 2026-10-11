-- Gravação do mapa conta para linha pela RPC app.gravar_mapa_conta_linha (migration 0037): quem grava, o que é
-- recusado e como a vigente e a herança mudam a cada gravação. Cria os próprios dados.
begin;
create extension if not exists pgtap with schema extensions;
select plan(37);

insert into app.tenant (id, razao_social) values
  ('0e000000-0000-4000-8000-0000000000e1', 'Construtora Mapa'),
  ('0e000000-0000-4000-8000-0000000000e2', 'Construtora Mapa vizinha');

insert into app.empresa (id, tenant_id, id_origem, nome) values
  ('0f000000-0000-4000-8000-0000000000e1', '0e000000-0000-4000-8000-0000000000e1', 21, 'Beta SPE'),
  ('0f000000-0000-4000-8000-0000000000e2', '0e000000-0000-4000-8000-0000000000e2', 21, 'Vizinha SPE');

insert into app.centro_custo (id, tenant_id, id_origem, nome, empresa_id) values
  ('0c000000-0000-4000-8000-0000000000e1', '0e000000-0000-4000-8000-0000000000e1', 971, 'Obra Beta', 21);

insert into staging.plano_conta (tenant_id, empresa_id, conta, conta_reduzida, nome, analitica, grupo) values
  ('0e000000-0000-4000-8000-0000000000e1', '0f000000-0000-4000-8000-0000000000e1', '1.1.1.01.0001', 101, 'Banco', true, 'ativo'),
  ('0e000000-0000-4000-8000-0000000000e1', '0f000000-0000-4000-8000-0000000000e1', '2.3.2', 232, 'Lucros Acumulados', false, 'passivo'),
  ('0e000000-0000-4000-8000-0000000000e1', '0f000000-0000-4000-8000-0000000000e1', '2.3.2.01.0001', 2321, 'Lucros Acumulados', true, 'passivo'),
  ('0e000000-0000-4000-8000-0000000000e1', '0f000000-0000-4000-8000-0000000000e1', '2.3.2.02.0001', 2322, 'Reserva Legal', true, 'passivo'),
  ('0e000000-0000-4000-8000-0000000000e2', '0f000000-0000-4000-8000-0000000000e2', '1.1.1.01.0001', 101, 'Banco vizinho', true, 'ativo');

insert into auth.users (id, email) values
  ('0a000000-0000-4000-8000-00000000d0e1', 'diretor.mapa@teste.invalid'),
  ('0a000000-0000-4000-8000-00000000f0e1', 'financeiro.mapa@teste.invalid'),
  ('0a000000-0000-4000-8000-00000000c0e1', 'gerente.mapa@teste.invalid'),
  ('0a000000-0000-4000-8000-00000000b0e1', 'leitura.mapa@teste.invalid'),
  ('0a000000-0000-4000-8000-00000000d0e2', 'diretor.mapa.vizinho@teste.invalid');

insert into app.usuario_tenant (user_id, tenant_id, perfil) values
  ('0a000000-0000-4000-8000-00000000d0e1', '0e000000-0000-4000-8000-0000000000e1', 'diretor'),
  ('0a000000-0000-4000-8000-00000000f0e1', '0e000000-0000-4000-8000-0000000000e1', 'financeiro'),
  ('0a000000-0000-4000-8000-00000000c0e1', '0e000000-0000-4000-8000-0000000000e1', 'gerente_obra'),
  ('0a000000-0000-4000-8000-00000000b0e1', '0e000000-0000-4000-8000-0000000000e1', 'leitura'),
  ('0a000000-0000-4000-8000-00000000d0e2', '0e000000-0000-4000-8000-0000000000e2', 'diretor');

insert into app.usuario_centro_custo (user_id, tenant_id, centro_custo_id) values
  ('0a000000-0000-4000-8000-00000000c0e1', '0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1'),
  ('0a000000-0000-4000-8000-00000000b0e1', '0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1');

-- Estrutura

select ok(
  (select prosecdef and proconfig @> array['search_path=""'] from pg_proc
   where oid = 'app.gravar_mapa_conta_linha(jsonb)'::regprocedure),
  'a RPC é security definer com search_path vazio'
);
select ok(
  has_function_privilege('authenticated', 'app.gravar_mapa_conta_linha(jsonb)', 'execute')
  and not has_function_privilege('anon', 'app.gravar_mapa_conta_linha(jsonb)', 'execute')
  and not has_function_privilege('public', 'app.gravar_mapa_conta_linha(jsonb)', 'execute'),
  'só o usuário logado executa a RPC'
);
select ok(
  not has_sequence_privilege('authenticated', 'app.mapa_conta_linha_id_seq', 'usage'),
  'usuário logado não usa a sequência do mapa'
);

-- Financeiro com segundo fator grava

select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000f0e1", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;

select is(
  app.gravar_mapa_conta_linha('[{"conta": "1.1.1.01.0001", "linha": "bancos"}, {"conta": "2.3.2", "linha": "lucros_acumulados"}]'),
  2,
  'financeiro em aal2 grava dois itens'
);
select results_eq(
  $$select conta, linha, linha_efetiva, atualizado_por from marts.mapa_contas order by conta$$,
  $$values ('1.1.1.01.0001', 'bancos', 'bancos', '0a000000-0000-4000-8000-00000000f0e1'::uuid),
           ('2.3.2', 'lucros_acumulados', 'lucros_acumulados', '0a000000-0000-4000-8000-00000000f0e1'::uuid),
           ('2.3.2.01.0001', null, 'lucros_acumulados', null),
           ('2.3.2.02.0001', null, 'lucros_acumulados', null)$$,
  'a sintética mapeada alcança as analíticas abaixo dela e a tela mostra quem gravou'
);
select is(
  app.gravar_mapa_conta_linha('[{"conta": "2.3.2.02.0001", "linha": "reserva_legal"}]'),
  1,
  'grava a analítica por cima da herança'
);
select results_eq(
  $$select conta, linha_efetiva from marts.mapa_contas where conta like '2.3.2.%' order by conta$$,
  $$values ('2.3.2.01.0001', 'lucros_acumulados'), ('2.3.2.02.0001', 'reserva_legal')$$,
  'a analítica mapeada vence a sintética; a irmã segue herdando'
);
select is(
  app.gravar_mapa_conta_linha('[{"conta": "2.3.2.02.0001", "linha": null}]'),
  1,
  'tira o mapa próprio da analítica'
);
select is(
  (select linha_efetiva from marts.mapa_contas where conta = '2.3.2.02.0001'),
  'lucros_acumulados',
  'sem mapa próprio a analítica volta a herdar da sintética'
);
select is(
  app.gravar_mapa_conta_linha('[{"conta": "2.3.2.02.0001", "linha": "reserva_legal"}]'),
  1,
  'devolve o mapa próprio da analítica'
);
select is(
  app.gravar_mapa_conta_linha('[{"conta": "1.1.1.01.0001", "linha": null}]'),
  1,
  'linha nula é aceita'
);
select is(
  (select linha_efetiva from marts.mapa_contas where conta = '1.1.1.01.0001'),
  null,
  'linha nula tira o mapa próprio e, sem prefixo mapeado, a conta fica sem linha'
);
select is(
  app.gravar_mapa_conta_linha('[{"conta": "1.1.1.01.0001"}]'),
  0,
  'item sem a chave linha vale como nulo e, igual ao vigente, não grava versão nova'
);
select is(app.gravar_mapa_conta_linha('[]'), 0, 'lista vazia grava zero e não falha');
select throws_ok(
  $$select app.gravar_mapa_conta_linha('[{"conta": "1.1.1.01.0001", "linha": "receita_vendas_incorporacao"}]')$$,
  '22023', null, 'conta de ativo não aceita linha de receita'
);
select is(
  (select count(*) from app.mapa_conta_linha where conta = '1.1.1.01.0001'),
  2::bigint,
  'as versões só crescem: duas mudanças da mesma conta são duas linhas'
);
select is(
  (select bool_and(criado_por = '0a000000-0000-4000-8000-00000000f0e1' and origem = 'painel') from app.mapa_conta_linha),
  true,
  'toda linha gravada pela RPC leva criado_por e origem painel'
);

select throws_ok(
  $$select app.gravar_mapa_conta_linha('[{"conta": "1.1.1.01.0001", "linha": "linha_que_nao_existe"}]')$$,
  '22023', null, 'linha inexistente recebe 22023'
);
select throws_ok(
  $$select app.gravar_mapa_conta_linha('[{"conta": "1.1.1.01.0001", "linha": "saldo_liquido"}]')$$,
  '22023', null, 'linha de total recebe 22023'
);
select throws_ok(
  $$select app.gravar_mapa_conta_linha('[{"conta": "1.1.1.01.0001", "linha": "grupo_lucros_acumulados"}]')$$,
  '22023', null, 'linha de grupo recebe 22023'
);
select throws_ok(
  $$select app.gravar_mapa_conta_linha('[{"conta": "9.9.9.99.9999", "linha": "bancos"}]')$$,
  '22023', null, 'conta fora do plano recebe 22023'
);
select throws_ok(
  $$select app.gravar_mapa_conta_linha('{"conta": "1.1.1.01.0001", "linha": "bancos"}')$$,
  '22023', null, 'objeto no lugar da lista recebe 22023'
);
select throws_ok(
  $$select app.gravar_mapa_conta_linha('[{"linha": "bancos"}]')$$,
  '22023', null, 'item sem conta recebe 22023'
);
select throws_ok(
  $$select app.gravar_mapa_conta_linha('[{"conta": "1.1.1.01.0001", "linha": 7}]')$$,
  '22023', null, 'linha que não é texto recebe 22023'
);
select throws_ok(
  $$select app.gravar_mapa_conta_linha(
      (select jsonb_agg(jsonb_build_object('conta', '1.1.1.01.0001', 'linha', 'bancos')) from generate_series(1, 501)))$$,
  '22023', null, 'mais de 500 itens recebe 22023'
);
select is(
  (select count(*) from app.mapa_conta_linha),
  6::bigint,
  'as gravações recusadas não deixaram linha'
);

-- Diretor também grava; em aal1 ninguém dos dois grava

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000d0e1", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;
select is(
  app.gravar_mapa_conta_linha('[{"conta": "1.1.1.01.0001", "linha": "bancos"}]'),
  1,
  'diretor em aal2 grava'
);

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000d0e1", "role": "authenticated", "aal": "aal1"}', true);
set local role authenticated;
select throws_ok(
  $$select app.gravar_mapa_conta_linha('[{"conta": "1.1.1.01.0001", "linha": "bancos"}]')$$,
  '42501', null, 'diretor em aal1 recebe 42501'
);

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000f0e1", "role": "authenticated", "aal": "aal1"}', true);
set local role authenticated;
select throws_ok(
  $$select app.gravar_mapa_conta_linha('[{"conta": "1.1.1.01.0001", "linha": "bancos"}]')$$,
  '42501', null, 'financeiro em aal1 recebe 42501'
);
select throws_ok(
  $$select app.gravar_mapa_conta_linha('[{"conta": "9.9.9.99.9999", "linha": "saldo_liquido"}]')$$,
  '42501', null, 'sem o segundo fator o erro é de permissão mesmo com conteúdo inválido'
);

-- Gerente e leitura

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000c0e1", "role": "authenticated", "aal": "aal1"}', true);
set local role authenticated;
select throws_ok(
  $$select app.gravar_mapa_conta_linha('[{"conta": "1.1.1.01.0001", "linha": "bancos"}]')$$,
  '42501', null, 'gerente de obra recebe 42501'
);
select is((select count(*) from app.mapa_conta_linha), 0::bigint, 'gerente de obra não lê o mapa');

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000b0e1", "role": "authenticated", "aal": "aal1"}', true);
set local role authenticated;
select throws_ok(
  $$select app.gravar_mapa_conta_linha('[{"conta": "1.1.1.01.0001", "linha": "bancos"}]')$$,
  '42501', null, 'perfil leitura recebe 42501'
);
select is((select count(*) from marts.mapa_contas), 0::bigint, 'perfil leitura não vê a tela de mapeamento');
select is((select count(*) from app.mapa_conta_linha), 7::bigint, 'perfil leitura resolve o mapa do tenant para o F&U');

-- Vizinho

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000d0e2", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;
select is((select count(*) from app.mapa_conta_linha), 0::bigint, 'outro tenant não vê o mapa');
select throws_ok(
  $$select app.gravar_mapa_conta_linha('[{"conta": "2.3.2", "linha": "lucros_acumulados"}]')$$,
  '22023', null, 'o vizinho não grava conta que só existe no plano alheio'
);

select * from finish();
rollback;
