// Leitura, rótulos e textos da DRE de viabilidade (marts.dre_viabilidade e marts.dre_resumo_obra, migration
// 0030). Sem acesso ao banco e sem conta: totais, diferenças e percentuais chegam prontos da view.
import { numeroOuNulo, numeroOuZero, perfilVeConferencia } from "./consultas/resumo-origem";
import type { ChaveExplicacao } from "./explicacoes";
import { formatarData, formatarDecimal, formatarPercentual, formatarReal } from "./formatar";

export const linhasResultado = [
  "vgv_bruto",
  "impostos",
  "vgv_liquido",
  "custo_vendas",
  "custo_empreendimento",
  "custo_terreno",
  "custo_projetos",
  "custo_licenciamento",
  "custo_construcao",
  "assistencia_tecnica",
  "juros_financiamento",
  "estoque",
  "resultado_bruto",
  "despesas",
  "despesas_comerciais",
  "despesas_administrativas",
  "lucro_operacional",
] as const;

export type LinhaResultado = (typeof linhasResultado)[number];

// As onze que o estudo digita (digitavel em marts.linha_resultado), na ordem da view. As outras seis são totais.
export const linhasDigitaveis = [
  "vgv_bruto",
  "impostos",
  "custo_terreno",
  "custo_projetos",
  "custo_licenciamento",
  "custo_construcao",
  "assistencia_tecnica",
  "juros_financiamento",
  "estoque",
  "despesas_comerciais",
  "despesas_administrativas",
] as const satisfies readonly LinhaResultado[];

export type LinhaDigitavel = (typeof linhasDigitaveis)[number];

const rotulosLinha: Record<LinhaResultado, string> = {
  vgv_bruto: "VGV bruto",
  impostos: "Impostos",
  vgv_liquido: "VGV líquido",
  custo_vendas: "Custo das vendas",
  custo_empreendimento: "Custo do empreendimento",
  custo_terreno: "Custo do terreno",
  custo_projetos: "Projetos",
  custo_licenciamento: "Licenciamento",
  custo_construcao: "Construção",
  assistencia_tecnica: "Assistência técnica",
  juros_financiamento: "Juros do financiamento",
  estoque: "Estoque",
  resultado_bruto: "Resultado bruto",
  despesas: "Despesas",
  despesas_comerciais: "Despesas comerciais",
  despesas_administrativas: "Despesas administrativas",
  lucro_operacional: "Lucro operacional",
};

// Linha que a view mandar e o painel ainda não conhecer aparece com o código, em vez de sumir da tabela.
// Diretor e financeiro gravam o estudo; leitura só consulta, para os sócios acompanharem sem segundo fator.
export const perfisDre = ["diretor", "financeiro", "leitura"] as const;

export function perfilVeDre(perfil: string | null | undefined): boolean {
  return perfisDre.some((permitido) => permitido === perfil);
}

// Grava quem vê a conferência com o ERP (diretor e financeiro), e só com o segundo fator confirmado na
// sessão. O banco repete as duas conferências dentro de app.gravar_viabilidade.
export function sessaoGravaEstudo(perfil: string | null | undefined, aal: string | null | undefined): boolean {
  return perfilVeConferencia(perfil) && aal === "aal2";
}

export function rotuloLinha(linha: string): string {
  return (rotulosLinha as Record<string, string>)[linha] ?? linha;
}

export type EstudoVigente = {
  id: string;
  versao: number;
  descricao: string | null;
  dataBase: string;
  linhas: Record<LinhaDigitavel, number>;
};

export type VersaoEstudo = {
  versao: number;
  descricao: string | null;
  dataBase: string;
  situacao: string;
  criadoEm: string;
  criadoPor: string | null;
};

export type AliquotaVigente = { aliquota: number; vigenciaInicio: string };

// Linha que faltar no banco (não acontece: a função grava as onze) aparece como zero no formulário.
export function lerEstudoVigente(linha: Record<string, unknown>): EstudoVigente {
  const valores = Array.isArray(linha.estudo_viabilidade_linha) ? (linha.estudo_viabilidade_linha as Record<string, unknown>[]) : [];
  const porLinha = new Map(valores.map((valor) => [String(valor.linha), numeroOuZero(valor.valor)]));
  const linhas = Object.fromEntries(linhasDigitaveis.map((chave) => [chave, porLinha.get(chave) ?? 0])) as Record<
    LinhaDigitavel,
    number
  >;
  return {
    id: String(linha.id),
    versao: numeroOuZero(linha.versao),
    descricao: typeof linha.descricao === "string" && linha.descricao !== "" ? linha.descricao : null,
    dataBase: String(linha.data_base),
    linhas,
  };
}

export function lerVersaoEstudo(linha: Record<string, unknown>): VersaoEstudo {
  return {
    versao: numeroOuZero(linha.versao),
    descricao: typeof linha.descricao === "string" && linha.descricao !== "" ? linha.descricao : null,
    dataBase: String(linha.data_base),
    situacao: String(linha.situacao),
    criadoEm: String(linha.criado_em),
    criadoPor: typeof linha.criado_por === "string" ? linha.criado_por : null,
  };
}

