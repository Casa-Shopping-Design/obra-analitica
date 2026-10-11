-- Quem vê qual empresa (migration 0036): diretor e financeiro todas as do tenant; leitura só a empresa cujas
-- obras são todas dele; gerente de obra nenhuma; holding sem obra só diretor e financeiro; outro tenant nada;
-- diretor em aal1 nada. Cria os próprios dados: Alfa (obras A1 e A2), Beta (obra B1) e a Holding sem obra.
begin;
create extension if not exists pgtap with schema extensions;
select plan(39);

insert into app.tenant (id, razao_social) values
  ('0e000000-0000-4000-8000-0000000000a1', 'Construtora Empresas'),
  ('0e000000-0000-4000-8000-0000000000a2', 'Construtora Empresas vizinha');

insert into app.empresa (id, tenant_id, id_origem, nome) values
  ('0f000000-0000-4000-8000-0000000000a1', '0e000000-0000-4000-8000-0000000000a1', 11, 'Alfa SPE'),
  ('0f000000-0000-4000-8000-0000000000a2', '0e000000-0000-4000-8000-0000000000a1', 12, 'Beta SPE'),
  ('0f000000-0000-4000-8000-0000000000a3', '0e000000-0000-4000-8000-0000000000a1', 1, 'Holding'),
  ('0f000000-0000-4000-8000-0000000000a9', '0e000000-0000-4000-8000-0000000000a2', 11, 'Vizinha SPE');

insert into app.centro_custo (id, tenant_id, id_origem, nome, empresa_id) values
  ('0c000000-0000-4000-8000-0000000000a1', '0e000000-0000-4000-8000-0000000000a1', 961, 'Obra A1', 11),
  ('0c000000-0000-4000-8000-0000000000a2', '0e000000-0000-4000-8000-0000000000a1', 962, 'Obra A2', 11),
  ('0c000000-0000-4000-8000-0000000000a3', '0e000000-0000-4000-8000-0000000000a1', 963, 'Obra B1', 12),
  ('0c000000-0000-4000-8000-0000000000a9', '0e000000-0000-4000-8000-0000000000a2', 961, 'Obra vizinha', 11);

insert into auth.users (id, email) values
  ('0a000000-0000-4000-8000-00000000d0a1', 'diretor.emp@teste.invalid'),
  ('0a000000-0000-4000-8000-00000000f0a1', 'financeiro.emp@teste.invalid'),
  ('0a000000-0000-4000-8000-00000000c0a1', 'gerente.emp@teste.invalid'),
  ('0a000000-0000-4000-8000-00000000b0a1', 'leitura.alfa@teste.invalid'),
  ('0a000000-0000-4000-8000-00000000b0a2', 'leitura.parcial@teste.invalid'),
  ('0a000000-0000-4000-8000-00000000b0a3', 'leitura.beta@teste.invalid'),
  ('0a000000-0000-4000-8000-00000000d0a2', 'diretor.emp.vizinho@teste.invalid');

insert into app.usuario_tenant (user_id, tenant_id, perfil) values
  ('0a000000-0000-4000-8000-00000000d0a1', '0e000000-0000-4000-8000-0000000000a1', 'diretor'),
  ('0a000000-0000-4000-8000-00000000f0a1', '0e000000-0000-4000-8000-0000000000a1', 'financeiro'),
  ('0a000000-0000-4000-8000-00000000c0a1', '0e000000-0000-4000-8000-0000000000a1', 'gerente_obra'),
  ('0a000000-0000-4000-8000-00000000b0a1', '0e000000-0000-4000-8000-0000000000a1', 'leitura'),
  ('0a000000-0000-4000-8000-00000000b0a2', '0e000000-0000-4000-8000-0000000000a1', 'leitura'),
  ('0a000000-0000-4000-8000-00000000b0a3', '0e000000-0000-4000-8000-0000000000a1', 'leitura'),
  ('0a000000-0000-4000-8000-00000000d0a2', '0e000000-0000-4000-8000-0000000000a2', 'diretor');

insert into app.usuario_centro_custo (user_id, tenant_id, centro_custo_id) values
  ('0a000000-0000-4000-8000-00000000c0a1', '0e000000-0000-4000-8000-0000000000a1', '0c000000-0000-4000-8000-0000000000a1'),
  ('0a000000-0000-4000-8000-00000000b0a1', '0e000000-0000-4000-8000-0000000000a1', '0c000000-0000-4000-8000-0000000000a1'),
  ('0a000000-0000-4000-8000-00000000b0a1', '0e000000-0000-4000-8000-0000000000a1', '0c000000-0000-4000-8000-0000000000a2'),
  ('0a000000-0000-4000-8000-00000000b0a2', '0e000000-0000-4000-8000-0000000000a1', '0c000000-0000-4000-8000-0000000000a1'),
  ('0a000000-0000-4000-8000-00000000b0a3', '0e000000-0000-4000-8000-0000000000a1', '0c000000-0000-4000-8000-0000000000a3');

