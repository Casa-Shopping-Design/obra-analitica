import { ExplicacaoIndicador } from "@/componentes/ExplicacaoIndicador";
import type { GradeDre } from "@/componentes/financeiro/montar-dre";
import { ValorEstado } from "@/componentes/financeiro/ValorEstado";
import { formatarMes, formatarPercentual } from "@/lib/formatar";

function textoCobertura(cobertura: number | null): string {
  return cobertura === null ? "sem lançamento" : `${formatarPercentual(cobertura)} classificado`;
}

// Tabela linha x mês em tela larga, com rolagem só dentro da moldura; em tela estreita, um cartão por mês.
export function GradeDreMensal({ grade, legenda }: { grade: GradeDre; legenda: string }) {
  return (
    <>
      <div className="hidden overflow-auto rounded-xl border border-borda bg-superficie md:block">
        <table className="w-full text-sm tabular-nums">
          <caption className="sr-only">{legenda}</caption>
          <thead>
            <tr className="text-suave">
              <th
                scope="col"
                className="sticky left-0 z-10 border-b border-borda bg-superficie px-3 py-2 text-left font-medium"
              >
                Linha
              </th>
              {grade.meses.map((mes, posicao) => (
                <th
                  key={mes}
                  scope="col"
                  className="border-b border-borda px-3 py-2 text-right align-bottom font-medium whitespace-nowrap"
                >
                  {formatarMes(mes)}
                  <span className="block text-xs font-normal">{textoCobertura(grade.cobertura[posicao])}</span>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {grade.linhas.map((linha) => (
              <tr
                key={linha.codigo}
                className={`border-b border-borda last:border-b-0 ${linha.informativa ? "text-suave" : ""}`}
              >
                <th
                  scope="row"
                  className={`sticky left-0 bg-superficie px-3 py-2 text-left whitespace-nowrap ${linha.subtotal ? "font-semibold" : "font-normal"}`}
                >
                  <span className="inline-flex items-center gap-1.5">
                    {linha.nome}
                    <ExplicacaoIndicador chave={linha.codigo} rotulo={linha.nome} />
                  </span>
                </th>
                {linha.celulas.map((celula, posicao) => (
                  <td
                    key={grade.meses[posicao]}
                    className={`px-3 py-2 text-right align-top whitespace-nowrap ${linha.subtotal ? "font-semibold" : ""}`}
                  >
                    <ValorEstado estado={celula} mostrarMotivo={false} />
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <ul aria-label={legenda} className="flex flex-col gap-3 md:hidden">
        {[...grade.meses].reverse().map((mes) => {
          const posicao = grade.meses.indexOf(mes);
          return (
            <li key={mes} className="rounded-xl border border-borda bg-superficie p-4">
              <p className="font-semibold">
                {formatarMes(mes)}{" "}
                <span className="text-sm font-normal text-suave">· {textoCobertura(grade.cobertura[posicao])}</span>
              </p>
              <dl className="mt-2 flex flex-col gap-1.5 text-sm">
                {grade.linhas.map((linha) => (
                  <div key={linha.codigo} className="flex flex-wrap justify-between gap-x-3">
                    <dt className={linha.subtotal ? "font-semibold" : "text-suave"}>{linha.nome}</dt>
                    <dd className={`text-right tabular-nums ${linha.subtotal ? "font-semibold" : ""}`}>
                      <ValorEstado estado={linha.celulas[posicao]} mostrarMotivo={false} />
                    </dd>
                  </div>
                ))}
              </dl>
            </li>
          );
        })}
      </ul>
    </>
  );
}
