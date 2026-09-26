// Monta a resposta das perguntas prontas a partir das linhas que as funções de lib/consultas devolvem:
// conclusão curta, tabelas separadas por natureza (fato, previsão contratual, simulação) e gráfico.
// Só escolhe, ordena, junta por chave e formata. Nenhum número novo é calculado aqui: a conclusão
// cita valores que vieram do banco, e contar linhas é o único "cálculo" feito.
import type { LinhaDrePeriodo, PendenciasClassificacao } from "../../lib/consultas/dre";
import type { LinhaCustoObraCategoria } from "../../lib/consultas/despesas";
import type { LinhaLiberacao, SaldoOperacaoCredito } from "../../lib/consultas/financiamento";
import type { LinhaFluxoProjetado, ResumoProjecaoObra } from "../../lib/consultas/fluxo";
import type {
  LinhaComparativoProjecao,
  LinhaExplicacaoDesvio,
  LinhaPendenciaPosEntrega,
  LinhaVisaoGerencial,
} from "../../lib/consultas/planejamento";
import type { ResumoReceitasObra } from "../../lib/consultas/receitas";
import { formatarReal } from "../../lib/formatar";
import { fraseMotivo } from "../../lib/mensagens";
import { rotulosSituacaoLiberacao, type NaturezaNumero } from "../../lib/mensagens-planejamento";
import { mesPorExtenso } from "../../lib/periodo";
import type { ColunaResposta, PerguntaPronta, SecaoPergunta } from "../../lib/perguntas-prontas";
import { juntarBaseESimulacao, piorMes, type ItemPremissa, type LinhaSimulacao, type ResultadoValidacao } from "../../lib/simulacao";

export type ValorCelula = string | number | boolean | null;
export type LinhaResposta = Record<string, ValorCelula>;

export type TabelaResposta = {
  chave: string;
  titulo: string;
  natureza: NaturezaNumero;
  colunas: readonly ColunaResposta[];
  linhas: LinhaResposta[];
};

export type SerieGrafico = { chave: string; rotulo: string; estilo: "cheio" | "tracejado" | "claro" };

export type GraficoResposta = {
  tipo: "linhas" | "barras";
  titulo: string;
  eixo: string;
  formatoEixo: "mes" | "texto";
  // Barras empilhadas só quando as séries se somam (fontes de um total); alternativas ficam lado a lado.
  empilhar?: boolean;
  series: SerieGrafico[];
  pontos: LinhaResposta[];
};

export type RespostaMontada = {
  conclusao: string | null;
  tabelas: TabelaResposta[];
  grafico: GraficoResposta | null;
  premissas: ItemPremissa[] | null;
  avisos: string[];
};

export type NomesObras = Readonly<Record<string, string>>;

function secao(pergunta: PerguntaPronta, chave: string): SecaoPergunta {
  const encontrada = pergunta.secoes.find((item) => item.chave === chave);
  if (!encontrada) throw new Error(`seção ${chave} ausente`);
  return encontrada;
}

function tabela(pergunta: PerguntaPronta, chave: string, linhas: LinhaResposta[]): TabelaResposta {
  const definicao = secao(pergunta, chave);
  return { chave, titulo: definicao.titulo, natureza: definicao.natureza, colunas: definicao.colunas, linhas };
}

function comNome<T extends { centro_custo_id: string }>(linhas: readonly T[], nomes: NomesObras): (T & { obra: string })[] {
  return linhas.map((linha) => ({ ...linha, obra: nomes[linha.centro_custo_id] ?? "Obra sem nome" }));
}

function porObra<T extends { obra: string }>(linhas: T[]): T[] {
  return [...linhas].sort((a, b) => a.obra.localeCompare(b.obra, "pt-BR"));
}

// Maior valor de uma coluna entre as linhas, só para citar na conclusão. O(n).
function maiorPor<T>(linhas: readonly T[], valor: (linha: T) => number | null): T | null {
  let maior: T | null = null;
  for (const linha of linhas) {
    const atual = valor(linha);
    if (atual === null || atual <= 0) continue;
    if (maior === null || atual > (valor(maior) as number)) maior = linha;
  }
  return maior;
}

function plural(quantidade: number, singular: string, varios: string): string {
  return `${quantidade} ${quantidade === 1 ? singular : varios}`;
}

