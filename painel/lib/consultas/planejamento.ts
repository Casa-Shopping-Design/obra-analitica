import "server-only";
import { ErroConsulta } from "@/lib/consultas/posicao";
import { converterColunas } from "@/lib/consultas/referencia";
import { criarClienteServidor } from "@/lib/supabase/servidor";
import { colunasValorFluxoProjetado } from "@/lib/consultas/fluxo";

// Tipos da seção 6.7 do contrato de dados; colunas iguais às tabelas e views da migration 0013.
export type TipoVersao = "meta" | "projecao";

export type VersaoPlanejamento = {
  id: string;
  tenant_id: string;
  centro_custo_id: string;
  tipo: TipoVersao;
  numero: number;
  descricao: string;
  data_referencia: string;
  premissas: Record<string, unknown>;
  autor: string;
  criada_em: string;
};

export type LinhaMetaMensal = {
  versao_id: string;
  tenant_id: string;
  centro_custo_id: string;
  competencia: string;
  unidades: number | null;
  valor_contratado: number | null;
  fracao_financiada: number | null;
  recebimento_esperado: number | null;
  limite_aporte_proprio: number | null;
};

export type LinhaComparativoProjecao = {
  tenant_id: string;
  centro_custo_id: string;
  competencia: string;
  versao_original_id: string | null;
  versao_original_numero: number | null;
  original_total_entradas: number | null;
  original_total_saidas: number | null;
  original_caixa_gerado_acumulado: number | null;
  atual_total_entradas: number;
  atual_total_saidas: number;
  atual_caixa_gerado_acumulado: number;
  realizado_entradas: number | null;
  realizado_saidas: number | null;
  diferenca_caixa_acumulado: number | null;
};

export type CausaDesvio =
  | "vendas_abaixo_meta"
  | "vendas_acima_meta"
  | "parcelas_vencidas_sem_pagamento"
  | "financiamento_nao_elegivel"
  | "liberacao_prevista_vencida"
  | "gasto_acima_previsto";

export type LinhaExplicacaoDesvio = {
  tenant_id: string;
  centro_custo_id: string;
  competencia: string;
  causa_codigo: CausaDesvio;
  causa_descricao: string;
  quantidade: number | null;
  valor: number | null;
  origem_dado: "origem" | "complemento_manual" | "versao_planejamento";
};

export type LinhaVisaoGerencial = {
  tenant_id: string;
  centro_custo_id: string;
  competencia: string;
  meta_unidades: number | null;
  meta_valor_contratado: number | null;
  meta_limite_aporte: number | null;
  vendas_unidades: number;
  vendas_valor: number;
  distratos_unidades: number;
  entrada_direta_prevista_original: number | null;
  entrada_direta_recebida: number;
  financiamento_previsto_original: number | null;
  financiamento_recebido: number;
  gastos_previstos_original: number | null;
  gastos_realizados: number;
  caixa_gerado_acumulado: number;
  necessidade_aporte_acumulada: number;
  caixa_gerado_acumulado_original: number | null;
  diferenca_original_atual: number | null;
};

export type LinhaPendenciaPosEntrega = {
  tenant_id: string;
  centro_custo_id: string;
  obra: string;
  data_entrega: string;
  recebiveis_vencidos: number;
  recebiveis_a_vencer: number;
  parcelas_abertas: number;
  titulos_em_aberto: number;
  titulos_abertos: number;
  liberacoes_nao_recebidas: number;
  credito_nao_liberado: number;
};

export type PremissaDistribuicao = {
  id: string;
  centro_custo_id: string;
  metodo: "fracao_mensal";
  fonte: string;
  observacao: string | null;
  criada_em: string;
  meses: { competencia: string; fracao: number }[];
};

// Linha de app.projecao_mensal: as colunas numéricas do fluxo projetado congeladas numa versão.
export type LinhaProjecaoVersao = { versao_id: string; competencia: string } & Record<
  (typeof colunasValorFluxoProjetado)[number],
  number
>;

export type JanelaMeses = { centroCustoId: string | null; inicio?: string | null; fim?: string | null };

const colunasVisaoValor = [
  "vendas_unidades",
  "vendas_valor",
  "distratos_unidades",
  "entrada_direta_recebida",
  "financiamento_recebido",
  "gastos_realizados",
  "caixa_gerado_acumulado",
  "necessidade_aporte_acumulada",
] as const;
const colunasVisaoAnulaveis = [
  "meta_unidades",
  "meta_valor_contratado",
  "meta_limite_aporte",
  "entrada_direta_prevista_original",
  "financiamento_previsto_original",
  "gastos_previstos_original",
  "caixa_gerado_acumulado_original",
  "diferenca_original_atual",
] as const;

