import type { Metadata } from "next";
import { AvisoCarga } from "@/componentes/financeiro/AvisoCarga";
import { Bloco, ErroBloco } from "@/componentes/financeiro/Aviso";
import { CartaoFinanceiro } from "@/componentes/financeiro/CartaoFinanceiro";
import { FiltrosDemonstrativo } from "@/componentes/financeiro/FiltrosDemonstrativo";
import { estadoDoValor, type EstadoValor } from "@/componentes/financeiro/montar-dre";
import { Selo } from "@/componentes/financeiro/Selo";
import { TabelaPorCentro, type ColunaCentro, type LinhaCentro } from "@/componentes/financeiro/TabelaPorCentro";
import { ValorEstado } from "@/componentes/financeiro/ValorEstado";
import {
  listarCustoPorCategoria,
  listarCustoResumo,
  listarCustoResumoConsolidado,
  listarDesembolsoPeriodo,
  type CustoObraResumo,
  type LinhaCustoObraCategoria,
  type LinhaDesembolsoPeriodo,
} from "@/lib/consultas/despesas";
import { exigirIdentidade } from "@/lib/consultas/identidade";
import { carregarReferencia, listarCentrosCusto, tentarConsulta } from "@/lib/consultas/referencia";
import { formatarData, formatarPercentual } from "@/lib/formatar";
import { mensagens } from "@/lib/mensagens";
import { lerIdCentro, lerPeriodo } from "@/lib/periodo";

export const metadata: Metadata = { title: "Despesas" };

const semFonte: EstadoValor = estadoDoValor(null, false, "sem_fonte");
const naoSeAplica = <span className="font-normal text-suave">Não se aplica</span>;

// Coluna que depende do orçamento: nula vira indisponível com o motivo que o banco mandou.
function doOrcamento(valor: number | null, motivo: string | null): EstadoValor {
  return valor === null ? estadoDoValor(null, false, motivo ?? "orcamento_ausente") : estadoDoValor(valor);
}

function celula(estado: EstadoValor) {
  return <ValorEstado estado={estado} mostrarMotivo={false} />;
}

function cobertura(valor: number | null) {
  if (valor === null) return <span className="font-normal text-suave">Sem título</span>;
  return (
    <span className="inline-flex items-center justify-end gap-1.5">
      {formatarPercentual(valor)}
      {valor < 1 && <Selo tipo="parcial">parcial</Selo>}
    </span>
  );
}

const colunasPorCentro: ColunaCentro[] = [
  { chave: "orcamento", rotulo: "Orçamento vigente", explicacao: "orcamento_vigente" },
  { chave: "lancado", rotulo: "Custo lançado", explicacao: "custo_lancado" },
  { chave: "desembolsado", rotulo: "Desembolsado", explicacao: "desembolsado" },
  { chave: "vencido", rotulo: "A pagar vencido", explicacao: "em_aberto_vencido" },
  { chave: "a_vencer", rotulo: "A pagar a vencer", explicacao: "em_aberto_a_vencer" },
  { chave: "ajuste", rotulo: "Descontos e acréscimos", explicacao: "ajuste_baixa" },
  { chave: "remanescente", rotulo: "Orçamento sem título", explicacao: "remanescente_sem_titulo" },
  { chave: "estimativa", rotulo: "Estimativa até a conclusão", explicacao: "estimativa_conclusao" },
  { chave: "desvio", rotulo: "Desvio sobre o orçamento", explicacao: "desvio" },
  { chave: "compromissos", rotulo: "Compromissos não faturados", explicacao: "compromissos_nao_faturados" },
  { chave: "cobertura", rotulo: "Classificado", explicacao: "cobertura" },
];

