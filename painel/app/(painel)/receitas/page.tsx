import type { Metadata } from "next";
import { AvisoCarga } from "@/componentes/financeiro/AvisoCarga";
import { Bloco, ErroBloco } from "@/componentes/financeiro/Aviso";
import { CartaoFinanceiro } from "@/componentes/financeiro/CartaoFinanceiro";
import { FiltrosDemonstrativo } from "@/componentes/financeiro/FiltrosDemonstrativo";
import { GraficoRecebimentos } from "@/componentes/financeiro/GraficoRecebimentos";
import { estadoDoValor } from "@/componentes/financeiro/montar-dre";
import {
  juntarRecebimentoMensal,
  origensRecebivel,
  rotulosOrigem,
  rotulosSituacao,
  situacoesParcela,
  valorDaOrigem,
} from "@/componentes/financeiro/receitas-tela";
import { NavegacaoPaginas, TabelaCarteira } from "@/componentes/financeiro/TabelaCarteira";
import { TabelaPorCentro, type LinhaCentro } from "@/componentes/financeiro/TabelaPorCentro";
import { ValorEstado } from "@/componentes/financeiro/ValorEstado";
import {
  listarCarteira,
  listarRecebimentoMensal,
  listarRecebimentoPeriodo,
  buscarResumoReceitasConsolidado,
  listarRecebimentoMensalConsolidado,
  listarResumoReceitas,
  type FiltrosCarteira,
  type LinhaRecebimentoPeriodo,
  type ResumoReceitasObra,
} from "@/lib/consultas/receitas";
import { exigirIdentidade } from "@/lib/consultas/identidade";
import { carregarReferencia, listarCentrosCusto, tentarConsulta } from "@/lib/consultas/referencia";
import { formatarData, formatarMes } from "@/lib/formatar";
import { mensagens } from "@/lib/mensagens";
import {
  lerData,
  lerIdCentro,
  lerOpcao,
  lerPagina,
  lerPeriodo,
  mesPorExtenso,
  montarEndereco,
  montarPaginacao,
  proximoMes,
  somarMeses,
} from "@/lib/periodo";
import { buscarPreferenciasTenant } from "@/lib/consultas/configuracao";

export const metadata: Metadata = { title: "Receitas" };

const classeCampo = "min-h-11 w-full min-w-0 rounded-lg border border-borda bg-superficie px-3";

function valor(numero: number | null) {
  return <ValorEstado estado={estadoDoValor(numero)} />;
}

function par(direta: number, financiamento: number) {
  return [
    { rotulo: rotulosOrigem.direta, estado: estadoDoValor(direta) },
    { rotulo: rotulosOrigem.financiamento, estado: estadoDoValor(financiamento) },
  ];
}

function linhasPorObra(resumos: ResumoReceitasObra[]): LinhaCentro[] {
  return resumos.map((resumo) => ({
    id: resumo.centro_custo_id,
    nome: resumo.obra,
    href: `/receitas?obra=${resumo.centro_custo_id}`,
    celulas: {
      vgv: valor(resumo.vgv_contratado_ativo),
      contratos: `${resumo.contratos_ativos} ativos, ${resumo.contratos_distratados} distratados`,
      recebido_direto: valor(resumo.recebido_direto),
      recebido_financiamento: valor(resumo.recebido_financiamento),
      vencido_direto: valor(resumo.vencido_direto),
      vencido_financiamento: valor(resumo.vencido_financiamento),
      a_vencer_direto: valor(resumo.a_vencer_direto),
      a_vencer_financiamento: valor(resumo.a_vencer_financiamento),
      proximo_direto: valor(resumo.previsto_proximo_mes_direto),
      proximo_financiamento: valor(resumo.previsto_proximo_mes_financiamento),
      distratado: valor(resumo.saldo_distratado),
    },
  }));
}

function CartoesRecebidoPeriodo({
  linhas,
  rotuloPeriodo,
}: {
  linhas: LinhaRecebimentoPeriodo[] | null;
  rotuloPeriodo: string;
}) {
  if (linhas === null) return <ErroBloco />;
  return (
    <CartaoFinanceiro
      rotulo={`Recebido em ${rotuloPeriodo}`}
      chave="recebido_periodo"
      valores={origensRecebivel.map((origem) => ({
        rotulo: rotulosOrigem[origem],
        estado: estadoDoValor(valorDaOrigem(linhas, origem, "recebido")),
      }))}
      textoAusente="Nenhum no período"
      contexto="Pela data do recebimento. Origem: baixas das parcelas dos contratos."
    />
  );
}

type TotaisReceitas = Omit<ResumoReceitasObra, "tenant_id" | "centro_custo_id" | "obra" | "tipo_centro">;

