import { describe, expect, it } from "vitest";
import {
  colunasDre,
  formatarMesAno,
  lerLinhaDre,
  linhasResultado,
  notaDre,
  percentualComSinal,
  prepararLinhasDre,
  rotuloLinha,
  situacaoDesvioMargem,
  textoDesvio,
  textoDesvioPontos,
  type LinhaDre,
} from "../lib/dre";
import { explicacoes } from "../lib/explicacoes";
import { formatarReal } from "../lib/formatar";
import { mensagens } from "../lib/mensagens";

// Cópia de marts.linha_resultado (migration 0030), na ordem da view.
const linhasDaView = [
  "vgv_bruto",
  "impostos",
  "vgv_liquido",
  "custo_vendas",
  "custo_empreendimento",
  "custo_terreno",
  "custo_projetos",
  "custo_licenciamento",
  "custo_construcao",
  "assistencia_tecnica",
  "juros_financiamento",
  "estoque",
  "resultado_bruto",
  "despesas",
  "despesas_comerciais",
  "despesas_administrativas",
  "lucro_operacional",
];

function linhaDre(linha: string, indice: number): LinhaDre {
  return {
    linha,
    ordem: (indice + 1) * 10,
    nivel: indice % 3,
    natureza: "custo",
    linhaDeTotal: indice % 4 === 0,
    fonteRealizado: indice === 5 ? "sem_fonte" : "total",
    viabilidade: 1000 + indice,
    pctViabilidade: 0.1,
    apropriado: 300 + indice,
    aApropriar: 200 + indice,
    aContratar: 600 + indice,
    aRealizar: 800 + indice,
    tendencia: 1100 + indice,
    pctTendencia: 0.11,
    desvio: 100,
    desvioPct: 0.1,
    desvioFavoravel: indice % 2 === 0 ? false : null,
  };
}

describe("rótulos da DRE", () => {
  it("toda linha de marts.linha_resultado tem rótulo próprio", () => {
    expect([...linhasResultado]).toEqual(linhasDaView);
    for (const linha of linhasDaView) {
      expect(rotuloLinha(linha)).not.toBe(linha);
      expect(rotuloLinha(linha).length).toBeGreaterThan(0);
    }
    expect(rotuloLinha("custo_terreno")).toBe("Custo do terreno");
    expect(rotuloLinha("vgv_bruto")).toBe("VGV bruto");
  });

  it("linha desconhecida aparece com o código em vez de sumir", () => {
    expect(rotuloLinha("linha_nova")).toBe("linha_nova");
  });

  it("toda coluna tem explicação e as dez do deck estão na ordem", () => {
    expect(colunasDre.map((coluna) => coluna.rotulo)).toEqual([
      "Viabilidade",
      "% Viab.",
      "Apropriado",
      "A apropriar",
      "A contratar",
      "A realizar",
      "Tendência",
      "% Tend.",
      "Desvio",
      "Desvio %",
    ]);
    for (const coluna of colunasDre) expect(explicacoes[coluna.explicacao].length).toBeGreaterThan(0);
  });
});

describe("texto do desvio", () => {
  it("diz a direção com o valor em real", () => {
    expect(textoDesvio(200)).toBe(`${formatarReal(200)} acima do estudo`);
    expect(textoDesvio(-200)).toBe(`${formatarReal(200)} abaixo do estudo`);
    expect(textoDesvio(0)).toBe("igual ao estudo");
  });

  it("percentual leva sinal e nulo vira sem base", () => {
    expect(percentualComSinal(0.05)).toBe("+5,0%");
    expect(percentualComSinal(-0.05)).toMatch(/^-5,0\s?%$/);
    expect(percentualComSinal(null)).toBe("sem base");
  });

  it("desvio da margem em pontos, com situação igual ao texto", () => {
    expect(textoDesvioPontos(0.023)).toBe("2,3 pontos acima do estudo");
    expect(textoDesvioPontos(-0.01)).toBe("1 ponto abaixo do estudo");
    expect(textoDesvioPontos(0.0004)).toBe("igual ao estudo");
    expect(textoDesvioPontos(null)).toBe("sem base");
    expect(situacaoDesvioMargem(0.023)).toBe("favoravel");
    expect(situacaoDesvioMargem(-0.023)).toBe("desfavoravel");
    expect(situacaoDesvioMargem(0.0004)).toBe("neutro");
  });
});

describe("linhas da tabela", () => {
  it("preserva a ordem recebida e não muda nenhum número", () => {
    const entrada = linhasDaView.map(linhaDre).reverse();
    const saida = prepararLinhasDre(entrada);
    expect(saida).toHaveLength(17);
    saida.forEach((linha, indice) => {
      const { rotulo, situacao, semRealizado, ...numeros } = linha;
      expect(numeros).toEqual(entrada[indice]);
      expect(rotulo).toBe(rotuloLinha(entrada[indice].linha));
      expect(semRealizado).toBe(entrada[indice].fonteRealizado === "sem_fonte");
      expect(situacao).toBe(entrada[indice].desvioFavoravel === false ? "desfavoravel" : "neutro");
    });
  });

  it("lê numeric em texto e mantém nulo onde a view devolve nulo", () => {
    const linha = lerLinhaDre({
      linha: "impostos",
      ordem: 20,
      nivel: 0,
      natureza: "deducao",
      linha_de_total: false,
      fonte_realizado: "sem_fonte",
      viabilidade: "2400000.00",
      pct_viabilidade: null,
      apropriado: "0",
      a_apropriar: 0,
      a_contratar: "2400000.00",
      a_realizar: "2400000.00",
      tendencia: "2400000.00",
      pct_tendencia: null,
      desvio: "0.00",
      desvio_pct: "0.0000",
      desvio_favoravel: null,
    });
    expect(linha.viabilidade).toBe(2400000);
    expect(linha.pctViabilidade).toBeNull();
    expect(linha.desvioPct).toBe(0);
    expect(linha.desvioFavoravel).toBeNull();
  });
});

describe("cabeçalho e mensagens", () => {
  it("nota cita o mês do realizado e o estudo", () => {
    expect(formatarMesAno("2026-09-01")).toBe("09/2026");
    expect(
      notaDre({ obra: "Aurora", competencia: "2026-08-01", estudoVersao: "2", estudoDataBase: "2024-10-15" }),
    ).toBe("Realizado até 08/2026. Estudo versão 2, de 15/10/2024.");
  });

  it("mensagens da DRE não citam tabela nem SQL", () => {
    for (const texto of Object.values(mensagens.dre)) {
      expect(texto).not.toMatch(/marts|select|dre_|stack/i);
    }
    expect(mensagens.dre.semEstudo).toBe("Esta obra ainda não tem estudo de viabilidade cadastrado.");
    expect(mensagens.dre.restrita).toBe("A DRE de viabilidade é restrita a diretor e financeiro.");
  });
});
