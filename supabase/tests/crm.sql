-- CRM como segunda origem com caso conhecido: versão mais nova do registro vence, registro apagado
-- no CRM some, reserva e repasse ligam ao contrato do ERP pelo vínculo, pelo código interno ou pelo
-- número, e o gerente só vê a obra dele. Cria os próprios dados para não depender do seed.
begin;
create extension if not exists pgtap with schema extensions;
select plan(29);

insert into app.tenant (id, razao_social) values
  ('0e000000-0000-4000-8000-0000000000d1', 'Construtora CRM'),
  ('0e000000-0000-4000-8000-0000000000d2', 'Construtora CRM vizinha');

insert into app.centro_custo (id, tenant_id, id_origem, nome) values
  ('0c000000-0000-4000-8000-0000000000d1', '0e000000-0000-4000-8000-0000000000d1', 971, 'Obra CRM A'),
  ('0c000000-0000-4000-8000-0000000000d2', '0e000000-0000-4000-8000-0000000000d1', 972, 'Obra CRM B'),
  ('0c000000-0000-4000-8000-0000000000d3', '0e000000-0000-4000-8000-0000000000d2', 971, 'Obra vizinha');

insert into auth.users (id, email) values
  ('0a000000-0000-4000-8000-00000000d0d1', 'diretor.crm@teste.invalid'),
  ('0a000000-0000-4000-8000-00000000c0d1', 'gerente.crm@teste.invalid');

insert into app.usuario_tenant (user_id, tenant_id, perfil) values
  ('0a000000-0000-4000-8000-00000000d0d1', '0e000000-0000-4000-8000-0000000000d1', 'diretor'),
  ('0a000000-0000-4000-8000-00000000c0d1', '0e000000-0000-4000-8000-0000000000d1', 'gerente_obra');

insert into app.usuario_centro_custo (user_id, tenant_id, centro_custo_id) values
  ('0a000000-0000-4000-8000-00000000c0d1', '0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1');

-- ERP: quatro contratos na obra A (um distratado, um sem repasse no CRM) e um na obra B.
insert into staging.unidade (tenant_id, centro_custo_id, id_origem, nome, situacao) values
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1', 1, 'A-101', 'V'),
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1', 2, 'A-102', 'V'),
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1', 3, 'A-103', 'D'),
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1', 4, 'A-104', 'V'),
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1', 5, 'A-105', 'C'),
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d2', 11, 'B-101', 'V'),
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d2', 12, 'B-102', 'V');

insert into staging.contrato_venda (tenant_id, centro_custo_id, id_origem, numero, data_venda, valor, situacao, data_distrato, unidade_id_origem) values
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1', 101, 'A-1', '2026-01-10', 300000, '1', null, 1),
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1', 102, 'A-2', '2026-01-20', 200000, '1', null, 2),
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1', 103, 'A-3', '2026-02-05', 250000, '3', '2026-03-15', 3),
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1', 104, 'A-4', '2026-02-10', 400000, '1', null, 4),
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d2', 201, 'B-1', '2026-01-15', 500000, '1', null, 11),
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d2', 202, 'B-2', '2026-04-10', 600000, '1', null, 12);

-- FI de 101 e 102 vencida e em aberto, de 104 e 201 a vencer; a de 103 é de distrato e não conta.
insert into staging.parcela_receber (tenant_id, centro_custo_id, id_origem, contrato_id_origem, vencimento, valor_original, saldo, tipo_condicao) values
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1', 1, 101, '2020-01-01', 180000, 180000, 'FI'),
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1', 2, 101, '2999-01-01', 5000, 5000, 'PM'),
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1', 1, 102, '2020-06-01', 120000, 120000, 'FI'),
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1', 1, 103, '2999-01-01', 150000, 150000, 'FI'),
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1', 1, 104, '2999-01-01', 240000, 240000, 'FI'),
  ('0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d2', 1, 201, '2999-01-01', 300000, 300000, 'FI');

