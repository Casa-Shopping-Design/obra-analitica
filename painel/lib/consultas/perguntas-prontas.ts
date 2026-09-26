import "server-only";
// Imports relativos: o teste troca estes módulos por espiões e confere que cada pergunta nova
// chama a mesma função de consulta da tela correspondente.
import { criarClienteServidor } from "../supabase/servidor";
import { ErroConsulta } from "./posicao";
import { carregarReferencia, listarCentrosCusto, type CentroCusto } from "./referencia";
import { listarDrePeriodo, listarPendenciasClassificacao } from "./dre";
import { listarCustoPorCategoria } from "./despesas";
import { listarResumoReceitas } from "./receitas";
import { contarEstoqueSimulacao, listarFluxoProjetado, listarResumoProjecao, simularFluxo } from "./fluxo";
import {
  listarComparativo,
  listarExplicacaoDesvio,
  listarPendenciasPosEntrega,
  listarVisaoGerencial,
} from "./planejamento";
import { listarLiberacoes, listarSaldoOperacoes } from "./financiamento";
import {
  montarAporteDesteMes,
  montarAporteNecessario,
  montarCustoPorCategoria,
  montarExposicaoMaxima,
  montarFinanciamentosPendentes,
  montarLiberadoEPendente,
  montarMetaDoMes,
  montarMudouDesdeProjecao,
  montarPendenciasClassificacao,
  montarPosEntrega,
  montarPrevistoProximoMes,
  montarQuandoFaltaCaixa,
  montarRespostaSimples,
  montarResultadoGerencial,
  montarSimularVendas,
  type LinhaResposta,
  type NomesObras,
  type RespostaMontada,
} from "../../componentes/planejamento/respostas-perguntas";
import { buscarPerguntaPronta, type IdPerguntaPronta, type PerguntaPronta } from "../perguntas-prontas";
import { mesDaData, mesPorExtenso, somarMeses } from "../periodo";
import { formularioPadrao, validarPremissas } from "../simulacao";

export type { LinhaResposta };

// Mesmo teto de linhas que o PT-07 vai impor ao SQL gerado.
export const limiteLinhas = 500;

type Cliente = Awaited<ReturnType<typeof criarClienteServidor>>;
type ResultadoSupabase = { data: unknown; error: { code: string } | null };

function lerLinhas(resultado: ResultadoSupabase): LinhaResposta[] {
  if (resultado.error) throw new ErroConsulta(resultado.error.code);
  return (resultado.data ?? []) as LinhaResposta[];
}

// Datas no fuso de Brasília, para "este mês" e "este ano" não virarem na meia-noite UTC.
function hojeEmBrasilia(): { ano: number; mes: number; dia: number } {
  const [ano, mes, dia] = new Intl.DateTimeFormat("en-CA", { timeZone: "America/Sao_Paulo" })
    .format(new Date())
    .split("-")
    .map(Number);
  return { ano, mes, dia };
}

// Mês acima de 12 vira o ano seguinte e o dia é limitado ao fim do mês, como faz o "+ interval" do Postgres.
function dataIso(ano: number, mes: number, dia: number): string {
  const data = new Date(Date.UTC(ano, mes - 1, 1));
  const ultimoDia = new Date(Date.UTC(data.getUTCFullYear(), data.getUTCMonth() + 1, 0)).getUTCDate();
  data.setUTCDate(Math.min(dia, ultimoDia));
  return data.toISOString().slice(0, 10);
}

// O padrão do nome é constante do código, nunca texto do usuário.
async function idsObrasPorNome(supabase: Cliente, padrao: string): Promise<string[]> {
  const linhas = lerLinhas(await supabase.schema("app").from("centro_custo").select("id").ilike("nome", padrao));
  return linhas.map((linha) => String(linha.id));
}

// Views sem o nome da obra recebem o nome por dicionário: O(n) sobre as linhas, uma consulta só.
async function incluirNomeObra(supabase: Cliente, linhas: LinhaResposta[]): Promise<LinhaResposta[]> {
  if (linhas.length === 0) return linhas;
  const obras = lerLinhas(await supabase.schema("app").from("centro_custo").select("id, nome"));
  const nomePorId = new Map(obras.map((obra) => [String(obra.id), String(obra.nome)]));
  return linhas.map(({ centro_custo_id, ...resto }) => ({
    obra: nomePorId.get(String(centro_custo_id)) ?? "",
    ...resto,
  }));
}

const porObra = (a: LinhaResposta, b: LinhaResposta) => String(a.obra).localeCompare(String(b.obra), "pt-BR");

type ConsultaSimples = (supabase: Cliente) => Promise<LinhaResposta[]>;

