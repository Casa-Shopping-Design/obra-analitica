import * as Sentry from "@sentry/nextjs";
import type { Instrumentation } from "next";

export async function register() {
  if (process.env.NEXT_RUNTIME === "nodejs" || process.env.NEXT_RUNTIME === "edge") {
    await import("./sentry.server.config");
  }
}

// Erro de Server Component, Route Handler e Server Action chega aqui. A etiqueta id_requisicao liga o
// evento do Sentry ao log da Vercel e ao que o usuário viu na tela.
export const onRequestError: Instrumentation.onRequestError = (erro, requisicao, contexto) => {
  const cabecalho = requisicao.headers["x-id-requisicao"];
  Sentry.withScope((escopo) => {
    escopo.setTag("id_requisicao", Array.isArray(cabecalho) ? cabecalho[0] : (cabecalho ?? "ausente"));
    Sentry.captureRequestError(erro, requisicao, contexto);
  });
};
