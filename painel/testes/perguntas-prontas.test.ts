import { readFileSync } from "node:fs";
import { join } from "node:path";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { catalogoViews } from "../lib/catalogo-views";
import { buscarPerguntaPronta, perguntasNovas, perguntasProntas } from "../lib/perguntas-prontas";
import { validarSql } from "../lib/validador-sql";

// Cada função de consulta vira um espião com resposta vazia; o teste só olha quem foi chamado.
const espioes = vi.hoisted(() => {
  const lista = async () => [];
  return {
    fluxo: {
      listarFluxoProjetado: vi.fn(lista),
      listarResumoProjecao: vi.fn(lista),
      simularFluxo: vi.fn(lista),
      contarEstoqueSimulacao: vi.fn(async () => 20),
      listarFluxoMensal: vi.fn(lista),
      listarFluxoCenario: vi.fn(lista),
    },
    planejamento: {
      listarVisaoGerencial: vi.fn(lista),
      listarExplicacaoDesvio: vi.fn(lista),
      listarComparativo: vi.fn(lista),
      listarPendenciasPosEntrega: vi.fn(lista),
      listarVersoes: vi.fn(lista),
    },
    financiamento: {
      listarSaldoOperacoes: vi.fn(lista),
      listarLiberacoes: vi.fn(lista),
      listarFinanciamentoContratos: vi.fn(lista),
      listarMedicoes: vi.fn(lista),
    },
    receitas: { listarResumoReceitas: vi.fn(lista), listarCarteira: vi.fn(lista) },
    despesas: { listarCustoPorCategoria: vi.fn(lista), listarCustoResumo: vi.fn(lista) },
    dre: {
      listarDrePeriodo: vi.fn(lista),
      listarPendenciasClassificacao: vi.fn(async () => ({ linhas: [], total: 0 })),
      contarPendenciasClassificacao: vi.fn(async () => 0),
    },
  };
});

vi.mock("server-only", () => ({}));
vi.mock("../lib/supabase/servidor", () => ({ criarClienteServidor: vi.fn() }));
vi.mock("../lib/consultas/posicao", () => ({ ErroConsulta: class ErroConsulta extends Error {} }));
vi.mock("../lib/consultas/referencia", () => ({
  carregarReferencia: vi.fn(async () => ({ situacao: null, dataReferencia: "2026-09-26", doBanco: true })),
  listarCentrosCusto: vi.fn(async () => [
    { id: "4c22f713-0217-4230-bf04-8581b4bf6a7b", nome: "Residencial Aurora", tipo: "obra" },
    { id: "d251449f-c7b0-4ca5-93d5-82440eb1175f", nome: "Parque das Aguas", tipo: "obra" },
  ]),
}));
vi.mock("../lib/consultas/fluxo", () => espioes.fluxo);
vi.mock("../lib/consultas/planejamento", () => espioes.planejamento);
vi.mock("../lib/consultas/financiamento", () => espioes.financiamento);
vi.mock("../lib/consultas/receitas", () => espioes.receitas);
vi.mock("../lib/consultas/despesas", () => espioes.despesas);
vi.mock("../lib/consultas/dre", () => espioes.dre);

const { responderPerguntaPronta } = await import("../lib/consultas/perguntas-prontas");

const colunasPorView = new Map(catalogoViews.map((view) => [view.nome, new Set(view.colunas)]));
const viewsDoSql = (sql: string) =>
  [...sql.matchAll(/\b(?:from|join)\s+([a-z_]+\.[a-z_]+)/gi)].map((referencia) => referencia[1].toLowerCase());
const apelidosDoSql = (sql: string) => [...sql.matchAll(/\bas\s+([a-z_]+)/gi)].map((apelido) => apelido[1].toLowerCase());
const secoes = perguntasProntas.flatMap((pergunta) =>
  pergunta.secoes.map((secao) => [`${pergunta.id}/${secao.chave}`, secao] as const),
);

