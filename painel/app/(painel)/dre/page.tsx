import type { Metadata } from "next";
import Link from "next/link";
import { AvisoCarga } from "@/componentes/financeiro/AvisoCarga";
import { Aviso, Bloco, ErroBloco } from "@/componentes/financeiro/Aviso";
import { FiltrosDemonstrativo } from "@/componentes/financeiro/FiltrosDemonstrativo";
import { GestaoClassificacao } from "@/componentes/financeiro/GestaoClassificacao";
import { GestaoCriterio } from "@/componentes/financeiro/GestaoCriterio";
import { GradeDreMensal } from "@/componentes/financeiro/GradeDreMensal";
import {
  coberturaDoPeriodo,
  criterioPendente,
  estadoDoValor,
  medidasMensais,
  montarGradeMensal,
  montarLinhasPeriodo,
  type MedidaMensal,
} from "@/componentes/financeiro/montar-dre";
import { Selo } from "@/componentes/financeiro/Selo";
import { TabelaDrePeriodo } from "@/componentes/financeiro/TabelaDrePeriodo";
import { TabelaPendencias } from "@/componentes/financeiro/TabelaPendencias";
import { TabelaPorCentro, type LinhaCentro } from "@/componentes/financeiro/TabelaPorCentro";
import { ValorEstado } from "@/componentes/financeiro/ValorEstado";
import {
  limitePendencias,
  listarCategoriasGerenciais,
  listarCriteriosReconhecimento,
  listarDreMensalConsolidado,
  listarDreMensalObra,
  listarDrePeriodo,
  listarMapeamentos,
  listarPendenciasClassificacao,
  listarReconhecimentoNoMes,
  type LinhaReconhecimentoObra,
} from "@/lib/consultas/dre";
import { aplicarRotulos } from "@/lib/configuracao";
import { buscarPreferenciasTenant, listarRotulos } from "@/lib/consultas/configuracao";
import { exigirIdentidade } from "@/lib/consultas/identidade";
import {
  buscarPerfilAtual,
  carregarReferencia,
  listarCentrosCusto,
  podeGravarFinanceiro,
  tentarConsulta,
  type CentroCusto,
} from "@/lib/consultas/referencia";
import { formatarMes, formatarPercentual } from "@/lib/formatar";
import { fraseMotivo, mensagens } from "@/lib/mensagens";
import { lerIdCentro, lerOpcao, lerPeriodo, montarEndereco, type Periodo } from "@/lib/periodo";

export const metadata: Metadata = { title: "DRE gerencial" };

const rotulosMedida: Record<MedidaMensal, string> = {
  valor_mes: "Valor do mês",
  valor_acumulado: "Acumulado desde o primeiro lançamento",
};

const rotulosMetodo: Record<LinhaReconhecimentoObra["metodo"], string> = {
  nao_definido: "Não definido",
  percentual_conclusao: "Percentual de conclusão",
};

const rotulosBase: Record<LinhaReconhecimentoObra["base_fracao_vendida"], string> = {
  unidades: "Unidades",
  area_privativa: "Área privativa",
  valor_tabela: "Valor de tabela",
};

function percentualOuTraco(valor: number | null, disponivel: boolean, motivo: string | null) {
  if (valor === null) return <ValorEstado estado={estadoDoValor(null, disponivel, motivo)} mostrarMotivo={false} />;
  return <>{formatarPercentual(valor)}</>;
}

function linhasReconhecimento(linhas: LinhaReconhecimentoObra[], nomes: Map<string, string>): LinhaCentro[] {
  return linhas.map((linha) => ({
    id: linha.centro_custo_id,
    nome: nomes.get(linha.centro_custo_id) ?? "Obra",
    celulas: {
      metodo: rotulosMetodo[linha.metodo],
      poc: percentualOuTraco(linha.poc, linha.disponivel, linha.motivo),
      fracao: percentualOuTraco(linha.fracao_vendida, linha.disponivel, linha.motivo),
      base: rotulosBase[linha.base_fracao_vendida] ?? linha.base_fracao_vendida,
      cobertura:
        linha.cobertura_custo === null ? (
          <span className="text-suave">Sem custo lançado</span>
        ) : (
          formatarPercentual(linha.cobertura_custo)
        ),
      incorrido: <ValorEstado estado={estadoDoValor(linha.custo_incorrido_acumulado)} />,
      estimado: <ValorEstado estado={estadoDoValor(linha.custo_total_estimado)} />,
      situacao: linha.disponivel ? (
        "Disponível"
      ) : (
        <span className="inline-block max-w-64 text-left whitespace-normal text-suave">
          {fraseMotivo(linha.motivo)}
        </span>
      ),
    },
  }));
}

