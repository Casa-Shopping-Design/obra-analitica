-- Casos C01, C03 (DRE), C04 e C05 (receitas), C06, C07 (receitas e DRE), C09 (custo), C10 e C22 de
-- docs/financeiro/casos_teste.md, mais as reconciliações R1 a R4, R6, R7 e R9 a R12 e as dos
-- consolidados de receitas e custo. Cada caso limpa o tenant A e grava só o que descreve.
begin;
create extension if not exists pgtap with schema extensions;
select plan(99);

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
  ('7a000000-0000-4000-8000-00000000c00a', 'gerente.financeiro@teste.invalid');
insert into app.usuario_tenant (user_id, tenant_id, perfil) values
  ('7a000000-0000-4000-8000-00000000d00a', '7e000000-0000-4000-8000-00000000000a', 'diretor'),
  ('7a000000-0000-4000-8000-00000000f00a', '7e000000-0000-4000-8000-00000000000a', 'financeiro'),
  ('7a000000-0000-4000-8000-00000000c00a', '7e000000-0000-4000-8000-00000000000a', 'gerente_obra');
insert into app.usuario_centro_custo (user_id, tenant_id, centro_custo_id) values
  ('7a000000-0000-4000-8000-00000000c00a', '7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1');

create function pg_temp.limpar() returns void language sql as $$
  delete from raw.registro where tenant_id = '7e000000-0000-4000-8000-00000000000a';
  select staging.recarregar('7e000000-0000-4000-8000-00000000000a');
  delete from app.mapa_conta_origem where tenant_id = '7e000000-0000-4000-8000-00000000000a';
  delete from app.criterio_reconhecimento where tenant_id = '7e000000-0000-4000-8000-00000000000a';
$$;

create function pg_temp.gravar_raw(p_endpoint text, p_payloads jsonb) returns void language sql as $$
  insert into raw.registro (tenant_id, endpoint, payload, hash_registro)
  select '7e000000-0000-4000-8000-00000000000a', p_endpoint, x, md5(x::text)
  from jsonb_array_elements(p_payloads) x
  on conflict do nothing
$$;

create function pg_temp.mapa(p_conta text, p_categoria text, p_tipo text default 'titulo_pagar') returns void
language sql as $$
  insert into app.mapa_conta_origem (tenant_id, tipo_origem, conta_origem, categoria_codigo, autor)
  values ('7e000000-0000-4000-8000-00000000000a', p_tipo, p_conta, p_categoria, '7a000000-0000-4000-8000-00000000d00a')
$$;

create function pg_temp.unidades(p_centro uuid, p_primeira integer, p_quantidade integer) returns void language sql as $$
  insert into staging.unidade (tenant_id, centro_custo_id, id_origem, nome, situacao)
  select '7e000000-0000-4000-8000-00000000000a', p_centro, n, 'U-' || n, 'D'
  from generate_series(p_primeira, p_primeira + p_quantidade - 1) n
$$;

create function pg_temp.contrato(p_centro uuid, p_id integer, p_valor numeric, p_data date, p_unidade integer,
                                 p_situacao text default '1', p_distrato date default null) returns void
language sql as $$
  insert into staging.contrato_venda (tenant_id, centro_custo_id, id_origem, numero, data_venda, valor, situacao,
                                      data_distrato, unidade_id_origem)
  values ('7e000000-0000-4000-8000-00000000000a', p_centro, p_id, 'C-' || p_id, p_data, p_valor, p_situacao,
          p_distrato, p_unidade);
  insert into staging.contrato_unidade (tenant_id, centro_custo_id, contrato_id_origem, sequencia, unidade_id_origem, principal)
  values ('7e000000-0000-4000-8000-00000000000a', p_centro, p_id, 1, p_unidade, true);
$$;

-- recebimentos em jsonb: [{"d": "2026-01-10", "v": 100.00}]
create function pg_temp.parcela(p_centro uuid, p_contrato integer, p_id integer, p_condicao text, p_vencimento date,
                                p_valor numeric, p_saldo numeric, p_recebimentos jsonb default '[]',
                                p_conta text default null, p_emissao date default null) returns void
language sql as $$
  insert into staging.recebimento (tenant_id, centro_custo_id, contrato_id_origem, parcela_id_origem, sequencia,
                                   data_recebimento, valor, origem, tipo_condicao, tipo_baixa)
  select '7e000000-0000-4000-8000-00000000000a', p_centro, p_contrato, p_id, x.ordem::integer, (x.item->>'d')::date,
         (x.item->>'v')::numeric, case when p_condicao = 'FI' then 'repasse' else 'direta' end, p_condicao,
         case when (x.item->>'v')::numeric < 0 then 'estorno' else 'recebimento' end
  from jsonb_array_elements(p_recebimentos) with ordinality x(item, ordem);
  insert into staging.parcela_receber (tenant_id, centro_custo_id, id_origem, contrato_id_origem, vencimento,
    valor_original, saldo, saldo_corrigido, tipo_condicao, valor_recebido, data_recebimento, conta_origem, data_emissao)
  select '7e000000-0000-4000-8000-00000000000a', p_centro, p_id, p_contrato, p_vencimento, p_valor, p_saldo, p_saldo,
         p_condicao, coalesce(sum((x->>'v')::numeric), 0), max((x->>'d')::date), p_conta, p_emissao
  from jsonb_array_elements(p_recebimentos) x;
$$;

-- pagamentos em jsonb: [{"d": "2026-01-10", "v": 100.00}]
create function pg_temp.titulo(p_centro uuid, p_id integer, p_conta text, p_competencia date, p_vencimento date,
                               p_valor numeric, p_pagamentos jsonb default '[]') returns void
language sql as $$
  insert into staging.pagamento (tenant_id, centro_custo_id, titulo_id_origem, sequencia_pagamento, sequencia_obra,
                                 sequencia_conta, data_pagamento, valor, conta_origem)
  select '7e000000-0000-4000-8000-00000000000a', p_centro, p_id, x.ordem::integer, 1, 1, (x.item->>'d')::date,
         (x.item->>'v')::numeric, p_conta
  from jsonb_array_elements(p_pagamentos) with ordinality x(item, ordem);
  insert into staging.titulo_pagar_apropriacao (tenant_id, centro_custo_id, titulo_id_origem, sequencia_obra,
    sequencia_conta, conta_origem, percentual, principal, valor_original, valor_pago, ajuste_baixa, saldo, vencimento,
    data_competencia, data_ultimo_pagamento)
  select '7e000000-0000-4000-8000-00000000000a', p_centro, p_id, 1, 1, p_conta, 1, true, p_valor,
         coalesce(sum((x->>'v')::numeric), 0), 0, p_valor - coalesce(sum((x->>'v')::numeric), 0), p_vencimento,
         p_competencia, max((x->>'d')::date)
  from jsonb_array_elements(p_pagamentos) x;
$$;

-- Estrutura e segurança dos objetos
select is((select count(*) from app.categoria_gerencial), 19::bigint, 'dezenove categorias fixas');
select is_empty(
  $$select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'app' and c.relname in ('categoria_gerencial', 'mapa_conta_origem', 'criterio_reconhecimento')
      and not (c.relrowsecurity and c.relforcerowsecurity)$$,
  'RLS ligado e forçado nas três tabelas novas'
);
select is_empty(
  $$select tablename, cmd from pg_policies
    where schemaname = 'app' and tablename in ('categoria_gerencial', 'mapa_conta_origem', 'criterio_reconhecimento')
      and permissive = 'PERMISSIVE'
    group by tablename, cmd having count(*) > 1$$,
  'uma política permissiva por tabela e ação'
);
select is_empty(
  $$select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'marts' and c.relkind = 'v'
      and c.relname in ('apropriacao_classificada', 'carteira_recebiveis', 'resumo_receitas_obra', 'resumo_receitas_consolidado',
        'recebimento_mensal', 'recebimento_mensal_consolidado', 'custo_obra_categoria', 'custo_obra_resumo',
        'custo_obra_resumo_consolidado', 'despesa_mensal', 'pendencia_classificacao', 'reconhecimento_obra_mensal',
        'dre_mensal', 'dre_mensal_consolidado')
      and not coalesce(c.reloptions @> array['security_invoker=true'], false)$$,
  'toda view nova com security_invoker'
);
select is(
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'marts' and c.relkind = 'v' and c.reloptions @> array['security_invoker=true']
      and c.relname in ('apropriacao_classificada', 'carteira_recebiveis', 'resumo_receitas_obra', 'resumo_receitas_consolidado',
        'recebimento_mensal', 'recebimento_mensal_consolidado', 'custo_obra_categoria', 'custo_obra_resumo',
        'custo_obra_resumo_consolidado', 'despesa_mensal', 'pendencia_classificacao', 'reconhecimento_obra_mensal',
        'dre_mensal', 'dre_mensal_consolidado')),
  14::bigint, 'as catorze views existem'
);
select is_empty(
  $$select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'marts' and p.proname in ('dre_periodo', 'recebimento_periodo', 'desembolso_periodo')
      and (p.prosecdef or p.provolatile <> 's' or not coalesce(p.proconfig @> array['search_path=""'], false)
           or has_function_privilege('anon', p.oid, 'execute') or not has_function_privilege('authenticated', p.oid, 'execute'))$$,
  'funções de período: invoker, stable, search_path vazio, sem anon, com authenticated'
);
select is_empty(
  $$select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname in ('validar_mapa_conta_origem', 'registrar_validacao_criterio')
      and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute')
           or not coalesce(p.proconfig @> array['search_path=""'], false))$$,
  'funções de gatilho fora do alcance do usuário'
);
select hasnt_column('marts', 'carteira_recebiveis', 'nome_cliente', 'carteira sem nome do comprador');
select is_empty(
  $$select linha_codigo from marts.dre_mensal where linha_codigo ilike '%lucro%' or linha_nome ilike '%lucro%'$$,
  'nenhuma linha chamada lucro'
);

