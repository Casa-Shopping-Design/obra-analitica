import "server-only";
import { ErroConsulta } from "@/lib/consultas/posicao";
import { converterColunas } from "@/lib/consultas/referencia";
import { intervaloDaPagina, linhasPorPagina } from "@/lib/periodo";
import { criarClienteServidor } from "@/lib/supabase/servidor";

// Tipos da seção 6.4 do contrato de dados; colunas iguais às views da migration 0011.
export type SituacaoParcela = "quitada" | "vencida" | "a_vencer" | "cancelada_distrato" | "baixada_sem_recebimento";
export type OrigemRecebivel = "direta" | "financiamento";

export type LinhaCarteiraRecebiveis = {
  tenant_id: string;
  centro_custo_id: string;
  contrato_id_origem: number;
  contrato_numero: string | null;
  unidade_id_origem: number | null;
  unidade: string | null;
  parcela_id_origem: number;
  numero_parcela: string | null;
  tipo_condicao: string | null;
  origem: OrigemRecebivel;
  vencimento: string;
  valor_original: number;
  valor_recebido: number;
  saldo: number;
  data_ultimo_recebimento: string | null;
  situacao: SituacaoParcela;
  parcial: boolean;
  dias_atraso: number | null;
  situacao_contrato: "ativo" | "distratado" | "outra" | null;
  inadimplente_origem: boolean | null;
};

export type ResumoReceitasObra = {
  tenant_id: string;
  centro_custo_id: string;
  obra: string;
  tipo_centro: "obra" | "empresa";
  vgv_contratado_ativo: number;
  contratos_ativos: number;
  contratos_distratados: number;
  recebido_direto: number;
  recebido_financiamento: number;
  vencido_direto: number;
  vencido_financiamento: number;
  a_vencer_direto: number;
  a_vencer_financiamento: number;
  previsto_proximo_mes_direto: number;
  previsto_proximo_mes_financiamento: number;
  saldo_distratado: number;
  data_referencia: string;
};

export type LinhaRecebimentoMensal = {
  tenant_id: string;
  centro_custo_id: string;
  competencia: string;
  origem: OrigemRecebivel;
  recebido: number;
  previsto_contratual: number;
  saldo_em_aberto: number;
};

export type LinhaRecebimentoPeriodo = { origem: OrigemRecebivel; recebido: number; previsto_contratual: number };

export type FiltrosCarteira = {
  centroCustoId: string | null;
  situacao: SituacaoParcela | null;
  origem: OrigemRecebivel | null;
  vencimentoDe: string | null;
  vencimentoAte: string | null;
  pagina: number;
};

export type PaginaCarteira = { linhas: LinhaCarteiraRecebiveis[]; total: number };

const colunasResumo = [
  "vgv_contratado_ativo",
  "contratos_ativos",
  "contratos_distratados",
  "recebido_direto",
  "recebido_financiamento",
  "vencido_direto",
  "vencido_financiamento",
  "a_vencer_direto",
  "a_vencer_financiamento",
  "previsto_proximo_mes_direto",
  "previsto_proximo_mes_financiamento",
  "saldo_distratado",
] as const;

// Uma linha por obra; o centro "Despesas sem obra" não tem venda e fica fora.
export async function listarResumoReceitas(centroCustoId: string | null): Promise<ResumoReceitasObra[]> {
  const supabase = await criarClienteServidor();
  let consulta = supabase
    .schema("marts")
    .from("resumo_receitas_obra")
    .select(`centro_custo_id, obra, tipo_centro, data_referencia, ${colunasResumo.join(", ")}`)
    .eq("tipo_centro", "obra");
  if (centroCustoId) consulta = consulta.eq("centro_custo_id", centroCustoId);
  const { data, error } = await consulta.order("obra");
  if (error) throw new ErroConsulta(error.code);
  return converterColunas<ResumoReceitasObra>(data ?? [], colunasResumo);
}

// marts.resumo_receitas_consolidado (seção 3.2.16): uma linha com a soma das obras que o RLS libera.
export type ResumoReceitasConsolidado = Omit<ResumoReceitasObra, "centro_custo_id" | "obra" | "tipo_centro"> & {
  quantidade_obras: number;
};