// Os mesmos cartões para uma obra e para o consolidado; os totais vêm prontos do banco.
function CartoesReceitas({
  totais,
  recebidoPeriodo,
  rotuloPeriodo,
}: {
  totais: TotaisReceitas;
  recebidoPeriodo: LinhaRecebimentoPeriodo[] | null;
  rotuloPeriodo: string;
}) {
  const dataReferencia = totais.data_referencia;
  const mesSeguinte = proximoMes(dataReferencia);
  const posicaoEm = `Posição em ${formatarData(dataReferencia)}`;
  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
      <CartaoFinanceiro
        rotulo="VGV contratado"
        chave="vgv_contratado_ativo"
        valores={[{ estado: estadoDoValor(totais.vgv_contratado_ativo) }]}
        contexto={`${posicaoEm}. ${totais.contratos_ativos} contratos ativos, ${totais.contratos_distratados} distratados.`}
      />
      <CartoesRecebidoPeriodo linhas={recebidoPeriodo} rotuloPeriodo={rotuloPeriodo} />
      <CartaoFinanceiro
        rotulo="Recebido desde o início"
        chave="recebido_acumulado"
        valores={par(totais.recebido_direto, totais.recebido_financiamento)}
        contexto={`${posicaoEm}. Pela data do recebimento.`}
      />
      <CartaoFinanceiro
        rotulo="Vencido e não pago"
        chave="vencido_receitas"
        valores={par(totais.vencido_direto, totais.vencido_financiamento)}
        contexto={`Vencimento antes de ${formatarData(dataReferencia)}. Fica fora do caixa previsto.`}
      />
      <CartaoFinanceiro
        rotulo="A vencer"
        chave="a_vencer_receitas"
        valores={par(totais.a_vencer_direto, totais.a_vencer_financiamento)}
        contexto={`Vencimento de ${formatarData(dataReferencia)} em diante. Contrato distratado não entra.`}
      />
      <CartaoFinanceiro
        rotulo={`Previsto para ${mesPorExtenso(mesSeguinte)}`}
        chave="previsto_proximo_mes"
        valores={par(totais.previsto_proximo_mes_direto, totais.previsto_proximo_mes_financiamento)}
        contexto={`Mês seguinte ao da data de referência (${formatarData(dataReferencia)}). Parcela já vencida não entra.`}
      />
      <CartaoFinanceiro
        rotulo="Saldo de contratos distratados"
        chave="saldo_distratado"
        valores={[{ estado: estadoDoValor(totais.saldo_distratado) }]}
        contexto={`${posicaoEm}. Fora da carteira; o que foi pago antes do distrato continua no recebido.`}
      />
    </div>
  );
}

