// Textos das telas de empresa e do mapa de contas. Nunca repassar a mensagem crua do banco.
export const mensagensEmpresa = {
  restrita: "O seu perfil não abre a visão por empresa. Peça ao diretor da construtora para liberar.",
  indisponivel: "Não foi possível carregar as empresas agora. Recarregue a página em alguns minutos.",
  semEmpresas:
    "Nenhuma empresa liberada para o seu perfil. As empresas aparecem depois da carga da contabilidade; se já houve carga, peça acesso ao diretor.",
  naoEncontrada: "Empresa não encontrada ou sem permissão para o seu perfil.",
  semContabilidade: "A contabilidade desta empresa ainda não foi carregada. Os relatórios aparecem depois da próxima carga.",
  relatorioIndisponivel: "Não foi possível montar este relatório agora. Recarregue a página em alguns minutos.",
  relatorioVazio: "Nenhum valor para este período. Escolha outro mês ou confira se a contabilidade do mês já foi carregada.",
  conferenciaIndisponivel: "Não foi possível carregar a conferência agora. Recarregue a página em alguns minutos.",
  semControle: "A conferência deste mês ainda não foi calculada. Ela aparece depois da próxima carga.",
  contasSemMapaIndisponivel: "Não foi possível carregar a lista de contas sem mapa agora. Recarregue a página em alguns minutos.",
  semContasSemMapa: "Todas as contas com saldo ou movimento desta empresa estão mapeadas.",
  pecaMapeamento: "Peça ao diretor ou ao financeiro para mapear estas contas.",
} as const;

export const mensagensMapa = {
  restrita: "Só diretor e financeiro abrem o mapa de contas. Peça ao diretor da construtora se precisar mudar uma linha.",
  indisponivel: "Não foi possível carregar o mapa de contas agora. Recarregue a página em alguns minutos.",
  semContas: "Nenhuma conta neste filtro. Tire o filtro ou espere a primeira carga da contabilidade.",
  semPermissao: "Só diretor e financeiro, com o segundo fator confirmado, gravam o mapa de contas.",
  semMudancas: "Nenhuma linha foi alterada. Escolha a linha de pelo menos uma conta antes de gravar.",
  limite: "Grave no máximo 500 contas de cada vez. Filtre por grupo e grave em partes.",
  formato: "Alguma conta ou linha veio em formato inesperado. Recarregue a página e escolha de novo.",
  foraDoCatalogo:
    "Alguma conta não existe mais no plano ou alguma linha não vale para o grupo da conta. Recarregue a página e escolha de novo.",
  gravacaoIndisponivel: "Não foi possível gravar agora. Tente de novo em alguns minutos.",
} as const;

export function mensagemGravadas(quantidade: number): string {
  return quantidade === 1
    ? "1 conta gravada. Os relatórios já usam a linha nova."
    : `${quantidade} contas gravadas. Os relatórios já usam as linhas novas.`;
}
