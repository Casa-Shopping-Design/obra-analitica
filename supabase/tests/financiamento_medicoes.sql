-- Casos C04 e C05 (financiamento), C13, C14, C15, C16, C17 e C20 de docs/financeiro/casos_teste.md, o caso de
-- 100 unidades com 50 vendidas e as reconciliações R1, R13 e R18. Nível staging; cada caso limpa o tenant A.
begin;
create extension if not exists pgtap with schema extensions;
select plan(69);

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

-- C04 financiamento separado da entrada direta
select set_config('app.data_referencia', '2026-03-31', true);
select pg_temp.contrato('7c000000-0000-4000-8000-0000000000a1', 5301, 400000.00, '2026-01-05', 300000.00);
select pg_temp.contrato('7c000000-0000-4000-8000-0000000000a1', 5302, 200000.00, '2025-06-01', 150000.00, '001', '2026-02-10');
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 5301, 1, 'AT', '2026-01-05', 40000.00, 0,
  '[{"data": "2026-01-05", "valor": 40000.00}]');
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 5301, 2, 'PM', '2026-06-05', 60000.00, 60000.00);
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 5301, 3, 'FI', '2026-12-20', 300000.00, 300000.00);
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 5302, 1, 'AT', '2025-06-01', 50000.00, 0,
  '[{"data": "2025-06-01", "valor": 50000.00}]');
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 5302, 2, 'FI', '2026-02-10', 150000.00, 0,
  '[{"data": "2026-02-12", "valor": 150000.00}]');

