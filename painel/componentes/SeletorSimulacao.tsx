"use client";

import { usePathname, useRouter } from "next/navigation";
import { useOptimistic, useTransition } from "react";
import { opcoesDesconto, opcoesRitmo, type DescontoPercentual, type Ritmo } from "@/lib/simulacao";

const classeOpcao =
  "flex min-h-11 cursor-pointer items-center gap-2 rounded-lg border border-borda bg-superficie px-3 has-checked:border-menu has-checked:bg-menu has-checked:text-menu-texto has-focus-visible:outline-3 has-focus-visible:outline-texto";

function Grupo<T extends number>({
  legenda,
  nome,
  opcoes,
  marcado,
  rotulo,
  escolher,
}: {
  legenda: string;
  nome: string;
  opcoes: readonly T[];
  marcado: T;
  rotulo: (opcao: T) => string;
  escolher: (opcao: T) => void;
}) {
  return (
    <fieldset className="flex flex-col gap-2">
      <legend className="text-sm font-medium">{legenda}</legend>
      <div className="flex flex-wrap gap-2">
        {opcoes.map((opcao) => (
          <label key={opcao} className={classeOpcao}>
            <input
              type="radio"
              name={nome}
              value={opcao}
              checked={marcado === opcao}
              onChange={() => escolher(opcao)}
              className="sr-only"
            />
            {rotulo(opcao)}
          </label>
        ))}
      </div>
    </fieldset>
  );
}

// Ritmo e desconto vão na URL e a página refaz a simulação no servidor, com o token de quem está vendo.
export function SeletorSimulacao({ ritmo, desconto }: { ritmo: Ritmo; desconto: DescontoPercentual }) {
  const roteador = useRouter();
  const caminho = usePathname();
  const [atualizando, iniciarTransicao] = useTransition();
  const [marcados, marcar] = useOptimistic({ ritmo, desconto });

  function aplicar(novo: { ritmo: Ritmo; desconto: DescontoPercentual }) {
    iniciarTransicao(() => {
      marcar(novo);
      roteador.replace(`${caminho}?ritmo=${novo.ritmo}&desconto=${novo.desconto}`, { scroll: false });
    });
  }

  return (
    <div className="flex flex-col gap-4" aria-busy={atualizando}>
      <div className="flex flex-wrap gap-x-10 gap-y-4">
        <Grupo
          legenda="Unidades vendidas por mês"
          nome="ritmo"
          opcoes={opcoesRitmo}
          marcado={marcados.ritmo}
          rotulo={(opcao) => String(opcao)}
          escolher={(opcao) => aplicar({ ritmo: opcao, desconto: marcados.desconto })}
        />
        <Grupo
          legenda="Desconto sobre a tabela"
          nome="desconto"
          opcoes={opcoesDesconto}
          marcado={marcados.desconto}
          rotulo={(opcao) => (opcao === 0 ? "Sem desconto" : `${opcao}%`)}
          escolher={(opcao) => aplicar({ ritmo: marcados.ritmo, desconto: opcao })}
        />
      </div>
      <p aria-live="polite" className="min-h-5 text-sm text-suave">
        {atualizando ? "Recalculando a simulação..." : ""}
      </p>
    </div>
  );
}