-- Um mês com duas contas por empresa: caixa e capital, fechando a partida.
insert into staging.plano_conta (tenant_id, empresa_id, conta, conta_reduzida, nome, analitica, grupo)
select e.tenant_id, e.id, c.conta, c.reduzida, c.nome, true, c.grupo
from app.empresa e
cross join (values ('1.1.1.01.0001', 101, 'Banco', 'ativo'), ('2.3.1.01.0001', 231, 'Capital', 'passivo')) as c (conta, reduzida, nome, grupo)
where e.tenant_id in ('0e000000-0000-4000-8000-0000000000a1', '0e000000-0000-4000-8000-0000000000a2');

insert into staging.saldo_contabil_empresa_mensal
  (tenant_id, empresa_id, conta, competencia, saldo_anterior, debito, credito, saldo_final,
   saldo_anterior_sem_zeramento, debito_sem_zeramento, credito_sem_zeramento, saldo_final_sem_zeramento)
select e.tenant_id, e.id, c.conta, '2025-06-01', 0, c.debito, c.credito, c.debito - c.credito, 0, c.debito, c.credito, c.debito - c.credito
from app.empresa e
cross join (values ('1.1.1.01.0001', 100, 0), ('2.3.1.01.0001', 0, 100)) as c (conta, debito, credito)
where e.tenant_id in ('0e000000-0000-4000-8000-0000000000a1', '0e000000-0000-4000-8000-0000000000a2');

insert into app.mapa_conta_linha (tenant_id, conta, linha, origem)
select t.id, c.conta, c.linha, 'demo'
from app.tenant t
cross join (values ('1.1.1.01.0001', 'bancos'), ('2.3.1.01.0001', 'aporte_capital')) as c (conta, linha)
where t.id in ('0e000000-0000-4000-8000-0000000000a1', '0e000000-0000-4000-8000-0000000000a2');

-- Estrutura

select ok(
  (select prosecdef and proconfig @> array['search_path=""'] from pg_proc
   where oid = 'app.empresas_permitidas()'::regprocedure),
  'empresas_permitidas é security definer com search_path vazio'
);
select ok(
  has_function_privilege('authenticated', 'app.empresas_permitidas()', 'execute')
  and not has_function_privilege('anon', 'app.empresas_permitidas()', 'execute'),
  'só o usuário logado executa empresas_permitidas'
);
select is(
  (select count(*) from pg_policies
   where (schemaname, tablename) in (('app', 'empresa'), ('staging', 'saldo_contabil_empresa_mensal'))
     and permissive = 'PERMISSIVE' and cmd = 'SELECT'
     and qual like '%empresas_permitidas%'),
  2::bigint,
  'empresa e saldo filtram pelas empresas permitidas'
);

-- Diretor com segundo fator

select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000d0a1", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;
select is((select count(*) from app.empresas_permitidas()), 3::bigint, 'diretor tem as três empresas permitidas');
select is((select count(*) from app.empresa), 3::bigint, 'diretor vê as três empresas, holding incluída');
select is((select count(*) from staging.saldo_contabil_empresa_mensal), 6::bigint, 'diretor lê o saldo das três');
select is((select count(*) from staging.plano_conta), 6::bigint, 'diretor lê o plano das três');
select is((select count(*) from marts.empresa_resumo), 3::bigint, 'diretor vê as três no resumo');
select is(
  (select obras from marts.empresa_resumo where empresa_id = '0f000000-0000-4000-8000-0000000000a1'),
  2,
  'a Alfa aparece com duas obras'
);
select is(
  (select obras from marts.empresa_resumo where empresa_id = '0f000000-0000-4000-8000-0000000000a3'),
  0,
  'a holding aparece sem obra'
);
select is((select count(*) from marts.controle_fontes_usos), 3::bigint, 'diretor vê o controle das três');
select is((select count(*) from marts.mapa_contas), 2::bigint, 'diretor vê o plano do tenant, uma linha por conta');
select is(
  (select valor from marts.fontes_usos('0f000000-0000-4000-8000-0000000000a3', '2025-06-01', '2025-06-01', true)
   where linha = 'caixa_equivalentes'),
  100::numeric,
  'diretor lê o F&U da holding'
);

