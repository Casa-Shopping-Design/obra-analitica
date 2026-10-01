import { describe, expect, it } from "vitest";
import { lerComparativo, pioresValores, type LinhaComparativo } from "../lib/comparativo";

function obra(id: string, parcial: Partial<LinhaComparativo> = {}): LinhaComparativo {
  return {
    centro_custo_id: id,
    obra: `Obra ${id}`,
    vgv_total: 1000,
    pct_vgv_vendido: 0.5,
    vendas_liquidas_12m: 2,
    estoque_inicio_12m: 4,
    vso_12m: 0.5,
    unidades_estoque: 2,
    valor_estoque: 500,
    resultado_projetado: 200,
    margem_projetada: 0.2,
    exposicao_maxima: 300,
    caixa_atual: -100,
    vencido_direto: 10,
    pct_inadimplencia: 0.01,
    pct_fisico: 0.5,
    pct_financeiro: 0.5,
    diferenca_financeiro_fisico: 0,
    alertas: 0,
    ...parcial,
  };
}

describe("pior valor de cada coluna", () => {
  it("marca o menor quando menos é pior e o maior quando mais é pior", () => {
    const piores = pioresValores([
      obra("a", { vso_12m: 0.05, exposicao_maxima: 900, caixa_atual: -500 }),
      obra("b", { vso_12m: 0.8, exposicao_maxima: 100, caixa_atual: 50 }),
    ]);
    expect([...piores.vso_12m]).toEqual(["a"]);
    expect([...piores.exposicao_maxima]).toEqual(["a"]);
    expect([...piores.caixa_atual]).toEqual(["a"]);
  });

  it("marca todas as obras empatadas no pior valor", () => {
    const piores = pioresValores([obra("a", { alertas: 3 }), obra("b", { alertas: 3 }), obra("c", { alertas: 1 })]);
    expect([...piores.alertas].sort()).toEqual(["a", "b"]);
  });

  it("não marca coluna com o mesmo valor em todas as obras", () => {
    const piores = pioresValores([obra("a"), obra("b")]);
    expect(piores.alertas.size).toBe(0);
    expect(piores.margem_projetada.size).toBe(0);
  });

  it("ignora obra sem número e não compara uma obra sozinha", () => {
    const piores = pioresValores([
      obra("a", { diferenca_financeiro_fisico: null, vso_12m: null }),
      obra("b", { diferenca_financeiro_fisico: 0.18, vso_12m: 0.1 }),
      obra("c", { diferenca_financeiro_fisico: 0.03, vso_12m: null }),
    ]);
    expect([...piores.diferenca_financeiro_fisico]).toEqual(["b"]);
    expect(piores.vso_12m.size).toBe(0);
  });

  it("não marca o VGV, que mede tamanho e não desempenho", () => {
    const piores = pioresValores([obra("a", { vgv_total: 10 }), obra("b", { vgv_total: 99 })]);
    expect(Object.keys(piores)).not.toContain("vgv_total");
  });
});

describe("leitura do comparativo", () => {
  it("converte o numeric que vem como texto e mantém nulo o que é nulo", () => {
    const [linha] = lerComparativo([
      { centro_custo_id: "a", obra: "Residencial Aurora", vgv_total: "40955703.05", vso_12m: "0.5000", pct_fisico: null, alertas: 2 },
    ]);
    expect(linha.vgv_total).toBe(40955703.05);
    expect(linha.vso_12m).toBe(0.5);
    expect(linha.pct_fisico).toBeNull();
    expect(linha.caixa_atual).toBe(0);
    expect(linha.alertas).toBe(2);
  });
});
