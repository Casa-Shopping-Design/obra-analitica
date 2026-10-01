-- Repasse por banco e leads por origem com caso conhecido: a soma dos bancos fecha com a obra, o
-- repasse antigo do contrato não conta, o distrato fica fora, parado em análise usa a data da última
-- mudança de situação, e o gerente só vê banco e lead da obra dele. Cria os próprios dados.
begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

insert into app.tenant (id, razao_social) values
  ('0e000000-0000-4000-8000-0000000000e1', 'Construtora Bancos'),
  ('0e000000-0000-4000-8000-0000000000e2', 'Construtora Bancos vizinha');

insert into app.centro_custo (id, tenant_id, id_origem, nome) values
  ('0c000000-0000-4000-8000-0000000000e1', '0e000000-0000-4000-8000-0000000000e1', 981, 'Obra Bancos A'),
  ('0c000000-0000-4000-8000-0000000000e2', '0e000000-0000-4000-8000-0000000000e1', 982, 'Obra Bancos B'),
  ('0c000000-0000-4000-8000-0000000000e3', '0e000000-0000-4000-8000-0000000000e2', 981, 'Obra Bancos vizinha');

insert into auth.users (id, email) values
  ('0a000000-0000-4000-8000-00000000d0e1', 'diretor.bancos@teste.invalid'),
  ('0a000000-0000-4000-8000-00000000c0e1', 'gerente.bancos@teste.invalid');

insert into app.usuario_tenant (user_id, tenant_id, perfil) values
  ('0a000000-0000-4000-8000-00000000d0e1', '0e000000-0000-4000-8000-0000000000e1', 'diretor'),
  ('0a000000-0000-4000-8000-00000000c0e1', '0e000000-0000-4000-8000-0000000000e1', 'gerente_obra');

insert into app.usuario_centro_custo (user_id, tenant_id, centro_custo_id) values
  ('0a000000-0000-4000-8000-00000000c0e1', '0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1');

-- Obra A: 106 é distrato; o resto está ativo. Obra B: um contrato só.
insert into staging.contrato_venda (tenant_id, centro_custo_id, id_origem, numero, data_venda, valor, situacao, data_distrato) values
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1', 101, 'A-1', '2025-12-01', 150000, '1', null),
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1', 102, 'A-2', '2025-12-01', 250000, '1', null),
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1', 103, 'A-3', '2025-12-01', 350000, '1', null),
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1', 104, 'A-4', '2025-12-01', 450000, '1', null),
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1', 105, 'A-5', '2025-12-01', 60000, '1', null),
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1', 106, 'A-6', '2025-12-01', 90000, '3', '2026-02-01'),
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1', 107, 'A-7', '2025-12-01', 80000, '1', null),
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e2', 201, 'B-1', '2025-12-01', 600000, '1', null);

-- Só a FI do 101 venceu em aberto: ele é o atrasado.
insert into staging.parcela_receber (tenant_id, centro_custo_id, id_origem, contrato_id_origem, vencimento, valor_original, saldo, tipo_condicao) values
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1', 1, 101, '2020-01-01', 100000, 100000, 'FI'),
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1', 1, 102, '2999-01-01', 200000, 200000, 'FI'),
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1', 1, 104, '2999-01-01', 400000, 400000, 'FI'),
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e2', 1, 201, '2999-01-01', 500000, 500000, 'FI');

