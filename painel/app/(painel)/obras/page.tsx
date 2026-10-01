import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { BotaoImprimir } from "@/componentes/BotaoImprimir";
import { TabelaComparativo } from "@/componentes/TabelaComparativo";
import type { LinhaComparativo } from "@/lib/comparativo";
import { listarComparativo } from "@/lib/consultas/comparativo";
import { mensagens } from "@/lib/mensagens";

export const metadata: Metadata = { title: "Comparativo entre obras" };

async function carregarComparativo(): Promise<LinhaComparativo[] | null> {
  try {
    return await listarComparativo();
  } catch {
    return null;
  }
}

// Entrada do menu: com uma obra só (gerente de obra), vai direto para a tela dela; com mais, compara.
export default async function PaginaObras() {
  const linhas = await carregarComparativo();
  if (linhas?.length === 1) redirect(`/obras/${linhas[0].centro_custo_id}`);

  return (
    <>
      {/* Só esta tela imprime deitada: a tabela não cabe na folha em pé. */}
      <style>{"@page { size: A4 landscape; }"}</style>
      <h1 className="font-serif text-[34px] font-semibold">Comparativo entre obras</h1>
      {linhas === null && (
        <p role="alert" className="text-alerta">
          {mensagens.posicao.indisponivel}
        </p>
      )}
      {linhas?.length === 0 && <p>{mensagens.posicao.semObras}</p>}
      {linhas && linhas.length > 1 && (
        <>
          <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
            <p className="max-w-3xl text-suave">
              Uma linha por obra com os números da última carga. O pior valor de cada coluna vem marcado em
              vermelho; o nome da obra abre a tela dela.
            </p>
            <BotaoImprimir />
          </div>
          <TabelaComparativo linhas={linhas} />
        </>
      )}
    </>
  );
}
