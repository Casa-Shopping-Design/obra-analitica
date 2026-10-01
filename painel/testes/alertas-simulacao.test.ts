import { describe, expect, it } from "vitest";
import { lerAlertas, ordenarAlertas, textoAlerta, type AlertaObra } from "../lib/alertas";
import { formatarMeses } from "../lib/formatar";
import { lerDesconto, lerRitmo, recortarSerie, ritmoMaisProximo } from "../lib/simulacao";

// Intl separa "R$" do número com espaço não quebrável.
function semEspacoFixo(texto: string): string {
  return texto.replace(/\u00a0/g, " ");
}

function alerta(parcial: Partial<AlertaObra> & Pick<AlertaObra, "tipo">): AlertaObra {
  return { centro_custo_id: "obra-1", obra: "Residencial Aurora", valor: null, referencia: null, ...parcial };
}

describe("texto dos alertas", () => {
  it("estoque que não acaba antes da entrega diz os dois prazos", () => {
    const texto = textoAlerta(alerta({ tipo: "estoque_apos_entrega", valor: 9.7, referencia: 9 }));
    expect(texto.titulo).toBe("Estoque não acaba antes da entrega");
    expect(texto.detalhe).toContain("9,7 meses para vender");
    expect(texto.detalhe).toContain("daqui a 9 meses");
    expect(texto.tela).toBe("estoque");
  });

  it("obra já entregue com estoque troca o título", () => {
    const texto = textoAlerta(alerta({ tipo: "estoque_apos_entrega", valor: 2.7, referencia: 0 }));
    expect(texto.titulo).toBe("Obra entregue com estoque");
  });

  it("sem ritmo de venda o estoque aparece como parado, sem inventar prazo", () => {
    const texto = textoAlerta(alerta({ tipo: "estoque_apos_entrega", valor: null, referencia: 5 }));
    expect(texto.titulo).toBe("Estoque parado");
    expect(texto.detalhe).not.toMatch(/\d+,\d meses/);
  });

  it("estouro mostra o valor e a fração do orçado", () => {
    const texto = textoAlerta(alerta({ tipo: "estouro_orcamento", valor: 2078085.64, referencia: 17500000 }));
    expect(semEspacoFixo(texto.detalhe)).toContain("R$ 2.078.085,64");
    expect(texto.detalhe).toContain("11,9%");
    expect(texto.tela).toBe("");
  });

  it("estouro sem orçamento cadastrado não divide por zero", () => {
    const texto = textoAlerta(alerta({ tipo: "estouro_orcamento", valor: 1000, referencia: 0 }));
    expect(semEspacoFixo(texto.detalhe)).toBe("Há R$ 1.000,00 de custo lançado sem orçamento cadastrado.");
  });

  it("pago à frente do físico em pontos percentuais", () => {
    expect(textoAlerta(alerta({ tipo: "pago_a_frente_do_fisico", valor: 0.2279 })).detalhe).toContain("23 pontos");
  });
});

describe("lista de alertas", () => {
  it("ignora tipo que a tela não conhece e converte numeric em texto", () => {
    const lidos = lerAlertas([
      { centro_custo_id: "a", obra: "Obra A", tipo: "repasse_atrasado", valor: "526203.86", referencia: null },
      { centro_custo_id: "a", obra: "Obra A", tipo: "tipo_novo", valor: 1, referencia: null },
    ]);
    expect(lidos).toEqual([
      { centro_custo_id: "a", obra: "Obra A", tipo: "repasse_atrasado", valor: 526203.86, referencia: null },
    ]);
  });

  it("ordena pelo peso do alerta e depois pelo nome da obra", () => {
    const ordenados = ordenarAlertas([
      alerta({ tipo: "pago_a_frente_do_fisico", obra: "Aurora" }),
      alerta({ tipo: "estouro_orcamento", obra: "Torre" }),
      alerta({ tipo: "repasse_atrasado", obra: "Torre" }),
      alerta({ tipo: "estouro_orcamento", obra: "Águas" }),
    ]);
    expect(ordenados.map((item) => `${item.tipo}:${item.obra}`)).toEqual([
      "repasse_atrasado:Torre",
      "estouro_orcamento:Águas",
      "estouro_orcamento:Torre",
      "pago_a_frente_do_fisico:Aurora",
    ]);
  });
});

describe("parâmetros da simulação", () => {
  it("aceita só os ritmos e descontos da lista", () => {
    expect(lerRitmo("4", 2)).toBe(4);
    expect(lerRitmo("3", 2)).toBe(2);
    expect(lerRitmo("1000", 2)).toBe(2);
    expect(lerRitmo(undefined, 1)).toBe(1);
    expect(lerRitmo(["8", "1"], 2)).toBe(8);
    expect(lerDesconto("10")).toBe(10);
    expect(lerDesconto("50")).toBe(0);
    expect(lerDesconto("-5")).toBe(0);
  });

  it("abre no ritmo da lista mais perto do que a obra vendeu", () => {
    expect(ritmoMaisProximo(null)).toBe(1);
    expect(ritmoMaisProximo(0)).toBe(1);
    expect(ritmoMaisProximo(0.17)).toBe(1);
    expect(ritmoMaisProximo(3.83)).toBe(4);
    expect(ritmoMaisProximo(20)).toBe(8);
  });

  it("recorta a série 12 meses antes de hoje e mantém o resto", () => {
    const serie = ["2025-08-01", "2025-09-01", "2025-10-01", "2026-09-01", "2030-01-01"].map((competencia) => ({ competencia }));
    expect(recortarSerie(serie, "2026-09").map((ponto) => ponto.competencia)).toEqual([
      "2025-09-01",
      "2025-10-01",
      "2026-09-01",
      "2030-01-01",
    ]);
  });
});

describe("meses por extenso", () => {
  it("uma casa decimal e singular para um mês", () => {
    expect(formatarMeses(1)).toBe("1 mês");
    expect(formatarMeses(9.66)).toBe("9,7 meses");
    expect(formatarMeses(335.29)).toBe("335,3 meses");
    expect(formatarMeses(0)).toBe("0 meses");
  });
});
