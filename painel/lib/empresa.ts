// Regras puras das telas de empresa (Fontes e Usos, DRE societária, custo incorrido e conferência).
// Nenhuma conta de negócio: os valores chegam prontos do banco e aqui só são lidos, ordenados e transpostos.

import { numeroOuNulo, numeroOuZero, perfilVeConferencia } from "./consultas/resumo-origem";

export const perfisEmpresa = ["diretor", "financeiro", "leitura"] as const;

export function perfilVeEmpresas(perfil: string | null | undefined): boolean {
  return perfisEmpresa.some((permitido) => permitido === perfil);
}

// O mapa de contas muda todos os relatórios do tenant, então fica com quem grava o estudo.
export function perfilEditaMapa(perfil: string | null | undefined): boolean {
  return perfilVeConferencia(perfil);
}

const formatoUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function idEmpresaValido(id: string): boolean {
  return formatoUuid.test(id);
}

export type ResumoEmpresa = {
  empresaId: string;
  nome: string;
  nomeFantasia: string | null;
  obras: number;
  primeiraCompetencia: string | null;
  ultimaCompetencia: string | null;
  caixaEquivalentes: number | null;
  fluxoOperacional: number | null;
  lucroLiquido: number | null;
  diferencaIdentidade: number | null;
  contasSemMapa: number;
};

export const colunasResumoEmpresa =
  "empresa_id, nome, nome_fantasia, obras, primeira_competencia, ultima_competencia, caixa_equivalentes, fluxo_operacional, lucro_liquido, diferenca_identidade, contas_sem_mapa";

function textoOuNulo(valor: unknown): string | null {
  return valor === null || valor === undefined || valor === "" ? null : String(valor);
}

export function lerResumoEmpresa(linha: Record<string, unknown>): ResumoEmpresa {
  return {
    empresaId: String(linha.empresa_id),
    nome: String(linha.nome ?? ""),
    nomeFantasia: textoOuNulo(linha.nome_fantasia),
    obras: numeroOuZero(linha.obras),
    primeiraCompetencia: textoOuNulo(linha.primeira_competencia),
    ultimaCompetencia: textoOuNulo(linha.ultima_competencia),
    caixaEquivalentes: numeroOuNulo(linha.caixa_equivalentes),
    fluxoOperacional: numeroOuNulo(linha.fluxo_operacional),
    lucroLiquido: numeroOuNulo(linha.lucro_liquido),
    diferencaIdentidade: numeroOuNulo(linha.diferenca_identidade),
    contasSemMapa: numeroOuZero(linha.contas_sem_mapa),
  };
}

// O nome fantasia é o que a construtora usa no dia a dia; a razão social fica de subtítulo.
export function nomeExibido(empresa: Pick<ResumoEmpresa, "nome" | "nomeFantasia">): string {
  return empresa.nomeFantasia ?? empresa.nome;
}

export type TipoLinhaRelatorio = "total" | "grupo" | "conta";

export type LinhaDemonstrativo = {
  ordem: number;
  linha: string;
  rotulo: string;
  tipo: string;
  nivel: number;
  valor: number;
  percentual: number | null;
};

export function lerLinhaDemonstrativo(linha: Record<string, unknown>, campoPercentual?: string): LinhaDemonstrativo {
  return {
    ordem: numeroOuZero(linha.ordem),
    linha: String(linha.linha),
    rotulo: String(linha.rotulo ?? linha.linha),
    tipo: String(linha.tipo ?? "conta"),
    nivel: numeroOuZero(linha.nivel),
    valor: numeroOuZero(linha.valor),
    percentual: campoPercentual ? numeroOuNulo(linha[campoPercentual]) : null,
  };
}

export function linhaEmDestaque(tipo: string): boolean {
  return tipo === "total" || tipo === "grupo";
}

// Os dois indicadores da aba de custo chegam da função do banco como linhas próprias, em fração.
export const linhasIndicadorCusto = ["pct_levado_ao_resultado", "taxa_encargos"] as const;
export type IndicadoresCusto = { pctLevadoAoResultado: number | null; taxaEncargos: number | null };

export function ehLinhaIndicador(linha: { tipo: string; linha: string }): boolean {
  return linha.tipo === "indicador" || (linhasIndicadorCusto as readonly string[]).includes(linha.linha);
}

export function separarIndicadoresCusto(linhas: LinhaDemonstrativo[]): {
  linhas: LinhaDemonstrativo[];
  indicadores: IndicadoresCusto;
} {
  const porLinha = new Map(linhas.filter(ehLinhaIndicador).map((linha) => [linha.linha, linha.valor]));
  return {
    linhas: linhas.filter((linha) => !ehLinhaIndicador(linha)),
    indicadores: {
      pctLevadoAoResultado: porLinha.get("pct_levado_ao_resultado") ?? null,
      taxaEncargos: porLinha.get("taxa_encargos") ?? null,
    },
  };
}

