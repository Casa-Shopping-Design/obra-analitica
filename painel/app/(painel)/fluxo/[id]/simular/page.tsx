import type { Metadata } from "next";
import { exigirIdentidade } from "@/lib/consultas/identidade";
import Link from "next/link";
import { Aviso, Bloco } from "@/componentes/financeiro/Aviso";
import { AvisoCarga } from "@/componentes/financeiro/AvisoCarga";
import { Selo } from "@/componentes/financeiro/Selo";
import { CartaoPlanejamento } from "@/componentes/planejamento/CartaoPlanejamento";
import { GraficoResposta } from "@/componentes/planejamento/GraficoResposta";
import { TabelaPlanejamento } from "@/componentes/planejamento/TabelaPlanejamento";
import { Inteiro, Valor } from "@/componentes/planejamento/Valor";
import { ErroConsulta } from "@/lib/consultas/posicao";
import {
  contarEstoqueSimulacao,
  listarFluxoProjetado,
  listarResumoProjecao,
  simularFluxo,
  type LinhaSimulacao,
} from "@/lib/consultas/fluxo";
import { buscarPadroesSimulacao } from "@/lib/consultas/configuracao";
import { carregarReferencia, tentarConsulta } from "@/lib/consultas/referencia";
import { formatarMes } from "@/lib/formatar";
import { mensagens } from "@/lib/mensagens";
import { explicacoesPlanejamento, mensagensPlanejamento, rotulosNatureza } from "@/lib/mensagens-planejamento";
import { lerIdCentro, mesDaData, mesPorExtenso } from "@/lib/periodo";
import {
  juntarBaseESimulacao,
  lerFormularioSimulacao,
  limitesSimulacao,
  piorMes,
  validarPremissas,
  type CampoSimulacao,
  type FormularioSimulacao,
} from "@/lib/simulacao";

export const metadata: Metadata = { title: "Simular cenário" };

type Campo = {
  nome: CampoSimulacao;
  rotulo: string;
  ajuda?: string;
  tipo?: "month";
  sufixo?: string;
};

const grupos: { legenda: string; nota?: string; campos: Campo[] }[] = [
  {
    legenda: "Novas vendas",
    campos: [
      { nome: "vendas_por_mes", rotulo: "Unidades por mês", ajuda: "Limitado ao estoque à venda da obra." },
      { nome: "mes_inicio_vendas", rotulo: "A partir de", tipo: "month" },
      { nome: "meses_vendas", rotulo: "Durante quantos meses", ajuda: `De 1 a ${limitesSimulacao.mesesVendas}.` },
      { nome: "desconto", rotulo: "Desconto sobre a tabela de hoje", sufixo: "%" },
    ],
  },
  {
    legenda: "Como o comprador paga",
    nota: "Entrada, parcelas e financiamento somam 100%.",
    campos: [
      { nome: "entrada", rotulo: "Entrada", sufixo: "%" },
      { nome: "parcelas", rotulo: "Parcelas mensais", sufixo: "%" },
      { nome: "quantidade_parcelas", rotulo: "Número de parcelas mensais" },
      { nome: "financiamento", rotulo: "Financiamento bancário", sufixo: "%" },
      { nome: "meses_liberacao", rotulo: "Meses entre a venda e a liberação do financiamento" },
    ],
  },
  {
    legenda: "Banco e cronograma",
    campos: [
      { nome: "atraso_liberacao", rotulo: "Atraso nas liberações já previstas (meses)" },
      { nome: "deslocamento_gastos", rotulo: "Deslocar o custo sem título (meses)" },
      { nome: "fator_gastos", rotulo: "Custo sem título, em % do previsto", sufixo: "%" },
    ],
  },
  {
    legenda: "Campanha comercial (hipótese)",
    nota: mensagensPlanejamento.simulacao.campanhaHipotese,
    campos: [
      { nome: "mes_campanha", rotulo: "Mês do custo da campanha", tipo: "month" },
      { nome: "custo_campanha", rotulo: "Custo da campanha", sufixo: "R$" },
    ],
  },
];

