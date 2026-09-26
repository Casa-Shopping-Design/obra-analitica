// Monta as linhas do DRE para a tela a partir do que o banco devolve. Só separa, ordena e troca o
// valor pelo estado (número, indisponível com motivo, ausente); nenhuma soma é feita aqui.
import type { CodigoLinhaDre, LinhaDrePeriodo, LinhaReconhecimentoObra } from "../../lib/consultas/dre";
import { fraseMotivo } from "../../lib/mensagens";

export type EstadoValor =
  | { tipo: "valor"; valor: number }
  | { tipo: "indisponivel"; motivo: string }
  | { tipo: "ausente" };

// Indisponível nunca vira zero; disponível sem número é dado ausente ("Não informado").
export function estadoDoValor(
  valor: number | null | undefined,
  disponivel: boolean = true,
  motivo?: string | null,
): EstadoValor {
  if (!disponivel) return { tipo: "indisponivel", motivo: fraseMotivo(motivo) };
  if (valor === null || valor === undefined || !Number.isFinite(valor)) return { tipo: "ausente" };
  return { tipo: "valor", valor };
}

const subtotais = new Set<CodigoLinhaDre>(["receita_liquida", "resultado_bruto", "resultado_gerencial"]);
// Da linha 100 em diante (custo de obra, fora do resultado, sem categoria, sem competência) é informativo.
const primeiraOrdemInformativa = 100;

export type LinhaDreTela = {
  codigo: CodigoLinhaDre;
  nome: string;
  ordem: number;
  subtotal: boolean;
  estado: EstadoValor;
};

export function montarLinhasPeriodo(linhas: LinhaDrePeriodo[]): {
  resultado: LinhaDreTela[];
  informativas: LinhaDreTela[];
} {
  const ordenadas = [...linhas].sort((a, b) => a.linha_ordem - b.linha_ordem);
  const telas = ordenadas.map((linha) => ({
    codigo: linha.linha_codigo,
    nome: linha.linha_nome,
    ordem: linha.linha_ordem,
    subtotal: subtotais.has(linha.linha_codigo),
    estado: estadoDoValor(linha.valor_periodo, linha.disponivel, linha.motivo),
  }));
  return {
    resultado: telas.filter((linha) => linha.ordem < primeiraOrdemInformativa),
    informativas: telas.filter((linha) => linha.ordem >= primeiraOrdemInformativa),
  };
}

// A cobertura do período é a mesma em todas as linhas da função; vale a primeira preenchida.
export function coberturaDoPeriodo(linhas: Pick<LinhaDrePeriodo, "linha_codigo" | "cobertura">[]): number | null {
  const comCobertura = linhas.find(
    (linha) => linha.linha_codigo !== "sem_data_competencia" && linha.cobertura !== null,
  );
  return comCobertura?.cobertura ?? null;
}

export type MedidaMensal = "valor_mes" | "valor_acumulado";
export const medidasMensais: readonly MedidaMensal[] = ["valor_mes", "valor_acumulado"];

type LinhaMensalBase = {
  competencia: string | null;
  linha_codigo: CodigoLinhaDre;
  linha_ordem: number;
  linha_nome: string;
  valor_mes: number | null;
  valor_acumulado: number | null;
  disponivel: boolean;
  motivo: string | null;
  cobertura: number | null;
};

export type LinhaGradeDre = Omit<LinhaDreTela, "estado"> & { informativa: boolean; celulas: EstadoValor[] };
export type GradeDre = { meses: string[]; cobertura: (number | null)[]; linhas: LinhaGradeDre[] };

// Linhas do banco em formato longo viram uma grade linha x mês. Mês em que a linha não veio fica
// "ausente", nunca zero. O(n log n) pela ordenação, com n até 13 linhas x 12 meses.
export function montarGradeMensal(linhas: LinhaMensalBase[], medida: MedidaMensal): GradeDre {
  const doPeriodo = linhas.filter((linha) => linha.competencia !== null);
  const meses = [...new Set(doPeriodo.map((linha) => (linha.competencia as string).slice(0, 10)))].sort();
  const posicaoMes = new Map(meses.map((mes, posicao) => [mes, posicao]));
  const cobertura: (number | null)[] = meses.map(() => null);
  const porCodigo = new Map<CodigoLinhaDre, LinhaGradeDre>();

  for (const linha of doPeriodo) {
    const posicao = posicaoMes.get((linha.competencia as string).slice(0, 10)) as number;
    let grade = porCodigo.get(linha.linha_codigo);
    if (!grade) {
      grade = {
        codigo: linha.linha_codigo,
        nome: linha.linha_nome,
        ordem: linha.linha_ordem,
        subtotal: subtotais.has(linha.linha_codigo),
        informativa: linha.linha_ordem >= primeiraOrdemInformativa,
        celulas: meses.map(() => ({ tipo: "ausente" }) as EstadoValor),
      };
      porCodigo.set(linha.linha_codigo, grade);
    }
    grade.celulas[posicao] = estadoDoValor(linha[medida], linha.disponivel, linha.motivo);
    if (cobertura[posicao] === null && linha.cobertura !== null) cobertura[posicao] = linha.cobertura;
  }

  return { meses, cobertura, linhas: [...porCodigo.values()].sort((a, b) => a.ordem - b.ordem) };
}

// O aviso aparece quando alguma obra do recorte está sem critério validado, pelo método efetivo
// que o banco devolve, ou quando o próprio DRE marca a linha com esse motivo.
export function criterioPendente(
  linhasPeriodo: Pick<LinhaDrePeriodo, "motivo">[],
  reconhecimento: Pick<LinhaReconhecimentoObra, "metodo">[],
): boolean {
  return (
    reconhecimento.some((linha) => linha.metodo === "nao_definido") ||
    linhasPeriodo.some((linha) => linha.motivo === "criterio_nao_validado")
  );
}
