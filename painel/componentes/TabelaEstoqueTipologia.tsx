import type { EstoqueTipologia } from "@/lib/consultas/estoque";
import { formatarReal } from "@/lib/formatar";

const inteiro = new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 0 });
const celula = "px-3 py-2 text-right tabular-nums print:px-1";

function realOuTraco(valor: number | null): string {
  return valor === null ? "sem preço" : formatarReal(valor);
}

// Contagens e valores vêm de marts.estoque_tipologia; a tabela não soma nada.
export function TabelaEstoqueTipologia({ linhas }: { linhas: EstoqueTipologia[] }) {
  return (
    <div className="overflow-x-auto print:overflow-visible">
      <table className="w-full min-w-[760px] border-collapse text-sm print:min-w-0 print:text-xs">
        <caption className="sr-only">Estoque por tipologia, com o valor a preço de hoje</caption>
        <thead>
          <tr className="border-b border-borda text-suave">
            <th scope="col" className="px-3 py-2 text-left font-semibold print:px-1">Tipologia</th>
            <th scope="col" className={`${celula} font-semibold`}>Disponíveis</th>
            <th scope="col" className={`${celula} font-semibold`}>Reservadas</th>
            <th scope="col" className={`${celula} font-semibold`}>Propostas</th>
            <th scope="col" className={`${celula} font-semibold`}>Vendidas</th>
            <th scope="col" className={`${celula} font-semibold`}>Fora de venda</th>
            <th scope="col" className={`${celula} font-semibold`}>Estoque a preço de hoje</th>
            <th scope="col" className={`${celula} font-semibold`}>Preço médio</th>
            <th scope="col" className={`${celula} font-semibold`}>Preço por m²</th>
          </tr>
        </thead>
        <tbody>
          {linhas.map((linha) => (
            <tr key={linha.tipologia} className="border-b border-borda">
              <th scope="row" className="px-3 py-2 text-left font-normal print:px-1">{linha.tipologia}</th>
              <td className={celula}>{inteiro.format(linha.disponiveis)}</td>
              <td className={celula}>{inteiro.format(linha.reservadas)}</td>
              <td className={celula}>{inteiro.format(linha.propostas)}</td>
              <td className={celula}>{inteiro.format(linha.vendidas)}</td>
              <td className={celula}>{inteiro.format(linha.fora_de_venda)}</td>
              <td className={celula}>{formatarReal(linha.valor_estoque)}</td>
              <td className={celula}>{realOuTraco(linha.preco_medio_estoque)}</td>
              <td className={celula}>{realOuTraco(linha.preco_m2_estoque)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
