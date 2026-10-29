import { describe, expect, it } from "vitest";
import { decidirManutencao, manutencaoLigada } from "../lib/manutencao";

describe("manutencaoLigada", () => {
  it("liga só com 1", () => {
    expect(manutencaoLigada("1")).toBe(true);
    for (const valor of [undefined, "", "0", "true", "sim", " 1"]) {
      expect(manutencaoLigada(valor), String(valor)).toBe(false);
    }
  });
});

describe("decidirManutencao", () => {
  it("desligada, tudo segue", () => {
    for (const caminho of ["/", "/obras/1", "/entrar", "/api/assistente"]) {
      expect(decidirManutencao(caminho, false)).toBe("seguir");
    }
  });

  it("ligada, tela vira a página de manutenção e rota de API responde 503 em JSON", () => {
    expect(decidirManutencao("/", true)).toBe("pagina");
    expect(decidirManutencao("/entrar", true)).toBe("pagina");
    expect(decidirManutencao("/obras/1/dre", true)).toBe("pagina");
    expect(decidirManutencao("/api/assistente", true)).toBe("api");
    expect(decidirManutencao("/api/origem/erp", true)).toBe("api");
  });

  it("ligada, a própria página e a saúde continuam respondendo", () => {
    expect(decidirManutencao("/manutencao", true)).toBe("seguir");
    expect(decidirManutencao("/api/saude", true)).toBe("seguir");
  });
});
