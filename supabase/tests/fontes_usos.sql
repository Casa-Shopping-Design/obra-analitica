-- Fontes e Usos, DRE societária e custo incorrido (migrations 0036 a 0038) com uma contabilidade inventada
-- que fecha em partida dobrada. A Alfa SPE (empresa 11) tem dois meses:
--   jan/2025: aporte de 1000; terreno a prazo 300; materiais a prazo 200; salários 100 e encargos 20 pagos;
--     transferência de 620 do custo ao estoque; venda de 800 com 500 recebidos; CMV 400; despesa adm 50 paga;
--     mútuo de 40 recebido numa conta de ativo (fica credora). Lucro 350, zerado contra a apuração e levado
--     a lucros acumulados; grupo 5 zerado contra a conta de transferência.
--   fev/2025: ajuste de exercícios anteriores de 7 (impostos a recuperar contra conta de PL que herda a linha
--     da sintética 2.3.2); 5 pagos numa conta sem mapa; venda de 100 a prazo; despesa adm 30 paga. Lucro 70.
--   mar/2025 chega só com uma passagem e não entra.
-- O raw das duas passagens do balancete é gerado a partir desse razão, como o carregador gravaria.
begin;
create extension if not exists pgtap with schema extensions;
select plan(63);

insert into app.tenant (id, razao_social) values
  ('0e000000-0000-4000-8000-0000000000f1', 'Construtora Fontes e Usos'),
  ('0e000000-0000-4000-8000-0000000000f2', 'Construtora Fontes e Usos vizinha');

insert into app.centro_custo (id, tenant_id, id_origem, nome) values
  ('0c000000-0000-4000-8000-0000000000f1', '0e000000-0000-4000-8000-0000000000f1', 951, 'Obra Alfa'),
  ('0c000000-0000-4000-8000-0000000000f2', '0e000000-0000-4000-8000-0000000000f2', 951, 'Obra vizinha');

insert into auth.users (id, email) values
  ('0a000000-0000-4000-8000-00000000d0f1', 'diretor.fu@teste.invalid'),
  ('0a000000-0000-4000-8000-00000000d0f2', 'diretor.fu.vizinho@teste.invalid');

insert into app.usuario_tenant (user_id, tenant_id, perfil) values
  ('0a000000-0000-4000-8000-00000000d0f1', '0e000000-0000-4000-8000-0000000000f1', 'diretor'),
  ('0a000000-0000-4000-8000-00000000d0f2', '0e000000-0000-4000-8000-0000000000f2', 'diretor');

insert into raw.registro (tenant_id, endpoint, payload, hash_registro) values
  ('0e000000-0000-4000-8000-0000000000f1', 'companies',
   '{"id": 11, "name": "Alfa Empreendimentos SPE Ltda", "tradeName": "Alfa", "cnpj": "00.000.000/0001-00"}', 'empresa-11'),
  ('0e000000-0000-4000-8000-0000000000f1', 'cost-centers',
   '{"id": 951, "name": "Obra Alfa", "idCompany": 11}', 'obra-951'),
  ('0e000000-0000-4000-8000-0000000000f2', 'companies',
   '{"id": 11, "name": "Vizinha SPE Ltda", "tradeName": "Vizinha"}', 'empresa-11');

create temporary table plano (conta text, reduzida integer, nome text, tipo text, grupo text) on commit drop;
insert into plano values
  ('1', 1, 'Ativo', 'SYNTHETIC', 'ASSETS'),
  ('1.1.1.01.0001', 101, 'Banco Conta Movimento', 'ANALYTICAL', 'ASSETS'),
  ('1.1.2.01.0001', 102, 'Clientes Incorporação', 'ANALYTICAL', 'ASSETS'),
  ('1.1.3.01.0001', 103, 'Imóveis em Construção', 'ANALYTICAL', 'ASSETS'),
  ('1.1.4.01.0001', 104, 'Impostos a Recuperar', 'ANALYTICAL', 'ASSETS'),
  ('1.1.5.01.0001', 105, 'Adiantamentos a Terceiros', 'ANALYTICAL', 'ASSETS'),
  ('1.2.1.01.0001', 121, 'Mútuo com Sócios', 'ANALYTICAL', 'ASSETS'),
  ('2.1.1.01.0001', 201, 'Fornecedores Nacionais', 'ANALYTICAL', 'LIABILITIES'),
  ('2.1.2.01.0001', 202, 'Terreno a Pagar', 'ANALYTICAL', 'LIABILITIES'),
  ('2.3.1.01.0001', 231, 'Capital Social', 'ANALYTICAL', 'LIABILITIES'),
  ('2.3.2', 232, 'Lucros ou Prejuízos Acumulados', 'SYNTHETIC', 'LIABILITIES'),
  ('2.3.2.01.0001', 2321, 'Lucros Acumulados', 'ANALYTICAL', 'LIABILITIES'),
  ('2.3.2.02.0001', 2322, 'Ajustes de Exercícios Anteriores', 'ANALYTICAL', 'LIABILITIES'),
  ('3.1.1.01.0001', 301, 'Receita de Vendas de Imóveis', 'ANALYTICAL', 'INCOME'),
  ('4.1.1.01.0001', 401, 'Custo dos Imóveis Vendidos', 'ANALYTICAL', 'EXPENSES'),
  ('4.2.1.01.0001', 421, 'Despesas Administrativas', 'ANALYTICAL', 'EXPENSES'),
  ('5.1.1.01.0001', 511, 'Terreno', 'ANALYTICAL', 'EXPENSES'),
  ('5.2', 52, 'Custo de Construção', 'SYNTHETIC', 'EXPENSES'),
  ('5.2.1.01.0001', 521, 'Materiais', 'ANALYTICAL', 'EXPENSES'),
  ('5.2.2.01.0001', 522, 'Salários', 'ANALYTICAL', 'EXPENSES'),
  ('5.2.3.01.0001', 523, 'Encargos Sociais', 'ANALYTICAL', 'EXPENSES'),
  ('5.2.9.01.0001', 529, 'Gastos Gerais', 'ANALYTICAL', 'EXPENSES'),
  ('5.9.1.01.0001', 591, 'Transferência para Estoque', 'ANALYTICAL', 'EXPENSES'),
  ('6.1.1.01.0001', 611, 'Apuração do Resultado', 'ANALYTICAL', 'TRANSITION');
