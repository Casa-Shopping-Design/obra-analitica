-- Catálogo das linhas dos três demonstrativos da planilha de Fontes e Usos do cliente e o de-para conta
-- contábil para linha, editável pelo financeiro (ver docs/decisoes/0019). Os rótulos são os da planilha,
-- inclusive a grafia de "Receita de Equivalênica Patrimonial", porque a importação casa por rótulo.

-- Lista fixa em view, como marts.linha_resultado da 0030: não tem tenant. Uma linha do tipo conta pode
-- aparecer em mais de um demonstrativo (estoque e CMV estão no custo incorrido também); o mapa guarda só o id.
-- pai é o agregado imediatamente acima, até o último total; nivel é só recuo de tela (0 total, 1 grupo, 2 conta).
-- grupo_conta é o primeiro dígito da conta que cabe na linha. Linhas do tipo indicador só existem na função
-- do custo incorrido. O demonstrativo 'fora' guarda contas que fecham a partida dobrada sem entrar em relatório.
create view marts.linha_relatorio with (security_invoker = true) as
select demonstrativo, linha, rotulo, grupo_conta, ordem, tipo, pai, nivel
from (values
  ('fontes_usos', 'fontes_operacionais', '(+) FONTES DE RECURSOS DAS ATIVIDADES OPERACIONAIS', null, 10, 'total', 'fluxo_operacional', 0),
  ('fontes_usos', 'grupo_lucros_acumulados', 'Lucros Acumulados', null, 20, 'grupo', 'fontes_operacionais', 1),
  ('fontes_usos', 'lucros_acumulados', 'Lucros Acumulados', '2', 21, 'conta', 'grupo_lucros_acumulados', 2),
  ('fontes_usos', 'reserva_legal', 'Reserva Legal', '2', 22, 'conta', 'grupo_lucros_acumulados', 2),
  ('fontes_usos', 'dividendos_pagar_participantes', 'Dividendos a Pagar Sócios Participantes', '2', 23, 'conta', 'grupo_lucros_acumulados', 2),
  ('fontes_usos', 'dividendos_pagar_ostensivos', 'Dividendos a Pagar Sócios Ostensivos', '2', 24, 'conta', 'grupo_lucros_acumulados', 2),
  ('fontes_usos', 'dividendos_pagar', 'Dividendos a Pagar', '2', 25, 'conta', 'grupo_lucros_acumulados', 2),
  ('fontes_usos', 'grupo_resultado_diferido', 'Resultado Diferido', null, 30, 'grupo', 'fontes_operacionais', 1),
  ('fontes_usos', 'provisao_assistencia_tecnica', 'Provisão Assistência Técnica', '2', 31, 'conta', 'grupo_resultado_diferido', 2),
  ('fontes_usos', 'resultado_diferido', 'Resultado Diferido', '2', 32, 'conta', 'grupo_resultado_diferido', 2),
  ('fontes_usos', 'grupo_recursos_terceiros', 'Recursos Tomados de Terceiros', null, 40, 'grupo', 'fontes_operacionais', 1),
  ('fontes_usos', 'adiantamento_clientes', 'Adiantamento e Obrigações com Clientes', '2', 41, 'conta', 'grupo_recursos_terceiros', 2),
  ('fontes_usos', 'emprestimos_bancarios', 'Empréstimos Bancários', '2', 42, 'conta', 'grupo_recursos_terceiros', 2),
  ('fontes_usos', 'fornecedores', 'Fornecedores e Credores Diversos', '2', 43, 'conta', 'grupo_recursos_terceiros', 2),
  ('fontes_usos', 'impostos_pagar', 'Impostos a Pagar', '2', 44, 'conta', 'grupo_recursos_terceiros', 2),
  ('fontes_usos', 'obrigacoes_terreno', 'Obrigações por Aquisição de Terreno', '2', 45, 'conta', 'grupo_recursos_terceiros', 2),
  ('fontes_usos', 'salarios_pagar', 'Salários e Obrigações Trabalhistas a Pagar', '2', 46, 'conta', 'grupo_recursos_terceiros', 2),
  ('fontes_usos', 'taxa_administracao_pagar', 'TAC a pagar (Tx. Ad. Central)', '2', 47, 'conta', 'grupo_recursos_terceiros', 2),
  ('fontes_usos', 'usos_operacionais', '(-) USO DE RECURSOS NAS ATIVIDADES OPERACIONAIS', null, 50, 'total', 'fluxo_operacional', 0),
  ('fontes_usos', 'grupo_recursos_aplicados', 'Recursos Aplicados a Retornar', null, 60, 'grupo', 'usos_operacionais', 1),
  ('fontes_usos', 'receber_incorporacao', 'Contas a Receber - Incorporação', '1', 61, 'conta', 'grupo_recursos_aplicados', 2),
  ('fontes_usos', 'receber_ajustes_pdd', 'Contas a Receber - Ajustes e PDD', '1', 62, 'conta', 'grupo_recursos_aplicados', 2),
  ('fontes_usos', 'receber_cartao', 'Contas a Receber - Cartão de Crédito', '1', 63, 'conta', 'grupo_recursos_aplicados', 2),
  ('fontes_usos', 'receber_outras_atividades', 'Contas a Receber - Outras Atividades', '1', 64, 'conta', 'grupo_recursos_aplicados', 2),
  ('fontes_usos', 'taxa_administracao_receber', 'TAC a Receber (Tx. Adm. Central)', '1', 65, 'conta', 'grupo_recursos_aplicados', 2),
  ('fontes_usos', 'estoque_imoveis_construcao', 'Estoque - Incorporação Imov. Em Construção', '1', 66, 'conta', 'grupo_recursos_aplicados', 2),
  ('fontes_usos', 'estoque_almoxarifado', 'Estoque - Materiais no Almoxarifado', '1', 67, 'conta', 'grupo_recursos_aplicados', 2),
  ('fontes_usos', 'estoque_projetos', 'Estoque - Projetos em Desenvolvimento', '1', 68, 'conta', 'grupo_recursos_aplicados', 2),
  ('fontes_usos', 'adiantamentos_terceiros', 'Adiantamentos à Terceiros', '1', 69, 'conta', 'grupo_recursos_aplicados', 2),
  ('fontes_usos', 'impostos_recuperar', 'Impostos a Recuperar', '1', 70, 'conta', 'grupo_recursos_aplicados', 2),
  ('fontes_usos', 'depositos_judiciais', 'Depósitos Judiciais e Cauções a Receber', '1', 71, 'conta', 'grupo_recursos_aplicados', 2),
  ('fontes_usos', 'grupo_corretagem_apropriar', 'Despesas de Corretagem a Apropriar', null, 80, 'grupo', 'usos_operacionais', 1),
  ('fontes_usos', 'corretagem_apropriada', '(-) Despesas de Corretagem Apropriadas', '1', 81, 'conta', 'grupo_corretagem_apropriar', 2),
  ('fontes_usos', 'corretagem_apropriar', 'Despesas de Corretagem a Apropriar', '1', 82, 'conta', 'grupo_corretagem_apropriar', 2),
  ('fontes_usos', 'grupo_despesas_diferidas', 'Despesas Diferidas', null, 90, 'grupo', 'usos_operacionais', 1),
  ('fontes_usos', 'marketing_institucional', 'Despesas com Marketing Institucional', '1', 91, 'conta', 'grupo_despesas_diferidas', 2),
  ('fontes_usos', 'despesas_diferidas', 'Despesas Diferidas', '1', 92, 'conta', 'grupo_despesas_diferidas', 2),
  ('fontes_usos', 'seguro_apropriar', 'Prêmio de Seguro a Apropriar', '1', 93, 'conta', 'grupo_despesas_diferidas', 2),
  ('fontes_usos', 'fluxo_operacional', 'FLUXO DE CAIXA DAS ATIVIDADES OPERACIONAIS (NCG)', null, 100, 'total', 'saldo_liquido', 0),
  ('fontes_usos', 'fontes_financeiras', 'FONTES DE RECURSOS DE ATIVIDADES FINANCEIRAS', null, 110, 'total', 'fluxo_financeiro', 0),
  ('fontes_usos', 'grupo_recursos_socios', 'Recursos Tomados de Sócios', null, 120, 'grupo', 'fontes_financeiras', 1),
  ('fontes_usos', 'aporte_capital', 'Aporte de Capital', '2', 121, 'conta', 'grupo_recursos_socios', 2),
  ('fontes_usos', 'capital_especial', 'Capital Especial', '2', 122, 'conta', 'grupo_recursos_socios', 2),
  ('fontes_usos', 'mutuo_pagar', 'Empréstimos e Mútuo a Pagar', '2', 123, 'conta', 'grupo_recursos_socios', 2),
  ('fontes_usos', 'grupo_recursos_socios_participantes', 'Recursos Tomados de Sócios Participantes', null, 130, 'grupo', 'fontes_financeiras', 1),
  ('fontes_usos', 'saldo_pagar_terreno', 'Saldo a Pagar de Terreno', '2', 131, 'conta', 'grupo_recursos_socios_participantes', 2),
  ('fontes_usos', 'usos_financeiros', 'USOS DE RECURSOS DE ATIVIDADES FINANCEIRAS', null, 140, 'total', 'fluxo_financeiro', 0),
  ('fontes_usos', 'grupo_partes_relacionadas', 'USOS (-) Recursos Aplicados Partes Relacionadas', null, 150, 'grupo', 'usos_financeiros', 1),
  ('fontes_usos', 'dividendos_receber', 'Dividendos a Receber', '1', 151, 'conta', 'grupo_partes_relacionadas', 2),
  ('fontes_usos', 'mutuo_receber', 'Empréstimos e Mútuo a Receber', '1', 152, 'conta', 'grupo_partes_relacionadas', 2),
  ('fontes_usos', 'grupo_participacoes', '520 - Participações em Outras Empresas', null, 160, 'grupo', 'usos_financeiros', 1),
  ('fontes_usos', 'equivalencia_patrimonial', 'Equivalência Patrimonial', '1', 161, 'conta', 'grupo_participacoes', 2),
  ('fontes_usos', 'participacoes_spe', 'Participações em SPEs Empreendimentos Próprios', '1', 162, 'conta', 'grupo_participacoes', 2),
  ('fontes_usos', 'grupo_investimentos_longo_prazo', '530 - Investimentos Longo Prazo', null, 170, 'grupo', 'usos_financeiros', 1),
  ('fontes_usos', 'aplicacoes_longo_prazo', 'Aplicações Financeiras Longo Prazo', '1', 171, 'conta', 'grupo_investimentos_longo_prazo', 2),
  ('fontes_usos', 'grupo_imobilizado', '540 - Imobilizado Técnico', null, 180, 'grupo', 'usos_financeiros', 1),
  ('fontes_usos', 'depreciacao_acumulada', '(-) Depreciação e Amortização', '1', 181, 'conta', 'grupo_imobilizado', 2),
  ('fontes_usos', 'imobilizado', 'Imobilizado', '1', 182, 'conta', 'grupo_imobilizado', 2),
  ('fontes_usos', 'fluxo_financeiro', 'FLUXO DE CAIXA DAS ATIVIDADES FINANCEIRAS', null, 190, 'total', 'saldo_liquido', 0),
  ('fontes_usos', 'saldo_liquido', 'SALDO LÍQUIDO DO FLUXO DE CAIXA', null, 200, 'total', null, 0),
  ('fontes_usos', 'caixa_equivalentes', 'CAIXA E EQUIVALENTES DE CAIXA', null, 210, 'total', null, 0),
  ('fontes_usos', 'bancos', 'Bancos c/movimento', '1', 211, 'conta', 'caixa_equivalentes', 1),
  ('fontes_usos', 'aplicacoes_financeiras', 'Aplicações Financeiras', '1', 212, 'conta', 'caixa_equivalentes', 1),
  ('fontes_usos', 'caixa', 'Caixa e Equivalentes de Caixa', '1', 213, 'conta', 'caixa_equivalentes', 1),

  ('dre', 'receita_bruta', 'RECEITA BRUTA', null, 10, 'total', 'receita_liquida', 0),
  ('dre', 'grupo_receita_vendas', 'RECEITA DE VENDAS', null, 20, 'grupo', 'receita_bruta', 1),
  ('dre', 'receita_vendas_incorporacao', 'Receita de Vendas - Incorporação', '3', 21, 'conta', 'grupo_receita_vendas', 2),
  ('dre', 'juros_tabela_price', 'Juros Tab. Price s/vendas a prazo', '3', 22, 'conta', 'grupo_receita_vendas', 2),
  ('dre', 'grupo_outras_receitas', 'OUTRAS RECEITAS', null, 30, 'grupo', 'receita_bruta', 1),
  ('dre', 'ganho_distrato', 'Ganho Distrato de Vendas', '3', 31, 'conta', 'grupo_outras_receitas', 2),
  ('dre', 'receita_servicos', 'Receita Serviços Prestados', '3', 32, 'conta', 'grupo_outras_receitas', 2),
  ('dre', 'outras_receitas', 'Outras Receitas', '3', 33, 'conta', 'grupo_outras_receitas', 2),
  ('dre', 'grupo_deducoes', '(-) DEDUÇÕES DE VENDAS', null, 40, 'grupo', 'receita_liquida', 1),
  ('dre', 'impostos_vendas', '(-) Impostos s/Vendas', '3', 41, 'conta', 'grupo_deducoes', 2),
  ('dre', 'perdas_vendas_canceladas', '(-) Perdas c/Vendas Canceladas', '3', 42, 'conta', 'grupo_deducoes', 2),
  ('dre', 'vendas_canceladas_abatimentos', '(-) Vendas Canceladas e Abatimentos', '3', 43, 'conta', 'grupo_deducoes', 2),
  ('dre', 'receita_liquida', 'RECEITA LÍQUIDA', null, 50, 'total', 'margem_contribuicao', 0),
  ('dre', 'grupo_custos', 'CUSTOS TOTAL DAS VENDAS', null, 60, 'grupo', 'margem_contribuicao', 1),
  ('dre', 'custo_unidades_vendidas', 'Custo das Unidades Vendidas', '4', 61, 'conta', 'grupo_custos', 2),
  ('dre', 'custo_assistencia_tecnica', 'Custo da Provisão de Assistência Técnica', '4', 62, 'conta', 'grupo_custos', 2),
  ('dre', 'outros_custos', 'Outros Custos', '4', 63, 'conta', 'grupo_custos', 2),
  ('dre', 'juros_financiamento_obra', 'Juros s/Finactº da Obra', '4', 64, 'conta', 'grupo_custos', 2),
  ('dre', 'custo_venda_terreno', 'Custo na Venda de Terreno', '4', 65, 'conta', 'grupo_custos', 2),
  ('dre', 'grupo_despesas_vendas', 'DESPESAS DE VENDAS', null, 70, 'grupo', 'margem_contribuicao', 1),
  ('dre', 'corretagem', 'Corretagem', '4', 71, 'conta', 'grupo_despesas_vendas', 2),
  ('dre', 'publicidade', 'Publicidade', '4', 72, 'conta', 'grupo_despesas_vendas', 2),
  ('dre', 'margem_contribuicao', 'MARGEM DE CONTRIBUIÇÃO', null, 80, 'total', 'lucro_operacional', 0),
  ('dre', 'grupo_despesas_fixas', 'DESPESAS FIXAS', null, 90, 'grupo', 'lucro_operacional', 1),
  ('dre', 'despesas_administrativas', 'Despesas Administrativas', '4', 91, 'conta', 'grupo_despesas_fixas', 2),
  ('dre', 'sentencas', 'Sentenças Cíveis e Trabalhistas', '4', 92, 'conta', 'grupo_despesas_fixas', 2),
  ('dre', 'servicos_terceiros_despesa', 'Serviços de Terceiros', '4', 93, 'conta', 'grupo_despesas_fixas', 2),
  ('dre', 'despesas_tributarias', 'Despesas Tributárias', '4', 94, 'conta', 'grupo_despesas_fixas', 2),
  ('dre', 'taxa_administracao_central', 'TAC - Tx. De Adm. Central', '4', 95, 'conta', 'grupo_despesas_fixas', 2),
  ('dre', 'depreciacao', 'Depreciação', '4', 96, 'conta', 'grupo_despesas_fixas', 2),
  ('dre', 'outras_despesas', 'Outras Despesas', '4', 97, 'conta', 'grupo_despesas_fixas', 2),
  ('dre', 'lucro_operacional', 'LUCRO OPERACIONAL', null, 100, 'total', 'lucro_antes_impostos', 0),
  ('dre', 'grupo_efeitos_financeiros', 'EFEITOS FINANCEIROS', null, 110, 'grupo', 'lucro_antes_impostos', 1),
  ('dre', 'despesas_financeiras', '(-) Despesas Financeiras', '3', 111, 'conta', 'grupo_efeitos_financeiros', 2),
  ('dre', 'receitas_financeiras', 'Receitas Financeiras', '3', 112, 'conta', 'grupo_efeitos_financeiros', 2),
  ('dre', 'receita_equivalencia', 'Receita de Equivalênica Patrimonial', '3', 113, 'conta', 'grupo_efeitos_financeiros', 2),
  ('dre', 'receita_participacao', 'Receita Financeira p/Participação em Outras Empresas', '3', 114, 'conta', 'grupo_efeitos_financeiros', 2),
  ('dre', 'lucro_antes_impostos', 'LUCRO LÍQUIDO ANTES DO IRPJ/CSLL', null, 120, 'total', 'lucro_liquido', 0),
  ('dre', 'irpj_csll', 'IRPJ / CSLL', '4', 130, 'conta', 'lucro_liquido', 1),
  ('dre', 'lucro_liquido', 'LUCRO LÍQUIDO', null, 140, 'total', null, 0),

  ('custo_incorrido', 'transferencia_custo_vendas_estoque', '05 (-) TRANSFERÊNCIA CUSTO DAS VENDAS/ESTOQUE', null, 10, 'total', null, 0),
  ('custo_incorrido', 'custo_unidades_vendidas', 'Custo das Unidades Vendidas', '4', 11, 'conta', 'transferencia_custo_vendas_estoque', 1),
  ('custo_incorrido', 'estoque_imoveis_construcao', 'Estoque - Incorporação Imov. Em Construção', '1', 12, 'conta', 'transferencia_custo_vendas_estoque', 1),
  ('custo_incorrido', 'custo_incorrido', 'CUSTO INCORRIDO', null, 20, 'total', null, 0),
  ('custo_incorrido', 'custo_terreno', 'Custo de Terreno', '5', 21, 'conta', 'custo_incorrido', 1),
  ('custo_incorrido', 'custo_projetos', 'Custo De Projetos', '5', 22, 'conta', 'custo_incorrido', 1),
  ('custo_incorrido', 'custo_legalizacao', 'Custo De Legalização', '5', 23, 'conta', 'custo_incorrido', 1),
  ('custo_incorrido', 'grupo_custo_construcao', 'Custo de Construção', null, 30, 'grupo', 'custo_incorrido', 1),
  ('custo_incorrido', 'materiais_aplicados', 'Materiais Aplicados Nas Obras', '5', 31, 'conta', 'grupo_custo_construcao', 2),
  ('custo_incorrido', 'salarios_proventos', 'Salários e Proventos', '5', 32, 'conta', 'grupo_custo_construcao', 2),
  ('custo_incorrido', 'encargos_sociais', 'Encargos Sociais', '5', 33, 'conta', 'grupo_custo_construcao', 2),
  ('custo_incorrido', 'encargos_complementares', 'Encargos Complementares', '5', 34, 'conta', 'grupo_custo_construcao', 2),
  ('custo_incorrido', 'servicos_terceiros_obra', 'Serviços de Terceiros', '5', 35, 'conta', 'grupo_custo_construcao', 2),
  ('custo_incorrido', 'gastos_gerais_obra', 'Gastos Gerais de Obra', '5', 36, 'conta', 'grupo_custo_construcao', 2),
  ('custo_incorrido', 'pct_levado_ao_resultado', '% do custo incorrido levado ao resultado', null, 40, 'indicador', null, 0),
  ('custo_incorrido', 'taxa_encargos', 'Taxa de encargos sobre salários', null, 41, 'indicador', null, 0),

  ('fora', 'apropriacao_mao_obra', 'Apropriação da Mão de Obra', '5', 10, 'conta', null, 1),
  ('fora', 'transferencia_custo_estoque', '(-) Transf. do Custo de Imóveis em Construção', '5', 20, 'conta', null, 1),
  ('fora', 'apuracao_resultado', 'Lucro do Exercício', '6', 30, 'conta', null, 1),
  ('fora', 'saldo_abertura', 'Saldo de Abertura', '6', 40, 'conta', null, 1)
) as l (demonstrativo, linha, rotulo, grupo_conta, ordem, tipo, pai, nivel);

