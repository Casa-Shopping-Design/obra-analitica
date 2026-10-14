// Período, modo e aba da tela de empresa, lidos da URL. Tudo que vem da URL é conferido contra o intervalo
// carregado; valor estranho cai no padrão em vez de virar erro.

export const abasEmpresa = [
  { id: "fontes-usos", rotulo: "Fontes e Usos" },
  { id: "dre", rotulo: "DRE" },
  { id: "custo", rotulo: "Custo incorrido" },
  { id: "conferencia", rotulo: "Conferência" },
] as const;

export type AbaEmpresa = (typeof abasEmpresa)[number]["id"];

export type PeriodoEmpresa = {
  // Mês no formato aaaa-mm.
  inicio: string;
  fim: string;
  acumulado: boolean;
  mensal: boolean;
  aba: AbaEmpresa;
};

export type BuscaUrl = Record<string, string | string[] | undefined>;

export const maximoMesesGrade = 12;

const formatoMes = /^(\d{4})-(0[1-9]|1[0-2])$/;

function primeiroValor(valor: string | string[] | undefined): string | undefined {
  return Array.isArray(valor) ? valor[0] : valor;
}

// Recebe "2026-09-01" ou "2026-09" e devolve "2026-09"; aaaa-mm compara certo como texto.
export function mesDe(data: string): string {
  return data.slice(0, 7);
}

function mesValido(valor: string | undefined, minimo: string, maximo: string): string | null {
  if (!valor || !formatoMes.test(valor)) return null;
  return valor >= minimo && valor <= maximo ? valor : null;
}

function abaValida(valor: string | undefined): AbaEmpresa {
  return abasEmpresa.find((aba) => aba.id === valor)?.id ?? "fontes-usos";
}

// Padrão: acumulado até a última competência carregada, como a planilha. O mês inicial só pesa no movimento
// do período e na grade mês a mês; sem escolha, começa em janeiro do ano do mês final.
export function lerPeriodo(busca: BuscaUrl, limites: { primeira: string; ultima: string }): PeriodoEmpresa {
  const primeira = mesDe(limites.primeira);
  const ultima = mesDe(limites.ultima);
  const fim = mesValido(primeiroValor(busca.ate), primeira, ultima) ?? ultima;
  const janeiro = `${fim.slice(0, 4)}-01`;
  const inicio = mesValido(primeiroValor(busca.de), primeira, fim) ?? (janeiro > primeira ? janeiro : primeira);
  return {
    inicio,
    fim,
    acumulado: primeiroValor(busca.modo) !== "periodo",
    mensal: primeiroValor(busca.visao) === "mensal",
    aba: abaValida(primeiroValor(busca.aba)),
  };
}

// As funções do banco recebem o primeiro dia de cada mês, o mesmo formato da competência no staging.
export function parametrosDemonstrativo(empresaId: string, periodo: PeriodoEmpresa) {
  return {
    p_empresa: empresaId,
    p_inicio: `${periodo.inicio}-01`,
    p_fim: `${periodo.fim}-01`,
    p_acumulado: periodo.acumulado,
  };
}

function somarMeses(mes: string, quantidade: number): string {
  const [ano, numero] = mes.split("-").map(Number);
  const total = ano * 12 + (numero - 1) + quantidade;
  return `${Math.floor(total / 12)}-${String((total % 12) + 1).padStart(2, "0")}`;
}

// Meses do intervalo, do mais antigo ao mais recente. Acima de doze ficam os doze que terminam no mês final.
export function mesesDaGrade(periodo: Pick<PeriodoEmpresa, "inicio" | "fim">): string[] {
  const meses: string[] = [];
  for (let mes = periodo.fim; mes >= periodo.inicio && meses.length < maximoMesesGrade; mes = somarMeses(mes, -1)) {
    meses.push(mes);
  }
  return meses.reverse();
}

// Todos os meses carregados, do mais recente ao mais antigo, para os seletores.
export function mesesDisponiveis(limites: { primeira: string; ultima: string }): string[] {
  const primeira = mesDe(limites.primeira);
  const meses: string[] = [];
  for (let mes = mesDe(limites.ultima); mes >= primeira; mes = somarMeses(mes, -1)) meses.push(mes);
  return meses;
}

// Endereço da tela com o período atual e as mudanças pedidas; o padrão não vai para a URL.
export function enderecoEmpresa(id: string, periodo: PeriodoEmpresa, mudancas: Partial<PeriodoEmpresa> = {}): string {
  const alvo = { ...periodo, ...mudancas };
  const busca = new URLSearchParams();
  if (alvo.aba !== "fontes-usos") busca.set("aba", alvo.aba);
  busca.set("de", alvo.inicio);
  busca.set("ate", alvo.fim);
  if (!alvo.acumulado) busca.set("modo", "periodo");
  if (alvo.mensal) busca.set("visao", "mensal");
  return `/empresas/${id}?${busca.toString()}`;
}

const nomesMes = [
  "janeiro", "fevereiro", "março", "abril", "maio", "junho",
  "julho", "agosto", "setembro", "outubro", "novembro", "dezembro",
];

// "2026-09" vira "setembro de 2026".
export function rotuloMes(mes: string): string {
  const [ano, numero] = mes.split("-");
  return `${nomesMes[Number(numero) - 1]} de ${ano}`;
}

export function descreverPeriodo(periodo: PeriodoEmpresa): string {
  if (periodo.acumulado) return `Acumulado até ${rotuloMes(periodo.fim)}, como na planilha.`;
  if (periodo.inicio === periodo.fim) return `Movimento de ${rotuloMes(periodo.fim)}.`;
  return `Movimento de ${rotuloMes(periodo.inicio)} a ${rotuloMes(periodo.fim)}.`;
}
