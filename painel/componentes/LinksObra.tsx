import Link from "next/link";
import { podeVerConferencia } from "@/lib/consultas/conferencia";

const classeLink = "w-fit text-sm font-semibold underline underline-offset-4 hover:text-menu";

// A DRE e a conferência só aparecem para diretor e financeiro; cada tela confere de novo o perfil.
export async function LinksObra({ id }: { id: string }) {
  const verConferencia = await podeVerConferencia().catch(() => false);
  const destinos = [
    ...(verConferencia ? [{ rotulo: "DRE de viabilidade", caminho: "dre" }] : []),
    { rotulo: "Mapa de unidades", caminho: "unidades" },
    { rotulo: "Estoque e vendas", caminho: "estoque" },
    { rotulo: "Simulação de vendas", caminho: "simulacao" },
    { rotulo: "Vendas e repasse", caminho: "vendas" },
    { rotulo: "Execução física", caminho: "execucao" },
    { rotulo: "Inadimplência", caminho: "inadimplencia" },
    ...(verConferencia ? [{ rotulo: "Conferência com o ERP", caminho: "conferencia" }] : []),
    { rotulo: "Relatório para imprimir", caminho: "relatorio" },
  ];
  return (
    <nav aria-label="Telas da obra">
      <ul className="flex flex-wrap gap-x-5 gap-y-2">
        {destinos.map((destino) => (
          <li key={destino.caminho}>
            <Link href={`/obras/${id}/${destino.caminho}`} className={classeLink}>
              {destino.rotulo}
            </Link>
          </li>
        ))}
      </ul>
    </nav>
  );
}