function linhaCentro(resumo: CustoObraResumo): LinhaCentro {
  const obra = resumo.tipo_centro === "obra";
  const orcamento = (valor: number | null) => (obra ? celula(doOrcamento(valor, resumo.motivo)) : naoSeAplica);
  return {
    id: resumo.centro_custo_id,
    nome: resumo.obra,
    href: `/despesas?obra=${resumo.centro_custo_id}`,
    celulas: {
      orcamento: orcamento(resumo.orcamento_vigente),
      lancado: celula(estadoDoValor(resumo.custo_lancado)),
      desembolsado: celula(estadoDoValor(resumo.desembolsado)),
      vencido: celula(estadoDoValor(resumo.em_aberto_vencido)),
      a_vencer: celula(estadoDoValor(resumo.em_aberto_a_vencer)),
      ajuste: celula(estadoDoValor(resumo.ajuste_baixa)),
      remanescente: orcamento(resumo.remanescente_sem_titulo),
      estimativa: orcamento(resumo.estimativa_conclusao),
      desvio: orcamento(resumo.desvio),
      compromissos: celula(semFonte),
      cobertura: cobertura(resumo.cobertura_classificacao),
    },
  };
}

function linhasCategoria(linhas: LinhaCustoObraCategoria[], motivoOrcamento: string | null): LinhaCentro[] {
  return linhas.map((linha) => ({
    id: linha.categoria_codigo ?? "sem-categoria",
    nome: linha.categoria_nome,
    celulas: {
      orcamento: celula(doOrcamento(linha.orcamento_vigente, motivoOrcamento)),
      lancado: celula(estadoDoValor(linha.custo_lancado)),
      desembolsado: celula(estadoDoValor(linha.desembolsado)),
      vencido: celula(estadoDoValor(linha.em_aberto_vencido)),
      a_vencer: celula(estadoDoValor(linha.em_aberto_a_vencer)),
      ajuste: celula(estadoDoValor(linha.ajuste_baixa)),
    },
  }));
}

function linhasDesembolso(linhas: LinhaDesembolsoPeriodo[]): LinhaCentro[] {
  return linhas.map((linha) => ({
    id: linha.categoria_codigo ?? "sem-categoria",
    nome: linha.categoria_nome,
    celulas: {
      lancado: celula(estadoDoValor(linha.lancado_competencia)),
      pago: celula(estadoDoValor(linha.pago)),
    },
  }));
}

type TotaisCusto = Pick<
  CustoObraResumo,
  | "orcamento_vigente"
  | "custo_lancado"
  | "desembolsado"
  | "em_aberto_vencido"
  | "em_aberto_a_vencer"
  | "ajuste_baixa"
  | "remanescente_sem_titulo"
  | "estimativa_conclusao"
  | "desvio"
  | "cobertura_classificacao"
  | "motivo"
>;

