// Leitura e destaque do comparativo entre obras (marts.comparativo_obras, migration 0027). Sem acesso ao
// banco, para o vitest provar o destaque do pior valor sem Supabase.
import { numeroOuNulo, numeroOuZero } from "./consultas/resumo-origem";

export type LinhaComparativo = {
  centro_custo_id: string;
  obra: string;
  vgv_total: number;
  pct_vgv_vendido: number | null;
  vendas_liquidas_12m: number;
  estoque_inicio_12m: number | null;
  vso_12m: number | null;
  unidades_estoque: number;
  valor_estoque: number;
  resultado_projetado: number;
  margem_projetada: number | null;
  exposicao_maxima: number;
  caixa_atual: number;
  vencido_direto: number;
  pct_inadimplencia: number | null;
  pct_fisico: number | null;
  pct_financeiro: number | null;
  diferenca_financeiro_fisico: number | null;
  alertas: number;
};

export function lerComparativo(linhas: Record<string, unknown>[]): LinhaComparativo[] {
  return linhas.map((linha) => ({
    centro_custo_id: String(linha.centro_custo_id),
    obra: String(linha.obra),
    vgv_total: numeroOuZero(linha.vgv_total),
    pct_vgv_vendido: numeroOuNulo(linha.pct_vgv_vendido),
    vendas_liquidas_12m: numeroOuZero(linha.vendas_liquidas_12m),
    estoque_inicio_12m: numeroOuNulo(linha.estoque_inicio_12m),
    vso_12m: numeroOuNulo(linha.vso_12m),
    unidades_estoque: numeroOuZero(linha.unidades_estoque),
    valor_estoque: numeroOuZero(linha.valor_estoque),
    resultado_projetado: numeroOuZero(linha.resultado_projetado),
    margem_projetada: numeroOuNulo(linha.margem_projetada),
    exposicao_maxima: numeroOuZero(linha.exposicao_maxima),
    caixa_atual: numeroOuZero(linha.caixa_atual),
    vencido_direto: numeroOuZero(linha.vencido_direto),
    pct_inadimplencia: numeroOuNulo(linha.pct_inadimplencia),
    pct_fisico: numeroOuNulo(linha.pct_fisico),
    pct_financeiro: numeroOuNulo(linha.pct_financeiro),
    diferenca_financeiro_fisico: numeroOuNulo(linha.diferenca_financeiro_fisico),
    alertas: numeroOuZero(linha.alertas),
  }));
}

// VGV fica de fora: obra maior não é obra pior.
export const piorQuando = {
  pct_vgv_vendido: "menor",
  vso_12m: "menor",
  valor_estoque: "maior",
  resultado_projetado: "menor",
  margem_projetada: "menor",
  exposicao_maxima: "maior",
  caixa_atual: "menor",
  pct_inadimplencia: "maior",
  vencido_direto: "maior",
  diferenca_financeiro_fisico: "maior",
  alertas: "maior",
} as const satisfies Partial<Record<keyof LinhaComparativo, "menor" | "maior">>;

export type ColunaComparada = keyof typeof piorQuando;

// O(c x o), c colunas e o obras (dezenas). Empate marca todas as empatadas; coluna com valor igual em
// todas as obras, ou com menos de duas obras com número, não marca nada, porque não há o que comparar.
export function pioresValores(linhas: LinhaComparativo[]): Record<ColunaComparada, Set<string>> {
  const piores = {} as Record<ColunaComparada, Set<string>>;
  for (const coluna of Object.keys(piorQuando) as ColunaComparada[]) {
    const comNumero = linhas.filter((linha) => linha[coluna] !== null);
    const valores = comNumero.map((linha) => linha[coluna] as number);
    const pior = piorQuando[coluna] === "maior" ? Math.max(...valores) : Math.min(...valores);
    const melhor = piorQuando[coluna] === "maior" ? Math.min(...valores) : Math.max(...valores);
    piores[coluna] =
      comNumero.length < 2 || pior === melhor
        ? new Set()
        : new Set(comNumero.filter((linha) => linha[coluna] === pior).map((linha) => linha.centro_custo_id));
  }
  return piores;
}
