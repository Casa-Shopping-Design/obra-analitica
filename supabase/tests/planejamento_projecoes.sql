-- Casos C06 (fluxo projetado), C09, C18, C19, C21 e C23 de docs/financeiro/casos_teste.md, aporte, pendências
-- depois da entrega, causas de desvio e as reconciliações R14, R15, R16 e R17. Nível staging; cada caso limpa
-- o tenant A.
begin;
create extension if not exists pgtap with schema extensions;
select plan(86);

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
  ('7a000000-0000-4000-8000-00000000c00a', 'gerente.financeiro@teste.invalid'),
  ('7a000000-0000-4000-8000-00000000e00a', 'leitura.financeiro@teste.invalid'),
  ('7a000000-0000-4000-8000-00000000d00b', 'diretorb.financeiro@teste.invalid');

insert into app.usuario_tenant (user_id, tenant_id, perfil) values
  ('7a000000-0000-4000-8000-00000000d00a', '7e000000-0000-4000-8000-00000000000a', 'diretor'),
  ('7a000000-0000-4000-8000-00000000f00a', '7e000000-0000-4000-8000-00000000000a', 'financeiro'),
  ('7a000000-0000-4000-8000-00000000c00a', '7e000000-0000-4000-8000-00000000000a', 'gerente_obra'),
  ('7a000000-0000-4000-8000-00000000e00a', '7e000000-0000-4000-8000-00000000000a', 'leitura'),
  ('7a000000-0000-4000-8000-00000000d00b', '7e000000-0000-4000-8000-00000000000b', 'diretor');

insert into app.usuario_centro_custo (user_id, tenant_id, centro_custo_id) values
  ('7a000000-0000-4000-8000-00000000c00a', '7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1'),
  ('7a000000-0000-4000-8000-00000000e00a', '7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1');

-- Gravação no nível staging como o carregador, com as regras de casos_teste.md ("Como ler").
create function pg_temp.contrato(p_centro uuid, p_id integer, p_valor numeric, p_data_venda date,
                                 p_valor_financiado numeric default null, p_banco text default null,
                                 p_data_repasse date default null, p_unidade integer default null) returns void
language sql as $$
  insert into staging.contrato_venda (tenant_id, centro_custo_id, id_origem, numero, data_venda, valor, situacao,
    banco_repasse, data_repasse, unidade_id_origem, valor_financiado)
  select cc.tenant_id, cc.id, p_id, 'C-' || p_id, p_data_venda, p_valor, '1', p_banco, p_data_repasse, p_unidade,
         p_valor_financiado
  from app.centro_custo cc where cc.id = p_centro;
  insert into staging.contrato_unidade (tenant_id, centro_custo_id, contrato_id_origem, sequencia, unidade_id_origem, principal)
  select cc.tenant_id, cc.id, p_id, 1, p_unidade, true
  from app.centro_custo cc where cc.id = p_centro and p_unidade is not null;
$$;

create function pg_temp.parcela(p_centro uuid, p_contrato integer, p_parcela integer, p_condicao text,
                                p_vencimento date, p_valor numeric, p_saldo numeric,
                                p_recebimentos jsonb default '[]') returns void
language sql as $$
  insert into staging.parcela_receber (tenant_id, centro_custo_id, id_origem, contrato_id_origem, vencimento,
    valor_original, saldo, saldo_corrigido, tipo_condicao, valor_recebido, data_recebimento)
  select cc.tenant_id, cc.id, p_parcela, p_contrato, p_vencimento, p_valor, p_saldo, p_saldo, p_condicao,
         coalesce((select sum((r ->> 'valor')::numeric) from jsonb_array_elements(p_recebimentos) r), 0),
         (select max((r ->> 'data')::date) from jsonb_array_elements(p_recebimentos) r)
  from app.centro_custo cc where cc.id = p_centro;
  insert into staging.recebimento (tenant_id, centro_custo_id, contrato_id_origem, parcela_id_origem, sequencia,
    data_recebimento, valor, origem, tipo_condicao, tipo_baixa)
  select cc.tenant_id, cc.id, p_contrato, p_parcela, r.posicao::integer, (r.item ->> 'data')::date,
         (r.item ->> 'valor')::numeric, case when p_condicao = 'FI' then 'repasse' else 'direta' end, p_condicao,
         case when (r.item ->> 'valor')::numeric < 0 then 'estorno' else 'recebimento' end
  from app.centro_custo cc
  cross join jsonb_array_elements(p_recebimentos) with ordinality as r(item, posicao)
  where cc.id = p_centro;
$$;

create function pg_temp.titulo(p_centro uuid, p_titulo integer, p_vencimento date, p_competencia date,
                               p_valor numeric, p_pagamentos jsonb default '[]') returns void
language sql as $$
  insert into staging.titulo_pagar_apropriacao (tenant_id, centro_custo_id, titulo_id_origem, sequencia_obra,
    sequencia_conta, percentual, principal, valor_original, valor_pago, ajuste_baixa, saldo, vencimento,
    data_competencia, data_ultimo_pagamento)
  select cc.tenant_id, cc.id, p_titulo, 1, 1, 1, true, p_valor, pg.pago, 0, p_valor - pg.pago, p_vencimento,
         p_competencia, pg.ultimo
  from app.centro_custo cc
  cross join (select coalesce(sum((x ->> 'valor')::numeric), 0) as pago, max((x ->> 'data')::date) as ultimo
              from jsonb_array_elements(p_pagamentos) x) pg
  where cc.id = p_centro;
  insert into staging.pagamento (tenant_id, centro_custo_id, titulo_id_origem, sequencia_pagamento, sequencia_obra,
    sequencia_conta, data_pagamento, valor)
  select cc.tenant_id, cc.id, p_titulo, x.posicao::integer, 1, 1, (x.item ->> 'data')::date, (x.item ->> 'valor')::numeric
  from app.centro_custo cc
  cross join jsonb_array_elements(p_pagamentos) with ordinality as x(item, posicao)
  where cc.id = p_centro;
$$;

create function pg_temp.unidade(p_centro uuid, p_id integer, p_situacao text, p_data_entrega date default null,
                                p_valor_sugerido numeric default null) returns void
language sql as $$
  insert into staging.unidade (tenant_id, centro_custo_id, id_origem, nome, tipologia, situacao, data_entrega)
  select cc.tenant_id, cc.id, p_id, 'Unidade ' || p_id, 'apartamento', p_situacao, p_data_entrega
  from app.centro_custo cc where cc.id = p_centro;
  insert into staging.unidade_valor (tenant_id, centro_custo_id, unidade_id_origem, valor_sugerido)
  select cc.tenant_id, cc.id, p_id, p_valor_sugerido
  from app.centro_custo cc where cc.id = p_centro and p_valor_sugerido is not null;
