// Regras puras das telas de vendas, execução, inadimplência e conferência. Sem acesso ao banco,
// para o vitest provar os casos conhecidos sem Supabase.

export const perfisConferencia = ["diretor", "financeiro"] as const;

export function perfilVeConferencia(perfil: string | null | undefined): boolean {
  return perfisConferencia.some((permitido) => permitido === perfil);
}

// PostgREST devolve numeric como número ou texto, conforme o tamanho; nulo continua nulo.
export function numeroOuNulo(valor: unknown): number | null {
  if (valor === null || valor === undefined || valor === "") return null;
  const numero = Number(valor);
  return Number.isFinite(numero) ? numero : null;
}

export function numeroOuZero(valor: unknown): number {
  return numeroOuNulo(valor) ?? 0;
}

export type LinhaFunil = {
  competencia: string;
  leads: number;
  reservas: number;
  reservas_canceladas: number;
  vendas: number;
  distratos: number;
  conversao_lead_reserva: number | null;
  conversao_reserva_venda: number | null;
};

export type TotalFunil = {
  leads: number;
  reservas: number;
  vendas: number;
  distratos: number;
  conversaoLeadReserva: number | null;
  conversaoReservaVenda: number | null;
};

// Soma o período antes de dividir; média das conversões mensais daria peso igual a mês fraco e forte.
export function totalizarFunil(linhas: LinhaFunil[]): TotalFunil {
  const total = linhas.reduce(
    (soma, linha) => ({
      leads: soma.leads + linha.leads,
      reservas: soma.reservas + linha.reservas,
      vendas: soma.vendas + linha.vendas,
      distratos: soma.distratos + linha.distratos,
    }),
    { leads: 0, reservas: 0, vendas: 0, distratos: 0 },
  );
  return {
    ...total,
    conversaoLeadReserva: total.leads > 0 ? total.reservas / total.leads : null,
    conversaoReservaVenda: total.reservas > 0 ? total.vendas / total.reservas : null,
  };
}

export type SituacaoDiferenca = "confere" | "atencao" | "diverge" | "sem_base";

// Até 1% é arredondamento e competência; acima de 5% alguém precisa olhar o lançamento.
export function classificarDiferenca(fracao: number | null): SituacaoDiferenca {
  if (fracao === null) return "sem_base";
  const absoluta = Math.abs(fracao);
  if (absoluta <= 0.01) return "confere";
  if (absoluta <= 0.05) return "atencao";
  return "diverge";
}

export type LinhaExecucao = {
  competencia: string;
  pct_fisico: number | null;
  pct_financeiro: number | null;
  pct_financeiro_origem: number | null;
  diferenca_financeiro_fisico: number | null;
};

// A view devolve o mês atual por último; a tela mostra o último mês com físico medido.
export function execucaoMaisRecente(linhas: LinhaExecucao[]): LinhaExecucao | null {
  for (let indice = linhas.length - 1; indice >= 0; indice -= 1) {
    if (linhas[indice].pct_fisico !== null) return linhas[indice];
  }
  return null;
}

// Pago acima do medido em mais de 10 pontos quer dizer adiantamento a fornecedor ou medição atrasada.
export function financeiroAdiantado(diferenca: number | null): boolean {
  return diferenca !== null && diferenca > 0.1;
}

export type LinhaInadimplencia = {
  data_posicao: string;
  ordem: number;
  faixa: string;
  titulos: number;
  parcelas: number;
  valor_atrasado: number;
  valor_atualizado: number;
};

export function totalizarInadimplencia(linhas: LinhaInadimplencia[]) {
  return linhas.reduce(
    (soma, linha) => ({
      titulos: soma.titulos + linha.titulos,
      parcelas: soma.parcelas + linha.parcelas,
      valorAtrasado: soma.valorAtrasado + linha.valor_atrasado,
      valorAtualizado: soma.valorAtualizado + linha.valor_atualizado,
    }),
    { titulos: 0, parcelas: 0, valorAtrasado: 0, valorAtualizado: 0 },
  );
}

const rotulosFaixa: Record<string, string> = {
  "1-30": "1 a 30 dias",
  "31-90": "31 a 90 dias",
  "91-180": "91 a 180 dias",
  ">180": "Mais de 180 dias",
};

export function rotuloFaixa(faixa: string): string {
  return rotulosFaixa[faixa] ?? faixa;
}

export type LinhaLeadOrigem = {
  origem: string;
  midia: string;
  leads: number;
  leads_descartados: number;
  pct_descartados: number | null;
  motivo_principal_descarte: string | null;
  leads_motivo_principal: number | null;
};

export type TotalLeadOrigem = { origem: string; leads: number; leadsDescartados: number };

// Leads e descartados somam por origem; o motivo principal não soma, por isso fica só na tabela por mídia.
export function somarLeadsPorOrigem(linhas: LinhaLeadOrigem[]): TotalLeadOrigem[] {
  const porOrigem = new Map<string, TotalLeadOrigem>();
  for (const linha of linhas) {
    const atual = porOrigem.get(linha.origem) ?? { origem: linha.origem, leads: 0, leadsDescartados: 0 };
    atual.leads += linha.leads;
    atual.leadsDescartados += linha.leads_descartados;
    porOrigem.set(linha.origem, atual);
  }
  return [...porOrigem.values()].sort((a, b) => b.leads - a.leads || a.origem.localeCompare(b.origem, "pt-BR"));
}

// Texto que o usuário vê nestas telas. Nunca a mensagem crua do banco.
export const mensagensOrigem = {
  indisponivel: "Não foi possível carregar esta tela agora. Recarregue a página em alguns minutos.",
  obraNaoEncontrada: "Obra não encontrada ou sem permissão para o seu perfil.",
  semCrm:
    "Esta obra ainda não tem dado do CRM de vendas. Se a construtora usa o CRM, peça ao administrador para ligar a carga dele.",
  semRepasse: "Nenhum repasse desta obra no CRM de vendas até a última carga.",
  semLeads: "Nenhum lead desta obra no CRM de vendas nos últimos 12 meses.",
  semExecucao:
    "Esta obra ainda não tem medição aprovada no ERP. O percentual físico aparece depois da primeira medição aprovada e da carga seguinte.",
  semInadimplencia:
    "Nenhuma posição de inadimplência carregada para esta obra. Ela aparece quando o pacote do ERP inclui a consulta em lote e a carga roda.",
  semConferencia:
    "O ERP ainda não fechou nenhum mês do mapa imobiliário desta obra. A conferência aparece depois da próxima carga com o mês fechado.",
  conferenciaRestrita: "A conferência com o ERP é só para os perfis Diretor e Financeiro. Peça acesso ao administrador da construtora.",
} as const;