-- C01 venda contratada, receita reconhecida e recebido são números diferentes
select pg_temp.limpar();
select set_config('app.data_referencia', '2026-04-30', true);
insert into staging.unidade (tenant_id, centro_custo_id, id_origem, nome) values
  ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1', 90001, 'T1-101');
select pg_temp.contrato('7c000000-0000-4000-8000-0000000000a1', 5001, 300000.00, '2026-01-10', 90001);
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 5001, 1, 'AT', '2026-01-10', 30000.00, 0, '[{"d": "2026-01-10", "v": 30000.00}]');
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 5001, 2, 'PM', '2026-02-10', 10000.00, 0, '[{"d": "2026-02-10", "v": 10000.00}]');
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 5001, 3, 'PM', '2026-03-10', 10000.00, 0, '[{"d": "2026-03-10", "v": 10000.00}]');
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 5001, 4, 'PM', '2026-04-10', 10000.00, 10000.00);
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 5001, 5, 'FI', '2027-06-30', 240000.00, 240000.00);

select results_eq(
  $$select vgv_contratado_ativo, recebido_direto, recebido_financiamento, vencido_direto, a_vencer_financiamento,
           previsto_proximo_mes_direto, previsto_proximo_mes_financiamento
    from marts.resumo_receitas_obra where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'$$,
  $$values (300000.00::numeric(18,2), 50000.00::numeric(18,2), 0.00::numeric(18,2), 10000.00::numeric(18,2),
            240000.00::numeric(18,2), 0.00::numeric(18,2), 0.00::numeric(18,2))$$,
  'C01: VGV, recebido e carteira da obra'
);
select results_eq(
  $$select linha_codigo, disponivel, valor_mes, valor_acumulado, motivo from marts.dre_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' and competencia = '2026-04-01'
      and linha_codigo in ('receita_bruta', 'resultado_gerencial', 'deducoes') order by linha_ordem$$,
  $$values ('receita_bruta', false, null::numeric(18,2), null::numeric(18,2), 'criterio_nao_validado'),
           ('deducoes', true, 0.00::numeric(18,2), 0.00::numeric(18,2), null),
           ('resultado_gerencial', false, null::numeric(18,2), null::numeric(18,2), 'criterio_nao_validado')$$,
  'C01: sem critério, receita e resultado indisponíveis; dedução é zero conhecido'
);
select results_eq(
  $$select vgv_ativo_fim_mes, receita_reconhecida_acumulada, disponivel, motivo from marts.reconhecimento_obra_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' and competencia = '2026-04-01'$$,
  $$values (300000.00::numeric(18,2), null::numeric(18,2), false, 'criterio_nao_validado')$$,
  'C01: VGV ativo é fato; receita reconhecida fica nula'
);
select is(
  (select count(*) from marts.dre_mensal where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'
     and competencia is not null),
  48::bigint, 'C01: quatro meses contínuos de janeiro a abril, doze linhas cada'
);
select results_eq(
  $$select situacao, parcial, dias_atraso, situacao_contrato, unidade, origem from marts.carteira_recebiveis
    where contrato_id_origem = 5001 order by parcela_id_origem$$,
  $$values ('quitada', false, null::integer, 'ativo', 'T1-101', 'direta'), ('quitada', false, null, 'ativo', 'T1-101', 'direta'),
           ('quitada', false, null, 'ativo', 'T1-101', 'direta'), ('vencida', false, 20, 'ativo', 'T1-101', 'direta'),
           ('a_vencer', false, null, 'ativo', 'T1-101', 'financiamento')$$,
  'C01: carteira por parcela com situação, atraso e origem traduzida'
);

-- C03 competência diferente do pagamento (nível raw)
select pg_temp.limpar();
select pg_temp.gravar_raw('outcome', '[{"billId": 7201, "dueDate": "2026-02-15", "issueDate": "2026-01-20",
  "originalAmount": 5000.00, "balanceAmount": 0, "buildingsCosts": [{"buildingId": 9001, "amount": 5000.00}],
  "paymentsCategories": [{"financialCategoryId": "2.01.001", "financialCategoryRate": 100}],
  "payments": [{"paymentDate": "2026-02-14", "amount": 5000.00}]}]');
select staging.recarregar('7e000000-0000-4000-8000-00000000000a');
select pg_temp.mapa('2.01.001', 'materiais');
select set_config('app.data_referencia', '2026-03-10', true);

select results_eq(
  $$select competencia, linha_codigo, valor_mes, valor_acumulado, cobertura from marts.dre_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'
      and linha_codigo in ('custo_obra_incorrido', 'despesas_administrativas') order by competencia, linha_ordem$$,
  $$values ('2026-01-01'::date, 'despesas_administrativas', 0.00::numeric(18,2), 0.00::numeric(18,2), 1.000000::numeric(9,6)),
           ('2026-01-01'::date, 'custo_obra_incorrido', -5000.00::numeric(18,2), -5000.00::numeric(18,2), 1.000000::numeric(9,6)),
           ('2026-02-01'::date, 'despesas_administrativas', 0.00, 0.00, null),
           ('2026-02-01'::date, 'custo_obra_incorrido', 0.00, -5000.00, null),
           ('2026-03-01'::date, 'despesas_administrativas', 0.00, 0.00, null),
           ('2026-03-01'::date, 'custo_obra_incorrido', 0.00, -5000.00, null)$$,
  'C03: custo de obra no mês da emissão, nunca como despesa; cobertura nula sem lançamento'
);
select results_eq(
  $$select competencia, lancado_competencia, pago, a_pagar, vencido from marts.despesa_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' and categoria_codigo = 'materiais' order by 1$$,
  $$values ('2026-01-01'::date, 5000.00::numeric(18,2), 0.00::numeric(18,2), 0.00::numeric(18,2), 0.00::numeric(18,2)),
           ('2026-02-01'::date, 0.00, 5000.00, 0.00, 0.00)$$,
  'C03: lançado pela competência e pago pelo dia do dinheiro, em colunas separadas'
);
select is_empty($$select 1 from marts.pendencia_classificacao where tenant_id = '7e000000-0000-4000-8000-00000000000a'$$,
  'C03: conta mapeada não é pendência');

-- C04 financiamento separado da entrada direta
select pg_temp.limpar();
select set_config('app.data_referencia', '2026-03-31', true);
select pg_temp.contrato('7c000000-0000-4000-8000-0000000000a1', 5301, 400000.00, '2026-01-05', 90401);
select pg_temp.contrato('7c000000-0000-4000-8000-0000000000a1', 5302, 200000.00, '2025-06-01', 90402);
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 5301, 1, 'AT', '2026-01-05', 40000.00, 0, '[{"d": "2026-01-05", "v": 40000.00}]');
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 5301, 2, 'PM', '2026-06-05', 60000.00, 60000.00);
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 5301, 3, 'FI', '2026-12-20', 300000.00, 300000.00);
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 5302, 1, 'AT', '2025-06-01', 50000.00, 0, '[{"d": "2025-06-01", "v": 50000.00}]');
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 5302, 2, 'FI', '2026-02-10', 150000.00, 0, '[{"d": "2026-02-12", "v": 150000.00}]');

select results_eq(
  $$select vgv_contratado_ativo, recebido_direto, recebido_financiamento, a_vencer_direto, a_vencer_financiamento,
           vencido_direto, vencido_financiamento, contratos_ativos
    from marts.resumo_receitas_obra where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'$$,
  $$values (600000.00::numeric(18,2), 90000.00::numeric(18,2), 150000.00::numeric(18,2), 60000.00::numeric(18,2),
            300000.00::numeric(18,2), 0.00::numeric(18,2), 0.00::numeric(18,2), 2)$$,
  'C04: resumo separa entrada direta de financiamento'
);
select results_eq(
  $$select recebido, previsto_contratual, saldo_em_aberto from marts.recebimento_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' and competencia = '2026-02-01' and origem = 'financiamento'$$,
  $$values (150000.00::numeric(18,2), 150000.00::numeric(18,2), 0.00::numeric(18,2))$$,
  'C04: financiamento recebido em fevereiro'
);
select results_eq(
  $$select r.recebido_direto = p.recebido_direto and r.recebido_financiamento = p.recebido_repasse
       and r.a_vencer_direto = p.a_receber_direto and r.a_vencer_financiamento = p.a_receber_repasse
    from marts.resumo_receitas_obra r join marts.posicao_financeira_obra p using (centro_custo_id)
    where r.centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'$$,
  $$values (true)$$,
  'C04: resumo de receitas bate com a posição da obra'
);
select results_eq(
  $$select origem, recebido, previsto_contratual
    from marts.recebimento_periodo('2026-01-15', '2026-03-20', '7c000000-0000-4000-8000-0000000000a1')$$,
  $$values ('direta', 40000.00::numeric(18,2), 40000.00::numeric(18,2)),
           ('financiamento', 150000.00::numeric(18,2), 150000.00::numeric(18,2))$$,
  'C04: recebimento do período com o mês truncado'
);

