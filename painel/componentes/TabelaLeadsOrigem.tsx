"use client";

import { useState } from "react";
import type { LinhaLeadOrigem } from "@/lib/consultas/resumo-origem";
import { formatarPercentual } from "@/lib/formatar";

const inteiro = new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 0 });
const celula = "px-3 py-2 text-right tabular-nums";
const linhasVisiveis = 10;

// Uma linha por origem e mídia, na ordem de volume que a consulta devolve. A tela abre com as maiores;
// o resto fica escondido até o clique, mas sai na impressão e entra no total.
export function TabelaLeadsOrigem({ linhas }: { linhas: LinhaLeadOrigem[] }) {
  const [todas, setTodas] = useState(false);
  const escondidas = linhas.length - linhasVisiveis;
  const total = linhas.reduce((soma, linha) => soma + linha.leads, 0);
  const descartados = linhas.reduce((soma, linha) => soma + linha.leads_descartados, 0);
  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[640px] border-collapse text-sm">
        <caption className="sr-only">Leads dos últimos 12 meses por origem e mídia</caption>
        <thead>
          <tr className="border-b border-borda text-suave">
            <th scope="col" className="px-3 py-2 text-left font-semibold">Origem</th>
            <th scope="col" className="px-3 py-2 text-left font-semibold">Mídia</th>
            <th scope="col" className={`${celula} font-semibold`}>Leads</th>
            <th scope="col" className={`${celula} font-semibold`}>Descartados</th>
            <th scope="col" className={`${celula} font-semibold`}>% descartados</th>
            <th scope="col" className="px-3 py-2 text-left font-semibold">Principal motivo do descarte</th>
          </tr>
        </thead>
        <tbody>
          {linhas.map((linha, posicao) => (
            <tr
              key={`${linha.origem}|${linha.midia}`}
              className={`border-b border-borda ${!todas && posicao >= linhasVisiveis ? "hidden print:table-row" : ""}`}
            >
              <th scope="row" className="px-3 py-2 text-left font-normal">{linha.origem}</th>
              <td className="px-3 py-2 text-left">{linha.midia}</td>
              <td className={celula}>{inteiro.format(linha.leads)}</td>
              <td className={celula}>{inteiro.format(linha.leads_descartados)}</td>
              <td className={celula}>{linha.pct_descartados === null ? "sem base" : formatarPercentual(linha.pct_descartados)}</td>
              <td className="px-3 py-2 text-left">
                {linha.motivo_principal_descarte === null ? (
                  <span className="text-suave">{linha.leads_descartados === 0 ? "nenhum descarte" : "sem motivo informado"}</span>
                ) : (
                  `${linha.motivo_principal_descarte} (${inteiro.format(linha.leads_motivo_principal ?? 0)})`
                )}
              </td>
            </tr>
          ))}
        </tbody>
        <tfoot>
          <tr className="font-semibold">
            <th scope="row" colSpan={2} className="px-3 py-2 text-left">Total</th>
            <td className={celula}>{inteiro.format(total)}</td>
            <td className={celula}>{inteiro.format(descartados)}</td>
            <td className={celula}>{total > 0 ? formatarPercentual(descartados / total) : "sem base"}</td>
            <td />
          </tr>
        </tfoot>
      </table>
      {escondidas > 0 && (
        <button
          type="button"
          onClick={() => setTodas(!todas)}
          aria-expanded={todas}
          className="mt-3 min-h-11 rounded-lg border border-borda px-4 text-sm font-semibold hover:border-texto print:hidden"
        >
          {todas ? `Mostrar só as ${linhasVisiveis} maiores` : `Ver todas as ${linhas.length} combinações`}
        </button>
      )}
    </div>
  );
}
