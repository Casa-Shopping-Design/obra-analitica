"use client";

import * as Sentry from "@sentry/nextjs";
import Link from "next/link";
import { useEffect } from "react";

// Último recurso quando até o layout falha: registra o erro e mostra uma saída, sem detalhe técnico.
export default function ErroGlobal({ error }: { error: Error & { digest?: string } }) {
  useEffect(() => {
    Sentry.captureException(error);
  }, [error]);

  return (
    <html lang="pt-BR">
      <body>
        <main style={{ padding: 32, fontFamily: "sans-serif" }}>
          <h1>Não foi possível abrir o painel</h1>
          <p>Tente recarregar a página. Se o problema continuar, avise o suporte informando o horário.</p>
          <Link href="/">Voltar ao início</Link>
        </main>
      </body>
    </html>
  );
}