export function lerAliquotaVigente(linha: Record<string, unknown>): AliquotaVigente {
  return { aliquota: numeroOuZero(linha.aliquota), vigenciaInicio: String(linha.vigencia_inicio) };
}

// A tabela guarda só o id de quem gravou; o painel não lê nome de outro usuário do Auth.
export function textoAutorVersao(versao: VersaoEstudo, usuarioId: string): string {
  if (versao.criadoPor === null) return "carga inicial";
  return versao.criadoPor === usuarioId ? "você" : "outro usuário";
}

export function textoSituacaoVersao(situacao: string): string {
  return situacao === "vigente" ? "vigente" : "substituída";
}

export type LinhaDre = {
  linha: string;
  ordem: number;
  nivel: number;
  natureza: string;
  linhaDeTotal: boolean;
  fonteRealizado: string;
  viabilidade: number;
  pctViabilidade: number | null;
  apropriado: number;
  aApropriar: number;
  aContratar: number;
  aRealizar: number;
  tendencia: number;
  pctTendencia: number | null;
  desvio: number;
  desvioPct: number | null;
  desvioFavoravel: boolean | null;
};

export type CabecalhoDre = {
  obra: string;
  competencia: string;
  estudoVersao: string;
  estudoDataBase: string;
};

export type ResumoDre = {
  centroCustoId: string;
  obra: string;
  competencia: string;
  estudoVersao: string;
  margemOperacionalViabilidade: number | null;
  margemOperacionalTendencia: number | null;
  desvioMargemOperacional: number | null;
};

// Uma linha por tenant de marts.dre_resumo_carteira (migration 0031), já somada e com as frações prontas.
export type ResumoCarteiraDre = {
  obras: number;
  vgvBrutoTendencia: number;
  vgvVendido: number;
  pctVendido: number | null;
  receitaApropriada: number;
  poc: number | null;
  custoApropriado: number;
  recebidoAcumulado: number;
  lucroOperacionalViabilidade: number;
  lucroOperacionalTendencia: number;
  margemOperacionalViabilidade: number | null;
  margemOperacionalTendencia: number | null;
  desvioMargemOperacional: number | null;
};

export function lerResumoCarteiraDre(linha: Record<string, unknown>): ResumoCarteiraDre {
  return {
    obras: numeroOuZero(linha.obras),
    vgvBrutoTendencia: numeroOuZero(linha.vgv_bruto_tendencia),
    vgvVendido: numeroOuZero(linha.vgv_vendido),
    pctVendido: numeroOuNulo(linha.pct_vendido),
    receitaApropriada: numeroOuZero(linha.receita_apropriada),
    poc: numeroOuNulo(linha.poc),
    custoApropriado: numeroOuZero(linha.custo_apropriado),
    recebidoAcumulado: numeroOuZero(linha.recebido_acumulado),
    lucroOperacionalViabilidade: numeroOuZero(linha.lucro_operacional_viabilidade),
    lucroOperacionalTendencia: numeroOuZero(linha.lucro_operacional_tendencia),
    margemOperacionalViabilidade: numeroOuNulo(linha.margem_operacional_viabilidade),
    margemOperacionalTendencia: numeroOuNulo(linha.margem_operacional_tendencia),
    desvioMargemOperacional: numeroOuNulo(linha.desvio_margem_operacional),
  };
}

export function lerLinhaDre(linha: Record<string, unknown>): LinhaDre {
  return {
    linha: String(linha.linha),
    ordem: numeroOuZero(linha.ordem),
    nivel: numeroOuZero(linha.nivel),
    natureza: String(linha.natureza),
    linhaDeTotal: linha.linha_de_total === true,
    fonteRealizado: String(linha.fonte_realizado),
    viabilidade: numeroOuZero(linha.viabilidade),
    pctViabilidade: numeroOuNulo(linha.pct_viabilidade),
    apropriado: numeroOuZero(linha.apropriado),
    aApropriar: numeroOuZero(linha.a_apropriar),
    aContratar: numeroOuZero(linha.a_contratar),
    aRealizar: numeroOuZero(linha.a_realizar),
    tendencia: numeroOuZero(linha.tendencia),
    pctTendencia: numeroOuNulo(linha.pct_tendencia),
    desvio: numeroOuZero(linha.desvio),
    desvioPct: numeroOuNulo(linha.desvio_pct),
    desvioFavoravel: typeof linha.desvio_favoravel === "boolean" ? linha.desvio_favoravel : null,
  };
}

export function lerCabecalhoDre(linha: Record<string, unknown>): CabecalhoDre {
  return {
    obra: String(linha.obra),
    competencia: String(linha.competencia),
    estudoVersao: String(linha.estudo_versao),
    estudoDataBase: String(linha.estudo_data_base),
  };
}

