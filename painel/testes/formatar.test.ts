import { describe, expect, it } from "vitest";
import { formatarConversao, formatarData, formatarMes, formatarPercentual, formatarReal, formatarRealCompacto } from "../lib/formatar";

// Intl separa "R$" do número com espaço não quebrável; o teste normaliza para comparar.
const semEspacoEspecial = (texto: string) => texto.replace(/ | /g, " ");

describe("formatarReal", () => {
  it("usa ponto no milhar, vírgula no decimal e duas casas", () => {
    expect(semEspacoEspecial(formatarReal(1234567.891))).toBe("R$ 1.234.567,89");
  });

  it("mostra zero com centavos", () => {
    expect(semEspacoEspecial(formatarReal(0))).toBe("R$ 0,00");
  });

  it("mantém o sinal de negativo", () => {
    expect(semEspacoEspecial(formatarReal(-17436000))).toBe("-R$ 17.436.000,00");
  });
});

describe("formatarPercentual", () => {
  it("converte fração em percentual com uma casa", () => {
    expect(semEspacoEspecial(formatarPercentual(0.37))).toBe("37,0%");
  });

  it("aceita valor acima de 100%", () => {
    expect(semEspacoEspecial(formatarPercentual(1.2389))).toBe("123,9%");
  });
});

describe("formatarData", () => {
  it("formata data pura sem deslocar o dia pelo fuso", () => {
    expect(formatarData("2026-09-22")).toBe("22/09/2026");
  });

  it("formata data e hora no fuso de Brasília", () => {
    expect(formatarData("2026-09-23T02:30:00Z")).toBe("22/09/2026");
  });
});

describe("formatarRealCompacto", () => {
  it("abrevia milhões para o eixo do gráfico", () => {
    expect(semEspacoEspecial(formatarRealCompacto(1250000))).toBe("R$ 1,3 mi");
  });
});

describe("formatarMes", () => {
  it("mostra mês abreviado e ano com dois dígitos", () => {
    expect(formatarMes("2026-09")).toBe("set/26");
    expect(formatarMes("2027-01-01")).toBe("jan/27");
  });
});

describe("formatarConversao", () => {
  it("mostra a taxa até 100%", () => {
    expect(semEspacoEspecial(formatarConversao(0.5, "mais vendas que reservas"))).toBe("50,0%");
    expect(semEspacoEspecial(formatarConversao(1, "mais vendas que reservas"))).toBe("100,0%");
  });

  it("acima de 100% diz o que aconteceu", () => {
    expect(formatarConversao(2, "mais vendas que reservas")).toBe("mais vendas que reservas");
  });

  it("sem denominador não inventa taxa", () => {
    expect(formatarConversao(null, "mais vendas que reservas")).toBe("sem base");
  });
});