-- CRM no raw, já sem dado pessoal. O hash só precisa ser único por tenant e endpoint.
insert into raw.registro (tenant_id, endpoint, payload, hash_registro)
select '0e000000-0000-4000-8000-0000000000d1', endpoint, payload::jsonb, md5(endpoint || payload)
from (values
  ('crm/reservas', '{"idreserva": 11, "referencia_data": "2026-01-10 09:00:00", "ativo": "S", "codigointerno_empreendimento": "971", "unidade": "A-101", "situacao": "Vendida", "venda": "Sim", "data_cad": "2026-01-05 10:00:00", "data_venda": "2026-01-10 09:00:00", "valor_contrato": 300000}'),
  ('crm/reservas', '{"idreserva": 12, "referencia_data": "2026-01-20 09:00:00", "ativo": "S", "codigointerno_empreendimento": "971", "codigointerno": "102", "unidade": "A-102", "situacao": "Vendida", "venda": "Sim", "data_cad": "2026-01-12", "data_venda": "2026-01-20", "valor_contrato": "200000.00"}'),
  ('crm/reservas', '{"idreserva": 13, "referencia_data": "2026-03-15 09:00:00", "ativo": "S", "codigointerno_empreendimento": "971", "codigointerno": "103", "unidade": "A-103", "situacao": "Distrato", "venda": "Sim", "data_cad": "2026-02-01", "data_venda": "2026-02-05", "data_cancelamento": "2026-03-15"}'),
  ('crm/reservas', '{"idreserva": 14, "referencia_data": "2026-01-25 09:00:00", "ativo": "S", "codigointerno_empreendimento": "971", "unidade": "A-105", "situacao": "Em análise", "venda": "Não", "data_cad": "2026-01-25", "data_venda": "0000-00-00"}'),
  ('crm/reservas', '{"idreserva": 15, "referencia_data": "2026-02-02 09:00:00", "ativo": "S", "codigointerno_empreendimento": "971", "unidade": "A-104", "situacao": "Cancelada", "venda": "Não", "data_cad": "2026-01-28", "data_cancelamento": "2026-02-02"}'),
  ('crm/reservas', '{"idreserva": 21, "referencia_data": "2026-01-15 09:00:00", "ativo": "S", "codigointerno_empreendimento": "972", "codigointerno": "201", "unidade": "B-101", "situacao": "Vendida", "venda": "Sim", "data_cad": "2026-01-08", "data_venda": "2026-01-15"}'),
  -- Empreendimento do CRM aponta a obra A, mas o contrato 202 é da obra B no ERP: vale o ERP.
  ('crm/reservas', '{"idreserva": 22, "referencia_data": "2026-04-10 09:00:00", "ativo": "S", "codigointerno_empreendimento": "971", "codigointerno": "202", "unidade": "B-102", "situacao": "Vendida", "venda": "Sim", "data_cad": "2026-04-01", "data_venda": "2026-04-10", "valor_contrato": 600000}'),
  ('crm/repasses', '{"idrepasse": 7, "referencia_data": "2026-04-20 10:00:00", "ativo": "S", "reserva": 22, "codigointerno_empreendimento": "971", "situacao": "Recurso liberado", "valor_financiado": 480000, "data_assinatura_de_contrato": "2026-04-12", "data_recurso_liberado": "2026-04-20"}'),
  ('crm/reservas/vinculo_erp', '{"idreserva": 11, "referencia_data": "2026-01-10 09:00:00", "ativo": "S", "codigointerno": "101"}'),
  ('crm/repasses', '{"idrepasse": 1, "referencia_data": "2026-01-01 10:00:00", "ativo": "S", "reserva": 11, "codigointerno_empreendimento": "971", "situacao": "Análise", "valor_financiado": 180000}'),
  ('crm/repasses', '{"idrepasse": 1, "referencia_data": "2026-03-01 10:00:00", "ativo": "S", "reserva": 11, "codigointerno_empreendimento": "971", "situacao": "Recurso liberado", "banco": "Banco Teste", "valor_financiado": 180000, "data_assinatura_de_contrato": "2026-02-01", "data_recurso_liberado": "2026-02-21", "data_alteracao_status": "2026-02-21 11:00:00"}'),
  ('crm/repasses', '{"idrepasse": 2, "referencia_data": "2026-02-10 10:00:00", "ativo": "S", "numero_contrato": "A-2", "codigointerno_empreendimento": "971", "situacao": "Assinado", "valor_financiado": "120000.00", "data_assinatura_de_contrato": "2026-02-10"}'),
  ('crm/repasses', '{"idrepasse": 3, "referencia_data": "2026-02-10 10:00:00", "ativo": "S", "reserva": 13, "codigointerno_empreendimento": "971", "situacao": "Análise", "valor_financiado": 150000}'),
  ('crm/repasses', '{"idrepasse": 4, "referencia_data": "2026-02-10 10:00:00", "ativo": "N", "reserva": 12, "codigointerno_empreendimento": "971", "situacao": "Análise", "valor_financiado": 1}'),
  ('crm/repasses', '{"idrepasse": 5, "referencia_data": "2026-02-10 10:00:00", "ativo": "S", "reserva": 21, "codigointerno_empreendimento": "972", "situacao": "Análise", "valor_previsto": 300000}'),
  ('crm/repasses', '{"idrepasse": 6, "referencia_data": "2026-02-10 10:00:00", "ativo": "S", "codigointerno_empreendimento": "XYZ", "situacao": "Análise", "valor_financiado": 1}'),
  ('crm/leads', '{"idlead": 1, "referencia_data": "2026-01-03 10:00:00", "ativo": "S", "codigointerno_empreendimento": "971", "data_cad": "2026-01-03 10:00:00", "origem_nome": "Site", "midia_original": "Google", "situacao": "Em atendimento"}'),
  ('crm/leads', '{"idlead": 2, "referencia_data": "2026-01-04 10:00:00", "ativo": "S", "codigointerno_empreendimento": "971;972", "data_cad": "2026-01-04", "origem_nome": "Site", "midia_original": "Google", "situacao": "Em atendimento"}'),
  ('crm/leads', '{"idlead": 3, "referencia_data": "2026-01-05 10:00:00", "ativo": "S", "codigointerno_empreendimento": "971", "data_cad": "2026-01-05", "origem_nome": "Stand", "situacao": "Em atendimento"}'),
  ('crm/leads', '{"idlead": 3, "referencia_data": "2026-01-20 10:00:00", "ativo": "S", "codigointerno_empreendimento": "971", "data_cad": "2026-01-05", "origem_nome": "Stand", "situacao": "Descartado", "motivo_cancelamento": "Preço"}'),
  ('crm/leads', '{"idlead": 4, "referencia_data": "2026-02-10 10:00:00", "ativo": "S", "codigointerno_empreendimento": "971", "data_cad": "2026-02-10", "origem_nome": "Site", "situacao": "Em atendimento"}'),
  ('crm/leads', '{"idlead": 5, "referencia_data": "2026-01-06 10:00:00", "ativo": "N", "codigointerno_empreendimento": "971", "data_cad": "2026-01-06", "situacao": "Em atendimento"}')
) as registros (endpoint, payload);

