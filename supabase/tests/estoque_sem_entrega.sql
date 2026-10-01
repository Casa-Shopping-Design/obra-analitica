-- Obra sem data de entrega fica com prazo nulo e sem o alerta de estoque depois da entrega (migration 0029).
-- Obra Sem Data: duas unidades disponíveis e nenhuma venda, então não há ritmo para vender o estoque.
begin;
create extension if not exists pgtap with schema extensions;
select plan(4);

insert into app.tenant (id, razao_social) values
  ('0e000000-0000-4000-8000-0000000000a9', 'Construtora Sem Data');

insert into app.centro_custo (id, tenant_id, id_origem, nome) values
  ('0c000000-0000-4000-8000-0000000000a9', '0e000000-0000-4000-8000-0000000000a9', 991, 'Obra Sem Data');

insert into staging.unidade (tenant_id, centro_custo_id, id_origem, nome, situacao, data_entrega) values
  ('0e000000-0000-4000-8000-0000000000a9', '0c000000-0000-4000-8000-0000000000a9', 1, 'SD-1', 'D', null),
  ('0e000000-0000-4000-8000-0000000000a9', '0c000000-0000-4000-8000-0000000000a9', 2, 'SD-2', 'D', null);

insert into staging.unidade_valor (tenant_id, centro_custo_id, unidade_id_origem, valor_sugerido) values
  ('0e000000-0000-4000-8000-0000000000a9', '0c000000-0000-4000-8000-0000000000a9', 1, 100),
  ('0e000000-0000-4000-8000-0000000000a9', '0c000000-0000-4000-8000-0000000000a9', 2, 200);

select is(
  (select meses_ate_entrega from marts.estoque_obra where centro_custo_id = '0c000000-0000-4000-8000-0000000000a9'),
  null::integer,
  'sem data de entrega, meses_ate_entrega é nulo'
);

select is(
  (select count(*)::integer from marts.alertas_obra
   where centro_custo_id = '0c000000-0000-4000-8000-0000000000a9' and tipo = 'estoque_apos_entrega'),
  0,
  'sem data de entrega, o alerta de estoque depois da entrega não dispara'
);

update staging.unidade set data_entrega = current_date - 40
where centro_custo_id = '0c000000-0000-4000-8000-0000000000a9';

select is(
  (select meses_ate_entrega from marts.estoque_obra where centro_custo_id = '0c000000-0000-4000-8000-0000000000a9'),
  0,
  'entrega já passada continua contando zero meses'
);

select is(
  (select count(*)::integer from marts.alertas_obra
   where centro_custo_id = '0c000000-0000-4000-8000-0000000000a9' and tipo = 'estoque_apos_entrega'),
  1,
  'com entrega passada e estoque sem ritmo de venda, o alerta dispara'
);

select * from finish();
rollback;