grant select on marts.linha_relatorio to authenticated;

-- Fecho transitivo de pai: para cada linha, as contas que somam nela (a conta soma em si mesma). Totais e
-- grupos saem daqui, nunca somando a coluna inteira. O(linhas x profundidade), com profundidade até 5.
create view marts.composicao_relatorio with (security_invoker = true) as
with recursive arvore as (
  select demonstrativo, linha as total, linha as componente, pai
  from marts.linha_relatorio
  where tipo = 'conta'
  union all
  select a.demonstrativo, a.pai, a.componente, l.pai
  from arvore a
  join marts.linha_relatorio l on l.demonstrativo = a.demonstrativo and l.linha = a.pai
)
select demonstrativo, total, componente from arvore;

grant select on marts.composicao_relatorio to authenticated;

-- A chave é o código contábil, nunca o nome: dois grupos têm "Serviços de Terceiros". Só cresce: cada gravação
-- insere linhas novas e a vigente é a última por (tenant_id, conta); linha nula tira o mapa próprio. O mapa é por
-- tenant porque o plano é o mesmo nas empresas do grupo. Quem gravou e quando é a própria auditoria.
create table app.mapa_conta_linha (
  id bigint generated always as identity primary key,
  tenant_id uuid not null references app.tenant(id) on delete cascade,
  conta text not null,
  linha text,
  criado_por uuid,
  criado_em timestamptz not null default now(),
  origem text not null check (origem in ('painel', 'importacao', 'demo'))
);
create index mapa_conta_linha_vigente_idx on app.mapa_conta_linha (tenant_id, conta, id desc);