-- C05 parcela vencida fica fora da previsão
select pg_temp.limpar();
select set_config('app.data_referencia', '2026-03-20', true);
select pg_temp.contrato('7c000000-0000-4000-8000-0000000000a1', 5401, 200000.00, '2025-10-01', 90501);
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 5401, 1, 'PM', '2026-03-10', 2000.00, 2000.00);
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 5401, 2, 'PM', '2026-04-10', 2000.00, 2000.00);
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 5401, 3, 'FI', '2026-03-01', 100000.00, 100000.00);

select results_eq(
  $$select previsto_proximo_mes_direto, previsto_proximo_mes_financiamento, vencido_direto, vencido_financiamento, a_vencer_direto
    from marts.resumo_receitas_obra where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'$$,
  $$values (2000.00::numeric(18,2), 0.00::numeric(18,2), 2000.00::numeric(18,2), 100000.00::numeric(18,2), 2000.00::numeric(18,2))$$,
  'C05: vencida nunca entra no previsto do próximo mês'
);

-- C06 próximo mês na virada do ano
select pg_temp.limpar();
select set_config('app.data_referencia', '2026-12-15', true);
select pg_temp.contrato('7c000000-0000-4000-8000-0000000000a1', 5501, 100000.00, '2026-06-01', 90601);
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 5501, n, 'PM', v, s, s)
from (values (1, '2026-12-10'::date, 800.00), (2, '2026-12-20'::date, 1000.00), (3, '2027-01-10'::date, 1500.00),
             (4, '2027-01-31'::date, 500.00), (5, '2027-02-01'::date, 700.00)) as p(n, v, s);

select results_eq(
  $$select previsto_proximo_mes_direto, vencido_direto, a_vencer_direto from marts.resumo_receitas_obra
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'$$,
  $$values (2000.00::numeric(18,2), 800.00::numeric(18,2), 3700.00::numeric(18,2))$$,
  'C06: próximo mês de dezembro é janeiro do ano seguinte'
);
select set_config('app.data_referencia', '2026-12-20', true);
select results_eq(
  $$select situacao, dias_atraso from marts.carteira_recebiveis where contrato_id_origem = 5501 and parcela_id_origem = 2$$,
  $$values ('a_vencer', null::integer)$$,
  'C06: no dia do vencimento a parcela ainda é a vencer'
);
select set_config('app.data_referencia', '2026-12-21', true);
select results_eq(
  $$select situacao, dias_atraso from marts.carteira_recebiveis where contrato_id_origem = 5501 and parcela_id_origem = 2$$,
  $$values ('vencida', 1)$$,
  'C06: um dia depois está vencida com um dia de atraso'
);

-- C07 distrato, estorno e renegociação (nível raw)
select pg_temp.limpar();
select pg_temp.gravar_raw('sales', '[
  {"id": 5601, "enterpriseId": 9001, "contractDate": "2025-10-01", "situation": "3", "cancellationDate": "2026-05-10", "value": 250000.00, "units": [{"id": 90601, "main": true}]},
  {"id": 5602, "enterpriseId": 9001, "contractDate": "2026-03-01", "situation": "1", "value": 100000.00, "units": [{"id": 90602, "main": true}]},
  {"id": 5603, "enterpriseId": 9001, "contractDate": "2026-01-15", "situation": "1", "value": 120000.00, "units": [{"id": 90603, "main": true}]}]');
select pg_temp.gravar_raw('income', '[
  {"projectId": 9001, "billId": 5601, "installmentId": 1, "paymentTerm": {"id": "AT"}, "dueDate": "2025-10-01", "originalAmount": 25000.00,
   "balanceAmount": 0, "correctedBalanceAmount": 0, "receipts": [{"paymentDate": "2025-10-01", "amount": 25000.00}]},
  {"projectId": 9001, "billId": 5601, "installmentId": 2, "paymentTerm": {"id": "PM"}, "dueDate": "2026-06-10", "originalAmount": 5000.00,
   "balanceAmount": 5000.00, "correctedBalanceAmount": 5000.00, "receipts": []},
  {"projectId": 9001, "billId": 5602, "installmentId": 1, "paymentTerm": {"id": "PM"}, "dueDate": "2026-04-10", "originalAmount": 3000.00,
   "balanceAmount": 3000.00, "correctedBalanceAmount": 3000.00,
   "receipts": [{"paymentDate": "2026-04-10", "amount": 3000.00}, {"paymentDate": "2026-04-20", "amount": -3000.00}]},
  {"projectId": 9001, "billId": 5603, "installmentId": 1, "paymentTerm": {"id": "PM"}, "dueDate": "2026-03-10", "originalAmount": 4000.00,
   "balanceAmount": 0, "correctedBalanceAmount": 0, "receipts": []},
  {"projectId": 9001, "billId": 5603, "installmentId": 2, "paymentTerm": {"id": "PM"}, "dueDate": "2026-07-10", "originalAmount": 2000.00,
   "balanceAmount": 2000.00, "correctedBalanceAmount": 2000.00, "receipts": []},
  {"projectId": 9001, "billId": 5603, "installmentId": 3, "paymentTerm": {"id": "PM"}, "dueDate": "2026-08-10", "originalAmount": 2000.00,
   "balanceAmount": 2000.00, "correctedBalanceAmount": 2000.00, "receipts": []}]');
select pg_temp.gravar_raw('outcome', '[{"billId": 7601, "dueDate": "2026-06-01", "issueDate": "2026-05-20", "originalAmount": 10000.00,
  "balanceAmount": 10000.00, "paymentsCategories": [{"financialCategoryId": "2.09.001", "financialCategoryRate": 100}], "payments": []}]');
select staging.recarregar('7e000000-0000-4000-8000-00000000000a');
select pg_temp.mapa('2.09.001', 'devolucao_distrato');
select set_config('app.data_referencia', '2026-06-15', true);

select results_eq(
  $$select contrato_id_origem, parcela_id_origem, situacao, valor_recebido, saldo, parcial, dias_atraso, situacao_contrato
    from marts.carteira_recebiveis where tenant_id = '7e000000-0000-4000-8000-00000000000a' order by 1, 2$$,
  $$values (5601, 1, 'quitada', 25000.00::numeric(18,2), 0.00::numeric(18,2), false, null::integer, 'distratado'),
           (5601, 2, 'cancelada_distrato', 0.00, 5000.00, false, null, 'distratado'),
           (5602, 1, 'vencida', 0.00, 3000.00, false, 66, 'ativo'),
           (5603, 1, 'baixada_sem_recebimento', 0.00, 0.00, false, null, 'ativo'),
           (5603, 2, 'a_vencer', 0.00, 2000.00, false, null, 'ativo'),
           (5603, 3, 'a_vencer', 0.00, 2000.00, false, null, 'ativo')$$,
  'C07: situação de cada parcela na carteira'
);
select results_eq(
  $$select contratos_ativos, contratos_distratados, vgv_contratado_ativo, recebido_direto, vencido_direto, a_vencer_direto,
           saldo_distratado
    from marts.resumo_receitas_obra where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'$$,
  $$values (2, 1, 220000.00::numeric(18,2), 25000.00::numeric(18,2), 3000.00::numeric(18,2), 4000.00::numeric(18,2),
            5000.00::numeric(18,2))$$,
  'C07: distratado fora do VGV e da carteira; recebido dele fica'
);
select results_eq(
  $$select competencia, recebido, previsto_contratual, saldo_em_aberto from marts.recebimento_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' and origem = 'direta' order by 1$$,
  $$values ('2025-10-01'::date, 25000.00::numeric(18,2), 25000.00::numeric(18,2), 0.00::numeric(18,2)),
           ('2026-04-01'::date, 0.00, 3000.00, 3000.00),
           ('2026-07-01'::date, 0.00, 2000.00, 2000.00),
           ('2026-08-01'::date, 0.00, 2000.00, 2000.00)$$,
  'C07: estorno zera o recebido; renegociada e distratada fora do previsto'
);
select results_eq(
  $$select linha_codigo, valor_mes, disponivel from marts.dre_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000ae' and competencia = '2026-05-01'
      and linha_codigo in ('fora_do_resultado', 'resultado_gerencial') order by linha_ordem$$,
  $$values ('resultado_gerencial', 0.00::numeric(18,2), true), ('fora_do_resultado', -10000.00::numeric(18,2), true)$$,
  'C07: devolução de distrato fora do resultado da empresa'
);

-- C09 custo futuro sem duplicar os títulos
select pg_temp.limpar();
select set_config('app.data_referencia', '2026-09-15', true);
insert into staging.item_orcamento (tenant_id, centro_custo_id, codigo, descricao, valor_total) values
  ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1', '01', 'Estrutura', 600000.00),
  ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1', '02', 'Acabamento', 400000.00);
select pg_temp.titulo('7c000000-0000-4000-8000-0000000000a1', 7901, null, '2026-08-01', '2026-08-10', 300000.00, '[{"d": "2026-08-10", "v": 300000.00}]');
select pg_temp.titulo('7c000000-0000-4000-8000-0000000000a1', 7902, null, '2026-09-01', '2026-10-05', 150000.00);
select pg_temp.titulo('7c000000-0000-4000-8000-0000000000a1', 7903, null, '2026-08-15', '2026-09-01', 50000.00);

