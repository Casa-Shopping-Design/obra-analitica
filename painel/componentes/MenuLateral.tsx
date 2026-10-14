"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { MarcaApo } from "@/componentes/MarcaApo";
import { itemAtivo, itensMenu } from "@/lib/menu";

const classeFoco = "focus-visible:outline-menu-texto";

// perfil é o nome mostrado; codigoPerfil é o valor cru que decide os itens.
export function MenuLateral({
  perfil,
  codigoPerfil,
  construtora,
}: {
  perfil: string;
  codigoPerfil: string | null;
  construtora: string;
}) {
  const caminho = usePathname();

  return (
    <nav
      aria-label="Menu principal"
      className="flex flex-col gap-1.5 bg-menu px-4 py-5 print:hidden text-menu-texto md:sticky md:top-0 md:h-screen md:w-[220px] md:shrink-0 md:px-5 md:py-8"
    >
      <MarcaApo className="px-3 pb-3 text-[22px] md:pb-7" />
      <ul className="flex flex-wrap gap-1.5 md:flex-col">
        {itensMenu(codigoPerfil).map((item) => {
          const ativo = itemAtivo(caminho, item.destino);
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
