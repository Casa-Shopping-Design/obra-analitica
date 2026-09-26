import type { Metadata } from "next";
import { exigirIdentidade } from "@/lib/consultas/identidade";
import Link from "next/link";
import { Aviso, Bloco, ErroBloco } from "@/componentes/financeiro/Aviso";
import { AvisoCarga } from "@/componentes/financeiro/AvisoCarga";
import { Selo } from "@/componentes/financeiro/Selo";
import {
  FormularioMetas,
  FormularioPremissa,
  FormularioVersaoProjecao,
  type LinhaMetaFormulario,
} from "@/componentes/planejamento/FormulariosPlanejamento";
import {
  compararMetas,
  janelasPlanejamento,
  juntarPorMes,
  limitesDaJanela,
  mesesAceitos,
  type Janela,
} from "@/componentes/planejamento/regras-planejamento";
import { TabelaPlanejamento, type ColunaPlanejamento } from "@/componentes/planejamento/TabelaPlanejamento";
import { Inteiro, Percentual, Valor } from "@/componentes/planejamento/Valor";
import { listarResumoProjecao } from "@/lib/consultas/fluxo";
import {
  buscarPremissaVigente,
  listarComparativo,
  listarExplicacaoDesvio,
  listarMetasDasVersoes,
  listarPendenciasPosEntrega,
  listarProjecaoDaVersao,
  listarVersoes,
  listarMetaAutomatica,
  listarVisaoGerencial,
  type LinhaMetaAutomatica,
  type LinhaExplicacaoDesvio,
  type LinhaMetaMensal,
  type LinhaPendenciaPosEntrega,
  type LinhaVisaoGerencial,
  type VersaoPlanejamento,
} from "@/lib/consultas/planejamento";
import { buscarParametrosObra } from "@/lib/consultas/configuracao";
import { carregarReferencia, listarCentrosCusto, tentarConsulta } from "@/lib/consultas/referencia";
import { formatarData, formatarMes } from "@/lib/formatar";
import { fraseMotivo, mensagens } from "@/lib/mensagens";
import {
  explicacoesPlanejamento,
  mensagensPlanejamento,
  rotulosCausaDesvio,
  rotulosOrigemDado,
} from "@/lib/mensagens-planejamento";
import { lerIdCentro, lerOpcao, mesDaData, montarEndereco, somarMeses } from "@/lib/periodo";
import { registrarPremissaDistribuicao, registrarVersaoMeta, registrarVersaoProjecao } from "./acoes";

export const metadata: Metadata = { title: "Planejamento" };

const opcoesJanela = Object.keys(janelasPlanejamento) as Janela[];
const formatoUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function lerVersao(valor: string | string[] | undefined): string | null {
  const texto = Array.isArray(valor) ? valor[0] : valor;
  return texto && formatoUuid.test(texto) ? texto.toLowerCase() : null;
}

const colunasVisao: ColunaPlanejamento[] = [
  { chave: "meta_unidades", rotulo: "Meta (unid.)" },
  { chave: "vendas_unidades", rotulo: "Vendidas" },
  { chave: "distratos", rotulo: "Distratos" },
  { chave: "meta_valor", rotulo: "Meta de venda" },
  { chave: "vendas_valor", rotulo: "Vendido" },
  { chave: "entrada_prevista", rotulo: "Entrada direta prevista (original)" },
  { chave: "entrada_recebida", rotulo: "Entrada direta recebida" },
  { chave: "financiamento_previsto", rotulo: "Liberações previstas (original)" },
  { chave: "financiamento_recebido", rotulo: "Liberações recebidas" },
  { chave: "gastos_previstos", rotulo: "Gastos previstos (original)" },
  { chave: "gastos_realizados", rotulo: "Gastos realizados" },
  { chave: "caixa", rotulo: "Caixa gerado acumulado", explicacao: explicacoesPlanejamento.caixa_gerado_acumulado },
  { chave: "caixa_original", rotulo: "Caixa no original" },
  { chave: "diferenca", rotulo: "Diferença", explicacao: explicacoesPlanejamento.diferenca_original_atual },
  { chave: "aporte", rotulo: "Aporte necessário", explicacao: explicacoesPlanejamento.necessidade_aporte_acumulada },
  { chave: "detalhe", rotulo: "Registros", texto: true },
];

