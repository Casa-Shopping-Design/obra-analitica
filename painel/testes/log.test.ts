import { describe, expect, expectTypeOf, it, vi } from "vitest";
import type { CamposLog } from "../lib/log";

const linhas: unknown[] = [];
vi.mock("pino", () => ({
  default: Object.assign(
    () => ({ info: (campos: unknown) => linhas.push(campos), warn: () => {}, error: () => {} }),
    { stdTimeFunctions: { isoTime: () => "" } },
  ),
}));

describe("campos do log", () => {
  // Falha na checagem de tipos se alguém abrir campo para a pergunta, o SQL ou o e-mail.
  it("não tem campo para pergunta, SQL, e-mail ou token", () => {
    expectTypeOf<CamposLog>().not.toHaveProperty("pergunta");
    expectTypeOf<CamposLog>().not.toHaveProperty("sql");
    expectTypeOf<CamposLog>().not.toHaveProperty("sql_gerado");
    expectTypeOf<CamposLog>().not.toHaveProperty("email");
    expectTypeOf<CamposLog>().not.toHaveProperty("token");
  });

  it("grava id da requisição, rota e resultado, com usuário e tenant nulos quando não informados", async () => {
    const { registrar } = await import("../lib/log");
    registrar("info", "teste", { id_requisicao: "abc", rota: "/api/saude", resultado: "ok" });
    expect(linhas[0]).toMatchObject({ id_requisicao: "abc", rota: "/api/saude", resultado: "ok", user_id: null, tenant_id: null });
  });
});
