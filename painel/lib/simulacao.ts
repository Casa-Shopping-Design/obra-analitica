// Premissas da simulação de caixa: lidas do formulário, validadas aqui no servidor com as regras da
// seção 4.1 do contrato de dados e mandadas ao banco como objeto. Nada de texto concatenado.
import type { PadroesSimulacao } from "./configuracao";
import { mesDaData, mesPorExtenso, somarMeses } from "./periodo";

export type PremissasSimulacao = {
  novas_vendas?: { competencia: string; quantidade: number }[];
  desconto_tabela?: number;
  composicao?: { entrada: number; parcelas_mensais: number; quantidade_parcelas_mensais: number; financiamento: number };
  meses_ate_liberacao_financiamento?: number;
  atraso_liberacao_bancaria_meses?: number;
  deslocamento_cronograma_meses?: number;
  fator_cronograma?: number;
  cancelar_contratos?: number[];
  custo_campanha?: { competencia: string; valor: number }[];
};

export type LinhaSimulacao = {
  competencia: string;
  recebido: number;
  carteira_prevista: number;
  novas_vendas_unidades: number;
  novas_vendas_valor: number;
  entradas_novas_vendas_direta: number;
  entradas_novas_vendas_financiamento: number;
  pago: number;
  a_pagar: number;
  custo_sem_titulo: number;
  custo_campanha: number;
  total_entradas: number;
  total_saidas: number;
  saldo_mes: number;
  caixa_gerado_acumulado: number;
  necessidade_aporte_acumulada: number;
  aporte_incremental_mes: number;
  aviso: "vendas_limitadas_ao_estoque" | null;
  premissas: PremissasSimulacao;
};

// Campos do formulário, com o nome que vai na URL.
export const camposSimulacao = [
  "vendas_por_mes",
  "mes_inicio_vendas",
  "meses_vendas",
  "desconto",
  "entrada",
  "parcelas",
  "quantidade_parcelas",
  "financiamento",
  "meses_liberacao",
  "atraso_liberacao",
  "deslocamento_gastos",
  "fator_gastos",
  "mes_campanha",
  "custo_campanha",
] as const;
export type CampoSimulacao = (typeof camposSimulacao)[number];
export type FormularioSimulacao = Record<CampoSimulacao, string>;

// Tetos de sanidade: acima disso é digitação errada, não cenário.
export const limitesSimulacao = {
  vendasPorMes: 200,
  mesesVendas: 36,
  mesesAFrente: 60,
  // Mesmo teto do catálogo de configuração (simulacao.quantidade_parcelas e simulacao.meses_ate_liberacao).
  quantidadeParcelas: 600,
  mesesLiberacao: 600,
  atrasoLiberacao: 24,
  deslocamentoGastos: 24,
  fatorGastosMaximo: 300,
  custoCampanhaMaximo: 1_000_000_000,
} as const;

// Fração vira o percentual que a pessoa digita: 0.125 aparece como "12,5".
function textoPercentual(fracao: number): string {
  return String(Number((fracao * 100).toFixed(4))).replace(".", ",");
}

// Sem padrão da obra (ou com a consulta falhando), valem os números fixos anteriores à configuração.
export function formularioPadrao(dataReferencia: string, padroes?: PadroesSimulacao | null): FormularioSimulacao {
  const percentual = (fracao: number | null | undefined, reserva: string) =>
    fracao === null || fracao === undefined ? reserva : textoPercentual(fracao);
  const inteiro = (valor: number | null | undefined, reserva: string) =>
    valor === null || valor === undefined || !Number.isInteger(valor) ? reserva : String(valor);
  return {
    vendas_por_mes: "2",
    mes_inicio_vendas: somarMeses(dataReferencia, 1).slice(0, 7),
    meses_vendas: "6",
    desconto: percentual(padroes?.desconto, "0"),
    entrada: percentual(padroes?.fracao_entrada, "10"),
    parcelas: percentual(padroes?.fracao_parcelas, "30"),
    quantidade_parcelas: inteiro(padroes?.quantidade_parcelas, "24"),
    financiamento: percentual(padroes?.fracao_financiamento, "60"),
    meses_liberacao: inteiro(padroes?.meses_ate_liberacao, "4"),
    atraso_liberacao: "0",
    deslocamento_gastos: "0",
    fator_gastos: "100",
    mes_campanha: "",
    custo_campanha: "",
  };
}

