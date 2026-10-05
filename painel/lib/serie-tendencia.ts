// Série mensal da margem operacional (marts.tendencia_resultado_mensal, migration 0033). Só lê, ordena,
// recorta e agrupa; as margens chegam prontas da view.
import { numeroOuNulo } from "./consultas/resumo-origem";
import { formatarMes } from "./formatar";
import { deslocarMes, mesCorrente } from "./serie-fluxo";

export const mesesNaSerie = 24;

export type PontoTendencia = {
  competencia: string;
  margemViabilidade: number | null;
  margemTendencia: number | null;
};

export type LinhaTendenciaObra = PontoTendencia & { centroCustoId: string };

export function lerPontoTendencia(linha: Record<string, unknown>): PontoTendencia {
  return {
    competencia: String(linha.competencia),
    margemViabilidade: numeroOuNulo(linha.margem_operacional_viabilidade),
    margemTendencia: numeroOuNulo(linha.margem_operacional_tendencia),
  };
}

export function lerLinhaTendenciaObra(linha: Record<string, unknown>): LinhaTendenciaObra {
  return { ...lerPontoTendencia(linha), centroCustoId: String(linha.centro_custo_id) };
}

// Competência é data ISO, então a ordem do texto é a ordem do tempo. O(n log n) pela ordenação.
export function recortarSerie(pontos: PontoTendencia[]): PontoTendencia[] {
  return [...pontos].sort((a, b) => a.competencia.localeCompare(b.competencia)).slice(-mesesNaSerie);
}

// Uma passada com dicionário por obra, O(n), e o recorte de cada obra depois.
export function agruparSeriePorObra(linhas: LinhaTendenciaObra[]): Map<string, PontoTendencia[]> {
  const porObra = new Map<string, PontoTendencia[]>();
  for (const { centroCustoId, ...ponto } of linhas) {
    const pontos = porObra.get(centroCustoId);
    if (pontos) pontos.push(ponto);
    else porObra.set(centroCustoId, [ponto]);
  }
  for (const [centroCustoId, pontos] of porObra) porObra.set(centroCustoId, recortarSerie(pontos));
  return porObra;
}

// Primeiro dia do mês mais antigo que cabe na janela, para a consulta da lista não trazer o histórico inteiro.
export function inicioJanela(agora: Date = new Date()): string {
  return `${deslocarMes(mesCorrente(agora), -(mesesNaSerie - 1))}-01`;
}

// Fração com duas casas: 0,2153 vira "21,53%". A view arredonda a margem em quatro casas.
const formatoMargem = new Intl.NumberFormat("pt-BR", {
  style: "percent",
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

export function formatarMargem(fracao: number | null): string {
  return fracao === null ? "sem base" : formatoMargem.format(fracao);
}

// Frase lida no lugar da miniatura: o primeiro e o último mês da tendência, sem conta nenhuma.
export function resumoSerie(pontos: PontoTendencia[]): string | null {
  if (pontos.length === 0) return null;
  const primeiro = pontos[0];
  const ultimo = pontos[pontos.length - 1];
  if (pontos.length === 1) {
    return `Margem na tendência de ${formatarMargem(ultimo.margemTendencia)} em ${formatarMes(ultimo.competencia)}.`;
  }
  return `Margem na tendência de ${formatarMargem(primeiro.margemTendencia)} em ${formatarMes(primeiro.competencia)} a ${formatarMargem(ultimo.margemTendencia)} em ${formatarMes(ultimo.competencia)}.`;
}
