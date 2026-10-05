import type { Metadata } from "next";
import Link from "next/link";
import { ExplicacaoIndicador } from "@/componentes/ExplicacaoIndicador";
import { podeVerConferencia } from "@/lib/consultas/conferencia";
import { listarResumoDre } from "@/lib/consultas/dre";
import { formatarMesAno, situacaoDesvioMargem, textoDesvioPontos, type ResumoDre, type SituacaoDesvio } from "@/lib/dre";
import type { ChaveExplicacao } from "@/lib/explicacoes";
import { formatarPercentual } from "@/lib/formatar";
import { mensagens } from "@/lib/mensagens";

export const metadata: Metadata = { title: "DRE de viabilidade" };

const titulo = "DRE de viabilidade";

async function carregar(): Promise<ResumoDre[] | null> {
  try {
    return await listarResumoDre();
  } catch {
    return null;
  }
}

function percentualOu(fracao: number | null): string {
  return fracao === null ? "sem base" : formatarPercentual(fracao);
}

const corSituacao: Record<SituacaoDesvio, string> = {
  favoravel: "text-entrada",
  desfavoravel: "text-alerta",
  neutro: "",
};

const colunas: { rotulo: string; explicacao: ChaveExplicacao }[] = [
  { rotulo: "Margem no estudo", explicacao: "margem_operacional_viabilidade" },
  { rotulo: "Margem na tendência", explicacao: "margem_operacional_tendencia" },
  { rotulo: "Desvio da margem", explicacao: "desvio_margem_operacional" },
];

const celula = "px-3 py-3 text-right align-top whitespace-nowrap";

// O perfil é conferido antes da leitura; o RLS também esconderia as linhas, mas a tela diz por quê.
export default async function PaginaDre() {
  const permitido = await podeVerConferencia().catch(() => false);
  if (!permitido) {
    return (
      <>
        <h1 className="font-serif text-[34px] font-semibold">{titulo}</h1>
        <p>{mensagens.dre.restrita}</p>
      </>
    );
  }

  const linhas = await carregar();

  return (
    <>
      <h1 className="font-serif text-[34px] font-semibold">{titulo}</h1>
      {linhas === null && (
        <p role="alert" className="text-alerta">
          {mensagens.dre.indisponivel}
        </p>
      )}
      {linhas?.length === 0 && <p>{mensagens.dre.semObras}</p>}
      {linhas && linhas.length > 0 && (
        <>
          <p className="max-w-3xl text-suave">
            Margem operacional de cada obra no estudo de viabilidade e na tendência, que soma o realizado ao que
            ainda falta. O nome da obra abre a DRE completa.
          </p>
          <section aria-labelledby="titulo-resumo-dre">
            <h2 id="titulo-resumo-dre" className="sr-only">
              Margem operacional por obra
            </h2>
            <div className="relative overflow-x-auto rounded-xl border border-borda bg-superficie">
              <table className="w-full min-w-[640px] border-collapse text-sm tabular-nums">
                <caption className="sr-only">
                  Margem operacional de cada obra no estudo, na tendência e o desvio em pontos percentuais.
                </caption>
                <thead>
                  <tr className="text-suave">
                    <th
                      scope="col"
                      className="sticky left-0 z-10 border-b border-borda bg-superficie px-3 py-3 text-left align-bottom font-medium"
                    >
                      Obra
                    </th>
                    {colunas.map((coluna) => (
                      <th
                        key={coluna.rotulo}
                        scope="col"
                        className="border-b border-borda px-3 py-3 text-right align-bottom font-medium"
                      >
                        <span className="inline-flex items-center justify-end gap-1.5">
                          {coluna.rotulo}
                          <ExplicacaoIndicador chave={coluna.explicacao} rotulo={coluna.rotulo} alinhamento="direita" />
                        </span>
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {linhas.map((linha) => (
                    <tr key={linha.centroCustoId} className="border-b border-borda last:border-b-0">
                      <th
                        scope="row"
                        className="sticky left-0 z-10 bg-superficie px-3 py-3 text-left align-top whitespace-nowrap"
                      >
                        <Link
                          href={`/obras/${linha.centroCustoId}/dre`}
                          className="font-semibold underline underline-offset-4 hover:text-menu"
                        >
                          {linha.obra}
                        </Link>
                        <span className="block text-xs font-normal text-suave">
                          Realizado até {formatarMesAno(linha.competencia)}, estudo versão {linha.estudoVersao}
                        </span>
                      </th>
                      <td className={celula}>{percentualOu(linha.margemOperacionalViabilidade)}</td>
                      <td className={celula}>{percentualOu(linha.margemOperacionalTendencia)}</td>
                      <td className={`${celula} ${corSituacao[situacaoDesvioMargem(linha.desvioMargemOperacional)]}`}>
                        {textoDesvioPontos(linha.desvioMargemOperacional)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
        </>
      )}
    </>
  );
}
