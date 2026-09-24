"use client";

import { usePathname, useRouter } from "next/navigation";
import { useOptimistic, useTransition } from "react";

const opcoes = [
  { meses: 0, rotulo: "Sem atraso" },
  { meses: 1, rotulo: "1 mês" },
  { meses: 3, rotulo: "3 meses" },
  { meses: 6, rotulo: "6 meses" },
];

// O cenário vai na URL e a página refaz a consulta no servidor, com o token de quem está vendo.
export function SeletorCenario({ mesesAtraso }: { mesesAtraso: number }) {
  const roteador = useRouter();
  const caminho = usePathname();
  const [atualizando, iniciarTransicao] = useTransition();
  // Marca a opção na hora do clique; o valor real volta da página quando o servidor responde.
  const [mesesMarcados, marcarMeses] = useOptimistic(mesesAtraso);

  function escolher(meses: number) {
    const destino = meses === 0 ? caminho : `${caminho}?cenario=${meses}`;
    iniciarTransicao(() => {
      marcarMeses(meses);
      roteador.replace(destino, { scroll: false });
    });
  }

  return (
    <fieldset className="flex flex-col gap-2" aria-busy={atualizando}>
      <legend className="text-sm font-medium">Atraso do repasse do banco</legend>
      <div className="flex flex-wrap gap-2">
        {opcoes.map((opcao) => (
          <label
            key={opcao.meses}
            className="flex min-h-11 cursor-pointer items-center gap-2 rounded-lg border border-borda bg-superficie px-3 has-checked:border-menu has-checked:bg-menu has-checked:text-menu-texto has-focus-visible:outline-3 has-focus-visible:outline-texto"
          >
            <input
              type="radio"
              name="cenario"
              value={opcao.meses}
              checked={mesesMarcados === opcao.meses}
              onChange={() => escolher(opcao.meses)}
              className="sr-only"
            />
            {opcao.rotulo}
          </label>
        ))}
      </div>
      <p aria-live="polite" className="min-h-5 text-sm text-suave">
        {atualizando ? "Recalculando o fluxo com o novo cenário..." : ""}
      </p>
    </fieldset>
  );
}
