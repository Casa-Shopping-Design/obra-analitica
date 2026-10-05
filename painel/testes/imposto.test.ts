import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { explicacoes } from "../lib/explicacoes";
import { avisoEstimativa, colunasImposto, formatarAliquota, lerImpostoObra, notaImposto } from "../lib/imposto";
import { mensagens } from "../lib/mensagens";

// Linha da Obra Norte do teste pgTAP supabase/tests/imposto_obra.sql, como a API devolve (numeric vem em texto).
const linhaNorte = {
  obra: "Obra Norte",
  competencia: "2026-09-01",
  aliquota: "0.040000",
  aliquota_vigencia_inicio: "2026-07-01",
  aliquota_informada_em: "2026-10-05T13:00:00+00:00",
  vgv_total: "3000.00",
  receita_apropriada: "1000.00",
  receita_a_apropriar: "1000.00",
  vgv_estoque: "1000.00",
  recebido_acumulado: "600.00",
  imposto_receita_apropriada: "40.00",
  imposto_recebimento: "24.00",
  imposto_diferido: "-16.00",
  imposto_vgv_estoque: "40.00",
  imposto_receita_a_apropriar: "40.00",
  imposto_vgv_total: "120.00",
  imposto_a_realizar: "80.00",
  imposto_viabilidade: "112.00",
};

describe("lerImpostoObra", () => {
  it("converte a linha da view sem refazer conta", () => {
    expect(lerImpostoObra(linhaNorte)).toEqual({
      obra: "Obra Norte",
      competencia: "2026-09-01",
      aliquota: 0.04,
      aliquotaVigenciaInicio: "2026-07-01",
      aliquotaInformadaEm: "2026-10-05T13:00:00+00:00",
      vgvTotal: 3000,
      receitaApropriada: 1000,
      receitaAApropriar: 1000,
      vgvEstoque: 1000,
      recebidoAcumulado: 600,
      impostoReceitaApropriada: 40,
      impostoRecebimento: 24,
      impostoDiferido: -16,
      impostoVgvEstoque: 40,
      impostoReceitaAApropriar: 40,
      impostoVgvTotal: 120,
      impostoARealizar: 80,
      impostoViabilidade: 112,
    });
  });

  it("deixa o imposto do estudo nulo quando o estudo não tem a linha", () => {
    expect(lerImpostoObra({ ...linhaNorte, imposto_viabilidade: null }).impostoViabilidade).toBeNull();
  });

  it("pede só colunas que existem na view da migration 0034", () => {
    const migration = readFileSync(
      join(__dirname, "..", "..", "supabase", "migrations", "0034_imposto_obra.sql"),
      "utf8",
    );
    for (const coluna of colunasImposto.split(", ")) {
      expect(migration, coluna).toMatch(new RegExp(`\\b${coluna}\\b`));
    }
  });
});

describe("textos da gestão de imposto", () => {
  it("mostra a alíquota com duas casas, como o deck", () => {
    expect(formatarAliquota(0.0632)).toBe("6,32%");
    expect(formatarAliquota(0.04)).toBe("4,00%");
    expect(formatarAliquota(0.039875)).toBe("3,9875%");
  });

  it("diz a alíquota, desde quando vale e quando foi informada", () => {
    expect(notaImposto(lerImpostoObra(linhaNorte))).toBe(
      "Alíquota de 4,00%, vigente desde 01/07/2026 e informada em 05/10/2026.",
    );
  });

  it("avisa que o valor é estimativa", () => {
    expect(avisoEstimativa).toBe("Valores estimados pela alíquota informada. Não substituem a apuração do contador.");
  });

  it("tem explicação para os nove cartões e mensagem para cada situação da tela", () => {
    for (const chave of [
      "vgv_total_imposto",
      "imposto_receita_apropriada",
      "imposto_recebimento",
      "imposto_diferido",
      "imposto_vgv_estoque",
      "imposto_receita_a_apropriar",
      "imposto_vgv_total",
      "imposto_a_realizar",
      "aliquota_imposto",
    ]) {
      expect(explicacoes).toHaveProperty(chave);
    }
    for (const texto of Object.values(mensagens.imposto)) {
      expect(texto).not.toMatch(/imposto_obra|marts|select/i);
    }
  });
});
