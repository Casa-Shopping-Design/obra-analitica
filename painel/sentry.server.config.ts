import * as Sentry from "@sentry/nextjs";
import { coletaDeDados, removerDadosPessoais } from "@/lib/filtro-sentry";

// Vale para os runtimes Node.js e Edge; o pacote escolhe a implementação de cada um.
// Sem SENTRY_DSN (desenvolvimento, CI) o SDK não envia nada.
Sentry.init({
  dsn: process.env.SENTRY_DSN,
  enabled: Boolean(process.env.SENTRY_DSN),
  release: process.env.VERCEL_GIT_COMMIT_SHA,
  environment: process.env.VERCEL_ENV ?? "local",
  tracesSampleRate: 0.2,
  dataCollection: coletaDeDados,
  beforeSend: removerDadosPessoais,
});