// Campo ausente na URL fica com o valor padrão (o da obra, quando houver); campo presente e vazio continua vazio.
export function lerFormularioSimulacao(
  valores: Record<string, string | string[] | undefined>,
  dataReferencia: string,
  padroes?: PadroesSimulacao | null,
): FormularioSimulacao {
  const padrao = formularioPadrao(dataReferencia, padroes);
  const lido = { ...padrao };
  for (const campo of camposSimulacao) {
    const valor = valores[campo];
    const texto = Array.isArray(valor) ? valor[0] : valor;
    if (texto !== undefined) lido[campo] = texto.trim().slice(0, 40);
  }
  return lido;
}

// Aceita "1.234,56", "1234,56" e "1234.56". Devolve nulo para qualquer outra coisa.
export function lerDecimal(texto: string): number | null {
  const limpo = texto.replace(/\s|R\$/g, "");
  if (limpo === "") return null;
  const normalizado = limpo.includes(",") ? limpo.replace(/\./g, "").replace(",", ".") : limpo;
  if (!/^\d+(\.\d+)?$/.test(normalizado)) return null;
  const numero = Number(normalizado);
  return Number.isFinite(numero) ? numero : null;
}

function lerInteiro(texto: string): number | null {
  if (!/^\d{1,6}$/.test(texto.trim())) return null;
  return Number(texto.trim());
}

// Percentual digitado vira centésimos de ponto inteiros, para a soma da composição ser exata.
function centesimosDePercentual(texto: string): number | null {
  const numero = lerDecimal(texto);
  if (numero === null) return null;
  const centesimos = Math.round(numero * 100);
  return Math.abs(centesimos - numero * 100) < 1e-6 ? centesimos : null;
}

function lerMesUrl(texto: string): string | null {
  return /^\d{4}-(0[1-9]|1[0-2])$/.test(texto) ? `${texto}-01` : null;
}

export type ItemPremissa = { rotulo: string; valor: string };

export type ResultadoValidacao =
  | { ok: true; premissas: PremissasSimulacao; resumo: ItemPremissa[] }
  | { ok: false; erros: Partial<Record<CampoSimulacao, string>> };

const formatoPercentual = new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 2 });
const formatoReal = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });

function percentual(centesimos: number): string {
  return `${formatoPercentual.format(centesimos / 100)}%`;
}

function fracaoDeCentesimos(centesimos: number): number {
  return Number((centesimos / 10_000).toFixed(6));
}

function plural(quantidade: number, singular: string, varios: string): string {
  return `${quantidade} ${quantidade === 1 ? singular : varios}`;
}