function SeletorMedida({ medida, filtros }: { medida: MedidaMensal; filtros: Record<string, string | null> }) {
  return (
    <nav aria-label="Valor mostrado na tabela mensal" className="flex flex-wrap gap-2">
      {medidasMensais.map((opcao) => (
        <Link
          key={opcao}
          href={montarEndereco("/dre", { ...filtros, visao: opcao === "valor_mes" ? null : opcao })}
          aria-current={opcao === medida ? "true" : undefined}
          scroll={false}
          className={`flex min-h-11 items-center rounded-lg border px-3 text-sm ${
            opcao === medida
              ? "border-menu bg-menu font-semibold text-menu-texto"
              : "border-borda bg-superficie hover:border-texto"
          }`}
        >
          {rotulosMedida[opcao]}
        </Link>
      ))}
    </nav>
  );
}

async function carregarDre(periodo: Periodo, centroId: string | null, podeGravar: boolean) {
  const [linhasPeriodo, mensal, reconhecimento, pendencias, criterios, categorias, mapeamentos] = await Promise.all([
    tentarConsulta(listarDrePeriodo(periodo.inicio, periodo.fim, centroId)),
    tentarConsulta(
      centroId
        ? listarDreMensalObra(centroId, periodo.inicio, periodo.fim)
        : listarDreMensalConsolidado(periodo.inicio, periodo.fim),
    ),
    tentarConsulta(listarReconhecimentoNoMes(periodo.fim, centroId)),
    tentarConsulta(listarPendenciasClassificacao()),
    tentarConsulta(listarCriteriosReconhecimento()),
    podeGravar ? tentarConsulta(listarCategoriasGerenciais()) : Promise.resolve(null),
    podeGravar ? tentarConsulta(listarMapeamentos()) : Promise.resolve(null),
  ]);
  return { linhasPeriodo, mensal, reconhecimento, pendencias, criterios, categorias, mapeamentos };
}

