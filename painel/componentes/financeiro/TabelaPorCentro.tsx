import Link from "next/link";
import { ExplicacaoIndicador } from "@/componentes/ExplicacaoIndicador";
import type { ChaveExplicacao } from "@/lib/explicacoes";

export type ColunaCentro = { chave: string; rotulo: string; explicacao?: ChaveExplicacao };
export type LinhaCentro = { id: string; nome: string; href?: string; celulas: Record<string, React.ReactNode> };
export type GrupoCentro = { titulo?: string; nota?: string; linhas: LinhaCentro[] };

function NomeCentro({ linha }: { linha: LinhaCentro }) {
  if (!linha.href) return <>{linha.nome}</>;
  return (
    <Link href={linha.href} className="font-semibold underline underline-offset-4 hover:text-menu">
      {linha.nome}
    </Link>
  );
}

// Tabela larga em tela grande, com rolagem só dentro da moldura; em tela estreita cada linha vira um
// cartão com as mesmas colunas. Grupos (como "Despesas sem obra") ficam num bloco próprio, nunca somados às obras.
export function TabelaPorCentro({
  legenda,
  rotuloPrimeira,
  colunas,
  grupos,
}: {
  legenda: string;
  rotuloPrimeira: string;
  colunas: ColunaCentro[];
  grupos: GrupoCentro[];
}) {
  const visiveis = grupos.filter((grupo) => grupo.linhas.length > 0);
  return (
    <>
      <div className="hidden max-h-[70vh] overflow-auto rounded-xl border border-borda bg-superficie md:block">
        <table className="w-full text-sm tabular-nums">
          <caption className="sr-only">{legenda}</caption>
          <thead>
            <tr className="text-suave">
              <th
                scope="col"
                className="sticky top-0 left-0 z-20 border-b border-borda bg-superficie px-4 py-3 text-left align-bottom font-medium"
              >
                {rotuloPrimeira}
              </th>
              {colunas.map((coluna) => (
                <th
                  key={coluna.chave}
                  scope="col"
                  className="sticky top-0 z-10 border-b border-borda bg-superficie px-4 py-3 text-right align-bottom font-medium"
                >
                  <span className="inline-flex items-center justify-end gap-1.5">
                    {coluna.rotulo}
                    {coluna.explicacao && (
                      <ExplicacaoIndicador chave={coluna.explicacao} rotulo={coluna.rotulo} alinhamento="direita" />
                    )}
                  </span>
                </th>
              ))}
            </tr>
          </thead>
          {visiveis.map((grupo, posicao) => (
            <tbody key={grupo.titulo ?? posicao}>
              {grupo.titulo && (
                <tr>
                  <th
                    scope="rowgroup"
                    colSpan={colunas.length + 1}
                    className="sticky left-0 border-b border-borda bg-superficie px-4 pt-5 pb-2 text-left font-semibold"
                  >
                    {grupo.titulo}
                    {grupo.nota && <span className="block text-xs font-normal text-suave">{grupo.nota}</span>}
                  </th>
                </tr>
              )}
              {grupo.linhas.map((linha) => (
                <tr key={linha.id} className="border-b border-borda last:border-b-0">
                  <th
                    scope="row"
                    className="sticky left-0 bg-superficie px-4 py-3 text-left font-normal whitespace-nowrap"
                  >
                    <NomeCentro linha={linha} />
                  </th>
                  {colunas.map((coluna) => (
                    <td key={coluna.chave} className="px-4 py-3 text-right align-top whitespace-nowrap">
                      {linha.celulas[coluna.chave]}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          ))}
        </table>
      </div>

      <div className="flex flex-col gap-4 md:hidden">
        {visiveis.map((grupo, posicao) => (
          <section key={grupo.titulo ?? posicao} aria-label={grupo.titulo ?? legenda} className="flex flex-col gap-3">
            {grupo.titulo && (
              <h3 className="font-semibold">
                {grupo.titulo}
                {grupo.nota && <span className="block text-xs font-normal text-suave">{grupo.nota}</span>}
              </h3>
            )}
            <ul className="flex flex-col gap-3">
              {grupo.linhas.map((linha) => (
                <li key={linha.id} className="rounded-xl border border-borda bg-superficie p-4">
                  <NomeCentro linha={linha} />
                  <dl className="mt-3 flex flex-col gap-1.5 text-sm">
                    {colunas.map((coluna) => (
                      <div key={coluna.chave} className="flex flex-wrap justify-between gap-x-3">
                        <dt className="text-suave">{coluna.rotulo}</dt>
                        <dd className="text-right font-medium tabular-nums">{linha.celulas[coluna.chave]}</dd>
                      </div>
                    ))}
                  </dl>
                </li>
              ))}
            </ul>
          </section>
        ))}
      </div>
    </>
  );
}