grant select on plano to authenticated;

-- fechamento marca as partidas de zeramento, que só aparecem na passagem com zeramento.
create temporary table partida (competencia date, conta text, debito numeric, credito numeric, fechamento boolean) on commit drop;
insert into partida values
  ('2025-01-01', '1.1.1.01.0001', 1000, 0, false), ('2025-01-01', '2.3.1.01.0001', 0, 1000, false),
  ('2025-01-01', '5.1.1.01.0001', 300, 0, false), ('2025-01-01', '2.1.2.01.0001', 0, 300, false),
  ('2025-01-01', '5.2.1.01.0001', 200, 0, false), ('2025-01-01', '2.1.1.01.0001', 0, 200, false),
  ('2025-01-01', '5.2.2.01.0001', 100, 0, false), ('2025-01-01', '1.1.1.01.0001', 0, 100, false),
  ('2025-01-01', '5.2.3.01.0001', 20, 0, false), ('2025-01-01', '1.1.1.01.0001', 0, 20, false),
  ('2025-01-01', '1.1.3.01.0001', 620, 0, false), ('2025-01-01', '5.9.1.01.0001', 0, 620, false),
  ('2025-01-01', '1.1.2.01.0001', 800, 0, false), ('2025-01-01', '3.1.1.01.0001', 0, 800, false),
  ('2025-01-01', '1.1.1.01.0001', 500, 0, false), ('2025-01-01', '1.1.2.01.0001', 0, 500, false),
  ('2025-01-01', '4.1.1.01.0001', 400, 0, false), ('2025-01-01', '1.1.3.01.0001', 0, 400, false),
  ('2025-01-01', '4.2.1.01.0001', 50, 0, false), ('2025-01-01', '1.1.1.01.0001', 0, 50, false),
  ('2025-01-01', '1.1.1.01.0001', 40, 0, false), ('2025-01-01', '1.2.1.01.0001', 0, 40, false),
  ('2025-01-01', '3.1.1.01.0001', 800, 0, true), ('2025-01-01', '6.1.1.01.0001', 0, 800, true),
  ('2025-01-01', '6.1.1.01.0001', 450, 0, true), ('2025-01-01', '4.1.1.01.0001', 0, 400, true),
  ('2025-01-01', '4.2.1.01.0001', 0, 50, true),
  ('2025-01-01', '6.1.1.01.0001', 350, 0, true), ('2025-01-01', '2.3.2.01.0001', 0, 350, true),
  ('2025-01-01', '5.9.1.01.0001', 620, 0, true), ('2025-01-01', '5.1.1.01.0001', 0, 300, true),
  ('2025-01-01', '5.2.1.01.0001', 0, 200, true), ('2025-01-01', '5.2.2.01.0001', 0, 100, true),
  ('2025-01-01', '5.2.3.01.0001', 0, 20, true),
  ('2025-02-01', '1.1.4.01.0001', 7, 0, false), ('2025-02-01', '2.3.2.02.0001', 0, 7, false),
  ('2025-02-01', '1.1.5.01.0001', 5, 0, false), ('2025-02-01', '1.1.1.01.0001', 0, 5, false),
  ('2025-02-01', '1.1.2.01.0001', 100, 0, false), ('2025-02-01', '3.1.1.01.0001', 0, 100, false),
  ('2025-02-01', '4.2.1.01.0001', 30, 0, false), ('2025-02-01', '1.1.1.01.0001', 0, 30, false),
  ('2025-02-01', '3.1.1.01.0001', 100, 0, true), ('2025-02-01', '6.1.1.01.0001', 0, 100, true),
  ('2025-02-01', '6.1.1.01.0001', 30, 0, true), ('2025-02-01', '4.2.1.01.0001', 0, 30, true),
  ('2025-02-01', '6.1.1.01.0001', 70, 0, true), ('2025-02-01', '2.3.2.01.0001', 0, 70, true);

