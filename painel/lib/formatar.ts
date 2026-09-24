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

export function formatarData(iso: string): string {
  // Data pura ("2026-09-22") não passa por Date, que a leria como meia-noite UTC e mostraria o dia anterior no Brasil.
  const dataPura = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  if (dataPura) {
    const [, ano, mes, dia] = dataPura;
    return `${dia}/${mes}/${ano}`;
  }
  return formatoDataHora.format(new Date(iso));
}