describe("perguntas prontas", () => {
  it("tem ids únicos", () => {
    const ids = perguntasProntas.map((pergunta) => pergunta.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it("tem o texto de cada pergunta único", () => {
    const textos = perguntasProntas.map((pergunta) => pergunta.pergunta);
    expect(new Set(textos).size).toBe(textos.length);
  });

  it.each(secoes)("%s passa no validador de SQL e só lê views do catálogo", (_id, secao) => {
    expect(validarSql(secao.sql).ok).toBe(true);
    const views = viewsDoSql(secao.sql).filter((nome) => nome !== "app.centro_custo");
    expect(views.length).toBeGreaterThan(0);
    views.forEach((nome) => expect(colunasPorView.has(nome)).toBe(true));
  });

  it.each(secoes)("%s mostra só colunas que existem nas views que consulta", (_id, secao) => {
    const disponiveis = new Set(["obra", ...apelidosDoSql(secao.sql)]);
    viewsDoSql(secao.sql).forEach((nome) => colunasPorView.get(nome)?.forEach((coluna) => disponiveis.add(coluna)));
    secao.colunas.forEach((coluna) => expect(disponiveis).toContain(coluna.chave));
  });

  it("não usa as views retiradas do assistente", () => {
    const nomes = catalogoViews.map((view) => view.nome).join(" ");
    expect(nomes).not.toMatch(/consolidado_centro_custo|break_even_obra/);
    secoes.forEach(([, secao]) => expect(secao.sql).not.toMatch(/consolidado_centro_custo|break_even_obra/));
  });

  it("nunca pede nome de comprador", () => {
    secoes.forEach(([, secao]) => expect(secao.sql).not.toMatch(/nome_cliente|cpf/i));
    catalogoViews.forEach((view) => expect(view.colunas.join(" ")).not.toMatch(/nome_cliente|cpf/i));
  });

  it("busca pelo id e ignora id fora da lista", () => {
    expect(buscarPerguntaPronta("exposicao-maxima")?.pergunta).toBe(
      "Quanto dinheiro próprio cada obra precisa no pior momento?",
    );
    expect(buscarPerguntaPronta("'; drop table app.tenant; --")).toBeUndefined();
    expect(buscarPerguntaPronta(undefined)).toBeUndefined();
  });

  it("tem as perguntas novas do contrato de dados e as de planejamento", () => {
    expect(perguntasNovas.map((pergunta) => pergunta.id)).toEqual(
      expect.arrayContaining([
        "resultado-gerencial-ano",
        "previsto-proximo-mes",
        "custo-por-categoria",
        "aporte-necessario",
        "financiamentos-pendentes",
        "pendencias-classificacao",
        "simular-vendas",
        "quando-falta-caixa",
        "meta-do-mes",
        "aporte-deste-mes",
        "mudou-desde-projecao",
        "liberado-e-pendente",
        "pos-entrega",
      ]),
    );
  });

  it("aporte tem uma fonte só: exposição máxima e aporte necessário leem a função da tela de fluxo", () => {
    for (const id of ["exposicao-maxima", "aporte-necessario"]) {
      const pergunta = perguntasNovas.find((item) => item.id === id);
      expect(pergunta?.tela.consultas.map((consulta) => `${consulta.modulo}.${consulta.funcao}`)).toEqual(["fluxo.listarResumoProjecao"]);
      pergunta?.secoes.forEach((secao) => expect(secao.sql).toMatch(/from marts\.resumo_projecao_obra/));
    }
  });

  it("o sql da simulação parte dos meses da simulação", () => {
    const [secao] = buscarPerguntaPronta("simular-vendas")?.secoes ?? [];
    expect(secao?.sql).toMatch(/from marts\.simular_fluxo\(\$1, \$2\) s left join marts\.fluxo_projetado_mensal f/);
    expect(secao?.sql).toMatch(/order by s\.competencia$/);
  });

  it("marca simulação só na pergunta que simula", () => {
    perguntasProntas.forEach((pergunta) => {
      const simula = pergunta.secoes.some((secao) => secao.natureza === "simulacao");
      expect(simula).toBe(pergunta.id === "simular-vendas");
    });
  });
});

// R20 do contrato: a pergunta chama a mesma função de lib/consultas que a tela, então o número bate.
describe("perguntas novas usam as funções das telas", () => {
  const todosEspioes = Object.entries(espioes).flatMap(([modulo, funcoes]) =>
    Object.entries(funcoes).map(([funcao, espiao]) => ({ modulo, funcao, espiao })),
  );

  beforeEach(() => todosEspioes.forEach(({ espiao }) => espiao.mockClear()));

  it.each(perguntasNovas.map((pergunta) => [pergunta.id, pergunta] as const))(
    "%s chama exatamente as funções declaradas",
    async (id, pergunta) => {
      await responderPerguntaPronta(id, "4c22f713-0217-4230-bf04-8581b4bf6a7b");
      const chamadas = todosEspioes
        .filter(({ espiao }) => espiao.mock.calls.length > 0)
        .map(({ modulo, funcao }) => `${modulo}.${funcao}`)
        .sort();
      const declaradas = [...new Set(pergunta.tela.consultas.map(({ modulo, funcao }) => `${modulo}.${funcao}`))].sort();
      expect(chamadas).toEqual(declaradas);
    },
  );

  it.each(perguntasNovas.flatMap((pergunta) => pergunta.tela.consultas.map((consulta) => [pergunta.id, consulta] as const)))(
    "%s: a tela importa a mesma função do mesmo módulo",
    (_id, consulta) => {
      const fonte = readFileSync(join(__dirname, "..", consulta.arquivo), "utf8");
      const importacao = new RegExp(
        `import\\s*\\{[^}]*\\b${consulta.funcao}\\b[^}]*\\}\\s*from\\s*"@/lib/consultas/${consulta.modulo}"`,
      );
      expect(fonte).toMatch(importacao);
      expect(fonte).toMatch(new RegExp(`\\b${consulta.funcao}\\(`));
    },
  );

  it("a simulação da pergunta usa as premissas validadas pela regra da tela", async () => {
    await responderPerguntaPronta("simular-vendas", "4c22f713-0217-4230-bf04-8581b4bf6a7b");
    const [obra, premissas] = espioes.fluxo.simularFluxo.mock.calls[0] as unknown as [string, Record<string, unknown>];
    expect(obra).toBe("4c22f713-0217-4230-bf04-8581b4bf6a7b");
    expect(premissas.novas_vendas).toEqual([{ competencia: "2026-10-01", quantidade: 5 }]);
    expect(premissas.composicao).toEqual({
      entrada: 0.1,
      parcelas_mensais: 0.3,
      quantidade_parcelas_mensais: 24,
      financiamento: 0.6,
    });
  });

  it("sem estoque suficiente, a pergunta de simulação não chama o banco e explica", async () => {
    espioes.fluxo.contarEstoqueSimulacao.mockResolvedValueOnce(3);
    const { resposta } = await responderPerguntaPronta("simular-vendas", "4c22f713-0217-4230-bf04-8581b4bf6a7b");
    expect(espioes.fluxo.simularFluxo).not.toHaveBeenCalled();
    expect(resposta.conclusao).toMatch(/3 unidades à venda/);
  });

  it("obra fora da lista liberada não é usada", async () => {
    const { obra } = await responderPerguntaPronta("custo-por-categoria", "00000000-0000-4000-8000-000000000000");
    expect(obra?.nome).toBe("Residencial Aurora");
    expect(espioes.despesas.listarCustoPorCategoria).toHaveBeenCalledWith("4c22f713-0217-4230-bf04-8581b4bf6a7b");
  });
});

describe("montagem das respostas novas a partir de linhas simuladas", async () => {
  const montar = await import("../componentes/planejamento/respostas-perguntas");
  const pergunta = (id: string) => {
    const encontrada = buscarPerguntaPronta(id);
    if (!encontrada) throw new Error(id);
    return encontrada;
  };
  const aurora = "4c22f713-0217-4230-bf04-8581b4bf6a7b";
  const parque = "d251449f-c7b0-4ca5-93d5-82440eb1175f";
  const nomes = { [aurora]: "Residencial Aurora", [parque]: "Parque das Aguas" };
  const fluxo = (centro: string, competencia: string, valores: Record<string, number | boolean> = {}) =>
    ({
      tenant_id: "t",
      centro_custo_id: centro,
      competencia,
      eh_passado: false,
      recebido_direto: 0,
      recebido_financiamento: 0,
      credito_producao_recebido: 0,
      previsto_direto: 0,
      previsto_financiamento_elegivel: 0,
      previsto_financiamento_pendente: 0,
      credito_producao_previsto: 0,
      vencido_a_receber: 0,
      pago: 0,
      a_pagar: 0,
      a_pagar_vencido: 0,
      custo_sem_titulo_distribuido: 0,
      total_entradas: 0,
      total_saidas: 0,
      saldo_mes: 0,
      caixa_gerado_acumulado: 0,
      necessidade_aporte_acumulada: 0,
      aporte_incremental_mes: 0,
      caixa_gerado_acumulado_conservador: 0,
      necessidade_aporte_conservadora: 0,
      ...valores,
    }) as import("../lib/consultas/fluxo").LinhaFluxoProjetado;
  const resumo = (centro: string, obra: string, valores: Record<string, unknown> = {}) =>
    ({
      tenant_id: "t",
      centro_custo_id: centro,
      obra,
      data_referencia: "2026-09-26",
      exposicao_maxima_projetada: 0,
      mes_exposicao_maxima: null,
      exposicao_maxima_conservadora: 0,
      custo_sem_titulo_total: null,
      custo_sem_titulo_distribuido_total: 0,
      custo_sem_titulo_nao_distribuido: null,
      premissa_distribuicao_id: null,
      motivo_distribuicao: null,
      exposicao_parcial: false,
      vencido_a_receber: 0,
      a_pagar_vencido: 0,
      financiamento_pendente_total: 0,
      ...valores,
    }) as import("../lib/consultas/fluxo").ResumoProjecaoObra;

  it("próximo mês cita a obra de maior entrada, separa as fontes e marca previsão", () => {
    const resposta = montar.montarPrevistoProximoMes(pergunta("previsto-proximo-mes"), {
      parcelas: [],
      fontes: [
        fluxo(aurora, "2026-10-01", { previsto_direto: 100, previsto_financiamento_elegivel: 50, total_entradas: 150 }),
        fluxo(parque, "2026-10-01", { previsto_direto: 20, total_entradas: 20 }),
      ],
      nomes,
      mes: "2026-10-01",
    });
    expect(resposta.conclusao).toMatch(/outubro de 2026.*Residencial Aurora.*150,00.*100,00.*50,00/);
    expect(resposta.tabelas.map((tabela) => tabela.natureza)).toEqual(["previsao", "previsao"]);
    expect(resposta.tabelas[1].linhas.map((linha) => linha.obra)).toEqual(["Parque das Aguas", "Residencial Aurora"]);
    expect(resposta.grafico?.empilhar).toBe(true);
  });

  it("aporte necessário cita o pico e avisa quando há número parcial", () => {
    const resposta = montar.montarAporteNecessario(pergunta("aporte-necessario"), {
      resumos: [
        resumo(aurora, "Residencial Aurora", { exposicao_maxima_projetada: 1_000_000, mes_exposicao_maxima: "2027-03-01", exposicao_parcial: true }),
        resumo(parque, "Parque das Aguas", { exposicao_maxima_projetada: 200_000, mes_exposicao_maxima: "2026-12-01" }),
      ],
    });
    expect(resposta.conclusao).toMatch(/Residencial Aurora.*1\.000\.000,00.*março de 2027.*1 obra tem número parcial/);
    expect(resposta.grafico?.empilhar).toBeFalsy();
  });

  it("quando falta caixa pega o primeiro mês com aporte de cada obra", () => {
    const resposta = montar.montarQuandoFaltaCaixa(pergunta("quando-falta-caixa"), {
      fluxo: [
        fluxo(aurora, "2026-09-01"),
        fluxo(aurora, "2026-11-01", { necessidade_aporte_acumulada: 300 }),
        fluxo(aurora, "2026-12-01", { necessidade_aporte_acumulada: 900 }),
        fluxo(parque, "2026-09-01"),
      ],
      resumos: [resumo(aurora, "Residencial Aurora"), resumo(parque, "Parque das Aguas")],
      nomes,
      mesReferencia: "2026-09-01",
    });
    expect(resposta.tabelas[0].linhas).toHaveLength(1);
    expect(resposta.tabelas[0].linhas[0]).toMatchObject({ obra: "Residencial Aurora", competencia: "2026-11-01", necessidade_aporte_acumulada: 300 });
    expect(resposta.conclusao).toMatch(/novembro de 2026.*300,00.*1 obra não precisa/);
  });

  it("meta do mês conta quem bateu sem calcular valor", () => {
    const visao = (centro: string, meta: number | null, vendas: number) =>
      ({ centro_custo_id: centro, competencia: "2026-09-01", meta_unidades: meta, vendas_unidades: vendas }) as unknown as import("../lib/consultas/planejamento").LinhaVisaoGerencial;
    const resposta = montar.montarMetaDoMes(pergunta("meta-do-mes"), {
      visao: [visao(aurora, 3, 4), visao(parque, 5, 2)],
      desvios: [],
      nomes,
      mes: "2026-09-01",
    });
    expect(resposta.conclusao).toMatch(/1 de 2 obras com meta bateram.*Parque das Aguas \(2 de 5\)/);
    expect(resposta.tabelas.map((tabela) => tabela.natureza)).toEqual(["fato", "previsao", "fato"]);
  });

  it("simulação mostra premissas, junta base e cenário e marca simulação", async () => {
    const { validarPremissas, formularioPadrao } = await import("../lib/simulacao");
    const validacao = validarPremissas({ ...formularioPadrao("2026-09-26"), vendas_por_mes: "5", meses_vendas: "1" }, {
      dataReferencia: "2026-09-26",
      estoque: 10,
    });
    const simulada = (competencia: string, caixa: number, aporte: number) =>
      ({ competencia, caixa_gerado_acumulado: caixa, necessidade_aporte_acumulada: aporte, novas_vendas_valor: 0, aviso: null }) as unknown as import("../lib/simulacao").LinhaSimulacao;
    const resposta = montar.montarSimularVendas(pergunta("simular-vendas"), {
      nomeObra: "Residencial Aurora",
      base: [
        fluxo(aurora, "2026-10-01", { caixa_gerado_acumulado: -500, necessidade_aporte_acumulada: 500 }),
        fluxo(aurora, "2026-11-01", { caixa_gerado_acumulado: -800, necessidade_aporte_acumulada: 800 }),
      ],
      simulacao: [simulada("2026-10-01", -400, 400), simulada("2026-11-01", -600, 600)],
      validacao,
    });
    expect(resposta.conclusao).toMatch(/800,00 em novembro de 2026.*600,00 em novembro de 2026.*simulação/);
    expect(resposta.premissas?.[0].valor).toMatch(/5 unidades/);
    expect(resposta.tabelas[0]).toMatchObject({ natureza: "simulacao" });
    expect(resposta.tabelas[0].linhas[0]).toMatchObject({ base: -500, simulado: -400, necessidade_aporte_acumulada: 400 });
  });

  it("mudou desde a projeção cita a versão e a diferença do mês de referência", () => {
    const linha = (competencia: string, diferenca: number | null, versao: number | null) =>
      ({ competencia, versao_original_numero: versao, diferenca_caixa_acumulado: diferenca, atual_caixa_gerado_acumulado: -1000 }) as unknown as import("../lib/consultas/planejamento").LinhaComparativoProjecao;
    const comVersao = montar.montarMudouDesdeProjecao(pergunta("mudou-desde-projecao"), {
      comparativo: [linha("2026-08-01", 10, 2), linha("2026-09-01", -250, 2)],
      desvios: [],
      nomeObra: "Residencial Aurora",
      mesReferencia: "2026-09-01",
    });
    expect(comVersao.conclusao).toMatch(/versão 2.*setembro de 2026.*-R\$\s250,00/);
    const semVersao = montar.montarMudouDesdeProjecao(pergunta("mudou-desde-projecao"), {
      comparativo: [linha("2026-09-01", null, null)],
      desvios: [],
      nomeObra: "Residencial Aurora",
      mesReferencia: "2026-09-01",
    });
    expect(semVersao.conclusao).toMatch(/não tem projeção registrada/);
    expect(semVersao.grafico).toBeNull();
  });

  it("resultado gerencial indisponível mostra o motivo, nunca zero", () => {
    const resposta = montar.montarResultadoGerencial(pergunta("resultado-gerencial-ano"), {
      consolidado: [
        { linha_codigo: "resultado_gerencial", linha_ordem: 90, linha_nome: "Resultado gerencial do período", valor_periodo: null, disponivel: false, motivo: "criterio_nao_validado", cobertura: null },
      ],
      obra: null,
      nomeObra: null,
      rotuloPeriodo: "janeiro a setembro de 2026",
    });
    expect(resposta.conclusao).toMatch(/ainda não pode ser mostrado. Critério de reconhecimento não validado/);
    expect(resposta.tabelas).toHaveLength(1);
  });

  it("pós-entrega avisa que é acompanhamento gerencial", () => {
    const resposta = montar.montarPosEntrega(pergunta("pos-entrega"), {
      pendencias: [{ centro_custo_id: parque, obra: "Parque das Aguas" } as unknown as import("../lib/consultas/planejamento").LinhaPendenciaPosEntrega],
    });
    expect(resposta.conclusao).toMatch(/não encerramento contábil/);
  });
});
