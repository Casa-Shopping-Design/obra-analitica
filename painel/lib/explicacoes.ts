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
  exposicao_carteira:
    "Maior saldo negativo acumulado das obras somadas mês a mês. É menor que a soma das exposições de cada obra quando os piores meses não coincidem.",
  unidades_estoque: "Unidades disponíveis, reservadas e em proposta. Vendida e fora de venda não entram.",
  ritmo_vendas:
    "Média de vendas menos distratos por mês nos últimos seis meses, contando mês sem venda como zero.",
  meses_para_vender_estoque:
    "Unidades em estoque divididas pelo ritmo dos últimos seis meses. É projeção no ritmo recente, não prazo garantido.",
  cobertura_orcamento:
    "Quanto do custo orçado os contratos ativos já cobrem. Não é caixa: ignora quando o dinheiro entra e sai.",
  vso: "Venda sobre oferta: vendas menos distratos do mês divididas pelas unidades em estoque no início do mês.",
  receita_simulada:
    "Valor das unidades em estoque pela tabela de hoje, com o desconto escolhido. Entra em parcelas até a entrega e no repasse das chaves.",
  pct_vgv_vendido: "Parte do VGV que já tem contrato de venda ativo. Contrato distratado não entra.",
  vso_12m:
    "Vendas menos distratos dos últimos 12 meses divididas pelas unidades em estoque no começo desse período.",
  estoque_obra:
    "Unidades disponíveis, reservadas e em proposta, e quanto valem pela tabela de hoje. Vendida e fora de venda não entram.",
  margem_projetada: "Resultado projetado dividido pelo VGV. Serve para comparar obras de tamanhos diferentes.",
  pct_inadimplencia:
    "Vencido e não pago dos compradores sobre tudo o que eles já pagaram, vão pagar e devem. Acima de 5% vira alerta.",
  avanco_fisico_financeiro:
    "Pago sobre o orçamento menos obra medida sobre o planejado, no mês atual. Positivo é pagamento à frente da obra; acima de 10 pontos vira alerta.",
  alertas_obra:
    "Alertas abertos com os dados da última carga: estouro do orçamento, repasse atrasado, inadimplência alta, pago à frente do físico e estoque que não acaba até a entrega.",
  exposicao_simulada:
    "Maior saldo negativo acumulado da obra com as vendas simuladas somadas ao fluxo de hoje. Custo ainda não lançado como título não entra.",
  dre_viabilidade: "O que o estudo de viabilidade vigente previu para a linha. É o número de partida, digitado no estudo.",
  dre_pct_viabilidade: "A linha do estudo sobre o VGV líquido do estudo.",
  dre_apropriado:
    "O que já entrou no resultado até o último mês fechado: receita e custo das unidades vendidas, pelo andamento da obra, como o ERP fecha no mapa imobiliário. Não é caixa.",
  dre_a_apropriar:
    "O que já está contratado e ainda não entrou no resultado: vendas assinadas que faltam apropriar e títulos lançados que faltam incorrer.",
  dre_a_contratar:
    "O que ainda não tem contrato. No VGV, unidades em estoque pelo preço de tabela de hoje; na construção, o orçamento que ainda não virou título. Linha sem realizado carregado repete o estudo.",
  dre_a_realizar: "A apropriar mais a contratar: o que falta acontecer até o fim da obra.",
  dre_tendencia:
    "Apropriado mais a apropriar mais a contratar. É o que a linha vai dar no fim da obra se nada mudar.",
  dre_pct_tendencia: "A linha na tendência sobre o VGV líquido da tendência.",
  dre_desvio:
    "Tendência menos viabilidade. Favorável quando ajuda o resultado (receita acima ou custo abaixo do estudo), desfavorável quando atrapalha.",
  dre_desvio_pct: "O desvio sobre o valor do estudo. Sem base quando o estudo previu zero para a linha.",
  margem_operacional_viabilidade: "Lucro operacional do estudo sobre o VGV líquido do estudo.",
  margem_operacional_tendencia: "Lucro operacional da tendência sobre o VGV líquido da tendência.",
  desvio_margem_operacional:
    "Margem na tendência menos margem no estudo, em pontos percentuais. Abaixo do estudo quer dizer que a obra vai render menos que o previsto.",
  tendencia_margem_mensal:
    "A margem operacional que a carga gravou em cada mês. A linha cheia é a tendência daquele mês; a tracejada é o estudo vigente no mesmo mês. A série começa no mês da primeira carga.",
  vgv_bruto_resultado:
    "VGV de hoje das obras com estudo de viabilidade: unidades vendidas pelo valor do contrato mais o estoque pelo preço de tabela atual. É a tendência do VGV bruto na DRE.",
  pct_vendido_resultado: "VGV vendido sobre o VGV de hoje, só nas obras com estudo de viabilidade. Contrato distratado não entra.",
  poc_resultado:
    "Receita apropriada sobre o VGV vendido: quanto das vendas já entrou no resultado pelo andamento da obra, até o último mês fechado no ERP.",
  margem_operacional_viabilidade_carteira:
    "Lucro operacional do estudo somado sobre o VGV líquido do estudo somado, nas obras com estudo. Não é a média das margens de cada obra.",
  margem_operacional_tendencia_carteira:
    "Lucro operacional da tendência somado sobre o VGV líquido da tendência somado. A nota compara com a margem do estudo, em pontos percentuais.",
  lucro_operacional_tendencia:
    "VGV líquido menos custo das vendas e despesas, na tendência: o que as obras vão dar no fim se nada mudar.",
  custo_apropriado:
    "Custo das vendas que já entrou no resultado até o último mês fechado, como o ERP fecha no mapa imobiliário. Não é o que foi pago.",
  recebido_acumulado:
    "Tudo o que já entrou em caixa, do comprador e do banco, nas obras com estudo. É caixa, não receita apropriada.",
  vgv_total_imposto:
    "VGV de hoje da obra: unidades vendidas pelo valor do contrato mais o estoque pelo preço de tabela atual. É a tendência do VGV bruto na DRE.",
  imposto_receita_apropriada:
    "Alíquota informada sobre a receita que já entrou no resultado pelo andamento da obra, até o último mês fechado no ERP.",
  imposto_recebimento: "Alíquota informada sobre tudo o que já entrou em caixa, do comprador e do banco.",
  imposto_diferido:
    "Imposto sobre os recebimentos menos imposto sobre a receita apropriada. Negativo quando a receita apropriada passou do que já entrou em caixa.",
  imposto_vgv_estoque: "Alíquota informada sobre as unidades em estoque, pelo preço de tabela de hoje.",
  imposto_receita_a_apropriar:
    "Alíquota informada sobre as vendas assinadas que ainda não entraram no resultado.",
  imposto_vgv_total: "Alíquota informada sobre o VGV total. É a tendência da linha de impostos na DRE de viabilidade.",
  imposto_a_realizar:
    "Imposto sobre a receita a apropriar mais o imposto sobre o estoque: o que ainda vai incidir até o fim da obra.",
  aliquota_imposto:
    "Alíquota única informada pela diretoria para a obra e aplicada sobre todas as bases desta tela. Não separa os tributos nem segue regra de regime.",
} as const;

export type ChaveExplicacao = keyof typeof explicacoes;
