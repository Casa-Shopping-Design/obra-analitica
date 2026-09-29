"use client";

import { useActionState } from "react";
import { verificarSegundoFator, type EstadoVerificacao } from "@/app/seguranca/segundo-fator/acoes";

const estadoInicial: EstadoVerificacao = { erro: null };

const classeCampo =
  "min-h-12 rounded-lg border border-borda bg-superficie px-3.5 text-center font-mono text-2xl tracking-[0.4em] text-texto focus-visible:border-texto";

export function VerificacaoSegundoFator() {
  const [estado, acao, enviando] = useActionState(verificarSegundoFator, estadoInicial);

  return (
    <form action={acao} className="flex flex-col gap-4.5" noValidate>
      <div className="flex flex-col gap-1.5">
        <label htmlFor="codigo" className="text-sm font-medium">
          Código do aplicativo
        </label>
        <input
          id="codigo"
          name="codigo"
          type="text"
          inputMode="numeric"
          autoComplete="one-time-code"
          pattern="[0-9]{6}"
          maxLength={7}
          required
          autoFocus
          aria-invalid={estado.erro ? true : undefined}
          aria-describedby={estado.erro ? "erro-verificacao" : "ajuda-verificacao"}
          className={classeCampo}
        />
        <p id="ajuda-verificacao" className="text-sm text-suave">
          O código muda a cada 30 segundos. Perdeu o celular? Peça ao administrador da construtora para remover o
          aparelho antigo.
        </p>
      </div>
      {estado.erro && (
        <p id="erro-verificacao" role="alert" className="rounded-lg border border-alerta px-3.5 py-2.5 text-sm text-alerta">
          {estado.erro}
        </p>
      )}
      <button
        type="submit"
        disabled={enviando}
        className="min-h-12 cursor-pointer rounded-lg bg-menu text-base font-semibold text-menu-texto disabled:cursor-wait disabled:opacity-70"
      >
        {enviando ? "Confirmando..." : "Confirmar"}
      </button>
    </form>
  );
}