const semGrafico = { grafico: null, premissas: null, avisos: [] as string[] };

// Perguntas antigas: uma tabela, sem conclusão calculada.
export function montarRespostaSimples(pergunta: PerguntaPronta, linhas: LinhaResposta[]): RespostaMontada {
  const [unica] = pergunta.secoes;
  return { conclusao: null, tabelas: [tabela(pergunta, unica.chave, linhas)], ...semGrafico };
}

export function montarResultadoGerencial(
  pergunta: PerguntaPronta,
  dados: { consolidado: LinhaDrePeriodo[]; obra: LinhaDrePeriodo[] | null; nomeObra: string | null; rotuloPeriodo: string },
): RespostaMontada {
  const resultado = dados.consolidado.find((linha) => linha.linha_codigo === "resultado_gerencial");
  const conclusao = !resultado
    ? null
    : resultado.disponivel && resultado.valor_periodo !== null
      ? `O resultado gerencial consolidado de ${dados.rotuloPeriodo} é ${formatarReal(resultado.valor_periodo)}. Não é lucro contábil: não inclui imposto de renda nem ajustes do contador.`
      : `O resultado gerencial de ${dados.rotuloPeriodo} ainda não pode ser mostrado. ${fraseMotivo(resultado.motivo)}`;
  const tabelas = [tabela(pergunta, "consolidado", dados.consolidado)];
  if (dados.obra) {
    const daObra = tabela(pergunta, "obra", dados.obra);
    tabelas.push({ ...daObra, titulo: dados.nomeObra ?? daObra.titulo });
  }
  return { conclusao, tabelas, ...semGrafico };
}

export function montarPrevistoProximoMes(
  pergunta: PerguntaPronta,
  dados: { parcelas: ResumoReceitasObra[]; fontes: LinhaFluxoProjetado[]; nomes: NomesObras; mes: string },
): RespostaMontada {
  const fontes = porObra(comNome(dados.fontes, dados.nomes));
  const maior = maiorPor(fontes, (linha) => linha.total_entradas);
  const conclusao = maior
    ? `Em ${mesPorExtenso(dados.mes)}, a obra com mais entrada prevista é ${maior.obra}: ${formatarReal(maior.total_entradas)}, sendo ${formatarReal(maior.previsto_direto)} dos compradores e ${formatarReal(maior.previsto_financiamento_elegivel)} de financiamento elegível. Previsão não é dinheiro recebido.`
    : `Nenhuma entrada prevista em ${mesPorExtenso(dados.mes)}.`;
  return {
    conclusao,
    tabelas: [tabela(pergunta, "parcelas", dados.parcelas), tabela(pergunta, "fontes", fontes)],
    grafico: fontes.length
      ? {
          tipo: "barras",
          titulo: `Entradas previstas em ${mesPorExtenso(dados.mes)}, por fonte`,
          eixo: "obra",
          formatoEixo: "texto",
          empilhar: true,
          series: [
            { chave: "previsto_direto", rotulo: "Entrada direta", estilo: "cheio" },
            { chave: "previsto_financiamento_elegivel", rotulo: "Financiamento elegível", estilo: "claro" },
            { chave: "previsto_financiamento_pendente", rotulo: "Financiamento pendente", estilo: "tracejado" },
            { chave: "credito_producao_previsto", rotulo: "Crédito à produção", estilo: "cheio" },
          ],
          pontos: fontes,
        }
      : null,
    premissas: null,
    avisos: [],
  };
}

export function montarCustoPorCategoria(
  pergunta: PerguntaPronta,
  dados: { categorias: LinhaCustoObraCategoria[]; nomeObra: string },
): RespostaMontada {
  const maior = maiorPor(dados.categorias, (linha) => linha.custo_lancado);
  const conclusao = maior
    ? `Na ${dados.nomeObra}, a categoria com mais custo lançado é ${maior.categoria_nome}: ${formatarReal(maior.custo_lancado)}, dos quais ${formatarReal(maior.desembolsado)} já foram pagos.`
    : null;
  return {
    conclusao,
    tabelas: [tabela(pergunta, "categorias", dados.categorias)],
    grafico: dados.categorias.length
      ? {
          tipo: "barras",
          titulo: "Pago e em aberto por categoria",
          eixo: "categoria_nome",
          formatoEixo: "texto",
          empilhar: true,
          series: [
            { chave: "desembolsado", rotulo: "Pago", estilo: "cheio" },
            { chave: "em_aberto_vencido", rotulo: "A pagar vencido", estilo: "tracejado" },
            { chave: "em_aberto_a_vencer", rotulo: "A pagar a vencer", estilo: "claro" },
          ],
          pontos: dados.categorias,
        }
      : null,
    premissas: null,
    avisos: [],
  };
}