-- Linha de outro tenant, para provar que a recarga e a leitura não cruzam tenant.
insert into staging.repasse (tenant_id, centro_custo_id, id_origem, situacao, valor_financiado) values
  ('0e000000-0000-4000-8000-0000000000d2', '0c000000-0000-4000-8000-0000000000d3', 1, 'Análise', 999999);

select ok(
  staging.numero_crm(repeat('9', 140000)) is null and staging.numero_crm('1.5') = 1.5,
  'número gigante vira nulo em vez de derrubar a recarga'
);

select staging.recarregar_crm('0e000000-0000-4000-8000-0000000000d1');

select results_eq(
  $$select id_origem from staging.repasse where tenant_id = '0e000000-0000-4000-8000-0000000000d1' order by 1$$,
  $$values (1), (2), (3), (5), (7)$$,
  'repasse apagado no CRM e repasse sem obra ficam fora'
);
select is(
  (select row(contrato_id_origem, unidade_id_origem, data_recurso_liberado, banco)::text from staging.repasse
   where tenant_id = '0e000000-0000-4000-8000-0000000000d1' and id_origem = 1),
  '(101,1,2026-02-21,"Banco Teste")',
  'versão mais nova do repasse vence e o contrato vem do vínculo da reserva com o ERP'
);
select is(
  (select contrato_id_origem from staging.repasse where tenant_id = '0e000000-0000-4000-8000-0000000000d1' and id_origem = 2),
  102,
  'repasse sem reserva liga ao contrato pelo número'
);
select is(
  (select row(contrato_id_origem, unidade_id_origem, vendida, data_venda)::text from staging.reserva
   where tenant_id = '0e000000-0000-4000-8000-0000000000d1' and id_origem = 14),
  '(,5,f,)',
  'reserva em andamento acha a unidade pelo nome e data zerada vira nula'
);
select is(
  (select row(centro_custo_id, contrato_id_origem, unidade_id_origem)::text from staging.reserva
   where tenant_id = '0e000000-0000-4000-8000-0000000000d1' and id_origem = 22),
  '(0c000000-0000-4000-8000-0000000000d2,202,12)',
  'reserva com empreendimento divergente fica na obra do contrato no ERP'
);
select is(
  (select row(centro_custo_id, contrato_id_origem)::text from staging.repasse
   where tenant_id = '0e000000-0000-4000-8000-0000000000d1' and id_origem = 7),
  '(0c000000-0000-4000-8000-0000000000d2,202)',
  'repasse com empreendimento divergente fica na obra do contrato no ERP'
);
select is(
  (select row(contrato_id_origem, valor_contrato)::text from staging.reserva
   where tenant_id = '0e000000-0000-4000-8000-0000000000d1' and id_origem = 12),
  '(102,200000.00)',
  'reserva sem vínculo liga pelo código interno e valor em texto vira número'
);
select results_eq(
  $$select centro_custo_id, sum(leads)::integer from staging.lead_diario
    where tenant_id = '0e000000-0000-4000-8000-0000000000d1' group by 1 order by 1$$,
  $$values ('0c000000-0000-4000-8000-0000000000d1'::uuid, 4), ('0c000000-0000-4000-8000-0000000000d2'::uuid, 1)$$,
  'lead com duas obras conta nas duas; lead apagado fica fora'
);
select is(
  (select row(situacao, motivo_cancelamento, leads)::text from staging.lead_diario
   where tenant_id = '0e000000-0000-4000-8000-0000000000d1' and origem = 'Stand'),
  '(Descartado,Preço,1)',
  'lead com duas versões conta uma vez, pela mais nova'
);

