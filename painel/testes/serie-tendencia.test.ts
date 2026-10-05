import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { GraficoTendencia, MiniaturaTendencia } from "../componentes/GraficoTendencia";
import { explicacoes } from "../lib/explicacoes";
import { mensagens } from "../lib/mensagens";
import {
  agruparSeriePorObra,
  formatarMargem,
  inicioJanela,
  lerLinhaTendenciaObra,
  lerPontoTendencia,
  mesesNaSerie,
  recortarSerie,
  resumoSerie,
  type PontoTendencia,
} from "../lib/serie-tendencia";

function mes(indice: number): string {
  const ano = 2024 + Math.floor(indice / 12);
  return `${ano}-${String((indice % 12) + 1).padStart(2, "0")}-01`;
}

function ponto(indice: number): PontoTendencia {
  return { competencia: mes(indice), margemViabilidade: 0.1964, margemTendencia: indice / 1000 };
}

// 30 meses, de 01/2024 a 06/2026, embaralhados numa ordem fixa para o teste não depender do acaso.
const trintaMeses = Array.from({ length: 30 }, (_, indice) => ponto((indice * 7) % 30));

describe("série de tendência", () => {
  it("30 meses fora de ordem viram os 24 mais recentes em ordem crescente", () => {
    const serie = recortarSerie(trintaMeses);
    expect(serie).toHaveLength(24);
    expect(mesesNaSerie).toBe(24);
    expect(serie[0].competencia).toBe("2024-07-01");
    expect(serie[23].competencia).toBe("2026-06-01");
    const competencias = serie.map((item) => item.competencia);
    expect(competencias).toEqual([...competencias].sort());
  });

  it("não mexe na entrada nem nos valores", () => {
    const copia = structuredClone(trintaMeses);
    const serie = recortarSerie(trintaMeses);
    expect(trintaMeses).toEqual(copia);
    expect(serie.find((item) => item.competencia === "2025-01-01")?.margemTendencia).toBe(0.012);
  });

  it("entrada vazia devolve lista vazia, e a tela diz quando a série começa", () => {
    expect(recortarSerie([])).toEqual([]);
    expect(agruparSeriePorObra([]).size).toBe(0);
    expect(resumoSerie([])).toBeNull();
    expect(mensagens.dre.serieVazia).toBe("A série começa no mês da primeira carga.");
  });

  it("margem 0,2153 aparece como 21,53%", () => {
    expect(formatarMargem(0.2153)).toBe("21,53%");
    expect(formatarMargem(null)).toBe("sem base");
  });

  it("lê numeric em texto como número e nulo como nulo", () => {
    expect(
      lerPontoTendencia({
        competencia: "2026-09-01",
        margem_operacional_viabilidade: "0.1964",
        margem_operacional_tendencia: null,
      }),
    ).toEqual({ competencia: "2026-09-01", margemViabilidade: 0.1964, margemTendencia: null });
  });

  it("agrupa a carteira por obra numa passada e recorta cada obra", () => {
    const linhas = [
      ...trintaMeses.map((item) => ({ ...item, centroCustoId: "norte" })),
      { ...ponto(3), centroCustoId: "sul" },
      { ...ponto(1), centroCustoId: "sul" },
    ];
    const porObra = agruparSeriePorObra(linhas);
    expect(porObra.get("norte")).toHaveLength(24);
    expect(porObra.get("sul")?.map((item) => item.competencia)).toEqual(["2024-02-01", "2024-04-01"]);
    expect(porObra.get("sul")?.[0]).not.toHaveProperty("centroCustoId");
    expect(
      lerLinhaTendenciaObra({ centro_custo_id: "sul", competencia: "2026-09-01" }).centroCustoId,
    ).toBe("sul");
  });

  it("a janela da lista começa 23 meses antes do mês corrente, no fuso de Brasília", () => {
    expect(inicioJanela(new Date("2026-10-05T12:00:00Z"))).toBe("2024-11-01");
    expect(inicioJanela(new Date("2026-10-01T02:00:00Z"))).toBe("2024-10-01");
  });

  it("o resumo lido no lugar da miniatura cita o primeiro e o último mês", () => {
    const serie = [
      { competencia: "2025-10-01", margemViabilidade: 0.1964, margemTendencia: 0.2241 },
      { competencia: "2026-09-01", margemViabilidade: 0.1964, margemTendencia: 0.2153 },
    ];
    expect(resumoSerie(serie)).toBe(
      "Margem na tendência de 22,41% em out/25 a 21,53% em set/26.",
    );
    expect(resumoSerie(serie.slice(1))).toBe("Margem na tendência de 21,53% em set/26.");
  });

  it("a tela sem série mostra quando ela começa, no gráfico e na miniatura", () => {
    const grafico = renderToStaticMarkup(createElement(GraficoTendencia, { pontos: [] }));
    const miniatura = renderToStaticMarkup(createElement(MiniaturaTendencia, { pontos: [] }));
    expect(grafico).toContain("A série começa no mês da primeira carga.");
    expect(miniatura).toContain("A série começa no mês da primeira carga.");
  });

  it("a tela mostra a margem 0,2153 como 21,53%, no texto e na tabela equivalente", () => {
    const pontos = [{ competencia: "2026-09-01", margemViabilidade: 0.1964, margemTendencia: 0.2153 }];
    const html = renderToStaticMarkup(createElement(GraficoTendencia, { pontos }));
    expect(html).toContain("Em set/26: tendência");
    expect(html.match(/21,53%/g)).toHaveLength(2);
    expect(html).toContain("19,64%");
    expect(html).toContain('<th scope="row">set/26</th>');
    expect(html).toContain("Margem no estudo");
  });

  it("o gráfico tem explicação própria", () => {
    expect(explicacoes.tendencia_margem_mensal).toContain("primeira carga");
  });
});
