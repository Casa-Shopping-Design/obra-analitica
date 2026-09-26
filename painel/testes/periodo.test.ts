import { describe, expect, it } from "vitest";
import {
  calcularPeriodo,
  hojeEmSaoPaulo,
  horaEmSaoPaulo,
  lerData,
  lerIdCentro,
  lerMes,
  lerOpcao,
  lerPeriodo,
  mesDaData,
  mesPorExtenso,
  mesesDoFiltro,
  montarEndereco,
  proximoMes,
  somarMeses,
  tiposPeriodo,
} from "../lib/periodo";

describe("proximoMes", () => {
  it("é o mês-calendário seguinte ao da data de referência", () => {
    expect(proximoMes("2026-09-26")).toBe("2026-10-01");
    expect(proximoMes("2026-09-01")).toBe("2026-10-01");
    expect(proximoMes("2026-09-30")).toBe("2026-10-01");
  });

  it("vira de dezembro para janeiro do ano seguinte", () => {
    expect(proximoMes("2026-12-15")).toBe("2027-01-01");
    expect(proximoMes("2026-12-31")).toBe("2027-01-01");
  });

  it("aparece por extenso com o ano", () => {
    expect(mesPorExtenso(proximoMes("2026-12-15"))).toBe("janeiro de 2027");
    expect(mesPorExtenso("2026-03-01")).toBe("março de 2026");
  });
});

describe("somarMeses e mesDaData", () => {
  it("atravessa a virada do ano nos dois sentidos", () => {
    expect(somarMeses("2026-01-01", -1)).toBe("2025-12-01");
    expect(somarMeses("2026-09-26", -11)).toBe("2025-10-01");
    expect(somarMeses("2026-11-01", 14)).toBe("2028-01-01");
  });

  it("leva qualquer dia para o primeiro do mês", () => {
    expect(mesDaData("2026-09-26")).toBe("2026-09-01");
  });
});

describe("calcularPeriodo", () => {
  const referencia = "2026-09-26";

  it("mês é só o mês escolhido", () => {
    expect(calcularPeriodo("mes", "2026-08-01", referencia)).toMatchObject({
      inicio: "2026-08-01",
      fim: "2026-08-01",
      rotulo: "agosto de 2026",
    });
  });

  it("trimestre fecha no mês de referência quando ele está no meio do trimestre", () => {
    expect(calcularPeriodo("trimestre", "2026-08-01", referencia)).toMatchObject({
      inicio: "2026-07-01",
      fim: "2026-09-01",
    });
    expect(calcularPeriodo("trimestre", "2026-09-01", "2026-08-10")).toMatchObject({
      inicio: "2026-07-01",
      fim: "2026-08-01",
    });
    expect(calcularPeriodo("trimestre", "2025-11-01", referencia).rotulo).toBe(
      "4º trimestre de 2025 (out/25 a dez/25)",
    );
  });

  it("ano vai de janeiro até o mês escolhido", () => {
    expect(calcularPeriodo("ano", referencia, referencia)).toMatchObject({
      inicio: "2026-01-01",
      fim: "2026-09-01",
      rotulo: "janeiro a setembro de 2026",
    });
    expect(calcularPeriodo("ano", "2026-01-01", referencia).rotulo).toBe("janeiro de 2026");
  });

  it("últimos 12 meses atravessam o ano", () => {
    expect(calcularPeriodo("doze_meses", referencia, referencia)).toMatchObject({
      inicio: "2025-10-01",
      fim: "2026-09-01",
      rotulo: "out/25 a set/26",
    });
  });

  it("mês depois da referência volta para o mês da referência", () => {
    expect(calcularPeriodo("mes", "2027-02-01", referencia).fim).toBe("2026-09-01");
  });
});

describe("filtros lidos da URL", () => {
  const referencia = "2026-09-26";

  it("aceita só opção da lista", () => {
    expect(lerOpcao("trimestre", tiposPeriodo, "ano")).toBe("trimestre");
    expect(lerOpcao("semestre", tiposPeriodo, "ano")).toBe("ano");
    expect(lerOpcao(["mes", "ano"], tiposPeriodo, "ano")).toBe("mes");
    expect(lerOpcao(undefined, tiposPeriodo, "ano")).toBe("ano");
  });

  it("mês fora do formato, no futuro ou antigo demais cai no mês de referência", () => {
    expect(lerMes("2026-07", referencia)).toBe("2026-07-01");
    expect(lerMes("2026-13", referencia)).toBe("2026-09-01");
    expect(lerMes("2026-10", referencia)).toBe("2026-09-01");
    expect(lerMes("1999-01", referencia)).toBe("2026-09-01");
    expect(lerMes("2026-07'; drop", referencia)).toBe("2026-09-01");
  });

  it("monta o período padrão sem parâmetros", () => {
    expect(lerPeriodo({}, referencia)).toMatchObject({ tipo: "ano", inicio: "2026-01-01", fim: "2026-09-01" });
    expect(lerPeriodo({ periodo: "mes", mes: "2026-05" }, referencia)).toMatchObject({
      inicio: "2026-05-01",
      fim: "2026-05-01",
    });
  });

  it("oferece os meses do mais recente para o mais antigo", () => {
    const meses = mesesDoFiltro(referencia, 3);
    expect(meses.map((mes) => mes.valor)).toEqual(["2026-09", "2026-08", "2026-07"]);
    expect(meses[0].rotulo).toBe("setembro de 2026");
  });

  it("aceita só data real no formato ISO", () => {
    expect(lerData("2026-02-28")).toBe("2026-02-28");
    expect(lerData("2026-02-30")).toBeNull();
    expect(lerData("28/02/2026")).toBeNull();
    expect(lerData(undefined)).toBeNull();
  });

  it("obra fora do formato de UUID vira consolidado", () => {
    expect(lerIdCentro("4C22F713-0217-4230-BF04-8581B4BF6A7B")).toBe("4c22f713-0217-4230-bf04-8581b4bf6a7b");
    expect(lerIdCentro("1 or 1=1")).toBeNull();
    expect(lerIdCentro("")).toBeNull();
  });

  it("monta o endereço sem os filtros vazios", () => {
    expect(montarEndereco("/receitas", { obra: null, periodo: "mes", pagina: 2, origem: "" })).toBe(
      "/receitas?periodo=mes&pagina=2",
    );
    expect(montarEndereco("/dre", {})).toBe("/dre");
  });
});

describe("fuso de Brasília", () => {
  it("usa a data de Brasília perto da meia-noite UTC", () => {
    expect(hojeEmSaoPaulo(new Date("2026-10-01T02:00:00Z"))).toBe("2026-09-30");
  });

  it("mostra a hora da carga no fuso de Brasília", () => {
    expect(horaEmSaoPaulo("2026-09-26T06:10:00Z")).toBe("03:10");
  });
});