-- A linha não tem chave estrangeira porque o catálogo é view; o gatilho segura a importação e a demo,
-- que gravam direto como dona do banco.
create function app.validar_mapa_conta_linha() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.linha is not null and not exists (
    select 1 from marts.linha_relatorio l
    where l.linha = new.linha and l.tipo = 'conta' and l.grupo_conta = left(new.conta, 1)
  ) then
    raise exception 'linha fora do catálogo ou de outro grupo de conta' using errcode = '22023';
  end if;
  return new;
end $$;

create trigger validar_linha before insert or update on app.mapa_conta_linha
  for each row execute function app.validar_mapa_conta_linha();

-- O perfil leitura entra porque as funções de F&U e DRE rodam com o papel de quem consulta e precisam
-- resolver a linha de cada conta; a tela de mapeamento (marts.mapa_contas) fica com diretor e financeiro.
alter table app.mapa_conta_linha enable row level security;
alter table app.mapa_conta_linha force row level security;
create policy leitura_mapa on app.mapa_conta_linha for select to authenticated
  using (tenant_id = (select app.tenant_atual())
         and (select app.perfil_atual()) in ('diretor', 'financeiro', 'leitura'));
create policy segundo_fator on app.mapa_conta_linha as restrictive for all to authenticated
  using ((select app.segundo_fator_cumprido()));
