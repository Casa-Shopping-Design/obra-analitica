// Catalogo semantico das views que o assistente pode consultar.
// E o unico lugar de onde a LLM aprende nomes de tabela e coluna.

export type ViewCatalogo = {
  nome: string;
  descricao: string;
  colunas: string[];
  exemplos: { pergunta: string; sql: string }[];
};

export const catalogoViews: ViewCatalogo[] = [
  {
    nome: "marts.consolidado_centro_custo",
    descricao: "Totais por obra: receita contratada, recebida, saldo a receber, custo orcado, realizado e saldo a pagar.",
    colunas: ["centro_custo_id", "obra", "receita_contratada", "receita_recebida", "saldo_a_receber", "custo_orcado", "custo_realizado", "saldo_a_pagar"],
    exemplos: [
      { pergunta: "Qual o saldo a receber total da Aurora?", sql: "select obra, saldo_a_receber from marts.consolidado_centro_custo where obra ilike '%aurora%'" },
      { pergunta: "Qual o custo realizado da Parque das Aguas em relacao ao orcado?", sql: "select obra, custo_realizado, custo_orcado, round(custo_realizado / nullif(custo_orcado,0), 4) as pct from marts.consolidado_centro_custo where obra ilike '%parque%'" },
    ],
  },
  {
    nome: "marts.fluxo_caixa_mensal",
    descricao: "Receita e desembolso por obra e mes (competencia), separando receita direta de repasse bancario, previsto e realizado.",
    colunas: ["centro_custo_id", "competencia", "receita_direta_prevista", "receita_direta_realizada", "repasse_previsto", "repasse_realizado", "desembolso_previsto", "desembolso_realizado"],
    exemplos: [
      { pergunta: "Quanto entra de repasse na Parque das Aguas nos proximos 6 meses?", sql: "select sum(f.repasse_previsto) from marts.fluxo_caixa_mensal f join app.centro_custo c on c.id = f.centro_custo_id where c.nome ilike '%parque%' and f.competencia between date_trunc('month', current_date) and current_date + interval '6 months'" },
      { pergunta: "Em que mes o desembolso da Aurora foi maior?", sql: "select f.competencia, f.desembolso_realizado from marts.fluxo_caixa_mensal f join app.centro_custo c on c.id = f.centro_custo_id where c.nome ilike '%aurora%' order by f.desembolso_realizado desc limit 1" },
    ],
  },
  {
    nome: "marts.vso_mensal",
    descricao: "Vendas, distratos e VGV vendido por obra e mes.",
    colunas: ["centro_custo_id", "competencia", "vendas", "distratos", "vgv_vendido"],
    exemplos: [
      { pergunta: "Qual foi a VSO media da Aurora nos ultimos 6 meses?", sql: "select avg(v.vendas) from marts.vso_mensal v join app.centro_custo c on c.id = v.centro_custo_id where c.nome ilike '%aurora%' and v.competencia >= current_date - interval '6 months'" },
      { pergunta: "Quantos distratos houve em 2026?", sql: "select sum(distratos) from marts.vso_mensal where competencia >= '2026-01-01'" },
    ],
  },
  {
    nome: "marts.estoque_atual",
    descricao: "Unidades disponiveis, reservadas e vendidas por obra e tipologia.",
    colunas: ["centro_custo_id", "tipologia", "disponiveis", "reservadas", "vendidas", "total"],
    exemplos: [
      { pergunta: "Quantas unidades disponiveis existem hoje no total?", sql: "select sum(disponiveis) from marts.estoque_atual" },
    ],
  },
  {
    nome: "marts.break_even_obra",
    descricao: "Ponto de equilibrio por obra: custo total, VGV vendido, percentual atingido, unidades faltantes e meses pelo ritmo atual.",
    colunas: ["centro_custo_id", "obra", "custo_total", "vgv_vendido", "ticket_medio", "vso_media_6m", "pct_atingido", "unidades_faltantes", "meses_para_break_even"],
    exemplos: [
      { pergunta: "Quantas unidades faltam para a Parque das Aguas atingir o ponto de equilibrio?", sql: "select obra, unidades_faltantes, meses_para_break_even from marts.break_even_obra where obra ilike '%parque%'" },
    ],
  },
];
