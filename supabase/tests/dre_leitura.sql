-- Perfil leitura na DRE de viabilidade (migration 0032): lê sem segundo fator só as obras liberadas a ele,
-- e não grava estudo nem alíquota. Gerente de obra continua sem DRE. Cria os próprios dados.
begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

insert into app.tenant (id, razao_social) values ('0e000000-0000-4000-8000-0000000000e1', 'Construtora leitura');

insert into app.centro_custo (id, tenant_id, id_origem, nome) values
  ('0c000000-0000-4000-8000-0000000000e1', '0e000000-0000-4000-8000-0000000000e1', 981, 'Obra liberada'),
  ('0c000000-0000-4000-8000-0000000000e2', '0e000000-0000-4000-8000-0000000000e1', 982, 'Obra não liberada');

insert into auth.users (id, email) values
  ('0a000000-0000-4000-8000-00000000e0a1', 'leitura.dre@teste.invalid'),
  ('0a000000-0000-4000-8000-00000000e0c1', 'gerente.leitura@teste.invalid');

insert into app.usuario_tenant (user_id, tenant_id, perfil) values
  ('0a000000-0000-4000-8000-00000000e0a1', '0e000000-0000-4000-8000-0000000000e1', 'leitura'),
  ('0a000000-0000-4000-8000-00000000e0c1', '0e000000-0000-4000-8000-0000000000e1', 'gerente_obra');

insert into app.usuario_centro_custo (user_id, tenant_id, centro_custo_id) values
  ('0a000000-0000-4000-8000-00000000e0a1', '0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1'),
  ('0a000000-0000-4000-8000-00000000e0c1', '0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1');

insert into app.estudo_viabilidade (id, tenant_id, centro_custo_id, versao, descricao, data_base, situacao) values
  ('0d000000-0000-4000-8000-0000000000e1', '0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1',
   1, 'Estudo de lançamento', current_date, 'vigente'),
  ('0d000000-0000-4000-8000-0000000000e2', '0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e2',
   1, 'Estudo de lançamento', current_date, 'vigente');

insert into app.estudo_viabilidade_linha (estudo_id, tenant_id, centro_custo_id, linha, valor) values
  ('0d000000-0000-4000-8000-0000000000e1', '0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1',
   'vgv_bruto', 1000),
  ('0d000000-0000-4000-8000-0000000000e2', '0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e2',
   'vgv_bruto', 2000);

insert into app.aliquota_imposto_obra (tenant_id, centro_custo_id, vigencia_inicio, aliquota) values
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1', current_date, 0.04);

-- Leitura em aal1
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000e0a1", "role": "authenticated", "aal": "aal1"}', true);
set local role authenticated;

select results_eq(
  $$select centro_custo_id from app.estudo_viabilidade$$,
  $$values ('0c000000-0000-4000-8000-0000000000e1'::uuid)$$,
  'leitura em aal1 vê o estudo da obra liberada e não o da outra'
);
select is((select count(*) from app.estudo_viabilidade_linha), 1::bigint, 'leitura vê as linhas do estudo da obra liberada');
select is((select count(*) from app.aliquota_imposto_obra), 1::bigint, 'leitura vê a alíquota da obra liberada');
select throws_ok(
  $$select app.gravar_viabilidade('0c000000-0000-4000-8000-0000000000e1', 'Tentativa', current_date, '{"vgv_bruto": 1}')$$,
  '42501', null, 'leitura não grava o estudo'
);
select throws_ok(
  $$select app.gravar_aliquota_imposto('0c000000-0000-4000-8000-0000000000e1', current_date, 0.05)$$,
  '42501', null, 'leitura não grava a alíquota'
);

-- Gerente de obra
reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000e0c1", "role": "authenticated", "aal": "aal1"}', true);
set local role authenticated;

select is((select count(*) from app.estudo_viabilidade), 0::bigint, 'gerente de obra continua sem estudo');
select is((select count(*) from app.estudo_viabilidade_linha), 0::bigint, 'gerente de obra continua sem linhas do estudo');

select * from finish();
rollback;
