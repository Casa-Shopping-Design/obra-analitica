import { ExplicacaoIndicador } from "@/componentes/ExplicacaoIndicador";
import type { LinhaDreTela } from "@/componentes/financeiro/montar-dre";
import { ValorEstado } from "@/componentes/financeiro/ValorEstado";

function Linhas({ linhas }: { linhas: LinhaDreTela[] }) {
  return (
    <>
      {linhas.map((linha) => (
        <tr
          key={linha.codigo}
          className={`border-b border-borda last:border-b-0 ${linha.subtotal ? "bg-fundo/40" : ""}`}
        >
          <th
            scope="row"
            className={`px-3 py-2.5 text-left align-top ${linha.subtotal ? "font-semibold" : "font-normal"}`}
          >
            <span className="inline-flex items-center gap-1.5">
              {linha.nome}
              <ExplicacaoIndicador chave={linha.codigo} rotulo={linha.nome} />
            </span>
          </th>
          <td className={`px-3 py-2.5 text-right align-top tabular-nums ${linha.subtotal ? "font-semibold" : ""}`}>
            <ValorEstado estado={linha.estado} />
          </td>
        </tr>
      ))}
    </>
  );
}

// Duas colunas só, para caber em 360 px: a linha e o valor do período. O informativo vem separado,
// porque não entra na soma do resultado.
export function TabelaDrePeriodo({
  resultado,
  informativas,
  rotuloPeriodo,
}: {
  resultado: LinhaDreTela[];
  informativas: LinhaDreTela[];
  rotuloPeriodo: string;
}) {
  return (
    <table className="w-full text-sm">
      <caption className="pb-2 text-left text-sm text-suave">
        DRE gerencial por competência, {rotuloPeriodo}, em reais. Receita positiva; custo e despesa negativos.
      </caption>
      <thead>
        <tr className="border-b border-borda text-suave">
          <th scope="col" className="px-3 py-2 text-left font-medium">
            Linha
          </th>
          <th scope="col" className="px-3 py-2 text-right font-medium">
            Valor no período
          </th>
        </tr>
      </thead>
      <tbody>
        <Linhas linhas={resultado} />
      </tbody>
      {informativas.length > 0 && (
        <tbody>
          <tr>
            <th scope="rowgroup" colSpan={2} className="px-3 pt-5 pb-2 text-left text-sm font-semibold text-suave">
              Informativo, fora da soma do resultado
            </th>
          </tr>
          <Linhas linhas={informativas} />
        </tbody>
      )}
    </table>
  );
}
