// Textos das telas de fluxo, planejamento, financiamento e das perguntas novas do assistente.
// Erro do banco nunca chega cru à tela: a ação troca o código por uma destas frases.

export const mensagensPlanejamento = {
  fluxo: {
    semObras: "Nenhuma obra liberada para o seu perfil. Peça acesso ao administrador da construtora.",
    semProjecao: "Esta obra ainda não tem entradas nem saídas para projetar.",
    naoESaldoBancario:
      "Caixa gerado acumulado é o que entrou e vai entrar menos o que saiu e vai sair, desde o início da obra. Não é saldo bancário: não inclui aplicações, empréstimos nem dinheiro de outras obras.",
    consolidadoPorObra:
      "O consolidado mostra cada obra numa linha. O mês a mês abre na obra: somar caixas de obras diferentes supõe que o dinheiro de uma cobre a outra, e o banco ainda não tem essa visão.",
    custoNaoDistribuido:
      "Parte do orçamento ainda não virou título e não tem premissa de meses. Ela fica fora do mês a mês e deixa o aporte parcial: o valor real tende a ser maior.",
    semOrcamento: "A obra não tem orçamento carregado; o custo que falta lançar não é conhecido e o aporte é parcial.",
  },
  simulacao: {
    realizadoIntocado:
      "A simulação parte da projeção de hoje e não grava nada: o realizado, a projeção salva e as metas continuam como estão.",
    corrijaCampos: "Confira os campos marcados antes de simular.",
    indisponivel: "Não foi possível simular agora. Confira as premissas e tente de novo em alguns minutos.",
    premissaRecusada: "O banco recusou uma das premissas. Confira os valores e tente de novo.",
    vendasLimitadas: "Em algum mês a venda pedida passou do estoque; o simulador vendeu só o que havia.",
    campanhaHipotese: "Custo e vendas de campanha são hipótese do cenário, não compromisso lançado.",
  },
  acao: {
    semSessao: "Sua sessão expirou. Entre de novo para registrar.",
    semPermissao: "Só o diretor e o financeiro podem registrar esta informação. Peça a um deles.",
    obraNaoEncontrada: "Obra não encontrada ou sem permissão para o seu perfil.",
    registroNaoEncontrado: "Registro não encontrado ou sem permissão para o seu perfil.",
    recusadoPeloBanco: "O registro foi recusado: um dos valores não passa nas regras. Confira os campos e tente de novo.",
    duplicado: "Já existe um registro com esses dados. Confira o número ou o vínculo informado.",
    limiteOperacao:
      "A liberação foi recusada: a soma das liberações passaria do valor contratado da operação, ou o contrato do comprador não está ativo. Revise os valores.",
    indisponivel: "Não foi possível registrar agora. Tente de novo em alguns minutos.",
    corrijaCampos: "Confira os campos marcados.",
  },
  planejamento: {
    escolhaObra: "Escolha uma obra para ver o planejamento mês a mês, as metas e as versões.",
    semVisao: "Esta obra ainda não tem meses projetados.",
    semDesvios: "Nenhuma causa de desvio sustentada pelos dados nos meses mostrados.",
    semVersoesProjecao:
      "Nenhuma projeção registrada. Registre a primeira para ter um planejamento original de comparação.",
    semMetas: "Nenhuma meta registrada para esta obra.",
    semPremissa: "Nenhuma premissa de meses cadastrada para o custo sem título.",
    semPendenciasPosEntrega: "Nenhuma obra entregue com recebível, título ou liberação em aberto.",
    posEntregaGerencial:
      "Acompanhamento gerencial do que ainda está aberto depois da entrega das unidades. Não é encerramento contábil da obra: o fechamento continua com o contador.",
    versoesImutaveis:
      "Cada registro cria uma versão nova numerada. As anteriores ficam guardadas e não podem ser alteradas nem apagadas.",
    campanhaNoSimulador:
      "Campanha comercial entra só como hipótese dentro de um cenário do simulador, com custo e vendas adicionais marcados como hipótese.",
  },
  financiamento: {
    semOperacoes: "Nenhuma operação de crédito cadastrada para esta obra.",
    semContratos: "Nenhum contrato com financiamento nesta obra.",
    semMedicoes: "Nenhuma medição do banco cadastrada.",
    semLiberacoes: "Nenhuma liberação cadastrada.",
    semHistorico: "Nenhuma alteração registrada, ou o seu perfil não pode ver o histórico.",
    complementoManual:
      "A origem não traz medição nem liberação do banco. Tudo aqui é complemento manual, com fonte e autor, e nunca altera os dados carregados da origem.",
    semRateio:
      "Liberação da obra inteira ou de um lote não é repartida entre as unidades: a fonte é agregada e o painel não inventa essa divisão.",
    medicaoNaoECaixa: "Medição aprovada mostra o valor elegível; não é dinheiro recebido.",
  },
} as const;