$$;

-- Limpa o tenant A entre os casos. Versão registrada não se apaga pelas vias normais; o modo réplica
-- desliga os gatilhos só aqui, como o dono faria numa limpeza de teste.
create function pg_temp.limpar() returns void
language plpgsql as $$
declare
  t text;
begin
  perform set_config('session_replication_role', 'replica', true);
  foreach t in array array['app.projecao_mensal', 'app.meta_mensal', 'app.versao_planejamento',
    'app.premissa_distribuicao_custo_mes', 'app.premissa_distribuicao_custo', 'app.liberacao_financiamento',
    'app.medicao_bancaria', 'app.operacao_credito_obra', 'app.etapa_financiamento_contrato',
    'app.auditoria_alteracao', 'staging.recebimento', 'staging.parcela_receber', 'staging.contrato_unidade',
    'staging.contrato_venda', 'staging.pagamento', 'staging.titulo_pagar_apropriacao', 'staging.item_orcamento',
    'staging.unidade_valor', 'staging.unidade'] loop
    execute format('delete from %s where tenant_id = %L', t, '7e000000-0000-4000-8000-00000000000a');
  end loop;
  perform set_config('session_replication_role', 'origin', true);
end $$;

-- C09 custo futuro sem duplicar os títulos existentes
select set_config('app.data_referencia', '2026-09-15', true);
insert into staging.item_orcamento (tenant_id, centro_custo_id, codigo, descricao, valor_total) values
  ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1', '01', 'Estrutura', 600000.00),
  ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1', '02', 'Acabamento', 400000.00);
select pg_temp.titulo('7c000000-0000-4000-8000-0000000000a1', 7901, '2026-08-10', '2026-08-01', 300000.00,
  '[{"data": "2026-08-10", "valor": 300000.00}]');
select pg_temp.titulo('7c000000-0000-4000-8000-0000000000a1', 7902, '2026-10-05', '2026-09-01', 150000.00);
select pg_temp.titulo('7c000000-0000-4000-8000-0000000000a1', 7903, '2026-09-01', '2026-08-15', 50000.00);

select results_eq(
  $$select competencia, total_saidas, caixa_gerado_acumulado from marts.fluxo_projetado_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' order by 1$$,
  $$values ('2026-08-01'::date, 300000.00::numeric(18,2), -300000.00::numeric(18,2)),
           ('2026-09-01'::date, 50000.00, -350000.00),
           ('2026-10-01'::date, 150000.00, -500000.00)$$,
  'C09 sem premissa: o custo sem título não entra nos meses'
);
select results_eq(
  $$select exposicao_maxima_projetada, mes_exposicao_maxima, custo_sem_titulo_total, custo_sem_titulo_nao_distribuido,
           exposicao_parcial, motivo_distribuicao, premissa_distribuicao_id
    from marts.resumo_projecao_obra where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'$$,
  $$values (500000.00::numeric(18,2), '2026-10-01'::date, 500000.00::numeric(18,2), 500000.00::numeric(18,2), true,
            'sem_premissa_distribuicao', null::uuid)$$,
  'C09 sem premissa: total separado e exposição parcial'
);

select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000f00a", "role": "authenticated"}', true);
set local role authenticated;
select throws_ok(
  $$select app.registrar_premissa_distribuicao('7c000000-0000-4000-8000-0000000000a1', 'Cronograma', null,
      '[{"competencia": "2026-10-01", "fracao": 0.5}, {"competencia": "2026-11-01", "fracao": 0.4}]')$$,
  '22023', 'premissa inválida: fracao', 'C09: premissa que não soma 1 é recusada pela função'
);
select throws_ok(
  $$select app.registrar_premissa_distribuicao('7c000000-0000-4000-8000-0000000000a1', 'Cronograma', null,
      '[{"competencia": "2026-10-15", "fracao": 1}]')$$,
  '22023', 'premissa inválida: competencia', 'C09: mês fora do primeiro dia é recusado'
);
select lives_ok(
  $$insert into app.premissa_distribuicao_custo (id, tenant_id, centro_custo_id, fonte)
    values ('70000000-0000-4000-8000-0000000009a1', '7e000000-0000-4000-8000-00000000000a',
            '7c000000-0000-4000-8000-0000000000a1', 'Gravada direto na tabela')$$,
  'C09: cabeçalho de premissa gravado direto na tabela'
);
select lives_ok(
  $$insert into app.premissa_distribuicao_custo_mes (premissa_id, tenant_id, centro_custo_id, competencia, fracao)
    values ('70000000-0000-4000-8000-0000000009a1', '7e000000-0000-4000-8000-00000000000a',
            '7c000000-0000-4000-8000-0000000000a1', '2026-10-01', 0.8)$$,
  'C09: mês da premissa com fração 0,8, sem completar 1'
);
reset role;
select results_eq(
  $$select motivo_distribuicao, custo_sem_titulo_distribuido_total, exposicao_parcial from marts.resumo_projecao_obra
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'$$,
  $$values ('premissa_invalida', 0.00::numeric(18,2), true)$$,
  'C09: premissa vigente inválida não distribui nada'
);