function linhasVisao(visao: LinhaVisaoGerencial[], centroId: string, mesReferencia: string) {
  return visao.map((linha) => {
    const mes = linha.competencia.slice(0, 10);
    const fimMes = somarMeses(mes, 1);
    const ultimoDia = new Date(Date.UTC(Number(fimMes.slice(0, 4)), Number(fimMes.slice(5, 7)) - 1, 0))
      .toISOString()
      .slice(0, 10);
    return {
      chave: mes,
      rotulo: formatarMes(mes),
      destaque: mes === mesReferencia,
      celulas: {
        meta_unidades: <Inteiro valor={linha.meta_unidades} ausente="Sem meta" />,
        vendas_unidades: <Inteiro valor={linha.vendas_unidades} />,
        distratos: <Inteiro valor={linha.distratos_unidades} />,
        meta_valor: <Valor valor={linha.meta_valor_contratado} ausente="Sem meta" />,
        vendas_valor: <Valor valor={linha.vendas_valor} />,
        entrada_prevista: <Valor valor={linha.entrada_direta_prevista_original} ausente="Sem versão" />,
        entrada_recebida: <Valor valor={linha.entrada_direta_recebida} />,
        financiamento_previsto: <Valor valor={linha.financiamento_previsto_original} ausente="Sem versão" />,
        financiamento_recebido: <Valor valor={linha.financiamento_recebido} />,
        gastos_previstos: <Valor valor={linha.gastos_previstos_original} ausente="Sem versão" />,
        gastos_realizados: <Valor valor={linha.gastos_realizados} />,
        caixa: <Valor valor={linha.caixa_gerado_acumulado} />,
        caixa_original: <Valor valor={linha.caixa_gerado_acumulado_original} ausente="Sem versão" />,
        diferenca: <Valor valor={linha.diferenca_original_atual} ausente="Sem versão" />,
        aporte: <Valor valor={linha.necessidade_aporte_acumulada} />,
        detalhe: (
          <span className="flex flex-col gap-0.5 text-xs">
            <Link
              className="underline underline-offset-2"
              href={montarEndereco("/receitas", { obra: centroId, venc_de: mes, venc_ate: ultimoDia })}
            >
              Parcelas do mês
            </Link>
            <Link
              className="underline underline-offset-2"
              href={montarEndereco("/despesas", { obra: centroId, periodo: "mes", mes: mes.slice(0, 7) })}
            >
              Títulos do mês
            </Link>
          </span>
        ),
      },
    };
  });
}

function ListaDesvios({ desvios }: { desvios: LinhaExplicacaoDesvio[] }) {
  if (desvios.length === 0) return <p>{mensagensPlanejamento.planejamento.semDesvios}</p>;
  return (
    <ul className="flex flex-col gap-2">
      {desvios.map((desvio) => (
        <li
          key={`${desvio.competencia}-${desvio.causa_codigo}`}
          className="flex flex-col gap-0.5 rounded-lg border border-borda p-3 text-sm"
        >
          <p className="font-semibold">
            {formatarMes(desvio.competencia)}: {rotulosCausaDesvio[desvio.causa_codigo] ?? desvio.causa_descricao}
          </p>
          <p>{desvio.causa_descricao}</p>
          <p className="text-suave tabular-nums">
            {desvio.quantidade !== null && <>Quantidade: {desvio.quantidade}. </>}
            {desvio.valor !== null && (
              <>
                Valor: <Valor valor={desvio.valor} />.{" "}
              </>
            )}
            Fonte: {rotulosOrigemDado[desvio.origem_dado] ?? desvio.origem_dado}.
          </p>
        </li>
      ))}
    </ul>
  );
}

const rotulosBaseMeta: Record<LinhaMetaAutomatica["base"], string> = {
  custo_orcado: "custo orçado",
  estimativa_conclusao: "estimativa até a conclusão",
};

