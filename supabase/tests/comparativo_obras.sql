-- Comparativo entre obras (migration 0027): cada coluna bate com o mart de onde sai, os casos feitos à mão
-- fecham e o gerente vê só a obra dele. Cria os próprios dados para não depender do seed.
--   Obra Leste: quatro unidades, duas disponíveis (100 e 300) e duas vendidas por 1000 cada, uma há três meses
--   e outra no mês passado. VSO de 12 meses: 2 vendas sobre 4 unidades no início da janela, 0,5.
--   Parcela direta de 200 vencida e 800 a vencer: inadimplência de 200 sobre 1000, 0,2.
--   Orçamento de 2000 contra 3000 a pagar estoura; com a inadimplência, são dois alertas. A entrega fica
--   para daqui a 24 meses, senão o estoque disparava o alerta de estoque depois da entrega.
--   Uma tarefa de 1000 planejados com metade medida neste mês: físico 0,5, financeiro zero.
--   Obra Oeste: só um título de 500 a pagar, sem orçamento, para o diretor ter duas obras.
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

create temporary table referencia on commit drop as
select m::date as mes_0,
  (m - interval '3 months')::date as menos_3,
  (m - interval '2 months')::date as menos_2,
  (m - interval '1 month')::date as menos_1,
  (m + interval '1 month')::date as mais_1,
  (m + interval '24 months')::date as mais_24
from date_trunc('month', current_date) as m;
grant select on referencia to authenticated;

insert into app.tenant (id, razao_social) values
  ('0e000000-0000-4000-8000-0000000000c7', 'Construtora Comparativo');

insert into app.centro_custo (id, tenant_id, id_origem, nome) values
  ('0c000000-0000-4000-8000-0000000000c7', '0e000000-0000-4000-8000-0000000000c7', 971, 'Obra Leste'),
  ('0c000000-0000-4000-8000-0000000000c8', '0e000000-0000-4000-8000-0000000000c7', 972, 'Obra Oeste');

insert into auth.users (id, email) values
  ('0a000000-0000-4000-8000-00000000d1c7', 'diretor.comparativo@teste.invalid'),
  ('0a000000-0000-4000-8000-00000000c1c7', 'gerente.comparativo@teste.invalid');

insert into app.usuario_tenant (user_id, tenant_id, perfil) values
  ('0a000000-0000-4000-8000-00000000d1c7', '0e000000-0000-4000-8000-0000000000c7', 'diretor'),
  ('0a000000-0000-4000-8000-00000000c1c7', '0e000000-0000-4000-8000-0000000000c7', 'gerente_obra');

insert into app.usuario_centro_custo (user_id, tenant_id, centro_custo_id) values
  ('0a000000-0000-4000-8000-00000000c1c7', '0e000000-0000-4000-8000-0000000000c7', '0c000000-0000-4000-8000-0000000000c7');

insert into staging.unidade (tenant_id, centro_custo_id, id_origem, nome, situacao, data_entrega)
select '0e000000-0000-4000-8000-0000000000c7'::uuid, '0c000000-0000-4000-8000-0000000000c7'::uuid, id_origem, nome,
  situacao, mais_24
from referencia, lateral (values (1, 'L-1', 'D'), (2, 'L-2', 'D'), (3, 'L-3', 'V'), (4, 'L-4', 'V')) as u (id_origem, nome, situacao);

insert into staging.unidade_valor (tenant_id, centro_custo_id, unidade_id_origem, valor_sugerido) values
  ('0e000000-0000-4000-8000-0000000000c7', '0c000000-0000-4000-8000-0000000000c7', 1, 100),
  ('0e000000-0000-4000-8000-0000000000c7', '0c000000-0000-4000-8000-0000000000c7', 2, 300);

insert into staging.contrato_venda (tenant_id, centro_custo_id, id_origem, data_venda, valor, situacao, unidade_id_origem)
select '0e000000-0000-4000-8000-0000000000c7'::uuid, '0c000000-0000-4000-8000-0000000000c7'::uuid, id_origem, data_venda,
  1000, '1', unidade
from referencia, lateral (values (10, menos_3 + 4, 3), (11, menos_1 + 4, 4)) as c (id_origem, data_venda, unidade);

insert into staging.parcela_receber (tenant_id, centro_custo_id, id_origem, contrato_id_origem, vencimento,
                                     valor_original, saldo, tipo_condicao)
select '0e000000-0000-4000-8000-0000000000c7'::uuid, '0c000000-0000-4000-8000-0000000000c7'::uuid, id_origem, 10,
  vencimento, valor, valor, 'PM'
from referencia, lateral (values (1, menos_2 + 5, 200), (2, mais_1 + 5, 800)) as p (id_origem, vencimento, valor);

insert into staging.titulo_pagar (tenant_id, centro_custo_id, id_origem, vencimento, valor_original, saldo)
select tenant_id::uuid, centro_custo_id::uuid, id_origem, mais_1 + 9, valor, valor
from referencia, lateral (values
  ('0e000000-0000-4000-8000-0000000000c7', '0c000000-0000-4000-8000-0000000000c7', 80, 3000),
  ('0e000000-0000-4000-8000-0000000000c7', '0c000000-0000-4000-8000-0000000000c8', 81, 500)
) as t (tenant_id, centro_custo_id, id_origem, valor);

