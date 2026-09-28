import type { ConferenciaObra, ItemConferencia } from "@/lib/consultas/conferencia";
import { classificarDiferenca, type SituacaoDiferenca } from "@/lib/consultas/resumo-origem";
import { formatarPercentual, formatarReal } from "@/lib/formatar";

const situacoes: Record<SituacaoDiferenca, { rotulo: string; classe: string }> = {
  confere: { rotulo: "Confere", classe: "text-entrada" },
  atencao: { rotulo: "Olhar", classe: "text-atencao" },
  diverge: { rotulo: "Diverge", classe: "text-alerta" },
  sem_base: { rotulo: "ERP zerado", classe: "text-suave" },
};

const celula = "px-3 py-2 text-right tabular-nums";

function Linha({ rotulo, item }: { rotulo: string; item: ItemConferencia }) {
  const situacao = situacoes[classificarDiferenca(item.diferencaPct)];
  return (
    <tr className="border-b border-borda">
      <th scope="row" className="px-3 py-2 text-left font-normal">{rotulo}</th>
      <td className={celula}>{formatarReal(item.painel)}</td>
      <td className={celula}>{formatarReal(item.origem)}</td>
      <td className={celula}>{formatarReal(item.diferenca)}</td>
      <td className={celula}>{item.diferencaPct === null ? "sem base" : formatarPercentual(item.diferencaPct)}</td>
      <td className={`${celula} font-semibold ${situacao.classe}`}>{situacao.rotulo}</td>
    </tr>
  );
}

export function TabelaConferencia({ conferencia }: { conferencia: ConferenciaObra }) {
  return (
    <div className="flex flex-col gap-4">
      <div className="overflow-x-auto">
        <table className="w-full min-w-[640px] border-collapse text-sm">
          <caption className="sr-only">Painel contra o ERP</caption>
          <thead>
            <tr className="border-b border-borda text-suave">
              <th scope="col" className="px-3 py-2 text-left font-semibold">Indicador</th>
              <th scope="col" className={`${celula} font-semibold`}>Painel</th>
              <th scope="col" className={`${celula} font-semibold`}>ERP</th>
              <th scope="col" className={`${celula} font-semibold`}>Diferença</th>
              <th scope="col" className={`${celula} font-semibold`}>Diferença em %</th>
              <th scope="col" className={`${celula} font-semibold`}>Situação</th>
            </tr>
          </thead>
          <tbody>
            <Linha rotulo="VGV" item={conferencia.vgv} />
            <Linha rotulo="Custo orçado" item={conferencia.custoOrcado} />
            <Linha rotulo="Custo incorrido" item={conferencia.custoIncorrido} />
            <Linha rotulo="Recebido" item={conferencia.recebido} />
          </tbody>
        </table>
      </div>
      <ul className="flex list-disc flex-col gap-1 pl-5 text-sm text-suave">
        <li>Até 1% de diferença confere; de 1% a 5% vale olhar; acima de 5% diverge.</li>
        <li>O VGV do painel é o de hoje: vendido pelo contrato mais o estoque pela tabela vigente.</li>
        <li>
          O custo incorrido do painel é o pago até o mês mais os títulos em aberto que vencem até o mês. O ERP apropria
          pela competência do título, então título lançado com vencimento futuro aparece como diferença.
        </li>
      </ul>
    </div>
  );
}