select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000f00a", "role": "authenticated"}', true);
set local role authenticated;
select isnt(
  app.registrar_premissa_distribuicao('7c000000-0000-4000-8000-0000000000a1', 'Cronograma de teste', null,
    '[{"competencia": "2026-10-01", "fracao": 0.5}, {"competencia": "2026-11-01", "fracao": 0.5}]'),
  null, 'C09: financeiro registra a premissa de meses'
);
reset role;
select results_eq(
  $$select competencia, pago, a_pagar_vencido, a_pagar, custo_sem_titulo_distribuido, total_saidas,
           caixa_gerado_acumulado, necessidade_aporte_acumulada, aporte_incremental_mes
    from marts.fluxo_projetado_mensal where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' order by 1$$,
  $$values
    ('2026-08-01'::date, 300000.00::numeric(18,2), 0.00::numeric(18,2), 0.00::numeric(18,2), 0.00::numeric(18,2),
     300000.00::numeric(18,2), -300000.00::numeric(18,2), 300000.00::numeric(18,2), 300000.00::numeric(18,2)),
    ('2026-09-01'::date, 0.00, 50000.00, 0.00, 0.00, 50000.00, -350000.00, 350000.00, 50000.00),
    ('2026-10-01'::date, 0.00, 0.00, 150000.00, 250000.00, 400000.00, -750000.00, 750000.00, 400000.00),
    ('2026-11-01'::date, 0.00, 0.00, 0.00, 250000.00, 250000.00, -1000000.00, 1000000.00, 250000.00)$$,
  'C09: fluxo com a premissa, sem somar orçamento aos títulos'
);
select results_eq(
  $$select exposicao_maxima_projetada, mes_exposicao_maxima, custo_sem_titulo_total, custo_sem_titulo_distribuido_total,
           custo_sem_titulo_nao_distribuido, exposicao_parcial, motivo_distribuicao
    from marts.resumo_projecao_obra where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'$$,
  $$values (1000000.00::numeric(18,2), '2026-11-01'::date, 500000.00::numeric(18,2), 500000.00::numeric(18,2),
            0.00::numeric(18,2), false, null::text)$$,
  'C09: resumo com a exposição completa'
);
select is(
  (select sum(total_saidas) from marts.fluxo_projetado_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' and competencia >= '2026-09-01'),
  700000.00::numeric, 'C09: saídas futuras = em aberto 200000 + orçamento sem título 500000'
);
select is(
  (select custo_sem_titulo_total from marts.resumo_projecao_obra where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'),
  (select custo_a_incorrer from marts.posicao_financeira_obra where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'),
  'R15: custo sem título igual ao custo a incorrer da posição'
);
select ok(
  (select custo_sem_titulo_distribuido_total + custo_sem_titulo_nao_distribuido = custo_sem_titulo_total
   from marts.resumo_projecao_obra where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'),
  'R15: distribuído mais não distribuído igual ao total'
);
select results_eq(
  $$select sum(f.pago), sum(f.a_pagar) + sum(f.a_pagar_vencido) from marts.fluxo_projetado_mensal f
    where f.centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'$$,
  $$select pago, a_pagar from marts.posicao_financeira_obra where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'$$,
  'R14: pago e a pagar do fluxo iguais aos da posição'
);
select results_eq(
  $$select s.competencia, s.caixa_gerado_acumulado from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000a1', '{}') s$$,
  $$select f.competencia, f.caixa_gerado_acumulado from marts.fluxo_projetado_mensal f
    where f.centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' order by 1$$,
  'R16: simulação vazia igual ao fluxo projetado, com custo sem título'
);

-- Premissa nova com mês já passado: agosto soma no mês corrente (P11)
select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000f00a", "role": "authenticated"}', true);
set local role authenticated;
select isnt(
  app.registrar_premissa_distribuicao('7c000000-0000-4000-8000-0000000000a1', 'Cronograma revisado', 'agosto não aconteceu',
    '[{"competencia": "2026-08-01", "fracao": 0.2}, {"competencia": "2026-10-01", "fracao": 0.4},
      {"competencia": "2026-11-01", "fracao": 0.4}]'),
  null, 'C09: premissa revisada registrada'
);
reset role;
select results_eq(
  $$select competencia, custo_sem_titulo_distribuido from marts.fluxo_projetado_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' and custo_sem_titulo_distribuido <> 0 order by 1$$,
  $$values ('2026-09-01'::date, 100000.00::numeric(18,2)), ('2026-10-01'::date, 200000.00), ('2026-11-01'::date, 200000.00)$$,
  'C09: a premissa mais recente vale e o mês passado vai para setembro'
);
select is((select count(*) from app.premissa_distribuicao_custo where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'),
  3::bigint, 'C09: premissas anteriores continuam gravadas');
select results_eq(
  $$select competencia, custo_sem_titulo from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000a1',
      '{"deslocamento_cronograma_meses": 1, "fator_cronograma": 1.1}') where custo_sem_titulo <> 0$$,
  $$values ('2026-10-01'::date, 110000.00::numeric(18,2)), ('2026-11-01'::date, 220000.00), ('2026-12-01'::date, 220000.00)$$,
  'Simulação: cronograma do custo sem título deslocado um mês e 10% maior'
);
select results_eq(
  $$select competencia, a_pagar, custo_campanha from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000a1',
      '{"deslocamento_cronograma_meses": 1, "custo_campanha": [{"competencia": "2026-11-01", "valor": 30000.00}]}')
    where competencia >= '2026-10-01'$$,
  $$values ('2026-10-01'::date, 150000.00::numeric(18,2), 0.00::numeric(18,2)),
           ('2026-11-01'::date, 0.00, 30000.00), ('2026-12-01'::date, 0.00, 0.00)$$,
  'Simulação: títulos lançados não se deslocam; campanha entra no mês pedido'
);

-- Variante com estouro
select pg_temp.titulo('7c000000-0000-4000-8000-0000000000a1', 7904, '2026-10-20', '2026-09-10', 600000.00);
select results_eq(
  $$select custo_sem_titulo_total, custo_sem_titulo_distribuido_total, custo_sem_titulo_nao_distribuido, exposicao_parcial
    from marts.resumo_projecao_obra where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'$$,
  $$values (0.00::numeric(18,2), 0.00::numeric(18,2), 0.00::numeric(18,2), false)$$,
  'C09 com estouro: nada a distribuir'
);
select results_eq(
  $$select estouro_orcamento, custo_a_incorrer from marts.posicao_financeira_obra
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'$$,
  $$values (100000.00, 0.00)$$,
  'C09 com estouro: posição com o estouro'
);

-- C06 próximo mês na virada de dezembro para janeiro
select pg_temp.limpar();
select set_config('app.data_referencia', '2026-12-15', true);
select pg_temp.contrato('7c000000-0000-4000-8000-0000000000a1', 5501, 5000.00, '2026-06-01');
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 5501, n, 'PM', v, s, s)
from (values (1, '2026-12-10'::date, 800.00), (2, '2026-12-20', 1000.00), (3, '2027-01-10', 1500.00),
             (4, '2027-01-31', 500.00), (5, '2027-02-01', 700.00)) x(n, v, s);
select is(app.data_referencia(), '2026-12-15'::date, 'C06: data de referência fixada');
select results_eq(
  $$select competencia, previsto_direto, vencido_a_receber, eh_passado from marts.fluxo_projetado_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' order by 1$$,
  $$values ('2026-12-01'::date, 1000.00::numeric(18,2), 800.00::numeric(18,2), false),
           ('2027-01-01'::date, 2000.00, 0.00, false), ('2027-02-01'::date, 700.00, 0.00, false)$$,
  'C06: próximo mês é janeiro de 2027, sem a parcela vencida de dezembro'
);
select set_config('app.data_referencia', '2026-12-21', true);
select results_eq(
  $$select previsto_direto, vencido_a_receber from marts.fluxo_projetado_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' and competencia = '2026-12-01'$$,
  $$values (0.00::numeric(18,2), 1800.00::numeric(18,2))$$,
  'C06: em 21/12 a parcela de 20/12 já venceu e sai do previsto'
);

-- Aporte: pico e incremento só quando a necessidade cresce
select pg_temp.limpar();
select set_config('app.data_referencia', '2026-09-15', true);
select pg_temp.contrato('7c000000-0000-4000-8000-0000000000a1', 5601, 2300.00, '2026-06-01');
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 5601, 1, 'AT', '2026-08-05', 300.00, 0,
  '[{"data": "2026-08-05", "valor": 300.00}]');
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 5601, 2, 'PM', '2026-11-10', 2000.00, 2000.00);
select pg_temp.titulo('7c000000-0000-4000-8000-0000000000a1', 5701, '2026-07-10', '2026-07-01', 1000.00,
  '[{"data": "2026-07-10", "valor": 1000.00}]');
