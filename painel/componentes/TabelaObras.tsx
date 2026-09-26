"use client";

import Link from "next/link";
import { useState } from "react";
import { ExplicacaoIndicador } from "@/componentes/ExplicacaoIndicador";
import type { PosicaoObra } from "@/lib/consultas/posicao";
import type { ChaveExplicacao } from "@/lib/explicacoes";
import { formatarReal } from "@/lib/formatar";

type ColunaValor = Extract<keyof PosicaoObra, ChaveExplicacao> | "aporte_projetado";
type ColunaOrdem = ColunaValor | "obra";
type Direcao = "asc" | "desc";
type Coluna = { chave: ColunaValor; rotulo: string; explicacao: ChaveExplicacao };

// Maior aporte da projeção por obra (marts.resumo_projecao_obra), já juntado pela página. Objeto simples
// porque atravessa a fronteira do componente de cliente.
export type AportesPorObra = Record<string, { valor: number; parcial: boolean }>;

const colunaAporte: Coluna = {
  chave: "aporte_projetado",
  rotulo: "Maior aporte necessário",
  explicacao: "exposicao_maxima_projetada",
};

// Todas as colunas de valor, na ordem: entra, sai, resultado. O aporte vem da projeção, a mesma fonte da
// tela de fluxo e do assistente.
const colunasPosicao: { chave: Exclude<ColunaValor, "aporte_projetado">; rotulo: string }[] = [
  { chave: "recebido_direto", rotulo: "Recebido do comprador" },
  { chave: "recebido_repasse", rotulo: "Recebido do banco" },
  { chave: "a_receber_direto", rotulo: "A receber do comprador" },
  { chave: "a_receber_repasse", rotulo: "A receber do banco" },
  { chave: "vencido_direto", rotulo: "Vencido do comprador" },
  { chave: "repasse_atrasado", rotulo: "Repasse atrasado" },
  { chave: "estoque_a_vender", rotulo: "Estoque a preço de hoje" },
  { chave: "pago", rotulo: "Pago" },
  { chave: "a_pagar", rotulo: "A pagar" },
  { chave: "custo_orcado", rotulo: "Custo orçado" },
  { chave: "custo_a_incorrer", rotulo: "Orçamento sem título" },
  { chave: "estouro_orcamento", rotulo: "Estouro do orçamento" },
  { chave: "caixa_atual", rotulo: "Caixa gerado acumulado" },
  { chave: "exposicao_maxima", rotulo: "Exposição máxima" },
  { chave: "resultado_contratado", rotulo: "Resultado contratado" },
  { chave: "resultado_projetado", rotulo: "Resultado projetado" },
];

const posicaoCaixa = colunasPosicao.findIndex((coluna) => coluna.chave === "caixa_atual");
const colunas: Coluna[] = [
  ...colunasPosicao.slice(0, posicaoCaixa + 1).map((coluna) => ({ ...coluna, explicacao: coluna.chave })),
  colunaAporte,
  ...colunasPosicao.slice(posicaoCaixa + 1).map((coluna) => ({ ...coluna, explicacao: coluna.chave })),
];

const rotulosOrdem: Record<ColunaOrdem, string> = {
  obra: "Obra",
  ...Object.fromEntries(colunas.map((coluna) => [coluna.chave, coluna.rotulo])),
} as Record<ColunaOrdem, string>;

function valorColuna(obra: PosicaoObra, coluna: ColunaValor, aportes: AportesPorObra): number | null {
  if (coluna === "aporte_projetado") return aportes[obra.centro_custo_id]?.valor ?? null;
  return Number(obra[coluna]);
}

// Sem valor (projeção não carregada) fica sempre no fim, nos dois sentidos.
function ordenar(obras: PosicaoObra[], coluna: ColunaOrdem, direcao: Direcao, aportes: AportesPorObra): PosicaoObra[] {
  const sinal = direcao === "asc" ? 1 : -1;
  return [...obras].sort((a, b) => {
    if (coluna === "obra") return sinal * a.obra.localeCompare(b.obra, "pt-BR");
    const valorA = valorColuna(a, coluna, aportes);
    const valorB = valorColuna(b, coluna, aportes);
    if (valorA === null || valorB === null) return valorA === null ? (valorB === null ? 0 : 1) : -1;
    return sinal * (valorA - valorB);
  });
}

function Celula({ obra, coluna, aportes }: { obra: PosicaoObra; coluna: ColunaValor; aportes: AportesPorObra }) {
  const valor = valorColuna(obra, coluna, aportes);
  if (valor === null) return <span className="text-suave">Não carregado</span>;
  const parcial = coluna === "aporte_projetado" && aportes[obra.centro_custo_id]?.parcial;
  return (
    <>
      {formatarReal(valor)}
      {parcial && <span className="block text-xs text-atencao">parcial</span>}
    </>
  );
}

function LinkObra({ obra }: { obra: PosicaoObra }) {
  return (
    <Link
      href={`/obras/${obra.centro_custo_id}`}
      className="font-semibold underline underline-offset-4 hover:text-menu"
    >
      {obra.obra}
    </Link>
  );
}

