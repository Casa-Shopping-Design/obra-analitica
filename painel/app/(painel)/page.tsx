import type { Metadata } from "next";
import Link from "next/link";
import { IndicadoresObra, type AporteProjetado } from "@/componentes/CartaoIndicador";
import { ExplicacaoIndicador } from "@/componentes/ExplicacaoIndicador";
import { AvisoCarga } from "@/componentes/financeiro/AvisoCarga";
import { ErroBloco } from "@/componentes/financeiro/Aviso";
import { CartaoFinanceiro } from "@/componentes/financeiro/CartaoFinanceiro";
import { estadoDoValor, type EstadoValor } from "@/componentes/financeiro/montar-dre";
import { Selo } from "@/componentes/financeiro/Selo";
import { ValorEstado } from "@/componentes/financeiro/ValorEstado";
import { TabelaObras, type AportesPorObra } from "@/componentes/TabelaObras";
import type { CustoObraResumo } from "@/lib/consultas/despesas";
import { listarCustoResumo } from "@/lib/consultas/despesas";
import { contarPendenciasClassificacao, listarDrePeriodo } from "@/lib/consultas/dre";
import { listarResumoProjecao, type ResumoProjecaoObra } from "@/lib/consultas/fluxo";
import { exigirIdentidade } from "@/lib/consultas/identidade";
import { listarPosicaoObras, type PosicaoObra } from "@/lib/consultas/posicao";
import { listarResumoReceitas, type ResumoReceitasObra } from "@/lib/consultas/receitas";
import { carregarReferencia, tentarConsulta } from "@/lib/consultas/referencia";
import type { ChaveExplicacao } from "@/lib/explicacoes";
import { formatarMes } from "@/lib/formatar";
import { mensagens } from "@/lib/mensagens";
import { calcularPeriodo, proximoMes } from "@/lib/periodo";

export const metadata: Metadata = { title: "Visão geral" };

type Complementos = {
  receitas: Map<string, ResumoReceitasObra> | null;
  custos: Map<string, CustoObraResumo> | null;
};

// Junção por chave para achar a linha de cada obra; nulo quando a consulta do bloco falhou.
function porCentro<T extends { centro_custo_id: string }>(linhas: T[] | null): Map<string, T> | null {
  return linhas ? new Map(linhas.map((linha) => [linha.centro_custo_id, linha])) : null;
}

function Item({ rotulo, chave, children }: { rotulo: string; chave: ChaveExplicacao; children: React.ReactNode }) {
  return (
    <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
      <dt className="flex items-center gap-1.5 text-sm text-suave">
        {rotulo}
        <ExplicacaoIndicador chave={chave} rotulo={rotulo} />
      </dt>
      <dd className="text-right font-semibold tabular-nums">{children}</dd>
    </div>
  );
}

function Valor({ estado }: { estado: EstadoValor }) {
  return <ValorEstado estado={estado} mostrarMotivo={false} />;
}

// Uma fonte só para o aporte: a projeção. Junção por centro_custo_id; nulo quando a consulta falhou.
function aportesPorObra(linhas: ResumoProjecaoObra[] | null): AportesPorObra | null {
  if (!linhas) return null;
  return Object.fromEntries(
    linhas.map((linha) => [
      linha.centro_custo_id,
      { valor: linha.exposicao_maxima_projetada, parcial: linha.exposicao_parcial },
    ]),
  );
}

function aporteDaObra(aportes: AportesPorObra | null, centroCustoId: string): AporteProjetado {
  return aportes?.[centroCustoId] ?? null;
}

const semDado = <span className="font-normal text-suave">Não carregado</span>;

function ComplementosObra({
  obra,
  complementos,
  mesSeguinte,
}: {
  obra: PosicaoObra;
  complementos: Complementos;
  mesSeguinte: string;
}) {
  const receitas = complementos.receitas?.get(obra.centro_custo_id);
  const custos = complementos.custos?.get(obra.centro_custo_id);
  return (
    <div className="flex flex-col gap-2 border-t border-borda pt-4">
      <dl className="flex flex-col gap-2">
        <Item rotulo="VGV contratado" chave="vgv_contratado_ativo">
          {receitas ? <Valor estado={estadoDoValor(receitas.vgv_contratado_ativo)} /> : semDado}
        </Item>
        <Item rotulo={`Entrada direta em ${formatarMes(mesSeguinte)}`} chave="previsto_proximo_mes_direto">
          {receitas ? <Valor estado={estadoDoValor(receitas.previsto_proximo_mes_direto)} /> : semDado}
        </Item>
        <Item rotulo={`Financiamento em ${formatarMes(mesSeguinte)}`} chave="previsto_proximo_mes_financiamento">
          {receitas ? <Valor estado={estadoDoValor(receitas.previsto_proximo_mes_financiamento)} /> : semDado}
        </Item>
        <Item rotulo="Desvio sobre o orçamento" chave="desvio">
          {custos ? (
            <Valor
              estado={
                custos.desvio === null
                  ? estadoDoValor(null, false, custos.motivo ?? "orcamento_ausente")
                  : estadoDoValor(custos.desvio)
              }
            />
          ) : (
            semDado
          )}
        </Item>
      </dl>
      <p className="flex flex-wrap gap-x-4 gap-y-1 pt-1 text-sm">
        <Link href={`/receitas?obra=${obra.centro_custo_id}`} className="underline underline-offset-4 hover:text-menu">
          Receitas da obra
        </Link>
        <Link href={`/despesas?obra=${obra.centro_custo_id}`} className="underline underline-offset-4 hover:text-menu">
          Despesas da obra
        </Link>
      </p>
    </div>
  );
}

