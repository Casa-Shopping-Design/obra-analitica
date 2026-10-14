import { describe, expect, it } from "vitest";
import {
  descreverPeriodo,
  enderecoEmpresa,
  lerPeriodo,
  mesesDaGrade,
  mesesDisponiveis,
  parametrosDemonstrativo,
  rotuloMes,
} from "../lib/empresa-periodo";

const limites = { primeira: "2025-01-01", ultima: "2026-09-01" };
const idEmpresa = "7a1c3e5f-2b4d-4c6e-8f0a-1b2c3d4e5f60";

describe("lerPeriodo", () => {
  it("sem nada na URL é acumulado até a última competência, aba Fontes e Usos, sem mês a mês", () => {
    expect(lerPeriodo({}, limites)).toEqual({
      inicio: "2026-01",
      fim: "2026-09",
      acumulado: true,
      mensal: false,
      aba: "fontes-usos",
    });
  });

  it("lê o período, o modo, a visão e a aba pedidos", () => {
    expect(lerPeriodo({ de: "2025-03", ate: "2025-11", modo: "periodo", visao: "mensal", aba: "dre" }, limites)).toEqual({
      inicio: "2025-03",
      fim: "2025-11",
      acumulado: false,
      mensal: true,
      aba: "dre",
    });
  });

  it("mês fora do carregado, mal formado ou inicial depois do final cai no padrão", () => {
    expect(lerPeriodo({ ate: "2027-01" }, limites).fim).toBe("2026-09");
    expect(lerPeriodo({ ate: "2024-12" }, limites).fim).toBe("2026-09");
    expect(lerPeriodo({ ate: "2026-13" }, limites).fim).toBe("2026-09");
    expect(lerPeriodo({ ate: "'; drop" }, limites).fim).toBe("2026-09");
    expect(lerPeriodo({ de: "2026-05", ate: "2026-02" }, limites)).toMatchObject({ inicio: "2026-01", fim: "2026-02" });
  });

  it("o início padrão não passa da primeira competência carregada", () => {
    expect(lerPeriodo({ ate: "2025-06" }, limites).inicio).toBe("2025-01");
    expect(lerPeriodo({}, { primeira: "2026-04-01", ultima: "2026-09-01" }).inicio).toBe("2026-04");
  });

  it("aba desconhecida volta para Fontes e Usos e valor repetido usa o primeiro", () => {
    expect(lerPeriodo({ aba: "balanco" }, limites).aba).toBe("fontes-usos");
    expect(lerPeriodo({ aba: ["custo", "dre"] }, limites).aba).toBe("custo");
  });
});

describe("parametrosDemonstrativo", () => {
  it("manda o primeiro dia de cada mês e o modo para a função do banco", () => {
    const periodo = lerPeriodo({ de: "2025-03", ate: "2025-11", modo: "periodo" }, limites);
    expect(parametrosDemonstrativo(idEmpresa, periodo)).toEqual({
      p_empresa: idEmpresa,
      p_inicio: "2025-03-01",
      p_fim: "2025-11-01",
      p_acumulado: false,
    });
    expect(parametrosDemonstrativo(idEmpresa, lerPeriodo({}, limites)).p_acumulado).toBe(true);
  });
});

describe("mesesDaGrade", () => {
  it("lista os meses do intervalo, virando o ano", () => {
    expect(mesesDaGrade({ inicio: "2025-11", fim: "2026-02" })).toEqual(["2025-11", "2025-12", "2026-01", "2026-02"]);
  });

  it("acima de doze meses fica com os doze que terminam no mês final", () => {
    const meses = mesesDaGrade({ inicio: "2025-01", fim: "2026-09" });
    expect(meses).toHaveLength(12);
    expect(meses[0]).toBe("2025-10");
    expect(meses[11]).toBe("2026-09");
  });

  it("um mês só vira uma coluna", () => {
    expect(mesesDaGrade({ inicio: "2026-09", fim: "2026-09" })).toEqual(["2026-09"]);
  });
});

describe("textos e endereços do período", () => {
  it("lista os meses carregados do mais recente ao mais antigo", () => {
    const meses = mesesDisponiveis(limites);
    expect(meses).toHaveLength(21);
    expect(meses[0]).toBe("2026-09");
    expect(meses[20]).toBe("2025-01");
  });

  it("escreve o mês e o período por extenso", () => {
    expect(rotuloMes("2026-03")).toBe("março de 2026");
    expect(descreverPeriodo(lerPeriodo({}, limites))).toBe("Acumulado até setembro de 2026, como na planilha.");
    expect(descreverPeriodo(lerPeriodo({ de: "2026-02", ate: "2026-04", modo: "periodo" }, limites))).toBe(
      "Movimento de fevereiro de 2026 a abril de 2026.",
    );
    expect(descreverPeriodo(lerPeriodo({ de: "2026-04", ate: "2026-04", modo: "periodo" }, limites))).toBe(
      "Movimento de abril de 2026.",
    );
  });

  it("monta o endereço da aba mantendo o período e sem repetir o padrão", () => {
    const periodo = lerPeriodo({ de: "2026-02", ate: "2026-04", modo: "periodo", visao: "mensal" }, limites);
    expect(enderecoEmpresa(idEmpresa, periodo, { aba: "custo" })).toBe(
      `/empresas/${idEmpresa}?aba=custo&de=2026-02&ate=2026-04&modo=periodo&visao=mensal`,
    );
    expect(enderecoEmpresa(idEmpresa, lerPeriodo({}, limites))).toBe(`/empresas/${idEmpresa}?de=2026-01&ate=2026-09`);
  });
});