// Frases dos indicadores das telas novas (seção 8 do contrato de dados).
export const explicacoesPlanejamento = {
  caixa_gerado_acumulado:
    "Soma, mês a mês, do que entrou e do que está previsto entrar menos o que saiu e vai sair. Entrada vencida fica fora; saída vencida entra. Não é saldo bancário.",
  caixa_gerado_conservador:
    "O mesmo caixa gerado acumulado sem o financiamento pendente, para ver o caixa se os compradores ainda sem aprovação do banco não forem liberados.",
  necessidade_aporte_acumulada:
    "Quanto dinheiro próprio a obra precisa ter colocado até o mês para o caixa gerado acumulado não ficar negativo.",
  aporte_incremental_mes: "Quanto a necessidade de aporte cresce no mês.",
  exposicao_maxima_projetada:
    "O pico da necessidade de aporte na projeção. Parcial quando há custo sem título não distribuído.",
  previsto_direto: "Parcelas dos compradores a vencer, pela data do vencimento. Parcela vencida não entra.",
  previsto_financiamento_elegivel:
    "Parcelas de financiamento de contratos já aprovados pelo banco ou com financiamento registrado na origem, pela data prevista.",
  previsto_financiamento_pendente:
    "Parcelas de financiamento de compradores sem aprovação do banco ou com pendência. Podem não entrar.",
  credito_producao_previsto:
    "Liberações do banco para a obra, cadastradas pelo financeiro e ainda não recebidas.",
  custo_sem_titulo_distribuido:
    "Orçamento sem título repartido nos meses pela premissa cadastrada, com fonte e autor.",
  custo_sem_titulo_nao_distribuido:
    "Orçamento sem título sem premissa de meses. Fica num total separado e deixa a necessidade de aporte parcial.",
  vencido_a_receber: "Parcelas vencidas e não pagas. Ficam fora do caixa previsto até serem recebidas.",
  a_pagar_vencido: "Títulos vencidos e não pagos. Entram no caixa do mês de referência, porque ainda vão sair.",
  saldo_liberavel: "Valor contratado com o banco menos a retenção e menos o que já foi liberado.",
  medido_elegivel: "Valor aceito pelo banco nas medições aprovadas. Não é dinheiro recebido.",
  simulacao: "Cenário com premissas escolhidas por você. Não altera o realizado nem a projeção salva.",
  diferenca_original_atual:
    "Caixa gerado acumulado de hoje menos o da projeção original do mês. Positivo é melhor que o planejado.",
} as const;

export type ChaveExplicacaoPlanejamento = keyof typeof explicacoesPlanejamento;

export type NaturezaNumero = "fato" | "previsao" | "simulacao";

// Rótulo que acompanha cada número na tela e no assistente.
export const rotulosNatureza: Record<NaturezaNumero, { rotulo: string; descricao: string }> = {
  fato: { rotulo: "Fato", descricao: "Já aconteceu: dinheiro recebido ou pago, venda assinada, registro feito." },
  previsao: {
    rotulo: "Previsão contratual",
    descricao: "Vem de parcelas, títulos, liberações e premissas cadastradas; pode mudar se alguém atrasar.",
  },
  simulacao: {
    rotulo: "Simulação",
    descricao: "Cenário com premissas escolhidas; não aconteceu e não foi gravado.",
  },
};

export const rotulosCausaDesvio: Record<string, string> = {
  vendas_abaixo_meta: "Vendas abaixo da meta",
  vendas_acima_meta: "Vendas acima da meta",
  parcelas_vencidas_sem_pagamento: "Parcelas vencidas sem pagamento",
  financiamento_nao_elegivel: "Financiamento ainda não elegível",
  liberacao_prevista_vencida: "Liberação prevista e não recebida",
  gasto_acima_previsto: "Gasto acima do previsto na versão original",
};

export const rotulosOrigemDado: Record<string, string> = {
  origem: "Dados da origem",
  complemento_manual: "Complemento manual",
  versao_planejamento: "Versão do planejamento",
};

export const rotulosModalidade: Record<string, string> = {
  credito_producao: "Crédito à produção",
  plano_empresario: "Plano empresário",
  credito_associativo: "Crédito associativo",
  outra: "Outra",
};

export const rotulosEtapa: Record<string, string> = {
  contratacao: "Contratação",
  aprovacao: "Aprovação",
  elegivel: "Elegível",
  liberado: "Liberado",
};

export const rotulosSituacaoLiberacao: Record<string, string> = {
  prevista: "Prevista",
  pendente: "Pendente",
  recebida: "Recebida",
  cancelada: "Cancelada",
  atrasada: "Prevista e atrasada",
};

export const rotulosNivelLiberacao: Record<string, string> = {
  contrato: "Contrato do comprador",
  empreendimento: "Obra inteira",
  lote: "Lote",
};

export const rotulosSituacaoMedicao: Record<string, string> = {
  apresentada: "Apresentada",
  aprovada: "Aprovada",
  reprovada: "Reprovada",
};

export const rotulosClassificacao: Record<string, string> = {
  financiamento_elegivel: "Elegível",
  financiamento_pendente: "Pendente",
};

// Código do Postgres ou do PostgREST vira frase; nunca mostra a mensagem crua.
export function fraseErroGravacao(codigo: string | undefined): string {
  switch (codigo) {
    case "42501":
      return mensagensPlanejamento.acao.semPermissao;
    case "23505":
      return mensagensPlanejamento.acao.duplicado;
    case "23514":
    case "23502":
    case "22023":
    case "22P02":
    case "23503":
      return mensagensPlanejamento.acao.recusadoPeloBanco;
    default:
      return mensagensPlanejamento.acao.indisponivel;
  }
}