// Sete consultas em paralelo depois da data de referência; cada bloco falha sozinho.
export default async function PaginaVisaoGeral() {
  await exigirIdentidade();
  const posicaoPedido = tentarConsulta(listarPosicaoObras());
  const referencia = await carregarReferencia();
  const ano = calcularPeriodo("ano", referencia.dataReferencia, referencia.dataReferencia);
  const mesSeguinte = proximoMes(referencia.dataReferencia);

  const [obras, receitas, custos, projecao, dreAno, pendencias] = await Promise.all([
    posicaoPedido,
    tentarConsulta(listarResumoReceitas(null)),
    tentarConsulta(listarCustoResumo(null)),
    tentarConsulta(listarResumoProjecao(null)),
    tentarConsulta(listarDrePeriodo(ano.inicio, ano.fim, null)),
    tentarConsulta(contarPendenciasClassificacao()),
  ]);
  const complementos: Complementos = {
    receitas: porCentro(receitas),
    custos: porCentro(custos),
  };
  const aportes = aportesPorObra(projecao);
  const resultadoAno = dreAno?.find((linha) => linha.linha_codigo === "resultado_gerencial");

  return (
    <>
      <header className="flex flex-col gap-2">
        <h1 className="font-serif text-[34px] font-semibold">Visão geral</h1>
        <AvisoCarga referencia={referencia} />
      </header>

      <section aria-label="Resultado e classificação" className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        {dreAno === null ? (
          <ErroBloco />
        ) : (
          <CartaoFinanceiro
            rotulo="Resultado gerencial do ano"
            chave="resultado_gerencial"
            valores={[
              {
                estado: resultadoAno
                  ? estadoDoValor(resultadoAno.valor_periodo, resultadoAno.disponivel, resultadoAno.motivo)
                  : { tipo: "ausente" },
              },
            ]}
            textoAusente="Sem lançamento no ano"
            contexto={
              <>
                {ano.rotulo}, por competência, todas as obras liberadas.{" "}
                <Link href="/dre" className="underline underline-offset-4 hover:text-menu">
                  Abrir o DRE gerencial
                </Link>
              </>
            }
          />
        )}
        {pendencias === null ? (
          <ErroBloco />
        ) : (
          <CartaoFinanceiro
            rotulo="Contas sem categoria"
            chave="pendencia_classificacao"
            valores={[]}
            destaque={pendencias === 0 ? "Nenhuma" : pendencias.toLocaleString("pt-BR")}
            selo={pendencias > 0 ? <Selo tipo="parcial">o DRE pode mudar</Selo> : undefined}
            contexto={
              <>
                Contas da origem ainda sem categoria gerencial.{" "}
                {pendencias > 0 && (
                  <Link href="/dre#pendencias" className="underline underline-offset-4 hover:text-menu">
                    Ver as contas
                  </Link>
                )}
              </>
            }
          />
        )}
      </section>

      {obras === null && (
        <p role="alert" className="text-alerta">
          {mensagens.posicao.indisponivel}
        </p>
      )}
      {obras?.length === 0 && <p>{mensagens.posicao.semObras}</p>}
      {obras && obras.length > 0 && (
        <>
          <ul aria-label="Obras" className="grid grid-cols-1 gap-4 xl:grid-cols-2 2xl:grid-cols-3">
            {obras.map((obra) => (
              <li key={obra.centro_custo_id}>
                <article
                  aria-labelledby={`obra-${obra.centro_custo_id}`}
                  className="flex h-full flex-col gap-5 rounded-xl border border-borda bg-superficie p-5"
                >
                  <h2 id={`obra-${obra.centro_custo_id}`} className="font-serif text-xl font-semibold">
                    <Link
                      href={`/obras/${obra.centro_custo_id}`}
                      className="underline underline-offset-4 hover:text-menu"
                    >
                      {obra.obra}
                    </Link>
                  </h2>
                  <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
                    <IndicadoresObra posicao={obra} aporte={aporteDaObra(aportes, obra.centro_custo_id)} />
                  </div>
                  <ComplementosObra obra={obra} complementos={complementos} mesSeguinte={mesSeguinte} />
                </article>
              </li>
            ))}
          </ul>
          <TabelaObras obras={obras} aportes={aportes ?? {}} />
        </>
      )}
    </>
  );
}
