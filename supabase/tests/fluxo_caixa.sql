-- Fluxo de caixa por evento com casos conhecidos: parcela quitada em dois recebimentos, título pago em
-- duas vezes, título rateado 60/40 entre obras, título sem obra e cenário de atraso do repasse.
-- Os dados entram por raw.registro e passam por staging.recarregar, como na carga real.
begin;
create extension if not exists pgtap with schema extensions;
select plan(19);

insert into app.tenant (id, razao_social) values
  ('0e000000-0000-4000-8000-0000000000f1', 'Construtora Fluxo');

insert into app.centro_custo (id, tenant_id, id_origem, nome) values
  ('0c000000-0000-4000-8000-0000000000f1', '0e000000-0000-4000-8000-0000000000f1', 961, 'Obra Norte'),
  ('0c000000-0000-4000-8000-0000000000f2', '0e000000-0000-4000-8000-0000000000f1', 962, 'Obra Sul');

-- mes_futuro: dois meses à frente, para a parcela e o título do cenário ficarem sempre como previstos.
create temporary table referencia on commit drop as
select (date_trunc('month', current_date) + interval '2 months')::date as mes_futuro;
grant select on referencia to authenticated;

insert into raw.registro (tenant_id, endpoint, payload, hash_registro)
select '0e000000-0000-4000-8000-0000000000f1', endpoint, payload, md5(payload::text)
from referencia, lateral (values
  ('income', jsonb_build_object(
     'projectId', 961, 'billId', 1, 'installmentId', 1, 'dueDate', '2026-01-10',
     'originalAmount', 1000, 'balanceAmount', 0, 'correctedBalanceAmount', 0,
     'paymentTerm', jsonb_build_object('id', 'PM'), 'defaulterSituation', 'N',
     'receipts', '[{"paymentDate": "2026-02-05", "amount": 400}, {"paymentDate": "2026-03-05", "amount": 600}]'::jsonb)),
  ('income', jsonb_build_object(
     'projectId', 961, 'billId', 2, 'installmentId', 1, 'dueDate', mes_futuro + 9,
     'originalAmount', 100, 'balanceAmount', 100, 'correctedBalanceAmount', 100,
     'paymentTerm', jsonb_build_object('id', 'PM'), 'defaulterSituation', 'N', 'receipts', '[]'::jsonb)),
  ('income', jsonb_build_object(
     'projectId', 961, 'billId', 2, 'installmentId', 2, 'dueDate', mes_futuro + 9,
     'originalAmount', 200, 'balanceAmount', 200, 'correctedBalanceAmount', 200,
     'paymentTerm', jsonb_build_object('id', 'FI'), 'defaulterSituation', 'N', 'receipts', '[]'::jsonb)),
  ('outcome', jsonb_build_object(
     'billId', 10, 'creditorName', 'Fornecedor Rateado', 'dueDate', '2026-04-10',
     'originalAmount', 1000, 'balanceAmount', 0,
     'buildingsCosts', '[{"buildingId": 961, "amount": 600}, {"buildingId": 962, "amount": 400}]'::jsonb,
     'payments', '[{"paymentDate": "2026-04-10", "amount": 1000}]'::jsonb)),
  ('outcome', jsonb_build_object(
     'billId', 11, 'creditorName', 'Fornecedor Parcelado', 'dueDate', '2026-06-20',
     'originalAmount', 500, 'balanceAmount', 0,
     'buildingsCosts', '[{"buildingId": 962, "amount": 500}]'::jsonb,
     'payments', '[{"paymentDate": "2026-06-20", "amount": 200}, {"paymentDate": "2026-07-20", "amount": 300}]'::jsonb)),
  ('outcome', jsonb_build_object(
     'billId', 12, 'creditorName', 'Escritorio da Empresa', 'dueDate', '2026-04-15',
     'originalAmount', 800, 'balanceAmount', 0, 'buildingsCosts', '[]'::jsonb,
     'payments', '[{"paymentDate": "2026-04-15", "amount": 800}]'::jsonb)),
  ('outcome', jsonb_build_object(
     'billId', 13, 'creditorName', 'Fornecedor Futuro', 'dueDate', mes_futuro + 14,
     'originalAmount', 150, 'balanceAmount', 150,
     'buildingsCosts', '[{"buildingId": 961, "amount": 150}]'::jsonb, 'payments', '[]'::jsonb)),
  ('outcome', jsonb_build_object(
     'billId', 14, 'creditorName', 'Registro Torto', 'dueDate', '2026-05-01',
     'originalAmount', 50, 'balanceAmount', 50, 'buildingsCosts', 'null'::jsonb, 'payments', 'null'::jsonb))
) as registros(endpoint, payload);

