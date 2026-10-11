import { describe, expect, it } from "vitest";
import {
  ehLinhaIndicador,
  idEmpresaValido,
  lerContaSemMapa,
  lerControle,
  lerLinhaDemonstrativo,
  lerLinhaMensal,
  lerResumoEmpresa,
  montarGradeMensal,
  nomeExibido,
  perfilEditaMapa,
  perfilVeEmpresas,
  separarIndicadoresCusto,
  situacaoIdentidade,
  type LinhaMensal,
} from "../lib/empresa";

function mensal(linha: string, ordem: number, competencia: string, valorMes: number, valorAcumulado: number): LinhaMensal {
  return { linha, rotulo: linha, ordem, tipo: "conta", nivel: 2, competencia, valorMes, valorAcumulado };
}

describe("perfis da visão por empresa", () => {
  it.each([
    ["diretor", true, true],
    ["financeiro", true, true],
    ["leitura", true, false],
    ["gerente_obra", false, false],
    ["comercial", false, false],
    [null, false, false],
  ])("%s vê empresas: %s; edita o mapa: %s", (perfil, ve, edita) => {
    expect(perfilVeEmpresas(perfil)).toBe(ve);
    expect(perfilEditaMapa(perfil)).toBe(edita);
  });

  it("aceita só uuid como id de empresa", () => {
    expect(idEmpresaValido("7a1c3e5f-2b4d-4c6e-8f0a-1b2c3d4e5f60")).toBe(true);
    expect(idEmpresaValido("11")).toBe(false);
    expect(idEmpresaValido("7a1c3e5f-2b4d-4c6e-8f0a-1b2c3d4e5f60' or 1=1")).toBe(false);
  });
});

describe("leitura das linhas do banco", () => {
  it("lê o resumo da empresa com numeric em texto e competência nula antes da carga", () => {
    const resumo = lerResumoEmpresa({
      empresa_id: "e1",
      nome: "Aurora Empreendimentos SPE Ltda",
      nome_fantasia: "Aurora",
      obras: 1,
      primeira_competencia: null,
      ultima_competencia: null,
      caixa_equivalentes: "1250.40",
      fluxo_operacional: null,
      lucro_liquido: "-300.10",
      diferenca_identidade: "0",
      contas_sem_mapa: 2,
    });
    expect(resumo).toMatchObject({
      nomeFantasia: "Aurora",
      ultimaCompetencia: null,
      caixaEquivalentes: 1250.4,
      fluxoOperacional: null,
      lucroLiquido: -300.1,
      contasSemMapa: 2,
    });
    expect(nomeExibido(resumo)).toBe("Aurora");
    expect(nomeExibido({ ...resumo, nomeFantasia: null })).toBe("Aurora Empreendimentos SPE Ltda");
  });

  it("lê a linha do demonstrativo com o percentual da coluna pedida", () => {
    const linha = lerLinhaDemonstrativo(
      { ordem: 3, linha: "receita_liquida", rotulo: "RECEITA LÍQUIDA", tipo: "total", nivel: 0, valor: "900.5", pct_receita_liquida: "1" },
      "pct_receita_liquida",
    );
    expect(linha).toEqual({ ordem: 3, linha: "receita_liquida", rotulo: "RECEITA LÍQUIDA", tipo: "total", nivel: 0, valor: 900.5, percentual: 1 });
    expect(lerLinhaDemonstrativo({ ordem: 1, linha: "bancos", valor: 10 }).percentual).toBeNull();
  });

  it("lê a linha mensal cortando a competência no mês", () => {
    const linha = lerLinhaMensal({
      linha: "caixa", rotulo: "Caixa", ordem: 9, tipo: "conta", nivel: 2, competencia: "2026-03-01", valor_mes: "5", valor_acumulado: "20",
    });
    expect(linha).toMatchObject({ competencia: "2026-03", valorMes: 5, valorAcumulado: 20 });
  });

  it("lê o controle e a conta sem mapa", () => {
    expect(
      lerControle({
        competencia: "2026-09-01", saldo_liquido_acumulado: "100", caixa_equivalentes_acumulado: "100", diferenca_identidade: "0",
        lucros_acumulados: "50", lucro_liquido_dre: "48", ajuste_exercicios_anteriores: "2", contas_sem_mapa: 0, movimento_sem_mapa: "0",
      }),
    ).toMatchObject({ diferencaIdentidade: 0, ajusteExerciciosAnteriores: 2, lucroLiquidoDre: 48 });
    expect(lerContaSemMapa({ conta: "1.1.9.01.0001", conta_reduzida: "77", nome: "Conta nova", grupo: "ativo", saldo_final: "3", movimento: "3" }))
      .toEqual({ conta: "1.1.9.01.0001", contaReduzida: 77, nome: "Conta nova", grupo: "ativo", saldoFinal: 3, movimento: 3 });
  });
});

