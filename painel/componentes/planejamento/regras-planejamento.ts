// Leitura e validação dos formulários de planejamento, feitas no servidor antes de chamar o banco,
// e as junções por mês das telas de comparação. Tudo puro: nenhum valor é somado ou derivado aqui,
// só conferido (a soma das frações da premissa é conferida em inteiros, sem arredondar nada).
import { lerDecimal } from "../../lib/simulacao";
import { mesDaData, mesPorExtenso, somarMeses } from "../../lib/periodo";

export type LerCampo = (nome: string) => string;

export function leitorDeFormulario(formulario: FormData): LerCampo {
  return (nome) => {
    const valor = formulario.get(nome);
    return typeof valor === "string" ? valor.trim() : "";
  };
}

export function leitorDeObjeto(valores: Record<string, string | undefined>): LerCampo {
  return (nome) => (valores[nome] ?? "").trim();
}

export type ErrosCampos = Record<string, string>;

export const limitesPlanejamento = {
  linhasMeta: 36,
  linhasPremissa: 60,
  mesesAntes: 12,
  mesesDepois: 72,
  textoCurto: 200,
  textoLongo: 1000,
  valorMaximo: 10_000_000_000,
  unidadesMaximas: 10_000,
} as const;

const formatoUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function ehUuid(texto: string): boolean {
  return formatoUuid.test(texto);
}

// "2026-10" vira "2026-10-01"; fora do intervalo aceito vira nulo.
export function lerMesDoFormulario(texto: string, dataReferencia: string): string | null {
  if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(texto)) return null;
  const mes = `${texto}-01`;
  const referencia = mesDaData(dataReferencia);
  if (mes < somarMeses(referencia, -limitesPlanejamento.mesesAntes)) return null;
  if (mes > somarMeses(referencia, limitesPlanejamento.mesesDepois)) return null;
  return mes;
}

export function mesesAceitos(dataReferencia: string): { valor: string; rotulo: string }[] {
  const referencia = mesDaData(dataReferencia);
  const total = limitesPlanejamento.mesesAntes + limitesPlanejamento.mesesDepois + 1;
  return Array.from({ length: total }, (_, posicao) => {
    const mes = somarMeses(referencia, posicao - limitesPlanejamento.mesesAntes);
    return { valor: mes.slice(0, 7), rotulo: mesPorExtenso(mes) };
  });
}

// Valor em reais com no máximo dois dígitos de centavos.
export function lerReais(texto: string): number | null {
  const numero = lerDecimal(texto);
  if (numero === null || numero > limitesPlanejamento.valorMaximo) return null;
  if (Math.abs(numero * 100 - Math.round(numero * 100)) > 1e-6) return null;
  return Number(numero.toFixed(2));
}

export function lerInteiroNaoNegativo(texto: string, maximo: number): number | null {
  if (!/^\d{1,9}$/.test(texto)) return null;
  const numero = Number(texto);
  return numero <= maximo ? numero : null;
}

// Percentual digitado ("60" ou "12,5") vira milionésimos inteiros de fração: 60% é 600000.
export function milionesimosDePercentual(texto: string): number | null {
  const numero = lerDecimal(texto);
  if (numero === null || numero > 100) return null;
  const milionesimos = Math.round(numero * 10_000);
  return Math.abs(milionesimos - numero * 10_000) < 1e-6 ? milionesimos : null;
}

export function fracaoDeMilionesimos(milionesimos: number): number {
  return Number((milionesimos / 1_000_000).toFixed(6));
}

export function lerTexto(texto: string, maximo: number, obrigatorio: boolean): string | null | undefined {
  if (texto === "") return obrigatorio ? undefined : null;
  if (texto.length > maximo) return undefined;
  return texto;
}

export type MetaMensalEntrada = {
  competencia: string;
  unidades: number | null;
  valor_contratado: number | null;
  fracao_financiada: number | null;
  recebimento_esperado: number | null;
  limite_aporte_proprio: number | null;
};

export type ResultadoMetas =
  | { ok: true; descricao: string; metas: MetaMensalEntrada[] }
  | { ok: false; erros: ErrosCampos };