-- Caixa: 101 assinado e atrasado, 102 liberado em 20 dias. Banco Lento: 103 liberado em 60 dias e 104
-- parado em análise há 90 dias (o repasse 4, mais antigo, era da Caixa e não vale mais). 105 e 107 sem
-- banco informado. 106 é distrato e fica fora. Obra B só tem o Banco B.
insert into staging.repasse
  (tenant_id, centro_custo_id, id_origem, contrato_id_origem, situacao, banco, data_assinatura, data_recurso_liberado,
   valor_financiado, data_alteracao_situacao) values
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1', 1, 101, 'Assinado', 'Caixa', '2026-01-10', null, 100000, '2026-01-10'),
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1', 2, 102, 'Liberado', 'Caixa', '2026-01-01', '2026-01-21', 200000, '2026-01-21'),
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1', 3, 103, 'Liberado', 'Banco Lento', '2026-01-01', '2026-03-02', 300000, '2026-03-02'),
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1', 4, 104, 'Cancelado', 'Caixa', null, null, 1, '2025-12-05'),
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1', 5, 104, 'Análise', 'Banco Lento', null, null, 400000, current_date - 90),
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1', 6, 105, 'Análise', null, null, null, 50000, current_date - 10),
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1', 7, 106, 'Análise', 'Caixa', null, null, 999, current_date - 200),
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1', 8, 107, 'Análise', '  ', null, null, 70000, null),
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e2', 9, 201, 'Análise', 'Banco B', null, null, 500000, current_date - 5),
  ('0e000000-0000-4000-8000-0000000000e2', '0c000000-0000-4000-8000-0000000000e3', 1, null, 'Análise', 'Caixa', null, null, 999999, current_date - 5);

-- Site/Google na obra A: 5 em atendimento, 6 descartados no período (empate de 3 a 3 entre Preço e
-- Localização) e 1 descartado fora da janela de 12 meses. Stand: 2 perdidos sem motivo.
insert into staging.lead_diario (tenant_id, centro_custo_id, dia, origem, midia, situacao, motivo_cancelamento, leads) values
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1', current_date - 10, 'Site', 'Google', 'Em atendimento', 'Sem cancelamento', 5),
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1', current_date - 20, 'Site', 'Google', 'Descartado', 'Preço', 3),
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1', current_date - 30, 'Site', 'Google', 'Descartado', 'Localização', 3),
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1', current_date - 400, 'Site', 'Google', 'Descartado', 'Preço', 1),
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1', current_date - 15, 'Stand', 'Não informada', 'Perdido', 'Sem cancelamento', 2),
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e1', current_date - 15, 'Stand', 'Não informada', 'Em atendimento', 'Sem cancelamento', 4),
  ('0e000000-0000-4000-8000-0000000000e1', '0c000000-0000-4000-8000-0000000000e2', current_date - 10, 'Site', 'Google', 'Em atendimento', 'Sem cancelamento', 7);

select results_eq(
  $$select banco, contratos_com_repasse::integer, repasses_em_analise::integer, valor_em_analise,
      repasses_assinados::integer, valor_assinado, repasses_liberados::integer, valor_liberado,
      repasses_atrasados::integer, valor_atrasado
    from marts.repasse_banco where centro_custo_id = '0c000000-0000-4000-8000-0000000000e1' order by banco$$,
  $$values ('Banco Lento', 2, 1, 400000::numeric, 0, 0::numeric, 1, 300000::numeric, 0, 0::numeric),
           ('Caixa', 2, 0, 0::numeric, 1, 100000::numeric, 1, 200000::numeric, 1, 100000::numeric),
           ('Não informado', 2, 2, 120000::numeric, 0, 0::numeric, 0, 0::numeric, 0, 0::numeric)$$,
  'obra A por banco: repasse antigo e distrato fora, banco vazio vira Não informado'
);
select results_eq(
  $$select banco, dias_medios_assinatura_liberacao, repasses_parados_analise::integer, valor_parado_analise
    from marts.repasse_banco where centro_custo_id = '0c000000-0000-4000-8000-0000000000e1' order by banco$$,
  $$values ('Banco Lento', 60.0, 1, 400000::numeric), ('Caixa', 20.0, 0, 0::numeric), ('Não informado', null, 0, 0::numeric)$$,
  'prazo médio por banco e parado em análise só com mais de 60 dias sem mudança de situação'
);
select results_eq(
  $$select b.centro_custo_id, sum(b.contratos_com_repasse)::integer, sum(b.repasses_em_analise)::integer, sum(b.valor_em_analise),
      sum(b.repasses_assinados)::integer, sum(b.valor_assinado), sum(b.repasses_liberados)::integer, sum(b.valor_liberado),
      sum(b.repasses_atrasados)::integer, sum(b.valor_atrasado)
    from marts.repasse_banco b
    where b.tenant_id = '0e000000-0000-4000-8000-0000000000e1' group by 1 order by 1$$,
  $$select centro_custo_id, contratos_com_repasse::integer, repasses_em_analise::integer, valor_em_analise,
      repasses_assinados::integer, valor_assinado, repasses_liberados::integer, valor_liberado,
      repasses_atrasados::integer, valor_atrasado
    from marts.repasse_obra where tenant_id = '0e000000-0000-4000-8000-0000000000e1' order by 1$$,
  'a soma dos bancos fecha com marts.repasse_obra em cada obra'
);
select is(
  (select round(sum(b.dias_medios_assinatura_liberacao * b.repasses_liberados) / sum(b.repasses_liberados), 1)
   from marts.repasse_banco b
   where b.centro_custo_id = '0c000000-0000-4000-8000-0000000000e1' and b.dias_medios_assinatura_liberacao is not null),
  (select dias_medios_assinatura_liberacao from marts.repasse_obra where centro_custo_id = '0c000000-0000-4000-8000-0000000000e1'),
  'média dos bancos ponderada pelos liberados dá o prazo da obra'
);