select pg_temp.titulo('7c000000-0000-4000-8000-0000000000a1', 5702, '2026-10-10', '2026-09-01', 500.00);
select results_eq(
  $$select competencia, saldo_mes, caixa_gerado_acumulado, necessidade_aporte_acumulada, aporte_incremental_mes
    from marts.fluxo_projetado_mensal where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' order by 1$$,
  $$values ('2026-07-01'::date, -1000.00::numeric(18,2), -1000.00::numeric(18,2), 1000.00::numeric(18,2), 1000.00::numeric(18,2)),
           ('2026-08-01'::date, 300.00, -700.00, 700.00, 0.00),
           ('2026-09-01'::date, 0.00, -700.00, 700.00, 0.00),
           ('2026-10-01'::date, -500.00, -1200.00, 1200.00, 500.00),
           ('2026-11-01'::date, 2000.00, 800.00, 0.00, 0.00)$$,
  'Aporte: necessidade = greatest(-caixa acumulado, 0) e incremento só quando cresce'
);
select results_eq(
  $$select exposicao_maxima_projetada, mes_exposicao_maxima, exposicao_parcial, motivo_distribuicao, custo_sem_titulo_total
    from marts.resumo_projecao_obra where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'$$,
  $$values (1200.00::numeric(18,2), '2026-10-01'::date, true, 'orcamento_ausente', null::numeric(18,2))$$,
  'Aporte: pico em outubro, parcial porque a obra não tem orçamento'
);
select hasnt_column('marts', 'fluxo_projetado_mensal', 'saldo_bancario', 'fluxo não chama o acumulado de saldo bancário');

-- C18 nova venda simulada entra pelo cronograma
select pg_temp.limpar();
select set_config('app.data_referencia', '2026-09-15', true);
select pg_temp.unidade('7c000000-0000-4000-8000-0000000000a2', u, 'D', null, v)
from (values (92101, 200000.00), (92102, 220000.00), (92103, 240000.00), (92104, 260000.00)) x(u, v);
create temporary table contagem_antes as
select (select count(*) from app.projecao_mensal) + (select count(*) from app.versao_planejamento)
     + (select count(*) from staging.contrato_venda) + (select count(*) from staging.parcela_receber)
     + (select count(*) from staging.unidade) as linhas;

