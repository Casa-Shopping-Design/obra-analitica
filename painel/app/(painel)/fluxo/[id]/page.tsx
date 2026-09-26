import type { Metadata } from "next";
import { exigirIdentidade } from "@/lib/consultas/identidade";
import Link from "next/link";
import { SeletorCenario } from "@/componentes/SeletorCenario";
import { Aviso, Bloco, ErroBloco } from "@/componentes/financeiro/Aviso";
import { AvisoCarga } from "@/componentes/financeiro/AvisoCarga";
import { Selo } from "@/componentes/financeiro/Selo";
import { CartaoPlanejamento } from "@/componentes/planejamento/CartaoPlanejamento";
import { GraficoFluxoProjetado } from "@/componentes/planejamento/GraficoFluxoProjetado";
import { GraficoResposta } from "@/componentes/planejamento/GraficoResposta";
import { montarSerieProjetada } from "@/componentes/planejamento/serie-projetada";
import { TabelaPlanejamento, type LinhaPlanejamento } from "@/componentes/planejamento/TabelaPlanejamento";
import { Valor } from "@/componentes/planejamento/Valor";
import {
  cenariosAtraso,
  listarFluxoProjetado,
  listarResumoProjecao,
  simularFluxo,
  type LinhaFluxoProjetado,
  type MesesAtraso,
} from "@/lib/consultas/fluxo";
import { carregarReferencia, tentarConsulta } from "@/lib/consultas/referencia";
import { formatarData, formatarMes } from "@/lib/formatar";
import { fraseMotivo, mensagens } from "@/lib/mensagens";
import { explicacoesPlanejamento, mensagensPlanejamento } from "@/lib/mensagens-planejamento";
import { lerIdCentro, lerOpcao, mesDaData, mesPorExtenso } from "@/lib/periodo";
import { juntarBaseESimulacao } from "@/lib/simulacao";
import { janelasPlanejamento, limitesDaJanela, type Janela } from "@/componentes/planejamento/regras-planejamento";

export const metadata: Metadata = { title: "Fluxo de caixa da obra" };

const opcoesJanela = Object.keys(janelasPlanejamento) as Janela[];

function lerCenario(valor: string | string[] | undefined): MesesAtraso {
  const meses = Number(Array.isArray(valor) ? valor[0] : valor);
  return cenariosAtraso.find((opcao) => opcao === meses) ?? 0;
}

const e = explicacoesPlanejamento;
const naoCarregado = <span className="text-base font-normal text-suave">Não carregado</span>;
const colunasMensais = [
  { chave: "recebido_direto", rotulo: "Recebido do comprador" },
  { chave: "recebido_financiamento", rotulo: "Recebido de financiamento" },
  { chave: "credito_producao_recebido", rotulo: "Crédito à produção recebido" },
  { chave: "previsto_direto", rotulo: "Previsto do comprador", explicacao: e.previsto_direto },
  {
    chave: "previsto_financiamento_elegivel",
    rotulo: "Financiamento elegível",
    explicacao: e.previsto_financiamento_elegivel,
  },
  {
    chave: "previsto_financiamento_pendente",
    rotulo: "Financiamento pendente",
    explicacao: e.previsto_financiamento_pendente,
  },
  {
    chave: "credito_producao_previsto",
    rotulo: "Crédito à produção previsto",
    explicacao: e.credito_producao_previsto,
  },
  { chave: "pago", rotulo: "Pago" },
  { chave: "a_pagar", rotulo: "A pagar" },
  { chave: "a_pagar_vencido", rotulo: "A pagar vencido", explicacao: e.a_pagar_vencido },
  {
    chave: "custo_sem_titulo_distribuido",
    rotulo: "Custo sem título distribuído",
    explicacao: e.custo_sem_titulo_distribuido,
  },
  { chave: "saldo_mes", rotulo: "Saldo do mês" },
  { chave: "caixa_gerado_acumulado", rotulo: "Caixa gerado acumulado", explicacao: e.caixa_gerado_acumulado },
  { chave: "necessidade_aporte_acumulada", rotulo: "Aporte necessário", explicacao: e.necessidade_aporte_acumulada },
  { chave: "aporte_incremental_mes", rotulo: "Aporte do mês", explicacao: e.aporte_incremental_mes },
] as const;

