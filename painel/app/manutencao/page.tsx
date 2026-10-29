import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { MolduraAcesso } from "@/componentes/MolduraAcesso";
import { manutencaoLigada } from "@/lib/manutencao";
import { mensagens } from "@/lib/mensagens";

export const metadata: Metadata = { title: mensagens.paginas.manutencaoTitulo };

// O proxy reescreve todas as telas para cá com status 503 enquanto MODO_MANUTENCAO=1. Fora da manutenção,
// quem abrir o endereço direto volta para o painel.
export default function PaginaManutencao() {
  if (!manutencaoLigada(process.env.MODO_MANUTENCAO)) redirect("/");
  return (
    <MolduraAcesso>
      <div role="status" className="flex flex-col gap-5">
        <h1 className="font-serif text-[28px] leading-tight font-semibold">{mensagens.paginas.manutencaoTitulo}</h1>
        <p className="leading-relaxed">{mensagens.paginas.manutencao}</p>
      </div>
    </MolduraAcesso>
  );
}