select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000d00a", "role": "authenticated"}', true);
set local role authenticated;
select results_eq(
  $$select competencia, novas_vendas_unidades, novas_vendas_valor, entradas_novas_vendas_direta,
           entradas_novas_vendas_financiamento, caixa_gerado_acumulado, aviso
    from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000a2',
      '{"novas_vendas": [{"competencia": "2026-10-01", "quantidade": 2}], "desconto_tabela": 0.05,
        "composicao": {"entrada": 0.10, "parcelas_mensais": 0.30, "quantidade_parcelas_mensais": 3, "financiamento": 0.60},
        "meses_ate_liberacao_financiamento": 4}')$$,
  $$values ('2026-09-01'::date, 0, 0.00::numeric(18,2), 0.00::numeric(18,2), 0.00::numeric(18,2), 0.00::numeric(18,2), null::text),
           ('2026-10-01'::date, 2, 437000.00, 43700.00, 0.00, 43700.00, null),
           ('2026-11-01'::date, 0, 0.00, 43700.00, 0.00, 87400.00, null),
           ('2026-12-01'::date, 0, 0.00, 43700.00, 0.00, 131100.00, null),
           ('2027-01-01'::date, 0, 0.00, 43700.00, 0.00, 174800.00, null),
           ('2027-02-01'::date, 0, 0.00, 0.00, 262200.00, 437000.00, null)$$,
  'C18: entrada no mês da venda, três parcelas e financiamento quatro meses depois'
);
select results_eq(
  $$select distinct premissas -> 'atraso_liberacao_bancaria_meses', premissas -> 'deslocamento_cronograma_meses',
           premissas -> 'fator_cronograma', premissas -> 'cancelar_contratos', premissas -> 'custo_campanha',
           premissas -> 'novas_vendas'
    from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000a2',
      '{"novas_vendas": [{"competencia": "2026-10-01", "quantidade": 2}], "desconto_tabela": 0.05,
        "composicao": {"entrada": 0.10, "parcelas_mensais": 0.30, "quantidade_parcelas_mensais": 3, "financiamento": 0.60},
        "meses_ate_liberacao_financiamento": 4}')$$,
  $$values ('0'::jsonb, '0'::jsonb, '1'::jsonb, '[]'::jsonb, '[]'::jsonb,
            '[{"competencia": "2026-10-01", "quantidade": 2}]'::jsonb)$$,
  'C18: premissas voltam com os padrões preenchidos'
);
select is(
  (select sum(novas_vendas_valor) - sum(entradas_novas_vendas_direta + entradas_novas_vendas_financiamento)
   from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000a2',
     '{"novas_vendas": [{"competencia": "2026-10-01", "quantidade": 1}, {"competencia": "2026-12-01", "quantidade": 2}],
       "desconto_tabela": 0.033,
       "composicao": {"entrada": 0.07, "parcelas_mensais": 0.33, "quantidade_parcelas_mensais": 7, "financiamento": 0.60},
       "meses_ate_liberacao_financiamento": 5}')),
  0.00::numeric, 'R17: valor vendido igual à soma das entradas quando o horizonte cobre tudo'
);
select results_eq(
  $$select competencia, novas_vendas_unidades, novas_vendas_valor, entradas_novas_vendas_direta, aviso
    from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000a2',
      '{"novas_vendas": [{"competencia": "2026-10-01", "quantidade": 6}], "desconto_tabela": 0.05,
        "composicao": {"entrada": 0.10, "parcelas_mensais": 0.30, "quantidade_parcelas_mensais": 3, "financiamento": 0.60},
        "meses_ate_liberacao_financiamento": 4}') where competencia in ('2026-10-01', '2026-11-01')$$,
  $$values ('2026-10-01'::date, 4, 874000.00::numeric(18,2), 87400.00::numeric(18,2), 'vendas_limitadas_ao_estoque'),
           ('2026-11-01'::date, 0, 0.00, 87400.00, null)$$,
  'C18: pedido de 6 limitado às 4 unidades em estoque, com aviso'
);
select results_eq(
  $$select competencia, entradas_novas_vendas_financiamento from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000a2',
      '{"novas_vendas": [{"competencia": "2026-10-01", "quantidade": 6}], "desconto_tabela": 0.05,
        "composicao": {"entrada": 0.10, "parcelas_mensais": 0.30, "quantidade_parcelas_mensais": 3, "financiamento": 0.60},
        "meses_ate_liberacao_financiamento": 4}') where entradas_novas_vendas_financiamento <> 0$$,
  $$values ('2027-02-01'::date, 524400.00::numeric(18,2))$$,
  'C18: financiamento das 4 unidades em fevereiro de 2027'
);
select is(
  (select sum(novas_vendas_unidades) from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000a2',
     '{"novas_vendas": [{"competencia": "2026-10-01", "quantidade": 3}, {"competencia": "2026-11-01", "quantidade": 3}],
       "composicao": {"entrada": 1}}')),
  4::bigint, 'C18: estoque consumido na ordem dos meses, nunca acima de 4'
);
select results_eq(
  $$select competencia, entradas_novas_vendas_direta from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000a2',
      '{"novas_vendas": [{"competencia": "2026-10-01", "quantidade": 2}], "desconto_tabela": 0.05,
        "composicao": {"entrada": 0.10, "parcelas_mensais": 0.30, "quantidade_parcelas_mensais": 7, "financiamento": 0.60},
        "meses_ate_liberacao_financiamento": 4}') where competencia >= '2026-11-01' and entradas_novas_vendas_direta <> 0$$,
  $$values ('2026-11-01'::date, 18728.57::numeric(18,2)), ('2026-12-01'::date, 18728.57), ('2027-01-01'::date, 18728.57),
           ('2027-02-01'::date, 18728.57), ('2027-03-01'::date, 18728.57), ('2027-04-01'::date, 18728.57),
           ('2027-05-01'::date, 18728.58)$$,
  'C18: sete parcelas com o centavo na última'
);
select results_eq(
  $$select competencia, entradas_novas_vendas_financiamento from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000a2',
      '{"novas_vendas": [{"competencia": "2026-10-01", "quantidade": 2}], "desconto_tabela": 0.05,
        "composicao": {"entrada": 0.10, "parcelas_mensais": 0.30, "quantidade_parcelas_mensais": 3, "financiamento": 0.60},
        "meses_ate_liberacao_financiamento": 4, "atraso_liberacao_bancaria_meses": 2}')
    where entradas_novas_vendas_financiamento <> 0$$,
  $$values ('2027-04-01'::date, 262200.00::numeric(18,2))$$,
  'C18: atraso de dois meses na liberação leva o financiamento para abril'
);
select throws_ok(
  $$select * from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000a2',
      '{"novas_vendas": [{"competencia": "2026-10-01", "quantidade": 2}],
        "composicao": {"entrada": 0.09, "parcelas_mensais": 0.30, "quantidade_parcelas_mensais": 3, "financiamento": 0.60},
        "meses_ate_liberacao_financiamento": 4}')$$,
  '22023', 'premissa inválida: composicao', 'C18: composição que soma 0,99 é recusada'
);
select throws_ok(
  $$select * from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000a2',
      '{"novas_vendas": [{"competencia": "2026-08-01", "quantidade": 2}], "composicao": {"entrada": 1}}')$$,
  '22023', 'premissa inválida: novas_vendas.competencia', 'C18: venda em mês passado é recusada'
);
select throws_ok(
  $$select * from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000a2', '{"novas_vendas": [{"competencia": "2026-10-01", "quantidade": 2}]}')$$,
  '22023', 'premissa inválida: composicao', 'Venda sem composição é recusada'
);
select throws_ok(
  $$select * from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000a2',
      '{"novas_vendas": [{"competencia": "2026-10-01", "quantidade": 1}], "composicao": {"entrada": 0.4, "financiamento": 0.6}}')$$,
  '22023', 'premissa inválida: meses_ate_liberacao_financiamento', 'Financiamento sem prazo de liberação é recusado'
);
select throws_ok(
  $$select * from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000a2', '{"desconto_tabela": 1}')$$,
  '22023', 'premissa inválida: desconto_tabela', 'Desconto de 100% é recusado'
);
select throws_ok(
  $$select * from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000a2', '{"vendas": []}')$$,
  '22023', 'premissa inválida: vendas', 'Chave desconhecida é recusada com o nome dela'
);
select throws_ok(
  $$select * from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000a2',
      '{"novas_vendas": [{"competencia": "2026-10-01", "quantidade": 1.5}], "composicao": {"entrada": 1}}')$$,
  '22023', 'premissa inválida: novas_vendas.quantidade', 'Quantidade fracionária é recusada'
);
select throws_ok(
  $$select * from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000a2', '{"fator_cronograma": 0}')$$,
  '22023', 'premissa inválida: fator_cronograma', 'Fator zero é recusado'
);
select throws_ok(
  $$select * from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000a2',
      jsonb_build_object('novas_vendas', (select jsonb_agg(jsonb_build_object('competencia', '2026-10-01', 'quantidade', 0))
                                          from generate_series(1, 121)), 'composicao', '{"entrada": 1}'::jsonb))$$,
  '22023', 'premissa inválida: novas_vendas tem mais de 120 itens', 'M9: novas_vendas com 121 itens é recusada'
);
select throws_ok(
  $$select * from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000a2',
      jsonb_build_object('custo_campanha', (select jsonb_agg(jsonb_build_object('competencia', '2026-10-01', 'valor', 1))
                                            from generate_series(1, 121))))$$,
  '22023', 'premissa inválida: custo_campanha tem mais de 120 itens', 'M9: custo_campanha com 121 itens é recusado'
);
select lives_ok(
  $$select * from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000a2',
      jsonb_build_object('custo_campanha', (select jsonb_agg(jsonb_build_object('competencia', '2026-10-01', 'valor', 1))
                                            from generate_series(1, 120))))$$,
  'M9: 120 itens ainda são aceitos'
);
select results_eq(
  $$select competencia, caixa_gerado_acumulado from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000a2', '{}')$$,
  $$select competencia, caixa_gerado_acumulado from marts.fluxo_projetado_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a2' order by 1$$,
  'C18: premissas vazias devolvem o fluxo projetado (R16)'
);
reset role;
select is(
  (select (select count(*) from app.projecao_mensal) + (select count(*) from app.versao_planejamento)
        + (select count(*) from staging.contrato_venda) + (select count(*) from staging.parcela_receber)
        + (select count(*) from staging.unidade)),
  (select linhas from contagem_antes), 'C18: a simulação não gravou nada'
);
select is(
  (select provolatile::text from pg_proc where oid = 'marts.simular_fluxo(uuid, jsonb)'::regprocedure), 's',
  'simular_fluxo é stable e não consegue escrever'
);
select ok(
  (select not prosecdef and proconfig @> array['search_path=""'] from pg_proc
   where oid = 'marts.simular_fluxo(uuid, jsonb)'::regprocedure),
  'simular_fluxo é security invoker com search_path vazio'
);

