import "server-only";
import type { CodigoMotivo, GrupoDre } from "@/lib/consultas/dre";
import { ErroConsulta } from "@/lib/consultas/posicao";
import { converterColunas } from "@/lib/consultas/referencia";
import { criarClienteServidor } from "@/lib/supabase/servidor";

// Tipos da seção 6.5 do contrato de dados; colunas iguais às views da migration 0011.
export type CustoObraResumo = {
  tenant_id: string;
  centro_custo_id: string;
  obra: string;
  tipo_centro: "obra" | "empresa";
  orcamento_vigente: number | null;
  orcamento_original: null;
  custo_lancado: number;
  desembolsado: number;
  em_aberto_vencido: number;
  em_aberto_a_vencer: number;
  ajuste_baixa: number;
  remanescente_sem_titulo: number | null;
  estimativa_conclusao: number | null;
  desvio: number | null;
  compromissos_nao_faturados: null;
  cobertura_classificacao: number | null;
  motivo: CodigoMotivo | null;
};

export type LinhaCustoObraCategoria = {
  tenant_id: string;
  centro_custo_id: string;
  tipo_centro: "obra" | "empresa";
  categoria_codigo: string | null;
  categoria_nome: string;
  grupo_dre: GrupoDre | null;
  orcamento_vigente: number | null;
  custo_lancado: number;
  desembolsado: number;
  em_aberto_vencido: number;
  em_aberto_a_vencer: number;
  ajuste_baixa: number;
};

export type LinhaDespesaMensal = {
  tenant_id: string;
  centro_custo_id: string;
  competencia: string;
  categoria_codigo: string | null;
  categoria_nome: string;
  grupo_dre: GrupoDre | null;
  lancado_competencia: number;
  pago: number;
  a_pagar: number;
  vencido: number;
};

export type LinhaDesembolsoPeriodo = {
  categoria_codigo: string | null;
  categoria_nome: string;
  grupo_dre: GrupoDre | null;
  lancado_competencia: number;
  pago: number;
};

const colunasValorResumo = [
  "custo_lancado",
  "desembolsado",
  "em_aberto_vencido",
  "em_aberto_a_vencer",
  "ajuste_baixa",
] as const;
const colunasAnulaveisResumo = [
  "orcamento_vigente",
  "orcamento_original",
  "remanescente_sem_titulo",
  "estimativa_conclusao",
  "desvio",
  "compromissos_nao_faturados",
  "cobertura_classificacao",
] as const;

// Uma linha por centro liberado, obras primeiro e "Despesas sem obra" por último.
export async function listarCustoResumo(centroCustoId: string | null): Promise<CustoObraResumo[]> {
  const supabase = await criarClienteServidor();
  let consulta = supabase
    .schema("marts")
    .from("custo_obra_resumo")
    .select(
      `centro_custo_id, obra, tipo_centro, motivo, ${[...colunasValorResumo, ...colunasAnulaveisResumo].join(", ")}`,
    );
  if (centroCustoId) consulta = consulta.eq("centro_custo_id", centroCustoId);
  const { data, error } = await consulta.order("tipo_centro", { ascending: false }).order("obra");
  if (error) throw new ErroConsulta(error.code);
  return converterColunas<CustoObraResumo>(data ?? [], colunasValorResumo, colunasAnulaveisResumo);
}

// Posição atual por categoria de um centro, maior custo primeiro; "Sem categoria" vem com código nulo.
export async function listarCustoPorCategoria(centroCustoId: string): Promise<LinhaCustoObraCategoria[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("custo_obra_categoria")
    .select(
      "categoria_codigo, categoria_nome, grupo_dre, orcamento_vigente, custo_lancado, desembolsado, em_aberto_vencido, em_aberto_a_vencer, ajuste_baixa",
    )
    .eq("centro_custo_id", centroCustoId)
    .order("custo_lancado", { ascending: false });
  if (error) throw new ErroConsulta(error.code);
  return converterColunas<LinhaCustoObraCategoria>(data ?? [], colunasValorResumo, ["orcamento_vigente"]);
}

// Lançado por competência e pago por data de pagamento no período, somados por categoria no Postgres.
export async function listarDesembolsoPeriodo(
  inicio: string,
  fim: string,
  centroCustoId: string | null,
): Promise<LinhaDesembolsoPeriodo[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .rpc("desembolso_periodo", { p_inicio: inicio, p_fim: fim, p_centro_custo_id: centroCustoId })
    .select("categoria_codigo, categoria_nome, grupo_dre, lancado_competencia, pago")
    .order("lancado_competencia", { ascending: false });
  if (error) throw new ErroConsulta(error.code);
  return converterColunas<LinhaDesembolsoPeriodo>(data ?? [], ["lancado_competencia", "pago"]);
}

export type GrupoCusto = "obras" | "despesas_sem_obra";

// marts.custo_obra_resumo_consolidado (seção 3.2.16): uma linha por grupo, somada no Postgres sobre o que o RLS libera.
export type CustoResumoConsolidado = {
  tenant_id: string;
  grupo: GrupoCusto;
  quantidade_centros: number;
  centros_sem_orcamento: number | null;
  orcamento_vigente: number | null;
  custo_lancado: number;
  desembolsado: number;
  em_aberto_vencido: number;
  em_aberto_a_vencer: number;
  ajuste_baixa: number;
  remanescente_sem_titulo: number | null;
  estimativa_conclusao: number | null;
  desvio: number | null;
  cobertura_classificacao: number | null;
  motivo: CodigoMotivo | null;
};

export async function listarCustoResumoConsolidado(): Promise<CustoResumoConsolidado[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("custo_obra_resumo_consolidado")
    .select(
      "grupo, quantidade_centros, centros_sem_orcamento, orcamento_vigente, custo_lancado, desembolsado, em_aberto_vencido, em_aberto_a_vencer, ajuste_baixa, remanescente_sem_titulo, estimativa_conclusao, desvio, cobertura_classificacao, motivo",
    )
    .order("grupo", { ascending: false });
  if (error) throw new ErroConsulta(error.code);
  return converterColunas<CustoResumoConsolidado>(
    data ?? [],
    [...colunasValorResumo, "quantidade_centros"],
    [
      "centros_sem_orcamento",
      "orcamento_vigente",
      "remanescente_sem_titulo",
      "estimativa_conclusao",
      "desvio",
      "cobertura_classificacao",
    ],
  );
}
