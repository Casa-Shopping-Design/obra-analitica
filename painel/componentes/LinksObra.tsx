import Link from "next/link";
import { podeVerConferencia } from "@/lib/consultas/conferencia";
import { podeVerDre } from "@/lib/consultas/dre";

const classeLink = "w-fit text-sm font-semibold underline underline-offset-4 hover:text-menu";

// A DRE aparece para diretor, financeiro e leitura, e a conferência só para os dois primeiros; cada tela
// confere de novo o perfil.
export async function LinksObra({ id }: { id: string }) {
  const [verDre, verConferencia] = await Promise.all([
    podeVerDre().catch(() => false),
    podeVerConferencia().catch(() => false),
  ]);
  const destinos = [
    ...(verDre ? [{ rotulo: "DRE de viabilidade", caminho: "dre" }] : []),
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