-- C19 cancelamento muda a projeção sem apagar o recebido
select pg_temp.limpar();
select set_config('app.data_referencia', '2026-09-15', true);
select pg_temp.contrato('7c000000-0000-4000-8000-0000000000a1', 6901, 100000.00, '2026-03-01');
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 6901, 1, 'AT', '2026-03-01', 20000.00, 0,
  '[{"data": "2026-03-01", "valor": 20000.00}]');
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 6901, 2, 'PM', '2026-10-10', 10000.00, 10000.00);
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 6901, 3, 'FI', '2027-03-10', 70000.00, 70000.00);
select results_eq(
  $$select competencia, recebido_direto, previsto_direto, previsto_financiamento_pendente from marts.fluxo_projetado_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'
      and competencia in ('2026-03-01', '2026-10-01', '2027-03-01') order by 1$$,
  $$values ('2026-03-01'::date, 20000.00::numeric(18,2), 0.00::numeric(18,2), 0.00::numeric(18,2)),
           ('2026-10-01'::date, 0.00, 10000.00, 0.00), ('2027-03-01'::date, 0.00, 0.00, 70000.00)$$,
  'C19: recebido em março, direta em outubro, financiamento pendente em março de 2027'
);
select results_eq(
  $$select sum(carteira_prevista), (array_agg(caixa_gerado_acumulado order by competencia desc))[1],
           sum(recebido) filter (where competencia = '2026-03-01')
    from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000a1', '{"cancelar_contratos": [6901]}')$$,
  $$values (0.00::numeric, 20000.00::numeric(18,2), 20000.00::numeric)$$,
  'C19: simular o cancelamento zera a carteira e mantém o recebido'
);
select results_eq(
  $$select s.competencia, s.caixa_gerado_acumulado from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000a1', '{}') s$$,
  $$select f.competencia, f.caixa_gerado_acumulado from marts.fluxo_projetado_mensal f
    where f.centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' order by 1$$,
  'C19: R16 com recebido, direta e financiamento'
);
select results_eq(
  $$select sum(carteira_prevista) filter (where competencia = '2027-05-01'), sum(carteira_prevista) filter (where competencia = '2027-03-01')
    from marts.simular_fluxo('7c000000-0000-4000-8000-0000000000a1', '{"atraso_liberacao_bancaria_meses": 2}')$$,
  $$values (70000.00::numeric, 0.00::numeric)$$,
  'Simulação: atraso bancário desloca o financiamento do comprador'
);
update staging.contrato_venda set situacao = '3', data_distrato = '2026-09-10' where id_origem = 6901;
select results_eq(
  $$select sum(recebido_direto) filter (where competencia = '2026-03-01'),
           sum(previsto_direto + previsto_financiamento_elegivel + previsto_financiamento_pendente)
    from marts.fluxo_projetado_mensal where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'$$,
  $$values (20000.00::numeric, 0.00::numeric)$$,
  'C19: depois do distrato o recebido fica e a carteira some'
);
select is((select count(*) from marts.recebivel_projetado where tenant_id = '7e000000-0000-4000-8000-00000000000a' and contrato_id_origem = 6901), 0::bigint,
  'C19: contrato distratado sem recebível projetado');
select is((select count(*) from marts.financiamento_contrato where tenant_id = '7e000000-0000-4000-8000-00000000000a' and contrato_id_origem = 6901), 0::bigint,
  'C19: contrato distratado sai do financiamento');

-- C21 versão anterior da projeção fica preservada
select pg_temp.limpar();
select set_config('app.data_referencia', '2026-09-15', true);
select pg_temp.titulo('7c000000-0000-4000-8000-0000000000a1', 8101, '2026-10-10', '2026-09-01', 1000.00);
select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000f00a", "role": "authenticated"}', true);
set local role authenticated;
select isnt(app.registrar_versao_projecao('7c000000-0000-4000-8000-0000000000a1', 'Projeção de setembro'), null,
  'C21: v1 registrada');
reset role;
select pg_temp.titulo('7c000000-0000-4000-8000-0000000000a1', 8102, '2026-10-20', '2026-09-01', 500.00);
select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000f00a", "role": "authenticated"}', true);
set local role authenticated;
select isnt(app.registrar_versao_projecao('7c000000-0000-4000-8000-0000000000a1', 'Projeção revisada'), null,
  'C21: v2 registrada');