select results_eq(
  $$select contrato_id_origem, classificacao, saldo_financiamento_aberto, recebido_financiamento, instituicao_financeira
    from marts.financiamento_contrato where tenant_id = '7e000000-0000-4000-8000-00000000000a' order by 1$$,
  $$values (5301, 'financiamento_pendente', 300000.00::numeric(18,2), 0.00::numeric(18,2), null::text),
           (5302, 'financiamento_elegivel', 0.00::numeric(18,2), 150000.00::numeric(18,2), '001')$$,
  'C04: 5301 sem etapa nem data do banco fica pendente; 5302 com financiamento na origem fica elegível'
);
select results_eq(
  $$select contrato_id_origem, parcela_id_origem, origem, classe, situacao, incluida_projecao
    from marts.recebivel_projetado where tenant_id = '7e000000-0000-4000-8000-00000000000a' order by 1, 2$$,
  $$values (5301, 2, 'direta', 'direta', 'a_vencer', true),
           (5301, 3, 'financiamento', 'financiamento_pendente', 'a_vencer', true)$$,
  'C04: só as parcelas em aberto viram recebível projetado'
);
select results_eq(
  $$select competencia, recebido_direto, recebido_financiamento, previsto_direto, previsto_financiamento_pendente
    from marts.fluxo_projetado_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'
      and competencia in ('2025-06-01', '2026-01-01', '2026-02-01', '2026-06-01', '2026-12-01') order by 1$$,
  $$values ('2025-06-01'::date, 50000.00::numeric(18,2), 0.00::numeric(18,2), 0.00::numeric(18,2), 0.00::numeric(18,2)),
           ('2026-01-01'::date, 40000.00, 0.00, 0.00, 0.00),
           ('2026-02-01'::date, 0.00, 150000.00, 0.00, 0.00),
           ('2026-06-01'::date, 0.00, 0.00, 60000.00, 0.00),
           ('2026-12-01'::date, 0.00, 0.00, 0.00, 300000.00)$$,
  'C04: fluxo projetado separa direta, financiamento recebido e financiamento pendente'
);
select is(
  (select count(*) from marts.fluxo_projetado_mensal where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'),
  19::bigint, 'C04: calendário contínuo de 2025-06 a 2026-12'
);
-- R13 contra a posição da 0007
select is(
  (select sum(previsto_direto) from marts.fluxo_projetado_mensal where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'),
  (select a_receber_direto from marts.posicao_financeira_obra where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'),
  'R13: previsto direto do fluxo igual ao a receber direto da posição'
);
select is(
  (select sum(recebido_direto + recebido_financiamento) from marts.fluxo_projetado_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'),
  (select recebido_direto + recebido_repasse from marts.posicao_financeira_obra
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'),
  'R1 no fluxo projetado: recebido igual ao da posição'
);

-- C05 parcela vencida fora da previsão; a FI vencida vai para o informativo
select pg_temp.limpar();
select set_config('app.data_referencia', '2026-03-20', true);
select pg_temp.contrato('7c000000-0000-4000-8000-0000000000a1', 5401, 200000.00, '2025-10-01');
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 5401, 1, 'PM', '2026-03-10', 2000.00, 2000.00);
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 5401, 2, 'PM', '2026-04-10', 2000.00, 2000.00);
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 5401, 3, 'FI', '2026-03-01', 100000.00, 100000.00);

select results_eq(
  $$select classe, situacao, incluida_projecao from marts.recebivel_projetado
    where tenant_id = '7e000000-0000-4000-8000-00000000000a' and contrato_id_origem = 5401 and parcela_id_origem = 3$$,
  $$values ('financiamento_pendente', 'vencida', false)$$,
  'C05: FI vencida fica fora da projeção'
);
select results_eq(
  $$select competencia, previsto_direto, vencido_a_receber, total_entradas, saldo_mes
    from marts.fluxo_projetado_mensal where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' order by 1$$,
  $$values ('2026-03-01'::date, 0.00::numeric(18,2), 102000.00::numeric(18,2), 0.00::numeric(18,2), 0.00::numeric(18,2)),
           ('2026-04-01'::date, 2000.00, 0.00, 2000.00, 2000.00)$$,
  'C05: março sem entrada prevista, vencido informativo; abril com a parcela a vencer'
);
select is(
  (select sum(previsto_financiamento_elegivel + previsto_financiamento_pendente)
          + (select sum(saldo) from marts.recebivel_projetado
             where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' and origem = 'financiamento'
               and not incluida_projecao)
   from marts.fluxo_projetado_mensal where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'),
  (select a_receber_repasse + repasse_atrasado from marts.posicao_financeira_obra
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'),
  'R13: financiamento previsto mais FI vencida igual ao a receber e atrasado de repasse da posição'
);

-- C13 unidades não vendidas não geram liberação
select pg_temp.limpar();
select set_config('app.data_referencia', '2026-09-15', true);
select pg_temp.unidade('7c000000-0000-4000-8000-0000000000a2', u, case when u <= 92003 then 'V' else 'D' end)
from generate_series(92001, 92010) u;
select pg_temp.contrato('7c000000-0000-4000-8000-0000000000a2', 6300 + n, 250000.00, '2026-05-01', 100000.00, null, null, 92000 + n)
from generate_series(1, 3) n;
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a2', 6300 + n, 1, 'FI', '2027-03-10', 100000.00, 100000.00)
from generate_series(1, 3) n;

select is((select count(*) from marts.financiamento_contrato where centro_custo_id = '7c000000-0000-4000-8000-0000000000a2'),
  3::bigint, 'C13: só as três vendas têm financiamento');
select is((select count(*) from marts.recebivel_projetado
  where centro_custo_id = '7c000000-0000-4000-8000-0000000000a2' and origem = 'financiamento'), 3::bigint,
  'C13: três recebíveis de financiamento, nenhum das unidades em estoque');
select results_eq(
  $$select previsto_financiamento_pendente, previsto_financiamento_elegivel from marts.fluxo_projetado_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a2' and competencia = '2027-03-01'$$,
  $$values (300000.00::numeric(18,2), 0.00::numeric(18,2))$$,
  'C13: financiamento sem etapa entra como pendente'
);
select is((select unidade from marts.financiamento_contrato where tenant_id = '7e000000-0000-4000-8000-00000000000a' and contrato_id_origem = 6301), 'Unidade 92001',
  'C13: unidade do contrato pelo nome, sem dado do comprador');
select hasnt_column('marts', 'financiamento_contrato', 'nome_cliente', 'financiamento_contrato não expõe o comprador');

select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000f00a", "role": "authenticated"}', true);
set local role authenticated;
select throws_ok(
  $$insert into app.liberacao_financiamento (tenant_id, centro_custo_id, nivel, contrato_id_origem, valor_previsto,
      data_prevista, situacao, fonte)
    values ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a2', 'contrato', 6399,
            100000.00, '2027-03-10', 'prevista', 'teste')$$,
  '23514', null, 'C13: liberação de contrato inexistente (unidade sem venda) é recusada'
);
select throws_ok(
  $$insert into app.liberacao_financiamento (tenant_id, centro_custo_id, nivel, valor_previsto, data_prevista,
      situacao, fonte)
    values ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a2', 'contrato', 100000.00,
            '2027-03-10', 'prevista', 'teste')$$,
  '23514', null, 'C13: liberação de contrato sem contrato é recusada'
);
select throws_ok(
  $$insert into app.etapa_financiamento_contrato (tenant_id, centro_custo_id, contrato_id_origem, etapa, data_etapa, fonte)
    values ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a2', 6399, 'elegivel',
            '2026-09-01', 'teste')$$,
  '23514', null, 'C13: etapa de contrato inexistente é recusada'
);
select lives_ok(
  $$insert into app.liberacao_financiamento (tenant_id, centro_custo_id, nivel, contrato_id_origem, valor_previsto,
      data_prevista, situacao, fonte)
    values ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a2', 'contrato', 6301,
            100000.00, '2027-03-10', 'prevista', 'Ofício do banco')$$,
  'C13: liberação de contrato vendido é aceita'
);
reset role;
select results_eq(
  $$select previsto_financiamento_pendente from marts.fluxo_projetado_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a2' and competencia = '2027-03-01'$$,
  $$values (300000.00::numeric(18,2))$$,
  'C13: liberação de contrato só classifica, não soma à parcela FI'
);

