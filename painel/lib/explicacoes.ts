// Uma frase por indicador, dizendo o que soma e o que fica de fora. As regras seguem as views de marts
// e a seção 8 do contrato de dados (docs/financeiro/contrato_dados.md).
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
  caixa_atual:
    "Só o realizado: tudo que já entrou dos compradores e do banco menos tudo que já foi pago, desde o início da obra. Não conta o que está a receber nem a pagar. Não é saldo bancário: não inclui aplicações, empréstimos nem dinheiro de outras obras.",
  exposicao_maxima:
    "Maior saldo negativo acumulado no fluxo da obra: o dinheiro próprio que ela exige no pior mês. Entrada vencida não conta; saída vencida conta.",
  resultado_contratado:
    "Tudo que entrou e vai entrar dos contratos, inclusive o vencido, menos o maior valor entre o orçamento e o custo lançado. Estoque não entra.",
  resultado_projetado:
    "O resultado contratado mais o estoque a preço de hoje, como se todas as unidades fossem vendidas pela tabela atual.",
  vgv_contratado_ativo:
    "Soma do valor dos contratos de venda ativos. Contrato distratado não entra. É venda, não é dinheiro recebido nem receita do DRE.",
  contratos: "Contratos de venda ativos e distratados na origem, contados um a um.",
  recebido_periodo:
    "Entradas de caixa pela data do recebimento dentro do período escolhido, separadas em entrada direta e financiamento. Estorno já descontado.",
  recebido_acumulado:
    "Tudo que já entrou desde o início da obra, separado em entrada direta e financiamento, pela data do recebimento.",
  recebido_financiamento: "Repasse do banco já recebido pelo financiamento dos compradores, pela data do recebimento.",
  vencido_financiamento:
    "Parcelas de financiamento com vencimento passado e ainda não pagas pelo banco. Não entram no caixa previsto.",
  vencido_receitas:
    "Parcelas com vencimento antes da data de referência e ainda em aberto, do comprador e do financiamento, mostradas separadas. Não entram no caixa previsto.",
  a_vencer_direto:
    "Saldo das parcelas dos compradores que vencem da data de referência em diante. Contrato distratado não entra.",
  a_vencer_financiamento: "Saldo das parcelas de financiamento que vencem da data de referência em diante.",
  a_vencer_receitas:
    "Saldo das parcelas que vencem da data de referência em diante, do comprador e do financiamento. Contrato distratado não entra.",
  previsto_proximo_mes_direto:
    "Parcelas dos compradores que vencem no mês seguinte ao da data de referência. Parcela já vencida não entra.",
  previsto_proximo_mes_financiamento:
    "Parcelas de financiamento que vencem no mês seguinte ao da data de referência. Parcela já vencida não entra.",
  previsto_proximo_mes:
    "Parcelas a vencer no mês seguinte ao da data de referência, do comprador e do financiamento. Parcela já vencida não entra.",
  saldo_distratado:
    "O que ficou em aberto em contratos distratados. Fica fora da carteira; o que esses compradores pagaram antes continua no recebido.",
  previsto_contratual:
    "Valor original das parcelas pelo mês do vencimento. Parcela de contrato distratado e parcela baixada sem recebimento (renegociada) não entram.",
  carteira_situacao:
    "Quitada, vencida, a vencer, cancelada por distrato ou baixada sem recebimento (renegociada ou cancelada na origem).",
  receita_bruta:
    "Receita das vendas reconhecida no mês pelo percentual de conclusão da obra. Só aparece depois que o financeiro valida o critério.",
  deducoes: "Tributos sobre a receita lançados no mês de competência dos títulos.",
  receita_liquida: "Receita bruta reconhecida menos as deduções e os tributos sobre a receita.",
  custo_imovel_vendido:
    "Parte do custo da obra que corresponde às unidades vendidas, pelo mesmo critério da receita. O resto do custo fica em estoque.",
  resultado_bruto: "Receita líquida menos o custo reconhecido dos imóveis vendidos.",
  despesas_comerciais: "Corretagem e marketing pela competência dos títulos.",
  despesas_administrativas: "Despesas da empresa pela competência dos títulos, inclusive as sem obra.",
  resultado_financeiro:
    "Receitas financeiras menos juros e encargos lançados. Rendimento de aplicação não entra: o extrato bancário não é carregado.",
  resultado_gerencial:
    "Resultado bruto menos despesas comerciais e administrativas, mais o resultado financeiro. Não é o lucro contábil: não inclui imposto de renda nem ajustes do contador.",
  custo_obra_incorrido: "Títulos de custo de obra pela competência. Vai para o estoque e não é despesa do mês.",
  fora_do_resultado:
    "Aportes, empréstimos, crédito à produção, amortizações, transferências e devoluções de distrato. Mexem no caixa, não no resultado.",
  sem_categoria:
    "Lançamentos cuja conta de origem ainda não foi classificada. Não entram em nenhuma linha do resultado até alguém classificar.",
  sem_data_competencia:
    "Títulos que a origem mandou sem data de emissão. Ficam fora dos meses até a origem informar a data.",
  cobertura:
    "Parte do valor lançado no período que já tem categoria. Abaixo de 100%, o resultado pode mudar quando as contas pendentes forem classificadas.",
  pendencia_classificacao:
    "Conta que apareceu na origem e ainda não tem categoria gerencial. O impacto é a parte do valor do mesmo tipo de lançamento que ela carrega.",
  poc: "Custo de obra lançado até o mês dividido pelo custo total estimado (o maior entre o orçamento e o custo já lançado).",
  fracao_vendida:
    "Unidades com contrato ativo dividido pelo total de unidades da obra. Premissa: todas as unidades pesam igual.",
  orcamento_vigente: "Soma dos itens do orçamento que está na origem hoje. A origem não guarda o orçamento original.",
  orcamento_original: "Orçamento aprovado no início da obra. Indisponível: a origem só guarda o orçamento vigente.",
  custo_lancado:
    "Títulos da obra, pagos ou não, pelo valor original. Parte de título rateado entre obras entra só pela fatia desta obra.",
  desembolsado: "Pagamentos da obra, pela data do pagamento.",
  em_aberto_vencido: "Saldo de títulos com vencimento passado. Entra no caixa previsto do mês de referência.",
  em_aberto_a_vencer: "Saldo de títulos que vencem da data de referência em diante.",
  ajuste_baixa:
    "Diferença entre o custo lançado e o que foi pago ou está em aberto: descontos obtidos menos juros e multas pagos.",
  remanescente_sem_titulo:
    "Parte do orçamento vigente que ainda não virou título. Nunca negativo. Não soma com os títulos: é o que falta lançar.",
  estimativa_conclusao: "Custo lançado mais o orçamento sem título.",
  desvio: "Quanto a estimativa até a conclusão passa do orçamento vigente. Zero quando está dentro.",
  compromissos_nao_faturados:
    "Pedidos de compra e contratos de empreiteiro ainda sem título. Indisponível: a origem ainda não é lida para isso.",
  lancado_competencia:
    "Títulos pelo mês de competência (emissão), pagos ou não. Título sem data de emissão fica de fora.",
  pago_periodo: "Pagamentos feitos dentro do período, pela data do pagamento.",
  despesas_sem_obra:
    "Títulos que a origem mandou sem obra. Ficam num grupo próprio, visível para diretor e financeiro, e entram no consolidado.",
  exposicao_maxima_projetada:
    "O pico da necessidade de aporte na projeção. Parcial quando há custo sem título não distribuído.",
} as const;

export type ChaveExplicacao = keyof typeof explicacoes;