// Perguntas da demo: uma função por pergunta, com filtros do cliente Supabase; nada de SQL em texto nem de
// entrada do usuário. O RLS de quem está logado decide quais obras aparecem.
const consultasSimples = {
  async "repasse-parque-6-meses"(supabase) {
    const ids = await idsObrasPorNome(supabase, "%parque%");
    if (ids.length === 0) return [];
    const hoje = hojeEmBrasilia();
    const linhas = lerLinhas(
      await supabase
        .schema("marts")
        .from("fluxo_caixa_mensal")
        .select("centro_custo_id, competencia, repasse_previsto")
        .in("centro_custo_id", ids)
        .gte("competencia", dataIso(hoje.ano, hoje.mes, 1))
        .lte("competencia", dataIso(hoje.ano, hoje.mes + 6, hoje.dia))
        .order("competencia")
        .limit(limiteLinhas),
    );
    return incluirNomeObra(supabase, linhas);
  },

  async "mes-mais-negativo-aurora"(supabase) {
    const ids = await idsObrasPorNome(supabase, "%aurora%");
    if (ids.length === 0) return [];
    const linhas = lerLinhas(
      await supabase
        .schema("marts")
        .from("fluxo_caixa_mensal")
        .select("centro_custo_id, competencia, saldo_acumulado")
        .in("centro_custo_id", ids)
        .order("saldo_acumulado")
        .limit(1),
    );
    return incluirNomeObra(supabase, linhas);
  },

  async "a-receber-aurora"(supabase) {
    return lerLinhas(
      await supabase
        .schema("marts")
        .from("posicao_financeira_obra")
        .select("obra, a_receber_repasse, repasse_atrasado, a_receber_direto, vencido_direto")
        .ilike("obra", "%aurora%")
        .limit(limiteLinhas),
    );
  },

  async "estouro-orcamento"(supabase) {
    return lerLinhas(
      await supabase
        .schema("marts")
        .from("posicao_financeira_obra")
        .select("obra, custo_orcado, pago, a_pagar, estouro_orcamento")
        .gt("estouro_orcamento", 0)
        .order("estouro_orcamento", { ascending: false })
        .limit(limiteLinhas),
    );
  },

  async "distratos-ano"(supabase) {
    const hoje = hojeEmBrasilia();
    const linhas = lerLinhas(
      await supabase
        .schema("marts")
        .from("vso_mensal")
        .select("centro_custo_id, competencia, distratos")
        .gte("competencia", dataIso(hoje.ano, 1, 1))
        .gt("distratos", 0)
        .order("competencia")
        .limit(limiteLinhas),
    );
    const comNome = await incluirNomeObra(supabase, linhas);
    return comNome.sort((a, b) => String(a.competencia).localeCompare(String(b.competencia)) || porObra(a, b));
  },

  async "unidades-disponiveis"(supabase) {
    const linhas = lerLinhas(
      await supabase
        .schema("marts")
        .from("estoque_atual")
        .select("centro_custo_id, tipologia, disponiveis, total")
        .order("tipologia")
        .limit(limiteLinhas),
    );
    const comNome = await incluirNomeObra(supabase, linhas);
    return comNome.sort((a, b) => porObra(a, b) || String(a.tipologia).localeCompare(String(b.tipologia), "pt-BR"));
  },

  async "preco-unidade-3q-0202-parque"(supabase) {
    const ids = await idsObrasPorNome(supabase, "%parque%");
    if (ids.length === 0) return [];
    const linhas = lerLinhas(
      await supabase
        .schema("marts")
        .from("mapa_unidades")
        .select("centro_custo_id, unidade, valor, valor_m2, indice_referencia")
        .in("centro_custo_id", ids)
        .eq("unidade", "3Q-0202")
        .limit(limiteLinhas),
    );
    return incluirNomeObra(supabase, linhas);
  },

  async "disponiveis-aurora"(supabase) {
    const ids = await idsObrasPorNome(supabase, "%aurora%");
    if (ids.length === 0) return [];
    const linhas = lerLinhas(
      await supabase
        .schema("marts")
        .from("mapa_unidades")
        .select("centro_custo_id, unidade, tipologia, area_privativa, valor")
        .in("centro_custo_id", ids)
        .eq("situacao", "disponivel")
        .order("tipologia")
        .order("unidade")
        .limit(limiteLinhas),
    );
    return incluirNomeObra(supabase, linhas);
  },

  async "cobertura-parque"(supabase) {
    return lerLinhas(
      await supabase
        .schema("marts")
        .from("cobertura_orcamento_obra")
        .select("obra, custo_orcado, vgv_contratado, unidades_para_cobrir")
        .ilike("obra", "%parque%")
        .limit(limiteLinhas),
    );
  },

  async "a-receber-banco"(supabase) {
    return lerLinhas(
      await supabase
        .schema("marts")
        .from("posicao_financeira_obra")
        .select("obra, a_receber_repasse, repasse_atrasado")
        .order("a_receber_repasse", { ascending: false })
        .limit(limiteLinhas),
    );
  },

  async "mais-vencido"(supabase) {
    return lerLinhas(
      await supabase
        .schema("marts")
        .from("posicao_financeira_obra")
        .select("obra, vencido_direto, repasse_atrasado")
        .order("vencido_direto", { ascending: false })
        .limit(limiteLinhas),
    );
  },

  async "estoque-preco-hoje"(supabase) {
    return lerLinhas(
      await supabase
        .schema("marts")
        .from("posicao_financeira_obra")
        .select("obra, estoque_a_vender")
        .order("estoque_a_vender", { ascending: false })
        .limit(limiteLinhas),
    );
  },
} satisfies Record<string, ConsultaSimples>;