// Uma linha por obra e mês; o recorte de meses cai no filtro de competência.
export async function listarVisaoGerencial(janela: JanelaMeses): Promise<LinhaVisaoGerencial[]> {
  const supabase = await criarClienteServidor();
  let consulta = supabase
    .schema("marts")
    .from("visao_gerencial_mensal")
    .select(`centro_custo_id, competencia, ${[...colunasVisaoValor, ...colunasVisaoAnulaveis].join(", ")}`);
  if (janela.centroCustoId) consulta = consulta.eq("centro_custo_id", janela.centroCustoId);
  if (janela.inicio) consulta = consulta.gte("competencia", janela.inicio);
  if (janela.fim) consulta = consulta.lte("competencia", janela.fim);
  const { data, error } = await consulta.order("centro_custo_id").order("competencia");
  if (error) throw new ErroConsulta(error.code);
  return converterColunas<LinhaVisaoGerencial>(data ?? [], colunasVisaoValor, colunasVisaoAnulaveis);
}

// A view só devolve causas que os dados sustentam; a tela não acrescenta nenhuma.
export async function listarExplicacaoDesvio(janela: JanelaMeses): Promise<LinhaExplicacaoDesvio[]> {
  const supabase = await criarClienteServidor();
  let consulta = supabase
    .schema("marts")
    .from("explicacao_desvio")
    .select("centro_custo_id, competencia, causa_codigo, causa_descricao, quantidade, valor, origem_dado");
  if (janela.centroCustoId) consulta = consulta.eq("centro_custo_id", janela.centroCustoId);
  if (janela.inicio) consulta = consulta.gte("competencia", janela.inicio);
  if (janela.fim) consulta = consulta.lte("competencia", janela.fim);
  const { data, error } = await consulta.order("competencia", { ascending: false }).order("causa_codigo");
  if (error) throw new ErroConsulta(error.code);
  return converterColunas<LinhaExplicacaoDesvio>(data ?? [], [], ["quantidade", "valor"]);
}

const colunasComparativoValor = ["atual_total_entradas", "atual_total_saidas", "atual_caixa_gerado_acumulado"] as const;
const colunasComparativoAnulaveis = [
  "versao_original_numero",
  "original_total_entradas",
  "original_total_saidas",
  "original_caixa_gerado_acumulado",
  "realizado_entradas",
  "realizado_saidas",
  "diferenca_caixa_acumulado",
] as const;

export async function listarComparativo(janela: JanelaMeses): Promise<LinhaComparativoProjecao[]> {
  const supabase = await criarClienteServidor();
  let consulta = supabase
    .schema("marts")
    .from("comparativo_projecao")
    .select(
      `centro_custo_id, competencia, versao_original_id, ${[...colunasComparativoValor, ...colunasComparativoAnulaveis].join(", ")}`,
    );
  if (janela.centroCustoId) consulta = consulta.eq("centro_custo_id", janela.centroCustoId);
  if (janela.inicio) consulta = consulta.gte("competencia", janela.inicio);
  if (janela.fim) consulta = consulta.lte("competencia", janela.fim);
  const { data, error } = await consulta.order("centro_custo_id").order("competencia");
  if (error) throw new ErroConsulta(error.code);
  return converterColunas<LinhaComparativoProjecao>(data ?? [], colunasComparativoValor, colunasComparativoAnulaveis);
}

// Versões de uma obra, a mais nova primeiro. Poucas dezenas por obra ao longo da construção.
export async function listarVersoes(centroCustoId: string, tipo: TipoVersao): Promise<VersaoPlanejamento[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("app")
    .from("versao_planejamento")
    .select("id, centro_custo_id, tipo, numero, descricao, data_referencia, premissas, criada_em")
    .eq("centro_custo_id", centroCustoId)
    .eq("tipo", tipo)
    .order("numero", { ascending: false });
  if (error) throw new ErroConsulta(error.code);
  return converterColunas<VersaoPlanejamento>(data ?? [], ["numero"]);
}

// Metas de até duas versões numa consulta só, para mostrar a vigente e comparar com outra.
export async function listarMetasDasVersoes(versaoIds: string[]): Promise<LinhaMetaMensal[]> {
  if (versaoIds.length === 0) return [];
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("app")
    .from("meta_mensal")
    .select(
      "versao_id, centro_custo_id, competencia, unidades, valor_contratado, fracao_financiada, recebimento_esperado, limite_aporte_proprio",
    )
    .in("versao_id", versaoIds)
    .order("competencia");
  if (error) throw new ErroConsulta(error.code);
  return converterColunas<LinhaMetaMensal>(
    data ?? [],
    [],
    ["unidades", "valor_contratado", "fracao_financiada", "recebimento_esperado", "limite_aporte_proprio"],
  );
}

