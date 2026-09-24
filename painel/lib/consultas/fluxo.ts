import "server-only";
import { criarClienteServidor } from "@/lib/supabase/servidor";
import { ErroConsulta } from "@/lib/consultas/posicao";
import type { LinhaFluxoCenario, LinhaFluxoMensal } from "@/lib/serie-fluxo";

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
