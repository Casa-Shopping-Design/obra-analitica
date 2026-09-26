// Todo texto de erro que o usuário vê sai daqui. Nunca repassar a mensagem crua do Supabase ou do banco.
export const mensagens = {
  entrar: {
    camposVazios: "Preencha o e-mail e a senha.",
    credenciaisInvalidas: "E-mail ou senha incorretos. Confira e tente de novo.",
    muitasTentativas: "Muitas tentativas seguidas. Espere alguns minutos e tente de novo.",
    indisponivel: "Não foi possível entrar agora. Tente de novo em alguns minutos.",
  },
  posicao: {
    indisponivel: "Não foi possível carregar as obras agora. Recarregue a página em alguns minutos.",
    semObras: "Nenhuma obra liberada para o seu perfil. Peça acesso ao administrador da construtora.",
  },
  obra: {
    naoEncontrada: "Obra não encontrada ou sem permissão.",
    indisponivel: "Não foi possível carregar esta obra agora. Recarregue a página em alguns minutos.",
  },
  unidades: {
    indisponivel: "Não foi possível carregar o mapa de unidades agora. Recarregue a página em alguns minutos.",
    obraNaoEncontrada: "Obra não encontrada ou sem permissão para o seu perfil.",
    semUnidades: "Esta obra ainda não tem unidades carregadas. Elas aparecem depois da próxima carga de dados.",
  },
  assistente: {
    indisponivel: "Não foi possível responder agora. Tente de novo em alguns minutos.",
    perguntaDesconhecida: "Essa pergunta não está na lista. Escolha uma das perguntas abaixo.",
  },
  carga: {
    semRegistro: "Dados da demo, gerados para apresentação. Não são números de uma construtora real.",
    semConsulta: "Não foi possível conferir a data da última carga. Recarregue a página em alguns minutos.",
    referenciaLocal: "Data de hoje; o banco não informou a data de referência.",
  },
  bloco: {
    indisponivel: "Não foi possível carregar este bloco agora. Recarregue a página em alguns minutos.",
  },
  dre: {
    semLancamentos: "Nenhum lançamento com data de competência neste período e recorte.",
    semPendencias: "Todas as contas vistas na origem já têm categoria.",
    criterioPendente:
      "Receita reconhecida, custo dos imóveis vendidos, resultado bruto e resultado gerencial ficam sem número até o financeiro validar o critério de reconhecimento. As despesas, as deduções e o custo de obra lançado aparecem normalmente.",
    semOrcamentoFonte: "O DRE não tem coluna de orçamento: a origem não traz um orçamento comparável por linha.",
  },
  gravacao: {
    semSessao: "Sua sessão terminou. Entre de novo para gravar.",
    semPermissao: "Só diretor ou financeiro da construtora pode gravar esta informação.",
    corrijaCampos: "Confira os campos marcados e tente de novo.",
    categoriaIncompativel: "Essa categoria não serve para este tipo de lançamento. Escolha outra da lista.",
    obraNaoEncontrada: "Obra não encontrada ou sem permissão.",
    recusada: "O banco recusou a gravação. Confira os dados e tente de novo.",
    indisponivel: "Não foi possível gravar agora. Tente de novo em alguns minutos.",
    classificada: "Conta classificada. O DRE e a lista de pendências já usam a nova categoria.",
    criterioValidado:
      "Critério registrado com o seu usuário como responsável pela validação. Receita e resultado passam a ser calculados.",
    criterioDesligado: "Critério voltou para não definido. Receita e resultado ficam indisponíveis de novo.",
  },
  receitas: {
    semCarteira: "Nenhuma parcela encontrada com esses filtros.",
    paginaForaDoIntervalo: "Esta página não existe mais com os filtros atuais.",
    semMovimento: "Nenhum recebimento nem parcela no período mostrado.",
    semReceitas: "Nenhum contrato nem parcela nas obras liberadas para o seu perfil.",
  },
  despesas: {
    semCustos: "Nenhum título nem orçamento nas obras liberadas para o seu perfil.",
    semCategorias: "Nenhum título lançado neste recorte.",
    semPeriodo: "Nenhum título com competência ou pagamento neste período.",
  },
  // Frases dos códigos de motivo da seção 9 do contrato de dados.
  motivos: {
    criterio_nao_validado: "Critério de reconhecimento não validado pelo financeiro.",
    orcamento_ausente: "A obra não tem orçamento carregado.",
    unidades_ausentes: "A obra não tem unidades cadastradas; a fração vendida não pode ser calculada.",
    custo_sem_categoria: "Há custo da obra sem categoria. Classifique as contas pendentes para liberar o cálculo.",
    custo_sem_competencia: "Há títulos da obra sem data de competência na origem.",
    sem_fonte: "A origem não traz este dado.",
    sem_premissa_distribuicao: "Não há premissa de meses para o custo sem título.",
    premissa_invalida: "A premissa de meses não soma 100%.",
    consolidado_parcial: "Alguma obra do consolidado está indisponível.",
    criterio_sem_validador:
      "O critério foi gravado pela carga, sem um usuário do financeiro. Registre o critério em DRE gerencial para liberar o cálculo.",
    area_privativa_ausente:
      "Falta a área privativa de alguma unidade da obra; a fração vendida por área não pode ser calculada. Complete o cadastro na origem ou troque a base em Configurações.",
    valor_tabela_ausente:
      "Falta o preço de tabela de alguma unidade da obra; a fração vendida por valor não pode ser calculada. Complete a tabela na origem ou troque a base em Configurações.",
    horizonte_ausente:
      "A meta automática não tem prazo: a obra não tem data de entrega das unidades nem data final informada em Configurações.",
    horizonte_encerrado: "O prazo da meta automática já passou. Informe uma nova data final em Configurações.",
    sem_estoque_disponivel:
      "Não há unidade disponível com preço de tabela; a meta em unidades não pode ser calculada.",
  },
  motivoDesconhecido: "Indisponível no momento.",
} as const;

export type CodigoMotivo = keyof typeof mensagens.motivos;

// O horizonte do gráfico da obra vem de exibicao.meses_grafico.
export function textoSemMovimentoObra(meses: number): string {
  return `Esta obra ainda não tem entradas nem saídas nos ${meses} meses mostrados no gráfico.`;
}

// Código de erro do banco vira frase; a mensagem crua, o SQL e o nome da tabela nunca chegam à tela.
export function fraseErroGravacao(codigo: string | undefined): string {
  if (codigo === "42501") return mensagens.gravacao.semPermissao;
  if (codigo && ["23514", "23502", "23503", "23505", "22023", "22P02"].includes(codigo))
    return mensagens.gravacao.recusada;
  return mensagens.gravacao.indisponivel;
}

// Código que o banco mandar e a tela não conhecer vira frase genérica, nunca o código cru.
export function fraseMotivo(codigo: string | null | undefined): string {
  if (!codigo) return mensagens.motivoDesconhecido;
  return codigo in mensagens.motivos ? mensagens.motivos[codigo as CodigoMotivo] : mensagens.motivoDesconhecido;
}