// Os mesmos cartões para uma obra, para o total das obras e para as despesas sem obra (sem orçamento).
function CartoesCusto({
  resumo,
  comOrcamento,
  dataReferencia,
}: {
  resumo: TotaisCusto;
  comOrcamento: boolean;
  dataReferencia: string;
}) {
  const posicaoEm = `Posição em ${formatarData(dataReferencia)}`;
  const obra = comOrcamento;
  const contexto = `${posicaoEm}. Origem: títulos a pagar, pagamentos e itens do orçamento.`;
  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
      {obra && (
        <CartaoFinanceiro
          rotulo="Orçamento vigente"
          chave="orcamento_vigente"
          valores={[{ estado: doOrcamento(resumo.orcamento_vigente, resumo.motivo) }]}
          contexto={contexto}
        />
      )}
      <CartaoFinanceiro
        rotulo="Custo lançado"
        chave="custo_lancado"
        valores={[{ estado: estadoDoValor(resumo.custo_lancado) }]}
        contexto={contexto}
      />
      <CartaoFinanceiro
        rotulo="Desembolsado"
        chave="desembolsado"
        valores={[{ estado: estadoDoValor(resumo.desembolsado) }]}
        contexto={`${posicaoEm}. Pela data do pagamento.`}
      />
      <CartaoFinanceiro
        rotulo="Em aberto"
        chave="em_aberto_vencido"
        valores={[
          { rotulo: "A pagar vencido", estado: estadoDoValor(resumo.em_aberto_vencido) },
          { rotulo: "A pagar a vencer", estado: estadoDoValor(resumo.em_aberto_a_vencer) },
        ]}
        contexto={`Vencido é o que venceu antes de ${formatarData(dataReferencia)}.`}
      />
      <CartaoFinanceiro
        rotulo="Descontos e acréscimos"
        chave="ajuste_baixa"
        valores={[{ estado: estadoDoValor(resumo.ajuste_baixa) }]}
        contexto={contexto}
      />
      {obra && (
        <>
          <CartaoFinanceiro
            rotulo="Orçamento sem título"
            chave="remanescente_sem_titulo"
            valores={[{ estado: doOrcamento(resumo.remanescente_sem_titulo, resumo.motivo) }]}
            contexto={contexto}
          />
          <CartaoFinanceiro
            rotulo="Estimativa até a conclusão"
            chave="estimativa_conclusao"
            valores={[{ estado: doOrcamento(resumo.estimativa_conclusao, resumo.motivo) }]}
            contexto="Custo lançado mais o orçamento sem título."
          />
          <CartaoFinanceiro
            rotulo="Desvio sobre o orçamento"
            chave="desvio"
            valores={[{ estado: doOrcamento(resumo.desvio, resumo.motivo) }]}
            contexto={contexto}
          />
          <CartaoFinanceiro
            rotulo="Orçamento original"
            chave="orcamento_original"
            valores={[{ estado: semFonte }]}
            contexto="A origem só guarda o orçamento vigente."
          />
        </>
      )}
      <CartaoFinanceiro
        rotulo="Compromissos não faturados"
        chave="compromissos_nao_faturados"
        valores={[{ estado: semFonte }]}
        contexto="Pedidos de compra e contratos de empreiteiro ainda não são lidos da origem."
      />
      <CartaoFinanceiro
        rotulo="Classificado"
        chave="cobertura"
        valores={[]}
        destaque={
          resumo.cobertura_classificacao === null ? (
            <span className="font-normal text-suave">Sem título lançado</span>
          ) : (
            formatarPercentual(resumo.cobertura_classificacao)
          )
        }
        selo={
          resumo.cobertura_classificacao !== null && resumo.cobertura_classificacao < 1 ? (
            <Selo tipo="parcial">parcial</Selo>
          ) : undefined
        }
        contexto="Parte do custo lançado que já tem categoria gerencial."
      />
    </div>
  );
}

