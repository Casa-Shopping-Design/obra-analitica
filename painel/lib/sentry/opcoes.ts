import type { ErrorEvent } from "@sentry/nextjs";

// Sem DSN (ambiente local, testes) o Sentry fica desligado e nada sai da máquina.
const dsn = process.env.NEXT_PUBLIC_SENTRY_DSN;

// Plano 4.2: sem dado pessoal, sem token. O usuário vai só pelo id (UUID); cookie, cabeçalho,
// e-mail, IP e corpo da requisição nunca saem para o Sentry.
export function limparEvento(evento: ErrorEvent): ErrorEvent {
  if (evento.user) evento.user = evento.user.id ? { id: evento.user.id } : undefined;
  if (evento.request) {
    delete evento.request.cookies;
    delete evento.request.headers;
    delete evento.request.data;
    delete evento.request.query_string;
  }
  return evento;
}

export const opcoesSentry = {
  dsn,
  enabled: Boolean(dsn),
  environment: process.env.NEXT_PUBLIC_VERCEL_ENV ?? process.env.NODE_ENV,
  tracesSampleRate: 0.2,
  sendDefaultPii: false,
  beforeSend: limparEvento,
};