-- Financeiro

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000f0a1", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;
select is((select count(*) from app.empresa), 3::bigint, 'financeiro vê as três empresas');
select is((select count(*) from marts.mapa_contas), 2::bigint, 'financeiro vê a tela de mapeamento');

-- Diretor só com a senha

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000d0a1", "role": "authenticated", "aal": "aal1"}', true);
set local role authenticated;
select is((select count(*) from app.empresa), 0::bigint, 'diretor em aal1 não lê empresa');
select is((select count(*) from staging.saldo_contabil_empresa_mensal), 0::bigint, 'diretor em aal1 não lê saldo');
select is((select count(*) from staging.plano_conta), 0::bigint, 'diretor em aal1 não lê o plano');
select is((select count(*) from app.mapa_conta_linha), 0::bigint, 'diretor em aal1 não lê o mapa');
select is((select count(*) from marts.empresa_resumo), 0::bigint, 'diretor em aal1 não vê o resumo');
select is(
  (select count(*) from marts.fontes_usos('0f000000-0000-4000-8000-0000000000a1', '2025-06-01', '2025-06-01', true)),
  0::bigint,
  'diretor em aal1 não recebe linha do F&U'
);

-- Gerente da obra A1

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000c0a1", "role": "authenticated", "aal": "aal1"}', true);
set local role authenticated;
select is((select count(*) from app.empresas_permitidas()), 0::bigint, 'gerente de obra não tem empresa permitida');
select is((select count(*) from app.empresa), 0::bigint, 'gerente de obra não vê empresa');
select is((select count(*) from staging.saldo_contabil_empresa_mensal), 0::bigint, 'gerente de obra não lê saldo');
select is((select count(*) from app.mapa_conta_linha), 0::bigint, 'gerente de obra não lê o mapa');
select is((select count(*) from marts.empresa_resumo), 0::bigint, 'gerente de obra não vê o resumo');
select is(
  (select count(*) from marts.fontes_usos('0f000000-0000-4000-8000-0000000000a1', '2025-06-01', '2025-06-01', true)),
  0::bigint,
  'gerente de obra não recebe linha do F&U'
);

-- Leitura com as duas obras da Alfa

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000b0a1", "role": "authenticated", "aal": "aal1"}', true);
set local role authenticated;
select results_eq(
  'select nome from app.empresa',
  $$values ('Alfa SPE')$$,
  'leitura com todas as obras da Alfa vê só a Alfa; a holding não'
);
select is((select count(*) from marts.empresa_resumo), 1::bigint, 'leitura vê uma empresa no resumo');
select is(
  (select valor from marts.fontes_usos('0f000000-0000-4000-8000-0000000000a1', '2025-06-01', '2025-06-01', true)
   where linha = 'caixa_equivalentes'),
  100::numeric,
  'leitura lê o F&U da Alfa com o mapa resolvido'
);
select is(
  (select count(*) from marts.fontes_usos('0f000000-0000-4000-8000-0000000000a3', '2025-06-01', '2025-06-01', true)),
  0::bigint,
  'leitura não recebe linha do F&U da holding'
);
select is((select count(*) from marts.fontes_usos_mensal where empresa_id <> '0f000000-0000-4000-8000-0000000000a1'), 0::bigint,
  'a view mensal só traz a Alfa para o leitura');
select is((select count(*) from marts.controle_fontes_usos), 0::bigint, 'leitura não vê o controle');
select is((select count(*) from marts.conta_sem_mapa), 0::bigint, 'leitura não vê as contas sem mapa');
select is((select count(*) from marts.mapa_contas), 0::bigint, 'leitura não vê a tela de mapeamento');
select is((select count(*) from staging.plano_conta), 0::bigint, 'leitura não lê o plano de contas');

-- Leitura com só uma das duas obras da Alfa, e leitura com a obra da Beta

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000b0a2", "role": "authenticated", "aal": "aal1"}', true);
set local role authenticated;
select is((select count(*) from app.empresa), 0::bigint, 'leitura com só uma obra da Alfa não vê a Alfa');

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000b0a3", "role": "authenticated", "aal": "aal1"}', true);
set local role authenticated;
select results_eq(
  'select nome from app.empresa',
  $$values ('Beta SPE')$$,
  'leitura com a obra da Beta vê só a Beta'
);

-- Vizinho

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000d0a2", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;
select results_eq(
  'select nome from app.empresa',
  $$values ('Vizinha SPE')$$,
  'diretor de outro tenant vê só a própria empresa'
);

select * from finish();
rollback;