export default async function PaginaDespesas({ searchParams }: PageProps<"/despesas">) {
  await exigirIdentidade();
  const filtrosUrl = await searchParams;
  const centrosPedido = tentarConsulta(listarCentrosCusto());
  const referencia = await carregarReferencia();
  const centros = await centrosPedido;

  const periodo = lerPeriodo(filtrosUrl, referencia.dataReferencia);
  const centroPedido = lerIdCentro(filtrosUrl.obra);
  const centro = centros?.find((item) => item.id === centroPedido) ?? null;
  const centroNaoEncontrado = centroPedido !== null && centros !== null && centro === null;
  const centroId = centroNaoEncontrado ? null : centroPedido;

  const cabecalho = (
    <header className="flex flex-col gap-2">
      <h1 className="font-serif text-[34px] font-semibold">Despesas</h1>
      <p className="max-w-3xl text-suave">
        Custo lançado, pago e em aberto, comparado com o orçamento vigente. Cada real aparece em um balde só:
        desembolsado, em aberto ou descontos e acréscimos.
      </p>
      <AvisoCarga referencia={referencia} />
    </header>
  );
  const filtros = (
    <FiltrosDemonstrativo
      acao="/despesas"
      centros={centros ?? []}
      centroSelecionado={centroId}
      periodo={periodo}
      dataReferencia={referencia.dataReferencia}
      incluirSemObra
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

  const [resumos, consolidado, categorias, desembolso] = await Promise.all([
    tentarConsulta(listarCustoResumo(centroId)),
    centroId ? Promise.resolve(null) : tentarConsulta(listarCustoResumoConsolidado()),
    centroId ? tentarConsulta(listarCustoPorCategoria(centroId)) : Promise.resolve(null),
    tentarConsulta(listarDesembolsoPeriodo(periodo.inicio, periodo.fim, centroId)),
  ]);

  const posicaoEm = `Posição em ${formatarData(referencia.dataReferencia)}`;
  const nomeRecorte = centro?.nome ?? "Consolidado das obras liberadas";
  const resumoCentro = centroId && resumos?.length === 1 ? resumos[0] : null;
  const obras = resumos?.filter((resumo) => resumo.tipo_centro === "obra") ?? [];
  const semObra = resumos?.filter((resumo) => resumo.tipo_centro === "empresa") ?? [];

  return (
    <>
      {cabecalho}
      {filtros}

      <Bloco
        id="posicao"
        titulo={nomeRecorte}
        contexto={`${posicaoEm}. Origem: títulos a pagar, pagamentos e itens do orçamento.`}
      >
        {resumos === null && <ErroBloco />}
        {resumos?.length === 0 && <p>{mensagens.despesas.semCustos}</p>}
        {resumoCentro && (
          <CartoesCusto
            resumo={resumoCentro}
            comOrcamento={resumoCentro.tipo_centro === "obra"}
            dataReferencia={referencia.dataReferencia}
          />
        )}
        {!centroId && consolidado === null && <ErroBloco />}
        {!centroId &&
          consolidado?.map((grupo) => (
            <section key={grupo.grupo} aria-labelledby={`grupo-${grupo.grupo}`} className="flex flex-col gap-3">
              <h3 id={`grupo-${grupo.grupo}`} className="font-semibold">
                {grupo.grupo === "obras"
                  ? `Total das obras (${grupo.quantidade_centros === 1 ? "1 obra" : `${grupo.quantidade_centros} obras`})`
                  : "Despesas sem obra"}
              </h3>
              {grupo.grupo === "despesas_sem_obra" && (
                <p className="text-sm text-suave">
                  Títulos que a origem mandou sem obra. Não têm orçamento e não entram no total das obras.
                </p>
              )}
              <CartoesCusto
                resumo={grupo}
                comOrcamento={grupo.grupo === "obras"}
                dataReferencia={referencia.dataReferencia}
              />
            </section>
          ))}
        {!centroId && resumos && resumos.length > 0 && (
          <>
            <h3 className="font-semibold">Por obra</h3>
            <TabelaPorCentro
              legenda={`Custos por obra e despesas sem obra, ${posicaoEm.toLowerCase()}, em reais`}
              rotuloPrimeira="Obra"
              colunas={colunasPorCentro}
              grupos={[
                { titulo: "Obras", linhas: obras.map(linhaCentro) },
                {
                  titulo: "Despesas sem obra",
                  nota: "Títulos que a origem mandou sem obra. Não têm orçamento e ficam separados das obras.",
                  linhas: semObra.map(linhaCentro),
                },
              ]}
            />
          </>
        )}
      </Bloco>

      {centroId && (
        <Bloco
          id="categorias"
          titulo="Por categoria"
          contexto={`${posicaoEm}. Conta sem categoria aparece como Sem categoria, nunca em outra linha.`}
        >
          {categorias === null && <ErroBloco />}
          {categorias?.length === 0 && <p>{mensagens.despesas.semCategorias}</p>}
          {categorias && categorias.length > 0 && (
            <TabelaPorCentro
              legenda={`Custos por categoria, ${nomeRecorte}, ${posicaoEm.toLowerCase()}, em reais`}
              rotuloPrimeira="Categoria"
              colunas={colunasPorCentro.slice(0, 6)}
              grupos={[{ linhas: linhasCategoria(categorias, resumoCentro?.motivo ?? null) }]}
            />
          )}
        </Bloco>
      )}

      <Bloco
        id="periodo"
        titulo={`Lançado e pago em ${periodo.rotulo}`}
        contexto={`${nomeRecorte}. Lançado pelo mês de competência (emissão); pago pela data do pagamento. Os dois eixos de tempo não se somam.`}
      >
        {desembolso === null && <ErroBloco />}
        {desembolso?.length === 0 && <p>{mensagens.despesas.semPeriodo}</p>}
        {desembolso && desembolso.length > 0 && (
          <TabelaPorCentro
            legenda={`Títulos lançados e pagos por categoria, ${nomeRecorte}, ${periodo.rotulo}, em reais`}
            rotuloPrimeira="Categoria"
            colunas={[
              { chave: "lancado", rotulo: "Lançado por competência", explicacao: "lancado_competencia" },
              { chave: "pago", rotulo: "Pago no período", explicacao: "pago_periodo" },
            ]}
            grupos={[{ linhas: linhasDesembolso(desembolso) }]}
          />
        )}
      </Bloco>
    </>
  );
}
