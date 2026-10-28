"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { abaAtiva, type AbaObra } from "@/lib/abas-obra";

// No celular a faixa rola para o lado em vez de quebrar em várias linhas; em tela média que não comporta
// todas, quebra em vez de esconder abas atrás da rolagem. A aba ativa leva traço e negrito,
// para não depender só da cor.
export function ListaAbasObra({ abas }: { abas: AbaObra[] }) {
  const caminho = usePathname();
  const raiz = abas[0]?.destino ?? "";

  return (
    <nav aria-label="Telas da obra" className="-mx-4 overflow-x-auto border-b border-borda px-4 md:mx-0 md:overflow-visible md:px-0 print:hidden">
      <ul className="flex min-w-max md:min-w-0 md:flex-wrap">
        {abas.map((aba) => {
          const ativa = abaAtiva(caminho, aba.destino, raiz);
          return (
            <li key={aba.destino}>
              <Link
                href={aba.destino}
                aria-current={ativa ? "page" : undefined}
                className={`-mb-px flex min-h-11 items-center border-b-[3px] px-2.5 text-sm whitespace-nowrap ${
                  ativa ? "border-menu font-semibold text-texto" : "border-transparent text-suave hover:text-texto"
                }`}
              >
                {aba.rotulo}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
