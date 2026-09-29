import * as Sentry from "@sentry/nextjs";
import "./sentry.client.config";

// Com Turbopack o Next só carrega o código de cliente por este arquivo; sentry.client.config.ts sozinho é ignorado.
export const onRouterTransitionStart = Sentry.captureRouterTransitionStart;