export function montarAporteNecessario(pergunta: PerguntaPronta, dados: { resumos: ResumoProjecaoObra[] }): RespostaMontada {
  const maior = maiorPor(dados.resumos, (linha) => linha.exposicao_maxima_projetada);
  const parciais = dados.resumos.filter((linha) => linha.exposicao_parcial).length;
  const partes = [
    maior
      ? `${maior.obra} tem o maior aporte na projeção: ${formatarReal(maior.exposicao_maxima_projetada)}${maior.mes_exposicao_maxima ? `, em ${mesPorExtenso(maior.mes_exposicao_maxima)}` : ""}.`
      : "Nenhuma obra precisa de aporte na projeção de hoje.",
  ];
  if (parciais > 0) {
    partes.push(
      `${plural(parciais, "obra tem", "obras têm")} número parcial: há custo sem título fora dos meses, e o aporte real tende a ser maior.`,
    );
  }
  return {
    conclusao: partes.join(" "),
    tabelas: [tabela(pergunta, "aporte", dados.resumos)],
    grafico: dados.resumos.length
      ? {
          tipo: "barras",
          titulo: "Maior aporte necessário por obra",
          eixo: "obra",
          formatoEixo: "texto",
          series: [
            { chave: "exposicao_maxima_projetada", rotulo: "Maior aporte", estilo: "cheio" },
            { chave: "exposicao_maxima_conservadora", rotulo: "Sem financiamento pendente", estilo: "tracejado" },
          ],
          pontos: dados.resumos,
        }
      : null,
    premissas: null,
    avisos: [],
  };
}

export function montarExposicaoMaxima(pergunta: PerguntaPronta, dados: { resumos: ResumoProjecaoObra[] }): RespostaMontada {
  const maior = maiorPor(dados.resumos, (linha) => linha.exposicao_maxima_projetada);
  const conclusao = maior
    ? `No pior momento da projeção, ${maior.obra} precisa de ${formatarReal(maior.exposicao_maxima_projetada)} de dinheiro próprio${maior.mes_exposicao_maxima ? `, em ${mesPorExtenso(maior.mes_exposicao_maxima)}` : ""}. É o mesmo número da tela de fluxo de caixa.`
    : "Nenhuma obra precisa de dinheiro próprio na projeção de hoje.";
  return { conclusao, tabelas: [tabela(pergunta, "resposta", dados.resumos)], ...semGrafico };
}

export function montarFinanciamentosPendentes(
  pergunta: PerguntaPronta,
  dados: { resumos: ResumoProjecaoObra[]; operacoes: SaldoOperacaoCredito[]; nomes: NomesObras },
): RespostaMontada {
  const maior = maiorPor(dados.resumos, (linha) => linha.financiamento_pendente_total);
  const operacoes = comNome(dados.operacoes, dados.nomes);
  const comMedicao = maiorPor(operacoes, (linha) => linha.previsto_aberto);
  const partes = [
    maior
      ? `${maior.obra} tem o maior financiamento de compradores ainda sem aprovação: ${formatarReal(maior.financiamento_pendente_total)}.`
      : "Nenhum financiamento de comprador pendente de aprovação.",
    comMedicao
      ? `Do crédito à produção, ${comMedicao.obra} (${comMedicao.instituicao}) tem ${formatarReal(comMedicao.previsto_aberto)} em liberações previstas que dependem de medição.`
      : "Nenhuma liberação de crédito à produção prevista em aberto.",
  ];
  return {
    conclusao: partes.join(" "),
    tabelas: [tabela(pergunta, "aprovacao", dados.resumos), tabela(pergunta, "medicao", operacoes)],
    ...semGrafico,
  };
}

const rotulosTipoOrigem: Record<string, string> = {
  titulo_pagar: "Título a pagar",
  parcela_receber: "Parcela a receber",
  orcamento: "Item de orçamento",
};