function linhasMensais(fluxo: LinhaFluxoProjetado[], mesReferencia: string): LinhaPlanejamento[] {
  return fluxo.map((linha) => {
    const mes = linha.competencia.slice(0, 10);
    return {
      chave: mes,
      rotulo: (
        <span className="inline-flex flex-col">
          {formatarMes(mes)}
          <span className="text-xs text-suave">
            {linha.eh_passado ? "Realizado" : mes === mesReferencia ? "Referência" : "Previsto"}
          </span>
        </span>
      ),
      destaque: mes === mesReferencia,
      celulas: Object.fromEntries(
        colunasMensais.map((coluna) => [coluna.chave, <Valor key={coluna.chave} valor={linha[coluna.chave]} />]),
      ),
    };
  });
}

function ObraNaoEncontrada() {
  return (
    <>
      <h1 className="font-serif text-[34px] font-semibold">{mensagens.obra.naoEncontrada}</h1>
      <p>
        <Link href="/fluxo" className="underline underline-offset-4 hover:text-menu">
          Voltar para o fluxo consolidado
        </Link>
      </p>
    </>
  );
}

export default async function PaginaFluxoObra({ params, searchParams }: PageProps<"/fluxo/[id]">) {
  // A rota confere a sessão por conta própria; o proxy e o layout sozinhos não bastam.
  await exigirIdentidade();
  const { id } = await params;
  const filtros = await searchParams;
  const centroId = lerIdCentro(id);
  if (!centroId) return <ObraNaoEncontrada />;
  const mesesAtraso = lerCenario(filtros.cenario);
  const janela = lerOpcao(filtros.janela, opcoesJanela, "longa");

  const referencia = await carregarReferencia();
  const mesReferencia = mesDaData(referencia.dataReferencia);
  const limites = limitesDaJanela(janela, referencia.dataReferencia);
  // Até três consultas em paralelo: resumo, meses da obra e, só com atraso escolhido, o cenário.
  const [resumos, fluxo, cenario] = await Promise.all([
    tentarConsulta(listarResumoProjecao(centroId)),
    tentarConsulta(listarFluxoProjetado({ centroCustoId: centroId })),
    mesesAtraso > 0
      ? tentarConsulta(simularFluxo(centroId, { atraso_liberacao_bancaria_meses: mesesAtraso }))
      : Promise.resolve(null),
  ]);
  if (resumos !== null && resumos.length === 0) return <ObraNaoEncontrada />;
  const resumo = resumos?.[0] ?? null;
  const doMes = fluxo?.find((linha) => linha.competencia.slice(0, 10) === mesReferencia) ?? null;
  const naJanela = (fluxo ?? []).filter((linha) => {
    const mes = linha.competencia.slice(0, 10);
    return (!limites.inicio || mes >= limites.inicio) && (!limites.fim || mes <= limites.fim);
  });

  return (
    <>
      <header className="flex flex-col gap-2">
        <Link href="/fluxo" className="text-sm text-suave underline underline-offset-4 hover:text-texto">
          Fluxo consolidado
        </Link>
        <h1 className="font-serif text-[34px] font-semibold">{resumo?.obra ?? "Fluxo de caixa da obra"}</h1>
        <p className="max-w-3xl text-suave">
          Caixa da obra mês a mês, pela data do dinheiro. Realizado, carteira contratada e desembolsos separados.
        </p>
        <nav aria-label="Atalhos da obra" className="flex flex-wrap gap-x-5 gap-y-2 text-sm font-semibold">
          <Link href={`/fluxo/${centroId}/simular`} className="underline underline-offset-4 hover:text-menu">
            Simular um cenário
          </Link>
          <Link href={`/planejamento?obra=${centroId}`} className="underline underline-offset-4 hover:text-menu">
            Planejamento e metas
          </Link>
          <Link
            href={`/planejamento/financiamento?obra=${centroId}`}
            className="underline underline-offset-4 hover:text-menu"
          >
            Financiamento e liberações
          </Link>
          <Link href={`/obras/${centroId}`} className="underline underline-offset-4 hover:text-menu">
            Resumo da obra
          </Link>
        </nav>
        <AvisoCarga referencia={referencia} />
      </header>

      <section aria-label="Resumo do caixa" className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
        <CartaoPlanejamento
          rotulo="Caixa gerado acumulado"
          explicacao={e.caixa_gerado_acumulado}
          valor={
            doMes ? <Valor valor={doMes.caixa_gerado_acumulado} /> : <span className="text-suave">Sem movimento</span>
          }
          contexto={`Em ${mesPorExtenso(mesReferencia)}, com o previsto do mês. Não é saldo bancário.`}
        />
        <CartaoPlanejamento
          rotulo="Maior aporte necessário"
          explicacao={e.exposicao_maxima_projetada}
          valor={resumo ? <Valor valor={resumo.exposicao_maxima_projetada} /> : naoCarregado}
          selo={
            resumo?.exposicao_parcial ? (
              <Selo tipo="parcial">parcial: há custo sem título fora dos meses</Selo>
            ) : undefined
          }
          contexto={
            resumo?.mes_exposicao_maxima
              ? `Pior caixa em ${mesPorExtenso(resumo.mes_exposicao_maxima)}. Previsão, sem novas vendas.`
              : "A projeção não fica negativa. Previsão, sem novas vendas."
          }
        />
        <CartaoPlanejamento
          rotulo="Aporte do mês"
          explicacao={e.aporte_incremental_mes}
          valor={doMes ? <Valor valor={doMes.aporte_incremental_mes} /> : naoCarregado}
          contexto={
            doMes ? (
              <>
                Aporte acumulado até {mesPorExtenso(mesReferencia)}:{" "}
                <Valor valor={doMes.necessidade_aporte_acumulada} />.
              </>
            ) : undefined
          }
        />
        <CartaoPlanejamento
          rotulo="Sem financiamento pendente"
          explicacao={e.caixa_gerado_conservador}
          valor={resumo ? <Valor valor={resumo.exposicao_maxima_conservadora} /> : naoCarregado}
          contexto="Maior aporte se os compradores ainda sem aprovação do banco não forem liberados."
        />
        <CartaoPlanejamento
          rotulo="Vencido a receber"
          explicacao={e.vencido_a_receber}
          valor={resumo ? <Valor valor={resumo.vencido_a_receber} /> : naoCarregado}
          contexto="Fora do caixa previsto até ser recebido."
        />
        <CartaoPlanejamento
          rotulo="A pagar vencido"
          explicacao={e.a_pagar_vencido}
          valor={resumo ? <Valor valor={resumo.a_pagar_vencido} /> : naoCarregado}
          contexto={`Entra no caixa de ${mesPorExtenso(mesReferencia)}.`}
        />
      </section>

      {resumo?.exposicao_parcial && (
        <Aviso titulo="Custo sem título fora dos meses">
          <p>
            {resumo.custo_sem_titulo_nao_distribuido === null
              ? mensagensPlanejamento.fluxo.semOrcamento
              : mensagensPlanejamento.fluxo.custoNaoDistribuido}{" "}
            {resumo.custo_sem_titulo_nao_distribuido !== null && (
              <>
                Valor fora dos meses: <Valor valor={resumo.custo_sem_titulo_nao_distribuido} />.{" "}
              </>
            )}
            {resumo.motivo_distribuicao && fraseMotivo(resumo.motivo_distribuicao)}{" "}
            <Link
              href={`/planejamento?obra=${centroId}#premissa`}
              className="font-semibold underline underline-offset-4"
            >
              Cadastrar a premissa de meses
            </Link>
          </p>
        </Aviso>
      )}

      <Bloco
        id="mes-a-mes"
        titulo="Mês a mês"
        contexto={`Posição em ${formatarData(referencia.dataReferencia)}. Entrada vencida fica fora; saída vencida entra no mês de referência.`}
      >
        <form method="get" aria-label="Meses mostrados" className="flex flex-col gap-2 sm:flex-row sm:items-end">
          <div className="flex flex-col gap-1.5">
            <label htmlFor="fluxo-janela" className="text-sm font-medium">
              Meses mostrados
            </label>
            <select
              id="fluxo-janela"
              name="janela"
              defaultValue={janela}
              className="min-h-11 rounded-lg border border-borda bg-superficie px-3"
            >
              {opcoesJanela.map((opcao) => (
                <option key={opcao} value={opcao}>
                  {janelasPlanejamento[opcao].rotulo}
                </option>
              ))}
            </select>
          </div>
          <button
            type="submit"
            className="min-h-11 cursor-pointer rounded-lg border border-borda bg-superficie px-4 font-semibold hover:border-texto"
          >
            Mostrar
          </button>
        </form>
        {fluxo === null && <ErroBloco />}
        {fluxo?.length === 0 && <p>{mensagensPlanejamento.fluxo.semProjecao}</p>}
        {naJanela.length > 0 && (
          <>
            <GraficoFluxoProjetado serie={montarSerieProjetada(naJanela)} mesReferencia={mesReferencia} />
            <p className="text-sm text-suave">
              O gráfico repete os totais da tabela abaixo. Cheio é realizado; hachurado é o mês de referência e os
              seguintes, com o realizado do mês e o previsto juntos.
            </p>
            <TabelaPlanejamento
              legenda="Fluxo de caixa projetado da obra, mês a mês, em reais"
              rotuloPrimeira="Mês"
              colunas={[...colunasMensais]}
              linhas={linhasMensais(naJanela, mesReferencia)}
            />
          </>
        )}
      </Bloco>

      <Bloco
        id="cenario"
        titulo="Atraso nas liberações do banco"
        contexto="Cenário rápido: desloca o financiamento previsto e o crédito à produção. Não grava nada."
      >
        <SeletorCenario mesesAtraso={mesesAtraso} />
        {mesesAtraso > 0 && cenario === null && (
          <p role="alert" className="text-alerta">
            {mensagensPlanejamento.simulacao.indisponivel}
          </p>
        )}
        {mesesAtraso > 0 && cenario && fluxo && (
          <GraficoResposta
            idBase="cenario-atraso"
            grafico={{
              tipo: "linhas",
              titulo: `Caixa gerado acumulado com ${mesesAtraso} ${mesesAtraso === 1 ? "mês" : "meses"} de atraso`,
              eixo: "competencia",
              formatoEixo: "mes",
              series: [
                { chave: "base", rotulo: "Projeção de hoje", estilo: "cheio" },
                { chave: "simulado", rotulo: "Com atraso (simulação)", estilo: "tracejado" },
              ],
              pontos: juntarBaseESimulacao(
                naJanela,
                cenario.filter((linha) => naJanela.some((base) => base.competencia === linha.competencia)),
              ),
            }}
          />
        )}
        {mesesAtraso > 0 && cenario && (
          <TabelaPlanejamento
            legenda="Cenário de atraso: caixa gerado acumulado e aporte por mês"
            rotuloPrimeira="Mês"
            colunas={[
              { chave: "carteira", rotulo: "Carteira prevista" },
              { chave: "caixa", rotulo: "Caixa gerado acumulado" },
              { chave: "aporte", rotulo: "Aporte necessário" },
            ]}
            linhas={cenario
              .filter((linha) => linha.competencia.slice(0, 10) >= mesReferencia)
              .map((linha) => ({
                chave: linha.competencia,
                rotulo: formatarMes(linha.competencia),
                celulas: {
                  carteira: <Valor valor={linha.carteira_prevista} />,
                  caixa: <Valor valor={linha.caixa_gerado_acumulado} />,
                  aporte: <Valor valor={linha.necessidade_aporte_acumulada} />,
                },
              }))}
          />
        )}
      </Bloco>
    </>
  );
}