select staging.recarregar('0e000000-0000-4000-8000-0000000000f1');
-- a segunda recarga precisa deixar tudo igual
select staging.recarregar('0e000000-0000-4000-8000-0000000000f1');

select is(
  (select count(*) from staging.recebimento where tenant_id = '0e000000-0000-4000-8000-0000000000f1'),
  2::bigint,
  'recarga repetida não duplica recebimento'
);

select results_eq(
  $$select competencia, entrada_direta_realizada from marts.fluxo_caixa_mensal
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000f1' and entrada_direta_realizada <> 0
    order by competencia$$,
  $$values ('2026-02-01'::date, 400::numeric), ('2026-03-01'::date, 600::numeric)$$,
  'parcela quitada em dois recebimentos entra em fevereiro e em março'
);

select is(
  (select sum(entrada_direta_prevista + entrada_direta_vencida) from marts.fluxo_caixa_mensal
   where centro_custo_id = '0c000000-0000-4000-8000-0000000000f1' and competencia < (select mes_futuro from referencia)),
  0::numeric,
  'parcela quitada não aparece como prevista nem como vencida'
);

select is(
  (select row(valor_recebido, data_recebimento)::text from staging.parcela_receber
   where tenant_id = '0e000000-0000-4000-8000-0000000000f1' and contrato_id_origem = 1),
  '(1000,2026-03-05)',
  'parcela guarda a soma dos recebimentos e a data do último'
);

select results_eq(
  $$select c.entrada_direta, c.repasse, c.saida from marts.fluxo_caixa_cenario(1) c, referencia r
    where c.centro_custo_id = '0c000000-0000-4000-8000-0000000000f1' and c.competencia = r.mes_futuro$$,
  $$values (100::numeric, 0::numeric, 150::numeric)$$,
  'atraso de um mês tira só o repasse do mês original'
);

select results_eq(
  $$select c.entrada_direta, c.repasse, c.saida from marts.fluxo_caixa_cenario(1) c, referencia r
    where c.centro_custo_id = '0c000000-0000-4000-8000-0000000000f1'
      and c.competencia = (r.mes_futuro + interval '1 month')::date$$,
  $$values (0::numeric, 200::numeric, 0::numeric)$$,
  'o repasse de 200 aparece no mês seguinte'
);

select results_eq(
  $$select c.entrada_direta, c.repasse, c.saida from marts.fluxo_caixa_cenario(0) c, referencia r
    where c.centro_custo_id = '0c000000-0000-4000-8000-0000000000f1' and c.competencia = r.mes_futuro$$,
  $$values (100::numeric, 200::numeric, 150::numeric)$$,
  'sem atraso o mês fica com os três valores'
);

select results_eq(
  $$select centro_custo_id, saida_realizada from marts.fluxo_caixa_mensal
    where tenant_id = '0e000000-0000-4000-8000-0000000000f1' and competencia = '2026-04-01'
    order by saida_realizada desc$$,
  $$values ('0c000000-0000-4000-8000-0000000000f1'::uuid, 600::numeric),
           ('0c000000-0000-4000-8000-0000000000f2'::uuid, 400::numeric)$$,
  'título de 1.000 rateado 60/40 aparece como 600 e 400; título sem obra não entra'
);

select results_eq(
  $$select competencia, saida_realizada from marts.fluxo_caixa_mensal
    where centro_custo_id = '0c000000-0000-4000-8000-0000000000f2' and competencia in ('2026-06-01', '2026-07-01')
    order by competencia$$,
  $$values ('2026-06-01'::date, 200::numeric), ('2026-07-01'::date, 300::numeric)$$,
  'título pago em duas vezes entra no mês de cada pagamento'
);

