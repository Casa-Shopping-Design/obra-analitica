import { describe, expect, it } from "vitest";
import { lerDataDigitada, lerFormularioAliquota, lerFormularioEstudo, lerIdObraDigitado } from "../lib/estudo-digitado";
import { linhasDigitaveis, linhasResultado } from "../lib/dre";
import {
  formatarAliquotaDigitada,
  formatarNumeroDigitado,
  lerAliquotaDigitada,
  lerNumeroDigitado,
  tetoValorDigitado,
} from "../lib/numero-digitado";

const idObra = "7a1c3e5f-2b4d-4c6e-8f0a-1b2c3d4e5f60";

describe("valor em real digitado", () => {
  it("lê o formato brasileiro com milhar e centavos", () => {
    expect(lerNumeroDigitado("1.234.567,89")).toBe(1234567.89);
    expect(lerNumeroDigitado("12,5")).toBe(12.5);
    expect(lerNumeroDigitado("1000")).toBe(1000);
    expect(lerNumeroDigitado("1.000")).toBe(1000);
    expect(lerNumeroDigitado("0")).toBe(0);
    expect(lerNumeroDigitado(" R$ 2.500,00 ")).toBe(2500);
  });

  it("recusa letra, sinal negativo e campo vazio", () => {
    expect(lerNumeroDigitado("abc")).toBeNull();
    expect(lerNumeroDigitado("-1")).toBeNull();
    expect(lerNumeroDigitado("")).toBeNull();
    expect(lerNumeroDigitado(null)).toBeNull();
    expect(lerNumeroDigitado(undefined)).toBeNull();
  });

  it("recusa ponto que não é milhar, mais de dois centavos e o que passa do teto", () => {
    expect(lerNumeroDigitado("1.5")).toBeNull();
    expect(lerNumeroDigitado("1.2345")).toBeNull();
    expect(lerNumeroDigitado("1,234")).toBeNull();
    expect(lerNumeroDigitado("99.999.999.999,99")).toBe(tetoValorDigitado);
    expect(lerNumeroDigitado("100.000.000.000,00")).toBeNull();
  });

  it("formata de volta no mesmo formato que aceita", () => {
    expect(formatarNumeroDigitado(1234567.89)).toBe("1.234.567,89");
    expect(formatarNumeroDigitado(0)).toBe("0,00");
    expect(lerNumeroDigitado(formatarNumeroDigitado(987654.3))).toBe(987654.3);
  });
});

describe("alíquota digitada em percentual", () => {
  it("converte o percentual da tela na fração do banco", () => {
    expect(lerAliquotaDigitada("6,32")).toBe(0.0632);
    expect(lerAliquotaDigitada("4")).toBe(0.04);
    expect(lerAliquotaDigitada("0")).toBe(0);
    expect(lerAliquotaDigitada("20")).toBe(0.2);
    expect(lerAliquotaDigitada("6,32%")).toBe(0.0632);
  });

  it("recusa acima de 20%, negativo, letra e vazio", () => {
    expect(lerAliquotaDigitada("25")).toBeNull();
    expect(lerAliquotaDigitada("20,01")).toBeNull();
    expect(lerAliquotaDigitada("-1")).toBeNull();
    expect(lerAliquotaDigitada("abc")).toBeNull();
    expect(lerAliquotaDigitada("")).toBeNull();
  });

  it("formata a fração de volta em percentual sem zero sobrando", () => {
    expect(formatarAliquotaDigitada(0.0632)).toBe("6,32");
    expect(formatarAliquotaDigitada(0.04)).toBe("4");
    expect(formatarAliquotaDigitada(0.123456)).toBe("12,3456");
  });
});

describe("data digitada", () => {
  it("aceita hoje e o passado no formato do input de data", () => {
    expect(lerDataDigitada("2026-10-05", "2026-10-05")).toBe("2026-10-05");
    expect(lerDataDigitada("2025-01-31", "2026-10-05")).toBe("2025-01-31");
  });

  it("recusa futuro, data que não existe e outro formato", () => {
    expect(lerDataDigitada("2026-10-06", "2026-10-05")).toBeNull();
    expect(lerDataDigitada("2026-02-30", "2026-10-05")).toBeNull();
    expect(lerDataDigitada("05/10/2026", "2026-10-05")).toBeNull();
    expect(lerDataDigitada("", "2026-10-05")).toBeNull();
  });
});