// Diz de onde vem a meta da visão gerencial: versão gravada (manual) ou cálculo do banco (automática).
function OrigemMeta({
  automatica,
  linhas,
  versaoVigente,
  obraId,
}: {
  automatica: boolean;
  linhas: LinhaMetaAutomatica[] | null;
  versaoVigente: number | null;
  obraId: string;
}) {
  const configuracao = (
    <Link
      href={`/configuracoes?escopo=${obraId}#grupo-comercial`}
      className="underline underline-offset-4 hover:text-menu"
    >
      Configurações
    </Link>
  );
  if (!automatica) {
    return (
      <p className="text-sm">
        <Selo tipo="informativo">meta manual</Selo>{" "}
        {versaoVigente === null
          ? "Nenhuma meta registrada. As metas vêm das versões gravadas abaixo."
          : `As metas vêm da versão ${versaoVigente} registrada abaixo.`}{" "}
        Para calcular a meta todo mês a partir do que falta vender, mude o método em {configuracao}.
      </p>
    );
  }
  const primeira = linhas?.find((linha) => linha.motivo === null) ?? null;
  const motivos = [...new Set((linhas ?? []).map((linha) => linha.motivo).filter((motivo) => motivo !== null))];
  return (
    <div className="flex flex-col gap-1 text-sm">
      <p>
        <Selo tipo="informativo">meta automática</Selo> Calculada todo mês: o que falta vender até o prazo, dividido
        pelos meses restantes, em unidades pelo ticket médio das unidades disponíveis. As versões de meta gravadas
        abaixo não entram na visão. Regra em {configuracao}.
      </p>
      {primeira && (
        <p className="text-suave">
          Base: {rotulosBaseMeta[primeira.base] ?? primeira.base}
          {primeira.horizonte ? `, prazo em ${formatarMes(primeira.horizonte)}` : ""}.
        </p>
      )}
      {linhas === null && <ErroBloco />}
      {motivos.map((motivo) => (
        <p key={motivo} className="text-atencao">
          <span aria-hidden="true">! </span>
          {fraseMotivo(motivo)}
        </p>
      ))}
    </div>
  );
}

function ListaVersoes({ versoes, rotulo }: { versoes: VersaoPlanejamento[]; rotulo: string }) {
  return (
    <ol className="flex flex-col gap-1.5 text-sm" aria-label={rotulo}>
      {versoes.map((versao) => (
        <li key={versao.id} className="flex flex-wrap gap-x-3 border-b border-borda pb-1.5 last:border-b-0">
          <span className="font-semibold">Versão {versao.numero}</span>
          <span>{versao.descricao}</span>
          <span className="text-suave">
            referência {formatarData(versao.data_referencia)}, registrada em {formatarData(versao.criada_em)}
          </span>
        </li>
      ))}
    </ol>
  );
}

function TabelaPendenciasPosEntrega({ pendencias }: { pendencias: LinhaPendenciaPosEntrega[] }) {
  return (
    <TabelaPlanejamento
      legenda="Pendências depois da entrega, por obra"
      rotuloPrimeira="Obra"
      colunas={[
        { chave: "entrega", rotulo: "Entrega" },
        { chave: "vencidos", rotulo: "A receber vencido" },
        { chave: "a_vencer", rotulo: "A receber a vencer" },
        { chave: "parcelas", rotulo: "Parcelas abertas" },
        { chave: "titulos", rotulo: "Títulos em aberto" },
        { chave: "qtd_titulos", rotulo: "Títulos abertos" },
        { chave: "liberacoes", rotulo: "Liberações não recebidas" },
        { chave: "credito", rotulo: "Crédito não liberado" },
      ]}
      linhas={pendencias.map((linha) => ({
        chave: linha.centro_custo_id,
        rotulo: linha.obra,
        href: `/planejamento?obra=${linha.centro_custo_id}`,
        celulas: {
          entrega: formatarData(linha.data_entrega),
          vencidos: <Valor valor={linha.recebiveis_vencidos} />,
          a_vencer: <Valor valor={linha.recebiveis_a_vencer} />,
          parcelas: <Inteiro valor={linha.parcelas_abertas} />,
          titulos: <Valor valor={linha.titulos_em_aberto} />,
          qtd_titulos: <Inteiro valor={linha.titulos_abertos} />,
          liberacoes: <Valor valor={linha.liberacoes_nao_recebidas} />,
          credito: <Valor valor={linha.credito_nao_liberado} />,
        },
      }))}
    />
  );
}

// Metas vigentes viram as linhas do formulário da versão nova, mais linhas em branco até 12.
function linhasFormularioMetas(metas: LinhaMetaMensal[], mesReferencia: string): LinhaMetaFormulario[] {
  const texto = (valor: number | null) => (valor === null ? "" : String(valor).replace(".", ","));
  const existentes = metas.map((meta) => ({
    mes: meta.competencia.slice(0, 7),
    unidades: meta.unidades === null ? "" : String(meta.unidades),
    valor: texto(meta.valor_contratado),
    fracao: meta.fracao_financiada === null ? "" : texto(Number((meta.fracao_financiada * 100).toFixed(4))),
    recebimento: texto(meta.recebimento_esperado),
    limite: texto(meta.limite_aporte_proprio),
  }));
  const vazias = Array.from({ length: Math.max(12 - existentes.length, 3) }, (_, posicao) => ({
    mes: existentes.length === 0 ? somarMeses(mesReferencia, posicao).slice(0, 7) : "",
    unidades: "",
    valor: "",
    fracao: "",
    recebimento: "",
    limite: "",
  }));
  return [...existentes, ...vazias];
}

