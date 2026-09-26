import "server-only";
import { ErroConsulta } from "@/lib/consultas/posicao";
import { converterColunas } from "@/lib/consultas/referencia";
import type { CodigoMotivo } from "@/lib/mensagens";
import { criarClienteServidor } from "@/lib/supabase/servidor";

export type { CodigoMotivo };

// Tipos da seção 6.3 do contrato de dados; colunas iguais às das views da migration 0011.
export type CodigoLinhaDre =
  | "receita_bruta"
  | "deducoes"
  | "receita_liquida"
  | "custo_imovel_vendido"
  | "resultado_bruto"
  | "despesas_comerciais"
  | "despesas_administrativas"
  | "resultado_financeiro"
  | "resultado_gerencial"
  | "custo_obra_incorrido"
  | "fora_do_resultado"
  | "sem_categoria"
  | "sem_data_competencia";

export type GrupoDre =
  | "receita_bruta"
  | "deducao_receita"
  | "custo_imovel"
  | "despesa_comercial"
  | "despesa_administrativa"
  | "resultado_financeiro"
  | "fora_do_resultado";

export type LinhaDreMensal = {
  tenant_id: string;
  centro_custo_id: string;
  tipo_centro: "obra" | "empresa";
  competencia: string | null;
  linha_codigo: CodigoLinhaDre;
  linha_ordem: number;
  linha_nome: string;
  valor_mes: number | null;
  valor_acumulado: number | null;
  disponivel: boolean;
  motivo: CodigoMotivo | null;
  valor_com_categoria: number;
  valor_total_lancado: number;
  cobertura: number | null;
};

export type LinhaDreConsolidado = Omit<LinhaDreMensal, "centro_custo_id" | "tipo_centro"> & {
  quantidade_centros: number;
};

export type LinhaDrePeriodo = {
  linha_codigo: CodigoLinhaDre;
  linha_ordem: number;
  linha_nome: string;
  valor_periodo: number | null;
  disponivel: boolean;
  motivo: CodigoMotivo | null;
  cobertura: number | null;
};

export type LinhaReconhecimentoObra = {
  tenant_id: string;
  centro_custo_id: string;
  competencia: string;
  metodo: "nao_definido" | "percentual_conclusao";
  disponivel: boolean;
  motivo: CodigoMotivo | null;
  custo_incorrido_acumulado: number;
  custo_total_estimado: number | null;
  poc: number | null;
  vgv_ativo_fim_mes: number;
  unidades_obra: number;
  unidades_vendidas_fim_mes: number;
  fracao_vendida: number | null;
  receita_reconhecida_acumulada: number | null;
  custo_reconhecido_acumulado: number | null;
  receita_reconhecida_mes: number | null;
  custo_reconhecido_mes: number | null;
};

export type LinhaPendenciaClassificacao = {
  tenant_id: string;
  tipo_origem: "titulo_pagar" | "parcela_receber" | "orcamento";
  conta_origem: string | null;
  quantidade_lancamentos: number;
  valor_envolvido: number;
  participacao: number | null;
  primeira_competencia: string | null;
  ultima_competencia: string | null;
};

export type CriterioReconhecimento = {
  id: string;
  tenant_id: string;
  centro_custo_id: string | null;
  metodo: "nao_definido" | "percentual_conclusao";
  base_fracao_vendida: "unidades";
  validado_por: string | null;
  validado_em: string | null;
  observacao: string | null;
};

export type CategoriaGerencial = {
  codigo: string;
  nome: string;
  grupo_dre: GrupoDre;
  natureza: "entrada" | "saida";
  ordem: number;
};

export type PendenciasClassificacao = { linhas: LinhaPendenciaClassificacao[]; total: number };

const colunasMensais =
  "competencia, linha_codigo, linha_ordem, linha_nome, valor_mes, valor_acumulado, disponivel, motivo, valor_com_categoria, valor_total_lancado, cobertura";

// Uma chamada: a função soma os meses no Postgres. Centro nulo é o consolidado do que o RLS libera.
export async function listarDrePeriodo(
  inicio: string,
  fim: string,
  centroCustoId: string | null,
): Promise<LinhaDrePeriodo[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .rpc("dre_periodo", { p_inicio: inicio, p_fim: fim, p_centro_custo_id: centroCustoId })
    .select("linha_codigo, linha_ordem, linha_nome, valor_periodo, disponivel, motivo, cobertura")
    .order("linha_ordem");
  if (error) throw new ErroConsulta(error.code);
  return converterColunas<LinhaDrePeriodo>(data ?? [], [], ["valor_periodo", "cobertura"]);
}

// Até 12 linhas por mês; com 12 meses dá 156 linhas. O filtro por centro e competência cai no índice da 0011.
export async function listarDreMensalObra(
  centroCustoId: string,
  inicio: string,
  fim: string,
): Promise<Omit<LinhaDreMensal, "tenant_id" | "centro_custo_id" | "tipo_centro">[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("dre_mensal")
    .select(colunasMensais)
    .eq("centro_custo_id", centroCustoId)
    .gte("competencia", inicio)
    .lte("competencia", fim)
    .order("competencia")
    .order("linha_ordem");
  if (error) throw new ErroConsulta(error.code);
  return converterColunas(
    data ?? [],
    ["valor_com_categoria", "valor_total_lancado"],
    ["valor_mes", "valor_acumulado", "cobertura"],
  );
}

