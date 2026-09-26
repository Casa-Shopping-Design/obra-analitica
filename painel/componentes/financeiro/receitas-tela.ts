// Rótulos e junções da tela de receitas. Junta por mês e origem o que o banco já somou; nada é somado aqui.
import type { LinhaRecebimentoMensal, OrigemRecebivel, SituacaoParcela } from "../../lib/consultas/receitas";

export const situacoesParcela: readonly SituacaoParcela[] = [
  "quitada",
  "vencida",
  "a_vencer",
  "cancelada_distrato",
  "baixada_sem_recebimento",
];
export const origensRecebivel: readonly OrigemRecebivel[] = ["direta", "financiamento"];

export const rotulosSituacao: Record<SituacaoParcela, string> = {
  quitada: "Quitada",
  vencida: "Vencida",
  a_vencer: "A vencer",
  cancelada_distrato: "Cancelada por distrato",
  baixada_sem_recebimento: "Baixada sem recebimento",
};

export const rotulosOrigem: Record<OrigemRecebivel, string> = {
  direta: "Entrada direta",
  financiamento: "Financiamento",
};

export type PontoRecebimento = {
  competencia: string;
  recebidoDireta: number | null;
  recebidoFinanciamento: number | null;
  previstoDireta: number | null;
  previstoFinanciamento: number | null;
  emAbertoDireta: number | null;
  emAbertoFinanciamento: number | null;
};

function pontoVazio(competencia: string): PontoRecebimento {
  return {
    competencia,
    recebidoDireta: null,
    recebidoFinanciamento: null,
    previstoDireta: null,
    previstoFinanciamento: null,
    emAbertoDireta: null,
    emAbertoFinanciamento: null,
  };
}

// Uma linha por mês com as duas origens lado a lado. Origem sem linha no mês fica nula ("sem dado").
// O(n log n) pela ordenação, com n até 2 origens x 12 meses.
export function juntarRecebimentoMensal(
  linhas: Pick<
    LinhaRecebimentoMensal,
    "competencia" | "origem" | "recebido" | "previsto_contratual" | "saldo_em_aberto"
  >[],
): PontoRecebimento[] {
  const pontos = new Map<string, PontoRecebimento>();
  for (const linha of linhas) {
    const mes = linha.competencia.slice(0, 10);
    const ponto = pontos.get(mes) ?? pontoVazio(mes);
    if (linha.origem === "direta") {
      ponto.recebidoDireta = linha.recebido;
      ponto.previstoDireta = linha.previsto_contratual;
      ponto.emAbertoDireta = linha.saldo_em_aberto;
    } else {
      ponto.recebidoFinanciamento = linha.recebido;
      ponto.previstoFinanciamento = linha.previsto_contratual;
      ponto.emAbertoFinanciamento = linha.saldo_em_aberto;
    }
    pontos.set(mes, ponto);
  }
  return [...pontos.values()].sort((a, b) => (a.competencia < b.competencia ? -1 : 1));
}

// Procura a linha de uma origem na resposta da função de período; sem linha, o valor é desconhecido.
export function valorDaOrigem<T extends { origem: OrigemRecebivel }>(
  linhas: T[],
  origem: OrigemRecebivel,
  coluna: keyof T,
): number | null {
  const linha = linhas.find((item) => item.origem === origem);
  return linha ? Number(linha[coluna]) : null;
}
