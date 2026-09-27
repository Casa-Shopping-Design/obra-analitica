-- VGV por obra com caso conhecido: uma vendida por contrato, duas em estoque pelo valor do cadastro
-- e uma fora de venda que não pode entrar. Cria os próprios dados para não depender do seed.
begin;
create extension if not exists pgtap with schema extensions;
select plan(4);

insert into app.tenant (id, razao_social) values
  ('0e000000-0000-4000-8000-0000000000c1', 'Construtora VGV');

insert into app.centro_custo (id, tenant_id, id_origem, nome) values
  ('0c000000-0000-4000-8000-0000000000c1', '0e000000-0000-4000-8000-0000000000c1', 951, 'Obra VGV'),
  ('0c000000-0000-4000-8000-0000000000c2', '0e000000-0000-4000-8000-0000000000c1', 952, 'Obra sem unidade');

insert into staging.unidade (tenant_id, centro_custo_id, id_origem, nome, tipologia, area_privativa, situacao) values
  ('0e000000-0000-4000-8000-0000000000c1', '0c000000-0000-4000-8000-0000000000c1', 1, '2Q-0101', '2Q', 50, 'V'),
  ('0e000000-0000-4000-8000-0000000000c1', '0c000000-0000-4000-8000-0000000000c1', 2, '2Q-0102', '2Q', 50, 'D'),
  ('0e000000-0000-4000-8000-0000000000c1', '0c000000-0000-4000-8000-0000000000c1', 3, '2Q-0103', '2Q', 50, 'C'),
  ('0e000000-0000-4000-8000-0000000000c1', '0c000000-0000-4000-8000-0000000000c1', 4, '2Q-0104', '2Q', 50, 'X');

insert into staging.contrato_venda (tenant_id, centro_custo_id, id_origem, data_venda, valor, situacao, unidade_id_origem) values
  ('0e000000-0000-4000-8000-0000000000c1', '0c000000-0000-4000-8000-0000000000c1', 10, '2026-01-10', 300000, '1', 1);

insert into staging.unidade_valor (tenant_id, centro_custo_id, unidade_id_origem, valor_sugerido) values
  ('0e000000-0000-4000-8000-0000000000c1', '0c000000-0000-4000-8000-0000000000c1', 1, 280000),
  ('0e000000-0000-4000-8000-0000000000c1', '0c000000-0000-4000-8000-0000000000c1', 2, 250000),
  ('0e000000-0000-4000-8000-0000000000c1', '0c000000-0000-4000-8000-0000000000c1', 3, 200000),
  ('0e000000-0000-4000-8000-0000000000c1', '0c000000-0000-4000-8000-0000000000c1', 4, 999999);

select is(
  (select vgv_vendido from marts.posicao_financeira_obra where centro_custo_id = '0c000000-0000-4000-8000-0000000000c1'),
  300000::numeric,
  'vendida entra pelo contrato, não pelo valor do cadastro'
);

select is(
  (select vgv_total from marts.posicao_financeira_obra where centro_custo_id = '0c000000-0000-4000-8000-0000000000c1'),
  750000::numeric,
  'VGV total soma vendido e estoque; fora de venda não entra'
);

select is(
  (select pct_vgv_vendido from marts.posicao_financeira_obra where centro_custo_id = '0c000000-0000-4000-8000-0000000000c1'),
  0.4::numeric,
  'fração vendida é vendido sobre o total'
);

select is(
  (select row(vgv_total, pct_vgv_vendido)::text from marts.posicao_financeira_obra
   where centro_custo_id = '0c000000-0000-4000-8000-0000000000c2'),
  '(0,)',
  'obra sem unidade tem VGV zero e fração nula, sem divisão por zero'
);

select * from finish();
rollback;