-- 100 unidades, 50 vendidas com financiamento: só as elegíveis entram como financiamento elegível
select pg_temp.limpar();
select set_config('app.data_referencia', '2026-09-15', true);
select pg_temp.unidade('7c000000-0000-4000-8000-0000000000a1', 91000 + n, case when n <= 50 then 'V' else 'D' end, null, 300000.00)
from generate_series(1, 100) n;
select pg_temp.contrato('7c000000-0000-4000-8000-0000000000a1', 8000 + n, 300000.00, '2026-03-01', 200000.00, null, null, 91000 + n)
from generate_series(1, 50) n;
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a1', 8000 + n, 1, 'FI', '2027-06-10', 200000.00, 200000.00)
from generate_series(1, 50) n;

select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000f00a", "role": "authenticated"}', true);
set local role authenticated;
select lives_ok(
  $$insert into app.etapa_financiamento_contrato (tenant_id, centro_custo_id, contrato_id_origem, etapa, data_etapa,
      data_prevista_liberacao, fonte)
    select '7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1', 8000 + n,
           case when n <= 20 then 'elegivel' else 'aprovacao' end, '2026-09-01',
           case when n <= 20 then date '2027-02-10' end, 'Planilha do correspondente'
    from generate_series(1, 25) n$$,
  '100/50: financeiro cadastra 20 elegíveis e 5 em aprovação'
);
reset role;
select results_eq(
  $$select classificacao, count(*) from marts.financiamento_contrato
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' group by 1 order by 1$$,
  $$values ('financiamento_elegivel', 20::bigint), ('financiamento_pendente', 30::bigint)$$,
  '100/50: 20 elegíveis e 30 pendentes, nenhuma linha para as 50 unidades em estoque'
);
select results_eq(
  $$select competencia, previsto_financiamento_elegivel, previsto_financiamento_pendente
    from marts.fluxo_projetado_mensal where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'
      and (previsto_financiamento_elegivel <> 0 or previsto_financiamento_pendente <> 0) order by 1$$,
  $$values ('2027-02-01'::date, 4000000.00::numeric(18,2), 0.00::numeric(18,2)),
           ('2027-06-01'::date, 0.00, 6000000.00)$$,
  '100/50: elegíveis na data prevista do banco, pendentes no vencimento'
);
select results_eq(
  $$select caixa_gerado_acumulado, caixa_gerado_acumulado_conservador, necessidade_aporte_conservadora
    from marts.fluxo_projetado_mensal where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'
    order by competencia desc limit 1$$,
  $$values (10000000.00::numeric(18,2), 4000000.00::numeric(18,2), 0.00::numeric(18,2))$$,
  '100/50: o conservador conta só o financiamento elegível'
);
select is(
  (select count(*) from app.auditoria_alteracao where tabela = 'app.etapa_financiamento_contrato'
     and autor = '7a000000-0000-4000-8000-00000000f00a' and operacao = 'insert'),
  25::bigint, '100/50: uma linha de auditoria por etapa, com o autor do JWT'
);
select is(
  (select registro_id from app.auditoria_alteracao where tabela = 'app.etapa_financiamento_contrato' order by registro_id limit 1),
  '7e000000-0000-4000-8000-00000000000a|8001', 'auditoria da etapa com a chave composta'
);

