import { describe, expect, it } from "vitest";
import {
  juntarRecebimentoMensal,
  rotulosSituacao,
  situacoesParcela,
  valorDaOrigem,
} from "../componentes/financeiro/receitas-tela";
import { intervaloDaPagina, lerPagina, linhasPorPagina, montarPaginacao } from "../lib/periodo";

describe("paginação da carteira", () => {
  it("usa 50 linhas por página", () => {
    expect(linhasPorPagina).toBe(50);
    expect(intervaloDaPagina(1)).toEqual({ de: 0, ate: 49 });
    expect(intervaloDaPagina(3)).toEqual({ de: 100, ate: 149 });
  });

  it("calcula páginas, anterior e próxima pelo total do banco", () => {
    expect(montarPaginacao(1, 120)).toMatchObject({
      pagina: 1,
      totalPaginas: 3,
      anterior: null,
      proxima: 2,
      de: 0,
      ate: 49,
    });
    expect(montarPaginacao(3, 120)).toMatchObject({ pagina: 3, anterior: 2, proxima: null, de: 100, ate: 119 });
  });

  it("fecha a página pedida além do fim na última e trata carteira vazia", () => {
    expect(montarPaginacao(9, 120).pagina).toBe(3);
    expect(montarPaginacao(1, 0)).toMatchObject({ pagina: 1, totalPaginas: 1, anterior: null, proxima: null });
    expect(montarPaginacao(1, 50)).toMatchObject({ totalPaginas: 1, proxima: null });
    expect(montarPaginacao(1, 51)).toMatchObject({ totalPaginas: 2, proxima: 2 });
  });

  it("lê a página da URL só como inteiro positivo", () => {
    expect(lerPagina("4")).toBe(4);
    expect(lerPagina("0")).toBe(1);
    expect(lerPagina("-2")).toBe(1);
    expect(lerPagina("2.5")).toBe(1);
    expect(lerPagina("abc")).toBe(1);
    expect(lerPagina(undefined)).toBe(1);
    expect(lerPagina("99999999")).toBe(1);
  });
});

describe("recebimento mensal", () => {
  it("junta direta e financiamento no mesmo mês, sem somar", () => {
    const pontos = juntarRecebimentoMensal([
      {
        competencia: "2026-10-01",
        origem: "financiamento",
        recebido: 0,
        previsto_contratual: 90000,
        saldo_em_aberto: 90000,
      },
      { competencia: "2026-09-01", origem: "direta", recebido: 3000, previsto_contratual: 4000, saldo_em_aberto: 1000 },
      {
        competencia: "2026-09-01",
        origem: "financiamento",
        recebido: 50000,
        previsto_contratual: 50000,
        saldo_em_aberto: 0,
      },
    ]);
    expect(pontos.map((ponto) => ponto.competencia)).toEqual(["2026-09-01", "2026-10-01"]);
    expect(pontos[0]).toMatchObject({ recebidoDireta: 3000, recebidoFinanciamento: 50000, previstoDireta: 4000 });
    expect(pontos[1]).toMatchObject({ recebidoDireta: null, previstoFinanciamento: 90000 });
  });

  it("origem sem linha na função de período é desconhecida, não zero", () => {
    const linhas = [{ origem: "direta" as const, recebido: 1200, previsto_contratual: 1500 }];
    expect(valorDaOrigem(linhas, "direta", "recebido")).toBe(1200);
    expect(valorDaOrigem(linhas, "financiamento", "recebido")).toBeNull();
  });

  it("tem rótulo para toda situação de parcela", () => {
    situacoesParcela.forEach((situacao) => expect(rotulosSituacao[situacao]).toBeTruthy());
  });
});