select throws_ok(
  $$select app.registrar_versao_projecao('7c000000-0000-4000-8000-0000000000a1', '  ')$$,
  '22023', 'premissa inválida: descricao', 'C21: versão sem descrição é recusada'
);
reset role;
select results_eq(
  $$select numero, tipo, data_referencia, autor, premissas ->> 'motivo_distribuicao' from app.versao_planejamento
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' order by numero$$,
  $$values (1, 'projecao', '2026-09-15'::date, '7a000000-0000-4000-8000-00000000f00a'::uuid, 'orcamento_ausente'),
           (2, 'projecao', '2026-09-15'::date, '7a000000-0000-4000-8000-00000000f00a'::uuid, 'orcamento_ausente')$$,
  'C21: duas versões numeradas, com a data de referência, o autor e as premissas'
);
select results_eq(
  $$select p.competencia, p.a_pagar, p.caixa_gerado_acumulado from app.projecao_mensal p
    join app.versao_planejamento v on v.id = p.versao_id where v.centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' and v.numero = 1 order by 1$$,
  $$values ('2026-09-01'::date, 0.00::numeric(18,2), 0.00::numeric(18,2)), ('2026-10-01'::date, 1000.00, -1000.00)$$,
  'C21: v1 guarda o fluxo da época'
);
select results_eq(
  $$select p.a_pagar, p.caixa_gerado_acumulado from app.projecao_mensal p
    join app.versao_planejamento v on v.id = p.versao_id where v.centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' and v.numero = 2 and p.competencia = '2026-10-01'$$,
  $$values (1500.00::numeric(18,2), -1500.00::numeric(18,2))$$,
  'C21: v2 com o título novo'
);
select results_eq(
  $$select versao_original_numero, original_total_saidas, atual_total_saidas, original_caixa_gerado_acumulado,
           atual_caixa_gerado_acumulado, diferenca_caixa_acumulado, realizado_saidas
    from marts.comparativo_projecao where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'
      and competencia = '2026-10-01'$$,
  $$values (1, 1000.00::numeric(18,2), 1500.00::numeric(18,2), -1000.00::numeric(18,2), -1500.00::numeric(18,2),
            -500.00::numeric(18,2), null::numeric(18,2))$$,
  'C21: comparativo contra a primeira versão do mês'
);
select throws_ok(
  $$update app.versao_planejamento set descricao = 'x'$$, '42501', null,
  'C21: nem o dono do banco altera versão registrada'
);
select throws_ok(
  $$delete from app.projecao_mensal$$, '42501', null, 'C21: nem o dono do banco apaga linha de versão'
);
select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000d00a", "role": "authenticated"}', true);
set local role authenticated;
select throws_ok($$update app.versao_planejamento set descricao = 'x'$$, '42501', null, 'C21: diretor não altera versão');
select throws_ok($$delete from app.projecao_mensal$$, '42501', null, 'C21: diretor não apaga linha de versão');
reset role;
select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000c00a", "role": "authenticated"}', true);
set local role authenticated;
select is((select count(*) from app.versao_planejamento), 2::bigint, 'C21: gerente lê as versões da obra dele');
reset role;

-- Versão de transação anterior não ganha linha nova
select set_config('session_replication_role', 'replica', true);
insert into app.versao_planejamento (id, tenant_id, centro_custo_id, tipo, numero, descricao, data_referencia, autor, criada_em)
values ('70000000-0000-4000-8000-000000000021', '7e000000-0000-4000-8000-00000000000a',
        '7c000000-0000-4000-8000-0000000000a1', 'projecao', 3, 'Versão de ontem', '2026-09-14',
        '7a000000-0000-4000-8000-00000000f00a', now() - interval '1 day');
select set_config('session_replication_role', 'origin', true);
select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000f00a", "role": "authenticated"}', true);
set local role authenticated;
select throws_ok(
  $$insert into app.projecao_mensal (versao_id, tenant_id, centro_custo_id, competencia, recebido_direto,
      recebido_financiamento, credito_producao_recebido, previsto_direto, previsto_financiamento_elegivel,
      previsto_financiamento_pendente, credito_producao_previsto, vencido_a_receber, pago, a_pagar, a_pagar_vencido,
      custo_sem_titulo_distribuido, total_entradas, total_saidas, saldo_mes, caixa_gerado_acumulado,
      necessidade_aporte_acumulada, aporte_incremental_mes, caixa_gerado_acumulado_conservador,
      necessidade_aporte_conservadora)
    values ('70000000-0000-4000-8000-000000000021', '7e000000-0000-4000-8000-00000000000a',
            '7c000000-0000-4000-8000-0000000000a1', '2026-12-01', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)$$,
  '23514', 'versão já registrada não recebe linhas novas', 'Versão anterior não ganha linha nova'
);
reset role;
select set_config('session_replication_role', 'replica', true);
delete from app.versao_planejamento where id = '70000000-0000-4000-8000-000000000021';
select set_config('session_replication_role', 'origin', true);

-- Pagamento acima do previsto na versão original: causa sustentada pela versão
select pg_temp.titulo('7c000000-0000-4000-8000-0000000000a1', 8103, '2026-09-10', '2026-09-01', 300.00,
  '[{"data": "2026-09-10", "valor": 300.00}]');
select results_eq(
  $$select causa_codigo, quantidade, valor, origem_dado from marts.explicacao_desvio
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'$$,
  $$values ('gasto_acima_previsto', null::integer, 300.00::numeric(18,2), 'versao_planejamento')$$,
  'Desvio: pagamento de setembro acima do previsto na versão 1, e nenhuma outra causa'
);
select results_eq(
  $$select competencia, gastos_previstos_original, gastos_realizados, caixa_gerado_acumulado,
           caixa_gerado_acumulado_original, diferenca_original_atual
    from marts.visao_gerencial_mensal where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' order by 1$$,
  $$values ('2026-09-01'::date, 0.00::numeric(18,2), 300.00::numeric(18,2), -300.00::numeric(18,2), 0.00::numeric(18,2),
            -300.00::numeric(18,2)),
           ('2026-10-01'::date, 1000.00, 0.00, -1800.00, -1000.00, -800.00)$$,
  'Visão gerencial: gastos e caixa contra a versão original'
);
select results_eq(
  $$select realizado_saidas from marts.comparativo_projecao
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' and competencia = '2026-09-01'$$,
  $$values (300.00::numeric(18,2))$$,
  'Comparativo: realizado do mês de referência'
);
select set_config('app.data_referencia', '2026-10-05', true);
select results_eq(
  $$select versao_original_numero from marts.comparativo_projecao
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' limit 1$$,
  $$values (2)$$,
  'Comparativo: sem versão no mês, vale a última dos meses anteriores'
);

-- C23 desvio contra a meta
select pg_temp.limpar();
select set_config('app.data_referencia', '2026-09-15', true);
select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000f00a", "role": "authenticated"}', true);
set local role authenticated;
select isnt(app.registrar_versao_meta('7c000000-0000-4000-8000-0000000000a1', 'Meta de agosto',
  '[{"competencia": "2026-08-01", "unidades": 3, "valor_contratado": 900000.00}]'), null, 'C23: meta registrada');
