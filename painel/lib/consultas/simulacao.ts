import "server-only";
import { criarClienteServidor } from "@/lib/supabase/servidor";
import { ErroConsulta } from "@/lib/consultas/posicao";
import { numeroOuZero } from "@/lib/consultas/resumo-origem";
import type { DescontoPercentual, Ritmo } from "@/lib/simulacao";

export type PontoSimulacao = {
  competencia: string;
  entradaDireta: number;
  repasse: number;
  saldoAtual: number;
  saldoSimulado: number;
};

export type ResumoSimulacao = {
  unidades_estoque: number;
  mes_ultima_venda: string | null;
  receita_simulada: number;
  exposicao_atual: number;
  mes_exposicao_atual: string | null;
  exposicao_simulada: number;
  mes_exposicao_simulada: string | null;
  mes_saldo_positivo: string | null;
};

function parametros(centroCustoId: string, ritmo: Ritmo, desconto: DescontoPercentual) {
  return { p_centro_custo_id: centroCustoId, p_unidades_mes: ritmo, p_desconto: desconto / 100 };
}

// A função devolve a obra inteira, uma linha por mês com movimento; poucas dezenas na demo.
export async function listarSimulacao(
  centroCustoId: string,
  ritmo: Ritmo,
  desconto: DescontoPercentual,
): Promise<PontoSimulacao[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .rpc("simular_venda_estoque", parametros(centroCustoId, ritmo, desconto));
  if (error) throw new ErroConsulta(error.code);
  return (data as Record<string, unknown>[]).map((linha) => ({
    competencia: String(linha.competencia).slice(0, 7),
    entradaDireta: numeroOuZero(linha.entrada_direta_simulada),
    repasse: numeroOuZero(linha.repasse_simulado),
    saldoAtual: numeroOuZero(linha.saldo_acumulado_atual),
    saldoSimulado: numeroOuZero(linha.saldo_acumulado_simulado),
  }));
}

export async function buscarResumoSimulacao(
  centroCustoId: string,
  ritmo: Ritmo,
  desconto: DescontoPercentual,
): Promise<ResumoSimulacao | null> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .rpc("resumo_venda_estoque", parametros(centroCustoId, ritmo, desconto))
    .maybeSingle<Record<string, unknown>>();
  if (error) throw new ErroConsulta(error.code);
  if (!data) return null;
  const textoOuNulo = (valor: unknown) => (valor ? String(valor) : null);
  return {
    unidades_estoque: numeroOuZero(data.unidades_estoque),
    mes_ultima_venda: textoOuNulo(data.mes_ultima_venda),
    receita_simulada: numeroOuZero(data.receita_simulada),
    exposicao_atual: numeroOuZero(data.exposicao_atual),
    mes_exposicao_atual: textoOuNulo(data.mes_exposicao_atual),
    exposicao_simulada: numeroOuZero(data.exposicao_simulada),
    mes_exposicao_simulada: textoOuNulo(data.mes_exposicao_simulada),
    mes_saldo_positivo: textoOuNulo(data.mes_saldo_positivo),
  };
}
