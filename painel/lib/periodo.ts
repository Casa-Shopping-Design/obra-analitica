// Filtros lidos da URL (período, opção de lista, data, página) e as contas de mês que eles exigem.
// Tudo puro: recebe texto da URL e a data de referência do banco, devolve valores já validados.

export const tiposPeriodo = ["mes", "trimestre", "ano", "doze_meses"] as const;
export type TipoPeriodo = (typeof tiposPeriodo)[number];

export const rotulosTipoPeriodo: Record<TipoPeriodo, string> = {
  mes: "Mês",
  trimestre: "Trimestre",
  ano: "Ano até o mês",
  doze_meses: "Últimos 12 meses",
};

// Valores de exibicao.periodo_padrao no catálogo de configuração e o tipo de período que cada um abre.
export const periodosDaPreferencia: Record<string, TipoPeriodo> = {
  mes: "mes",
  trimestre: "trimestre",
  ano_ate_mes: "ano",
  ultimos_12: "doze_meses",
};

export function tipoPeriodoDaPreferencia(valor: unknown, padrao: TipoPeriodo): TipoPeriodo {
  return typeof valor === "string" && Object.hasOwn(periodosDaPreferencia, valor) ? periodosDaPreferencia[valor] : padrao;
}

// inicio e fim são o primeiro dia do mês ("aaaa-mm-01"), como a coluna competencia do banco.
export type Periodo = { tipo: TipoPeriodo; mes: string; inicio: string; fim: string; rotulo: string };

export type ValorUrl = string | string[] | undefined;

const nomesMesExtenso = [
  "janeiro",
  "fevereiro",
  "março",
  "abril",
  "maio",
  "junho",
  "julho",
  "agosto",
  "setembro",
  "outubro",
  "novembro",
  "dezembro",
];
const nomesMesCurto = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"];

// Quantos meses para trás o filtro aceita; mais que isso é endereço digitado à mão.
export const mesesNoFiltro = 60;

function primeiroValor(valor: ValorUrl): string | undefined {
  return Array.isArray(valor) ? valor[0] : valor;
}

function indiceMes(mes: string): number {
  const [ano, numero] = mes.split("-").map(Number);
  return ano * 12 + (numero - 1);
}

function mesDoIndice(indice: number): string {
  const ano = Math.floor(indice / 12);
  const numero = (indice % 12) + 1;
  return `${ano}-${String(numero).padStart(2, "0")}-01`;
}

function dataValida(texto: string): boolean {
  const partes = /^(\d{4})-(\d{2})-(\d{2})$/.exec(texto);
  if (!partes) return false;
  const [, ano, mes, dia] = partes.map(Number);
  const data = new Date(Date.UTC(ano, mes - 1, dia));
  return data.getUTCFullYear() === ano && data.getUTCMonth() === mes - 1 && data.getUTCDate() === dia;
}

// "2026-09-26" vira "2026-09-01".
export function mesDaData(data: string): string {
  return `${data.slice(0, 7)}-01`;
}

// Soma meses a um mês "aaaa-mm-01" (ou data), nos dois sentidos, atravessando a virada do ano.
export function somarMeses(mes: string, quantidade: number): string {
  return mesDoIndice(indiceMes(mes.slice(0, 7)) + quantidade);
}

// Mesma regra do banco: mês-calendário seguinte ao da data de referência. 15/12/2026 dá 01/01/2027.
export function proximoMes(dataReferencia: string): string {
  return somarMeses(dataReferencia, 1);
}

// "2026-10-01" vira "outubro de 2026".
export function mesPorExtenso(mes: string): string {
  const [ano, numero] = mes.split("-").map(Number);
  return `${nomesMesExtenso[numero - 1]} de ${ano}`;
}

function mesCurto(mes: string): string {
  const [ano, numero] = mes.split("-");
  return `${nomesMesCurto[Number(numero) - 1]}/${ano.slice(2)}`;
}

// Data de hoje no fuso de Brasília, para quando o banco não devolve a data de referência.
export function hojeEmSaoPaulo(agora: Date = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Sao_Paulo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(agora);
}