revoke all on table app.mapa_conta_linha from public, anon, authenticated;
grant select on table app.mapa_conta_linha to authenticated;
revoke all on sequence app.mapa_conta_linha_id_seq from public, anon, authenticated;

-- Linha efetiva de cada conta analítica com saldo carregado: a vigente da própria conta vence; senão vale o
-- prefixo sintético mais longo mapeado (1.1.1 cobre 1.1.1.01.0001). Vigente nula tira o mapa próprio da
-- conta, que volta a herdar do prefixo. Não depende do plano de contas, para o perfil leitura resolver o mapa.
-- O(contas x mapeamentos) no like por prefixo: 300 contas por empresa e 200 mapeamentos dão 60 mil comparações.
create view marts.mapa_conta_efetivo with (security_invoker = true) as
with vigente as materialized (
  select distinct on (tenant_id, conta) tenant_id, conta, linha
  from app.mapa_conta_linha
  order by tenant_id, conta, id desc
), conta_saldo as (
  select distinct tenant_id, empresa_id, conta
  from staging.saldo_contabil_empresa_mensal
)
select c.tenant_id, c.empresa_id, c.conta, m.linha
from conta_saldo c
left join lateral (
  select v.linha
  from vigente v
  where v.tenant_id = c.tenant_id and v.linha is not null and (c.conta = v.conta or c.conta like v.conta || '.%')
  order by length(v.conta) desc
  limit 1
) m on true;