select results_eq(
  $$select orcamento_vigente, custo_lancado, desembolsado, em_aberto_vencido, em_aberto_a_vencer, ajuste_baixa,
           remanescente_sem_titulo, estimativa_conclusao, desvio, motivo
    from marts.custo_obra_resumo where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'$$,
  $$values (1000000.00::numeric(18,2), 500000.00::numeric(18,2), 300000.00::numeric(18,2), 50000.00::numeric(18,2),
            150000.00::numeric(18,2), 0.00::numeric(18,2), 500000.00::numeric(18,2), 1000000.00::numeric(18,2),
            0.00::numeric(18,2), null::text)$$,
  'C09: remanescente é só o que falta lançar; o orçamento nunca soma com os títulos'
);
select results_eq(
  $$select p.custo_a_incorrer, p.estouro_orcamento from marts.posicao_financeira_obra p
    where p.centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'$$,
  $$values (500000.00, 0.00)$$,
  'C09: posição com o mesmo remanescente'
);
select results_eq(
  $$select categoria_codigo, categoria_nome, orcamento_vigente, custo_lancado from marts.custo_obra_categoria
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'$$,
  $$values (null::text, 'Sem categoria', 1000000.00::numeric(18,2), 500000.00::numeric(18,2))$$,
  'C09: sem mapeamento, orçamento e títulos ficam em Sem categoria'
);
select pg_temp.titulo('7c000000-0000-4000-8000-0000000000a1', 7904, null, '2026-09-10', '2026-10-20', 600000.00);
select results_eq(
  $$select r.custo_lancado, r.remanescente_sem_titulo, r.estimativa_conclusao, r.desvio, p.estouro_orcamento, p.custo_a_incorrer
    from marts.custo_obra_resumo r join marts.posicao_financeira_obra p using (centro_custo_id)
    where r.centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'$$,
  $$values (1100000.00::numeric(18,2), 0.00::numeric(18,2), 1100000.00::numeric(18,2), 100000.00::numeric(18,2),
            100000.00, 0.00)$$,
  'C09: com estouro, desvio igual ao estouro da posição e remanescente zero'
);

-- C10 categoria não mapeada e dado ausente diferente de zero
select pg_temp.limpar();
select set_config('app.data_referencia', '2026-06-10', true);
select pg_temp.mapa('2.01.001', 'materiais');
insert into app.criterio_reconhecimento (tenant_id, metodo, autor)
values ('7e000000-0000-4000-8000-00000000000a', 'percentual_conclusao', '7a000000-0000-4000-8000-00000000f00a');
select pg_temp.titulo('7c000000-0000-4000-8000-0000000000a1', 7911, '9.99.999', '2026-05-05', '2026-07-10', 2000.00);
select pg_temp.titulo('7c000000-0000-4000-8000-0000000000a1', 7912, null, '2026-05-06', '2026-07-10', 1000.00);
select pg_temp.titulo('7c000000-0000-4000-8000-0000000000a1', 7913, '2.01.001', '2026-05-07', '2026-07-10', 7000.00);
select pg_temp.titulo('7c000000-0000-4000-8000-0000000000a1', 7914, '2.01.001', null, '2026-07-10', 500.00);
select pg_temp.contrato('7c000000-0000-4000-8000-0000000000a1', 5801, 100000.00, '2026-05-01', 91801);
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 5801, 1, 'PM', '2026-07-10', 1000.00, 1000.00);

select results_eq(
  $$select conta_origem, quantidade_lancamentos, valor_envolvido, participacao, primeira_competencia
    from marts.pendencia_classificacao where tenant_id = '7e000000-0000-4000-8000-00000000000a' and tipo_origem = 'titulo_pagar'
    order by conta_origem nulls last$$,
  $$values ('9.99.999', 1, 2000.00::numeric(18,2), 0.190476::numeric(9,6), '2026-05-01'::date),
           (null, 1, 1000.00, 0.095238, '2026-05-01'::date)$$,
  'C10: conta desconhecida e conta nula viram pendência com valor e participação'
);
select results_eq(
  $$select linha_codigo, valor_mes, valor_total_lancado, valor_com_categoria, cobertura from marts.dre_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' and competencia = '2026-05-01'
      and linha_codigo in ('custo_obra_incorrido', 'sem_categoria') order by linha_ordem$$,
  $$values ('custo_obra_incorrido', -7000.00::numeric(18,2), 10000.00::numeric(18,2), 7000.00::numeric(18,2), 0.700000::numeric(9,6)),
           ('sem_categoria', -3000.00, 10000.00, 7000.00, 0.700000)$$,
  'C10: sem categoria fica na linha própria e reduz a cobertura'
);
select results_eq(
  $$select competencia, valor_mes from marts.dre_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' and linha_codigo = 'sem_data_competencia'$$,
  $$values (null::date, -500.00::numeric(18,2))$$,
  'C10: título sem competência não cai em mês nenhum'
);
select results_eq(
  $$select valor_mes, disponivel from marts.dre_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' and competencia = '2026-06-01' and linha_codigo = 'deducoes'$$,
  $$values (0.00::numeric(18,2), true)$$,
  'C10: dedução de junho é zero conhecido'
);
select results_eq(
  $$select disponivel, motivo, poc, custo_incorrido_acumulado, custo_total_estimado from marts.reconhecimento_obra_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' and competencia = '2026-05-01'$$,
  $$values (false, 'orcamento_ausente', null::numeric(9,6), 7000.00::numeric(18,2), null::numeric(18,2))$$,
  'C10: sem orçamento o POC fica indisponível, o custo incorrido continua'
);
select results_eq(
  $$select orcamento_vigente, remanescente_sem_titulo, estimativa_conclusao, desvio, orcamento_original,
           compromissos_nao_faturados, motivo, cobertura_classificacao
    from marts.custo_obra_resumo where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'$$,
  $$values (null::numeric(18,2), null::numeric(18,2), null::numeric(18,2), null::numeric(18,2), null::numeric(18,2),
            null::numeric(18,2), 'orcamento_ausente', 0.714286::numeric(9,6))$$,
  'C10: sem orçamento, colunas dependentes nulas e não zero'
);
select results_eq(
  $$select custo_orcado, orcamento_carregado from marts.posicao_financeira_obra
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'$$,
  $$values (0.00::numeric, false)$$,
  'C10: posição mantém custo_orcado zero por compatibilidade'
);
select results_eq(
  $$select situacao, dias_atraso from marts.carteira_recebiveis where contrato_id_origem = 5801$$,
  $$values ('a_vencer', null::integer)$$,
  'C10: parcela a vencer tem atraso nulo, não zero'
);
select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000f00a", "role": "authenticated"}', true);
set local role authenticated;
select throws_ok(
  $$insert into app.mapa_conta_origem (tenant_id, tipo_origem, conta_origem, categoria_codigo)
    values ('7e000000-0000-4000-8000-00000000000a', 'titulo_pagar', '9.99.998', 'venda_imoveis')$$,
  '23514', null, 'C10: título não mapeia para categoria de entrada'
);
select throws_ok(
  $$insert into app.mapa_conta_origem (tenant_id, tipo_origem, conta_origem, categoria_codigo)
    values ('7e000000-0000-4000-8000-00000000000a', 'parcela_receber', '1.99.999', 'materiais')$$,
  '23514', null, 'C10: parcela não mapeia para categoria de saída'
);
select throws_ok(
  $$insert into app.mapa_conta_origem (tenant_id, tipo_origem, conta_origem, categoria_codigo)
    values ('7e000000-0000-4000-8000-00000000000a', 'orcamento', '01', 'corretagem')$$,
  '23514', null, 'C10: item de orçamento só mapeia para custo do imóvel'
);
select lives_ok(
  $$insert into app.mapa_conta_origem (tenant_id, tipo_origem, conta_origem, categoria_codigo)
    values ('7e000000-0000-4000-8000-00000000000a', 'titulo_pagar', '9.99.999', 'materiais')$$,
  'C10: financeiro classifica a conta pendente'
);
select is_empty(
  $$select 1 from marts.pendencia_classificacao where tenant_id = '7e000000-0000-4000-8000-00000000000a'
      and tipo_origem = 'titulo_pagar' and conta_origem = '9.99.999'$$,
  'C10: conta classificada sai da pendência'
);
select is(
  (select cobertura from marts.dre_mensal where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'
     and competencia = '2026-05-01' and linha_codigo = 'custo_obra_incorrido'),
  0.900000::numeric(9,6), 'C10: cobertura de maio sobe para 90%'
);
reset role;

-- C22 percentual de conclusão com números conhecidos
select pg_temp.limpar();
select set_config('app.data_referencia', '2026-02-20', true);
select pg_temp.mapa(c, g) from (values ('2.01.001', 'materiais'), ('2.02.001', 'tributos_receita'), ('2.03.001', 'corretagem'),
  ('2.04.001', 'despesas_administrativas'), ('2.05.001', 'despesas_financeiras')) as m(c, g);