-- C14 venda sem financiamento elegível não vira entrada bancária automática
select pg_temp.limpar();
select set_config('app.data_referencia', '2026-09-15', true);
select pg_temp.contrato('7c000000-0000-4000-8000-0000000000a2', 6401, 200000.00, '2026-06-01', 180000.00);
select pg_temp.contrato('7c000000-0000-4000-8000-0000000000a2', 6402, 250000.00, '2026-06-01', 200000.00);
select pg_temp.contrato('7c000000-0000-4000-8000-0000000000a2', 6403, 150000.00, '2026-06-01', 0.00);
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a2', 6401, 1, 'FI', '2027-01-10', 180000.00, 180000.00);
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a2', 6402, 1, 'FI', '2027-01-10', 200000.00, 200000.00);
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a2', 6403, 1, 'PM', '2027-01-10', 150000.00, 150000.00);
insert into app.etapa_financiamento_contrato (tenant_id, centro_custo_id, contrato_id_origem, etapa, data_etapa, fonte, autor)
values ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a2', 6402, 'elegivel', '2026-09-01',
        'Carta de crédito', '7a000000-0000-4000-8000-00000000f00a');

select results_eq(
  $$select contrato_id_origem, classificacao from marts.financiamento_contrato where tenant_id = '7e000000-0000-4000-8000-00000000000a' order by 1$$,
  $$values (6401, 'financiamento_pendente'), (6402, 'financiamento_elegivel')$$,
  'C14: 6401 pendente, 6402 elegível e 6403 sem linha'
);
select results_eq(
  $$select previsto_financiamento_elegivel, previsto_financiamento_pendente, previsto_direto, saldo_mes,
           caixa_gerado_acumulado, caixa_gerado_acumulado_conservador
    from marts.fluxo_projetado_mensal where centro_custo_id = '7c000000-0000-4000-8000-0000000000a2'
      and competencia = '2027-01-01'$$,
  $$values (200000.00::numeric(18,2), 180000.00::numeric(18,2), 150000.00::numeric(18,2), 530000.00::numeric(18,2),
            530000.00::numeric(18,2), 350000.00::numeric(18,2))$$,
  'C14: janeiro separa elegível, pendente e direta; conservador sem o pendente'
);
select is((select financiamento_pendente_total from marts.resumo_projecao_obra
  where centro_custo_id = '7c000000-0000-4000-8000-0000000000a2'), 180000.00::numeric(18,2),
  'C14: resumo com o financiamento pendente');

select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000f00a", "role": "authenticated"}', true);
set local role authenticated;
select throws_ok(
  $$update app.etapa_financiamento_contrato set pendencia = true where tenant_id = '7e000000-0000-4000-8000-00000000000a' and contrato_id_origem = 6402$$,
  '23514', null, 'C14: pendência sem motivo é recusada'
);
select lives_ok(
  $$update app.etapa_financiamento_contrato set pendencia = true, motivo_pendencia = 'documentação do comprador'
    where tenant_id = '7e000000-0000-4000-8000-00000000000a' and contrato_id_origem = 6402$$,
  'C14: financeiro marca pendência com motivo'
);
reset role;
select results_eq(
  $$select previsto_financiamento_pendente, previsto_financiamento_elegivel from marts.fluxo_projetado_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a2' and competencia = '2027-01-01'$$,
  $$values (380000.00::numeric(18,2), 0.00::numeric(18,2))$$,
  'C14: com pendência, 6402 volta a pendente'
);
select is(
  (select count(*) from app.auditoria_alteracao where tabela = 'app.etapa_financiamento_contrato' and operacao = 'update'
     and antes ->> 'pendencia' = 'false' and depois ->> 'pendencia' = 'true'),
  1::bigint, 'C14: a mudança fica na auditoria com o antes e o depois'
);
update staging.contrato_venda set data_repasse = '2026-09-01' where id_origem = 6401;
select is((select classificacao from marts.financiamento_contrato where tenant_id = '7e000000-0000-4000-8000-00000000000a' and contrato_id_origem = 6401),
  'financiamento_elegivel', 'C14: data do financiamento na origem torna 6401 elegível (P9)');

-- C15 e C20: valores diferentes por contrato e liberação agregada sem rateio por unidade
select pg_temp.limpar();
select set_config('app.data_referencia', '2026-09-15', true);
select pg_temp.contrato('7c000000-0000-4000-8000-0000000000a2', c, v, '2026-04-01', v)
from (values (6501, 100000.00), (6502, 150000.00), (6503, 250000.00)) x(c, v);
select pg_temp.parcela('7c000000-0000-4000-8000-0000000000a2', c, 1, 'FI', '2027-02-10', v, v)
from (values (6501, 100000.00), (6502, 150000.00), (6503, 250000.00)) x(c, v);
insert into app.etapa_financiamento_contrato (tenant_id, centro_custo_id, contrato_id_origem, etapa, data_etapa,
  data_prevista_liberacao, fonte, autor)