select is(
  (select count(*) from (select competencia from partida group by competencia having sum(debito) <> sum(credito)) as torto),
  0::bigint,
  'o razão inventado fecha em partida dobrada nos dois meses'
);

-- Duas passagens por mês para toda conta do plano. A sintética recebe a soma das analíticas abaixo dela,
-- para provar que o staging a deixa de fora do saldo.
insert into raw.registro (tenant_id, endpoint, payload, hash_registro)
with mes (competencia) as (values ('2025-01-01'::date), ('2025-02-01'::date)),
passagem (sem_zeramento) as (values (false), (true)),
calculo as (
  select m.competencia, p.conta, p.reduzida, p.nome, p.tipo, p.grupo, pa.sem_zeramento,
    coalesce(sum(l.debito) filter (where l.competencia = m.competencia), 0) as debito,
    coalesce(sum(l.credito) filter (where l.competencia = m.competencia), 0) as credito,
    coalesce(sum(l.debito - l.credito) filter (where l.competencia < m.competencia), 0) as anterior
  from mes m
  cross join plano p
  cross join passagem pa
  left join partida l
    on (l.conta = p.conta or (p.tipo = 'SYNTHETIC' and l.conta like p.conta || '.%'))
   and l.competencia <= m.competencia
   and (not pa.sem_zeramento or not l.fechamento)
  group by m.competencia, p.conta, p.reduzida, p.nome, p.tipo, p.grupo, pa.sem_zeramento
)
select '0e000000-0000-4000-8000-0000000000f1', 'trial-balance',
  jsonb_build_object(
    'companyId', 11, 'reducedCode', c.reduzida, 'accountGroup', c.grupo, 'account', c.conta,
    'accountName', c.nome, 'accountType', c.tipo, 'debit', c.debito, 'credit', c.credito,
    'operatingBalance', jsonb_build_object('value', abs(c.debito - c.credito),
                                           'type', case when c.debito - c.credito < 0 then 'C' else 'D' end),
    'balances', jsonb_build_object(
      'previous', jsonb_build_object('value', abs(c.anterior), 'type', case when c.anterior < 0 then 'C' else 'D' end),
      'current', jsonb_build_object('value', abs(c.anterior + c.debito - c.credito),
                                    'type', case when c.anterior + c.debito - c.credito < 0 then 'C' else 'D' end)),
    'initialPeriod', to_char(c.competencia, 'YYYY-MM-DD'),
    'desconsiderClosingBalance', c.sem_zeramento),
  md5(c.conta || c.competencia::text || c.sem_zeramento::text)
from calculo c;

-- Março chega só com a passagem com zeramento.
insert into raw.registro (tenant_id, endpoint, payload, hash_registro)
select '0e000000-0000-4000-8000-0000000000f1', 'trial-balance',
  jsonb_build_object('companyId', 11, 'reducedCode', 101, 'accountGroup', 'ASSETS', 'account', '1.1.1.01.0001',
    'accountName', 'Banco Conta Movimento', 'accountType', 'ANALYTICAL', 'debit', 0, 'credit', 0,
    'operatingBalance', jsonb_build_object('value', 0, 'type', 'D'),
    'balances', jsonb_build_object('previous', jsonb_build_object('value', 1335, 'type', 'D'),
                                   'current', jsonb_build_object('value', 1335, 'type', 'D')),
    'initialPeriod', '2025-03-01', 'desconsiderClosingBalance', false),
  'marco-uma-passagem';

select staging.recarregar_contabil('0e000000-0000-4000-8000-0000000000f1');
select staging.recarregar_contabil('0e000000-0000-4000-8000-0000000000f2');

select set_config('teste.alfa', (select id::text from app.empresa
  where tenant_id = '0e000000-0000-4000-8000-0000000000f1' and id_origem = 11), true);

-- Staging

