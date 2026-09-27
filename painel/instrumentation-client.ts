import * as Sentry from "@sentry/nextjs";
import { opcoesSentry } from "@/lib/sentry/opcoes";

// Sem gravação de sessão (replay): as telas mostram números financeiros de clientes.
Sentry.init(opcoesSentry);

export const onRouterTransitionStart = Sentry.captureRouterTransitionStart;
