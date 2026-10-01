import Link from "next/link";
import { ExplicacaoIndicador } from "@/componentes/ExplicacaoIndicador";
import { pioresValores, type ColunaComparada, type LinhaComparativo } from "@/lib/comparativo";
import type { ChaveExplicacao } from "@/lib/explicacoes";
import { formatarDecimal, formatarPercentual, formatarReal } from "@/lib/formatar";

type Coluna = {
  rotulo: string;
  explicacao: ChaveExplicacao;
  destaque?: ColunaComparada;
  valor: (linha: LinhaComparativo) => string;
  detalhe?: (linha: LinhaComparativo) => string | null;
};

function percentualOu(fracao: number | null, vazio: string): string {
  return fracao === null ? vazio : formatarPercentual(fracao);
}

function pontos(diferenca: number): string {
  const valor = Math.round(diferenca * 1000) / 10;
  return `${valor > 0 ? "+" : ""}${formatarDecimal(valor)} pontos`;
}

const colunas: Coluna[] = [
  { rotulo: "VGV", explicacao: "vgv_total", valor: (linha) => formatarReal(linha.vgv_total) },
  {
    rotulo: "Vendido",
    explicacao: "pct_vgv_vendido",
    destaque: "pct_vgv_vendido",
    valor: (linha) => percentualOu(linha.pct_vgv_vendido, "sem preço"),
  },
  {
    rotulo: "VSO 12 meses",
    explicacao: "vso_12m",
    destaque: "vso_12m",
    valor: (linha) => percentualOu(linha.vso_12m, "sem estoque"),
    detalhe: (linha) =>
      linha.estoque_inicio_12m === null ? null : `${linha.vendas_liquidas_12m} sobre ${linha.estoque_inicio_12m} un.`,
  },
  {
    rotulo: "Estoque",
    explicacao: "estoque_obra",
    destaque: "valor_estoque",
    valor: (linha) => formatarReal(linha.valor_estoque),
    detalhe: (linha) => `${linha.unidades_estoque} ${linha.unidades_estoque === 1 ? "unidade" : "unidades"}`,
  },
  {
    rotulo: "Resultado projetado",
    explicacao: "resultado_projetado",
    destaque: "resultado_projetado",
    valor: (linha) => formatarReal(linha.resultado_projetado),
  },
  {
    rotulo: "Margem",
    explicacao: "margem_projetada",
    destaque: "margem_projetada",
    valor: (linha) => percentualOu(linha.margem_projetada, "sem VGV"),
  },
  {
    rotulo: "Exposição máxima",
    explicacao: "exposicao_maxima",
    destaque: "exposicao_maxima",
    valor: (linha) => formatarReal(linha.exposicao_maxima),
  },
  {
    rotulo: "Caixa atual",
    explicacao: "caixa_atual",
    destaque: "caixa_atual",
    valor: (linha) => formatarReal(linha.caixa_atual),
  },
  {
    rotulo: "Inadimplência",
    explicacao: "pct_inadimplencia",
    destaque: "pct_inadimplencia",
    valor: (linha) => percentualOu(linha.pct_inadimplencia, "sem carteira"),
  },
  {
    rotulo: "Vencido do comprador",
    explicacao: "vencido_direto",
    destaque: "vencido_direto",
    valor: (linha) => formatarReal(linha.vencido_direto),
  },
  {
    rotulo: "Pago à frente do físico",
    explicacao: "avanco_fisico_financeiro",
    destaque: "diferenca_financeiro_fisico",
    valor: (linha) =>
      linha.diferenca_financeiro_fisico === null ? "sem medição" : pontos(linha.diferenca_financeiro_fisico),
    detalhe: (linha) =>
      linha.pct_fisico === null || linha.pct_financeiro === null
        ? null
        : `físico ${formatarPercentual(linha.pct_fisico)}, pago ${formatarPercentual(linha.pct_financeiro)}`,
  },
  {
    rotulo: "Alertas",
    explicacao: "alertas_obra",
    destaque: "alertas",
    valor: (linha) => String(linha.alertas),
  },
];

const celula = "px-3 py-3 text-right align-top whitespace-nowrap print:px-1 print:py-1";
const classePior = "bg-alerta/10 font-semibold text-alerta print:[print-color-adjust:exact]";

// Tabela só de leitura: no celular rola para o lado com o nome da obra fixo; na impressão cabe numa folha deitada.
export function TabelaComparativo({ linhas }: { linhas: LinhaComparativo[] }) {
  const piores = pioresValores(linhas);

  return (
    <section aria-labelledby="titulo-comparativo" className="flex flex-col gap-3">
      <h2 id="titulo-comparativo" className="sr-only">
        Indicadores por obra
      </h2>
      <p className="text-sm text-suave md:hidden print:hidden">Arraste a tabela para o lado para ver todas as colunas.</p>
      <div className="overflow-x-auto rounded-xl border border-borda bg-superficie print:overflow-visible print:rounded-none print:border-0">
        <table className="w-full min-w-[1180px] border-collapse text-sm tabular-nums print:min-w-0 print:text-[8pt]">
          <caption className="sr-only">
            Indicadores de cada obra lado a lado. O pior valor de cada coluna vem marcado.
          </caption>
          <thead>
            <tr className="text-suave">
              <th
                scope="col"
                className="sticky left-0 z-10 border-b border-borda bg-superficie px-3 py-3 text-left align-bottom font-medium print:static print:px-1"
              >
                Obra
              </th>
              {colunas.map((coluna) => (
                <th
                  key={coluna.rotulo}
                  scope="col"
                  className="border-b border-borda px-3 py-3 text-right align-bottom font-medium print:px-1 print:whitespace-normal"
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
              <tr key={linha.centro_custo_id} className="border-b border-borda last:border-b-0">
                <th
                  scope="row"
                  className="sticky left-0 z-10 bg-superficie px-3 py-3 text-left align-top whitespace-nowrap print:static print:px-1 print:py-1"
                >
                  <Link
                    href={`/obras/${linha.centro_custo_id}`}
                    className="font-semibold underline underline-offset-4 hover:text-menu print:no-underline"
                  >
                    {linha.obra}
                  </Link>
                </th>
                {colunas.map((coluna) => {
                  const pior = coluna.destaque !== undefined && piores[coluna.destaque].has(linha.centro_custo_id);
                  const detalhe = coluna.detalhe?.(linha) ?? null;
                  return (
                    <td key={coluna.rotulo} className={`${celula} ${pior ? classePior : ""}`}>
                      {coluna.valor(linha)}
                      {pior && <span className="sr-only"> (pior entre as obras)</span>}
                      {detalhe && <span className="block text-xs font-normal text-suave">{detalhe}</span>}
                    </td>
                  );
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}