select is(
  (select nome || ' | ' || nome_fantasia from app.empresa where id = current_setting('teste.alfa')::uuid),
  'Alfa Empreendimentos SPE Ltda | Alfa',
  'companies vira app.empresa com nome e nome fantasia'
);
select is(
  (select empresa_id from app.centro_custo where id = '0c000000-0000-4000-8000-0000000000f1'),
  11,
  'cost-centers.idCompany acerta a empresa da obra'
);
select is(
  (select count(*) from staging.plano_conta where empresa_id = current_setting('teste.alfa')::uuid),
  (select count(*) from plano),
  'o plano de contas tem analíticas e sintéticas'
);
select is(
  (select analitica from staging.plano_conta where empresa_id = current_setting('teste.alfa')::uuid and conta = '2.3.2'),
  false,
  'a sintética fica marcada como tal'
);
select is(
  (select grupo from staging.plano_conta where empresa_id = current_setting('teste.alfa')::uuid and conta = '6.1.1.01.0001'),
  'transitoria',
  'accountGroup vira o grupo em português'
);
select is(
  (select count(*) from staging.saldo_contabil_empresa_mensal where empresa_id = current_setting('teste.alfa')::uuid),
  (select count(*) * 2 from plano where tipo = 'ANALYTICAL'),
  'só contas analíticas, uma linha por conta e mês completo'
);
select is(
  (select count(*) from staging.saldo_contabil_empresa_mensal
   where empresa_id = current_setting('teste.alfa')::uuid and competencia = '2025-03-01'),
  0::bigint,
  'mês com uma só passagem não entra'
);
select results_eq(
  $$select saldo_final, saldo_final_sem_zeramento, debito, debito_sem_zeramento
    from staging.saldo_contabil_empresa_mensal
    where empresa_id = current_setting('teste.alfa')::uuid and conta = '3.1.1.01.0001' and competencia = '2025-01-01'$$,
  $$values (0::numeric(16,2), -800::numeric(16,2), 800::numeric(16,2), 0::numeric(16,2))$$,
  'a receita zera na passagem com zeramento e guarda o acumulado credor na passagem sem'
);
select is(
  (select saldo_final from staging.saldo_contabil_empresa_mensal
   where empresa_id = current_setting('teste.alfa')::uuid and conta = '2.3.2.01.0001' and competencia = '2025-02-01'),
  -420::numeric(16,2),
  'saldo credor entra negativo'
);
select is(
  (select sum(saldo_final) from staging.saldo_contabil_empresa_mensal
   where empresa_id = current_setting('teste.alfa')::uuid and competencia = '2025-02-01'),
  0::numeric,
  'a soma dos saldos finais do mês é zero: a partida dobrada chegou inteira'
);

select staging.recarregar_contabil('0e000000-0000-4000-8000-0000000000f1');
select is(
  (select count(*) from staging.saldo_contabil_empresa_mensal where empresa_id = current_setting('teste.alfa')::uuid),
  (select count(*) * 2 from plano where tipo = 'ANALYTICAL'),
  'recarga repetida não duplica'
);
select is(
  (select count(*) from staging.plano_conta where empresa_id = current_setting('teste.alfa')::uuid),
  (select count(*) from plano),
  'recarga repetida não duplica o plano'
);

-- Mapa: a sintética 2.3.2 cobre as duas analíticas de PL; a sintética 5.2 cobre gastos gerais, mas materiais,
-- salários e encargos têm mapa próprio e vencem. 1.1.5.01.0001 fica sem mapa de propósito.
insert into app.mapa_conta_linha (tenant_id, conta, linha, origem)
select '0e000000-0000-4000-8000-0000000000f1', conta, linha, 'demo'
from (values
  ('1.1.1.01.0001', 'bancos'), ('1.1.2.01.0001', 'receber_incorporacao'),
  ('1.1.3.01.0001', 'estoque_imoveis_construcao'), ('1.1.4.01.0001', 'impostos_recuperar'),
  ('1.2.1.01.0001', 'mutuo_receber'), ('2.1.1.01.0001', 'fornecedores'), ('2.1.2.01.0001', 'obrigacoes_terreno'),
  ('2.3.1.01.0001', 'aporte_capital'), ('2.3.2', 'lucros_acumulados'),
  ('3.1.1.01.0001', 'receita_vendas_incorporacao'), ('4.1.1.01.0001', 'custo_unidades_vendidas'),
  ('4.2.1.01.0001', 'despesas_administrativas'),
  ('5.1.1.01.0001', 'custo_terreno'), ('5.2', 'gastos_gerais_obra'), ('5.2.1.01.0001', 'materiais_aplicados'),
  ('5.2.2.01.0001', 'salarios_proventos'), ('5.2.3.01.0001', 'encargos_sociais'),
  ('5.9.1.01.0001', 'transferencia_custo_estoque'), ('6.1.1.01.0001', 'apuracao_resultado')
) as m (conta, linha);

select throws_ok(
  $$insert into app.mapa_conta_linha (tenant_id, conta, linha, origem)
    values ('0e000000-0000-4000-8000-0000000000f1', '1.1.1.01.0001', 'saldo_liquido', 'demo')$$,
  '22023', null,
  'nem a dona do banco grava linha de total no mapa'
);

-- Catálogo