// Premissas fixas da pergunta de simulação, validadas pela mesma função do formulário da tela.
export function premissasCincoUnidades(dataReferencia: string) {
  return {
    ...formularioPadrao(dataReferencia),
    vendas_por_mes: "5",
    meses_vendas: "1",
    mes_inicio_vendas: somarMeses(dataReferencia, 1).slice(0, 7),
  };
}

export type ContextoPergunta = {
  dataReferencia: string;
  obra: CentroCusto | null;
  nomes: NomesObras;
};

type ConsultaNova = (pergunta: PerguntaPronta, contexto: ContextoPergunta) => Promise<RespostaMontada>;

function exigirObra(contexto: ContextoPergunta): CentroCusto {
  if (!contexto.obra) throw new ErroConsulta("obra_obrigatoria");
  return contexto.obra;
}

// Perguntas novas: chamam as mesmas funções de lib/consultas que as telas usam (tela.consultas no catálogo)
// e só montam a resposta. Cada chamada independente vai em paralelo.
const consultasNovas = {
  async "resultado-gerencial-ano"(pergunta, contexto) {
    const mesReferencia = mesDaData(contexto.dataReferencia);
    const inicioAno = `${mesReferencia.slice(0, 4)}-01-01`;
    const [consolidado, daObra] = await Promise.all([
      listarDrePeriodo(inicioAno, mesReferencia, null),
      contexto.obra ? listarDrePeriodo(inicioAno, mesReferencia, contexto.obra.id) : Promise.resolve(null),
    ]);
    const rotuloPeriodo =
      inicioAno === mesReferencia ? mesPorExtenso(mesReferencia) : `janeiro a ${mesPorExtenso(mesReferencia)}`;
    const soResultado = (linhas: typeof consolidado) => linhas.filter((linha) => linha.linha_ordem < 100);
    return montarResultadoGerencial(pergunta, {
      consolidado: soResultado(consolidado),
      obra: daObra ? soResultado(daObra) : null,
      nomeObra: contexto.obra?.nome ?? null,
      rotuloPeriodo,
    });
  },

  async "previsto-proximo-mes"(pergunta, contexto) {
    const mes = somarMeses(contexto.dataReferencia, 1);
    const [parcelas, fontes] = await Promise.all([
      listarResumoReceitas(null),
      listarFluxoProjetado({ centroCustoId: null, inicio: mes, fim: mes }),
    ]);
    return montarPrevistoProximoMes(pergunta, { parcelas, fontes, nomes: contexto.nomes, mes });
  },

  async "custo-por-categoria"(pergunta, contexto) {
    const obra = exigirObra(contexto);
    const categorias = await listarCustoPorCategoria(obra.id);
    return montarCustoPorCategoria(pergunta, { categorias, nomeObra: obra.nome });
  },

  // Mesma fonte do cartão e da tabela da tela de fluxo: um número só para o aporte.
  async "exposicao-maxima"(pergunta) {
    return montarExposicaoMaxima(pergunta, { resumos: await listarResumoProjecao(null) });
  },

  async "aporte-necessario"(pergunta) {
    return montarAporteNecessario(pergunta, { resumos: await listarResumoProjecao(null) });
  },

  async "financiamentos-pendentes"(pergunta, contexto) {
    const [resumos, operacoes] = await Promise.all([listarResumoProjecao(null), listarSaldoOperacoes(null)]);
    return montarFinanciamentosPendentes(pergunta, { resumos, operacoes, nomes: contexto.nomes });
  },

  async "pendencias-classificacao"(pergunta) {
    return montarPendenciasClassificacao(pergunta, { pendencias: await listarPendenciasClassificacao() });
  },

  async "simular-vendas"(pergunta, contexto) {
    const obra = exigirObra(contexto);
    const [base, estoque] = await Promise.all([
      listarFluxoProjetado({ centroCustoId: obra.id }),
      contarEstoqueSimulacao(obra.id),
    ]);
    const validacao = validarPremissas(premissasCincoUnidades(contexto.dataReferencia), {
      dataReferencia: contexto.dataReferencia,
      estoque,
    });
    const simulacao = validacao.ok ? await simularFluxo(obra.id, validacao.premissas) : null;
    return montarSimularVendas(pergunta, { nomeObra: obra.nome, base, simulacao, validacao });
  },

  async "quando-falta-caixa"(pergunta, contexto) {
    const mesReferencia = mesDaData(contexto.dataReferencia);
    const [fluxo, resumos] = await Promise.all([
      listarFluxoProjetado({ centroCustoId: null, inicio: mesReferencia }),
      listarResumoProjecao(null),
    ]);
    return montarQuandoFaltaCaixa(pergunta, { fluxo, resumos, nomes: contexto.nomes, mesReferencia });
  },

  async "meta-do-mes"(pergunta, contexto) {
    const mes = mesDaData(contexto.dataReferencia);
    const janela = { centroCustoId: null, inicio: mes, fim: mes };
    const [visao, desvios] = await Promise.all([listarVisaoGerencial(janela), listarExplicacaoDesvio(janela)]);
    return montarMetaDoMes(pergunta, { visao, desvios, nomes: contexto.nomes, mes });
  },

  async "aporte-deste-mes"(pergunta, contexto) {
    const mes = mesDaData(contexto.dataReferencia);
    const [fluxo, resumos] = await Promise.all([
      listarFluxoProjetado({ centroCustoId: null, inicio: mes, fim: mes }),
      listarResumoProjecao(null),
    ]);
    return montarAporteDesteMes(pergunta, { fluxo, resumos, nomes: contexto.nomes, mes });
  },

  async "mudou-desde-projecao"(pergunta, contexto) {
    const obra = exigirObra(contexto);
    const mesReferencia = mesDaData(contexto.dataReferencia);
    const [comparativo, desvios] = await Promise.all([
      listarComparativo({ centroCustoId: obra.id, inicio: somarMeses(mesReferencia, -1), fim: somarMeses(mesReferencia, 12) }),
      listarExplicacaoDesvio({ centroCustoId: obra.id, inicio: somarMeses(mesReferencia, -1), fim: mesReferencia }),
    ]);
    return montarMudouDesdeProjecao(pergunta, { comparativo, desvios, nomeObra: obra.nome, mesReferencia });
  },

  async "liberado-e-pendente"(pergunta, contexto) {
    const [operacoes, liberacoes] = await Promise.all([
      listarSaldoOperacoes(null),
      listarLiberacoes({ centroCustoId: null, situacoesEfetivas: ["pendente", "atrasada"] }),
    ]);
    return montarLiberadoEPendente(pergunta, { operacoes, liberacoes, nomes: contexto.nomes });
  },

  async "pos-entrega"(pergunta) {
    return montarPosEntrega(pergunta, { pendencias: await listarPendenciasPosEntrega(null) });
  },
} satisfies Record<string, ConsultaNova>;