export async function listarDreMensalConsolidado(
  inicio: string,
  fim: string,
): Promise<Omit<LinhaDreConsolidado, "tenant_id">[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("dre_mensal_consolidado")
    .select(`${colunasMensais}, quantidade_centros`)
    .gte("competencia", inicio)
    .lte("competencia", fim)
    .order("competencia")
    .order("linha_ordem");
  if (error) throw new ErroConsulta(error.code);
  return converterColunas(
    data ?? [],
    ["valor_com_categoria", "valor_total_lancado", "quantidade_centros"],
    ["valor_mes", "valor_acumulado", "cobertura"],
  );
}

// Percentual de conclusão de cada obra no último mês do período; com obra escolhida, só ela.
export async function listarReconhecimentoNoMes(
  competencia: string,
  centroCustoId: string | null,
): Promise<LinhaReconhecimentoObra[]> {
  const supabase = await criarClienteServidor();
  let consulta = supabase.schema("marts").from("reconhecimento_obra_mensal").select("*").eq("competencia", competencia);
  if (centroCustoId) consulta = consulta.eq("centro_custo_id", centroCustoId);
  const { data, error } = await consulta.order("centro_custo_id");
  if (error) throw new ErroConsulta(error.code);
  return converterColunas<LinhaReconhecimentoObra>(
    data ?? [],
    ["custo_incorrido_acumulado", "vgv_ativo_fim_mes", "unidades_obra", "unidades_vendidas_fim_mes"],
    [
      "custo_total_estimado",
      "poc",
      "fracao_vendida",
      "receita_reconhecida_acumulada",
      "custo_reconhecido_acumulado",
      "receita_reconhecida_mes",
      "custo_reconhecido_mes",
    ],
  );
}

export const limitePendencias = 20;

// As contas de maior valor primeiro, com o total de contas pendentes contado no banco.
export async function listarPendenciasClassificacao(
  limite: number = limitePendencias,
): Promise<PendenciasClassificacao> {
  const supabase = await criarClienteServidor();
  const { data, error, count } = await supabase
    .schema("marts")
    .from("pendencia_classificacao")
    .select(
      "tipo_origem, conta_origem, quantidade_lancamentos, valor_envolvido, participacao, primeira_competencia, ultima_competencia",
      { count: "exact" },
    )
    .order("valor_envolvido", { ascending: false })
    .limit(limite);
  if (error) throw new ErroConsulta(error.code);
  return {
    linhas: converterColunas<LinhaPendenciaClassificacao>(
      data ?? [],
      ["quantidade_lancamentos", "valor_envolvido"],
      ["participacao"],
    ),
    total: count ?? 0,
  };
}

// Só a contagem, para o aviso da visão geral; head evita trazer as linhas.
export async function contarPendenciasClassificacao(): Promise<number> {
  const supabase = await criarClienteServidor();
  const { error, count } = await supabase
    .schema("marts")
    .from("pendencia_classificacao")
    .select("conta_origem", { count: "exact", head: true });
  if (error) throw new ErroConsulta(error.code);
  return count ?? 0;
}

// Lista fixa e global de categorias (19 linhas), para os formulários de classificação.
export async function listarCategoriasGerenciais(): Promise<CategoriaGerencial[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("app")
    .from("categoria_gerencial")
    .select("codigo, nome, grupo_dre, natureza, ordem")
    .order("ordem");
  if (error) throw new ErroConsulta(error.code);
  return converterColunas<CategoriaGerencial>(data ?? [], ["ordem"]);
}

// Critério do tenant (centro nulo) e das obras que o RLS libera; poucas linhas.
export async function listarCriteriosReconhecimento(): Promise<CriterioReconhecimento[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("app")
    .from("criterio_reconhecimento")
    .select("id, tenant_id, centro_custo_id, metodo, base_fracao_vendida, validado_por, validado_em, observacao")
    .order("centro_custo_id", { nullsFirst: true });
  if (error) throw new ErroConsulta(error.code);
  return (data ?? []) as CriterioReconhecimento[];
}

export type MapeamentoConta = {
  tipo_origem: LinhaPendenciaClassificacao["tipo_origem"];
  conta_origem: string;
  categoria_codigo: string;
  observacao: string | null;
  atualizado_em: string;
};

export const limiteMapeamentos = 200;

// Contas já classificadas, as mais recentes primeiro, para quem precisa corrigir uma classificação.
export async function listarMapeamentos(): Promise<{ linhas: MapeamentoConta[]; total: number }> {
  const supabase = await criarClienteServidor();
  const { data, error, count } = await supabase
    .schema("app")
    .from("mapa_conta_origem")
    .select("tipo_origem, conta_origem, categoria_codigo, observacao, atualizado_em", { count: "exact" })
    .order("atualizado_em", { ascending: false })
    .limit(limiteMapeamentos);
  if (error) throw new ErroConsulta(error.code);
  return { linhas: (data ?? []) as MapeamentoConta[], total: count ?? 0 };
}