describe("montarGradeMensal", () => {
  const meses = ["2026-01", "2026-02", "2026-03"];

  it("transpõe uma linha por mês em uma coluna por mês, na ordem do relatório", () => {
    const linhas = [
      mensal("caixa", 30, "2026-02", 5, 15),
      mensal("bancos", 10, "2026-01", 1, 1),
      mensal("caixa", 30, "2026-01", 10, 10),
      mensal("bancos", 10, "2026-03", 2, 3),
    ];
    expect(montarGradeMensal(linhas, meses, false)).toEqual([
      { linha: "bancos", rotulo: "bancos", tipo: "conta", nivel: 2, valores: [1, null, 2] },
      { linha: "caixa", rotulo: "caixa", tipo: "conta", nivel: 2, valores: [10, 5, null] },
    ]);
  });

  it("usa o acumulado no modo acumulado, sem somar nada", () => {
    const linhas = [mensal("caixa", 1, "2026-01", 10, 10), mensal("caixa", 1, "2026-02", 5, 15)];
    expect(montarGradeMensal(linhas, meses, true)[0].valores).toEqual([10, 15, null]);
  });

  it("ignora mês fora da grade e devolve vazio sem linhas", () => {
    expect(montarGradeMensal([mensal("caixa", 1, "2025-12", 1, 1)], meses, false)).toEqual([]);
    expect(montarGradeMensal([], meses, true)).toEqual([]);
  });
});

describe("indicadores do custo incorrido", () => {
  it("separa as duas linhas de indicador da tabela", () => {
    const linhas = [
      lerLinhaDemonstrativo({ ordem: 1, linha: "custo_incorrido", tipo: "total", nivel: 0, valor: 100 }),
      lerLinhaDemonstrativo({ ordem: 90, linha: "pct_levado_ao_resultado", tipo: "indicador", nivel: 0, valor: 0.4 }),
      lerLinhaDemonstrativo({ ordem: 91, linha: "taxa_encargos", tipo: "indicador", nivel: 0, valor: 0.8 }),
    ];
    const { linhas: tabela, indicadores } = separarIndicadoresCusto(linhas);
    expect(tabela.map((linha) => linha.linha)).toEqual(["custo_incorrido"]);
    expect(indicadores).toEqual({ pctLevadoAoResultado: 0.4, taxaEncargos: 0.8 });
  });

  it("sem as linhas de indicador devolve nulo e não mexe na tabela", () => {
    const linhas = [lerLinhaDemonstrativo({ ordem: 1, linha: "custo_terreno", tipo: "conta", nivel: 1, valor: 5 })];
    expect(separarIndicadoresCusto(linhas)).toEqual({ linhas, indicadores: { pctLevadoAoResultado: null, taxaEncargos: null } });
    expect(ehLinhaIndicador({ tipo: "conta", linha: "taxa_encargos" })).toBe(true);
  });
});

describe("situacaoIdentidade", () => {
  it.each([
    [0, "fecha"],
    [0.004, "fecha"],
    [-0.004, "fecha"],
    [0.01, "diferenca"],
    [-1500, "diferenca"],
    [null, "sem_dado"],
  ])("diferença %s: %s", (diferenca, esperado) => {
    expect(situacaoIdentidade(diferenca)).toBe(esperado);
  });
});