select staging.recarregar_crm('0e000000-0000-4000-8000-0000000000d1');
-- Só os dois tenants do teste: o banco local pode ter a carga da demo em outro tenant.
select results_eq(
  $$select tenant_id, count(*)::integer, sum(valor_financiado) filter (where valor_financiado = 999999)::integer
    from staging.repasse
    where tenant_id in ('0e000000-0000-4000-8000-0000000000d1', '0e000000-0000-4000-8000-0000000000d2')
    group by 1 order by 1$$,
  $$values ('0e000000-0000-4000-8000-0000000000d1'::uuid, 5, null::integer),
           ('0e000000-0000-4000-8000-0000000000d2'::uuid, 1, 999999)$$,
  'recarregar de novo não duplica e não apaga o outro tenant'
);

select is(
  (select row(contratos_financiados_origem, contratos_com_repasse, contratos_sem_repasse, repasses_em_analise,
              repasses_assinados, repasses_liberados, repasses_atrasados)::text
   from marts.repasse_obra where centro_custo_id = '0c000000-0000-4000-8000-0000000000d1'),
  '(3,2,1,0,1,1,1)',
  'obra A: distrato fora, um assinado atrasado, um liberado e um contrato sem repasse no CRM'
);
select is(
  (select row(valor_assinado, valor_liberado, valor_atrasado, dias_medios_assinatura_liberacao)::text
   from marts.repasse_obra where centro_custo_id = '0c000000-0000-4000-8000-0000000000d1'),
  '(120000.00,180000,120000.00,20.0)',
  'obra A: valores por etapa e vinte dias da assinatura ao recurso'
);
select is(
  (select row(a_receber_repasse_origem, repasse_atrasado_origem, liberado_sem_baixa_origem)::text
   from marts.repasse_obra where centro_custo_id = '0c000000-0000-4000-8000-0000000000d1'),
  '(240000,300000,180000)',
  'obra A: FI em aberto no ERP e recurso liberado no CRM ainda sem baixa no ERP'
);
select is(
  (select row(repasses_em_analise, valor_em_analise, a_receber_repasse_origem)::text
   from marts.repasse_obra where centro_custo_id = '0c000000-0000-4000-8000-0000000000d2'),
  '(1,300000,300000)',
  'obra B: repasse em análise pelo valor previsto quando falta o financiado'
);