export function montarPendenciasClassificacao(
  pergunta: PerguntaPronta,
  dados: { pendencias: PendenciasClassificacao },
): RespostaMontada {
  const linhas = dados.pendencias.linhas.map((linha) => ({
    ...linha,
    tipo_origem: rotulosTipoOrigem[linha.tipo_origem] ?? linha.tipo_origem,
    conta_origem: linha.conta_origem ?? "Sem código na origem",
  }));
  const [primeira] = linhas;
  const conclusao = primeira
    ? `${plural(dados.pendencias.total, "conta está", "contas estão")} sem categoria. A de maior valor é ${primeira.conta_origem} (${primeira.tipo_origem.toLowerCase()}), com ${formatarReal(primeira.valor_envolvido)}.`
    : null;
  return { conclusao, tabelas: [tabela(pergunta, "pendencias", linhas)], ...semGrafico };
}

export function montarSimularVendas(
  pergunta: PerguntaPronta,
  dados: {
    nomeObra: string;
    base: LinhaFluxoProjetado[];
    simulacao: LinhaSimulacao[] | null;
    validacao: ResultadoValidacao;
  },
): RespostaMontada {
  if (!dados.validacao.ok || !dados.simulacao) {
    const motivo = dados.validacao.ok ? null : Object.values(dados.validacao.erros)[0];
    return {
      conclusao: `A simulação não rodou para a ${dados.nomeObra}. ${motivo ?? ""}`.trim(),
      tabelas: [],
      ...semGrafico,
    };
  }
  const porMes = new Map(dados.simulacao.map((linha) => [linha.competencia.slice(0, 10), linha]));
  const pontos = juntarBaseESimulacao(dados.base, dados.simulacao).map((ponto) => {
    const simulada = porMes.get(ponto.competencia);
    return {
      competencia: ponto.competencia,
      base: ponto.base,
      simulado: ponto.simulado,
      necessidade_aporte_acumulada: simulada?.necessidade_aporte_acumulada ?? null,
      novas_vendas_valor: simulada?.novas_vendas_valor ?? null,
    };
  });
  const piorBase = piorMes(dados.base);
  const piorSimulado = piorMes(dados.simulacao);
  const antes = piorBase
    ? `${formatarReal(piorBase.necessidade_aporte_acumulada)} em ${mesPorExtenso(piorBase.competencia)}`
    : "nenhum aporte";
  const depois = piorSimulado
    ? `${formatarReal(piorSimulado.necessidade_aporte_acumulada)} em ${mesPorExtenso(piorSimulado.competencia)}`
    : "nenhum aporte";
  const avisos = dados.simulacao.some((linha) => linha.aviso === "vendas_limitadas_ao_estoque")
    ? ["Em algum mês a venda pedida passou do estoque; o simulador vendeu só o que havia."]
    : [];
  return {
    conclusao: `Na ${dados.nomeObra}, o maior aporte passa de ${antes} na projeção de hoje para ${depois} com as novas vendas. É simulação: nada foi gravado.`,
    tabelas: [tabela(pergunta, "comparacao", pontos)],
    grafico: {
      tipo: "linhas",
      titulo: "Caixa gerado acumulado",
      eixo: "competencia",
      formatoEixo: "mes",
      series: [
        { chave: "base", rotulo: "Projeção de hoje", estilo: "cheio" },
        { chave: "simulado", rotulo: "Com as novas vendas", estilo: "tracejado" },
      ],
      pontos,
    },
    premissas: dados.validacao.resumo,
    avisos,
  };
}

// Primeiro mês com necessidade de aporte, por obra, sobre linhas já ordenadas por obra e mês. O(n).
export function primeiroMesComAporte(linhas: readonly LinhaFluxoProjetado[]): Map<string, LinhaFluxoProjetado> {
  const primeiros = new Map<string, LinhaFluxoProjetado>();
  for (const linha of linhas) {
    if (linha.necessidade_aporte_acumulada > 0 && !primeiros.has(linha.centro_custo_id)) {
      primeiros.set(linha.centro_custo_id, linha);
    }
  }
  return primeiros;
}