export type RespostaPerguntaPronta = {
  resposta: RespostaMontada;
  dataReferencia: string;
  consultadoEm: string;
  obra: CentroCusto | null;
};

// obraId já validado como UUID pela página; obra fora da lista do RLS é tratada como não escolhida.
export async function responderPerguntaPronta(
  id: IdPerguntaPronta,
  obraId: string | null = null,
): Promise<RespostaPerguntaPronta> {
  const pergunta = buscarPerguntaPronta(id) as PerguntaPronta;
  const hoje = hojeEmBrasilia();
  const consultadoEm = dataIso(hoje.ano, hoje.mes, hoje.dia);

  if (id in consultasSimples) {
    const supabase = await criarClienteServidor();
    const linhas = await consultasSimples[id as keyof typeof consultasSimples](supabase);
    return { resposta: montarRespostaSimples(pergunta, linhas), dataReferencia: consultadoEm, consultadoEm, obra: null };
  }

  const [referencia, centros] = await Promise.all([carregarReferencia(), listarCentrosCusto()]);
  const obras = centros.filter((centro) => centro.tipo === "obra");
  const nomes = Object.fromEntries(obras.map((centro) => [centro.id, centro.nome]));
  const escolhida = obras.find((centro) => centro.id === obraId) ?? null;
  const obra = escolhida ?? (pergunta.obra === "obrigatoria" ? (obras[0] ?? null) : null);
  const contexto: ContextoPergunta = { dataReferencia: referencia.dataReferencia, obra, nomes };
  const resposta = await consultasNovas[id as keyof typeof consultasNovas](pergunta, contexto);
  return { resposta, dataReferencia: referencia.dataReferencia, consultadoEm, obra };
}