// estoque: unidades à venda na obra (nulo quando a contagem falhou; o banco limita de novo).
export function validarPremissas(
  formulario: FormularioSimulacao,
  contexto: { dataReferencia: string; estoque: number | null },
): ResultadoValidacao {
  const erros: Partial<Record<CampoSimulacao, string>> = {};
  const mesReferencia = mesDaData(contexto.dataReferencia);
  const ultimoMes = somarMeses(mesReferencia, limitesSimulacao.mesesAFrente);

  const vendasPorMes = lerInteiro(formulario.vendas_por_mes);
  if (vendasPorMes === null || vendasPorMes > limitesSimulacao.vendasPorMes) {
    erros.vendas_por_mes = `Informe um número inteiro de 0 a ${limitesSimulacao.vendasPorMes}.`;
  }
  const mesesVendas = lerInteiro(formulario.meses_vendas);
  if (mesesVendas === null || mesesVendas < 1 || mesesVendas > limitesSimulacao.mesesVendas) {
    erros.meses_vendas = `Informe de 1 a ${limitesSimulacao.mesesVendas} meses.`;
  }
  const mesInicio = lerMesUrl(formulario.mes_inicio_vendas);
  if (!mesInicio || mesInicio < mesReferencia || mesInicio > ultimoMes) {
    erros.mes_inicio_vendas = `Escolha um mês entre ${mesPorExtenso(mesReferencia)} e ${mesPorExtenso(ultimoMes)}.`;
  }

  const vendeAlgo = vendasPorMes !== null && vendasPorMes > 0;
  const totalPedido = vendasPorMes !== null && mesesVendas !== null ? vendasPorMes * mesesVendas : null;
  if (
    vendeAlgo &&
    totalPedido !== null &&
    contexto.estoque !== null &&
    totalPedido > contexto.estoque &&
    !erros.vendas_por_mes
  ) {
    erros.vendas_por_mes =
      contexto.estoque === 0
        ? "A obra não tem unidades à venda. Deixe as vendas em 0 para simular só atraso e gastos."
        : `Você pediu ${totalPedido} vendas, mas a obra tem ${plural(contexto.estoque, "unidade", "unidades")} à venda. Diminua as vendas por mês ou os meses.`;
  }

  const desconto = centesimosDePercentual(formulario.desconto);
  if (desconto === null || desconto >= 10_000) erros.desconto = "Informe um desconto de 0% a menos de 100%.";

  const entrada = centesimosDePercentual(formulario.entrada);
  const parcelas = centesimosDePercentual(formulario.parcelas);
  const financiamento = centesimosDePercentual(formulario.financiamento);
  if (entrada === null || entrada > 10_000) erros.entrada = "Informe um percentual de 0% a 100%.";
  if (parcelas === null || parcelas > 10_000) erros.parcelas = "Informe um percentual de 0% a 100%.";
  if (financiamento === null || financiamento > 10_000) erros.financiamento = "Informe um percentual de 0% a 100%.";
  if (
    vendeAlgo &&
    entrada !== null &&
    parcelas !== null &&
    financiamento !== null &&
    !erros.entrada &&
    !erros.parcelas &&
    !erros.financiamento &&
    entrada + parcelas + financiamento !== 10_000
  ) {
    erros.financiamento = `Entrada, parcelas e financiamento precisam somar 100%. Hoje somam ${percentual(entrada + parcelas + financiamento)}.`;
  }

  const quantidadeParcelas = lerInteiro(formulario.quantidade_parcelas);
  if (
    vendeAlgo &&
    parcelas !== null &&
    parcelas > 0 &&
    (quantidadeParcelas === null || quantidadeParcelas < 1 || quantidadeParcelas > limitesSimulacao.quantidadeParcelas)
  ) {
    erros.quantidade_parcelas = `Informe de 1 a ${limitesSimulacao.quantidadeParcelas} parcelas.`;
  }

  const mesesLiberacao = lerInteiro(formulario.meses_liberacao);
  if (
    vendeAlgo &&
    financiamento !== null &&
    financiamento > 0 &&
    (mesesLiberacao === null || mesesLiberacao > limitesSimulacao.mesesLiberacao)
  ) {
    erros.meses_liberacao = `Informe de 0 a ${limitesSimulacao.mesesLiberacao} meses.`;
  }

  const atraso = lerInteiro(formulario.atraso_liberacao);
  if (atraso === null || atraso > limitesSimulacao.atrasoLiberacao) {
    erros.atraso_liberacao = `Informe de 0 a ${limitesSimulacao.atrasoLiberacao} meses.`;
  }
  const deslocamento = lerInteiro(formulario.deslocamento_gastos);
  if (deslocamento === null || deslocamento > limitesSimulacao.deslocamentoGastos) {
    erros.deslocamento_gastos = `Informe de 0 a ${limitesSimulacao.deslocamentoGastos} meses.`;
  }
  const fator = centesimosDePercentual(formulario.fator_gastos);
  if (fator === null || fator <= 0 || fator > limitesSimulacao.fatorGastosMaximo * 100) {
    erros.fator_gastos = `Informe um percentual maior que 0% e até ${limitesSimulacao.fatorGastosMaximo}%.`;
  }

  const temCampanha = formulario.mes_campanha !== "" || formulario.custo_campanha !== "";
  const mesCampanha = lerMesUrl(formulario.mes_campanha);
  const custoCampanha = lerDecimal(formulario.custo_campanha);
  if (temCampanha) {
    if (!mesCampanha || mesCampanha < mesReferencia || mesCampanha > ultimoMes) {
      erros.mes_campanha = `Escolha um mês entre ${mesPorExtenso(mesReferencia)} e ${mesPorExtenso(ultimoMes)}.`;
    }
    if (custoCampanha === null || custoCampanha <= 0 || custoCampanha > limitesSimulacao.custoCampanhaMaximo) {
      erros.custo_campanha = "Informe o custo da campanha em reais, maior que zero.";
    } else if (Math.abs(custoCampanha * 100 - Math.round(custoCampanha * 100)) > 1e-6) {
      erros.custo_campanha = "Use no máximo dois dígitos de centavos.";
    }
  }

  if (Object.keys(erros).length > 0) return { ok: false, erros };

  // A partir daqui todos os valores foram conferidos acima.
  const qtd = vendasPorMes as number;
  const nMeses = mesesVendas as number;
  const inicio = mesInicio as string;
  const premissas: PremissasSimulacao = {
    novas_vendas: qtd > 0 ? Array.from({ length: nMeses }, (_, i) => ({ competencia: somarMeses(inicio, i), quantidade: qtd })) : [],
    desconto_tabela: fracaoDeCentesimos(desconto as number),
    atraso_liberacao_bancaria_meses: atraso as number,
    deslocamento_cronograma_meses: deslocamento as number,
    fator_cronograma: fracaoDeCentesimos(fator as number),
    custo_campanha: temCampanha ? [{ competencia: mesCampanha as string, valor: Number((custoCampanha as number).toFixed(2)) }] : [],
  };
  if (qtd > 0) {
    premissas.composicao = {
      entrada: fracaoDeCentesimos(entrada as number),
      parcelas_mensais: fracaoDeCentesimos(parcelas as number),
      quantidade_parcelas_mensais: (parcelas as number) > 0 ? (quantidadeParcelas as number) : 1,
      financiamento: fracaoDeCentesimos(financiamento as number),
    };
    if ((financiamento as number) > 0) premissas.meses_ate_liberacao_financiamento = mesesLiberacao as number;
  }

  const resumo: ItemPremissa[] = [
    {
      rotulo: "Novas vendas",
      valor:
        qtd > 0
          ? `${plural(qtd, "unidade", "unidades")} por mês durante ${plural(nMeses, "mês", "meses")}, a partir de ${mesPorExtenso(inicio)}`
          : "Nenhuma",
    },
  ];
  if (qtd > 0) {
    resumo.push(
      { rotulo: "Preço", valor: `Tabela de hoje com ${percentual(desconto as number)} de desconto` },
      {
        rotulo: "Composição",
        valor: `Entrada ${percentual(entrada as number)}, parcelas mensais ${percentual(parcelas as number)}${(parcelas as number) > 0 ? ` em ${quantidadeParcelas}x` : ""}, financiamento ${percentual(financiamento as number)}`,
      },
    );
    if ((financiamento as number) > 0) {
      resumo.push({
        rotulo: "Liberação do financiamento das novas vendas",
        valor: `${plural(mesesLiberacao as number, "mês", "meses")} depois da venda`,
      });
    }
  }
  resumo.push(
    { rotulo: "Atraso nas liberações do banco", valor: plural(atraso as number, "mês", "meses") },
    {
      rotulo: "Cronograma do custo sem título",
      valor: `Deslocado ${plural(deslocamento as number, "mês", "meses")}, ${percentual(fator as number)} do valor`,
    },
    {
      rotulo: "Campanha comercial (hipótese)",
      valor: temCampanha
        ? `${formatoReal.format(custoCampanha as number)} em ${mesPorExtenso(mesCampanha as string)}`
        : "Nenhuma",
    },
  );
  return { ok: true, premissas, resumo };
}

