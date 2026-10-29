import type { Metadata } from "next";
import Link from "next/link";
import { MolduraAcesso } from "@/componentes/MolduraAcesso";
import { mensagens } from "@/lib/mensagens";

export const metadata: Metadata = { title: mensagens.paginas.naoEncontradaTitulo };

// Endereço que não existe. Fica fora do grupo (painel) porque a rota pode não ter usuário entrado; quem
// estiver entrado volta ao painel pelo link, e o proxy manda para a entrada quem não estiver.
export default function PaginaNaoEncontrada() {
  return (
    <MolduraAcesso>
      <div className="flex flex-col gap-5">
        <h1 className="font-serif text-[28px] leading-tight font-semibold">{mensagens.paginas.naoEncontradaTitulo}</h1>
        <p className="leading-relaxed">{mensagens.paginas.naoEncontrada}</p>
        <Link href="/" className="w-fit text-sm underline underline-offset-4 hover:text-menu">
          Ir para a visão geral
        </Link>
      </div>
    </MolduraAcesso>
  );
}