function CampoFormulario({
  campo,
  formulario,
  erro,
}: {
  campo: Campo;
  formulario: FormularioSimulacao;
  erro: string | undefined;
}) {
  const id = `simular-${campo.nome}`;
  const descricoes = [campo.ajuda ? `${id}-ajuda` : null, erro ? `${id}-erro` : null].filter(Boolean).join(" ");
  return (
    <div className="flex min-w-0 flex-col gap-1.5">
      <label htmlFor={id} className="text-sm font-medium">
        {campo.rotulo}
        {campo.sufixo && <span className="text-suave"> ({campo.sufixo})</span>}
      </label>
      <input
        id={id}
        name={campo.nome}
        type={campo.tipo ?? "text"}
        inputMode={campo.tipo ? undefined : "decimal"}
        defaultValue={formulario[campo.nome]}
        aria-invalid={erro ? true : undefined}
        aria-describedby={descricoes || undefined}
        className={`min-h-11 w-full rounded-lg border bg-superficie px-3 tabular-nums ${erro ? "border-alerta" : "border-borda"}`}
      />
      {campo.ajuda && (
        <p id={`${id}-ajuda`} className="text-xs text-suave">
          {campo.ajuda}
        </p>
      )}
      {erro && (
        <p id={`${id}-erro`} className="text-sm text-alerta">
          {erro}
        </p>
      )}
    </div>
  );
}

// Premissas validadas aqui antes de chegar ao banco; a função do banco valida de novo e nunca grava.
async function rodarSimulacao(centroId: string, premissas: Parameters<typeof simularFluxo>[1]) {
  try {
    return { linhas: await simularFluxo(centroId, premissas), erro: null };
  } catch (erro) {
    const recusada = erro instanceof ErroConsulta && erro.message === "22023";
    return {
      linhas: null,
      erro: recusada ? mensagensPlanejamento.simulacao.premissaRecusada : mensagensPlanejamento.simulacao.indisponivel,
    };
  }
}

function colunasResultado() {
  return [
    { chave: "novas_unidades", rotulo: "Novas vendas (unidades)" },
    { chave: "novas_valor", rotulo: "Valor das novas vendas" },
    { chave: "novas_direta", rotulo: "Entradas das novas vendas: comprador" },
    { chave: "novas_financiamento", rotulo: "Entradas das novas vendas: banco" },
    { chave: "recebido", rotulo: "Recebido (fato)" },
    { chave: "carteira", rotulo: "Carteira prevista" },
    { chave: "pago", rotulo: "Pago (fato)" },
    { chave: "a_pagar", rotulo: "A pagar" },
    { chave: "custo_sem_titulo", rotulo: "Custo sem título" },
    { chave: "campanha", rotulo: "Campanha (hipótese)" },
    { chave: "saldo", rotulo: "Saldo do mês" },
    { chave: "caixa", rotulo: "Caixa gerado acumulado", explicacao: explicacoesPlanejamento.caixa_gerado_acumulado },
    { chave: "aporte", rotulo: "Aporte necessário", explicacao: explicacoesPlanejamento.necessidade_aporte_acumulada },
  ];
}

function linhaResultado(linha: LinhaSimulacao) {
  return {
    chave: linha.competencia,
    rotulo: (
      <span className="inline-flex flex-col">
        {formatarMes(linha.competencia)}
        {linha.aviso === "vendas_limitadas_ao_estoque" && <Selo tipo="parcial">venda limitada ao estoque</Selo>}
      </span>
    ),
    celulas: {
      novas_unidades: <Inteiro valor={linha.novas_vendas_unidades} />,
      novas_valor: <Valor valor={linha.novas_vendas_valor} />,
      novas_direta: <Valor valor={linha.entradas_novas_vendas_direta} />,
      novas_financiamento: <Valor valor={linha.entradas_novas_vendas_financiamento} />,
      recebido: <Valor valor={linha.recebido} />,
      carteira: <Valor valor={linha.carteira_prevista} />,
      pago: <Valor valor={linha.pago} />,
      a_pagar: <Valor valor={linha.a_pagar} />,
      custo_sem_titulo: <Valor valor={linha.custo_sem_titulo} />,
      campanha: <Valor valor={linha.custo_campanha} />,
      saldo: <Valor valor={linha.saldo_mes} />,
      caixa: <Valor valor={linha.caixa_gerado_acumulado} />,
      aporte: <Valor valor={linha.necessidade_aporte_acumulada} />,
    },
  };
}

