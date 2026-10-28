"use client";

import * as Sentry from "@sentry/nextjs";
import Link from "next/link";
import { useEffect } from "react";
import { mensagens } from "@/lib/mensagens";

export type ErroTela = Error & { digest?: string };

// Mostra o código (digest) e nunca a mensagem: em produção o Next troca a mensagem do servidor por uma
// genérica, e a do cliente pode trazer dado da tela. Erro do servidor já chega ao Sentry pelo
// onRequestError; aqui só se registra o que nasceu no navegador, que é o que vem sem digest.
export function AvisoErro({ erro, tentarDeNovo }: { erro: ErroTela; tentarDeNovo: () => void }) {
  useEffect(() => {
    if (!erro.digest) Sentry.captureException(erro);
  }, [erro]);

  return (
    <div role="alert" className="flex flex-col gap-5">
      <h1 className="font-serif text-[28px] leading-tight font-semibold">{mensagens.paginas.erroTitulo}</h1>
      <p className="leading-relaxed">{mensagens.paginas.erro}</p>
      {erro.digest && (
        <p className="text-sm text-suave">
          {mensagens.paginas.erroCodigo} <code className="font-mono text-texto">{erro.digest}</code>
        </p>
      )}
      <div className="flex flex-wrap items-center gap-x-6 gap-y-3">
        <button
          type="button"
          onClick={tentarDeNovo}
          className="min-h-11 cursor-pointer rounded-lg bg-menu px-5 font-semibold text-menu-texto hover:bg-menu-ativo"
        >
          Tentar de novo
        </button>
        <Link href="/" className="text-sm underline underline-offset-4 hover:text-menu">
          Ir para a visão geral
        </Link>
      </div>
    </div>
  );
}
