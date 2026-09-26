import "server-only";
import { criarClienteServidor } from "@/lib/supabase/servidor";
import { ErroConsulta } from "@/lib/consultas/posicao";
import { converterColunas } from "@/lib/consultas/referencia";
import { objetoAusente } from "@/lib/consultas/configuracao";
import type { CodigoMotivo } from "@/lib/mensagens";
import type { LinhaFluxoCenario, LinhaFluxoMensal } from "@/lib/serie-fluxo";
import type { LinhaSimulacao, PremissasSimulacao } from "@/lib/simulacao";

export type { LinhaSimulacao, PremissasSimulacao };

export const cenariosAtraso = [0, 1, 3, 6] as const;
export type MesesAtraso = (typeof cenariosAtraso)[number];

const colunasMensais = [
  "competencia",
  "entrada_direta_realizada",
  "entrada_direta_prevista",
  "entrada_direta_vencida",
  "repasse_realizado",
  "repasse_previsto",
  "repasse_vencido",
  "saida_realizada",
  "saida_prevista",
  "saida_vencida",
  "saldo_acumulado",
].join(", ");

// Uma consulta por obra. centro_custo_id é chave da partição da janela da view, então o filtro desce até
// staging, onde o RLS acrescenta tenant_id e os dois caem no índice (tenant_id, centro_custo_id, vencimento).
export async function listarFluxoMensal(centroCustoId: string): Promise<LinhaFluxoMensal[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("fluxo_caixa_mensal")
    .select(colunasMensais)
    .eq("centro_custo_id", centroCustoId)
    .order("competencia");
  if (error) throw new ErroConsulta(error.code);
  return data as unknown as LinhaFluxoMensal[];
}

// A função devolve todas as obras que o RLS libera; o filtro por obra vai junto na mesma chamada.
export async function listarFluxoCenario(
  centroCustoId: string,
  mesesAtraso: MesesAtraso,
): Promise<LinhaFluxoCenario[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .rpc("fluxo_caixa_cenario", { p_meses_atraso: mesesAtraso })
    .select("competencia, entrada_direta, repasse, saida, saldo_acumulado")
    .eq("centro_custo_id", centroCustoId)
    .order("competencia");
  if (error) throw new ErroConsulta(error.code);
  return data as unknown as LinhaFluxoCenario[];
}

// Tipos da seção 6.6 do contrato de dados; colunas iguais às views da migration 0013.
export type LinhaFluxoProjetado = {
  tenant_id: string;
  centro_custo_id: string;
  competencia: string;
  eh_passado: boolean;
  recebido_direto: number;
  recebido_financiamento: number;
  credito_producao_recebido: number;
  previsto_direto: number;
  previsto_financiamento_elegivel: number;
  previsto_financiamento_pendente: number;
  credito_producao_previsto: number;
  vencido_a_receber: number;
  pago: number;
  a_pagar: number;
  a_pagar_vencido: number;
  custo_sem_titulo_distribuido: number;
  total_entradas: number;
  total_saidas: number;
  saldo_mes: number;
  caixa_gerado_acumulado: number;
  necessidade_aporte_acumulada: number;
  aporte_incremental_mes: number;
  caixa_gerado_acumulado_conservador: number;
  necessidade_aporte_conservadora: number;
  // Parte do vencido a receber que entra no mês de referência quando caixa.receber_vencido = mes_referencia.
  vencido_recuperacao_prevista: number;
};

export type ResumoProjecaoObra = {
  tenant_id: string;
  centro_custo_id: string;
  obra: string;
  data_referencia: string;
  exposicao_maxima_projetada: number;
  mes_exposicao_maxima: string | null;
  exposicao_maxima_conservadora: number;
  custo_sem_titulo_total: number | null;
  custo_sem_titulo_distribuido_total: number;
  custo_sem_titulo_nao_distribuido: number | null;
  premissa_distribuicao_id: string | null;
  motivo_distribuicao: CodigoMotivo | null;
  exposicao_parcial: boolean;
  vencido_a_receber: number;
  a_pagar_vencido: number;
  financiamento_pendente_total: number;
};

export const colunasValorFluxoProjetado = [
  "recebido_direto",
  "recebido_financiamento",
  "credito_producao_recebido",
  "previsto_direto",
  "previsto_financiamento_elegivel",
  "previsto_financiamento_pendente",
  "credito_producao_previsto",
  "vencido_a_receber",
  "pago",
  "a_pagar",
  "a_pagar_vencido",
  "custo_sem_titulo_distribuido",
  "total_entradas",
  "total_saidas",
  "saldo_mes",
  "caixa_gerado_acumulado",
  "necessidade_aporte_acumulada",
  "aporte_incremental_mes",
  "caixa_gerado_acumulado_conservador",
  "necessidade_aporte_conservadora",
  "vencido_recuperacao_prevista",
] as const;

export type FiltroFluxoProjetado = { centroCustoId: string | null; inicio?: string | null; fim?: string | null };

