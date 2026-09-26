import { describe, expect, it } from "vitest";
import {
  coberturaDoPeriodo,
  criterioPendente,
  estadoDoValor,
  montarGradeMensal,
  montarLinhasPeriodo,
} from "../componentes/financeiro/montar-dre";
import type { CodigoLinhaDre, LinhaDrePeriodo } from "../lib/consultas/dre";
import {
  categoriaServeParaOrigem,
  categoriasPara,
  escopoTenant,
  leitorDoFormulario,
  validarClassificacao,
  validarCriterio,
} from "../componentes/financeiro/regras-classificacao";
import { fraseErroGravacao, fraseMotivo } from "../lib/mensagens";

const ordens: Record<CodigoLinhaDre, [number, string]> = {
  receita_bruta: [10, "Receita bruta reconhecida"],
  deducoes: [20, "Deduções e tributos sobre a receita"],
  receita_liquida: [30, "Receita líquida"],
  custo_imovel_vendido: [40, "Custo reconhecido dos imóveis vendidos"],
  resultado_bruto: [50, "Resultado bruto"],
  despesas_comerciais: [60, "Despesas comerciais"],
  despesas_administrativas: [70, "Despesas administrativas"],
  resultado_financeiro: [80, "Resultado financeiro"],
  resultado_gerencial: [90, "Resultado gerencial do período"],
  custo_obra_incorrido: [100, "Custo de obra lançado no mês (vai para o estoque)"],
  fora_do_resultado: [110, "Movimentos fora do resultado"],
  sem_categoria: [120, "Lançamentos sem categoria"],
  sem_data_competencia: [130, "Lançamentos sem data de competência"],
};

const dependemDoCriterio = new Set<CodigoLinhaDre>([
  "receita_bruta",
  "receita_liquida",
  "custo_imovel_vendido",
  "resultado_bruto",
  "resultado_gerencial",
]);

// Caso C22 do contrato (fevereiro de 2026) na variante sem critério validado.
function linhaPeriodo(codigo: CodigoLinhaDre, valor: number | null, cobertura: number | null = 1): LinhaDrePeriodo {
  const [ordem, nome] = ordens[codigo];
  const indisponivel = dependemDoCriterio.has(codigo);
  return {
    linha_codigo: codigo,
    linha_ordem: ordem,
    linha_nome: nome,
    valor_periodo: indisponivel ? null : valor,
    disponivel: !indisponivel,
    motivo: indisponivel ? "criterio_nao_validado" : null,
    cobertura,
  };
}

const periodoSemCriterio: LinhaDrePeriodo[] = [
  linhaPeriodo("sem_data_competencia", -500, null),
  linhaPeriodo("resultado_gerencial", null),
  linhaPeriodo("deducoes", -5000),
  linhaPeriodo("receita_bruta", null),
  linhaPeriodo("custo_obra_incorrido", -300000),
  linhaPeriodo("despesas_comerciais", -10000),
  linhaPeriodo("despesas_administrativas", 0),
  linhaPeriodo("receita_liquida", null),
  linhaPeriodo("custo_imovel_vendido", null),
  linhaPeriodo("resultado_bruto", null),
  linhaPeriodo("resultado_financeiro", -2000),
  linhaPeriodo("fora_do_resultado", 0),
  linhaPeriodo("sem_categoria", 0),
];

describe("estadoDoValor", () => {
  it("indisponível nunca vira zero e leva a frase do motivo", () => {
    expect(estadoDoValor(null, false, "criterio_nao_validado")).toEqual({
      tipo: "indisponivel",
      motivo: "Critério de reconhecimento não validado pelo financeiro.",
    });
  });

  it("zero conhecido continua zero", () => {
    expect(estadoDoValor(0)).toEqual({ tipo: "valor", valor: 0 });
  });

  it("disponível sem número é dado ausente", () => {
    expect(estadoDoValor(null)).toEqual({ tipo: "ausente" });
  });

  it("código de motivo desconhecido vira frase genérica, nunca o código", () => {
    expect(estadoDoValor(null, false, "erro_interno_xyz")).toEqual({ tipo: "indisponivel", motivo: fraseMotivo(null) });
  });
});