// Tabela larga em tela grande; em tela estreita cada obra vira um cartão com as mesmas colunas.
export function TabelaObras({ obras, aportes }: { obras: PosicaoObra[]; aportes: AportesPorObra }) {
  const [coluna, setColuna] = useState<ColunaOrdem>("obra");
  const [direcao, setDirecao] = useState<Direcao>("asc");
  const ordenadas = ordenar(obras, coluna, direcao, aportes);

  function alternar(nova: ColunaOrdem) {
    if (nova === coluna) {
      setDirecao(direcao === "asc" ? "desc" : "asc");
    } else {
      setColuna(nova);
      setDirecao(nova === "obra" ? "asc" : "desc");
    }
  }

  function ariaSort(chave: ColunaOrdem) {
    if (chave !== coluna) return "none" as const;
    return direcao === "asc" ? ("ascending" as const) : ("descending" as const);
  }

  function seta(chave: ColunaOrdem) {
    if (chave !== coluna) return null;
    return <span aria-hidden="true">{direcao === "asc" ? " ↑" : " ↓"}</span>;
  }

  return (
    <section aria-labelledby="titulo-tabela-obras" className="flex flex-col gap-3">
      <h2 id="titulo-tabela-obras" className="font-serif text-2xl font-semibold">
        Todas as colunas por obra
      </h2>

      <div className="hidden max-h-[70vh] overflow-auto rounded-xl border border-borda bg-superficie md:block">
        <table className="w-full text-sm tabular-nums">
          <caption className="sr-only">
            Posição financeira por obra, em reais. Os botões do cabeçalho ordenam a tabela.
          </caption>
          <thead>
            <tr className="text-suave">
              <th
                scope="col"
                aria-sort={ariaSort("obra")}
                className="sticky top-0 left-0 z-10 border-b border-borda bg-superficie px-4 py-3 text-left font-medium"
              >
                <button type="button" onClick={() => alternar("obra")} className="cursor-pointer font-medium">
                  Obra
                  {seta("obra")}
                </button>
              </th>
              {colunas.map((item) => (
                <th
                  key={item.chave}
                  scope="col"
                  aria-sort={ariaSort(item.chave)}
                  className="sticky top-0 border-b border-borda bg-superficie px-4 py-3 text-right align-bottom font-medium"
                >
                  <span className="inline-flex items-center justify-end gap-1.5">
                    <button
                      type="button"
                      onClick={() => alternar(item.chave)}
                      className="cursor-pointer text-right font-medium"
                    >
                      {item.rotulo}
                      {seta(item.chave)}
                    </button>
                    <ExplicacaoIndicador chave={item.explicacao} rotulo={item.rotulo} alinhamento="direita" />
                  </span>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {ordenadas.map((obra) => (
              <tr key={obra.centro_custo_id} className="border-b border-borda last:border-b-0">
                <th scope="row" className="sticky left-0 bg-superficie px-4 py-3 text-left whitespace-nowrap">
                  <LinkObra obra={obra} />
                </th>
                {colunas.map((item) => (
                  <td key={item.chave} className="px-4 py-3 text-right whitespace-nowrap">
                    <Celula obra={obra} coluna={item.chave} aportes={aportes} />
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="flex flex-col gap-3 md:hidden">
        <div className="flex flex-col gap-1.5">
          <label htmlFor="ordem-cartoes" className="text-sm font-medium">
            Ordenar por
          </label>
          <div className="flex gap-2">
            <select
              id="ordem-cartoes"
              value={coluna}
              onChange={(evento) => setColuna(evento.target.value as ColunaOrdem)}
              className="min-h-11 min-w-0 flex-1 rounded-lg border border-borda bg-superficie px-3"
            >
              {(Object.keys(rotulosOrdem) as ColunaOrdem[]).map((chave) => (
                <option key={chave} value={chave}>
                  {rotulosOrdem[chave]}
                </option>
              ))}
            </select>
            <button
              type="button"
              onClick={() => setDirecao(direcao === "asc" ? "desc" : "asc")}
              className="min-h-11 shrink-0 cursor-pointer rounded-lg border border-borda bg-superficie px-3 text-sm"
            >
              {direcao === "asc" ? "Crescente" : "Decrescente"}
            </button>
          </div>
        </div>
        <ul className="flex flex-col gap-3">
          {ordenadas.map((obra) => (
            <li key={obra.centro_custo_id} className="rounded-xl border border-borda bg-superficie p-4">
              <LinkObra obra={obra} />
              <dl className="mt-3 flex flex-col gap-1.5 text-sm">
                {colunas.map((item) => (
                  <div key={item.chave} className="flex flex-wrap justify-between gap-x-3">
                    <dt className="text-suave">{item.rotulo}</dt>
                    <dd className="text-right font-medium tabular-nums">
                      <Celula obra={obra} coluna={item.chave} aportes={aportes} />
                    </dd>
                  </div>
                ))}
              </dl>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