// Obra escolhida: os meses dela, 40 a 60 linhas. Sem obra, as obras que o RLS libera, com o recorte de meses
// obrigatório na tela que usa (10 obras x poucos meses). Filtro em centro e competência, ordem no banco.
export async function listarFluxoProjetado(filtro: FiltroFluxoProjetado): Promise<LinhaFluxoProjetado[]> {
  const supabase = await criarClienteServidor();
  let consulta = supabase
    .schema("marts")
    .from("fluxo_projetado_mensal")
    .select(`centro_custo_id, competencia, eh_passado, ${colunasValorFluxoProjetado.join(", ")}`);
  if (filtro.centroCustoId) consulta = consulta.eq("centro_custo_id", filtro.centroCustoId);
  if (filtro.inicio) consulta = consulta.gte("competencia", filtro.inicio);
  if (filtro.fim) consulta = consulta.lte("competencia", filtro.fim);
  const { data, error } = await consulta.order("centro_custo_id").order("competencia");
  if (error) throw new ErroConsulta(error.code);
  return converterColunas<LinhaFluxoProjetado>(data ?? [], colunasValorFluxoProjetado);
}

const colunasValorResumo = [
  "exposicao_maxima_projetada",
  "exposicao_maxima_conservadora",
  "custo_sem_titulo_distribuido_total",
  "vencido_a_receber",
  "a_pagar_vencido",
  "financiamento_pendente_total",
] as const;
const colunasAnulaveisResumo = ["custo_sem_titulo_total", "custo_sem_titulo_nao_distribuido"] as const;

// Uma linha por obra liberada; com obra escolhida, só ela.
export async function listarResumoProjecao(centroCustoId: string | null): Promise<ResumoProjecaoObra[]> {
  const supabase = await criarClienteServidor();
  let consulta = supabase
    .schema("marts")
    .from("resumo_projecao_obra")
    .select(
      `centro_custo_id, obra, data_referencia, mes_exposicao_maxima, premissa_distribuicao_id, motivo_distribuicao, exposicao_parcial, ${[...colunasValorResumo, ...colunasAnulaveisResumo].join(", ")}`,
    );
  if (centroCustoId) consulta = consulta.eq("centro_custo_id", centroCustoId);
  const { data, error } = await consulta.order("obra");
  if (error) throw new ErroConsulta(error.code);
  return converterColunas<ResumoProjecaoObra>(data ?? [], colunasValorResumo, colunasAnulaveisResumo);
}

const colunasValorSimulacao = [
  "recebido",
  "carteira_prevista",
  "novas_vendas_unidades",
  "novas_vendas_valor",
  "entradas_novas_vendas_direta",
  "entradas_novas_vendas_financiamento",
  "pago",
  "a_pagar",
  "custo_sem_titulo",
  "custo_campanha",
  "total_entradas",
  "total_saidas",
  "saldo_mes",
  "caixa_gerado_acumulado",
  "necessidade_aporte_acumulada",
  "aporte_incremental_mes",
] as const;

// Premissas já validadas em lib/simulacao.ts vão como objeto jsonb; a função é security invoker e não grava.
// Obra fora das permitidas volta sem linhas pelo RLS.
export async function simularFluxo(centroCustoId: string, premissas: PremissasSimulacao): Promise<LinhaSimulacao[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .rpc("simular_fluxo", { p_centro_custo_id: centroCustoId, p_premissas: premissas })
    .order("competencia");
  if (error) throw new ErroConsulta(error.code);
  return converterColunas<LinhaSimulacao>(data ?? [], colunasValorSimulacao);
}

// Mesma base de estoque da simulação (seção 4.1, regra 3); só a contagem, sem trazer as linhas.
export async function contarEstoqueSimulacao(centroCustoId: string): Promise<number> {
  const supabase = await criarClienteServidor();
  const { error, count } = await supabase
    .schema("marts")
    .from("mapa_unidades")
    .select("unidade_id", { count: "exact", head: true })
    .eq("centro_custo_id", centroCustoId)
    .in("situacao", ["disponivel", "reservada", "proposta"])
    .not("valor", "is", null);
  if (error) throw new ErroConsulta(error.code);
  return count ?? 0;
}

export type LinhaFluxoConsolidado = Pick<
  LinhaFluxoProjetado,
  | "competencia"
  | "eh_passado"
  | "total_entradas"
  | "total_saidas"
  | "saldo_mes"
  | "caixa_gerado_acumulado"
  | "necessidade_aporte_acumulada"
  | "aporte_incremental_mes"
  | "caixa_gerado_acumulado_conservador"
  | "necessidade_aporte_conservadora"
  | "vencido_recuperacao_prevista"
>;

const colunasConsolidado = [
  "total_entradas",
  "total_saidas",
  "saldo_mes",
  "caixa_gerado_acumulado",
  "necessidade_aporte_acumulada",
  "aporte_incremental_mes",
  "caixa_gerado_acumulado_conservador",
  "necessidade_aporte_conservadora",
  "vencido_recuperacao_prevista",
] as const;

// Série do tenant com as obras somadas (o caixa de uma cobre a outra), uma linha por mês, somada no banco.
// Nulo quando a view ainda não existe no banco: a tela mostra então só a lista por obra.
export async function listarFluxoConsolidado(): Promise<LinhaFluxoConsolidado[] | null> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("fluxo_projetado_consolidado")
    .select(`competencia, eh_passado, ${colunasConsolidado.join(", ")}`)
    .order("competencia");
  if (error) {
    if (objetoAusente(error.code)) return null;
    throw new ErroConsulta(error.code);
  }
  return converterColunas<LinhaFluxoConsolidado>(data ?? [], colunasConsolidado);
}
