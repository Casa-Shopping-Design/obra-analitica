"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { MarcaApo } from "@/componentes/MarcaApo";

const itens = [
  { rotulo: "Visão geral", destino: "/" },
  { rotulo: "Obras", destino: "/obras" },
  { rotulo: "Mapa de unidades", destino: "/unidades" },
  { rotulo: "Assistente", destino: "/assistente" },
];

function estaAtivo(caminho: string, destino: string): boolean {
  return destino === "/" ? caminho === "/" : caminho === destino || caminho.startsWith(`${destino}/`);
}

const classeFoco = "focus-visible:outline-menu-texto";

export function MenuLateral({ perfil, construtora }: { perfil: string; construtora: string }) {
  const caminho = usePathname();

  return (
    <nav
      aria-label="Menu principal"
      className="flex flex-col gap-1.5 bg-menu px-4 py-5 print:hidden text-menu-texto md:sticky md:top-0 md:h-screen md:w-[220px] md:shrink-0 md:px-5 md:py-8"
    >
      <MarcaApo className="px-3 pb-3 text-[22px] md:pb-7" />
      <ul className="flex flex-wrap gap-1.5 md:flex-col">
        {itens.map((item) => {
          const ativo = estaAtivo(caminho, item.destino);
          return (
            <li key={item.destino}>
              <Link
                href={item.destino}
                aria-current={ativo ? "page" : undefined}
                className={`flex min-h-11 items-center rounded-lg px-3 ${classeFoco} ${
                  ativo ? "bg-menu-ativo font-semibold" : "text-menu-suave hover:text-menu-texto"
                }`}
              >
                {item.rotulo}
              </Link>
            </li>
          );
        })}
      </ul>
      <div className="hidden flex-1 md:block" />
      <p className="px-3 pt-3 text-[13px] leading-normal text-menu-suave">
        {perfil}
        {construtora && (
          <>
            <br />
            {construtora}
          </>
        )}
      </p>
      <form action="/sair" method="post">
        <button
          type="submit"
          className={`flex min-h-11 w-full cursor-pointer items-center rounded-lg px-3 text-menu-suave hover:text-menu-texto ${classeFoco}`}
        >
          Sair
        </button>
      </form>
    </nav>
  );
}