export default async function PaginaReceitas({ searchParams }: PageProps<"/receitas">) {
  await exigirIdentidade();
  const filtrosUrl = await searchParams;
  const centrosPedido = tentarConsulta(listarCentrosCusto());
  const preferenciasPedido = buscarPreferenciasTenant();
  const referencia = await carregarReferencia();
  const centros = await centrosPedido;

  const dataReferencia = referencia.dataReferencia;
  const periodo = lerPeriodo(filtrosUrl, dataReferencia, (await preferenciasPedido).periodoPadrao);
  const centroPedido = lerIdCentro(filtrosUrl.obra);
  const centro = centros?.find((item) => item.id === centroPedido && item.tipo === "obra") ?? null;
  const centroNaoEncontrado = centroPedido !== null && centros !== null && centro === null;
  const centroId = centroNaoEncontrado ? null : centroPedido;
  const mesSeguinte = proximoMes(dataReferencia);

  const filtrosCarteira: FiltrosCarteira = {
    centroCustoId: centroId,
    situacao: lerOpcao(filtrosUrl.situacao, [...situacoesParcela, ""] as const, "") || null,
    origem: lerOpcao(filtrosUrl.origem, [...origensRecebivel, ""] as const, "") || null,
    vencimentoDe: lerData(filtrosUrl.venc_de),
    vencimentoAte: lerData(filtrosUrl.venc_ate),
    pagina: lerPagina(filtrosUrl.pagina),
  };
  const filtrosBase = { obra: centroId, periodo: periodo.tipo, mes: periodo.mes.slice(0, 7) };
  const filtrosComCarteira = {
    ...filtrosBase,
    situacao: filtrosCarteira.situacao,
    origem: filtrosCarteira.origem,
    venc_de: filtrosCarteira.vencimentoDe,
    venc_ate: filtrosCarteira.vencimentoAte,
  };

  const cabecalho = (
    <header className="flex flex-col gap-2">
      <h1 className="font-serif text-[34px] font-semibold">Receitas</h1>
      <p className="max-w-3xl text-suave">
        Vendas contratadas, dinheiro recebido e parcelas em aberto, sempre com a entrada direta separada do
        financiamento. Venda não é receita do DRE nem dinheiro no caixa.
      </p>
      <AvisoCarga referencia={referencia} />
    </header>
  );
  const filtros = (
    <FiltrosDemonstrativo
      acao="/receitas"
      centros={centros ?? []}
      centroSelecionado={centroId}
      periodo={periodo}
      dataReferencia={dataReferencia}
    />
  );

  if (centroNaoEncontrado) {
    return (
      <>
        {cabecalho}
        {filtros}
        <p role="alert">{mensagens.obra.naoEncontrada}</p>
      </>
    );
  }

  // Evolução: 12 meses até o fim do período e 12 depois, para mostrar o previsto das parcelas.
  const inicioEvolucao = somarMeses(periodo.fim, -11);
  const fimEvolucao = somarMeses(periodo.fim, 12);
  const [resumos, consolidado, recebidoPeriodo, mensal, carteira] = await Promise.all([
    tentarConsulta(listarResumoReceitas(centroId)),
    centroId ? Promise.resolve(null) : tentarConsulta(buscarResumoReceitasConsolidado()),
    tentarConsulta(listarRecebimentoPeriodo(periodo.inicio, periodo.fim, centroId)),
    tentarConsulta(
      centroId
        ? listarRecebimentoMensal(centroId, inicioEvolucao, fimEvolucao)
        : listarRecebimentoMensalConsolidado(inicioEvolucao, fimEvolucao),
    ),
    tentarConsulta(listarCarteira(filtrosCarteira)),
  ]);

  const resumoObra = centroId && resumos?.length === 1 ? resumos[0] : null;
  const nomeRecorte = centro?.nome ?? "Consolidado das obras liberadas";
  const posicaoEm = `Posição em ${formatarData(dataReferencia)}`;
  const paginacao = carteira ? montarPaginacao(filtrosCarteira.pagina, carteira.total) : null;

  return (
    <>
      {cabecalho}
      {filtros}

      <Bloco
        id="resumo"
        titulo={nomeRecorte}
        contexto={`${posicaoEm}. Origem: contratos de venda e parcelas a receber.`}
      >
        {resumos === null && <ErroBloco />}
        {resumos?.length === 0 && <p>{mensagens.receitas.semReceitas}</p>}

        {resumoObra && (
          <CartoesReceitas totais={resumoObra} recebidoPeriodo={recebidoPeriodo} rotuloPeriodo={periodo.rotulo} />
        )}

        {!centroId && resumos && resumos.length > 0 && (
          <>
            {consolidado === null && <ErroBloco />}
            {consolidado && (
              <CartoesReceitas totais={consolidado} recebidoPeriodo={recebidoPeriodo} rotuloPeriodo={periodo.rotulo} />
            )}
            <h3 className="font-semibold">Por obra</h3>
            <p className="text-sm text-suave">
              Previsto para {mesPorExtenso(mesSeguinte)}: mês seguinte ao da data de referência (
              {formatarData(dataReferencia)}). Clique na obra para ver só os números dela.
            </p>
            <TabelaPorCentro
              legenda={`Receitas por obra, ${posicaoEm.toLowerCase()}, em reais`}
              rotuloPrimeira="Obra"
              colunas={[
                { chave: "vgv", rotulo: "VGV contratado", explicacao: "vgv_contratado_ativo" },
                { chave: "contratos", rotulo: "Contratos", explicacao: "contratos" },
                { chave: "recebido_direto", rotulo: "Recebido do comprador", explicacao: "recebido_direto" },
                {
                  chave: "recebido_financiamento",
                  rotulo: "Recebido de financiamento",
                  explicacao: "recebido_financiamento",
                },
                { chave: "vencido_direto", rotulo: "Vencido do comprador", explicacao: "vencido_direto" },
                {
                  chave: "vencido_financiamento",
                  rotulo: "Financiamento atrasado",
                  explicacao: "vencido_financiamento",
                },
                { chave: "a_vencer_direto", rotulo: "A receber do comprador", explicacao: "a_vencer_direto" },
                {
                  chave: "a_vencer_financiamento",
                  rotulo: "A receber de financiamento",
                  explicacao: "a_vencer_financiamento",
                },
                {
                  chave: "proximo_direto",
                  rotulo: `Entrada direta em ${formatarMes(mesSeguinte)}`,
                  explicacao: "previsto_proximo_mes_direto",
                },
                {
                  chave: "proximo_financiamento",
                  rotulo: `Financiamento em ${formatarMes(mesSeguinte)}`,
                  explicacao: "previsto_proximo_mes_financiamento",
                },
                { chave: "distratado", rotulo: "Saldo distratado", explicacao: "saldo_distratado" },
              ]}
              grupos={[{ linhas: linhasPorObra(resumos) }]}
            />
          </>
        )}
      </Bloco>

      <Bloco
        id="evolucao"
        titulo="Evolução mensal"
        contexto={`${formatarMes(inicioEvolucao)} a ${formatarMes(fimEvolucao)}. Recebido pela data do recebimento; previsto pelo vencimento das parcelas.`}
      >
        {mensal === null && <ErroBloco />}
        {mensal?.length === 0 && <p>{mensagens.receitas.semMovimento}</p>}
        {mensal && mensal.length > 0 && (
          <GraficoRecebimentos
            pontos={juntarRecebimentoMensal(mensal)}
            legenda={`Recebido e previsto por mês, ${nomeRecorte}, em reais`}
          />
        )}
      </Bloco>

      <Bloco
        id="carteira"
        titulo="Parcelas"
        contexto={`${nomeRecorte}. Uma linha por parcela, por vencimento. ${posicaoEm}.`}
      >
        <form
          action="/receitas#carteira"
          method="get"
          aria-label="Filtros das parcelas"
          className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-5 lg:items-end"
        >
          {Object.entries(filtrosBase).map(([nome, conteudo]) =>
            conteudo ? <input key={nome} type="hidden" name={nome} value={conteudo} /> : null,
          )}
          <div className="flex min-w-0 flex-col gap-1.5">
            <label htmlFor="filtro-situacao" className="text-sm font-medium">
              Situação
            </label>
            <select
              id="filtro-situacao"
              name="situacao"
              defaultValue={filtrosCarteira.situacao ?? ""}
              className={classeCampo}
            >
              <option value="">Todas</option>
              {situacoesParcela.map((situacao) => (
                <option key={situacao} value={situacao}>
                  {rotulosSituacao[situacao]}
                </option>
              ))}
            </select>
          </div>
          <div className="flex min-w-0 flex-col gap-1.5">
            <label htmlFor="filtro-origem" className="text-sm font-medium">
              Origem
            </label>
            <select
              id="filtro-origem"
              name="origem"
              defaultValue={filtrosCarteira.origem ?? ""}
              className={classeCampo}
            >
              <option value="">Entrada direta e financiamento</option>
              {origensRecebivel.map((origem) => (
                <option key={origem} value={origem}>
                  {rotulosOrigem[origem]}
                </option>
              ))}
            </select>
          </div>
          <div className="flex min-w-0 flex-col gap-1.5">
            <label htmlFor="filtro-venc-de" className="text-sm font-medium">
              Vencimento a partir de
            </label>
            <input
              id="filtro-venc-de"
              type="date"
              name="venc_de"
              defaultValue={filtrosCarteira.vencimentoDe ?? ""}
              className={classeCampo}
            />
          </div>
          <div className="flex min-w-0 flex-col gap-1.5">
            <label htmlFor="filtro-venc-ate" className="text-sm font-medium">
              Vencimento até
            </label>
            <input
              id="filtro-venc-ate"
              type="date"
              name="venc_ate"
              defaultValue={filtrosCarteira.vencimentoAte ?? ""}
              className={classeCampo}
            />
          </div>
          <button
            type="submit"
            className="min-h-11 cursor-pointer rounded-lg bg-menu px-4 font-semibold text-menu-texto hover:bg-menu-ativo"
          >
            Filtrar parcelas
          </button>
        </form>

        {carteira === null && <ErroBloco />}
        {carteira && carteira.linhas.length === 0 && filtrosCarteira.pagina > 1 && (
          <p>
            {mensagens.receitas.paginaForaDoIntervalo}{" "}
            <a
              href={montarEndereco("/receitas", filtrosComCarteira) + "#carteira"}
              className="underline underline-offset-4 hover:text-menu"
            >
              Voltar para a primeira página
            </a>
          </p>
        )}
        {carteira && carteira.linhas.length === 0 && filtrosCarteira.pagina === 1 && (
          <p>{mensagens.receitas.semCarteira}</p>
        )}
        {carteira && carteira.linhas.length > 0 && paginacao && (
          <>
            <TabelaCarteira
              linhas={carteira.linhas}
              legenda={`Parcelas a receber, ${nomeRecorte}, página ${paginacao.pagina}`}
            />
            <NavegacaoPaginas
              paginacao={paginacao}
              endereco={(pagina) =>
                `${montarEndereco("/receitas", { ...filtrosComCarteira, pagina: pagina > 1 ? pagina : null })}#carteira`
              }
            />
          </>
        )}
      </Bloco>
    </>
  );
}
