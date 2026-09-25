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
    semMovimento: "Esta obra ainda não tem entradas nem saídas nos 36 meses mostrados no gráfico.",
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
} as const;