grant select on marts.mapa_conta_efetivo to authenticated;

-- Plano de contas do tenant (uma linha por conta, distinta entre empresas) com a linha vigente própria e a
-- efetiva, para a tela de mapeamento. Só diretor e financeiro; sem usuário (dona do banco) lê tudo.
create view marts.mapa_contas with (security_invoker = true) as
with plano as (
  select distinct on (tenant_id, conta) tenant_id, conta, conta_reduzida, nome, grupo, analitica
  from staging.plano_conta
  order by tenant_id, conta, empresa_id
), vigente as materialized (
  select distinct on (tenant_id, conta) tenant_id, conta, linha, criado_em, criado_por
  from app.mapa_conta_linha
  order by tenant_id, conta, id desc
)
select p.tenant_id, p.conta, p.conta_reduzida, p.nome, p.grupo, p.analitica,
  v.linha,
  ef.linha as linha_efetiva,
  (select string_agg(distinct l.demonstrativo, ', ' order by l.demonstrativo)
   from marts.linha_relatorio l where l.linha = ef.linha) as demonstrativos,
  v.criado_em as atualizado_em,
  v.criado_por as atualizado_por
from plano p
left join vigente v on v.tenant_id = p.tenant_id and v.conta = p.conta
left join lateral (
  select x.linha
  from vigente x
  where x.tenant_id = p.tenant_id and x.linha is not null and (p.conta = x.conta or p.conta like x.conta || '.%')
  order by length(x.conta) desc
  limit 1
) ef on true
where (select auth.uid()) is null or (select app.perfil_atual()) in ('diretor', 'financeiro');