// Fotografia de uma versão de projeção, para comparar com o fluxo de hoje lado a lado.
export async function listarProjecaoDaVersao(versaoId: string): Promise<LinhaProjecaoVersao[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("app")
    .from("projecao_mensal")
    .select(`versao_id, competencia, ${colunasValorFluxoProjetado.join(", ")}`)
    .eq("versao_id", versaoId)
    .order("competencia");
  if (error) throw new ErroConsulta(error.code);
  return converterColunas<LinhaProjecaoVersao>(data ?? [], colunasValorFluxoProjetado);
}

export async function listarPendenciasPosEntrega(centroCustoId: string | null): Promise<LinhaPendenciaPosEntrega[]> {
  const supabase = await criarClienteServidor();
  let consulta = supabase
    .schema("marts")
    .from("pendencias_pos_entrega")
    .select(
      "centro_custo_id, obra, data_entrega, recebiveis_vencidos, recebiveis_a_vencer, parcelas_abertas, titulos_em_aberto, titulos_abertos, liberacoes_nao_recebidas, credito_nao_liberado",
    );
  if (centroCustoId) consulta = consulta.eq("centro_custo_id", centroCustoId);
  const { data, error } = await consulta.order("data_entrega");
  if (error) throw new ErroConsulta(error.code);
  return converterColunas<LinhaPendenciaPosEntrega>(data ?? [], [
    "recebiveis_vencidos",
    "recebiveis_a_vencer",
    "parcelas_abertas",
    "titulos_em_aberto",
    "titulos_abertos",
    "liberacoes_nao_recebidas",
    "credito_nao_liberado",
  ]);
}

// Premissa vigente é a mais nova (seção 3.4.1). Uma ida só: os meses vêm embutidos pela chave estrangeira
// premissa_distribuicao_custo_mes.premissa_id; o RLS vale nas duas tabelas.
export async function buscarPremissaVigente(centroCustoId: string): Promise<PremissaDistribuicao | null> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("app")
    .from("premissa_distribuicao_custo")
    .select("id, centro_custo_id, metodo, fonte, observacao, criada_em, meses:premissa_distribuicao_custo_mes(competencia, fracao)")
    .eq("centro_custo_id", centroCustoId)
    .order("criada_em", { ascending: false })
    .limit(1)
    .maybeSingle<Omit<PremissaDistribuicao, "meses"> & { meses: { competencia: string; fracao: unknown }[] | null }>();
  if (error) throw new ErroConsulta(error.code);
  if (!data) return null;
  // No máximo 60 meses; ordenar aqui evita depender da ordem do recurso embutido.
  const meses = converterColunas<{ competencia: string; fracao: number }>(data.meses ?? [], ["fracao"]).sort((a, b) =>
    a.competencia < b.competencia ? -1 : 1,
  );
  return { ...data, meses };
}

export type Escritor = { usuarioId: string; perfil: "diretor" | "financeiro" };
export type ResultadoEscritor = { ok: true; escritor: Escritor } | { ok: false; motivo: "sem_sessao" | "sem_permissao" };

type Cliente = Awaited<ReturnType<typeof criarClienteServidor>>;

// getUser valida o token no Auth. O perfil vem de app.usuario_tenant pelo tenant atual, nunca de user_metadata.
// A conferência só adianta a mensagem: quem decide a gravação é o RLS com o JWT do usuário.
export async function conferirEscritor(supabase: Cliente): Promise<ResultadoEscritor> {
  const { data: dadosUsuario } = await supabase.auth.getUser();
  if (!dadosUsuario.user) return { ok: false, motivo: "sem_sessao" };
  // app.perfil_atual() lê o perfil do tenant de app.tenant_atual() (claim tenant_id do JWT), a mesma regra do RLS.
  const { data: perfil, error } = await supabase.schema("app").rpc("perfil_atual");
  if (error) throw new ErroConsulta(error.code);
  if (perfil !== "diretor" && perfil !== "financeiro") return { ok: false, motivo: "sem_permissao" };
  return { ok: true, escritor: { usuarioId: dadosUsuario.user.id, perfil } };
}

// A obra precisa estar visível ao usuário; o tenant_id gravado é o da própria obra, que o RLS confere de novo.
export async function buscarObraParaEscrita(
  supabase: Cliente,
  centroCustoId: string,
): Promise<{ id: string; tenant_id: string } | null> {
  const { data, error } = await supabase
    .schema("app")
    .from("centro_custo")
    .select("id, tenant_id")
    .eq("id", centroCustoId)
    .eq("tipo", "obra")
    .maybeSingle<{ id: string; tenant_id: string }>();
  if (error) throw new ErroConsulta(error.code);
  return data;
}