describe("montarLinhasPeriodo", () => {
  const { resultado, informativas } = montarLinhasPeriodo(periodoSemCriterio);

  it("põe as linhas do resultado na ordem do DRE e separa o informativo", () => {
    expect(resultado.map((linha) => linha.codigo)).toEqual([
      "receita_bruta",
      "deducoes",
      "receita_liquida",
      "custo_imovel_vendido",
      "resultado_bruto",
      "despesas_comerciais",
      "despesas_administrativas",
      "resultado_financeiro",
      "resultado_gerencial",
    ]);
    expect(informativas.map((linha) => linha.codigo)).toEqual([
      "custo_obra_incorrido",
      "fora_do_resultado",
      "sem_categoria",
      "sem_data_competencia",
    ]);
  });

  it("sem critério, receita, custo vendido e resultados ficam indisponíveis e o resto aparece", () => {
    const estados = new Map(resultado.map((linha) => [linha.codigo, linha.estado]));
    for (const codigo of dependemDoCriterio) expect(estados.get(codigo)?.tipo).toBe("indisponivel");
    expect(estados.get("deducoes")).toEqual({ tipo: "valor", valor: -5000 });
    expect(estados.get("despesas_administrativas")).toEqual({ tipo: "valor", valor: 0 });
  });

  it("marca os subtotais", () => {
    expect(resultado.filter((linha) => linha.subtotal).map((linha) => linha.codigo)).toEqual([
      "receita_liquida",
      "resultado_bruto",
      "resultado_gerencial",
    ]);
  });

  it("nenhuma linha se chama lucro líquido", () => {
    [...resultado, ...informativas].forEach((linha) => expect(linha.nome.toLowerCase()).not.toContain("lucro"));
  });
});

describe("coberturaDoPeriodo e criterioPendente", () => {
  it("lê a cobertura de uma linha do período, ignorando a sem competência", () => {
    expect(
      coberturaDoPeriodo([linhaPeriodo("sem_data_competencia", -500, null), linhaPeriodo("deducoes", 0, 0.7)]),
    ).toBe(0.7);
    expect(coberturaDoPeriodo([])).toBeNull();
  });

  it("acusa o critério pendente pelo método da obra ou pelo motivo da linha", () => {
    expect(criterioPendente([], [{ metodo: "nao_definido" }])).toBe(true);
    expect(criterioPendente(periodoSemCriterio, [])).toBe(true);
    expect(criterioPendente([linhaPeriodo("deducoes", 0)], [{ metodo: "percentual_conclusao" }])).toBe(false);
  });
});

describe("montarGradeMensal", () => {
  // Caso C22 com critério validado: janeiro e fevereiro de 2026, e a linha sem competência de fora.
  const linhas = [
    { mes: "2026-02-01", codigo: "receita_bruta", mensal: 150000, acumulado: 250000 },
    { mes: "2026-01-01", codigo: "receita_bruta", mensal: 100000, acumulado: 100000 },
    { mes: "2026-01-01", codigo: "resultado_gerencial", mensal: 20000, acumulado: 20000 },
    { mes: "2026-02-01", codigo: "resultado_gerencial", mensal: 10000, acumulado: 30000 },
    { mes: "2026-02-01", codigo: "deducoes", mensal: -5000, acumulado: -5000 },
    { mes: null, codigo: "sem_data_competencia", mensal: -500, acumulado: -500 },
  ].map((linha) => ({
    competencia: linha.mes,
    linha_codigo: linha.codigo as CodigoLinhaDre,
    linha_ordem: ordens[linha.codigo as CodigoLinhaDre][0],
    linha_nome: ordens[linha.codigo as CodigoLinhaDre][1],
    valor_mes: linha.mensal,
    valor_acumulado: linha.acumulado,
    disponivel: true,
    motivo: null,
    cobertura: linha.mes === "2026-02-01" ? 1 : 0.8,
  }));

  it("monta a grade linha por mês com o valor do mês", () => {
    const grade = montarGradeMensal(linhas, "valor_mes");
    expect(grade.meses).toEqual(["2026-01-01", "2026-02-01"]);
    expect(grade.linhas.map((linha) => linha.codigo)).toEqual(["receita_bruta", "deducoes", "resultado_gerencial"]);
    expect(grade.linhas[0].celulas).toEqual([
      { tipo: "valor", valor: 100000 },
      { tipo: "valor", valor: 150000 },
    ]);
    expect(grade.cobertura).toEqual([0.8, 1]);
  });

  it("mês em que a linha não veio fica ausente, não zero", () => {
    const grade = montarGradeMensal(linhas, "valor_mes");
    expect(grade.linhas[1].celulas[0]).toEqual({ tipo: "ausente" });
  });

  it("na visão acumulada usa o acumulado do banco", () => {
    const grade = montarGradeMensal(linhas, "valor_acumulado");
    expect(grade.linhas[2].celulas).toEqual([
      { tipo: "valor", valor: 20000 },
      { tipo: "valor", valor: 30000 },
    ]);
  });

  it("indisponível no mês aparece como indisponível na célula", () => {
    const grade = montarGradeMensal(
      [{ ...linhas[1], valor_mes: null, valor_acumulado: null, disponivel: false, motivo: "orcamento_ausente" }],
      "valor_mes",
    );
    expect(grade.linhas[0].celulas[0]).toEqual({ tipo: "indisponivel", motivo: "A obra não tem orçamento carregado." });
  });
});