export type LinhaMensal = {
  linha: string;
  rotulo: string;
  ordem: number;
  tipo: string;
  nivel: number;
  competencia: string;
  valorMes: number;
  valorAcumulado: number;
};

export const colunasMensal = "linha, rotulo, ordem, tipo, nivel, competencia, valor_mes, valor_acumulado";

export function lerLinhaMensal(linha: Record<string, unknown>): LinhaMensal {
  return {
    linha: String(linha.linha),
    rotulo: String(linha.rotulo ?? linha.linha),
    ordem: numeroOuZero(linha.ordem),
    tipo: String(linha.tipo ?? "conta"),
    nivel: numeroOuZero(linha.nivel),
    competencia: String(linha.competencia).slice(0, 7),
    valorMes: numeroOuZero(linha.valor_mes),
    valorAcumulado: numeroOuZero(linha.valor_acumulado),
  };
}

export type LinhaGrade = { linha: string; rotulo: string; tipo: string; nivel: number; valores: (number | null)[] };

// Transpõe a view mensal (uma linha por linha do relatório e mês) em uma linha por linha do relatório, com uma
// coluna por mês. O(n) sobre as linhas com dicionário, mais a ordenação das ~60 linhas do relatório.
// Mês sem valor fica nulo, e a tela mostra vazio em vez de zero inventado.
export function montarGradeMensal(linhas: LinhaMensal[], meses: string[], acumulado: boolean): LinhaGrade[] {
  const posicaoMes = new Map(meses.map((mes, indice) => [mes, indice]));
  const porLinha = new Map<string, LinhaGrade>();
  const ordemDaLinha = new Map<string, number>();
  for (const linha of linhas) {
    const indice = posicaoMes.get(linha.competencia);
    if (indice === undefined) continue;
    let destino = porLinha.get(linha.linha);
    if (!destino) {
      destino = { linha: linha.linha, rotulo: linha.rotulo, tipo: linha.tipo, nivel: linha.nivel, valores: meses.map(() => null) };
      porLinha.set(linha.linha, destino);
      ordemDaLinha.set(linha.linha, linha.ordem);
    }
    destino.valores[indice] = acumulado ? linha.valorAcumulado : linha.valorMes;
  }
  return [...porLinha.values()].sort((a, b) => (ordemDaLinha.get(a.linha) ?? 0) - (ordemDaLinha.get(b.linha) ?? 0));
}

export type ControleEmpresa = {
  competencia: string;
  saldoLiquidoAcumulado: number;
  caixaEquivalentesAcumulado: number;
  diferencaIdentidade: number;
  lucrosAcumulados: number;
  lucroLiquidoDre: number;
  ajusteExerciciosAnteriores: number;
  contasSemMapa: number;
  movimentoSemMapa: number;
};

export const colunasControle =
  "competencia, saldo_liquido_acumulado, caixa_equivalentes_acumulado, diferenca_identidade, lucros_acumulados, lucro_liquido_dre, ajuste_exercicios_anteriores, contas_sem_mapa, movimento_sem_mapa";

export function lerControle(linha: Record<string, unknown>): ControleEmpresa {
  return {
    competencia: String(linha.competencia),
    saldoLiquidoAcumulado: numeroOuZero(linha.saldo_liquido_acumulado),
    caixaEquivalentesAcumulado: numeroOuZero(linha.caixa_equivalentes_acumulado),
    diferencaIdentidade: numeroOuZero(linha.diferenca_identidade),
    lucrosAcumulados: numeroOuZero(linha.lucros_acumulados),
    lucroLiquidoDre: numeroOuZero(linha.lucro_liquido_dre),
    ajusteExerciciosAnteriores: numeroOuZero(linha.ajuste_exercicios_anteriores),
    contasSemMapa: numeroOuZero(linha.contas_sem_mapa),
    movimentoSemMapa: numeroOuZero(linha.movimento_sem_mapa),
  };
}

export type ContaSemMapa = {
  conta: string;
  contaReduzida: number | null;
  nome: string;
  grupo: string;
  saldoFinal: number;
  movimento: number;
};

export const colunasContaSemMapa = "conta, conta_reduzida, nome, grupo, saldo_final, movimento";

export function lerContaSemMapa(linha: Record<string, unknown>): ContaSemMapa {
  return {
    conta: String(linha.conta),
    contaReduzida: numeroOuNulo(linha.conta_reduzida),
    nome: String(linha.nome ?? ""),
    grupo: String(linha.grupo ?? ""),
    saldoFinal: numeroOuZero(linha.saldo_final),
    movimento: numeroOuZero(linha.movimento),
  };
}

// Centavo de diferença é arredondamento do ERP; o banco devolve a diferença, a tela só decide o selo.
const toleranciaCentavos = 0.005;

export type SituacaoIdentidade = "fecha" | "diferenca" | "sem_dado";

export function situacaoIdentidade(diferenca: number | null): SituacaoIdentidade {
  if (diferenca === null) return "sem_dado";
  return Math.abs(diferenca) < toleranciaCentavos ? "fecha" : "diferenca";
}