select pg_temp.unidades('7c000000-0000-4000-8000-0000000000a1', 91001, 10);
insert into staging.item_orcamento (tenant_id, centro_custo_id, codigo, descricao, valor_total) values
  ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1', '01', 'Obra', 2000000.00);
select pg_temp.contrato('7c000000-0000-4000-8000-0000000000a1', 7000 + n, 250000.00, '2026-01-15', 91000 + n)
from generate_series(1, 4) n;
select pg_temp.titulo('7c000000-0000-4000-8000-0000000000a1', t, c, d, '2026-03-10', v)
from (values (8201, '2.01.001', '2026-01-20'::date, 200000.00), (8202, '2.01.001', '2026-02-10'::date, 300000.00),
             (8203, '2.02.001', '2026-02-11'::date, 5000.00), (8204, '2.03.001', '2026-02-12'::date, 10000.00),
             (8205, '2.04.001', '2026-02-13'::date, 3000.00), (8206, '2.05.001', '2026-02-14'::date, 2000.00)) as t(t, c, d, v);

select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000f00a", "role": "authenticated"}', true);
set local role authenticated;
select lives_ok(
  $$insert into app.criterio_reconhecimento (tenant_id, metodo, validado_por)
    values ('7e000000-0000-4000-8000-00000000000a', 'percentual_conclusao', '7a000000-0000-4000-8000-00000000d00a')$$,
  'C22: financeiro valida o percentual de conclusão'
);
reset role;
select results_eq(
  $$select validado_por, validado_em is not null, autor from app.criterio_reconhecimento
    where tenant_id = '7e000000-0000-4000-8000-00000000000a'$$,
  $$values ('7a000000-0000-4000-8000-00000000f00a'::uuid, true, '7a000000-0000-4000-8000-00000000f00a'::uuid)$$,
  'C22: validado_por é o do JWT, não o mandado'
);
select results_eq(
  $$select competencia, custo_incorrido_acumulado, poc, vgv_ativo_fim_mes, fracao_vendida, receita_reconhecida_acumulada,
           receita_reconhecida_mes, custo_reconhecido_acumulado, custo_reconhecido_mes, custo_total_estimado, disponivel
    from marts.reconhecimento_obra_mensal where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' order by 1$$,
  $$values ('2026-01-01'::date, 200000.00::numeric(18,2), 0.100000::numeric(9,6), 1000000.00::numeric(18,2),
            0.400000::numeric(9,6), 100000.00::numeric(18,2), 100000.00::numeric(18,2), 80000.00::numeric(18,2),
            80000.00::numeric(18,2), 2000000.00::numeric(18,2), true),
           ('2026-02-01'::date, 500000.00, 0.250000, 1000000.00, 0.400000, 250000.00, 150000.00, 200000.00, 120000.00,
            2000000.00, true)$$,
  'C22: POC, fração vendida, receita e custo reconhecidos do caso conhecido'
);
select results_eq(
  $$select linha_codigo, sum(valor_mes) filter (where competencia = '2026-01-01'),
           sum(valor_mes) filter (where competencia = '2026-02-01'),
           sum(valor_acumulado) filter (where competencia = '2026-02-01')
    from marts.dre_mensal where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' and competencia is not null
      and linha_ordem <= 100
    group by linha_codigo, linha_ordem order by linha_ordem$$,
  $$values ('receita_bruta', 100000.00::numeric, 150000.00::numeric, 250000.00::numeric),
           ('deducoes', 0.00, -5000.00, -5000.00),
           ('receita_liquida', 100000.00, 145000.00, 245000.00),
           ('custo_imovel_vendido', -80000.00, -120000.00, -200000.00),
           ('resultado_bruto', 20000.00, 25000.00, 45000.00),
           ('despesas_comerciais', 0.00, -10000.00, -10000.00),
           ('despesas_administrativas', 0.00, -3000.00, -3000.00),
           ('resultado_financeiro', 0.00, -2000.00, -2000.00),
           ('resultado_gerencial', 20000.00, 10000.00, 30000.00),
           ('custo_obra_incorrido', -200000.00, -300000.00, -500000.00)$$,
  'C22: DRE mês a mês e acumulado do caso conhecido'
);
select results_eq(
  $$select valor_total_lancado, cobertura from marts.dre_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' and competencia = '2026-02-01' and linha_codigo = 'resultado_gerencial'$$,
  $$values (320000.00::numeric(18,2), 1.000000::numeric(9,6))$$,
  'C22: fevereiro todo classificado'
);
select results_eq(
  $$select linha_codigo, valor_periodo, disponivel from marts.dre_periodo('2026-01-01', '2026-02-01', '7c000000-0000-4000-8000-0000000000a1')
    where linha_codigo in ('receita_bruta', 'resultado_gerencial') order by linha_ordem$$,
  $$values ('receita_bruta', 250000.00::numeric(18,2), true), ('resultado_gerencial', 30000.00::numeric(18,2), true)$$,
  'C22: DRE do período'
);
select results_eq(
  $$select custo_lancado, remanescente_sem_titulo from marts.custo_obra_resumo
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'$$,
  $$values (520000.00::numeric(18,2), 1480000.00::numeric(18,2))$$,
  'C22: toda conta da obra conta contra o orçamento (P14)'
);
select results_eq(
  $$select r.vgv_contratado_ativo, k.receita_reconhecida_acumulada, r.recebido_direto + r.recebido_financiamento
    from marts.resumo_receitas_obra r join marts.reconhecimento_obra_mensal k using (centro_custo_id)
    where r.centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' and k.competencia = '2026-02-01'$$,
  $$values (1000000.00::numeric(18,2), 250000.00::numeric(18,2), 0.00::numeric(18,2))$$,
  'C22: VGV contratado, receita reconhecida e recebido são três números diferentes'
);

-- C22 com distrato do contrato 7003 em fevereiro
update staging.contrato_venda set situacao = '3', data_distrato = '2026-02-10' where id_origem = 7003;
select results_eq(
  $$select competencia, vgv_ativo_fim_mes, fracao_vendida, receita_reconhecida_acumulada, receita_reconhecida_mes,
           custo_reconhecido_acumulado, custo_reconhecido_mes
    from marts.reconhecimento_obra_mensal where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' order by 1$$,
  $$values ('2026-01-01'::date, 1000000.00::numeric(18,2), 0.400000::numeric(9,6), 100000.00::numeric(18,2),
            100000.00::numeric(18,2), 80000.00::numeric(18,2), 80000.00::numeric(18,2)),
           ('2026-02-01'::date, 750000.00, 0.300000, 187500.00, 87500.00, 150000.00, 70000.00)$$,
  'C22: distrato reduz receita e custo no mês do distrato; janeiro não muda'
);
select results_eq(
  $$select linha_codigo, valor_mes from marts.dre_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' and competencia = '2026-02-01'
      and linha_codigo in ('resultado_bruto', 'resultado_gerencial') order by linha_ordem$$,
  $$values ('resultado_bruto', 12500.00::numeric(18,2)), ('resultado_gerencial', -2500.00::numeric(18,2))$$,
  'C22: resultado de fevereiro com o distrato'
);
update staging.contrato_venda set situacao = '1', data_distrato = null where id_origem = 7003;

-- C22 sem critério
select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000f00a", "role": "authenticated"}', true);
set local role authenticated;
select lives_ok(
  $$update app.criterio_reconhecimento set metodo = 'nao_definido' where tenant_id = '7e000000-0000-4000-8000-00000000000a'$$,
  'C22: financeiro volta o critério para não definido'
);
reset role;
select results_eq(
  $$select validado_por, validado_em from app.criterio_reconhecimento where tenant_id = '7e000000-0000-4000-8000-00000000000a'$$,
  $$values (null::uuid, null::timestamptz)$$,
  'C22: sem critério, validação nula'
);
select is_empty(
  $$select linha_codigo from marts.dre_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' and competencia is not null
      and linha_codigo in ('receita_bruta', 'receita_liquida', 'custo_imovel_vendido', 'resultado_bruto', 'resultado_gerencial')
      and (disponivel or valor_mes is not null or valor_acumulado is not null or motivo is distinct from 'criterio_nao_validado')$$,
  'C22: as cinco linhas dependentes do critério ficam indisponíveis e nulas em todos os meses'
);
select results_eq(
  $$select linha_codigo, valor_mes, disponivel from marts.dre_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' and competencia = '2026-02-01'
      and linha_codigo in ('deducoes', 'despesas_comerciais', 'custo_obra_incorrido') order by linha_ordem$$,
  $$values ('deducoes', -5000.00::numeric(18,2), true), ('despesas_comerciais', -10000.00::numeric(18,2), true),
           ('custo_obra_incorrido', -300000.00::numeric(18,2), true)$$,
  'C22: linhas por competência seguem disponíveis'
);
select results_eq(
  $$select competencia, poc, custo_incorrido_acumulado from marts.reconhecimento_obra_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' order by 1$$,
  $$values ('2026-01-01'::date, null::numeric(9,6), 200000.00::numeric(18,2)), ('2026-02-01'::date, null, 500000.00)$$,
  'C22: POC nulo, custo incorrido continua'
);
select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000d00a", "role": "authenticated"}', true);
set local role authenticated;
select results_eq(
  $$select disponivel, motivo, valor_mes, quantidade_centros from marts.dre_mensal_consolidado
    where competencia = '2026-02-01' and linha_codigo = 'resultado_gerencial'$$,
  $$values (false, 'criterio_nao_validado', null::numeric(18,2), 1)$$,
  'C22: consolidado do diretor indisponível pelo motivo comum'
);
select results_eq(
  $$select valor_periodo, disponivel, motivo from marts.dre_periodo('2026-01-01', '2026-02-28')
    where linha_codigo = 'resultado_gerencial'$$,
  $$values (null::numeric(18,2), false, 'criterio_nao_validado')$$,
  'C22: DRE do período consolidado indisponível'
);
reset role;