select is(
  (select count(*) from marts.linha_relatorio where demonstrativo = 'fontes_usos' and tipo = 'conta'),
  44::bigint,
  'o F&U tem as 44 linhas de conta da planilha'
);
select is(
  (select count(*) from marts.linha_relatorio where demonstrativo = 'dre' and tipo = 'conta'),
  27::bigint,
  'a DRE tem as 27 linhas de conta da planilha'
);
select is(
  (select array_agg(componente order by componente) from marts.composicao_relatorio
   where demonstrativo = 'fontes_usos' and total = 'caixa_equivalentes'),
  array['aplicacoes_financeiras', 'bancos', 'caixa'],
  'caixa e equivalentes soma só o bloco de caixa'
);
select is(
  (select count(*) from marts.composicao_relatorio where demonstrativo = 'fontes_usos' and total = 'saldo_liquido'),
  41::bigint,
  'o saldo líquido soma todas as contas do F&U fora do bloco de caixa'
);
select is(
  (select count(*) from marts.linha_relatorio l
   where l.pai is not null and not exists (
     select 1 from marts.linha_relatorio p where p.demonstrativo = l.demonstrativo and p.linha = l.pai)),
  0::bigint,
  'todo pai do catálogo existe no mesmo demonstrativo'
);

-- Diretor com segundo fator

select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000d0f1", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;

select is(
  (select count(*) from marts.fontes_usos(current_setting('teste.alfa')::uuid, '2025-01-01', '2025-02-01', true)),
  (select count(*) from marts.linha_relatorio where demonstrativo = 'fontes_usos'),
  'o F&U devolve todas as linhas do catálogo, na ordem'
);
select results_eq(
  $$select linha, valor from marts.fontes_usos(current_setting('teste.alfa')::uuid, '2025-01-01', '2025-02-01', true)
    where linha in ('lucros_acumulados', 'grupo_lucros_acumulados', 'grupo_recursos_terceiros', 'fontes_operacionais',
                    'estoque_imoveis_construcao', 'impostos_recuperar', 'usos_operacionais', 'fluxo_operacional',
                    'fontes_financeiras', 'mutuo_receber', 'usos_financeiros', 'fluxo_financeiro',
                    'saldo_liquido', 'bancos', 'caixa_equivalentes')
    order by ordem$$,
  $$values ('fontes_operacionais', 927::numeric), ('grupo_lucros_acumulados', 427::numeric),
           ('lucros_acumulados', 427::numeric), ('grupo_recursos_terceiros', 500::numeric),
           ('usos_operacionais', -627::numeric), ('estoque_imoveis_construcao', -220::numeric),
           ('impostos_recuperar', -7::numeric), ('fluxo_operacional', 300::numeric),
           ('fontes_financeiras', 1000::numeric), ('usos_financeiros', 40::numeric), ('mutuo_receber', 40::numeric),
           ('fluxo_financeiro', 1040::numeric), ('saldo_liquido', 1340::numeric),
           ('caixa_equivalentes', 1335::numeric), ('bancos', 1335::numeric)$$,
  'F&U acumulado em fevereiro: herança da sintética, mútuo credor como fonte e saldo líquido 5 acima do caixa'
);
select is(
  (select valor from marts.fontes_usos(current_setting('teste.alfa')::uuid, '2025-01-01', '2025-01-01', true)
   where linha = 'saldo_liquido'),
  (select valor from marts.fontes_usos(current_setting('teste.alfa')::uuid, '2025-01-01', '2025-01-01', true)
   where linha = 'caixa_equivalentes'),
  'em janeiro, com tudo mapeado, saldo líquido é igual ao caixa'
);
select is(
  (select valor from marts.fontes_usos(current_setting('teste.alfa')::uuid, '2025-01-01', '2025-01-01', true)
   where linha = 'caixa_equivalentes'),
  1370::numeric,
  'caixa de janeiro é 1370'
);
select results_eq(
  $$select linha, valor from marts.fontes_usos(current_setting('teste.alfa')::uuid, '2025-02-01', '2025-02-01', false)
    where linha in ('grupo_lucros_acumulados', 'receber_incorporacao', 'saldo_liquido', 'caixa_equivalentes')
    order by ordem$$,
  $$values ('grupo_lucros_acumulados', 77::numeric), ('receber_incorporacao', -100::numeric),
           ('saldo_liquido', -30::numeric), ('caixa_equivalentes', -35::numeric)$$,
  'F&U no período de fevereiro: movimento do mês, saldo líquido 5 acima do caixa pela conta sem mapa'
);
select is(
  (select valor from marts.fontes_usos(current_setting('teste.alfa')::uuid, '2025-01-01', '2025-02-01', false)
   where linha = 'saldo_liquido'),
  1340::numeric,
  'período de janeiro a fevereiro soma o mesmo que o acumulado de fevereiro'
);
select is(
  (select valor from marts.fontes_usos(current_setting('teste.alfa')::uuid, '2025-01-01', '2025-12-01', true)
   where linha = 'saldo_liquido'),
  1340::numeric,
  'acumulado até um mês ainda não carregado usa o último mês carregado'
);

