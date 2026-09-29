"use client";

import { useActionState } from "react";
import { cadastrarSegundoFator, type EstadoCadastro } from "@/app/seguranca/segundo-fator/acoes";

const estadoInicial: EstadoCadastro = { fatorId: null, qrCode: null, segredo: null, erro: null };

const classeCampo =
  "min-h-12 rounded-lg border border-borda bg-superficie px-3.5 text-center font-mono text-2xl tracking-[0.4em] text-texto focus-visible:border-texto";
const classeBotao =
  "min-h-12 cursor-pointer rounded-lg bg-menu text-base font-semibold text-menu-texto disabled:cursor-wait disabled:opacity-70";

// Agrupa o segredo de quatro em quatro para quem precisa digitar no aplicativo em vez de ler o QR.
function formatarSegredo(segredo: string): string {
  return segredo.replace(/(.{4})/g, "$1 ").trim();
}

export function CadastroSegundoFator() {
  const [estado, acao, enviando] = useActionState(cadastrarSegundoFator, estadoInicial);

  if (!estado.qrCode || !estado.segredo) {
    return (
      <form action={acao} className="flex flex-col gap-4.5">
        <input type="hidden" name="etapa" value="iniciar" />
        {estado.erro && (
          <p role="alert" className="rounded-lg border border-alerta px-3.5 py-2.5 text-sm text-alerta">
            {estado.erro}
          </p>
        )}
        <button type="submit" disabled={enviando} className={classeBotao}>
          {enviando ? "Gerando o código..." : "Gerar código QR"}
        </button>
      </form>
    );
  }

  return (
    <form action={acao} className="flex flex-col gap-5" noValidate>
      <input type="hidden" name="etapa" value="confirmar" />
      <ol className="flex flex-col gap-5 text-[15px] leading-relaxed">
        <li className="flex flex-col gap-3">
          <span>
            <span className="font-semibold">1.</span> No aplicativo, escolha adicionar conta e aponte a câmera para o
            código abaixo.
          </span>
          {/* O QR chega do Auth como SVG em data URI; a CSP libera img-src data: para isso. */}
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={estado.qrCode}
            alt="Código QR para cadastrar o Obra Analítica no aplicativo autenticador"
            width={200}
            height={200}
            className="self-center rounded-lg border border-borda bg-superficie p-2"
          />
          <details className="text-sm text-suave">
            <summary className="cursor-pointer underline underline-offset-4">Não consegue ler o código? Digite a chave</summary>
            <p className="mt-2">
              Chave para digitação manual:{" "}
              <code className="font-mono text-base tracking-wider break-all text-texto">{formatarSegredo(estado.segredo)}</code>
            </p>
          </details>
        </li>
        <li className="flex flex-col gap-1.5">
          <label htmlFor="codigo">
            <span className="font-semibold">2.</span> Digite os seis dígitos que o aplicativo mostrar.
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
            aria-describedby={estado.erro ? "erro-cadastro" : undefined}
            className={classeCampo}
          />
        </li>
      </ol>
      {estado.erro && (
        <p id="erro-cadastro" role="alert" className="rounded-lg border border-alerta px-3.5 py-2.5 text-sm text-alerta">
          {estado.erro}
        </p>
      )}
      <button type="submit" disabled={enviando} className={classeBotao}>
        {enviando ? "Confirmando..." : "Confirmar e entrar"}
      </button>
    </form>
  );
}