export default async function PaginaPlanejamento({ searchParams }: PageProps<"/planejamento">) {
  // A rota confere a sessão por conta própria; o proxy e o layout sozinhos não bastam.
  await exigirIdentidade();
  const filtros = await searchParams;
  const [referencia, centros] = await Promise.all([carregarReferencia(), tentarConsulta(listarCentrosCusto())]);
  const obras = (centros ?? []).filter((centro) => centro.tipo === "obra");
  const centroPedido = lerIdCentro(filtros.obra);
  const obra = obras.find((item) => item.id === centroPedido) ?? null;
  const janela = lerOpcao(filtros.janela, opcoesJanela, "curta");
  const mesReferencia = mesDaData(referencia.dataReferencia);

  const cabecalho = (
    <header className="flex flex-col gap-2">
      <h1 className="font-serif text-[34px] font-semibold">Planejamento</h1>
      <p className="max-w-3xl text-suave">
        Metas, projeção registrada e realizado lado a lado, mês a mês. Cada registro vira uma versão nova, e as
        anteriores ficam guardadas para comparar.
      </p>
      <AvisoCarga referencia={referencia} />
    </header>
  );
  const filtro = (
    <form
      action="/planejamento"
      method="get"
      aria-label="Filtros"
      className="grid grid-cols-1 gap-3 rounded-xl border border-borda bg-superficie p-4 sm:grid-cols-3 sm:items-end"
    >
      <div className="flex min-w-0 flex-col gap-1.5">
        <label htmlFor="planejamento-obra" className="text-sm font-medium">
          Obra
        </label>
        <select
          id="planejamento-obra"
          name="obra"
          defaultValue={obra?.id ?? ""}
          className="min-h-11 w-full rounded-lg border border-borda bg-superficie px-3"
        >
          <option value="">Todas as obras (pendências após a entrega)</option>
          {obras.map((item) => (
            <option key={item.id} value={item.id}>
              {item.nome}
            </option>
          ))}
        </select>
      </div>
      <div className="flex min-w-0 flex-col gap-1.5">
        <label htmlFor="planejamento-janela" className="text-sm font-medium">
          Meses mostrados
        </label>
        <select
          id="planejamento-janela"
          name="janela"
          defaultValue={janela}
          className="min-h-11 w-full rounded-lg border border-borda bg-superficie px-3"
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
        className="min-h-11 cursor-pointer rounded-lg bg-menu px-4 font-semibold text-menu-texto hover:bg-menu-ativo"
      >
        Aplicar filtros
      </button>
    </form>
  );

  if (centroPedido && centros !== null && !obra) {
    return (
      <>
        {cabecalho}
        {filtro}
        <p role="alert">{mensagens.obra.naoEncontrada}</p>
      </>
    );
  }

  if (!obra) {
    const pendencias = await tentarConsulta(listarPendenciasPosEntrega(null));
    return (
      <>
        {cabecalho}
        {filtro}
        <p>{mensagensPlanejamento.planejamento.escolhaObra}</p>
        <Bloco
          id="pos-entrega"
          titulo="Depois da entrega"
          contexto={mensagensPlanejamento.planejamento.posEntregaGerencial}
        >
          {pendencias === null && <ErroBloco />}
          {pendencias?.length === 0 && <p>{mensagensPlanejamento.planejamento.semPendenciasPosEntrega}</p>}
          {pendencias && pendencias.length > 0 && <TabelaPendenciasPosEntrega pendencias={pendencias} />}
        </Bloco>
      </>
    );
  }

  const limites = limitesDaJanela(janela, referencia.dataReferencia);
  const janelaObra = { centroCustoId: obra.id, inicio: limites.inicio, fim: limites.fim };
  const versaoPedida = lerVersao(filtros.versao);
  const metaComparada = lerVersao(filtros.meta_comparar);
  // Primeira leva em paralelo; as metas dependem das versões e vão numa consulta só em seguida.
  const [visao, desvios, comparativo, versoesProjecao, versoesMeta, premissaConsultada, resumos, pendencias, regraMeta] =
    await Promise.all([
      tentarConsulta(listarVisaoGerencial(janelaObra)),
      tentarConsulta(listarExplicacaoDesvio({ ...janelaObra, fim: mesReferencia })),
      tentarConsulta(listarComparativo(janelaObra)),
      tentarConsulta(listarVersoes(obra.id, "projecao")),
      tentarConsulta(listarVersoes(obra.id, "meta")),
      tentarConsulta(buscarPremissaVigente(obra.id).then((vigente) => ({ vigente }))),
      tentarConsulta(listarResumoProjecao(obra.id)),
      tentarConsulta(listarPendenciasPosEntrega(obra.id)),
      buscarParametrosObra(obra.id, ["comercial__meta_metodo"]),
    ]);
  const metaAutomatica = regraMeta?.comercial__meta_metodo === "automatica";
  const metaVigente = versoesMeta?.[0] ?? null;
  const metaParaComparar =
    versoesMeta?.find((versao) => versao.id === metaComparada && versao.id !== metaVigente?.id) ?? null;
  const versaoParaComparar = versoesProjecao?.find((versao) => versao.id === versaoPedida) ?? null;
  const [metas, projecaoVersao, metaCalculada] = await Promise.all([
    metaVigente
      ? tentarConsulta(listarMetasDasVersoes([metaVigente.id, ...(metaParaComparar ? [metaParaComparar.id] : [])]))
      : Promise.resolve([] as LinhaMetaMensal[]),
    versaoParaComparar ? tentarConsulta(listarProjecaoDaVersao(versaoParaComparar.id)) : Promise.resolve(null),
    metaAutomatica ? tentarConsulta(listarMetaAutomatica(janelaObra)) : Promise.resolve(null),
  ]);
  const resumo = resumos?.[0] ?? null;
  const premissa = premissaConsultada?.vigente ?? null;
  const meses = mesesAceitos(referencia.dataReferencia);
  const enderecoBase = { obra: obra.id, janela };

  return (
    <>
      {cabecalho}
      {filtro}

      <nav aria-label="Seções do planejamento" className="flex flex-wrap gap-x-5 gap-y-2 text-sm font-semibold">
        <a href="#visao" className="underline underline-offset-4">
          Visão mensal
        </a>
        <a href="#desvios" className="underline underline-offset-4">
          Desvios
        </a>
        <a href="#projecao" className="underline underline-offset-4">
          Versões da projeção
        </a>
        <a href="#metas" className="underline underline-offset-4">
          Metas
        </a>
        <a href="#premissa" className="underline underline-offset-4">
          Custo sem título
        </a>
        <a href="#pos-entrega" className="underline underline-offset-4">
          Depois da entrega
        </a>
        <Link href={`/planejamento/financiamento?obra=${obra.id}`} className="underline underline-offset-4">
          Financiamento e medições
        </Link>
        <Link href={`/fluxo/${obra.id}`} className="underline underline-offset-4">
          Fluxo de caixa
        </Link>
      </nav>

      <Bloco
        id="visao"
        titulo={`${obra.nome}: visão gerencial mensal`}
        contexto={`Posição em ${formatarData(referencia.dataReferencia)}. "Original" é a primeira projeção registrada no mês de referência; sem ela, a última dos meses anteriores.`}
      >
        <OrigemMeta
          automatica={metaAutomatica}
          linhas={metaCalculada}
          versaoVigente={metaVigente?.numero ?? null}
          obraId={obra.id}
        />
        {visao === null && <ErroBloco />}
        {visao?.length === 0 && <p>{mensagensPlanejamento.planejamento.semVisao}</p>}
        {visao && visao.length > 0 && (
          <TabelaPlanejamento
            legenda={`Visão gerencial mensal da ${obra.nome}`}
            rotuloPrimeira="Mês"
            colunas={colunasVisao}
            linhas={linhasVisao(visao, obra.id, mesReferencia)}
          />
        )}
      </Bloco>

      <Bloco
        id="desvios"
        titulo="Por que o caixa se afastou do planejado"
        contexto="Só as causas que os dados sustentam, até o mês de referência."
      >
        {desvios === null ? <ErroBloco /> : <ListaDesvios desvios={desvios} />}
      </Bloco>

      <Bloco id="projecao" titulo="Versões da projeção" contexto={mensagensPlanejamento.planejamento.versoesImutaveis}>
        <FormularioVersaoProjecao acao={registrarVersaoProjecao} obraId={obra.id} />
        {versoesProjecao === null && <ErroBloco />}
        {versoesProjecao?.length === 0 && <p>{mensagensPlanejamento.planejamento.semVersoesProjecao}</p>}
        {versoesProjecao && versoesProjecao.length > 0 && (
          <ListaVersoes versoes={versoesProjecao} rotulo="Versões da projeção" />
        )}

        <h3 className="font-semibold">Original, atual e realizado</h3>
        {comparativo === null && <ErroBloco />}
        {comparativo && comparativo.length > 0 && (
          <TabelaPlanejamento
            legenda="Comparativo da projeção original, atual e realizado por mês"
            rotuloPrimeira="Mês"
            colunas={[
              { chave: "versao", rotulo: "Versão original" },
              { chave: "orig_entradas", rotulo: "Entradas (original)" },
              { chave: "atual_entradas", rotulo: "Entradas (atual)" },
              { chave: "real_entradas", rotulo: "Entradas realizadas" },
              { chave: "orig_saidas", rotulo: "Saídas (original)" },
              { chave: "atual_saidas", rotulo: "Saídas (atual)" },
              { chave: "real_saidas", rotulo: "Saídas realizadas" },
              { chave: "orig_caixa", rotulo: "Caixa (original)" },
              { chave: "atual_caixa", rotulo: "Caixa (atual)" },
              { chave: "diferenca", rotulo: "Diferença", explicacao: explicacoesPlanejamento.diferenca_original_atual },
            ]}
            linhas={comparativo.map((linha) => ({
              chave: linha.competencia,
              rotulo: formatarMes(linha.competencia),
              destaque: linha.competencia.slice(0, 10) === mesReferencia,
              celulas: {
                versao: <Inteiro valor={linha.versao_original_numero} ausente="Sem versão" />,
                orig_entradas: <Valor valor={linha.original_total_entradas} ausente="Sem versão" />,
                atual_entradas: <Valor valor={linha.atual_total_entradas} />,
                real_entradas: <Valor valor={linha.realizado_entradas} ausente="Ainda não" />,
                orig_saidas: <Valor valor={linha.original_total_saidas} ausente="Sem versão" />,
                atual_saidas: <Valor valor={linha.atual_total_saidas} />,
                real_saidas: <Valor valor={linha.realizado_saidas} ausente="Ainda não" />,
                orig_caixa: <Valor valor={linha.original_caixa_gerado_acumulado} ausente="Sem versão" />,
                atual_caixa: <Valor valor={linha.atual_caixa_gerado_acumulado} />,
                diferenca: <Valor valor={linha.diferenca_caixa_acumulado} ausente="Sem versão" />,
              },
            }))}
          />
        )}

        {versoesProjecao && versoesProjecao.length > 0 && (
          <form
            method="get"
            aria-label="Comparar com outra versão"
            className="flex flex-col gap-2 sm:flex-row sm:items-end"
          >
            <input type="hidden" name="obra" value={obra.id} />
            <input type="hidden" name="janela" value={janela} />
            <div className="flex flex-col gap-1.5">
              <label htmlFor="comparar-versao" className="text-sm font-medium">
                Comparar a projeção atual com a versão
              </label>
              <select
                id="comparar-versao"
                name="versao"
                defaultValue={versaoParaComparar?.id ?? ""}
                className="min-h-11 rounded-lg border border-borda bg-superficie px-3"
              >
                <option value="">Nenhuma</option>
                {versoesProjecao.map((versao) => (
                  <option key={versao.id} value={versao.id}>
                    Versão {versao.numero}: {versao.descricao.slice(0, 60)}
                  </option>
                ))}
              </select>
            </div>
            <button
              type="submit"
              className="min-h-11 cursor-pointer rounded-lg border border-borda bg-superficie px-4 font-semibold hover:border-texto"
            >
              Comparar
            </button>
          </form>
        )}
        {versaoParaComparar && projecaoVersao === null && <ErroBloco />}
        {versaoParaComparar && projecaoVersao && comparativo && (
          <TabelaPlanejamento
            legenda={`Projeção atual e versão ${versaoParaComparar.numero}, lado a lado`}
            rotuloPrimeira="Mês"
            colunas={[
              { chave: "entradas_versao", rotulo: `Entradas (versão ${versaoParaComparar.numero})` },
              { chave: "entradas_atual", rotulo: "Entradas (atual)" },
              { chave: "saidas_versao", rotulo: `Saídas (versão ${versaoParaComparar.numero})` },
              { chave: "saidas_atual", rotulo: "Saídas (atual)" },
              { chave: "caixa_versao", rotulo: `Caixa (versão ${versaoParaComparar.numero})` },
              { chave: "caixa_atual", rotulo: "Caixa (atual)" },
            ]}
            linhas={juntarPorMes(
              projecaoVersao.filter((linha) => comparativo.some((atual) => atual.competencia === linha.competencia)),
              comparativo,
            ).map(({ competencia, a, b }) => ({
              chave: competencia,
              rotulo: formatarMes(competencia),
              celulas: {
                entradas_versao: <Valor valor={a?.total_entradas} ausente="Fora da versão" />,
                entradas_atual: <Valor valor={b?.atual_total_entradas} />,
                saidas_versao: <Valor valor={a?.total_saidas} ausente="Fora da versão" />,
                saidas_atual: <Valor valor={b?.atual_total_saidas} />,
                caixa_versao: <Valor valor={a?.caixa_gerado_acumulado} ausente="Fora da versão" />,
                caixa_atual: <Valor valor={b?.atual_caixa_gerado_acumulado} />,
              },
            }))}
          />
        )}
      </Bloco>

      <Bloco id="metas" titulo="Metas por mês" contexto={mensagensPlanejamento.planejamento.versoesImutaveis}>
        {versoesMeta === null && <ErroBloco />}
        {versoesMeta?.length === 0 && <p>{mensagensPlanejamento.planejamento.semMetas}</p>}
        {metaVigente && metas && (
          <>
            <p className="text-sm">
              Vigente: <strong>versão {metaVigente.numero}</strong>, {metaVigente.descricao}, registrada em{" "}
              {formatarData(metaVigente.criada_em)}.
            </p>
            {versoesMeta && versoesMeta.length > 1 && (
              <form method="get" aria-label="Comparar metas" className="flex flex-col gap-2 sm:flex-row sm:items-end">
                <input type="hidden" name="obra" value={obra.id} />
                <input type="hidden" name="janela" value={janela} />
                <div className="flex flex-col gap-1.5">
                  <label htmlFor="comparar-meta" className="text-sm font-medium">
                    Comparar com a versão de metas
                  </label>
                  <select
                    id="comparar-meta"
                    name="meta_comparar"
                    defaultValue={metaParaComparar?.id ?? ""}
                    className="min-h-11 rounded-lg border border-borda bg-superficie px-3"
                  >
                    <option value="">Nenhuma</option>
                    {versoesMeta.slice(1).map((versao) => (
                      <option key={versao.id} value={versao.id}>
                        Versão {versao.numero}: {versao.descricao.slice(0, 60)}
                      </option>
                    ))}
                  </select>
                </div>
                <button
                  type="submit"
                  className="min-h-11 cursor-pointer rounded-lg border border-borda bg-superficie px-4 font-semibold hover:border-texto"
                >
                  Comparar
                </button>
              </form>
            )}
            <TabelaPlanejamento
              legenda="Metas da versão vigente por mês"
              rotuloPrimeira="Mês"
              colunas={[
                { chave: "unidades", rotulo: "Unidades" },
                { chave: "valor", rotulo: "Valor contratado" },
                { chave: "fracao", rotulo: "Financiado" },
                { chave: "recebimento", rotulo: "Recebimento esperado" },
                { chave: "limite", rotulo: "Limite de aporte" },
                ...(metaParaComparar
                  ? [
                      { chave: "unidades_antes", rotulo: `Unidades (versão ${metaParaComparar.numero})` },
                      { chave: "valor_antes", rotulo: `Valor (versão ${metaParaComparar.numero})` },
                    ]
                  : []),
              ]}
              linhas={compararMetas(metas, metaVigente.id, metaParaComparar?.id ?? null).map(
                ({ competencia, a, b }) => ({
                  chave: competencia,
                  rotulo: formatarMes(competencia),
                  celulas: {
                    unidades: <Inteiro valor={a?.unidades} ausente="Sem meta" />,
                    valor: <Valor valor={a?.valor_contratado} ausente="Sem meta" />,
                    fracao: <Percentual fracao={a?.fracao_financiada} ausente="Sem meta" />,
                    recebimento: <Valor valor={a?.recebimento_esperado} ausente="Sem meta" />,
                    limite: <Valor valor={a?.limite_aporte_proprio} ausente="Sem meta" />,
                    unidades_antes: <Inteiro valor={b?.unidades} ausente="Sem meta" />,
                    valor_antes: <Valor valor={b?.valor_contratado} ausente="Sem meta" />,
                  },
                }),
              )}
            />
          </>
        )}
        {versoesMeta && versoesMeta.length > 0 && <ListaVersoes versoes={versoesMeta} rotulo="Versões das metas" />}
        <details className="rounded-xl border border-borda p-4">
          <summary className="min-h-11 cursor-pointer content-center font-semibold">
            Registrar nova versão das metas
          </summary>
          <div className="mt-3">
            <FormularioMetas
              acao={registrarVersaoMeta}
              obraId={obra.id}
              linhas={linhasFormularioMetas(
                metaVigente ? (metas ?? []).filter((meta) => meta.versao_id === metaVigente.id) : [],
                mesReferencia,
              )}
              meses={meses}
            />
          </div>
        </details>
      </Bloco>

      <Bloco
        id="premissa"
        titulo="Custo sem título: premissa de meses"
        contexto="Sem premissa cadastrada, o custo que falta lançar fica fora do mês a mês e o aporte aparece como parcial."
      >
        {resumo && (
          <dl className="grid gap-x-6 gap-y-1.5 text-sm sm:grid-cols-[auto_1fr]">
            <dt className="text-suave">Custo sem título</dt>
            <dd>
              {resumo.custo_sem_titulo_total === null ? (
                fraseMotivo("orcamento_ausente")
              ) : (
                <Valor valor={resumo.custo_sem_titulo_total} />
              )}
            </dd>
            <dt className="text-suave">Distribuído nos meses</dt>
            <dd>
              <Valor valor={resumo.custo_sem_titulo_distribuido_total} />
            </dd>
            <dt className="text-suave">Fora dos meses</dt>
            <dd className="flex flex-wrap items-center gap-2">
              <Valor valor={resumo.custo_sem_titulo_nao_distribuido} ausente="Não se sabe" />
              {resumo.exposicao_parcial && <Selo tipo="parcial">aporte parcial</Selo>}
              {resumo.motivo_distribuicao && (
                <span className="text-suave">{fraseMotivo(resumo.motivo_distribuicao)}</span>
              )}
            </dd>
          </dl>
        )}
        {premissaConsultada === null && <ErroBloco />}
        {premissa ? (
          <div className="flex flex-col gap-2 text-sm">
            <p>
              Vigente desde {formatarData(premissa.criada_em)}. Fonte: {premissa.fonte}.
              {premissa.observacao && <> {premissa.observacao}</>}
            </p>
            <ul className="flex flex-wrap gap-2">
              {premissa.meses.map((mes) => (
                <li key={mes.competencia} className="rounded-lg border border-borda px-2 py-1 tabular-nums">
                  {formatarMes(mes.competencia)}: <Percentual fracao={mes.fracao} />
                </li>
              ))}
            </ul>
          </div>
        ) : (
          premissaConsultada !== null && <p>{mensagensPlanejamento.planejamento.semPremissa}</p>
        )}
        <details className="rounded-xl border border-borda p-4">
          <summary className="min-h-11 cursor-pointer content-center font-semibold">Cadastrar nova premissa</summary>
          <div className="mt-3">
            <FormularioPremissa
              acao={registrarPremissaDistribuicao}
              obraId={obra.id}
              meses={meses}
              linhas={Array.from({ length: 12 }, (_, posicao) => ({
                mes: premissa?.meses[posicao]?.competencia.slice(0, 7) ?? "",
                percentual:
                  premissa?.meses[posicao] !== undefined
                    ? String(Number((premissa.meses[posicao].fracao * 100).toFixed(4))).replace(".", ",")
                    : "",
              }))}
            />
          </div>
        </details>
      </Bloco>

      <Bloco
        id="campanhas"
        titulo="Campanhas comerciais"
        contexto={mensagensPlanejamento.planejamento.campanhaNoSimulador}
      >
        <p>
          <Link href={`/fluxo/${obra.id}/simular`} className="font-semibold underline underline-offset-4">
            Testar uma campanha no simulador
          </Link>
        </p>
      </Bloco>

      <Bloco
        id="pos-entrega"
        titulo="Depois da entrega"
        contexto={mensagensPlanejamento.planejamento.posEntregaGerencial}
      >
        {pendencias === null && <ErroBloco />}
        {pendencias?.length === 0 && <p>{mensagensPlanejamento.planejamento.semPendenciasPosEntrega}</p>}
        {pendencias && pendencias.length > 0 && <TabelaPendenciasPosEntrega pendencias={pendencias} />}
      </Bloco>

      {resumo?.exposicao_parcial && (
        <Aviso titulo="Aporte parcial">{mensagensPlanejamento.fluxo.custoNaoDistribuido}</Aviso>
      )}
      <p className="text-sm text-suave">
        <Link href={montarEndereco("/planejamento", { ...enderecoBase })} className="underline underline-offset-4">
          Limpar as comparações
        </Link>
      </p>
    </>
  );
}