select results_eq(
  $$select linha, valor, pct_receita_liquida
    from marts.dre_societaria(current_setting('teste.alfa')::uuid, '2025-01-01', '2025-02-01', true)
    where linha in ('receita_vendas_incorporacao', 'receita_bruta', 'receita_liquida', 'custo_unidades_vendidas',
                    'grupo_custos', 'margem_contribuicao', 'grupo_despesas_fixas', 'lucro_operacional',
                    'lucro_antes_impostos', 'lucro_liquido')
    order by ordem$$,
  $$values ('receita_bruta', 900::numeric, 1.0000::numeric), ('receita_vendas_incorporacao', 900::numeric, 1.0000::numeric),
           ('receita_liquida', 900::numeric, 1.0000::numeric), ('grupo_custos', -400::numeric, -0.4444::numeric),
           ('custo_unidades_vendidas', -400::numeric, -0.4444::numeric),
           ('margem_contribuicao', 500::numeric, 0.5556::numeric), ('grupo_despesas_fixas', -80::numeric, -0.0889::numeric),
           ('lucro_operacional', 420::numeric, 0.4667::numeric), ('lucro_antes_impostos', 420::numeric, 0.4667::numeric),
           ('lucro_liquido', 420::numeric, 0.4667::numeric)$$,
  'DRE acumulada em fevereiro sai da passagem sem zeramento, com percentual sobre a receita líquida'
);
select is(
  (select valor from marts.dre_societaria(current_setting('teste.alfa')::uuid, '2025-01-01', '2025-01-01', true)
   where linha = 'lucro_liquido'),
  350::numeric,
  'lucro acumulado de janeiro é 350 e não zero: o zeramento ficou fora da DRE'
);
select is(
  (select valor from marts.dre_societaria(current_setting('teste.alfa')::uuid, '2025-02-01', '2025-02-01', false)
   where linha = 'lucro_liquido'),
  70::numeric,
  'lucro do período de fevereiro é 70'
);
select is(
  (select valor from marts.dre_societaria(current_setting('teste.alfa')::uuid, '2025-01-01', '2025-02-01', false)
   where linha = 'lucro_liquido'),
  420::numeric,
  'DRE acumulada é a soma dos períodos: 350 mais 70'
);

select results_eq(
  $$select linha, tipo, valor, pct_custo_incorrido
    from marts.custo_incorrido(current_setting('teste.alfa')::uuid, '2025-01-01', '2025-02-01', true)
    where linha in ('transferencia_custo_vendas_estoque', 'custo_unidades_vendidas', 'estoque_imoveis_construcao',
                    'custo_incorrido', 'custo_terreno', 'grupo_custo_construcao', 'materiais_aplicados',
                    'gastos_gerais_obra', 'pct_levado_ao_resultado', 'taxa_encargos')
    order by ordem$$,
  $$values ('transferencia_custo_vendas_estoque', 'total', 620::numeric, 1.0000::numeric),
           ('custo_unidades_vendidas', 'conta', 400::numeric, 0.6452::numeric),
           ('estoque_imoveis_construcao', 'conta', 220::numeric, 0.3548::numeric),
           ('custo_incorrido', 'total', 620::numeric, 1.0000::numeric),
           ('custo_terreno', 'conta', 300::numeric, 0.4839::numeric),
           ('grupo_custo_construcao', 'grupo', 320::numeric, 0.5161::numeric),
           ('materiais_aplicados', 'conta', 200::numeric, 0.3226::numeric),
           ('gastos_gerais_obra', 'conta', 0::numeric, 0.0000::numeric),
           ('pct_levado_ao_resultado', 'indicador', 0.6452::numeric, null::numeric),
           ('taxa_encargos', 'indicador', 0.2000::numeric, null::numeric)$$,
  'custo incorrido é estoque mais CMV; a analítica mapeada vence a sintética 5.2; indicadores no fim'
);
select is(
  (select valor from marts.custo_incorrido(current_setting('teste.alfa')::uuid, '2025-02-01', '2025-02-01', false)
   where linha = 'custo_incorrido'),
  0::numeric,
  'no período de fevereiro não houve custo novo'
);

-- Views mensais e conferência