describe("formulário do estudo", () => {
  function formulario(campos: Record<string, string>): FormData {
    const dados = new FormData();
    for (const [nome, valor] of Object.entries(campos)) dados.set(nome, valor);
    return dados;
  }

  const completo = Object.fromEntries(linhasDigitaveis.map((linha) => [linha, "0"]));

  it("as onze linhas digitáveis estão entre as dezessete da view", () => {
    expect(linhasDigitaveis).toHaveLength(11);
    for (const linha of linhasDigitaveis) expect(linhasResultado).toContain(linha);
  });

  it("devolve as onze linhas como número, a descrição aparada e a data-base", () => {
    const leitura = lerFormularioEstudo(
      formulario({ ...completo, centro_custo_id: idObra, descricao: "  revisão  ", data_base: "2026-09-30", vgv_bruto: "2.800,00" }),
      "2026-10-05",
    );
    expect(leitura.ok).toBe(true);
    if (!leitura.ok) return;
    expect(leitura.valores).toMatchObject({ centroCustoId: idObra, descricao: "revisão", dataBase: "2026-09-30" });
    expect(leitura.valores.linhas.vgv_bruto).toBe(2800);
    expect(Object.keys(leitura.valores.linhas)).toHaveLength(11);
  });

  it("descrição vazia vira nula e acima de 120 caracteres é recusada", () => {
    const vazia = lerFormularioEstudo(formulario({ ...completo, centro_custo_id: idObra, descricao: "", data_base: "2026-09-30" }), "2026-10-05");
    expect(vazia.ok && vazia.valores.descricao).toBeNull();
    const longa = lerFormularioEstudo(
      formulario({ ...completo, centro_custo_id: idObra, descricao: "x".repeat(121), data_base: "2026-09-30" }),
      "2026-10-05",
    );
    expect(longa).toEqual({ ok: false, motivo: "valor" });
  });

  it("recusa linha ausente, valor negativo e data-base futura", () => {
    const semUmaLinha = Object.fromEntries(Object.entries(completo).filter(([linha]) => linha !== "vgv_bruto"));
    expect(lerFormularioEstudo(formulario({ ...semUmaLinha, centro_custo_id: idObra, data_base: "2026-09-30" }), "2026-10-05")).toEqual({
      ok: false,
      motivo: "valor",
    });
    expect(
      lerFormularioEstudo(formulario({ ...completo, centro_custo_id: idObra, data_base: "2026-09-30", estoque: "-1" }), "2026-10-05"),
    ).toEqual({ ok: false, motivo: "valor" });
    expect(lerFormularioEstudo(formulario({ ...completo, centro_custo_id: idObra, data_base: "2026-10-06" }), "2026-10-05")).toEqual({
      ok: false,
      motivo: "valor",
    });
  });

  it("recusa obra sem id válido antes de olhar os valores", () => {
    expect(lerIdObraDigitado("101")).toBeNull();
    expect(lerFormularioEstudo(formulario({ ...completo, centro_custo_id: "101", data_base: "2026-09-30" }), "2026-10-05")).toEqual({
      ok: false,
      motivo: "obra",
    });
  });

  it("lê a alíquota em percentual e a vigência", () => {
    const leitura = lerFormularioAliquota(formulario({ centro_custo_id: idObra, aliquota: "6,32", vigencia_inicio: "2026-10-01" }), "2026-10-05");
    expect(leitura).toEqual({ ok: true, valores: { centroCustoId: idObra, vigenciaInicio: "2026-10-01", aliquota: 0.0632 } });
    expect(lerFormularioAliquota(formulario({ centro_custo_id: idObra, aliquota: "25", vigencia_inicio: "2026-10-01" }), "2026-10-05")).toEqual({
      ok: false,
      motivo: "valor",
    });
  });
});
