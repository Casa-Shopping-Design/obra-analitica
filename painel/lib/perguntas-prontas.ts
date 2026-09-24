// Perguntas prontas do assistente. O campo sql é o texto revisado por João e vira o contrato do PT-07;
// até lá quem executa é a função de mesmo id em lib/consultas/perguntas-prontas.ts, que precisa
// devolver exatamente o que este sql devolveria. Mudou um, muda o outro.

export type FormatoColuna = "texto" | "real" | "inteiro" | "mes" | "data" | "area";

export type ColunaResposta = { chave: string; rotulo: string; formato: FormatoColuna };

export type PerguntaPronta = {
  id: string;
  pergunta: string;
  sql: string;
  colunas: readonly ColunaResposta[];
  semResultado: string;
};

export const perguntasProntas = [
  {
    id: "repasse-parque-6-meses",
    pergunta: "Quanto entra de repasse na Parque das Águas nos próximos 6 meses?",
    sql: "select c.nome as obra, f.competencia, f.repasse_previsto from marts.fluxo_caixa_mensal f join app.centro_custo c on c.id = f.centro_custo_id where c.nome ilike '%parque%' and f.competencia between date_trunc('month', current_date) and current_date + interval '6 months' order by f.competencia",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "competencia", rotulo: "Mês", formato: "mes" },
      { chave: "repasse_previsto", rotulo: "Repasse previsto", formato: "real" },
    ],
    semResultado: "Nenhum repasse previsto para a Parque das Águas nos próximos 6 meses, ou a obra não está liberada para o seu perfil.",
  },
  {
    id: "mes-mais-negativo-aurora",
    pergunta: "Em que mês o caixa da Aurora fica mais negativo?",
    sql: "select c.nome as obra, f.competencia, f.saldo_acumulado from marts.fluxo_caixa_mensal f join app.centro_custo c on c.id = f.centro_custo_id where c.nome ilike '%aurora%' order by f.saldo_acumulado limit 1",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "competencia", rotulo: "Mês", formato: "mes" },
      { chave: "saldo_acumulado", rotulo: "Saldo acumulado", formato: "real" },
    ],
    semResultado: "A Residencial Aurora não tem fluxo de caixa carregado ou não está liberada para o seu perfil.",
  },
  {
    id: "a-receber-aurora",
    pergunta: "Quanto a Aurora ainda vai receber do banco e quanto dos compradores?",
    sql: "select obra, a_receber_repasse, repasse_atrasado, a_receber_direto, vencido_direto from marts.posicao_financeira_obra where obra ilike '%aurora%'",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "a_receber_repasse", rotulo: "Repasse a receber", formato: "real" },
      { chave: "repasse_atrasado", rotulo: "Repasse atrasado", formato: "real" },
      { chave: "a_receber_direto", rotulo: "A receber do comprador", formato: "real" },
      { chave: "vencido_direto", rotulo: "Vencido do comprador", formato: "real" },
    ],
    semResultado: "A Residencial Aurora não está liberada para o seu perfil.",
  },
  {
    id: "exposicao-maxima",
    pergunta: "Quanto dinheiro próprio cada obra precisa no pior momento?",
    sql: "select obra, exposicao_maxima from marts.posicao_financeira_obra order by exposicao_maxima desc",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "exposicao_maxima", rotulo: "Exposição máxima", formato: "real" },
    ],
    semResultado: "Nenhuma obra liberada para o seu perfil.",
  },
  {
    id: "estouro-orcamento",
    pergunta: "Alguma obra estourou o orçamento?",
    sql: "select obra, custo_orcado, pago, a_pagar, estouro_orcamento from marts.posicao_financeira_obra where estouro_orcamento > 0 order by estouro_orcamento desc",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "custo_orcado", rotulo: "Custo orçado", formato: "real" },
      { chave: "pago", rotulo: "Pago", formato: "real" },
      { chave: "a_pagar", rotulo: "A pagar", formato: "real" },
      { chave: "estouro_orcamento", rotulo: "Estouro", formato: "real" },
    ],
    semResultado: "Nenhuma das obras liberadas para o seu perfil passou do orçamento.",
  },
  {
    id: "distratos-ano",
    pergunta: "Quantos distratos houve neste ano?",
    sql: "select c.nome as obra, v.competencia, v.distratos from marts.vso_mensal v join app.centro_custo c on c.id = v.centro_custo_id where v.competencia >= date_trunc('year', current_date) and v.distratos > 0 order by v.competencia, c.nome",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "competencia", rotulo: "Mês", formato: "mes" },
      { chave: "distratos", rotulo: "Distratos", formato: "inteiro" },
    ],
    semResultado: "Nenhum distrato neste ano nas obras liberadas para o seu perfil.",
  },
  {
    id: "unidades-disponiveis",
    pergunta: "Quantas unidades disponíveis cada obra tem hoje, por tipologia?",
    sql: "select c.nome as obra, e.tipologia, e.disponiveis, e.total from marts.estoque_atual e join app.centro_custo c on c.id = e.centro_custo_id order by c.nome, e.tipologia",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "tipologia", rotulo: "Tipologia", formato: "texto" },
      { chave: "disponiveis", rotulo: "Disponíveis", formato: "inteiro" },
      { chave: "total", rotulo: "Total de unidades", formato: "inteiro" },
    ],
    semResultado: "Nenhuma unidade cadastrada nas obras liberadas para o seu perfil.",
  },
  {
    id: "preco-unidade-3q-0202-parque",
    pergunta: "Quanto custa hoje a unidade 3Q-0202 da Parque das Águas?",
    sql: "select c.nome as obra, m.unidade, m.valor, m.valor_m2, m.indice_referencia from marts.mapa_unidades m join app.centro_custo c on c.id = m.centro_custo_id where c.nome ilike '%parque%' and m.unidade = '3Q-0202'",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "unidade", rotulo: "Unidade", formato: "texto" },
      { chave: "valor", rotulo: "Valor hoje", formato: "real" },
      { chave: "valor_m2", rotulo: "Valor por m²", formato: "real" },
      { chave: "indice_referencia", rotulo: "Índice de", formato: "data" },
    ],
    semResultado: "A unidade 3Q-0202 não foi encontrada ou a Parque das Águas não está liberada para o seu perfil.",
  },
  {
    id: "disponiveis-aurora",
    pergunta: "Quais unidades da Aurora estão disponíveis e quanto vale cada uma hoje?",
    sql: "select c.nome as obra, m.unidade, m.tipologia, m.area_privativa, m.valor from marts.mapa_unidades m join app.centro_custo c on c.id = m.centro_custo_id where c.nome ilike '%aurora%' and m.situacao = 'disponivel' order by m.tipologia, m.unidade",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "unidade", rotulo: "Unidade", formato: "texto" },
      { chave: "tipologia", rotulo: "Tipologia", formato: "texto" },
      { chave: "area_privativa", rotulo: "Área privativa", formato: "area" },
      { chave: "valor", rotulo: "Valor hoje", formato: "real" },
    ],
    semResultado: "Nenhuma unidade disponível na Residencial Aurora, ou a obra não está liberada para o seu perfil.",
  },
  {
    id: "cobertura-parque",
    pergunta: "Quantas vendas faltam para o VGV da Parque das Águas cobrir o orçamento?",
    sql: "select obra, custo_orcado, vgv_contratado, unidades_para_cobrir from marts.cobertura_orcamento_obra where obra ilike '%parque%'",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "custo_orcado", rotulo: "Custo orçado", formato: "real" },
      { chave: "vgv_contratado", rotulo: "VGV contratado", formato: "real" },
      { chave: "unidades_para_cobrir", rotulo: "Vendas que faltam", formato: "inteiro" },
    ],
    semResultado: "A Parque das Águas não está liberada para o seu perfil.",
  },
  {
    id: "a-receber-banco",
    pergunta: "Quanto cada obra ainda vai receber do banco?",
    sql: "select obra, a_receber_repasse, repasse_atrasado from marts.posicao_financeira_obra order by a_receber_repasse desc",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "a_receber_repasse", rotulo: "Repasse a receber", formato: "real" },
      { chave: "repasse_atrasado", rotulo: "Repasse atrasado", formato: "real" },
    ],
    semResultado: "Nenhuma obra liberada para o seu perfil.",
  },
  {
    id: "mais-vencido",
    pergunta: "Qual obra tem mais dinheiro vencido a receber dos compradores?",
    sql: "select obra, vencido_direto, repasse_atrasado from marts.posicao_financeira_obra order by vencido_direto desc",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "vencido_direto", rotulo: "Vencido do comprador", formato: "real" },
      { chave: "repasse_atrasado", rotulo: "Repasse atrasado", formato: "real" },
    ],
    semResultado: "Nenhuma obra liberada para o seu perfil.",
  },
  {
    id: "estoque-preco-hoje",
    pergunta: "Quanto vale o estoque de cada obra a preço de hoje?",
    sql: "select obra, estoque_a_vender from marts.posicao_financeira_obra order by estoque_a_vender desc",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "estoque_a_vender", rotulo: "Estoque a preço de hoje", formato: "real" },
    ],
    semResultado: "Nenhuma obra liberada para o seu perfil.",
  },
] as const satisfies readonly PerguntaPronta[];

type PerguntaDoCatalogo = (typeof perguntasProntas)[number];
export type IdPerguntaPronta = PerguntaDoCatalogo["id"];

export function buscarPerguntaPronta(id: string | undefined): PerguntaDoCatalogo | undefined {
  return perguntasProntas.find((pergunta) => pergunta.id === id);
}
