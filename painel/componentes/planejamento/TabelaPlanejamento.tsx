import Link from "next/link";
import { Explicacao } from "@/componentes/planejamento/Explicacao";

export type ColunaPlanejamento = { chave: string; rotulo: string; explicacao?: string; texto?: boolean };
export type LinhaPlanejamento = {
  chave: string;
  rotulo: React.ReactNode;
  href?: string;
  destaque?: boolean;
  celulas: Record<string, React.ReactNode>;
};

// Tabela larga com rolagem só dentro da moldura; em tela estreita cada linha vira um cartão.
// A primeira coluna é cabeçalho de linha (mês ou obra), para leitor de tela anunciar o contexto.
export function TabelaPlanejamento({
  legenda,
  rotuloPrimeira,
  colunas,
  linhas,
}: {
  legenda: string;
  rotuloPrimeira: string;
  colunas: ColunaPlanejamento[];
  linhas: LinhaPlanejamento[];
}) {
  const rotuloLinha = (linha: LinhaPlanejamento) =>
    linha.href ? (
      <Link href={linha.href} className="font-semibold underline underline-offset-4 hover:text-menu">
        {linha.rotulo}
      </Link>
    ) : (
      linha.rotulo
    );

  return (
    <>
      <div className="hidden max-h-[70vh] overflow-auto rounded-xl border border-borda bg-superficie md:block">
        <table className="w-full text-sm tabular-nums">
          <caption className="sr-only">{legenda}</caption>
          <thead>
            <tr className="text-suave">
              <th scope="col" className="sticky top-0 left-0 z-20 border-b border-borda bg-superficie px-3 py-3 text-left align-bottom font-medium">
                {rotuloPrimeira}
              </th>
              {colunas.map((coluna) => (
                <th
                  key={coluna.chave}
                  scope="col"
                  className={`sticky top-0 z-10 border-b border-borda bg-superficie px-3 py-3 align-bottom font-medium ${coluna.texto ? "text-left" : "text-right"}`}
                >
                  <span className={`inline-flex items-center gap-1.5 ${coluna.texto ? "" : "justify-end"}`}>
                    {coluna.rotulo}
                    {coluna.explicacao && <Explicacao texto={coluna.explicacao} rotulo={coluna.rotulo} alinhamento="direita" />}
                  </span>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {linhas.map((linha) => (
              <tr key={linha.chave} className={`border-b border-borda last:border-b-0 ${linha.destaque ? "bg-trilho/60" : ""}`}>
                <th scope="row" className="sticky left-0 bg-superficie px-3 py-2.5 text-left font-normal whitespace-nowrap">
                  {rotuloLinha(linha)}
                </th>
                {colunas.map((coluna) => (
                  <td
                    key={coluna.chave}
                    className={`px-3 py-2.5 align-top ${coluna.texto ? "min-w-48 text-left" : "text-right whitespace-nowrap"}`}
                  >
                    {linha.celulas[coluna.chave]}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <ul className="flex flex-col gap-3 md:hidden" aria-label={legenda}>
        {linhas.map((linha) => (
          <li key={linha.chave} className="rounded-xl border border-borda bg-superficie p-4">
            <p className="font-semibold">{rotuloLinha(linha)}</p>
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
    </>
  );
}
