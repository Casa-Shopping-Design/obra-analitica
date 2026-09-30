"use client";

import { useId, useState } from "react";
import { explicacoes, type ChaveExplicacao } from "@/lib/explicacoes";

// O title cobre quem passa o mouse; o botão abre o texto para toque e teclado. Esc ou sair do foco fecha.
export function ExplicacaoIndicador({
  chave,
  rotulo,
  alinhamento = "esquerda",
}: {
  chave: ChaveExplicacao;
  rotulo: string;
  alinhamento?: "esquerda" | "direita";
}) {
  const [aberta, setAberta] = useState(false);
  const idTexto = useId();
  const texto = explicacoes[chave];

  return (
    <span className="relative inline-flex align-middle print:hidden">
      <button
        type="button"
        title={texto}
        aria-label={`O que é ${rotulo}`}
        aria-expanded={aberta}
        aria-controls={idTexto}
        onClick={() => setAberta((valor) => !valor)}
        onBlur={() => setAberta(false)}
        onKeyDown={(evento) => {
          if (evento.key === "Escape") setAberta(false);
        }}
        className="inline-flex size-6 cursor-help items-center justify-center rounded-full border border-borda text-xs font-semibold text-suave hover:text-texto"
      >
        ?
      </button>
      <span
        id={idTexto}
        role="tooltip"
        hidden={!aberta}
        className={`absolute top-7 z-20 ${alinhamento === "direita" ? "right-0" : "left-0"} w-64 rounded-lg border border-borda bg-superficie p-3 text-left text-sm leading-snug font-normal text-texto shadow-md`}
      >
        {texto}
      </span>
    </span>
  );
}