select '7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a2', c, 'elegivel', '2026-09-01',
       '2026-11-10', 'Carta de crédito', '7a000000-0000-4000-8000-00000000f00a'
from unnest(array[6501, 6502, 6503]) c;
insert into app.operacao_credito_obra (id, tenant_id, centro_custo_id, modalidade, instituicao, valor_contratado,
  percentual_retencao, fonte, autor)
values ('7b000000-0000-4000-8000-000000000015', '7e000000-0000-4000-8000-00000000000a',
        '7c000000-0000-4000-8000-0000000000a2', 'credito_producao', 'Banco Teste', 1000000.00, 0.05,
        'Contrato de crédito', '7a000000-0000-4000-8000-00000000f00a');
insert into app.liberacao_financiamento (tenant_id, centro_custo_id, nivel, operacao_credito_id, valor_previsto,
  data_prevista, situacao, fonte, autor)
values ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a2', 'empreendimento',
        '7b000000-0000-4000-8000-000000000015', 500000.00, '2026-12-10', 'prevista', 'Cronograma do banco',
        '7a000000-0000-4000-8000-00000000f00a');

select results_eq(
  $$select contrato_id_origem, saldo_financiamento_aberto from marts.financiamento_contrato where tenant_id = '7e000000-0000-4000-8000-00000000000a' order by 1$$,
  $$values (6501, 100000.00::numeric(18,2)), (6502, 150000.00::numeric(18,2)), (6503, 250000.00::numeric(18,2))$$,
  'C15: saldo de cada contrato pelo seu valor, nenhum 166666.67'
);
select results_eq(
  $$select distinct data_prevista from marts.recebivel_projetado where centro_custo_id = '7c000000-0000-4000-8000-0000000000a2'$$,
  $$values ('2026-11-10'::date)$$,
  'C15: data prevista da etapa no lugar do vencimento'
);
select results_eq(
  $$select competencia, previsto_financiamento_elegivel, credito_producao_previsto from marts.fluxo_projetado_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a2' and competencia >= '2026-11-01' order by 1$$,
  $$values ('2026-11-01'::date, 500000.00::numeric(18,2), 0.00::numeric(18,2)),
           ('2026-12-01'::date, 0.00, 500000.00)$$,
  'C15: financiamento em novembro, crédito à produção em dezembro, nada no vencimento de fevereiro'
);
select is((select contrato_id_origem from marts.liberacao_status where tenant_id = '7e000000-0000-4000-8000-00000000000a' and nivel = 'empreendimento'), null::integer,
  'C15: liberação de empreendimento sem contrato');

insert into app.liberacao_financiamento (tenant_id, centro_custo_id, nivel, operacao_credito_id, valor_previsto,
  data_prevista, situacao, valor_recebido, data_recebimento, vinculo_tipo, vinculo_chave, fonte, autor)
values ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a2', 'empreendimento',
        '7b000000-0000-4000-8000-000000000015', 500000.00, '2026-08-20', 'recebida', 500000.00, '2026-08-20',
        'lancamento_manual', 'extrato-2026-08-20-001', 'Extrato bancário', '7a000000-0000-4000-8000-00000000f00a');
select is((select count(*) from marts.liberacao_status where tenant_id = '7e000000-0000-4000-8000-00000000000a' and nivel = 'empreendimento' and contrato_id_origem is not null),
  0::bigint, 'C20: nenhuma liberação agregada ligada a contrato');
select hasnt_column('marts', 'financiamento_contrato', 'valor_liberado', 'C20: financiamento_contrato sem valor liberado');
select hasnt_column('marts', 'recebivel_projetado', 'valor_liberado', 'C20: recebivel_projetado sem valor liberado');
select hasnt_column('marts', 'carteira_recebiveis', 'valor_liberado', 'C20: carteira_recebiveis sem valor liberado');
select results_eq(
  $$select competencia, credito_producao_recebido from marts.fluxo_projetado_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a2' and credito_producao_recebido <> 0$$,
  $$values ('2026-08-01'::date, 500000.00::numeric(18,2))$$,
  'C20: crédito à produção recebido numa linha da obra'
);
select results_eq(
  $$select contrato_id_origem, recebido_financiamento from marts.financiamento_contrato where tenant_id = '7e000000-0000-4000-8000-00000000000a' order by 1$$,
  $$values (6501, 0.00::numeric(18,2)), (6502, 0.00::numeric(18,2)), (6503, 0.00::numeric(18,2))$$,
  'C20: a liberação agregada não é repartida entre os contratos'
);

