import type { ErrorEvent } from "@sentry/nextjs";
import { describe, expect, it } from "vitest";
import { removerDadosPessoais } from "../lib/filtro-sentry";

describe("filtro do Sentry", () => {
  it("apaga e-mail, nome, IP, cookie e token, e mantém o UUID e o id da requisição", () => {
    const evento: ErrorEvent = {
      type: undefined,
      user: { id: "0a000000-0000-4000-8000-00000000d001", email: "diretor@teste.invalid", username: "Diretor", ip_address: "10.0.0.1" },
      request: {
        url: "https://painel.teste.invalid/obras",
        cookies: { "sb-access-token": "segredo" },
        headers: { Cookie: "sb=segredo", Authorization: "Bearer segredo", "x-id-requisicao": "abc" },
      },
    };

    const filtrado = removerDadosPessoais(evento);

    expect(filtrado.user).toEqual({ id: "0a000000-0000-4000-8000-00000000d001" });
    expect(filtrado.request?.cookies).toBeUndefined();
    expect(filtrado.request?.headers).toEqual({ "x-id-requisicao": "abc" });
  });

  it("aceita evento sem usuário nem requisição", () => {
    const evento: ErrorEvent = { type: undefined, message: "falha" };
    expect(removerDadosPessoais(evento)).toEqual({ type: undefined, message: "falha" });
  });
});