export async function buscarResumoReceitasConsolidado(): Promise<ResumoReceitasConsolidado | null> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("resumo_receitas_consolidado")
    .select(`quantidade_obras, data_referencia, ${colunasResumo.join(", ")}`)
    .maybeSingle();
  if (error) throw new ErroConsulta(error.code);
  return converterColunas<ResumoReceitasConsolidado>(data, [...colunasResumo, "quantidade_obras"])[0] ?? null;
}

export async function listarRecebimentoPeriodo(
  inicio: string,
  fim: string,
  centroCustoId: string | null,
): Promise<LinhaRecebimentoPeriodo[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .rpc("recebimento_periodo", { p_inicio: inicio, p_fim: fim, p_centro_custo_id: centroCustoId })
    .select("origem, recebido, previsto_contratual");
  if (error) throw new ErroConsulta(error.code);
  return converterColunas<LinhaRecebimentoPeriodo>(data ?? [], ["recebido", "previsto_contratual"]);
}

// No máximo duas linhas por mês (direta e financiamento) de uma obra.
export async function listarRecebimentoMensal(
  centroCustoId: string,
  inicio: string,
  fim: string,
): Promise<LinhaRecebimentoMensal[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("recebimento_mensal")
    .select("competencia, origem, recebido, previsto_contratual, saldo_em_aberto")
    .eq("centro_custo_id", centroCustoId)
    .gte("competencia", inicio)
    .lte("competencia", fim)
    .order("competencia")
    .order("origem");
  if (error) throw new ErroConsulta(error.code);
  return converterColunas<LinhaRecebimentoMensal>(data ?? [], ["recebido", "previsto_contratual", "saldo_em_aberto"]);
}

// Mesma série de recebimento_mensal, somada no Postgres sobre as obras liberadas.
export async function listarRecebimentoMensalConsolidado(
  inicio: string,
  fim: string,
): Promise<LinhaRecebimentoMensal[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("recebimento_mensal_consolidado")
    .select("competencia, origem, recebido, previsto_contratual, saldo_em_aberto")
    .gte("competencia", inicio)
    .lte("competencia", fim)
    .order("competencia")
    .order("origem");
  if (error) throw new ErroConsulta(error.code);
  return converterColunas<LinhaRecebimentoMensal>(data ?? [], ["recebido", "previsto_contratual", "saldo_em_aberto"]);
}

// Nome de comprador não está na view e não é pedido. A contagem exata cobre até 30.000 parcelas por tenant.
const colunasCarteira =
  "centro_custo_id, contrato_id_origem, contrato_numero, unidade, parcela_id_origem, numero_parcela, tipo_condicao, origem, vencimento, valor_original, valor_recebido, saldo, data_ultimo_recebimento, situacao, parcial, dias_atraso, situacao_contrato";

export async function listarCarteira(filtros: FiltrosCarteira): Promise<PaginaCarteira> {
  const supabase = await criarClienteServidor();
  const { de, ate } = intervaloDaPagina(filtros.pagina, linhasPorPagina);
  let consulta = supabase.schema("marts").from("carteira_recebiveis").select(colunasCarteira, { count: "exact" });
  if (filtros.centroCustoId) consulta = consulta.eq("centro_custo_id", filtros.centroCustoId);
  if (filtros.situacao) consulta = consulta.eq("situacao", filtros.situacao);
  if (filtros.origem) consulta = consulta.eq("origem", filtros.origem);
  if (filtros.vencimentoDe) consulta = consulta.gte("vencimento", filtros.vencimentoDe);
  if (filtros.vencimentoAte) consulta = consulta.lte("vencimento", filtros.vencimentoAte);
  const { data, error, count } = await consulta
    .order("vencimento")
    .order("contrato_numero")
    .order("parcela_id_origem")
    .range(de, ate);
  // 416 do PostgREST (PGRST103) é página além do fim: devolve vazio com o total para a tela oferecer a última.
  if (error && error.code !== "PGRST103") throw new ErroConsulta(error.code);
  return {
    linhas: converterColunas<LinhaCarteiraRecebiveis>(
      data ?? [],
      ["valor_original", "valor_recebido", "saldo"],
      ["dias_atraso"],
    ),
    total: count ?? 0,
  };
}