export function lerResumoDre(linha: Record<string, unknown>): ResumoDre {
  return {
    centroCustoId: String(linha.centro_custo_id),
    obra: String(linha.obra),
    competencia: String(linha.competencia),
    estudoVersao: String(linha.estudo_versao),
    margemOperacionalViabilidade: numeroOuNulo(linha.margem_operacional_viabilidade),
    margemOperacionalTendencia: numeroOuNulo(linha.margem_operacional_tendencia),
    desvioMargemOperacional: numeroOuNulo(linha.desvio_margem_operacional),
  };
}

export type SituacaoDesvio = "favoravel" | "desfavoravel" | "neutro";

export type LinhaTabelaDre = LinhaDre & {
  rotulo: string;
  situacao: SituacaoDesvio;
  semRealizado: boolean;
};

function situacaoDesvio(favoravel: boolean | null): SituacaoDesvio {
  if (favoravel === null) return "neutro";
  return favoravel ? "favoravel" : "desfavoravel";
}

// Acrescenta só rótulo e marcas de leitura; a ordem é a da consulta e nenhum número muda.
export function prepararLinhasDre(linhas: LinhaDre[]): LinhaTabelaDre[] {
  return linhas.map((linha) => ({
    ...linha,
    rotulo: rotuloLinha(linha.linha),
    situacao: situacaoDesvio(linha.desvioFavoravel),
    semRealizado: linha.fonteRealizado === "sem_fonte",
  }));
}

// O texto diz a direção do desvio; a cor, que diz se é bom ou ruim, nunca aparece sozinha.
export function textoDesvio(desvio: number): string {
  if (desvio === 0) return "igual ao estudo";
  return `${formatarReal(Math.abs(desvio))} ${desvio > 0 ? "acima" : "abaixo"} do estudo`;
}

export function textoSituacao(situacao: SituacaoDesvio): string | null {
  if (situacao === "favoravel") return "favorável";
  if (situacao === "desfavoravel") return "desfavorável";
  return null;
}

export function percentualOuSemBase(fracao: number | null): string {
  return fracao === null ? "sem base" : formatarPercentual(fracao);
}

export function percentualComSinal(fracao: number | null): string {
  if (fracao === null) return "sem base";
  return `${fracao > 0 ? "+" : ""}${formatarPercentual(fracao)}`;
}

function pontosPercentuais(fracao: number): number {
  return Math.round(Math.abs(fracao) * 1000) / 10;
}

// Margem maior que a do estudo é sempre boa; o que arredonda para zero ponto fica neutro, como o texto.
export function situacaoDesvioMargem(fracao: number | null): SituacaoDesvio {
  if (fracao === null || pontosPercentuais(fracao) === 0) return "neutro";
  return fracao > 0 ? "favoravel" : "desfavoravel";
}

// Fração da view em pontos percentuais: 0,023 vira "2,3 pontos acima do estudo".
export function textoDesvioPontos(fracao: number | null): string {
  if (fracao === null) return "sem base";
  const pontos = pontosPercentuais(fracao);
  if (pontos === 0) return "igual ao estudo";
  return `${formatarDecimal(pontos)} ${pontos === 1 ? "ponto" : "pontos"} ${fracao > 0 ? "acima" : "abaixo"} do estudo`;
}

// Recebe data ISO ("2026-09-01") e devolve "09/2026".
export function formatarMesAno(competencia: string): string {
  const [ano, mes] = competencia.split("-");
  return `${mes}/${ano}`;
}

export function notaDre(cabecalho: CabecalhoDre): string {
  return `Realizado até ${formatarMesAno(cabecalho.competencia)}. Estudo versão ${cabecalho.estudoVersao}, de ${formatarData(cabecalho.estudoDataBase)}.`;
}

export type ColunaDre = {
  chave: keyof Pick<
    LinhaDre,
    | "viabilidade"
    | "pctViabilidade"
    | "apropriado"
    | "aApropriar"
    | "aContratar"
    | "aRealizar"
    | "tendencia"
    | "pctTendencia"
    | "desvio"
    | "desvioPct"
  >;
  rotulo: string;
  explicacao: ChaveExplicacao;
  percentual: boolean;
};

export const colunasDre: ColunaDre[] = [
  { chave: "viabilidade", rotulo: "Viabilidade", explicacao: "dre_viabilidade", percentual: false },
  { chave: "pctViabilidade", rotulo: "% Viab.", explicacao: "dre_pct_viabilidade", percentual: true },
  { chave: "apropriado", rotulo: "Apropriado", explicacao: "dre_apropriado", percentual: false },
  { chave: "aApropriar", rotulo: "A apropriar", explicacao: "dre_a_apropriar", percentual: false },
  { chave: "aContratar", rotulo: "A contratar", explicacao: "dre_a_contratar", percentual: false },
  { chave: "aRealizar", rotulo: "A realizar", explicacao: "dre_a_realizar", percentual: false },
  { chave: "tendencia", rotulo: "Tendência", explicacao: "dre_tendencia", percentual: false },
  { chave: "pctTendencia", rotulo: "% Tend.", explicacao: "dre_pct_tendencia", percentual: true },
  { chave: "desvio", rotulo: "Desvio", explicacao: "dre_desvio", percentual: false },
  { chave: "desvioPct", rotulo: "Desvio %", explicacao: "dre_desvio_pct", percentual: true },
];
