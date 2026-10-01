import { totalizarFunil, type LinhaFunil } from "@/lib/consultas/resumo-origem";
import { formatarConversao, formatarMes } from "@/lib/formatar";

const inteiro = new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 0 });

const maisReservas = "mais reservas que leads";
const maisVendas = "mais vendas que reservas";

const celula = "px-3 py-2 text-right tabular-nums";

// Mês a mês e o total do período. Conversão é razão do mesmo mês, não coorte.
export function TabelaFunil({ linhas }: { linhas: LinhaFunil[] }) {
  const total = totalizarFunil(linhas);
  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[640px] border-collapse text-sm">
        <caption className="sr-only">Funil de vendas por mês</caption>
        <thead>
          <tr className="border-b border-borda text-suave">
            <th scope="col" className="px-3 py-2 text-left font-semibold">Mês</th>
            <th scope="col" className={`${celula} font-semibold`}>Leads</th>
            <th scope="col" className={`${celula} font-semibold`}>Reservas</th>
            <th scope="col" className={`${celula} font-semibold`}>Vendas</th>
            <th scope="col" className={`${celula} font-semibold`}>Distratos</th>
            <th scope="col" className={`${celula} font-semibold`}>Lead para reserva</th>
            <th scope="col" className={`${celula} font-semibold`}>Reserva para venda</th>
          </tr>
        </thead>
        <tbody>
          {linhas.map((linha) => (
            <tr key={linha.competencia} className="border-b border-borda">
              <th scope="row" className="px-3 py-2 text-left font-normal">{formatarMes(linha.competencia)}</th>
              <td className={celula}>{inteiro.format(linha.leads)}</td>
              <td className={celula}>{inteiro.format(linha.reservas)}</td>
              <td className={celula}>{inteiro.format(linha.vendas)}</td>
              <td className={celula}>{inteiro.format(linha.distratos)}</td>
              <td className={celula}>{formatarConversao(linha.conversao_lead_reserva, maisReservas)}</td>
              <td className={celula}>{formatarConversao(linha.conversao_reserva_venda, maisVendas)}</td>
            </tr>
          ))}
        </tbody>
        <tfoot>
          <tr className="font-semibold">
            <th scope="row" className="px-3 py-2 text-left">Período</th>
            <td className={celula}>{inteiro.format(total.leads)}</td>
            <td className={celula}>{inteiro.format(total.reservas)}</td>
            <td className={celula}>{inteiro.format(total.vendas)}</td>
            <td className={celula}>{inteiro.format(total.distratos)}</td>
            <td className={celula}>{formatarConversao(total.conversaoLeadReserva, maisReservas)}</td>
            <td className={celula}>{formatarConversao(total.conversaoReservaVenda, maisVendas)}</td>
          </tr>
        </tfoot>
      </table>
    </div>
  );
}
