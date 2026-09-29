import * as Sentry from "@sentry/nextjs";
import { coletaDeDados, removerDadosPessoais } from "@/lib/filtro-sentry";

// O DSN do Sentry só permite enviar eventos, por isso pode ir ao navegador. As variáveis
// NEXT_PUBLIC_VERCEL_* são as de sistema que a Vercel expõe ao navegador.
Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  enabled: Boolean(process.env.NEXT_PUBLIC_SENTRY_DSN),
  release: process.env.NEXT_PUBLIC_VERCEL_GIT_COMMIT_SHA,
  environment: process.env.NEXT_PUBLIC_VERCEL_ENV ?? "local",
  tracesSampleRate: 0.2,
  dataCollection: coletaDeDados,
  beforeSend: removerDadosPessoais,
});