select results_eq(
  $$select origem, midia, leads, leads_descartados, pct_descartados, motivo_principal_descarte, leads_motivo_principal
    from marts.leads_origem where centro_custo_id = '0c000000-0000-4000-8000-0000000000e1' order by leads desc$$,
  $$values ('Site', 'Google', 11, 6, 0.5455, 'Localização', 3), ('Stand', 'Não informada', 6, 2, 0.3333, null, null)$$,
  'leads por origem: janela de 12 meses, empate de motivo em ordem alfabética, perdido sem motivo conta como descartado'
);
select is(
  (select sum(leads)::integer from marts.leads_origem where tenant_id = '0e000000-0000-4000-8000-0000000000e1'),
  24,
  'lead fora da janela não entra no total'
);

select is(
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'marts' and c.relname in ('repasse_banco', 'leads_origem')
     and 'security_invoker=true' = any(c.reloptions)),
  2::bigint,
  'as duas views respeitam o RLS de quem consulta'
);
select ok(
  has_table_privilege('authenticated', 'marts.repasse_banco', 'select')
  and has_table_privilege('authenticated', 'marts.leads_origem', 'select'),
  'usuário logado consulta as duas views'
);
select is_empty(
  $$select table_name || '.' || column_name from information_schema.columns
    where (table_schema, table_name) in (('marts', 'repasse_banco'), ('marts', 'leads_origem'))
      and column_name ~ '(^|_)(nome|cliente|email|telefone|documento|cpf|cnpj|renda|score|corretor|usuario|agencia|conta)(_|$)'$$,
  'views novas não têm coluna de dado pessoal nem bancário do comprador'
);
select has_index('staging', 'parcela_receber', 'parcela_receber_repasse_idx', 'índice da parcela de financiamento por contrato');

-- Diretor do tenant
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-00000000d0e1", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;

select results_eq(
  'select distinct centro_custo_id from marts.repasse_banco order by 1',
  $$values ('0c000000-0000-4000-8000-0000000000e1'::uuid), ('0c000000-0000-4000-8000-0000000000e2'::uuid)$$,
  'diretor vê os bancos das duas obras e nada do outro tenant'
);
select is((select count(*) from marts.leads_origem), 3::bigint, 'diretor vê os leads das duas obras do tenant');

-- Gerente da obra A
reset role;
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-00000000c0e1", "role": "authenticated"}', true);
set local role authenticated;

select results_eq(
  'select distinct centro_custo_id from marts.repasse_banco',
  $$values ('0c000000-0000-4000-8000-0000000000e1'::uuid)$$,
  'gerente vê o repasse por banco só da obra dele'
);
select is(
  (select count(*) from marts.repasse_banco where banco = 'Banco B'),
  0::bigint,
  'gerente da obra A não vê o banco que só aparece na obra B'
);
select results_eq(
  'select distinct centro_custo_id from marts.leads_origem',
  $$values ('0c000000-0000-4000-8000-0000000000e1'::uuid)$$,
  'gerente vê leads por origem só da obra dele'
);
select is(
  (select sum(valor_em_analise) from marts.repasse_banco),
  520000::numeric,
  'a soma que o gerente vê não carrega valor de outra obra nem de outro tenant'
);

select * from finish();
rollback;