describe("validação dos formulários do DRE", () => {
  const formulario = (campos: Record<string, string>) => {
    const dados = new FormData();
    Object.entries(campos).forEach(([nome, valor]) => dados.set(nome, valor));
    return leitorDoFormulario(dados);
  };
  const obra = "dba8148c-5ef6-4b83-ba1b-f84fddf2ae58";

  it("aceita classificação completa e limpa espaços", () => {
    expect(
      validarClassificacao(
        formulario({ tipo_origem: "titulo_pagar", conta_origem: " 2.01.001 ", categoria_codigo: "materiais" }),
      ),
    ).toEqual({
      ok: true,
      dados: { tipo_origem: "titulo_pagar", conta_origem: "2.01.001", categoria_codigo: "materiais", observacao: null },
    });
  });

  it("recusa tipo fora da lista, conta vazia e categoria com caractere estranho", () => {
    const resultado = validarClassificacao(
      formulario({ tipo_origem: "extrato", conta_origem: "", categoria_codigo: "materiais'; drop" }),
    );
    expect(resultado.ok).toBe(false);
    if (!resultado.ok)
      expect(Object.keys(resultado.erros).sort()).toEqual(["categoria_codigo", "conta_origem", "tipo_origem"]);
  });

  it("recusa conta e observação longas demais", () => {
    const resultado = validarClassificacao(
      formulario({
        tipo_origem: "orcamento",
        conta_origem: "9".repeat(61),
        categoria_codigo: "terreno",
        observacao: "x".repeat(501),
      }),
    );
    expect(resultado.ok).toBe(false);
    if (!resultado.ok) expect(Object.keys(resultado.erros).sort()).toEqual(["conta_origem", "observacao"]);
  });

  it("segue a regra do gatilho: título em saída, parcela em entrada, orçamento só em custo do imóvel", () => {
    const materiais = { natureza: "saida" as const, grupo_dre: "custo_imovel" as const };
    const corretagem = { natureza: "saida" as const, grupo_dre: "despesa_comercial" as const };
    const venda = { natureza: "entrada" as const, grupo_dre: "receita_bruta" as const };
    expect(categoriaServeParaOrigem("titulo_pagar", materiais)).toBe(true);
    expect(categoriaServeParaOrigem("titulo_pagar", venda)).toBe(false);
    expect(categoriaServeParaOrigem("parcela_receber", venda)).toBe(true);
    expect(categoriaServeParaOrigem("parcela_receber", corretagem)).toBe(false);
    expect(categoriaServeParaOrigem("orcamento", materiais)).toBe(true);
    expect(categoriaServeParaOrigem("orcamento", corretagem)).toBe(false);
    expect(categoriasPara("orcamento", [materiais, corretagem, venda])).toEqual([materiais]);
  });

  it("ligar o percentual de conclusão exige confirmação e observação", () => {
    const resultado = validarCriterio(formulario({ escopo: escopoTenant, metodo: "percentual_conclusao" }));
    expect(resultado.ok).toBe(false);
    if (!resultado.ok) expect(Object.keys(resultado.erros).sort()).toEqual(["confirmacao", "observacao"]);
  });

  it("aceita critério do tenant ou de uma obra", () => {
    expect(
      validarCriterio(
        formulario({
          escopo: escopoTenant,
          metodo: "percentual_conclusao",
          confirmacao: "sim",
          observacao: "Validado com o contador",
        }),
      ),
    ).toEqual({
      ok: true,
      dados: { centro_custo_id: null, metodo: "percentual_conclusao", observacao: "Validado com o contador" },
    });
    expect(validarCriterio(formulario({ escopo: obra.toUpperCase(), metodo: "nao_definido" }))).toEqual({
      ok: true,
      dados: { centro_custo_id: obra, metodo: "nao_definido", observacao: null },
    });
  });

  it("recusa escopo que não é tenant nem UUID e método desconhecido", () => {
    const resultado = validarCriterio(formulario({ escopo: "todas", metodo: "entrega_chaves" }));
    expect(resultado.ok).toBe(false);
    if (!resultado.ok) expect(Object.keys(resultado.erros).sort()).toEqual(["escopo", "metodo"]);
  });

  it("erro do banco vira frase sem código nem SQL", () => {
    expect(fraseErroGravacao("42501")).toBe("Só diretor ou financeiro da construtora pode gravar esta informação.");
    expect(fraseErroGravacao("23514")).toBe("O banco recusou a gravação. Confira os dados e tente de novo.");
    expect(fraseErroGravacao(undefined)).not.toMatch(/\d{5}|select|insert/i);
  });
});
