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
} as const;
