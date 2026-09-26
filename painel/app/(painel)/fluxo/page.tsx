import type { Metadata } from "next";
import { exigirIdentidade } from "@/lib/consultas/identidade";
import { redirect } from "next/navigation";
import { Aviso, Bloco, ErroBloco } from "@/componentes/financeiro/Aviso";
import { AvisoCarga } from "@/componentes/financeiro/AvisoCarga";
import { Selo } from "@/componentes/financeiro/Selo";
import { TabelaPlanejamento } from "@/componentes/planejamento/TabelaPlanejamento";
import { Valor } from "@/componentes/planejamento/Valor";
import { listarResumoProjecao, type ResumoProjecaoObra } from "@/lib/consultas/fluxo";
import { carregarReferencia, listarCentrosCusto, tentarConsulta } from "@/lib/consultas/referencia";
import { formatarData, formatarMes } from "@/lib/formatar";
import { fraseMotivo } from "@/lib/mensagens";
import { explicacoesPlanejamento, mensagensPlanejamento } from "@/lib/mensagens-planejamento";
import { lerIdCentro } from "@/lib/periodo";

export const metadata: Metadata = { title: "Fluxo de caixa" };

const colunas = [
  { chave: "exposicao", rotulo: "Maior aporte", explicacao: explicacoesPlanejamento.exposicao_maxima_projetada },
  { chave: "mes", rotulo: "Mês do pior caixa" },
  {
    chave: "conservadora",
    rotulo: "Sem financiamento pendente",
    explicacao: explicacoesPlanejamento.caixa_gerado_conservador,
  },
  {
    chave: "pendente",
    rotulo: "Financiamento pendente",
    explicacao: explicacoesPlanejamento.previsto_financiamento_pendente,
  },
  { chave: "vencido", rotulo: "Vencido a receber", explicacao: explicacoesPlanejamento.vencido_a_receber },
  { chave: "a_pagar_vencido", rotulo: "A pagar vencido", explicacao: explicacoesPlanejamento.a_pagar_vencido },
  {
    chave: "nao_distribuido",
    rotulo: "Custo sem título fora dos meses",
    explicacao: explicacoesPlanejamento.custo_sem_titulo_nao_distribuido,
  },
];

function linhaDaObra(resumo: ResumoProjecaoObra) {
  return {
    chave: resumo.centro_custo_id,
    rotulo: resumo.obra,
    href: `/fluxo/${resumo.centro_custo_id}`,
    celulas: {
      exposicao: (
        <span className="inline-flex flex-col items-end gap-1">
          <Valor valor={resumo.exposicao_maxima_projetada} />
          {resumo.exposicao_parcial && <Selo tipo="parcial">parcial</Selo>}
        </span>
      ),
      mes: resumo.mes_exposicao_maxima ? (
        formatarMes(resumo.mes_exposicao_maxima)
      ) : (
        <span className="text-suave">Sem aporte</span>
      ),
      conservadora: <Valor valor={resumo.exposicao_maxima_conservadora} />,
      pendente: <Valor valor={resumo.financiamento_pendente_total} />,
      vencido: <Valor valor={resumo.vencido_a_receber} />,
      a_pagar_vencido: <Valor valor={resumo.a_pagar_vencido} />,
      nao_distribuido:
        resumo.custo_sem_titulo_nao_distribuido === null ? (
          <span className="text-xs text-suave">{fraseMotivo(resumo.motivo_distribuicao ?? "orcamento_ausente")}</span>
        ) : (
          <Valor valor={resumo.custo_sem_titulo_nao_distribuido} />
        ),
    },
  };
}

// Consolidado: uma consulta a marts.resumo_projecao_obra, uma linha por obra liberada.
export default async function PaginaFluxo({ searchParams }: PageProps<"/fluxo">) {
  // A rota confere a sessão por conta própria; o proxy e o layout sozinhos não bastam.
  await exigirIdentidade();
  const obraPedida = lerIdCentro((await searchParams).obra);
  if (obraPedida) redirect(`/fluxo/${obraPedida}`);

  const [referencia, resumos, centros] = await Promise.all([
    carregarReferencia(),
    tentarConsulta(listarResumoProjecao(null)),
    tentarConsulta(listarCentrosCusto()),
  ]);
  const obras = (centros ?? []).filter((centro) => centro.tipo === "obra");
  const parciais = (resumos ?? []).filter((resumo) => resumo.exposicao_parcial);

  return (
    <>
      <header className="flex flex-col gap-2">
        <h1 className="font-serif text-[34px] font-semibold">Fluxo de caixa</h1>
        <p className="max-w-3xl text-suave">
          Dinheiro que entrou e saiu, e o que os contratos, títulos e liberações dizem que vai entrar e sair, mês a mês
          e pela data do caixa. Não é competência: para receita e custo do período, veja o DRE gerencial.
        </p>
        <AvisoCarga referencia={referencia} />
      </header>

      <form
        action="/fluxo"
        method="get"
        aria-label="Escolher obra"
        className="flex flex-col gap-3 rounded-xl border border-borda bg-superficie p-4 sm:flex-row sm:items-end"
      >
        <div className="flex min-w-0 flex-1 flex-col gap-1.5">
          <label htmlFor="fluxo-obra" className="text-sm font-medium">
            Obra
          </label>
          <select
            id="fluxo-obra"
            name="obra"
            defaultValue=""
            className="min-h-11 w-full rounded-lg border border-borda bg-superficie px-3"
          >
            <option value="">Todas as obras liberadas (consolidado)</option>
            {obras.map((obra) => (
              <option key={obra.id} value={obra.id}>
                {obra.nome}
              </option>
            ))}
          </select>
        </div>
        <button
          type="submit"
          className="min-h-11 cursor-pointer rounded-lg bg-menu px-4 font-semibold text-menu-texto hover:bg-menu-ativo"
        >
          Ver o mês a mês
        </button>
      </form>

      <Bloco
        id="consolidado"
        titulo="Consolidado das obras liberadas"
        contexto={`Projeção sem novas vendas, com posição em ${formatarData(referencia.dataReferencia)}. Origem: parcelas, títulos, pagamentos e complementos manuais de financiamento.`}
      >
        <p className="max-w-3xl text-sm">{mensagensPlanejamento.fluxo.naoESaldoBancario}</p>
        <p className="max-w-3xl text-sm text-suave">{mensagensPlanejamento.fluxo.consolidadoPorObra}</p>
        {parciais.length > 0 && (
          <Aviso titulo="Aporte parcial">
            {parciais.map((resumo) => resumo.obra).join(", ")}: {mensagensPlanejamento.fluxo.custoNaoDistribuido}
          </Aviso>
        )}
        {resumos === null && <ErroBloco />}
        {resumos?.length === 0 && <p>{mensagensPlanejamento.fluxo.semObras}</p>}
        {resumos && resumos.length > 0 && (
          <TabelaPlanejamento
            legenda="Aporte e pendências da projeção por obra"
            rotuloPrimeira="Obra"
            colunas={colunas}
            linhas={resumos.map(linhaDaObra)}
          />
        )}
      </Bloco>
    </>
  );
}