-- C16 medição aprovada sem recebimento fica fora do realizado
select pg_temp.limpar();
select set_config('app.data_referencia', '2026-09-15', true);
select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000f00a", "role": "authenticated"}', true);
set local role authenticated;
select lives_ok(
  $$insert into app.operacao_credito_obra (id, tenant_id, centro_custo_id, modalidade, instituicao, valor_contratado,
      percentual_retencao, fonte, referencia_documento, autor)
    values ('7b000000-0000-4000-8000-000000000016', '7e000000-0000-4000-8000-00000000000a',
            '7c000000-0000-4000-8000-0000000000a1', 'credito_producao', 'Banco Teste', 1000000.00, 0.05,
            'Contrato de crédito', 'CT-16', '7a000000-0000-4000-8000-00000000d00a')$$,
  'C16: financeiro cadastra a operação'
);
select throws_ok(
  $$insert into app.medicao_bancaria (tenant_id, centro_custo_id, operacao_credito_id, numero, data_vistoria,
      avanco_fisico_informado, situacao, valor_elegivel, fonte)
    values ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1',
            '7b000000-0000-4000-8000-000000000016', 1, '2026-08-10', 0.20, 'aprovada', 200000.00, 'RAE 1')$$,
  '23514', null, 'C16: medição aprovada sem data de aprovação é recusada'
);
select lives_ok(
  $$insert into app.medicao_bancaria (id, tenant_id, centro_custo_id, operacao_credito_id, numero, data_vistoria,
      avanco_fisico_informado, situacao, data_aprovacao, valor_elegivel, fonte)
    values ('7d000000-0000-4000-8000-000000000016', '7e000000-0000-4000-8000-00000000000a',
            '7c000000-0000-4000-8000-0000000000a1', '7b000000-0000-4000-8000-000000000016', 1, '2026-08-10', 0.20,
            'aprovada', '2026-08-20', 200000.00, 'RAE 1')$$,
  'C16: medição aprovada cadastrada'
);
select throws_ok(
  $$insert into app.medicao_bancaria (tenant_id, centro_custo_id, operacao_credito_id, numero, data_vistoria,
      avanco_fisico_informado, situacao, fonte)
    values ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a2',
            '7b000000-0000-4000-8000-000000000016', 2, '2026-09-10', 0.30, 'apresentada', 'RAE 2')$$,
  '23503', null, 'C16: medição não liga a operação de outra obra'
);
select lives_ok(
  $$insert into app.liberacao_financiamento (id, tenant_id, centro_custo_id, nivel, operacao_credito_id, medicao_id,
      valor_previsto, data_prevista, situacao, fonte)
    values ('7f000000-0000-4000-8000-000000000016', '7e000000-0000-4000-8000-00000000000a',
            '7c000000-0000-4000-8000-0000000000a1', 'empreendimento', '7b000000-0000-4000-8000-000000000016',
            '7d000000-0000-4000-8000-000000000016', 200000.00, '2026-09-05', 'prevista', 'Cronograma do banco')$$,
  'C16: liberação prevista pela medição'
);
reset role;
select results_eq(
  $$select situacao_efetiva, dias_atraso, origem_dado from marts.liberacao_status
    where id = '7f000000-0000-4000-8000-000000000016'$$,
  $$values ('atrasada', 10, 'complemento_manual')$$,
  'C16: liberação prevista vencida aparece atrasada'
);
select is(
  (select count(*) from marts.fluxo_projetado_mensal where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'
     and (credito_producao_recebido <> 0 or credito_producao_previsto <> 0)),
  0::bigint, 'C16: medição aprovada e liberação atrasada não entram no fluxo'
);
select is(
  (select count(*) from marts.fluxo_caixa_mensal where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'
     and entrada_direta_realizada + repasse_realizado <> 0),
  0::bigint, 'C16: nenhuma entrada realizada no fluxo de caixa'
);
select results_eq(
  $$select medido_elegivel, liberado_recebido, elegivel_nao_liberado, previsto_aberto, retencao_prevista,
           limite_antes_retencao, saldo_liberavel, saldo_nao_programado, excede_limite
    from marts.saldo_operacao_credito where operacao_credito_id = '7b000000-0000-4000-8000-000000000016'$$,
  $$values (200000.00::numeric(18,2), 0.00::numeric(18,2), 200000.00::numeric(18,2), 200000.00::numeric(18,2),
            50000.00::numeric(18,2), 950000.00::numeric(18,2), 950000.00::numeric(18,2), 750000.00::numeric(18,2), false)$$,
  'C16: saldo da operação com retenção e medição sem dinheiro'
);
select results_eq(
  $$select causa_codigo, quantidade, valor, origem_dado from marts.explicacao_desvio
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' and competencia = '2026-09-01'$$,
  $$values ('liberacao_prevista_vencida', 1, 200000.00::numeric(18,2), 'complemento_manual')$$,
  'C16: desvio explicado pela liberação vencida, sem outra causa'
);
select results_eq(
  $$select autor, fonte, referencia_documento from app.operacao_credito_obra
    where id = '7b000000-0000-4000-8000-000000000016'$$,
  $$values ('7a000000-0000-4000-8000-00000000f00a'::uuid, 'Contrato de crédito', 'CT-16')$$,
  'C16: autor gravado é o do JWT, com fonte e documento'
);

