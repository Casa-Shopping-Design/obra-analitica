// Monta a série do gráfico da obra a partir das linhas das views. Só junta por mês, ordena e recorta;
// nenhum valor é somado ou derivado aqui, todos saem do banco.

export type LinhaFluxoMensal = {
  competencia: string;
  entrada_direta_realizada: number | string;
  entrada_direta_prevista: number | string;
  entrada_direta_vencida: number | string;
  repasse_realizado: number | string;
  repasse_previsto: number | string;
  repasse_vencido: number | string;
  saida_realizada: number | string;
  saida_prevista: number | string;
  saida_vencida: number | string;
  saldo_acumulado: number | string;
};

export type LinhaFluxoCenario = {
  competencia: string;
  entrada_direta: number | string;
  repasse: number | string;
  saida: number | string;
  saldo_acumulado: number | string;
};

// No cenário com atraso, a função do banco devolve o repasse já deslocado numa coluna só, sem separar
// realizado de previsto. Por isso repasseRealizado e repassePrevisto ficam nulos e repasseCenario é preenchido.
export type PontoFluxo = {
  competencia: string;
  entradaDiretaRealizada: number | null;
  entradaDiretaPrevista: number | null;
  repasseRealizado: number | null;
  repassePrevisto: number | null;
  repasseCenario: number | null;
  saidaRealizada: number | null;
  saidaPrevista: number | null;
  saidaVencida: number | null;
  saldoAcumulado: number | null;
};

export const mesesParaTras = 12;
export const mesesParaFrente = 24;

// O PostgREST pode devolver numeric como texto; converter não altera o valor.
function paraNumero(valor: number | string | null | undefined): number | null {
  if (valor === null || valor === undefined) return null;
  const numero = Number(valor);
  return Number.isFinite(numero) ? numero : null;
}

function chaveMes(competencia: string): string {
  return competencia.slice(0, 7);
}

// Desloca "aaaa-mm" em n meses, para achar as bordas da janela.
export function deslocarMes(mes: string, quantidade: number): string {
  const [ano, numeroMes] = mes.split("-").map(Number);
  const indice = ano * 12 + (numeroMes - 1) + quantidade;
  const anoNovo = Math.floor(indice / 12);
  const mesNovo = (indice % 12) + 1;
  return `${anoNovo}-${String(mesNovo).padStart(2, "0")}`;
}

// Mês corrente no fuso de Brasília, no formato "aaaa-mm".
export function mesCorrente(agora: Date = new Date()): string {
  const partes = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Sao_Paulo",
    year: "numeric",
    month: "2-digit",
  }).formatToParts(agora);
  const ano = partes.find((parte) => parte.type === "year")?.value;
  const mes = partes.find((parte) => parte.type === "month")?.value;
  return `${ano}-${mes}`;
}

function pontoVazio(competencia: string): PontoFluxo {
  return {
    competencia,
    entradaDiretaRealizada: null,
    entradaDiretaPrevista: null,
    repasseRealizado: null,
    repassePrevisto: null,
    repasseCenario: null,
    saidaRealizada: null,
    saidaPrevista: null,
    saidaVencida: null,
    saldoAcumulado: null,
  };
}

// O(n log n) pela ordenação, com n no máximo de algumas centenas de meses por obra.
export function montarSerieFluxo(
  linhasMensais: LinhaFluxoMensal[],
  linhasCenario: LinhaFluxoCenario[] | null,
  mesReferencia: string,
): PontoFluxo[] {
  const inicio = deslocarMes(mesReferencia, -mesesParaTras);
  const fim = deslocarMes(mesReferencia, mesesParaFrente - 1);
  const dentroDaJanela = (mes: string) => mes >= inicio && mes <= fim;
  const pontos = new Map<string, PontoFluxo>();

  for (const linha of linhasMensais) {
    const mes = chaveMes(linha.competencia);
    if (!dentroDaJanela(mes)) continue;
    const ponto = pontos.get(mes) ?? pontoVazio(mes);
    ponto.entradaDiretaRealizada = paraNumero(linha.entrada_direta_realizada);
    ponto.entradaDiretaPrevista = paraNumero(linha.entrada_direta_prevista);
    ponto.saidaRealizada = paraNumero(linha.saida_realizada);
    ponto.saidaPrevista = paraNumero(linha.saida_prevista);
    ponto.saidaVencida = paraNumero(linha.saida_vencida);
    if (!linhasCenario) {
      ponto.repasseRealizado = paraNumero(linha.repasse_realizado);
      ponto.repassePrevisto = paraNumero(linha.repasse_previsto);
      ponto.saldoAcumulado = paraNumero(linha.saldo_acumulado);
    }
    pontos.set(mes, ponto);
  }

  for (const linha of linhasCenario ?? []) {
    const mes = chaveMes(linha.competencia);
    if (!dentroDaJanela(mes)) continue;
    const ponto = pontos.get(mes) ?? pontoVazio(mes);
    ponto.repasseCenario = paraNumero(linha.repasse);
    ponto.saldoAcumulado = paraNumero(linha.saldo_acumulado);
    pontos.set(mes, ponto);
  }

  return [...pontos.values()].sort((a, b) => (a.competencia < b.competencia ? -1 : 1));
}