select is(
  (select sum(saida_realizada) from marts.fluxo_caixa_mensal where tenant_id = '0e000000-0000-4000-8000-0000000000f1'),
  (select sum(p.valor) from staging.pagamento p
   where p.tenant_id = '0e000000-0000-4000-8000-0000000000f1'
     and exists (select 1 from staging.rateio_titulo rt
                 where rt.tenant_id = p.tenant_id and rt.titulo_id_origem = p.titulo_id_origem)),
  'saída realizada de todas as obras soma o que foi pago nos títulos com rateio'
);

select is(
  (select sum(valor) from staging.pagamento where tenant_id = '0e000000-0000-4000-8000-0000000000f1'),
  2300::numeric,
  'pagamento do título sem obra fica em staging, fora das obras'
);

select results_eq(
  $$select t.id_origem, t.centro_custo_id from staging.titulo_pagar t
    where t.tenant_id = '0e000000-0000-4000-8000-0000000000f1'
      and not exists (select 1 from staging.rateio_titulo rt
                      where rt.tenant_id = t.tenant_id and rt.titulo_id_origem = t.id_origem)
    order by t.id_origem$$,
  $$values (12, null::uuid), (14, null::uuid)$$,
  'título sem apropriação, inclusive com lista nula, fica sem obra'
);

select is(
  (select centro_custo_id from staging.titulo_pagar
   where tenant_id = '0e000000-0000-4000-8000-0000000000f1' and id_origem = 10),
  null::uuid,
  'título dividido entre obras não fica preso a uma obra só'
);

select results_eq(
  $$select p.centro_custo_id, p.recebido_direto + p.recebido_repasse, p.pago
    from marts.posicao_financeira_obra p
    where p.tenant_id = '0e000000-0000-4000-8000-0000000000f1' order by 1$$,
  $$select cc.id,
      coalesce((select sum(rc.valor) from staging.recebimento rc where rc.centro_custo_id = cc.id), 0),
      coalesce((select sum(pg.valor * rt.fracao) from staging.pagamento pg
                join staging.rateio_titulo rt on rt.tenant_id = pg.tenant_id and rt.titulo_id_origem = pg.titulo_id_origem
                where rt.centro_custo_id = cc.id), 0)
    from app.centro_custo cc where cc.tenant_id = '0e000000-0000-4000-8000-0000000000f1' order by 1$$,
  'posição da obra bate com a soma direta dos recebimentos e dos pagamentos rateados'
);

-- Gerente da Obra Sul: só enxerga a parte dela no rateio, e a fração continua certa.
insert into auth.users (id, email) values ('0a000000-0000-4000-8000-00000000f001', 'gerente.fluxo@teste.invalid');
insert into app.usuario_tenant (user_id, tenant_id, perfil) values
  ('0a000000-0000-4000-8000-00000000f001', '0e000000-0000-4000-8000-0000000000f1', 'gerente_obra');
insert into app.usuario_centro_custo (user_id, tenant_id, centro_custo_id) values
  ('0a000000-0000-4000-8000-00000000f001', '0e000000-0000-4000-8000-0000000000f1', '0c000000-0000-4000-8000-0000000000f2');

select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-00000000f001", "role": "authenticated"}', true);
set local role authenticated;

select results_eq(
  $$select centro_custo_id, saida_realizada from marts.fluxo_caixa_mensal where competencia = '2026-04-01'$$,
  $$values ('0c000000-0000-4000-8000-0000000000f2'::uuid, 400::numeric)$$,
  'gerente da Obra Sul vê 400 do título rateado, não o título inteiro'
);

select results_eq(
  'select id_origem from staging.titulo_pagar order by 1',
  $$values (10), (11)$$,
  'gerente vê só títulos com parte na obra dele; título sem obra fica oculto'
);

select is((select count(*) from staging.recebimento), 0::bigint, 'gerente da Obra Sul não vê recebimento da Obra Norte');

select is(
  (select count(*) from staging.pagamento where titulo_id_origem = 12),
  0::bigint,
  'gerente não vê pagamento de título sem obra'
);

select is(
  (select count(*) from staging.rateio_titulo where centro_custo_id <> '0c000000-0000-4000-8000-0000000000f2'),
  0::bigint,
  'gerente não vê a parte da outra obra no rateio'
);

select * from finish();
rollback;