select throws_ok(
  $$select app.registrar_versao_meta('7c000000-0000-4000-8000-0000000000a1', 'Meta repetida',
      '[{"competencia": "2026-08-01", "unidades": 3}, {"competencia": "2026-08-01", "unidades": 1}]')$$,
  '22023', 'premissa inválida: metas', 'C23: mês repetido na meta é recusado'
);
select throws_ok(
  $$select app.registrar_versao_meta('7c000000-0000-4000-8000-0000000000a1', 'Meta', '[{"competencia": "2026-08-01", "vendas": 3}]')$$,
  '22023', 'premissa inválida: vendas', 'C23: campo desconhecido na meta é recusado'
);
reset role;
select pg_temp.contrato('7c000000-0000-4000-8000-0000000000a1', 7101, 300000.00, '2026-08-12');
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 7101, 1, 'AT', '2026-08-12', 30000.00, 0,
  '[{"data": "2026-08-12", "valor": 30000.00}]');
select results_eq(
  $$select competencia, causa_codigo, quantidade, valor, origem_dado from marts.explicacao_desvio
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'$$,
  $$values ('2026-08-01'::date, 'vendas_abaixo_meta', -2, -600000.00::numeric(18,2), 'versao_planejamento')$$,
  'C23: vendas abaixo da meta em agosto e nenhuma causa em julho'
);
select results_eq(
  $$select meta_unidades, vendas_unidades, meta_valor_contratado, vendas_valor, distratos_unidades,
           entrada_direta_recebida, entrada_direta_prevista_original
    from marts.visao_gerencial_mensal where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'
      and competencia = '2026-08-01'$$,
  $$values (3, 1, 900000.00::numeric(18,2), 300000.00::numeric(18,2), 0, 30000.00::numeric(18,2), null::numeric(18,2))$$,
  'C23: visão gerencial com meta e realizado comercial; sem versão de projeção o original é nulo'
);
select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000f00a", "role": "authenticated"}', true);
set local role authenticated;
select isnt(app.registrar_versao_meta('7c000000-0000-4000-8000-0000000000a1', 'Meta revista',
  '[{"competencia": "2026-08-01", "unidades": 0}]'), null, 'C23: meta revista registrada');
reset role;
select results_eq(
  $$select causa_codigo, quantidade, valor from marts.explicacao_desvio
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'$$,
  $$values ('vendas_acima_meta', 1, null::numeric(18,2))$$,
  'C23: vale a última meta; sem valor na meta, a diferença de valor fica nula'
);
select is((select count(*) from app.meta_mensal where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'), 2::bigint,
  'C23: a meta anterior continua gravada');

-- Pendências depois da entrega das chaves
select pg_temp.limpar();
select set_config('app.data_referencia', '2026-09-15', true);
select pg_temp.unidade('7c000000-0000-4000-8000-0000000000a1', 91201, 'V', '2026-06-30');
select pg_temp.unidade('7c000000-0000-4000-8000-0000000000a1', 91202, 'D', '2026-05-31');
select pg_temp.unidade('7c000000-0000-4000-8000-0000000000a2', 92201, 'V', '2027-12-31');
select pg_temp.contrato('7c000000-0000-4000-8000-0000000000a1', 9101, 3000.00, '2025-06-01', null, null, null, 91201);
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 9101, 1, 'PM', '2026-08-10', 1000.00, 1000.00);
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 9101, 2, 'PM', '2026-11-10', 2000.00, 2000.00);
select pg_temp.titulo('7c000000-0000-4000-8000-0000000000a1', 9201, '2026-10-01', '2026-09-01', 500.00);
insert into app.operacao_credito_obra (id, tenant_id, centro_custo_id, modalidade, instituicao, valor_contratado,
  percentual_retencao, fonte, autor)
values ('7b000000-0000-4000-8000-000000000091', '7e000000-0000-4000-8000-00000000000a',
        '7c000000-0000-4000-8000-0000000000a1', 'plano_empresario', 'Banco Teste', 1000000.00, 0.05,
        'Contrato de crédito', '7a000000-0000-4000-8000-00000000f00a');
insert into app.liberacao_financiamento (tenant_id, centro_custo_id, nivel, operacao_credito_id, valor_previsto,
  data_prevista, situacao, motivo, valor_recebido, data_recebimento, vinculo_tipo, vinculo_chave, fonte, autor)
values
  ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1', 'empreendimento',
   '7b000000-0000-4000-8000-000000000091', 300000.00, '2026-05-10', 'recebida', null, 300000.00, '2026-05-12',
   'lancamento_manual', 'extrato-2026-05-12', 'Extrato', '7a000000-0000-4000-8000-00000000f00a'),
  ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1', 'empreendimento',
   '7b000000-0000-4000-8000-000000000091', 100000.00, '2026-10-10', 'prevista', null, null, null, null, null,
   'Cronograma', '7a000000-0000-4000-8000-00000000f00a'),
  ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1', 'empreendimento',
   '7b000000-0000-4000-8000-000000000091', 50000.00, '2026-11-10', 'pendente', 'habite-se', null, null, null, null,
   'Cronograma', '7a000000-0000-4000-8000-00000000f00a');
select results_eq(
  $$select centro_custo_id, data_entrega, recebiveis_vencidos, recebiveis_a_vencer, parcelas_abertas, titulos_em_aberto,
           titulos_abertos, liberacoes_nao_recebidas, credito_nao_liberado
    from marts.pendencias_pos_entrega where tenant_id = '7e000000-0000-4000-8000-00000000000a'$$,
  $$values ('7c000000-0000-4000-8000-0000000000a1'::uuid, '2026-06-30'::date, 1000.00::numeric(18,2),
            2000.00::numeric(18,2), 2, 500.00::numeric(18,2), 1, 150000.00::numeric(18,2), 700000.00::numeric(18,2))$$,
  'Pós-entrega: só T1, com recebíveis, título, liberações e crédito ainda abertos'
);
select results_eq(
  $$select competencia, causa_codigo, quantidade, valor, origem_dado from marts.explicacao_desvio
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'$$,
  $$values ('2026-08-01'::date, 'parcelas_vencidas_sem_pagamento', 1, 1000.00::numeric(18,2), 'origem')$$,
  'Desvio: parcela vencida sem pagamento é causa sustentada pela origem'
);
select is((select count(*) from marts.explicacao_desvio where centro_custo_id = '7c000000-0000-4000-8000-0000000000a2'),
  0::bigint, 'Desvio: obra sem dado não ganha causa');

select * from finish();
rollback;
