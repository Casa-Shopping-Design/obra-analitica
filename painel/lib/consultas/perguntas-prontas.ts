import "server-only";
import { criarClienteServidor } from "@/lib/supabase/servidor";
import { ErroConsulta } from "@/lib/consultas/posicao";
import { rotuloLinha } from "@/lib/dre";
import { rotulosAlerta, type IdPerguntaPronta } from "@/lib/perguntas-prontas";

export type LinhaResposta = Record<string, string | number | null>;

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

type ConsultaPergunta = (supabase: Cliente) => Promise<LinhaResposta[]>;

// Uma função por pergunta, com filtros do cliente Supabase: nada de SQL em texto nem de entrada do usuário.
// O RLS de quem está logado decide quais obras aparecem.
const consultas: Record<IdPerguntaPronta, ConsultaPergunta> = {
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

  async "exposicao-maxima"(supabase) {
    return lerLinhas(
      await supabase
        .schema("marts")
        .from("posicao_financeira_obra")
        .select("obra, exposicao_maxima")
        .order("exposicao_maxima", { ascending: false })
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

  async "tempo-vender-estoque"(supabase) {
    return lerLinhas(
      await supabase
        .schema("marts")
        .from("estoque_obra")
        .select("obra, unidades_estoque, meses_para_vender_estoque, data_entrega, meses_ate_entrega")
        .order("meses_para_vender_estoque", { ascending: false, nullsFirst: true })
        .limit(limiteLinhas),
    );
  },

  async "exposicao-carteira"(supabase) {
    return lerLinhas(
      await supabase
        .schema("marts")
        .from("posicao_carteira")
        .select("obras, exposicao_maxima, mes_exposicao_maxima, soma_exposicao_obras")
        .limit(limiteLinhas),
    );
  },

  async "obras-pedem-atencao"(supabase) {
    const linhas = lerLinhas(
      await supabase
        .schema("marts")
        .from("alertas_obra")
        .select("obra, tipo")
        .order("obra")
        .order("tipo")
        .limit(limiteLinhas),
    );
    // Tipo fora da lista sai nulo, como no case do sql da pergunta.
    const rotulos: Record<string, string> = rotulosAlerta;
    return linhas.map(({ obra, tipo }) => ({ obra, tipo: rotulos[String(tipo)] ?? null }));
  },

  async "estoque-tipologia-preco-hoje"(supabase) {
    const linhas = lerLinhas(
      await supabase
        .schema("marts")
        .from("estoque_tipologia")
        .select("centro_custo_id, tipologia, disponiveis, reservadas, propostas, valor_estoque, preco_m2_estoque")
        .order("tipologia")
        .limit(limiteLinhas),
    );
    const comNome = await incluirNomeObra(supabase, linhas);
    return comNome.sort((a, b) => porObra(a, b) || String(a.tipologia).localeCompare(String(b.tipologia), "pt-BR"));
  },

  // As cinco abaixo leem views que o RLS abre só a diretor, financeiro e leitura; a tela já filtra pelo perfil
  // e, se a consulta chegar aqui por outro caminho, volta vazia.
  async "tendencia-lucro-obras"(supabase) {
    return lerLinhas(
      await supabase
        .schema("marts")
        .from("dre_viabilidade")
        .select("obra, viabilidade, tendencia, desvio, desvio_pct")
        .eq("linha", "lucro_operacional")
        .order("desvio")
        .limit(limiteLinhas),
    );
  },

  async "linha-mais-desvia-parque"(supabase) {
    const linhas = lerLinhas(
      await supabase
        .schema("marts")
        .from("dre_viabilidade")
        .select("obra, linha, viabilidade, tendencia, desvio")
        .ilike("obra", "%parque%")
        .eq("linha_de_total", false)
        .eq("desvio_favoravel", false)
        .limit(limiteLinhas),
    );
    // O cliente não ordena por abs(); são no máximo onze linhas por obra, ordenadas aqui sem mudar valor.
    return linhas
      .sort((a, b) => Math.abs(Number(b.desvio)) - Math.abs(Number(a.desvio)))
      .slice(0, 3)
      .map((linha) => ({ ...linha, linha: rotuloLinha(String(linha.linha)) }));
  },

  async "margem-perdida-obras"(supabase) {
    return lerLinhas(
      await supabase
        .schema("marts")
        .from("dre_resumo_obra")
        .select("obra, margem_operacional_viabilidade, margem_operacional_tendencia, desvio_margem_operacional")
        .order("desvio_margem_operacional")
        .limit(limiteLinhas),
    );
  },

  async "receita-a-apropriar-obras"(supabase) {
    return lerLinhas(
      await supabase
        .schema("marts")
        .from("dre_viabilidade")
        .select("obra, apropriado, a_apropriar, a_contratar")
        .eq("linha", "vgv_bruto")
        .order("obra")
        .limit(limiteLinhas),
    );
  },

  async "imposto-a-gerar-obras"(supabase) {
    return lerLinhas(
      await supabase
        .schema("marts")
        .from("imposto_obra")
        .select("obra, aliquota, imposto_receita_a_apropriar, imposto_vgv_estoque, imposto_a_realizar")
        .order("imposto_a_realizar", { ascending: false })
        .limit(limiteLinhas),
    );
  },
};

export type RespostaPerguntaPronta = { linhas: LinhaResposta[]; consultadoEm: string };

export async function responderPerguntaPronta(id: IdPerguntaPronta): Promise<RespostaPerguntaPronta> {
  const supabase = await criarClienteServidor();
  const linhas = await consultas[id](supabase);
  const hoje = hojeEmBrasilia();
  return { linhas, consultadoEm: dataIso(hoje.ano, hoje.mes, hoje.dia) };
}