// Identidade, referência, perfil, centros e preferências primeiro (a data e o período padrão da construtora
// definem o período), depois até oito em paralelo; categorias e contas classificadas só para quem pode gravar.
export default async function PaginaDre({ searchParams }: PageProps<"/dre">) {
  await exigirIdentidade();
  const filtrosUrl = await searchParams;
  const centrosPedido = tentarConsulta(listarCentrosCusto());
  const perfilPedido = tentarConsulta(buscarPerfilAtual());
  const preferenciasPedido = buscarPreferenciasTenant();
  const rotulosPedido = tentarConsulta(listarRotulos());
  const referencia = await carregarReferencia();
  const centros: CentroCusto[] | null = await centrosPedido;
  const podeGravar = podeGravarFinanceiro(await perfilPedido);

  const preferencias = await preferenciasPedido;
  const periodo = lerPeriodo(filtrosUrl, referencia.dataReferencia, preferencias.periodoPadrao);
  const centroPedido = lerIdCentro(filtrosUrl.obra);
  const medida = lerOpcao(filtrosUrl.visao, medidasMensais, "valor_mes");
  const centro = centros?.find((item) => item.id === centroPedido) ?? null;
  const centroNaoEncontrado = centroPedido !== null && centros !== null && centro === null;
  const centroId = centroNaoEncontrado ? null : centroPedido;
  const nomeRecorte = centro?.nome ?? "Consolidado das obras liberadas";
  const nomes = new Map((centros ?? []).map((item) => [item.id, item.nome]));
  const filtrosAtuais = { obra: centroId, periodo: periodo.tipo, mes: periodo.mes.slice(0, 7) };

  const cabecalho = (
    <header className="flex flex-col gap-2">
      <h1 className="font-serif text-[34px] font-semibold">DRE gerencial</h1>
      <p className="max-w-3xl text-suave">
        Regime de competência: cada título entra no mês da emissão, não no mês do pagamento. Para ver o dinheiro que
        entrou e saiu, use Receitas, Despesas e Fluxo de caixa.
      </p>
      <AvisoCarga referencia={referencia} />
    </header>
  );

  const filtros = (
    <FiltrosDemonstrativo
      acao="/dre"
      centros={centros ?? []}
      centroSelecionado={centroId}
      periodo={periodo}
      dataReferencia={referencia.dataReferencia}
      incluirSemObra
      camposOcultos={medida === "valor_mes" ? {} : { visao: medida }}
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

  const { linhasPeriodo, mensal, reconhecimento, pendencias, criterios, categorias, mapeamentos } = await carregarDre(
    periodo,
    centroId,
    podeGravar,
  );
  const rotulos = (await rotulosPedido) ?? [];
  const nomeDaLinha = <T extends { codigo: string; nome: string }>(linhas: T[]) =>
    aplicarRotulos(linhas, (linha) => linha.codigo, rotulos, "linha_dre");
  const montadas = linhasPeriodo ? montarLinhasPeriodo(linhasPeriodo) : null;
  const linhasTela = montadas
    ? { resultado: nomeDaLinha(montadas.resultado), informativas: nomeDaLinha(montadas.informativas) }
    : null;
  const cobertura = linhasPeriodo ? coberturaDoPeriodo(linhasPeriodo) : null;
  const semCriterio = criterioPendente(linhasPeriodo ?? [], reconhecimento ?? []);
  const gradeProduto = mensal ? montarGradeMensal(mensal, medida) : null;
  const grade = gradeProduto ? { ...gradeProduto, linhas: nomeDaLinha(gradeProduto.linhas) } : null;
  const categoriasTela = categorias
    ? aplicarRotulos(categorias, (categoria) => categoria.codigo, rotulos, "categoria")
    : null;
  const recorte = `${nomeRecorte}, ${periodo.rotulo}`;

  return (
    <>
      {cabecalho}
      {filtros}

      {semCriterio && (
        <Aviso titulo="Critério de reconhecimento não validado">
          <p>{mensagens.dre.criterioPendente}</p>
          <p className="pt-1">
            <a href="#criterio" className="underline underline-offset-4 hover:text-menu">
              Ver e registrar o critério
            </a>
          </p>
        </Aviso>
      )}

      <Bloco
        id="resultado-periodo"
        titulo="Resultado do período por competência"
        contexto={`${recorte}. Origem: títulos a pagar e parcelas classificados por categoria gerencial.`}
      >
        {linhasTela === null && <ErroBloco />}
        {linhasTela && linhasTela.resultado.length === 0 && linhasTela.informativas.length === 0 && (
          <p>{mensagens.dre.semLancamentos}</p>
        )}
        {linhasTela && linhasTela.resultado.length + linhasTela.informativas.length > 0 && (
          <>
            {cobertura !== null && cobertura < 1 && (
              <p className="flex flex-wrap items-center gap-2 text-sm">
                <Selo tipo="parcial">parcial</Selo>
                {formatarPercentual(cobertura)} do valor lançado no período tem categoria.
                <a href="#pendencias" className="underline underline-offset-4 hover:text-menu">
                  Ver as contas sem categoria
                </a>
              </p>
            )}
            {cobertura !== null && cobertura >= 1 && (
              <p className="text-sm text-suave">Todo o valor lançado no período tem categoria.</p>
            )}
            <TabelaDrePeriodo
              resultado={linhasTela.resultado}
              informativas={linhasTela.informativas}
              rotuloPeriodo={periodo.rotulo}
            />
            <p className="text-sm text-suave">
              {mensagens.dre.semOrcamentoFonte} &quot;Resultado gerencial do período&quot; não é o lucro contábil.
            </p>
          </>
        )}
      </Bloco>

      <Bloco
        id="mes-a-mes"
        titulo="Mês a mês"
        contexto={`${recorte}. Cada coluna é um mês de competência; o acumulado soma desde o primeiro mês com lançamento no recorte.`}
      >
        <SeletorMedida medida={medida} filtros={filtrosAtuais} />
        {grade === null && <ErroBloco />}
        {grade && grade.meses.length === 0 && <p>{mensagens.dre.semLancamentos}</p>}
        {grade && grade.meses.length > 0 && (
          <GradeDreMensal
            grade={grade}
            legenda={`DRE gerencial mês a mês, ${rotulosMedida[medida].toLowerCase()}, ${recorte}, em reais`}
          />
        )}
      </Bloco>

      {centro?.tipo !== "empresa" && (
        <Bloco
          id="conclusao"
          titulo="Percentual de conclusão por obra"
          contexto={`Posição no fim de ${formatarMes(periodo.fim)}. Base do reconhecimento de receita e custo quando o critério estiver validado. A base da fração vendida e a cobertura mínima do custo com categoria vêm de Configurações.`}
        >
          {reconhecimento === null && <ErroBloco />}
          {reconhecimento && reconhecimento.length === 0 && <p>{mensagens.dre.semLancamentos}</p>}
          {reconhecimento && reconhecimento.length > 0 && (
            <TabelaPorCentro
              legenda={`Percentual de conclusão e fração vendida por obra no fim de ${formatarMes(periodo.fim)}`}
              rotuloPrimeira="Obra"
              colunas={[
                { chave: "metodo", rotulo: "Critério" },
                { chave: "poc", rotulo: "Percentual de conclusão", explicacao: "poc" },
                { chave: "fracao", rotulo: "Fração vendida", explicacao: "fracao_vendida" },
                { chave: "base", rotulo: "Base da fração vendida" },
                { chave: "cobertura", rotulo: "Custo com categoria" },
                { chave: "incorrido", rotulo: "Custo de obra lançado até o mês", explicacao: "custo_obra_incorrido" },
                { chave: "estimado", rotulo: "Custo total estimado" },
                { chave: "situacao", rotulo: "Situação" },
              ]}
              grupos={[{ linhas: linhasReconhecimento(reconhecimento, nomes) }]}
            />
          )}
        </Bloco>
      )}

      <Bloco
        id="pendencias"
        titulo="Contas sem categoria"
        contexto="Todas as obras liberadas, sem filtro de período. Enquanto não forem classificadas, o valor fica na linha Sem categoria e o resultado pode mudar."
      >
        {pendencias === null && <ErroBloco />}
        {pendencias && pendencias.total === 0 && <p>{mensagens.dre.semPendencias}</p>}
        {pendencias && pendencias.total > 0 && (
          <>
            <p className="flex flex-wrap items-center gap-2 text-sm">
              <Selo tipo="parcial">
                {pendencias.total === 1 ? "1 conta pendente" : `${pendencias.total} contas pendentes`}
              </Selo>
              {pendencias.total > limitePendencias && `Mostrando as ${limitePendencias} de maior valor.`}
            </p>
            <TabelaPendencias linhas={pendencias.linhas} />
          </>
        )}
        {podeGravar && categoriasTela === null && <ErroBloco />}
        {podeGravar && categoriasTela && (
          <GestaoClassificacao
            pendencias={pendencias?.linhas ?? []}
            categorias={categoriasTela}
            mapeamentos={mapeamentos}
          />
        )}
        {!podeGravar && (
          <p className="text-sm text-suave">Só diretor ou financeiro da construtora pode classificar contas.</p>
        )}
      </Bloco>

      <Bloco
        id="criterio"
        titulo="Critério de reconhecimento"
        contexto="Define como receita e custo dos imóveis vendidos entram no DRE. Sem critério validado, essas linhas ficam indisponíveis."
      >
        {criterios === null && <ErroBloco />}
        <GestaoCriterio criterios={criterios} obras={centros ?? []} podeGravar={podeGravar} />
      </Bloco>
    </>
  );
}
