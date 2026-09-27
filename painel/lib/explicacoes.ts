// Uma frase por indicador, dizendo o que soma e o que fica de fora. As regras seguem as views
// marts.posicao_financeira_obra e marts.fluxo_caixa_mensal (migrations 0005 e 0007).
export const explicacoes = {
  recebido_direto: "O que os compradores já pagaram direto à construtora, pela data do pagamento.",
  recebido_repasse: "O que o banco já pagou de repasse do financiamento dos compradores.",
  a_receber_direto:
    "Parcelas dos compradores que ainda vão vencer. Contrato distratado não entra; parcela vencida fica em Vencido do comprador.",
  a_receber_repasse:
    "Repasse do banco que ainda vai vencer. Contrato distratado não entra; repasse vencido fica em Repasse atrasado.",
  vencido_direto: "Parcelas dos compradores que venceram e não foram pagas. Não entram no saldo projetado do mês.",
  repasse_atrasado: "Repasse do banco que já venceu e não foi pago. Não entra no saldo projetado do mês.",
  vencido:
    "Parcelas vencidas e não pagas, do comprador e do banco, mostradas separadas. Nenhuma das duas entra no saldo projetado.",
  estoque_a_vender:
    "Unidades disponíveis, reservadas e em proposta, pelo preço de tabela de hoje. Unidade vendida não entra.",
  pago: "Títulos da obra já pagos, pela data do pagamento.",
  a_pagar: "Títulos da obra lançados e ainda não pagos, inclusive os vencidos.",
  custo_orcado: "Soma dos itens do orçamento da obra.",
  custo_a_incorrer: "Parte do orçamento que ainda não virou título a pagar. Nunca fica negativo.",
  estouro_orcamento: "Quanto o custo lançado (pago mais a pagar) passou do orçamento. Zero quando está dentro.",
  caixa_atual: "Tudo que já entrou, do comprador e do banco, menos tudo que já foi pago. Não conta o que está a receber ou a pagar.",
  exposicao_maxima:
    "Maior saldo negativo acumulado no fluxo da obra: o dinheiro próprio que ela exige no pior mês. Entrada vencida não conta; saída vencida conta.",
  resultado_contratado:
    "Tudo que entrou e vai entrar dos contratos, inclusive o vencido, menos o maior valor entre o orçamento e o custo lançado. Estoque não entra.",
  vgv_total:
    "Valor geral de vendas: as unidades vendidas pelo valor do contrato mais o estoque pelo preço de tabela de hoje. Unidade fora de venda não entra.",
  vgv_vendido: "Soma dos contratos de venda ativos das unidades vendidas. Contrato distratado não entra.",
  resultado_projetado:
    "O resultado contratado mais o estoque a preço de hoje, como se todas as unidades fossem vendidas pela tabela atual.",
} as const;

export type ChaveExplicacao = keyof typeof explicacoes;
