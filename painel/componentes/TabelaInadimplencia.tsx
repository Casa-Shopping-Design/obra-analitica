import { rotuloFaixa, totalizarInadimplencia, type LinhaInadimplencia } from "@/lib/consultas/resumo-origem";
import { formatarReal } from "@/lib/formatar";

const inteiro = new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 0 });
const celula = "px-3 py-2 text-right tabular-nums";

// As quatro faixas vêm sempre da view, com zero quando vazias, para faixa sem título não sumir da tela.
// Cada título cai na faixa da parcela mais atrasada.
export function TabelaInadimplencia({ linhas }: { linhas: LinhaInadimplencia[] }) {
  const total = totalizarInadimplencia(linhas);
  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[560px] border-collapse text-sm">
        <caption className="sr-only">Inadimplência por faixa de atraso</caption>
        <thead>
          <tr className="border-b border-borda text-suave">
            <th scope="col" className="px-3 py-2 text-left font-semibold">Atraso</th>
            <th scope="col" className={`${celula} font-semibold`}>Títulos</th>
            <th scope="col" className={`${celula} font-semibold`}>Parcelas</th>
            <th scope="col" className={`${celula} font-semibold`}>Valor corrigido</th>
            <th scope="col" className={`${celula} font-semibold`}>Com juros e multa</th>
          </tr>
        </thead>
        <tbody>
          {linhas.map((linha) => (
            <tr key={linha.ordem} className="border-b border-borda">
              <th scope="row" className="px-3 py-2 text-left font-normal">{rotuloFaixa(linha.faixa)}</th>
              <td className={celula}>{inteiro.format(linha.titulos)}</td>
              <td className={celula}>{inteiro.format(linha.parcelas)}</td>
              <td className={celula}>{formatarReal(linha.valor_atrasado)}</td>
              <td className={celula}>{formatarReal(linha.valor_atualizado)}</td>
            </tr>
          ))}
        </tbody>
        <tfoot>
          <tr className="font-semibold">
            <th scope="row" className="px-3 py-2 text-left">Total</th>
            <td className={celula}>{inteiro.format(total.titulos)}</td>
            <td className={celula}>{inteiro.format(total.parcelas)}</td>
            <td className={celula}>{formatarReal(total.valorAtrasado)}</td>
            <td className={celula}>{formatarReal(total.valorAtualizado)}</td>
          </tr>
        </tfoot>
      </table>
    </div>
  );
}