// Linha i do formulário: mes_i, unidades_i, valor_i, fracao_i, recebimento_i, limite_i. Linha vazia é ignorada.
export function validarMetas(ler: LerCampo, dataReferencia: string): ResultadoMetas {
  const erros: ErrosCampos = {};
  const descricao = lerTexto(ler("descricao"), limitesPlanejamento.textoCurto, true);
  if (!descricao) erros.descricao = "Descreva a versão em até 200 caracteres (por exemplo, o motivo da revisão).";

  const metas: MetaMensalEntrada[] = [];
  const vistos = new Set<string>();
  for (let i = 0; i < limitesPlanejamento.linhasMeta; i++) {
    const campos = ["mes", "unidades", "valor", "fracao", "recebimento", "limite"].map((nome) => ler(`${nome}_${i}`));
    if (campos.every((campo) => campo === "")) continue;
    const [mesTexto, unidadesTexto, valorTexto, fracaoTexto, recebimentoTexto, limiteTexto] = campos;
    const competencia = lerMesDoFormulario(mesTexto, dataReferencia);
    if (!competencia) {
      erros[`mes_${i}`] = "Escolha o mês da meta.";
      continue;
    }
    if (vistos.has(competencia)) {
      erros[`mes_${i}`] = `${mesPorExtenso(competencia)} aparece mais de uma vez. Use uma linha por mês.`;
      continue;
    }
    vistos.add(competencia);

    const unidades = unidadesTexto === "" ? null : lerInteiroNaoNegativo(unidadesTexto, limitesPlanejamento.unidadesMaximas);
    if (unidadesTexto !== "" && unidades === null) erros[`unidades_${i}`] = "Informe um número inteiro de unidades.";
    const valor = valorTexto === "" ? null : lerReais(valorTexto);
    if (valorTexto !== "" && valor === null) erros[`valor_${i}`] = "Informe o valor em reais, com até dois centavos.";
    const fracao = fracaoTexto === "" ? null : milionesimosDePercentual(fracaoTexto);
    if (fracaoTexto !== "" && fracao === null) erros[`fracao_${i}`] = "Informe um percentual de 0% a 100%.";
    const recebimento = recebimentoTexto === "" ? null : lerReais(recebimentoTexto);
    if (recebimentoTexto !== "" && recebimento === null) erros[`recebimento_${i}`] = "Informe o valor em reais.";
    const limite = limiteTexto === "" ? null : lerReais(limiteTexto);
    if (limiteTexto !== "" && limite === null) erros[`limite_${i}`] = "Informe o valor em reais.";

    if ([unidadesTexto, valorTexto, fracaoTexto, recebimentoTexto, limiteTexto].every((campo) => campo === "")) {
      erros[`unidades_${i}`] = "Preencha pelo menos um valor da meta deste mês.";
    }
    metas.push({
      competencia,
      unidades,
      valor_contratado: valor,
      fracao_financiada: fracao === null ? null : fracaoDeMilionesimos(fracao),
      recebimento_esperado: recebimento,
      limite_aporte_proprio: limite,
    });
  }
  if (metas.length === 0 && !Object.keys(erros).some((chave) => chave.startsWith("mes_"))) {
    erros.mes_0 = "Preencha a meta de pelo menos um mês.";
  }
  if (Object.keys(erros).length > 0) return { ok: false, erros };
  metas.sort((a, b) => (a.competencia < b.competencia ? -1 : 1));
  return { ok: true, descricao: descricao as string, metas };
}

export type ResultadoPremissa =
  | { ok: true; fonte: string; observacao: string | null; meses: { competencia: string; fracao: number }[] }
  | { ok: false; erros: ErrosCampos };