export function montarQuandoFaltaCaixa(
  pergunta: PerguntaPronta,
  dados: { fluxo: LinhaFluxoProjetado[]; resumos: ResumoProjecaoObra[]; nomes: NomesObras; mesReferencia: string },
): RespostaMontada {
  const primeiros = porObra(comNome([...primeiroMesComAporte(dados.fluxo).values()], dados.nomes));
  const semAporte = dados.resumos.filter((resumo) => !primeiros.some((linha) => linha.centro_custo_id === resumo.centro_custo_id));
  const maisCedo = [...primeiros].sort((a, b) => (a.competencia < b.competencia ? -1 : 1))[0];
  const partes = [
    maisCedo
      ? maisCedo.competencia.slice(0, 10) <= dados.mesReferencia
        ? `${maisCedo.obra} já precisa de aporte em ${mesPorExtenso(dados.mesReferencia)}: ${formatarReal(maisCedo.necessidade_aporte_acumulada)} acumulados.`
        : `Sem novas vendas, a primeira obra a precisar de aporte é ${maisCedo.obra}, em ${mesPorExtenso(maisCedo.competencia)}: ${formatarReal(maisCedo.necessidade_aporte_acumulada)}.`
      : "Sem novas vendas, nenhuma obra precisa de aporte da data de referência em diante.",
  ];
  if (semAporte.length > 0 && primeiros.length > 0) {
    partes.push(`${plural(semAporte.length, "obra não precisa", "obras não precisam")} de aporte na projeção.`);
  }
  return {
    conclusao: partes.join(" "),
    tabelas: [tabela(pergunta, "falta", primeiros), tabela(pergunta, "pico", dados.resumos)],
    ...semGrafico,
  };
}

export function montarMetaDoMes(
  pergunta: PerguntaPronta,
  dados: { visao: LinhaVisaoGerencial[]; desvios: LinhaExplicacaoDesvio[]; nomes: NomesObras; mes: string },
): RespostaMontada {
  const visao = porObra(comNome(dados.visao, dados.nomes));
  const comMeta = visao.filter((linha) => linha.meta_unidades !== null);
  const batidas = comMeta.filter((linha) => linha.vendas_unidades >= (linha.meta_unidades as number));
  const conclusao =
    comMeta.length === 0
      ? `Nenhuma obra tem meta de unidades para ${mesPorExtenso(dados.mes)}. Registre as metas em Planejamento.`
      : `Em ${mesPorExtenso(dados.mes)}, ${batidas.length} de ${plural(comMeta.length, "obra com meta bateu", "obras com meta bateram")} a meta de unidades.${
          batidas.length < comMeta.length
            ? ` Abaixo da meta: ${comMeta
                .filter((linha) => !batidas.includes(linha))
                .map((linha) => `${linha.obra} (${linha.vendas_unidades} de ${linha.meta_unidades})`)
                .join(", ")}.`
            : ""
        } O efeito no caixa está na diferença para o planejamento original.`;
  return {
    conclusao,
    tabelas: [
      tabela(pergunta, "vendas", visao),
      tabela(pergunta, "caixa", visao),
      tabela(pergunta, "desvios", porObra(comNome(dados.desvios, dados.nomes))),
    ],
    ...semGrafico,
  };
}

export function montarAporteDesteMes(
  pergunta: PerguntaPronta,
  dados: { fluxo: LinhaFluxoProjetado[]; resumos: ResumoProjecaoObra[]; nomes: NomesObras; mes: string },
): RespostaMontada {
  const parcial = new Map(dados.resumos.map((resumo) => [resumo.centro_custo_id, resumo.exposicao_parcial]));
  const linhas = porObra(comNome(dados.fluxo, dados.nomes)).map((linha) => ({
    ...linha,
    exposicao_parcial: parcial.get(linha.centro_custo_id) ?? null,
  }));
  const comAporte = linhas.filter((linha) => linha.aporte_incremental_mes > 0);
  const maior = maiorPor(linhas, (linha) => linha.aporte_incremental_mes);
  const conclusao = maior
    ? `Em ${mesPorExtenso(dados.mes)}, ${plural(comAporte.length, "obra precisa", "obras precisam")} de aporte novo. A maior é ${maior.obra}: ${formatarReal(maior.aporte_incremental_mes)} no mês.`
    : `Nenhuma obra precisa de aporte novo em ${mesPorExtenso(dados.mes)}.`;
  return {
    conclusao,
    tabelas: [tabela(pergunta, "aporte", linhas)],
    grafico: null,
    premissas: null,
    avisos: linhas.some((linha) => linha.exposicao_parcial)
      ? ["Há obra com custo sem título fora dos meses: o aporte dela é parcial e tende a ser maior."]
      : [],
  };
}