grant select on marts.mapa_contas to authenticated;

-- Grava um lote de mapeamentos e devolve quantas linhas entraram. Itens: [{"conta": "1.1.1.02.0001",
-- "linha": "bancos"}]; linha nula ou ausente tira o mapa próprio. Confere usuário, segundo fator e perfil antes
-- de olhar o conteúdo, para o erro de permissão (42501) nunca depender do que foi mandado.
create function app.gravar_mapa_conta_linha(p_itens jsonb) returns integer
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_tenant uuid := app.tenant_atual();
  v_linhas integer;
begin
  if auth.uid() is null or v_tenant is null then
    raise exception 'gravação exige usuário ligado a uma construtora' using errcode = '42501';
  end if;
  if not app.segundo_fator_cumprido() then
    raise exception 'gravação exige o segundo fator' using errcode = '42501';
  end if;
  if coalesce(app.perfil_atual(), '') not in ('diretor', 'financeiro') then
    raise exception 'só diretor e financeiro gravam o mapa de contas' using errcode = '42501';
  end if;

  if p_itens is null or jsonb_typeof(p_itens) <> 'array' then
    raise exception 'itens precisam ser uma lista' using errcode = '22023';
  end if;
  if jsonb_array_length(p_itens) > 500 then
    raise exception 'no máximo 500 itens por gravação' using errcode = '22023';
  end if;
  if jsonb_array_length(p_itens) = 0 then
    return 0;
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_itens) as item
    where jsonb_typeof(item) <> 'object'
       or jsonb_typeof(item -> 'conta') <> 'string'
       or jsonb_typeof(item -> 'linha') not in ('string', 'null')
  ) then
    raise exception 'item sem conta ou com linha inválida' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_itens) as item
    where not exists (
      select 1 from staging.plano_conta p
      where p.tenant_id = v_tenant and p.conta = item ->> 'conta'
    )
  ) then
    raise exception 'conta fora do plano de contas' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_itens) as item
    where item ->> 'linha' is not null
      and not exists (
        select 1 from marts.linha_relatorio l
        where l.linha = item ->> 'linha' and l.tipo = 'conta' and l.grupo_conta = left(item ->> 'conta', 1)
      )
  ) then
    raise exception 'linha fora do catálogo ou de outro grupo de conta' using errcode = '22023';
  end if;

  -- Duas gravações simultâneas do mesmo tenant disputariam a ordem dos ids, que define a vigente.
  perform pg_advisory_xact_lock(hashtextextended('mapa_conta_linha:' || v_tenant::text, 0));

  -- Item igual ao vigente não vira versão nova, para a tabela só crescer quando o mapa muda de fato.
  insert into app.mapa_conta_linha (tenant_id, conta, linha, criado_por, origem)
  select v_tenant, item ->> 'conta', item ->> 'linha', auth.uid(), 'painel'
  from jsonb_array_elements(p_itens) with ordinality as itens (item, posicao)
  where (item ->> 'linha') is distinct from (
    select m.linha from app.mapa_conta_linha m
    where m.tenant_id = v_tenant and m.conta = item ->> 'conta'
    order by m.id desc limit 1
  )
  order by posicao;

  get diagnostics v_linhas = row_count;
  return v_linhas;
end;
$$;

revoke execute on function app.gravar_mapa_conta_linha(jsonb) from public, anon;
grant execute on function app.gravar_mapa_conta_linha(jsonb) to authenticated;
revoke execute on function app.validar_mapa_conta_linha() from public, anon, authenticated;
