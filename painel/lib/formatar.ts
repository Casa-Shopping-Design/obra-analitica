const formatoReal = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });
const formatoPercentual = new Intl.NumberFormat("pt-BR", {
  style: "percent",
  minimumFractionDigits: 1,
  maximumFractionDigits: 1,
});
const formatoDataHora = new Intl.DateTimeFormat("pt-BR", {
  timeZone: "America/Sao_Paulo",
  day: "2-digit",
  month: "2-digit",
  year: "numeric",
});

export function formatarReal(valor: number): string {
  return formatoReal.format(valor);
}

// Recebe fração: 0.37 vira "37,0%".
export function formatarPercentual(fracao: number): string {
  return formatoPercentual.format(fracao);
}

// Conversão do mês compara contagens do mesmo mês, então passa de 100% quando a venda vem de reserva de outro mês.
// Acima de 100% a tela diz o que aconteceu em vez de mostrar uma taxa que parece erro.
export function formatarConversao(fracao: number | null, acimaDoTotal: string): string {
  if (fracao === null) return "sem base";
  return fracao > 1 ? acimaDoTotal : formatarPercentual(fracao);
}

export function formatarData(iso: string): string {
  // Data pura ("2026-09-22") não passa por Date, que a leria como meia-noite UTC e mostraria o dia anterior no Brasil.
  const dataPura = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  if (dataPura) {
    const [, ano, mes, dia] = dataPura;
    return `${dia}/${mes}/${ano}`;
  }
  return formatoDataHora.format(new Date(iso));
}

const formatoRealCompacto = new Intl.NumberFormat("pt-BR", {
  style: "currency",
  currency: "BRL",
  notation: "compact",
  maximumFractionDigits: 1,
});
const nomesMes = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"];

// Para eixo de gráfico: 1.250.000 vira "R$ 1,3 mi".
export function formatarRealCompacto(valor: number): string {
  return formatoRealCompacto.format(valor);
}

// Recebe "aaaa-mm" ou data ISO e devolve "set/26".
export function formatarMes(competencia: string): string {
  const [ano, mes] = competencia.split("-");
  return `${nomesMes[Number(mes) - 1]}/${ano.slice(2)}`;
}

const formatoDecimal = new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 1 });

// Uma casa decimal, sem zero sobrando: 9.7 vira "9,7" e 2 vira "2".
export function formatarDecimal(valor: number): string {
  return formatoDecimal.format(valor);
}

export function formatarMeses(quantidade: number): string {
  const arredondado = Math.round(quantidade * 10) / 10;
  return arredondado === 1 ? "1 mês" : `${formatarDecimal(arredondado)} meses`;
}