insert into staging.rateio_titulo (tenant_id, titulo_id_origem, centro_custo_id, valor, fracao) values
  ('0e000000-0000-4000-8000-0000000000c7', 80, '0c000000-0000-4000-8000-0000000000c7', 3000, 1),
  ('0e000000-0000-4000-8000-0000000000c7', 81, '0c000000-0000-4000-8000-0000000000c8', 500, 1);

insert into staging.item_orcamento (tenant_id, centro_custo_id, codigo, descricao, valor_total) values
  ('0e000000-0000-4000-8000-0000000000c7', '0c000000-0000-4000-8000-0000000000c7', '01', 'Estrutura', 2000);

insert into staging.medicao_obra (tenant_id, centro_custo_id, numero_medicao, unidade_construtiva_id, tarefa_id,
                                  data_medicao, situacao_aprovacao, consistente, quantidade_planejada,
                                  quantidade_acumulada, preco_unitario)
select '0e000000-0000-4000-8000-0000000000c7', '0c000000-0000-4000-8000-0000000000c7', 1, 1, 1, mes_0, 'APROVADA', true,
  10, 5, 100
from referencia;

-- Estrutura

select ok(
  (select reloptions @> array['security_invoker=true'] from pg_class where oid = 'marts.comparativo_obras'::regclass),
  'a view roda como quem consulta'
);
select ok(
  has_table_privilege('authenticated', 'marts.comparativo_obras', 'select')
  and not has_table_privilege('anon', 'marts.comparativo_obras', 'select'),
  'usuário logado lê a view e anônimo não'
);

-- Diretor com segundo fator

select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000d1c7", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;

select results_eq(
  'select obra from marts.comparativo_obras order by obra',
  $$values ('Obra Leste'), ('Obra Oeste')$$,
  'diretor compara as duas obras do tenant'
);
select results_eq(
  $$select vgv_total, vgv_vendido, pct_vgv_vendido, resultado_projetado, exposicao_maxima, caixa_atual,
      vencido_direto, repasse_atrasado
    from marts.comparativo_obras where centro_custo_id = '0c000000-0000-4000-8000-0000000000c7'$$,
  $$select vgv_total, vgv_vendido, pct_vgv_vendido, resultado_projetado, exposicao_maxima, caixa_atual,
      vencido_direto, repasse_atrasado
    from marts.posicao_financeira_obra where centro_custo_id = '0c000000-0000-4000-8000-0000000000c7'$$,
  'VGV, resultado, exposição, caixa e vencidos batem com a posição financeira'
);
select results_eq(
  $$select unidades_estoque, valor_estoque, meses_para_vender_estoque
    from marts.comparativo_obras where centro_custo_id = '0c000000-0000-4000-8000-0000000000c7'$$,
  $$select unidades_estoque::integer, valor_estoque, meses_para_vender_estoque
    from marts.estoque_obra where centro_custo_id = '0c000000-0000-4000-8000-0000000000c7'$$,
  'estoque bate com o estoque da obra'
);
select results_eq(
  $$select competencia_execucao, pct_fisico, pct_financeiro, diferenca_financeiro_fisico
    from marts.comparativo_obras where centro_custo_id = '0c000000-0000-4000-8000-0000000000c7'$$,
  $$select competencia, pct_fisico, pct_financeiro, diferenca_financeiro_fisico
    from marts.execucao_fisica_obra where centro_custo_id = '0c000000-0000-4000-8000-0000000000c7'
    order by competencia desc limit 1$$,
  'execução é a do mês mais recente do mart de execução'
);
select results_eq(
  $$select alertas from marts.comparativo_obras order by obra$$,
  $$select count(a.tipo)::integer from app.centro_custo c
      left join marts.alertas_obra a on a.centro_custo_id = c.id
     where c.tenant_id = '0e000000-0000-4000-8000-0000000000c7'
     group by c.nome order by c.nome$$,
  'quantidade de alertas bate com a view de alertas, zero incluído'
);
select results_eq(
  $$select vendas_liquidas_12m, estoque_inicio_12m, vso_12m
    from marts.comparativo_obras where centro_custo_id = '0c000000-0000-4000-8000-0000000000c7'$$,
  $$values (2, 4, 0.5::numeric)$$,
  'VSO de 12 meses: duas vendas sobre quatro unidades no início da janela'
);
select results_eq(
  $$select pct_inadimplencia, margem_projetada = round(resultado_projetado / vgv_total, 4), alertas, pct_fisico
    from marts.comparativo_obras where centro_custo_id = '0c000000-0000-4000-8000-0000000000c7'$$,
  $$values (0.2::numeric, true, 2, 0.5::numeric)$$,
  'inadimplência de 200 sobre 1000, margem sobre o VGV, dois alertas e metade medida'
);

-- Gerente da Obra Leste

reset role;
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-00000000c1c7", "role": "authenticated"}', true);
set local role authenticated;

select results_eq(
  'select centro_custo_id from marts.comparativo_obras',
  $$values ('0c000000-0000-4000-8000-0000000000c7'::uuid)$$,
  'gerente vê só a obra vinculada'
);
select is(
  (select alertas from marts.comparativo_obras),
  2,
  'gerente vê os alertas da obra dele'
);

-- Diretor só com senha

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000d1c7", "role": "authenticated", "aal": "aal1"}', true);
set local role authenticated;

select is((select count(*) from marts.comparativo_obras), 0::bigint, 'diretor sem segundo fator não vê obra nenhuma');

select * from finish();
rollback;