select is(
  (select count(*) from marts.fontes_usos_mensal where empresa_id = current_setting('teste.alfa')::uuid),
  (select count(*) * 2 from marts.linha_relatorio where demonstrativo = 'fontes_usos'),
  'a view mensal do F&U tem todas as linhas nos dois meses'
);
select results_eq(
  $$select competencia, valor_mes, valor_acumulado from marts.fontes_usos_mensal
    where empresa_id = current_setting('teste.alfa')::uuid and linha = 'saldo_liquido' order by competencia$$,
  $$values ('2025-01-01'::date, 1370::numeric, 1370::numeric), ('2025-02-01'::date, -30::numeric, 1340::numeric)$$,
  'saldo líquido mês a mês e acumulado'
);
select is(
  (select empresa from marts.dre_societaria_mensal where empresa_id = current_setting('teste.alfa')::uuid limit 1),
  'Alfa Empreendimentos SPE Ltda',
  'a view mensal traz o nome da empresa'
);
select is(
  (select valor_acumulado from marts.dre_societaria_mensal
   where empresa_id = current_setting('teste.alfa')::uuid and linha = 'lucro_liquido' and competencia = '2025-02-01'),
  420::numeric,
  'DRE mensal acumulada bate com a função'
);
select is(
  (select count(*) from marts.custo_incorrido_mensal
   where empresa_id = current_setting('teste.alfa')::uuid and tipo = 'indicador'),
  0::bigint,
  'a view mensal do custo não traz as linhas de indicador'
);
select results_eq(
  $$select competencia, diferenca_identidade, lucros_acumulados, lucro_liquido_dre, ajuste_exercicios_anteriores,
           contas_sem_mapa, movimento_sem_mapa
    from marts.controle_fontes_usos where empresa_id = current_setting('teste.alfa')::uuid order by competencia$$,
  $$values ('2025-01-01'::date, 0::numeric, 350::numeric, 350::numeric, 0::numeric, 0, 0::numeric),
           ('2025-02-01'::date, 5::numeric, 427::numeric, 420::numeric, 7::numeric, 1, 5::numeric)$$,
  'o controle mostra a conta sem mapa como diferença e o ajuste de PL como ajuste de exercícios anteriores'
);
select results_eq(
  $$select conta, nome, saldo_final, movimento from marts.conta_sem_mapa
    where empresa_id = current_setting('teste.alfa')::uuid$$,
  $$values ('1.1.5.01.0001', 'Adiantamentos a Terceiros', 5::numeric, 5::numeric)$$,
  'a conta sem mapa aparece com nome, saldo e movimento'
);
select results_eq(
  $$select nome, obras, primeira_competencia, ultima_competencia, caixa_equivalentes, fluxo_operacional,
           lucro_liquido, diferenca_identidade, contas_sem_mapa
    from marts.empresa_resumo$$,
  $$values ('Alfa Empreendimentos SPE Ltda', 1, '2025-01-01'::date, '2025-02-01'::date, 1335::numeric, 300::numeric,
            420::numeric, 5::numeric, 1)$$,
  'o resumo da empresa traz a posição do último mês'
);
select results_eq(
  $$select conta, linha, linha_efetiva, demonstrativos from marts.mapa_contas
    where conta in ('2.3.2', '2.3.2.02.0001', '5.2.1.01.0001', '5.2.9.01.0001', '1.1.3.01.0001', '1.1.5.01.0001')
    order by conta$$,
  $$values ('1.1.3.01.0001', 'estoque_imoveis_construcao', 'estoque_imoveis_construcao', 'custo_incorrido, fontes_usos'),
           ('1.1.5.01.0001', null, null, null),
           ('2.3.2', 'lucros_acumulados', 'lucros_acumulados', 'fontes_usos'),
           ('2.3.2.02.0001', null, 'lucros_acumulados', 'fontes_usos'),
           ('5.2.1.01.0001', 'materiais_aplicados', 'materiais_aplicados', 'custo_incorrido'),
           ('5.2.9.01.0001', null, 'gastos_gerais_obra', 'custo_incorrido')$$,
  'a tela de mapeamento mostra a linha própria, a herdada e os demonstrativos'
);
select is(
  (select count(*) from marts.mapa_contas),
  (select count(*) from plano),
  'a tela de mapeamento lista o plano inteiro do tenant'
);

-- Vizinho

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000d0f2", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;

select is(
  (select count(*) from marts.fontes_usos(current_setting('teste.alfa')::uuid, '2025-01-01', '2025-02-01', true)),
  0::bigint,
  'diretor de outro tenant não recebe linha nenhuma da Alfa'
);
select is(
  (select count(*) from marts.dre_societaria(current_setting('teste.alfa')::uuid, '2025-01-01', '2025-02-01', true)),
  0::bigint,
  'nem da DRE'
);
select is(
  (select count(*) from marts.custo_incorrido(current_setting('teste.alfa')::uuid, '2025-01-01', '2025-02-01', true)),
  0::bigint,
  'nem do custo incorrido'
);
select is((select count(*) from marts.empresa_resumo), 1::bigint, 'o vizinho vê só a própria empresa no resumo');
select is((select count(*) from marts.fontes_usos_mensal), 0::bigint, 'o vizinho não vê o F&U mensal da Alfa');
select is((select count(*) from marts.controle_fontes_usos), 0::bigint, 'o vizinho não vê o controle da Alfa');
select is((select count(*) from marts.mapa_contas), 0::bigint, 'o vizinho não vê o plano da Alfa');

-- Estrutura

