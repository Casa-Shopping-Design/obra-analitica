import "server-only";
import { criarClienteServidor } from "@/lib/supabase/servidor";
import { lerComparativo, type LinhaComparativo } from "@/lib/comparativo";
import { ErroConsulta } from "@/lib/consultas/posicao";

const colunas =
  "centro_custo_id, obra, vgv_total, pct_vgv_vendido, vendas_liquidas_12m, estoque_inicio_12m, vso_12m, unidades_estoque, valor_estoque, resultado_projetado, margem_projetada, exposicao_maxima, caixa_atual, vencido_direto, pct_inadimplencia, pct_fisico, pct_financeiro, diferenca_financeiro_fisico, alertas";

// Uma consulta para a tela inteira: a junção dos marts roda no Postgres (migration 0027) e o RLS filtra as obras.
export async function listarComparativo(): Promise<LinhaComparativo[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase.schema("marts").from("comparativo_obras").select(colunas).order("obra");
  if (error) throw new ErroConsulta(error.code);
  return lerComparativo(data as Record<string, unknown>[]);
}