export default async function PaginaSimular({ params, searchParams }: PageProps<"/fluxo/[id]/simular">) {
  // A rota confere a sessão por conta própria; o proxy e o layout sozinhos não bastam.
  await exigirIdentidade();
  const { id } = await params;
  const filtros = await searchParams;
  const centroId = lerIdCentro(id);
  const referencia = await carregarReferencia();
  const [resumos, base, estoque, padroes] = centroId
    ? await Promise.all([
        tentarConsulta(listarResumoProjecao(centroId)),
        tentarConsulta(listarFluxoProjetado({ centroCustoId: centroId })),
        tentarConsulta(contarEstoqueSimulacao(centroId)),
        buscarPadroesSimulacao(centroId),
      ])
    : [[], null, null, null];
  if (!centroId || (resumos !== null && resumos.length === 0)) {
    return (
      <>
        <h1 className="font-serif text-[34px] font-semibold">{mensagens.obra.naoEncontrada}</h1>
        <Link href="/fluxo" className="underline underline-offset-4 hover:text-menu">
          Voltar para o fluxo de caixa
        </Link>
      </>
    );
  }

  const nomeObra = resumos?.[0]?.obra ?? "Obra";
  const formulario = lerFormularioSimulacao(filtros, referencia.dataReferencia, padroes);
  const pediuSimulacao = filtros.simular === "1";
  const validacao = pediuSimulacao
    ? validarPremissas(formulario, { dataReferencia: referencia.dataReferencia, estoque })
    : null;
  const resultado = validacao?.ok ? await rodarSimulacao(centroId, validacao.premissas) : null;
  const erros = validacao && !validacao.ok ? validacao.erros : {};
  const mesReferencia = mesDaData(referencia.dataReferencia);
  const simuladas = resultado?.linhas ?? null;
  const piorBase = base ? piorMes(base) : null;
  const piorSimulado = simuladas ? piorMes(simuladas) : null;

  return (
    <>
      <header className="flex flex-col gap-2">
        <Link href={`/fluxo/${centroId}`} className="text-sm text-suave underline underline-offset-4 hover:text-texto">
          Fluxo de caixa da {nomeObra}
        </Link>
        <h1 className="font-serif text-[34px] font-semibold">Simular cenário</h1>
        <p className="max-w-3xl text-suave">{mensagensPlanejamento.simulacao.realizadoIntocado}</p>
        <AvisoCarga referencia={referencia} />
      </header>

      <form
        method="get"
        aria-label="Premissas da simulação"
        className="flex flex-col gap-5 rounded-xl border border-borda bg-superficie p-4 md:p-5"
        noValidate
      >
        <input type="hidden" name="simular" value="1" />
        <p className="text-sm text-suave">
          {estoque === null
            ? "Não foi possível contar o estoque agora; o simulador limita as vendas ao que houver."
            : `Estoque à venda na ${nomeObra}: ${estoque} ${estoque === 1 ? "unidade" : "unidades"}, pelo preço de tabela de hoje.`}
        </p>
        {grupos.map((grupo) => (
          <fieldset key={grupo.legenda} className="flex flex-col gap-3">
            <legend className="mb-1 font-semibold">{grupo.legenda}</legend>
            {grupo.nota && <p className="text-sm text-suave">{grupo.nota}</p>}
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
              {grupo.campos.map((campo) => (
                <CampoFormulario key={campo.nome} campo={campo} formulario={formulario} erro={erros[campo.nome]} />
              ))}
            </div>
          </fieldset>
        ))}
        <div className="flex flex-wrap items-center gap-3">
          <button
            type="submit"
            className="min-h-11 cursor-pointer rounded-lg bg-menu px-5 font-semibold text-menu-texto hover:bg-menu-ativo"
          >
            Simular
          </button>
          <Link href={`/fluxo/${centroId}/simular`} className="text-sm underline underline-offset-4">
            Voltar às premissas padrão
          </Link>
        </div>
        <p className="text-sm text-suave">
          Desconto, composição do pagamento, número de parcelas e meses até a liberação começam com os padrões da obra.{" "}
          <Link
            href={`/configuracoes?escopo=${centroId}#grupo-simulacao`}
            className="underline underline-offset-4 hover:text-menu"
          >
            Ver os padrões em Configurações
          </Link>
        </p>
        <div aria-live="polite" className="text-sm">
          {validacao && !validacao.ok && <p className="text-alerta">{mensagensPlanejamento.simulacao.corrijaCampos}</p>}
          {resultado?.erro && <p className="text-alerta">{resultado.erro}</p>}
        </div>
      </form>

      {validacao?.ok && simuladas && (
        <>
          <Bloco
            id="premissas"
            titulo="Premissas usadas"
            contexto={`${rotulosNatureza.simulacao.rotulo}. ${rotulosNatureza.simulacao.descricao}`}
          >
            <dl className="grid gap-x-6 gap-y-1.5 text-sm sm:grid-cols-[auto_1fr]">
              {validacao.resumo.map((item) => (
                <div key={item.rotulo} className="contents">
                  <dt className="text-suave">{item.rotulo}</dt>
                  <dd>{item.valor}</dd>
                </div>
              ))}
            </dl>
            {simuladas.some((linha) => linha.aviso === "vendas_limitadas_ao_estoque") && (
              <Aviso titulo="Vendas limitadas">{mensagensPlanejamento.simulacao.vendasLimitadas}</Aviso>
            )}
          </Bloco>

          <section aria-label="Resultado da simulação" className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <CartaoPlanejamento
              rotulo="Maior aporte na projeção de hoje"
              explicacao={explicacoesPlanejamento.exposicao_maxima_projetada}
              valor={<Valor valor={piorBase?.necessidade_aporte_acumulada ?? 0} />}
              contexto={
                piorBase
                  ? `Em ${mesPorExtenso(piorBase.competencia)}. Previsão contratual.`
                  : "Sem aporte. Previsão contratual."
              }
            />
            <CartaoPlanejamento
              rotulo="Maior aporte no cenário"
              explicacao={explicacoesPlanejamento.simulacao}
              valor={<Valor valor={piorSimulado?.necessidade_aporte_acumulada ?? 0} />}
              selo={<Selo tipo="parcial">simulação</Selo>}
              contexto={
                piorSimulado ? `Em ${mesPorExtenso(piorSimulado.competencia)}.` : "O cenário não precisa de aporte."
              }
            />
          </section>

          <Bloco
            id="resultado"
            titulo="Caixa gerado acumulado: hoje e no cenário"
            contexto="Nada foi gravado. O realizado é o mesmo nas duas linhas."
          >
            {base && (
              <GraficoResposta
                idBase="simulacao"
                grafico={{
                  tipo: "linhas",
                  titulo: "Caixa gerado acumulado",
                  eixo: "competencia",
                  formatoEixo: "mes",
                  series: [
                    { chave: "base", rotulo: "Projeção de hoje", estilo: "cheio" },
                    { chave: "simulado", rotulo: "Cenário simulado", estilo: "tracejado" },
                  ],
                  pontos: juntarBaseESimulacao(base, simuladas),
                }}
              />
            )}
            <p className="text-sm text-suave">
              A tabela abaixo traz os números do gráfico, do mês de referência em diante.
            </p>
            <TabelaPlanejamento
              legenda="Resultado da simulação por mês, em reais"
              rotuloPrimeira="Mês"
              colunas={colunasResultado()}
              linhas={simuladas.filter((linha) => linha.competencia.slice(0, 10) >= mesReferencia).map(linhaResultado)}
            />
          </Bloco>
        </>
      )}
    </>
  );
}