-- Critério por obra vence o do tenant; motivos de bloqueio em ordem
insert into app.criterio_reconhecimento (tenant_id, centro_custo_id, metodo, autor)
values ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1', 'percentual_conclusao',
        '7a000000-0000-4000-8000-00000000f00a');
select is(
  (select receita_reconhecida_acumulada from marts.reconhecimento_obra_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' and competencia = '2026-02-01'),
  250000.00::numeric(18,2), 'critério da obra vale sobre o do tenant'
);
select pg_temp.titulo('7c000000-0000-4000-8000-0000000000a1', 8207, '2.01.001', null, '2026-03-10', 1000.00);
select results_eq(
  $$select competencia, motivo from marts.reconhecimento_obra_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' order by 1$$,
  $$values ('2026-01-01'::date, 'custo_sem_competencia'), ('2026-02-01'::date, 'custo_sem_competencia')$$,
  'título sem competência bloqueia o reconhecimento da obra'
);
select pg_temp.titulo('7c000000-0000-4000-8000-0000000000a1', 8208, '2.99.001', '2026-02-05', '2026-03-10', 1000.00);
select results_eq(
  $$select competencia, motivo from marts.reconhecimento_obra_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' order by 1$$,
  $$values ('2026-01-01'::date, 'custo_sem_competencia'), ('2026-02-01'::date, 'custo_sem_categoria')$$,
  'custo sem categoria bloqueia a partir do mês em que aparece e vem antes da falta de competência'
);
select results_eq(
  $$select linha_codigo, disponivel, motivo from marts.dre_periodo('2026-01-01', '2026-02-01', '7c000000-0000-4000-8000-0000000000a1')
    where linha_codigo = 'receita_bruta'$$,
  $$values ('receita_bruta', false, 'custo_sem_categoria')$$,
  'período de uma obra mostra o motivo do mês indisponível mais recente'
);
delete from staging.unidade where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1';
select is(
  (select motivo from marts.reconhecimento_obra_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' and competencia = '2026-01-01'),
  'unidades_ausentes', 'obra sem unidades não calcula fração vendida'
);

-- Base mista para as reconciliações: payloads de C02, C07 e C08, orçamento em T1, contas mapeadas,
-- uma parcela de receita financeira e uma de aporte em T2.
select pg_temp.limpar();
select pg_temp.gravar_raw('sales', '[
  {"id": 5101, "enterpriseId": 9001, "number": "T1-5101", "contractDate": "2026-01-01", "situation": "1", "value": 2000.00, "units": [{"id": 90011, "main": true}]},
  {"id": 5601, "enterpriseId": 9001, "contractDate": "2025-10-01", "situation": "3", "cancellationDate": "2026-05-10", "value": 250000.00, "units": [{"id": 90601, "main": true}]},
  {"id": 5602, "enterpriseId": 9001, "contractDate": "2026-03-01", "situation": "1", "value": 100000.00, "units": [{"id": 90602, "main": true}]},
  {"id": 5901, "enterpriseId": 9002, "contractDate": "2026-02-01", "situation": "1", "value": 300000.00, "units": [{"id": 92901, "main": true}]}]');
select pg_temp.gravar_raw('units', '[
  {"id": 90011, "enterpriseId": 9001, "name": "T1-11"}, {"id": 90601, "enterpriseId": 9001, "name": "T1-61"},
  {"id": 90602, "enterpriseId": 9001, "name": "T1-62"}, {"id": 92901, "enterpriseId": 9002, "name": "T2-01"}]');
select pg_temp.gravar_raw('income', '[
  {"projectId": 9001, "billId": 5101, "installmentId": 1, "dueDate": "2026-01-10", "issueDate": "2026-01-01",
   "originalAmount": 1000.00, "balanceAmount": 0, "correctedBalanceAmount": 0, "paymentTerm": {"id": "PM"},
   "receiptsCategories": [{"financialCategoryId": "1.01.001"}],
   "receipts": [{"paymentDate": "2026-02-05", "amount": 400.00}, {"paymentDate": "2026-03-07", "amount": 600.00}]},
  {"projectId": 9001, "billId": 5101, "installmentId": 2, "dueDate": "2026-02-10", "issueDate": "2026-01-01",
   "originalAmount": 1000.00, "balanceAmount": 700.00, "correctedBalanceAmount": 700.00, "paymentTerm": {"id": "PM"},
   "receiptsCategories": [{"financialCategoryId": "1.01.001"}], "receipts": [{"paymentDate": "2026-02-10", "amount": 300.00}]},
  {"projectId": 9001, "billId": 5601, "installmentId": 1, "paymentTerm": {"id": "AT"}, "dueDate": "2025-10-01", "originalAmount": 25000.00,
   "balanceAmount": 0, "correctedBalanceAmount": 0, "receipts": [{"paymentDate": "2025-10-01", "amount": 25000.00}]},
  {"projectId": 9001, "billId": 5601, "installmentId": 2, "paymentTerm": {"id": "PM"}, "dueDate": "2026-06-10", "originalAmount": 5000.00,
   "balanceAmount": 5000.00, "correctedBalanceAmount": 5000.00, "receipts": []},
  {"projectId": 9001, "billId": 5602, "installmentId": 1, "paymentTerm": {"id": "PM"}, "dueDate": "2026-04-10", "originalAmount": 3000.00,
   "balanceAmount": 3000.00, "correctedBalanceAmount": 3000.00,
   "receipts": [{"paymentDate": "2026-04-10", "amount": 3000.00}, {"paymentDate": "2026-04-20", "amount": -3000.00}]},
  {"projectId": 9002, "billId": 5901, "installmentId": 1, "paymentTerm": {"id": "FI"}, "dueDate": "2026-05-10", "originalAmount": 200000.00,
   "balanceAmount": 0, "correctedBalanceAmount": 0, "receipts": [{"paymentDate": "2026-05-12", "amount": 200000.00}]},
  {"projectId": 9002, "billId": 5901, "installmentId": 2, "paymentTerm": {"id": "FI"}, "dueDate": "2026-08-10", "originalAmount": 100000.00,
   "balanceAmount": 100000.00, "correctedBalanceAmount": 100000.00, "receipts": []},
  {"projectId": 9002, "billId": 5902, "installmentId": 1, "paymentTerm": {"id": "PM"}, "dueDate": "2026-03-01", "issueDate": "2026-03-01",
   "originalAmount": 1500.00, "balanceAmount": 0, "correctedBalanceAmount": 0,
   "receiptsCategories": [{"financialCategoryId": "1.09.001"}], "receipts": [{"paymentDate": "2026-03-01", "amount": 1500.00}]},
  {"projectId": 9002, "billId": 5903, "installmentId": 1, "paymentTerm": {"id": "PM"}, "dueDate": "2026-04-01", "issueDate": "2026-04-01",
   "originalAmount": 50000.00, "balanceAmount": 0, "correctedBalanceAmount": 0,
   "receiptsCategories": [{"financialCategoryId": "1.08.001"}], "receipts": [{"paymentDate": "2026-04-01", "amount": 50000.00}]}]');
select pg_temp.gravar_raw('outcome', '[
  {"billId": 7101, "dueDate": "2026-02-20", "issueDate": "2026-02-01", "originalAmount": 1000.00, "balanceAmount": 250.00,
   "buildingsCosts": [{"buildingId": 9001, "amount": 1000.00}],
   "paymentsCategories": [{"financialCategoryId": "2.01.001", "financialCategoryRate": 100}],
   "payments": [{"paymentDate": "2026-02-20", "amount": 500.00}, {"paymentDate": "2026-03-10", "amount": 250.00}]},
  {"billId": 7601, "dueDate": "2026-06-01", "issueDate": "2026-05-20", "originalAmount": 10000.00, "balanceAmount": 10000.00,
   "paymentsCategories": [{"financialCategoryId": "2.09.001", "financialCategoryRate": 100}], "payments": []},
  {"billId": 7801, "dueDate": "2026-03-20", "issueDate": "2026-02-01", "originalAmount": 1000.00, "balanceAmount": 899.95,
   "buildingsCosts": [{"buildingId": 9001, "amount": 500.00}, {"buildingId": 9002, "amount": 500.00}],
   "paymentsCategories": [{"financialCategoryId": "2.01.001", "financialCategoryRate": 70}, {"financialCategoryId": "2.03.001", "financialCategoryRate": 30}],
   "payments": [{"paymentDate": "2026-02-10", "amount": 100.05}]},
  {"billId": 7802, "dueDate": "2026-02-15", "issueDate": "2026-02-05", "originalAmount": 800.00, "balanceAmount": 0,
   "paymentsCategories": [{"financialCategoryId": "2.04.001", "financialCategoryRate": 100}],
   "payments": [{"paymentDate": "2026-02-15", "amount": 800.00}]},
  {"billId": 7803, "dueDate": "2026-03-05", "issueDate": "2026-02-10", "originalAmount": 50.00, "balanceAmount": 50.00,
   "buildingsCosts": [{"buildingId": 9999, "amount": 50.00}], "payments": []},
  {"billId": 7804, "dueDate": "2026-04-05", "issueDate": "2026-03-10", "originalAmount": 1200.00, "balanceAmount": 0,
   "buildingsCosts": [{"buildingId": 9002, "amount": 1200.00}],
   "paymentsCategories": [{"financialCategoryId": "2.05.001", "financialCategoryRate": 100}],
   "payments": [{"paymentDate": "2026-04-05", "amount": 1150.00}]},
  {"billId": 7805, "dueDate": "2026-07-05", "originalAmount": 400.00, "balanceAmount": 400.00,
   "buildingsCosts": [{"buildingId": 9001, "amount": 400.00}],
   "paymentsCategories": [{"financialCategoryId": "2.02.001", "financialCategoryRate": 100}], "payments": []}]');
select pg_temp.gravar_raw('building-cost-estimation-items', '[
  {"buildingId": 9001, "wbsCode": "01", "description": "Estrutura", "totalPrice": 1500.00},
  {"buildingId": 9001, "wbsCode": "02", "description": "Acabamento", "totalPrice": 800.00}]');
select staging.recarregar('7e000000-0000-4000-8000-00000000000a');
select pg_temp.mapa(c, g) from (values ('2.01.001', 'materiais'), ('2.02.001', 'tributos_receita'), ('2.03.001', 'corretagem'),
  ('2.04.001', 'despesas_administrativas'), ('2.05.001', 'despesas_financeiras'), ('2.09.001', 'devolucao_distrato')) as m(c, g);
select pg_temp.mapa(c, g, 'parcela_receber') from (values ('1.01.001', 'venda_imoveis'), ('1.09.001', 'receitas_financeiras'),
  ('1.08.001', 'aporte_socios')) as m(c, g);
select pg_temp.mapa('01', 'terreno', 'orcamento');
select set_config('app.data_referencia', '2026-06-15', true);

select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000d00a", "role": "authenticated"}', true);
set local role authenticated;

select results_eq(
  $$select linha_codigo, valor_mes from marts.dre_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a2' and linha_codigo in ('resultado_financeiro', 'fora_do_resultado')
      and competencia in ('2026-03-01', '2026-04-01') order by competencia, linha_ordem$$,
  $$values ('resultado_financeiro', 300.00::numeric(18,2)), ('fora_do_resultado', 0.00::numeric(18,2)),
           ('resultado_financeiro', 0.00::numeric(18,2)), ('fora_do_resultado', 50000.00::numeric(18,2))$$,
  'parcela de receita financeira entra pela emissão; aporte fica fora do resultado'
);
select results_eq(
  $$select tipo_origem, conta_origem, valor_envolvido from marts.pendencia_classificacao order by 1, 2 nulls last$$,
  $$values ('orcamento', '02', 800.00::numeric(18,2)),
           ('parcela_receber', null, 333000.00::numeric(18,2)),
           ('titulo_pagar', null, 50.00::numeric(18,2))$$,
  'pendências da base mista: orçamento sem mapa, parcelas sem conta e título sem conta'
);
select results_eq(
  $$select sum(participacao) filter (where tipo_origem = 'parcela_receber') from marts.pendencia_classificacao$$,
  $$values (0.861578::numeric)$$,
  'participação das parcelas sem conta sobre todas as parcelas visíveis'
);

-- R1, R3, R4: recebido por obra igual em recebimento, resumo, carteira, posição, fluxo e série mensal
select is_empty(
  $$with r as (select centro_custo_id, sum(valor) as v from staging.recebimento
               where tipo_baixa in ('recebimento', 'estorno') group by 1),
         f as (select centro_custo_id, sum(entrada_direta_realizada + repasse_realizado) as v from marts.fluxo_caixa_mensal group by 1),
         k as (select centro_custo_id, sum(valor_recebido) as v from marts.carteira_recebiveis group by 1),
         m as (select centro_custo_id, sum(recebido) as v from marts.recebimento_mensal group by 1)
    select p.centro_custo_id from marts.posicao_financeira_obra p
    join marts.resumo_receitas_obra s using (centro_custo_id)
    left join r using (centro_custo_id) left join f using (centro_custo_id)
    left join k using (centro_custo_id) left join m using (centro_custo_id)
    where coalesce(r.v, 0) <> s.recebido_direto + s.recebido_financiamento
       or s.recebido_direto + s.recebido_financiamento <> p.recebido_direto + p.recebido_repasse
       or coalesce(f.v, 0) <> p.recebido_direto + p.recebido_repasse
       or coalesce(k.v, 0) <> s.recebido_direto + s.recebido_financiamento
       or coalesce(m.v, 0) <> coalesce(r.v, 0)$$,
  'R1, R3, R4: recebido por obra igual em todas as fontes'
);
select is((select count(*) from marts.resumo_receitas_obra where tipo_centro = 'obra'), 2::bigint,
  'R1: as duas obras com receita entram na conferência');
-- R2
select is_empty(
  $$with k as (
      select centro_custo_id,
        coalesce(sum(saldo) filter (where situacao = 'a_vencer' and origem = 'direta'), 0) as av_d,
        coalesce(sum(saldo) filter (where situacao = 'a_vencer' and origem = 'financiamento'), 0) as av_f,
        coalesce(sum(saldo) filter (where situacao = 'vencida' and origem = 'direta'), 0) as ve_d,
        coalesce(sum(saldo) filter (where situacao = 'vencida' and origem = 'financiamento'), 0) as ve_f
      from marts.carteira_recebiveis group by 1)
    select p.centro_custo_id from marts.posicao_financeira_obra p
    join marts.resumo_receitas_obra s using (centro_custo_id) join k using (centro_custo_id)
    where k.av_d <> s.a_vencer_direto or s.a_vencer_direto <> p.a_receber_direto
       or k.av_f <> s.a_vencer_financiamento or s.a_vencer_financiamento <> p.a_receber_repasse
       or k.ve_d <> s.vencido_direto or s.vencido_direto <> p.vencido_direto
       or k.ve_f <> s.vencido_financiamento or s.vencido_financiamento <> p.repasse_atrasado$$,
  'R2: a vencer e vencido por obra e origem iguais na carteira, no resumo e na posição'
);
-- R6
select is_empty(
  $$select centro_custo_id from marts.custo_obra_resumo
    where custo_lancado <> desembolsado + em_aberto_vencido + em_aberto_a_vencer + ajuste_baixa$$,
  'R6: custo lançado = desembolsado + em aberto + ajuste em cada centro'
);
select is_empty(
  $$select r.centro_custo_id from marts.custo_obra_resumo r
    join (select centro_custo_id, sum(orcamento_vigente) as o, sum(custo_lancado) as l, sum(desembolsado) as d,
                 sum(em_aberto_vencido) as v, sum(em_aberto_a_vencer) as a, sum(ajuste_baixa) as j
          from marts.custo_obra_categoria group by 1) k using (centro_custo_id)
    where r.orcamento_vigente is distinct from k.o or r.custo_lancado <> k.l or r.desembolsado <> k.d
       or r.em_aberto_vencido <> k.v or r.em_aberto_a_vencer <> k.a or r.ajuste_baixa <> k.j$$,
  'R6: soma das categorias igual ao resumo em cada coluna'
);
select is(
  (select ajuste_baixa from marts.custo_obra_resumo where centro_custo_id = '7c000000-0000-4000-8000-0000000000a2'),
  50.00::numeric(18,2), 'R6: desconto de 50,00 no título 7804 aparece como ajuste de baixa'
);
-- R7 e R9
select is_empty(
  $$select r.centro_custo_id from marts.custo_obra_resumo r join marts.posicao_financeira_obra p using (centro_custo_id)
    where r.desembolsado <> p.pago or r.em_aberto_vencido + r.em_aberto_a_vencer <> p.a_pagar
       or r.custo_lancado <> p.custo_lancado
       or (r.orcamento_vigente is not null and r.remanescente_sem_titulo <> p.custo_a_incorrer)
       or (r.orcamento_vigente is not null and r.desvio <> p.estouro_orcamento)
       or (r.orcamento_vigente is not null and r.estimativa_conclusao <> r.custo_lancado + r.remanescente_sem_titulo)$$,
  'R7 e R9: custo por obra igual à posição; estimativa e desvio fecham'
);
select results_eq(
  $$select tipo_centro, count(*) from marts.custo_obra_resumo group by 1 order by 1$$,
  $$values ('empresa', 1::bigint), ('obra', 2::bigint)$$,
  'diretor vê o resumo de custo das duas obras e de Despesas sem obra'
);
-- R10
select is_empty(
  $$select c.competencia, c.linha_codigo from marts.dre_mensal_consolidado c
    join (select competencia, linha_codigo, sum(valor_mes) as v, sum(valor_acumulado) as a, count(*) as n
          from marts.dre_mensal group by 1, 2) d
      on d.competencia is not distinct from c.competencia and d.linha_codigo = c.linha_codigo
    where c.disponivel and (c.valor_mes <> d.v or c.valor_acumulado <> d.a or c.quantidade_centros <> d.n)$$,
  'R10: consolidado igual à soma dos centros em cada linha disponível'
);
select results_eq(
  $$select valor_mes, quantidade_centros from marts.dre_mensal_consolidado
    where competencia = '2026-02-01' and linha_codigo = 'despesas_administrativas'$$,
  $$values (-800.00::numeric(18,2), 3)$$,
  'despesa sem obra entra no consolidado do diretor'
);
select results_eq(
  $$select disponivel, motivo from marts.dre_mensal_consolidado where competencia = '2026-02-01' and linha_codigo = 'resultado_gerencial'$$,
  $$values (false, 'consolidado_parcial')$$,
  'consolidado com obra indisponível e empresa disponível é parcial'
);
-- R11
select is_empty(
  $$with dre as (
      select centro_custo_id, sum(valor_mes) as v from marts.dre_mensal
      where linha_ordem in (20, 60, 70, 80, 100, 110, 120, 130) group by 1),
    apropriado as (
      select centro_custo_id, -sum(valor_original) as v from staging.titulo_pagar_apropriacao
      where data_competencia is null or data_competencia < (date_trunc('month', app.data_referencia()) + interval '1 month')
      group by 1)
    select a.centro_custo_id from apropriado a left join dre d using (centro_custo_id)
    where a.centro_custo_id <> '7c000000-0000-4000-8000-0000000000a2' and a.v <> coalesce(d.v, 0)$$,
  'R11: cada título entra uma vez no DRE dos centros sem parcela classificada'
);
select is(
  (select sum(valor_mes) from marts.dre_mensal where centro_custo_id = '7c000000-0000-4000-8000-0000000000a2'
     and linha_ordem in (20, 60, 70, 80, 100, 110, 120, 130)),
  (select -sum(valor_original) from staging.titulo_pagar_apropriacao where centro_custo_id = '7c000000-0000-4000-8000-0000000000a2')
    + 1500.00 + 50000.00,
  'R11: em T2 a diferença é só a receita financeira e o aporte'
);
select is(
  (select valor_mes from marts.dre_mensal where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'
     and linha_codigo = 'sem_data_competencia'),
  -400.00::numeric(18,2), 'título sem emissão fica em sem data de competência'
);
-- R12
select is_empty(
  $$select p.linha_codigo from marts.dre_periodo('2026-02-01', '2026-04-30', '7c000000-0000-4000-8000-0000000000a2') p
    join (select linha_codigo, sum(valor_mes) as v, bool_and(disponivel) as disp from marts.dre_mensal
          where centro_custo_id = '7c000000-0000-4000-8000-0000000000a2'
            and (competencia between '2026-02-01' and '2026-04-01' or competencia is null)
          group by 1) d using (linha_codigo)
    where p.disponivel <> d.disp or (d.disp and p.valor_periodo <> d.v)$$,
  'R12: DRE do período igual à soma dos meses da obra'
);
select is_empty(
  $$select p.linha_codigo from marts.dre_periodo('2025-01-01', '2026-06-30') p
    join (select linha_codigo, sum(valor_mes) as v, bool_and(disponivel) as disp from marts.dre_mensal group by 1) d
      using (linha_codigo)
    where p.disponivel <> d.disp or (d.disp and p.valor_periodo <> d.v)$$,
  'R12: DRE do período consolidado igual à soma de todos os centros'
);
select is(
  (select count(*) from marts.dre_periodo('2026-01-01', '2026-06-30')), 13::bigint, 'DRE do período traz as treze linhas'
);
-- Funções de período e séries mensais
select is_empty(
  $$select p.origem from marts.recebimento_periodo('2026-02-01', '2026-05-31') p
    join (select origem, sum(recebido) as r, sum(previsto_contratual) as c from marts.recebimento_mensal
          where competencia between '2026-02-01' and '2026-05-01' group by 1) m using (origem)
    where p.recebido <> m.r or p.previsto_contratual <> m.c$$,
  'recebimento do período igual à soma da série mensal'
);
select is_empty(
  $$select p.categoria_codigo from marts.desembolso_periodo('2026-01-01', '2026-06-30') p
    full join (select categoria_codigo, sum(lancado_competencia) as l, sum(pago) as g from marts.despesa_mensal
               where competencia between '2026-01-01' and '2026-06-01' group by 1) m
      on coalesce(m.categoria_codigo, '') = coalesce(p.categoria_codigo, '')
    where p.lancado_competencia is distinct from m.l or p.pago is distinct from m.g$$,
  'desembolso do período igual à soma da série mensal'
);
select is(
  (select sum(pago) from marts.despesa_mensal),
  (select sum(valor) from staging.pagamento),
  'todo pagamento aparece uma vez na despesa mensal'
);
select is(
  (select sum(lancado_competencia) from marts.despesa_mensal),
  (select sum(valor_original) from staging.titulo_pagar_apropriacao where data_competencia is not null),
  'todo título com competência aparece uma vez no lançado'
);
-- Consolidados de receitas e custo
select is_empty(
  $$select 1 from marts.resumo_receitas_consolidado c
    join (select tenant_id, count(*) as n, sum(vgv_contratado_ativo) as vgv, sum(contratos_ativos) as ca,
                 sum(contratos_distratados) as cd, sum(recebido_direto) as rd, sum(recebido_financiamento) as rf,
                 sum(vencido_direto) as vd, sum(vencido_financiamento) as vf, sum(a_vencer_direto) as ad,
                 sum(a_vencer_financiamento) as af, sum(previsto_proximo_mes_direto) as pd,
                 sum(previsto_proximo_mes_financiamento) as pf, sum(saldo_distratado) as sd
          from marts.resumo_receitas_obra where tipo_centro = 'obra' group by 1) s using (tenant_id)
    where c.quantidade_obras <> s.n or c.vgv_contratado_ativo <> s.vgv or c.contratos_ativos <> s.ca
       or c.contratos_distratados <> s.cd or c.recebido_direto <> s.rd or c.recebido_financiamento <> s.rf
       or c.vencido_direto <> s.vd or c.vencido_financiamento <> s.vf or c.a_vencer_direto <> s.ad
       or c.a_vencer_financiamento <> s.af or c.previsto_proximo_mes_direto <> s.pd
       or c.previsto_proximo_mes_financiamento <> s.pf or c.saldo_distratado <> s.sd$$,
  'resumo de receitas consolidado igual à soma das obras'
);
select results_eq(
  $$select quantidade_obras, vgv_contratado_ativo, recebido_direto, recebido_financiamento from marts.resumo_receitas_consolidado$$,
  $$values (2, 402000.00::numeric(18,2), 77800.00::numeric(18,2), 200000.00::numeric(18,2))$$,
  'resumo consolidado com os números da base mista'
);
select is_empty(
  $$select 1 from marts.recebimento_mensal_consolidado c
    full join (select m.competencia, m.origem, sum(m.recebido) as r, sum(m.previsto_contratual) as p, sum(m.saldo_em_aberto) as s
               from marts.recebimento_mensal m join app.centro_custo cc on cc.id = m.centro_custo_id and cc.tipo = 'obra'
               group by 1, 2) s using (competencia, origem)
    where c.recebido is distinct from s.r or c.previsto_contratual is distinct from s.p or c.saldo_em_aberto is distinct from s.s$$,
  'recebimento mensal consolidado igual à soma das obras mês a mês'
);
select is_empty(
  $$select 1 from marts.custo_obra_resumo_consolidado c
    join (select case tipo_centro when 'obra' then 'obras' else 'despesas_sem_obra' end as grupo, count(*) as n,
                 sum(custo_lancado) as l, sum(desembolsado) as d, sum(em_aberto_vencido) as v, sum(em_aberto_a_vencer) as a,
                 sum(ajuste_baixa) as j
          from marts.custo_obra_resumo group by 1) s using (grupo)
    where c.quantidade_centros <> s.n or c.custo_lancado <> s.l or c.desembolsado <> s.d or c.em_aberto_vencido <> s.v
       or c.em_aberto_a_vencer <> s.a or c.ajuste_baixa <> s.j$$,
  'custo consolidado igual à soma dos centros de cada grupo'
);
select results_eq(
  $$select grupo, quantidade_centros, centros_sem_orcamento, orcamento_vigente, custo_lancado, remanescente_sem_titulo, motivo
    from marts.custo_obra_resumo_consolidado order by grupo$$,
  $$values ('despesas_sem_obra', 1, null::integer, null::numeric(18,2), 10850.00::numeric(18,2), null::numeric(18,2), null::text),
           ('obras', 2, 1, null, 3600.00, null, 'consolidado_parcial')$$,
  'custo consolidado: sem orçamento em todas as obras, orçamento do grupo fica nulo e parcial'
);
reset role;
insert into staging.item_orcamento (tenant_id, centro_custo_id, codigo, descricao, valor_total) values
  ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a2', '01', 'Obra', 5000.00);
select results_eq(
  $$select orcamento_vigente, remanescente_sem_titulo, estimativa_conclusao, desvio, motivo
    from marts.custo_obra_resumo_consolidado
    where tenant_id = '7e000000-0000-4000-8000-00000000000a' and grupo = 'obras'$$,
  $$values (7300.00::numeric(18,2), 3700.00::numeric(18,2), 7300.00::numeric(18,2), 0.00::numeric(18,2), null::text)$$,
  'custo consolidado soma o remanescente de cada obra quando todas têm orçamento'
);

select * from finish();
rollback;