-- C17 liberação parcial respeitando saldo e limite
select pg_temp.limpar();
select set_config('app.data_referencia', '2026-09-15', true);
insert into app.operacao_credito_obra (id, tenant_id, centro_custo_id, modalidade, instituicao, valor_contratado,
  percentual_retencao, fonte, autor)
values ('7b000000-0000-4000-8000-000000000017', '7e000000-0000-4000-8000-00000000000a',
        '7c000000-0000-4000-8000-0000000000a1', 'credito_producao', 'Banco Teste', 1000000.00, 0.05,
        'Contrato de crédito', '7a000000-0000-4000-8000-00000000f00a');
select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000f00a", "role": "authenticated"}', true);
set local role authenticated;
select lives_ok(
  $$insert into app.liberacao_financiamento (tenant_id, centro_custo_id, nivel, operacao_credito_id, valor_previsto,
      data_prevista, situacao, valor_recebido, data_recebimento, vinculo_tipo, vinculo_chave, fonte)
    values ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1', 'empreendimento',
            '7b000000-0000-4000-8000-000000000017', 300000.00, '2026-07-05', 'recebida', 300000.00, '2026-07-10',
            'lancamento_manual', 'extrato-2026-07-10-001', 'Extrato bancário'),
           ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1', 'empreendimento',
            '7b000000-0000-4000-8000-000000000017', 600000.00, '2026-10-10', 'prevista', null, null, null, null,
            'Cronograma do banco')$$,
  'C17: L1 recebida e L2 prevista'
);
reset role;
select results_eq(
  $$select retencao_prevista, limite_antes_retencao, liberado_recebido, previsto_aberto, saldo_liberavel,
           saldo_nao_programado, excede_limite
    from marts.saldo_operacao_credito where operacao_credito_id = '7b000000-0000-4000-8000-000000000017'$$,
  $$values (50000.00::numeric(18,2), 950000.00::numeric(18,2), 300000.00::numeric(18,2), 600000.00::numeric(18,2),
            650000.00::numeric(18,2), 50000.00::numeric(18,2), false)$$,
  'C17: saldo liberável e não programado'
);
select results_eq(
  $$select competencia, credito_producao_recebido, credito_producao_previsto from marts.fluxo_projetado_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1'
      and (credito_producao_recebido <> 0 or credito_producao_previsto <> 0) order by 1$$,
  $$values ('2026-07-01'::date, 300000.00::numeric(18,2), 0.00::numeric(18,2)),
           ('2026-10-01'::date, 0.00, 600000.00)$$,
  'C17: recebida em julho pelo dia do dinheiro, prevista em outubro'
);
select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000f00a", "role": "authenticated"}', true);
set local role authenticated;
select throws_ok(
  $$insert into app.liberacao_financiamento (tenant_id, centro_custo_id, nivel, operacao_credito_id, valor_previsto,
      data_prevista, situacao, fonte)
    values ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1', 'empreendimento',
            '7b000000-0000-4000-8000-000000000017', 150000.00, '2026-12-10', 'prevista', 'teste')$$,
  '23514', null, 'C17: L3 de 150000 passaria de 1000000 e é recusada'
);
select lives_ok(
  $$insert into app.liberacao_financiamento (id, tenant_id, centro_custo_id, nivel, operacao_credito_id, valor_previsto,
      data_prevista, situacao, fonte)
    values ('7f000000-0000-4000-8000-000000000173', '7e000000-0000-4000-8000-00000000000a',
            '7c000000-0000-4000-8000-0000000000a1', 'empreendimento', '7b000000-0000-4000-8000-000000000017',
            100000.00, '2026-12-10', 'prevista', 'teste')$$,
  'C17: L3 de 100000 fecha o valor contratado'
);
reset role;
select results_eq(
  $$select excede_limite, saldo_nao_programado from marts.saldo_operacao_credito
    where operacao_credito_id = '7b000000-0000-4000-8000-000000000017'$$,
  $$values (true, 0.00::numeric(18,2))$$,
  'C17: acima do limite depois da retenção, sinalizado'
);
select set_config('request.jwt.claims', '{"sub": "7a000000-0000-4000-8000-00000000f00a", "role": "authenticated"}', true);
set local role authenticated;
select throws_ok(
  $$update app.operacao_credito_obra set valor_contratado = 900000.00
    where id = '7b000000-0000-4000-8000-000000000017'$$,
  '23514', null, 'C17: valor contratado não desce abaixo do programado'
);
select lives_ok(
  $$update app.liberacao_financiamento set situacao = 'cancelada', motivo = 'teste de limite'
    where id = '7f000000-0000-4000-8000-000000000173'$$,
  'C17: L3 cancelada pelo financeiro'
);
select throws_ok(
  $$insert into app.liberacao_financiamento (tenant_id, centro_custo_id, nivel, operacao_credito_id, valor_previsto,
      data_prevista, situacao, valor_recebido, data_recebimento, vinculo_tipo, vinculo_chave, fonte)
    values ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1', 'empreendimento',
            '7b000000-0000-4000-8000-000000000017', 10000.00, '2026-07-05', 'recebida', 10000.00, '2026-07-10',
            'lancamento_manual', 'extrato-2026-07-10-001', 'teste')$$,
  '23505', null, 'C17: o mesmo lançamento do extrato não liga a duas liberações'
);
select throws_ok(
  $$insert into app.liberacao_financiamento (tenant_id, centro_custo_id, nivel, operacao_credito_id, valor_previsto,
      data_prevista, situacao, valor_recebido, data_recebimento, vinculo_tipo, fonte)
    values ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1', 'empreendimento',
            '7b000000-0000-4000-8000-000000000017', 10000.00, '2026-07-05', 'recebida', 10000.00, '2026-07-10',
            'lancamento_manual', 'teste')$$,
  '23514', null, 'C17: liberação recebida sem chave do vínculo é recusada'
);
select lives_ok(
  $$insert into app.liberacao_financiamento (tenant_id, centro_custo_id, nivel, operacao_credito_id, descricao_lote,
      valor_previsto, data_prevista, situacao, valor_recebido, data_recebimento, vinculo_tipo, vinculo_chave, fonte)
    values ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1', 'lote',
            '7b000000-0000-4000-8000-000000000017', 'Lote teste', 50000.00, '2026-08-01', 'recebida', 50000.00,
            '2026-08-01', 'recebimento', '6601|1|1', 'Extrato bancário')$$,
  'C17: L5 de lote ligada a um recebimento do staging'
);
reset role;
select is(
  (select credito_producao_recebido from marts.fluxo_projetado_mensal
    where centro_custo_id = '7c000000-0000-4000-8000-0000000000a1' and competencia = '2026-08-01'),
  0.00::numeric(18,2), 'C17: liberação ligada a recebimento não soma de novo no fluxo'
);
select ok(
  not exists (select 1 from marts.saldo_operacao_credito where liberado_recebido + previsto_aberto > valor_contratado),
  'R18: nenhuma operação com recebido mais previsto acima do contratado'
);
select results_eq(
  $$select operacao, depois ->> 'situacao', autor from app.auditoria_alteracao
    where tabela = 'app.liberacao_financiamento' and registro_id = '7f000000-0000-4000-8000-000000000173' order by alterado_em, id$$,
  $$values ('insert', 'prevista', '7a000000-0000-4000-8000-00000000f00a'::uuid),
           ('update', 'cancelada', '7a000000-0000-4000-8000-00000000f00a'::uuid)$$,
  'C17: inclusão e cancelamento de L3 na auditoria'
);
select pg_temp.contrato('7c000000-0000-4000-8000-0000000000a1', 7701, 100000.00, '2026-05-01', 80000.00);
select throws_ok(
  $$insert into app.liberacao_financiamento (tenant_id, centro_custo_id, nivel, contrato_id_origem, valor_previsto,
      data_prevista, situacao, valor_recebido, data_recebimento, vinculo_tipo, vinculo_chave, fonte, autor)
    values ('7e000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-0000000000a1', 'contrato', 7701,
            1000.00, '2026-07-05', 'recebida', 1000.00, '2026-07-10', 'lancamento_manual', 'x', 'teste',
            '7a000000-0000-4000-8000-00000000f00a')$$,
  '23514', null, 'liberação de contrato não aceita lançamento manual, que duplicaria a parcela FI'
);

select * from finish();
rollback;
