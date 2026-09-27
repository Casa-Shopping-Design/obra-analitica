// Libera só o host de envio do projeto no Sentry (ex.: https://o123.ingest.us.sentry.io), não o domínio todo.
export function origemDoDsn(dsn: string | undefined): string {
  if (!dsn) return "";
  try {
    return new URL(dsn).origin;
  } catch {
    return "";
  }
}

// Script só com o nonce da requisição; estilo inline só em desenvolvimento, onde o Next injeta CSS por script.
export function montarPoliticaConteudo(nonce: string): string {
  const emDesenvolvimento = process.env.NODE_ENV === "development";
  const urlSupabase = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
  const origemSentry = origemDoDsn(process.env.NEXT_PUBLIC_SENTRY_DSN);

  const diretivas = [
    "default-src 'self'",
    `script-src 'self' 'nonce-${nonce}' 'strict-dynamic'${emDesenvolvimento ? " 'unsafe-eval'" : ""}`,
    `style-src 'self' ${emDesenvolvimento ? "'unsafe-inline'" : `'nonce-${nonce}'`}`,
    "img-src 'self' blob: data:",
    "font-src 'self'",
    `connect-src 'self' ${urlSupabase} ${origemSentry}`.replace(/\s+/g, " ").trim(),
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
  ];
  if (!emDesenvolvimento) diretivas.push("upgrade-insecure-requests");
  return diretivas.join("; ");
}
