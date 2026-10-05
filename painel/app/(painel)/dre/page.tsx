import type { Metadata } from "next";
import Link from "next/link";
import { ExplicacaoIndicador } from "@/componentes/ExplicacaoIndicador";
import { MiniaturaTendencia } from "@/componentes/GraficoTendencia";
import { listarResumoDre, listarTendenciaCarteira, podeVerDre } from "@/lib/consultas/dre";
import {
  formatarMesAno,
  percentualOuSemBase,
  situacaoDesvioMargem,
  textoDesvioPontos,
  type ResumoDre,
  type SituacaoDesvio,
} from "@/lib/dre";
import type { ChaveExplicacao } from "@/lib/explicacoes";
import { mensagens } from "@/lib/mensagens";
import { agruparSeriePorObra, type PontoTendencia } from "@/lib/serie-tendencia";

export const metadata: Metadata = { title: "DRE de viabilidade" };

const titulo = "DRE de viabilidade";

async function carregar(): Promise<ResumoDre[] | null> {
  try {
    return await listarResumoDre();
  } catch {
    return null;
  }
}

// Sem a série a lista continua; cada linha diz que a miniatura não carregou.
async function carregarSeries(): Promise<Map<string, PontoTendencia[]> | null> {
  try {
    return agruparSeriePorObra(await listarTendenciaCarteira());
  } catch {
    return null;
  }
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
  { rotulo: "Margem mês a mês", explicacao: "tendencia_margem_mensal" },
];

const celula = "px-3 py-3 text-right align-top whitespace-nowrap";

// O perfil é conferido antes da leitura; o RLS também esconderia as linhas, mas a tela diz por quê.
export default async function PaginaDre() {
  const permitido = await podeVerDre().catch(() => false);
  if (!permitido) {
    return (
      <>
        <h1 className="font-serif text-[34px] font-semibold">{titulo}</h1>
        <p>{mensagens.dre.restrita}</p>
      </>
    );
  }

  const [linhas, series] = await Promise.all([carregar(), carregarSeries()]);

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
            ainda falta. A miniatura mostra os últimos meses: linha cheia é a tendência, tracejada é o estudo. O
            nome da obra abre a DRE completa.
          </p>
          {series === null && (
            <p role="alert" className="text-alerta">
              {mensagens.dre.serieIndisponivel}
            </p>
          )}
          <section aria-labelledby="titulo-resumo-dre">
            <h2 id="titulo-resumo-dre" className="sr-only">
              Margem operacional por obra
            </h2>
            <div className="relative overflow-x-auto rounded-xl border border-borda bg-superficie">
              <table className="w-full min-w-[800px] border-collapse text-sm tabular-nums">
                <caption className="sr-only">
                  Margem operacional de cada obra no estudo, na tendência, o desvio em pontos percentuais e a margem da
                  tendência nos últimos meses.
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
                      <td className={celula}>{percentualOuSemBase(linha.margemOperacionalViabilidade)}</td>
                      <td className={celula}>{percentualOuSemBase(linha.margemOperacionalTendencia)}</td>
                      <td className={`${celula} ${corSituacao[situacaoDesvioMargem(linha.desvioMargemOperacional)]}`}>
                        {textoDesvioPontos(linha.desvioMargemOperacional)}
                      </td>
                      <td className="w-40 px-3 py-3 text-right align-top">
                        {series === null ? (
                          <span className="text-xs text-suave">indisponível</span>
                        ) : (
                          <MiniaturaTendencia pontos={series.get(linha.centroCustoId) ?? []} />
                        )}
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