// Hora "hh:mm" de um instante, no fuso de Brasília.
export function horaEmSaoPaulo(instante: string): string {
  return new Intl.DateTimeFormat("pt-BR", {
    timeZone: "America/Sao_Paulo",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).format(new Date(instante));
}

function rotuloPeriodo(tipo: TipoPeriodo, inicio: string, fim: string): string {
  if (tipo === "mes") return mesPorExtenso(fim);
  if (tipo === "trimestre") {
    const trimestre = Math.floor((Number(inicio.slice(5, 7)) - 1) / 3) + 1;
    const meses = inicio === fim ? mesCurto(fim) : `${mesCurto(inicio)} a ${mesCurto(fim)}`;
    return `${trimestre}º trimestre de ${inicio.slice(0, 4)} (${meses})`;
  }
  if (tipo === "ano") {
    return inicio === fim
      ? mesPorExtenso(fim)
      : `${nomesMesExtenso[Number(inicio.slice(5, 7)) - 1]} a ${mesPorExtenso(fim)}`;
  }
  return `${mesCurto(inicio)} a ${mesCurto(fim)}`;
}

// Nenhum período passa do mês da data de referência: o futuro não tem competência realizada.
export function calcularPeriodo(tipo: TipoPeriodo, mes: string, dataReferencia: string): Periodo {
  const mesReferencia = mesDaData(dataReferencia);
  const mesEscolhido = mesDaData(mes) > mesReferencia ? mesReferencia : mesDaData(mes);
  const indice = indiceMes(mesEscolhido.slice(0, 7));
  let inicio = mesEscolhido;
  let fim = mesEscolhido;
  if (tipo === "trimestre") {
    const primeiro = indice - (indice % 12) + Math.floor((indice % 12) / 3) * 3;
    inicio = mesDoIndice(primeiro);
    fim = mesDoIndice(primeiro + 2);
    if (fim > mesReferencia) fim = mesReferencia;
  } else if (tipo === "ano") {
    inicio = mesDoIndice(indice - (indice % 12));
  } else if (tipo === "doze_meses") {
    inicio = mesDoIndice(indice - 11);
  }
  return { tipo, mes: mesEscolhido, inicio, fim, rotulo: rotuloPeriodo(tipo, inicio, fim) };
}

export function lerOpcao<T extends string>(valor: ValorUrl, opcoes: readonly T[], padrao: T): T {
  const texto = primeiroValor(valor);
  return opcoes.find((opcao) => opcao === texto) ?? padrao;
}

// Aceita "aaaa-mm" entre o mês de referência e mesesNoFiltro meses antes; o resto cai no mês de referência.
export function lerMes(valor: ValorUrl, dataReferencia: string): string {
  const mesReferencia = mesDaData(dataReferencia);
  const texto = primeiroValor(valor);
  if (!texto || !/^\d{4}-(0[1-9]|1[0-2])$/.test(texto)) return mesReferencia;
  const mes = `${texto}-01`;
  if (mes > mesReferencia || mes < somarMeses(mesReferencia, -(mesesNoFiltro - 1))) return mesReferencia;
  return mes;
}

export function lerPeriodo(
  valores: { periodo?: ValorUrl; mes?: ValorUrl },
  dataReferencia: string,
  padrao: TipoPeriodo = "ano",
): Periodo {
  const tipo = lerOpcao(valores.periodo, tiposPeriodo, padrao);
  return calcularPeriodo(tipo, lerMes(valores.mes, dataReferencia), dataReferencia);
}

// Meses oferecidos no filtro, do mais recente para o mais antigo, como "aaaa-mm".
export function mesesDoFiltro(
  dataReferencia: string,
  quantidade: number = mesesNoFiltro,
): { valor: string; rotulo: string }[] {
  const mesReferencia = mesDaData(dataReferencia);
  return Array.from({ length: quantidade }, (_, posicao) => {
    const mes = somarMeses(mesReferencia, -posicao);
    return { valor: mes.slice(0, 7), rotulo: mesPorExtenso(mes) };
  });
}

export function lerData(valor: ValorUrl): string | null {
  const texto = primeiroValor(valor);
  return texto && dataValida(texto) ? texto : null;
}

const formatoUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Obra fora do formato vira consolidado; obra de outro tenant volta vazia pelo RLS.
export function lerIdCentro(valor: ValorUrl): string | null {
  const texto = primeiroValor(valor);
  return texto && formatoUuid.test(texto) ? texto.toLowerCase() : null;
}

export const linhasPorPagina = 50;
// Teto de páginas aceitas na URL; 30.000 parcelas por tenant dão 600 páginas.
const paginaMaxima = 10_000;

export function lerPagina(valor: ValorUrl): number {
  const texto = primeiroValor(valor);
  if (!texto || !/^\d{1,5}$/.test(texto)) return 1;
  const pagina = Number(texto);
  return pagina >= 1 && pagina <= paginaMaxima ? pagina : 1;
}

export type Paginacao = {
  pagina: number;
  totalPaginas: number;
  totalLinhas: number;
  // Índices para .range() do PostgREST, com fim incluído.
  de: number;
  ate: number;
  anterior: number | null;
  proxima: number | null;
};

export function intervaloDaPagina(pagina: number, tamanho: number = linhasPorPagina): { de: number; ate: number } {
  const de = (pagina - 1) * tamanho;
  return { de, ate: de + tamanho - 1 };
}

// Com o total devolvido pelo banco, fecha a página pedida no intervalo existente.
export function montarPaginacao(pagina: number, totalLinhas: number, tamanho: number = linhasPorPagina): Paginacao {
  const totalPaginas = Math.max(1, Math.ceil(totalLinhas / tamanho));
  const atual = Math.min(Math.max(1, pagina), totalPaginas);
  const { de, ate } = intervaloDaPagina(atual, tamanho);
  return {
    pagina: atual,
    totalPaginas,
    totalLinhas,
    de,
    ate: Math.min(ate, Math.max(totalLinhas - 1, de)),
    anterior: atual > 1 ? atual - 1 : null,
    proxima: atual < totalPaginas ? atual + 1 : null,
  };
}

// Monta o endereço com os filtros atuais, trocando só o que mudou e tirando os vazios.
export function montarEndereco(caminho: string, filtros: Record<string, string | number | null | undefined>): string {
  const parametros = new URLSearchParams();
  for (const [chave, valor] of Object.entries(filtros)) {
    if (valor !== null && valor !== undefined && valor !== "") parametros.set(chave, String(valor));
  }
  const busca = parametros.toString();
  return busca ? `${caminho}?${busca}` : caminho;
}
