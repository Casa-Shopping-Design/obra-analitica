import { describe, expect, it } from "vitest";
import {
  deslocarMes,
  mesCorrente,
  montarSerieFluxo,
  type LinhaFluxoCenario,
  type LinhaFluxoMensal,
} from "../lib/serie-fluxo";

function linhaMensal(competencia: string, valor: number): LinhaFluxoMensal {
  return {
    competencia,
    entrada_direta_realizada: valor,
    entrada_direta_prevista: valor + 1,
    entrada_direta_vencida: 0,
    repasse_realizado: valor + 2,
    repasse_previsto: valor + 3,
    repasse_vencido: 0,
    saida_realizada: valor + 4,
    saida_prevista: valor + 5,
    saida_vencida: valor + 6,
    saldo_acumulado: valor * 10,
  };
}

// Cinco anos de meses, de jan/2024 a dez/2028, com os pares e os ímpares separados para sair da ordem.
function cincoAnosForaDeOrdem(): LinhaFluxoMensal[] {
  const linhas: LinhaFluxoMensal[] = [];
  for (let indice = 0; indice < 60; indice++) {
    linhas.push(linhaMensal(`${deslocarMes("2024-01", indice)}-01`, indice));
  }
  return [...linhas.filter((_, indice) => indice % 2 === 1), ...linhas.filter((_, indice) => indice % 2 === 0)];
}

describe("deslocarMes", () => {
  it("atravessa a virada de ano nos dois sentidos", () => {
    expect(deslocarMes("2026-09", -12)).toBe("2025-09");
    expect(deslocarMes("2026-09", 23)).toBe("2028-08");
    expect(deslocarMes("2026-01", -1)).toBe("2025-12");
  });
});

describe("mesCorrente", () => {
  it("usa o fuso de Brasília na virada do mês", () => {
    expect(mesCorrente(new Date("2026-10-01T02:00:00Z"))).toBe("2026-09");
  });
});

describe("montarSerieFluxo", () => {
  it("ordena por mês e recorta 12 meses para trás e 24 para frente", () => {
    const serie = montarSerieFluxo(cincoAnosForaDeOrdem(), null, "2026-09");

    expect(serie).toHaveLength(36);
    expect(serie[0].competencia).toBe("2025-09");
    expect(serie[35].competencia).toBe("2028-08");
    const meses = serie.map((ponto) => ponto.competencia);
    expect(meses).toEqual([...meses].sort());
  });

  it("copia os valores da view sem somar nada", () => {
    const [ponto] = montarSerieFluxo([linhaMensal("2026-09-01", 100)], null, "2026-09");

    expect(ponto).toEqual({
      competencia: "2026-09",
      entradaDiretaRealizada: 100,
      entradaDiretaPrevista: 101,
      repasseRealizado: 102,
      repassePrevisto: 103,
      repasseCenario: null,
      saidaRealizada: 104,
      saidaPrevista: 105,
      saidaVencida: 106,
      saldoAcumulado: 1000,
    });
  });

  it("converte numeric que chega como texto", () => {
    const linha = { ...linhaMensal("2026-09-01", 0), saldo_acumulado: "-1234.56" };
    const [ponto] = montarSerieFluxo([linha], null, "2026-09");

    expect(ponto.saldoAcumulado).toBe(-1234.56);
  });

  it("no cenário, repasse e saldo vêm da função e o mês deslocado para fora da view entra na série", () => {
    const mensais = [linhaMensal("2026-09-01", 100)];
    const cenario: LinhaFluxoCenario[] = [
      { competencia: "2026-12-01", entrada_direta: 0, repasse: 103, saida: 0, saldo_acumulado: 500 },
      { competencia: "2026-09-01", entrada_direta: 201, repasse: 102, saida: 315, saldo_acumulado: 400 },
    ];
    const serie = montarSerieFluxo(mensais, cenario, "2026-09");

    expect(serie.map((ponto) => ponto.competencia)).toEqual(["2026-09", "2026-12"]);
    expect(serie[0]).toMatchObject({
      entradaDiretaRealizada: 100,
      repasseRealizado: null,
      repassePrevisto: null,
      repasseCenario: 102,
      saidaVencida: 106,
      saldoAcumulado: 400,
    });
    expect(serie[1]).toMatchObject({ entradaDiretaRealizada: null, repasseCenario: 103, saldoAcumulado: 500 });
  });

  it("descarta o mês do cenário que passa do fim da janela", () => {
    const cenario: LinhaFluxoCenario[] = [
      { competencia: "2028-09-01", entrada_direta: 0, repasse: 50, saida: 0, saldo_acumulado: 10 },
    ];

    expect(montarSerieFluxo([], cenario, "2026-09")).toEqual([]);
  });
});
