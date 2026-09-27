import { describe, expect, it } from "vitest";
import type { ErrorEvent } from "@sentry/nextjs";
import { limparEvento } from "../lib/sentry/opcoes";
import { montarPoliticaConteudo, origemDoDsn } from "../lib/politica-conteudo";

describe("limparEvento", () => {
  it("mantém só o id do usuário e tira cookie, cabeçalho, corpo e parâmetros da requisição", () => {
    const evento = {
      type: undefined,
      user: { id: "0a000000-0000-4000-8000-000000000001", email: "pessoa@exemplo.invalid", ip_address: "10.0.0.1" },
      request: {
        url: "https://painel.exemplo.invalid/dre",
        cookies: { "sb-access-token": "segredo" },
        headers: { authorization: "Bearer segredo" },
        data: "corpo",
        query_string: "obra=1",
      },
    } as unknown as ErrorEvent;

    const limpo = limparEvento(evento);

    expect(limpo.user).toEqual({ id: "0a000000-0000-4000-8000-000000000001" });
    expect(limpo.request).toEqual({ url: "https://painel.exemplo.invalid/dre" });
  });

  it("descarta o usuário quando não há id", () => {
    const evento = { type: undefined, user: { email: "pessoa@exemplo.invalid" } } as unknown as ErrorEvent;
    expect(limparEvento(evento).user).toBeUndefined();
  });
});

describe("origem do Sentry na política de conteúdo", () => {
  it("libera só o host de envio do projeto", () => {
    expect(origemDoDsn("https://chavepublica@o1.ingest.us.sentry.io/2")).toBe("https://o1.ingest.us.sentry.io");
  });

  it("sem DSN ou com DSN inválido não libera nada", () => {
    expect(origemDoDsn(undefined)).toBe("");
    expect(origemDoDsn("nao e url")).toBe("");
  });

  it("entra no connect-src junto com o Supabase", () => {
    const antes = process.env.NEXT_PUBLIC_SENTRY_DSN;
    process.env.NEXT_PUBLIC_SENTRY_DSN = "https://chavepublica@o1.ingest.us.sentry.io/2";
    const politica = montarPoliticaConteudo("nonce");
    process.env.NEXT_PUBLIC_SENTRY_DSN = antes;
    expect(politica).toMatch(/connect-src 'self'[^;]* https:\/\/o1\.ingest\.us\.sentry\.io/);
  });
});