select is(
  (select row(leads, reservas, reservas_canceladas, vendas, distratos, conversao_lead_reserva, conversao_reserva_venda)::text
   from marts.funil_vendas_mensal
   where centro_custo_id = '0c000000-0000-4000-8000-0000000000d1' and competencia = '2026-01-01'),
  '(3,4,0,2,0,1.3333,0.5000)',
  'funil da obra A em janeiro'
);
select is(
  (select row(leads, reservas, reservas_canceladas, vendas, distratos)::text
   from marts.funil_vendas_mensal
   where centro_custo_id = '0c000000-0000-4000-8000-0000000000d1' and competencia = '2026-03-01'),
  '(0,0,1,0,1)',
  'mês sem lead aparece com zero e distrato cai no mês do cancelamento'
);

select is_empty(
  $$select table_name || '.' || column_name from information_schema.columns
    where (table_schema, table_name) in (('staging', 'repasse'), ('staging', 'reserva'), ('staging', 'lead_diario'),
                                         ('marts', 'repasse_obra'), ('marts', 'funil_vendas_mensal'))
      and column_name ~ '(^|_)(nome|cliente|email|telefone|documento|cpf|cnpj|renda|score|profissao|cidade|cep|nascimento|agencia|sexo|idade|estado_civil|corretor|usuario)(_|$)'$$,
  'tabelas e views novas não têm coluna de dado pessoal'
);
select is(
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'staging' and c.relname in ('repasse', 'reserva', 'lead_diario')
     and c.relrowsecurity and c.relforcerowsecurity),
  3::bigint,
  'RLS ligado e forçado nas três tabelas novas'
);
select is(
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'marts' and c.relname in ('repasse_obra', 'funil_vendas_mensal')
     and 'security_invoker=true' = any(c.reloptions)),
  2::bigint,
  'as duas views respeitam o RLS de quem consulta'
);
select ok(
  not has_function_privilege('authenticated', 'staging.recarregar_crm(uuid)', 'execute')
  and not has_function_privilege('anon', 'staging.recarregar_crm(uuid)', 'execute'),
  'usuário da API não executa a recarga'
);

-- Diretor do tenant
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-00000000d0d1", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;

select is((select count(*) from marts.repasse_obra), 2::bigint, 'diretor vê o repasse das duas obras');
select is((select count(*) from staging.repasse), 5::bigint, 'diretor não vê repasse de outro tenant');

-- Gerente da obra A
reset role;
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-00000000c0d1", "role": "authenticated"}', true);
set local role authenticated;

select results_eq(
  'select centro_custo_id from marts.repasse_obra',
  $$values ('0c000000-0000-4000-8000-0000000000d1'::uuid)$$,
  'gerente vê o repasse só da obra dela'
);
select results_eq(
  'select distinct centro_custo_id from staging.repasse',
  $$values ('0c000000-0000-4000-8000-0000000000d1'::uuid)$$,
  'gerente não vê repasse de outra obra'
);
select results_eq(
  'select distinct centro_custo_id from marts.funil_vendas_mensal',
  $$values ('0c000000-0000-4000-8000-0000000000d1'::uuid)$$,
  'gerente vê o funil só da obra dela'
);
select is(
  (select count(*) from staging.reserva where centro_custo_id <> '0c000000-0000-4000-8000-0000000000d1')
    + (select count(*) from staging.lead_diario where centro_custo_id <> '0c000000-0000-4000-8000-0000000000d1'),
  0::bigint,
  'gerente não vê reserva nem lead de outra obra'
);
select is(
  (select count(*) from staging.reserva where contrato_id_origem = 202)
    + (select count(*) from staging.repasse where contrato_id_origem = 202),
  0::bigint,
  'gerente da obra A não recebe o contrato da obra B marcado com o empreendimento dela no CRM'
);
select throws_ok(
  $$select staging.recarregar_crm('0e000000-0000-4000-8000-0000000000d1')$$,
  '42501',
  null,
  'gerente não consegue recarregar o CRM'
);

select * from finish();
rollback;
