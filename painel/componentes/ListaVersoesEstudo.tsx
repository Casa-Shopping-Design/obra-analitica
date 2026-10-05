import Link from "next/link";
import { versoesPorPagina, type PaginaVersoes } from "@/lib/consultas/dre";
import { textoAutorVersao, textoSituacaoVersao } from "@/lib/dre";
import { formatarData } from "@/lib/formatar";
import { mensagens } from "@/lib/mensagens";

type Propriedades = { centroCustoId: string; usuarioId: string; pagina: PaginaVersoes };

const celula = "px-3 py-2.5 align-top";
const classeLink = "text-sm underline underline-offset-4 hover:text-menu";

// Só leitura: versão antiga não se edita nem se apaga. A página vai no endereço, então o botão de voltar funciona.
export function ListaVersoesEstudo({ centroCustoId, usuarioId, pagina }: Propriedades) {
  if (pagina.total === 0) return <p>{mensagens.estudo.semVersoes}</p>;

  const primeira = (pagina.pagina - 1) * versoesPorPagina + 1;
  const ultima = Math.min(pagina.pagina * versoesPorPagina, pagina.total);
  const temAnterior = pagina.pagina > 1;
  const temProxima = ultima < pagina.total;
  const caminho = `/obras/${centroCustoId}/dre/estudo`;

  return (
    <div className="flex flex-col gap-3">
      <div className="overflow-x-auto rounded-xl border border-borda bg-superficie">
        <table className="w-full min-w-[640px] border-collapse text-sm">
          <caption className="sr-only">Versões do estudo de viabilidade, da mais nova para a mais antiga.</caption>
          <thead>
            <tr className="text-suave">
              <th scope="col" className={`${celula} border-b border-borda text-right font-medium`}>
                Versão
              </th>
              <th scope="col" className={`${celula} border-b border-borda text-left font-medium`}>
                Descrição
              </th>
              <th scope="col" className={`${celula} border-b border-borda text-left font-medium`}>
                Data-base
              </th>
              <th scope="col" className={`${celula} border-b border-borda text-left font-medium`}>
                Gravada em
              </th>
              <th scope="col" className={`${celula} border-b border-borda text-left font-medium`}>
                Por
              </th>
              <th scope="col" className={`${celula} border-b border-borda text-left font-medium`}>
                Situação
              </th>
            </tr>
          </thead>
          <tbody>
            {pagina.versoes.map((versao) => (
              <tr
                key={versao.versao}
                className={`border-b border-borda last:border-b-0 ${versao.situacao === "vigente" ? "font-semibold" : ""}`}
              >
                <th
                  scope="row"
                  className={`${celula} text-right tabular-nums ${versao.situacao === "vigente" ? "font-semibold" : "font-normal"}`}
                >
                  {versao.versao}
                </th>
                <td className={celula}>{versao.descricao ?? "sem descrição"}</td>
                <td className={`${celula} whitespace-nowrap`}>{formatarData(versao.dataBase)}</td>
                <td className={`${celula} whitespace-nowrap`}>{formatarData(versao.criadoEm)}</td>
                <td className={celula}>{textoAutorVersao(versao, usuarioId)}</td>
                <td className={celula}>{textoSituacaoVersao(versao.situacao)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <nav aria-label="Páginas das versões" className="flex flex-wrap items-center gap-x-5 gap-y-2 text-sm text-suave">
        <span>
          Mostrando {primeira} a {ultima} de {pagina.total}.
        </span>
        {temAnterior && (
          <Link href={`${caminho}?pagina=${pagina.pagina - 1}`} className={classeLink}>
            Mais novas
          </Link>
        )}
        {temProxima && (
          <Link href={`${caminho}?pagina=${pagina.pagina + 1}`} className={classeLink}>
            Mais antigas
          </Link>
        )}
      </nav>
    </div>
  );
}