reset role;
select ok(
  (select bool_and(c.relrowsecurity and c.relforcerowsecurity) from pg_class c
   where c.oid in ('app.empresa'::regclass, 'staging.plano_conta'::regclass,
                   'staging.saldo_contabil_empresa_mensal'::regclass, 'app.mapa_conta_linha'::regclass)),
  'RLS ligado e forçado nas quatro tabelas novas'
);
select is(
  (select count(*) from pg_policies
   where (schemaname, tablename) in (('app', 'empresa'), ('staging', 'plano_conta'),
                                     ('staging', 'saldo_contabil_empresa_mensal'), ('app', 'mapa_conta_linha'))
     and permissive = 'PERMISSIVE'),
  4::bigint,
  'uma política permissiva por tabela'
);
select is(
  (select count(*) from pg_policies
   where (schemaname, tablename) in (('app', 'empresa'), ('staging', 'plano_conta'),
                                     ('staging', 'saldo_contabil_empresa_mensal'), ('app', 'mapa_conta_linha'))
     and policyname = 'segundo_fator' and permissive = 'RESTRICTIVE'),
  4::bigint,
  'a restritiva do segundo fator está nas quatro'
);
select ok(
  not has_table_privilege('authenticated', 'app.empresa', 'insert, update, delete')
  and not has_table_privilege('authenticated', 'staging.saldo_contabil_empresa_mensal', 'insert, update, delete')
  and not has_table_privilege('authenticated', 'staging.plano_conta', 'insert, update, delete')
  and not has_table_privilege('authenticated', 'app.mapa_conta_linha', 'insert, update, delete')
  and not has_table_privilege('anon', 'app.empresa', 'select')
  and not has_table_privilege('anon', 'staging.saldo_contabil_empresa_mensal', 'select'),
  'usuário logado não escreve nas tabelas pela API e anônimo não lê'
);
select is(
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'marts'
     and c.relname in ('linha_relatorio', 'composicao_relatorio', 'mapa_conta_efetivo', 'mapa_contas',
                       'saldo_linha_mensal', 'fontes_usos_mensal', 'dre_societaria_mensal', 'custo_incorrido_mensal',
                       'controle_fontes_usos', 'conta_sem_mapa', 'empresa_resumo')
     and c.reloptions @> array['security_invoker=true']),
  11::bigint,
  'as onze views rodam como quem consulta'
);
select ok(
  has_table_privilege('authenticated', 'marts.fontes_usos_mensal', 'select')
  and has_table_privilege('authenticated', 'marts.empresa_resumo', 'select')
  and has_table_privilege('authenticated', 'marts.controle_fontes_usos', 'select')
  and not has_table_privilege('anon', 'marts.fontes_usos_mensal', 'select')
  and not has_table_privilege('anon', 'marts.empresa_resumo', 'select'),
  'usuário logado lê as views e anônimo não'
);
select ok(
  has_function_privilege('authenticated', 'marts.fontes_usos(uuid, date, date, boolean)', 'execute')
  and has_function_privilege('authenticated', 'marts.dre_societaria(uuid, date, date, boolean)', 'execute')
  and has_function_privilege('authenticated', 'marts.custo_incorrido(uuid, date, date, boolean)', 'execute')
  and not has_function_privilege('anon', 'marts.fontes_usos(uuid, date, date, boolean)', 'execute')
  and not has_function_privilege('public', 'marts.dre_societaria(uuid, date, date, boolean)', 'execute'),
  'só o usuário logado chama as três funções'
);
select ok(
  not (select bool_or(prosecdef) from pg_proc
       where oid in ('marts.fontes_usos(uuid, date, date, boolean)'::regprocedure,
                     'marts.dre_societaria(uuid, date, date, boolean)'::regprocedure,
                     'marts.custo_incorrido(uuid, date, date, boolean)'::regprocedure)),
  'as três funções rodam com o papel de quem chama'
);
select ok(
  not has_function_privilege('authenticated', 'staging.recarregar_contabil(uuid)', 'execute')
  and not has_function_privilege('anon', 'staging.recarregar_contabil(uuid)', 'execute')
  and not has_function_privilege('public', 'staging.recarregar_contabil(uuid)', 'execute'),
  'usuário da API não executa a recarga contábil'
);
select ok(
  (select prosecdef and proconfig @> array['search_path=""'] from pg_proc
   where oid = 'staging.recarregar_contabil(uuid)'::regprocedure),
  'a recarga é security definer com search_path vazio'
);
select is_empty(
  $$select table_name || '.' || column_name from information_schema.columns
    where (table_schema, table_name) in (('app', 'empresa'), ('staging', 'plano_conta'),
      ('staging', 'saldo_contabil_empresa_mensal'), ('app', 'mapa_conta_linha'), ('marts', 'empresa_resumo'),
      ('marts', 'controle_fontes_usos'), ('marts', 'conta_sem_mapa'), ('marts', 'mapa_contas'))
      and column_name ~ '(^|_)(cnpj|cpf|email|telefone|renda|score|agencia)(_|$)'$$,
  'tabelas e views novas não guardam cnpj nem dado pessoal'
);
select has_index('staging', 'saldo_contabil_empresa_mensal', 'saldo_contabil_empresa_mensal_competencia_idx',
  'índice do saldo por empresa e competência');
select has_index('app', 'centro_custo', 'centro_custo_empresa_idx', 'índice da obra por empresa');
select has_index('app', 'mapa_conta_linha', 'mapa_conta_linha_vigente_idx', 'índice da vigente do mapa');

select * from finish();
rollback;