export function montarMudouDesdeProjecao(
  pergunta: PerguntaPronta,
  dados: { comparativo: LinhaComparativoProjecao[]; desvios: LinhaExplicacaoDesvio[]; nomeObra: string; mesReferencia: string },
): RespostaMontada {
  const doMes = dados.comparativo.find((linha) => linha.competencia.slice(0, 10) === dados.mesReferencia);
  const versao = dados.comparativo.find((linha) => linha.versao_original_numero !== null)?.versao_original_numero ?? null;
  const conclusao =
    versao === null
      ? `A ${dados.nomeObra} não tem projeção registrada para comparar. Registre uma versão em Planejamento.`
      : doMes && doMes.diferenca_caixa_acumulado !== null
        ? `Comparado à versão ${versao} da projeção, o caixa gerado acumulado da ${dados.nomeObra} em ${mesPorExtenso(dados.mesReferencia)} mudou ${formatarReal(doMes.diferenca_caixa_acumulado)} (${formatarReal(doMes.atual_caixa_gerado_acumulado)} hoje).`
        : `A versão ${versao} da projeção não cobre ${mesPorExtenso(dados.mesReferencia)}.`;
  return {
    conclusao,
    tabelas: [tabela(pergunta, "comparativo", dados.comparativo), tabela(pergunta, "desvios", dados.desvios)],
    grafico:
      versao === null
        ? null
        : {
            tipo: "linhas",
            titulo: "Caixa gerado acumulado: original e atual",
            eixo: "competencia",
            formatoEixo: "mes",
            series: [
              { chave: "original_caixa_gerado_acumulado", rotulo: "Projeção original", estilo: "tracejado" },
              { chave: "atual_caixa_gerado_acumulado", rotulo: "Projeção atual", estilo: "cheio" },
            ],
            pontos: dados.comparativo,
          },
    premissas: null,
    avisos: [],
  };
}

export function montarLiberadoEPendente(
  pergunta: PerguntaPronta,
  dados: { operacoes: SaldoOperacaoCredito[]; liberacoes: LinhaLiberacao[]; nomes: NomesObras },
): RespostaMontada {
  const operacoes = comNome(dados.operacoes, dados.nomes);
  const liberacoes = comNome(dados.liberacoes, dados.nomes).map((linha) => ({
    ...linha,
    situacao_efetiva: rotulosSituacaoLiberacao[linha.situacao_efetiva] ?? linha.situacao_efetiva,
  }));
  const maiorLiberado = maiorPor(operacoes, (linha) => linha.liberado_recebido);
  const atrasadas = dados.liberacoes.filter((linha) => linha.situacao_efetiva === "atrasada").length;
  const partes = [
    maiorLiberado
      ? `${maiorLiberado.obra} (${maiorLiberado.instituicao}) já recebeu ${formatarReal(maiorLiberado.liberado_recebido)} de ${formatarReal(maiorLiberado.valor_contratado)} contratados.`
      : "Nenhuma liberação de crédito à produção recebida.",
    dados.liberacoes.length
      ? `${plural(dados.liberacoes.length, "liberação está", "liberações estão")} pendente ou atrasada${atrasadas ? `, ${atrasadas} com data prevista vencida` : ""}.`
      : "Nenhuma liberação pendente ou atrasada.",
  ];
  return {
    conclusao: partes.join(" "),
    tabelas: [tabela(pergunta, "operacoes", operacoes), tabela(pergunta, "pendentes", liberacoes)],
    ...semGrafico,
  };
}

export function montarPosEntrega(pergunta: PerguntaPronta, dados: { pendencias: LinhaPendenciaPosEntrega[] }): RespostaMontada {
  const conclusao = dados.pendencias.length
    ? `${plural(dados.pendencias.length, "obra entregue ainda tem", "obras entregues ainda têm")} valores em aberto. Acompanhamento gerencial, não encerramento contábil.`
    : null;
  return { conclusao, tabelas: [tabela(pergunta, "pendencias", dados.pendencias)], ...semGrafico };
}
