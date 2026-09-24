import type { Metadata } from "next";
import { listarPosicaoObras, type PosicaoObra } from "@/lib/consultas/posicao";
import { formatarReal } from "@/lib/formatar";
import { mensagens } from "@/lib/mensagens";

export const metadata: Metadata = { title: "Visão geral" };

// Página provisória do PT-01, só para provar o acesso com RLS. O PT-02 substitui.
const colunas: { chave: keyof PosicaoObra; rotulo: string }[] = [
  { chave: "caixa_atual", rotulo: "Caixa atual" },
  { chave: "exposicao_maxima", rotulo: "Exposição máxima" },
  { chave: "a_receber_direto", rotulo: "A receber do comprador" },
  { chave: "a_receber_repasse", rotulo: "A receber do banco" },
  { chave: "a_pagar", rotulo: "A pagar" },
  { chave: "resultado_projetado", rotulo: "Resultado projetado" },
];

async function carregarObras(): Promise<PosicaoObra[] | null> {
  try {
    return await listarPosicaoObras();
  } catch {
    return null;
  }
}

export default async function PaginaVisaoGeral() {
  const obras = await carregarObras();

  return (
    <>
      <h1 className="font-serif text-[34px] font-semibold">Visão geral</h1>
      {obras === null && (
        <p role="alert" className="text-alerta">
          {mensagens.posicao.indisponivel}
        </p>
      )}
      {obras?.length === 0 && <p>{mensagens.posicao.semObras}</p>}
      {obras && obras.length > 0 && (
        <div className="overflow-x-auto rounded-xl border border-borda bg-superficie">
          <table className="w-full text-sm tabular-nums">
            <caption className="sr-only">Posição financeira por obra, em reais</caption>
            <thead>
              <tr className="border-b border-borda text-suave">
                <th scope="col" className="px-4 py-3 text-left font-medium">
                  Obra
                </th>
                {colunas.map((coluna) => (
                  <th key={coluna.chave} scope="col" className="px-4 py-3 text-right font-medium">
                    {coluna.rotulo}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {obras.map((obra) => (
                <tr key={obra.centro_custo_id} className="border-b border-borda last:border-b-0">
                  <th scope="row" className="px-4 py-3 text-left font-semibold whitespace-nowrap">
                    {obra.obra}
                  </th>
                  {colunas.map((coluna) => (
                    <td key={coluna.chave} className="px-4 py-3 text-right whitespace-nowrap">
                      {formatarReal(Number(obra[coluna.chave]))}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}