// A soma das frações precisa ser exatamente 100%: conferida em milionésimos inteiros, como o banco.
export function validarPremissaDistribuicao(ler: LerCampo, dataReferencia: string): ResultadoPremissa {
  const erros: ErrosCampos = {};
  const fonte = lerTexto(ler("fonte"), limitesPlanejamento.textoCurto, true);
  if (!fonte) erros.fonte = "Informe a fonte da premissa (cronograma, planilha, reunião), em até 200 caracteres.";
  const observacao = lerTexto(ler("observacao"), limitesPlanejamento.textoLongo, false);
  if (observacao === undefined) erros.observacao = "Use até 1.000 caracteres.";

  const meses: { competencia: string; milionesimos: number }[] = [];
  const vistos = new Set<string>();
  for (let i = 0; i < limitesPlanejamento.linhasPremissa; i++) {
    const mesTexto = ler(`mes_${i}`);
    const percentualTexto = ler(`percentual_${i}`);
    if (mesTexto === "" && percentualTexto === "") continue;
    const competencia = lerMesDoFormulario(mesTexto, dataReferencia);
    if (!competencia) {
      erros[`mes_${i}`] = "Escolha o mês.";
      continue;
    }
    if (vistos.has(competencia)) {
      erros[`mes_${i}`] = `${mesPorExtenso(competencia)} aparece mais de uma vez.`;
      continue;
    }
    vistos.add(competencia);
    const milionesimos = milionesimosDePercentual(percentualTexto);
    if (milionesimos === null || milionesimos === 0) {
      erros[`percentual_${i}`] = "Informe um percentual maior que 0% e até 100%, com até quatro casas.";
      continue;
    }
    meses.push({ competencia, milionesimos });
  }
  if (meses.length === 0 && Object.keys(erros).every((chave) => !chave.startsWith("mes_") && !chave.startsWith("percentual_"))) {
    erros.mes_0 = "Informe pelo menos um mês com percentual.";
  }
  const soma = meses.reduce((total, mes) => total + mes.milionesimos, 0);
  if (meses.length > 0 && soma !== 1_000_000 && !Object.keys(erros).some((chave) => chave.startsWith("percentual_"))) {
    erros.soma = `Os percentuais precisam somar exatamente 100%. Hoje somam ${(soma / 10_000).toLocaleString("pt-BR", { maximumFractionDigits: 4 })}%.`;
  }
  if (Object.keys(erros).length > 0) return { ok: false, erros };
  return {
    ok: true,
    fonte: fonte as string,
    observacao: observacao ?? null,
    meses: meses
      .sort((a, b) => (a.competencia < b.competencia ? -1 : 1))
      .map((mes) => ({ competencia: mes.competencia, fracao: fracaoDeMilionesimos(mes.milionesimos) })),
  };
}

export function validarDescricaoVersao(ler: LerCampo): { ok: true; descricao: string } | { ok: false; erros: ErrosCampos } {
  const descricao = lerTexto(ler("descricao"), limitesPlanejamento.textoCurto, true);
  if (!descricao) return { ok: false, erros: { descricao: "Descreva a versão em até 200 caracteres." } };
  return { ok: true, descricao };
}

type ComCompetencia = { competencia: string };

export type LinhaLadoALado<A, B> = { competencia: string; a: A | null; b: B | null };

// Junta duas séries mensais pelo mês, sem calcular nada: cada lado mostra o que o banco devolveu.
// O(n log n) pela ordenação; n é o número de meses (dezenas).
export function juntarPorMes<A extends ComCompetencia, B extends ComCompetencia>(
  ladoA: readonly A[],
  ladoB: readonly B[],
): LinhaLadoALado<A, B>[] {
  const porMes = new Map<string, LinhaLadoALado<A, B>>();
  for (const linha of ladoA) {
    const mes = linha.competencia.slice(0, 10);
    porMes.set(mes, { competencia: mes, a: linha, b: null });
  }
  for (const linha of ladoB) {
    const mes = linha.competencia.slice(0, 10);
    const existente = porMes.get(mes) ?? { competencia: mes, a: null, b: null };
    existente.b = linha;
    porMes.set(mes, existente);
  }
  return [...porMes.values()].sort((x, y) => (x.competencia < y.competencia ? -1 : 1));
}

// Separa as metas de duas versões (vigente e escolhida para comparar) e junta pelo mês.
export function compararMetas<T extends ComCompetencia & { versao_id: string }>(
  metas: readonly T[],
  versaoVigente: string,
  versaoComparada: string | null,
): LinhaLadoALado<T, T>[] {
  const vigente = metas.filter((meta) => meta.versao_id === versaoVigente);
  const comparada = versaoComparada ? metas.filter((meta) => meta.versao_id === versaoComparada) : [];
  return juntarPorMes(vigente, comparada);
}

// Janela de meses da visão gerencial, escolhida na URL.
export const janelasPlanejamento = {
  curta: { rotulo: "6 meses antes e 12 depois", antes: 6, depois: 12 },
  longa: { rotulo: "12 meses antes e 24 depois", antes: 12, depois: 24 },
  tudo: { rotulo: "Todos os meses da obra", antes: null, depois: null },
} as const;
export type Janela = keyof typeof janelasPlanejamento;

export function limitesDaJanela(janela: Janela, dataReferencia: string): { inicio: string | null; fim: string | null } {
  const opcao = janelasPlanejamento[janela];
  const referencia = mesDaData(dataReferencia);
  return {
    inicio: opcao.antes === null ? null : somarMeses(referencia, -opcao.antes),
    fim: opcao.depois === null ? null : somarMeses(referencia, opcao.depois),
  };
}
