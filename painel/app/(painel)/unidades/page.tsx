import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { listarObras, type ObraResumo } from "@/lib/consultas/unidades";
import { mensagens } from "@/lib/mensagens";

export const metadata: Metadata = { title: "Mapa de unidades" };

async function carregarObras(): Promise<ObraResumo[] | null> {
  try {
    return await listarObras();
  } catch {
    return null;
  }
}

// Entrada do menu: com uma obra só (gerente de obra), vai direto para o mapa dela.
export default async function PaginaEscolherObra() {
  const obras = await carregarObras();
  if (obras?.length === 1) redirect(`/obras/${obras[0].id}/unidades`);

  return (
    <>
      <h1 className="font-serif text-[34px] font-semibold">Mapa de unidades</h1>
      {obras === null && (
        <p role="alert" className="text-alerta">
          {mensagens.unidades.indisponivel}
        </p>
      )}
      {obras?.length === 0 && <p>{mensagens.posicao.semObras}</p>}
      {obras && obras.length > 1 && (
        <>
          <p className="text-suave">Escolha a obra para ver a situação de cada unidade.</p>
          <ul className="flex max-w-xl flex-col gap-2">
            {obras.map((obra) => (
              <li key={obra.id}>
                <Link
                  href={`/obras/${obra.id}/unidades`}
                  className="flex min-h-12 items-center rounded-xl border border-borda bg-superficie px-4 font-semibold hover:border-texto"
                >
                  {obra.nome}
                </Link>
              </li>
            ))}
          </ul>
        </>
      )}
    </>
  );
}