// Mês de maior necessidade de aporte numa série já calculada pelo banco; só escolhe, não recalcula.
// O(n) sobre os meses. Nulo quando a necessidade nunca passa de zero.
export function piorMes<T extends { competencia: string; necessidade_aporte_acumulada: number }>(
  linhas: readonly T[],
): T | null {
  let pior: T | null = null;
  for (const linha of linhas) {
    if (linha.necessidade_aporte_acumulada <= 0) continue;
    if (!pior || linha.necessidade_aporte_acumulada > pior.necessidade_aporte_acumulada) pior = linha;
  }
  return pior;
}

export type PontoComparacao = {
  competencia: string;
  base: number | null;
  simulado: number | null;
};

// Junta a projeção sem premissas e a simulação pelo mês, para o gráfico e a tabela. O(n log n).
export function juntarBaseESimulacao(
  base: readonly { competencia: string; caixa_gerado_acumulado: number }[],
  simulacao: readonly { competencia: string; caixa_gerado_acumulado: number }[],
): PontoComparacao[] {
  const pontos = new Map<string, PontoComparacao>();
  for (const linha of base) {
    const mes = linha.competencia.slice(0, 10);
    pontos.set(mes, { competencia: mes, base: linha.caixa_gerado_acumulado, simulado: null });
  }
  for (const linha of simulacao) {
    const mes = linha.competencia.slice(0, 10);
    const ponto = pontos.get(mes) ?? { competencia: mes, base: null, simulado: null };
    ponto.simulado = linha.caixa_gerado_acumulado;
    pontos.set(mes, ponto);
  }
  return [...pontos.values()].sort((a, b) => (a.competencia < b.competencia ? -1 : 1));
}
