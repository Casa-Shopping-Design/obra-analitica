import "server-only";
import { criarClienteServidor } from "@/lib/supabase/servidor";
import { ErroConsulta } from "@/lib/consultas/posicao";
import { numeroOuNulo, type LinhaExecucao } from "@/lib/consultas/resumo-origem";

export const mesesExecucao = 12;

// Os 12 meses mais recentes da migration 0019, do mais antigo para o mais novo, numa consulta por obra.
export async function listarExecucaoObra(centroCustoId: string): Promise<LinhaExecucao[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("execucao_fisica_obra")
    .select("competencia, pct_fisico, pct_financeiro, pct_financeiro_origem, diferenca_financeiro_fisico")
    .eq("centro_custo_id", centroCustoId)
    .order("competencia", { ascending: false })
    .limit(mesesExecucao);
  if (error) throw new ErroConsulta(error.code);
  return (data as Record<string, unknown>[])
    .map((linha) => ({
      competencia: String(linha.competencia),
      pct_fisico: numeroOuNulo(linha.pct_fisico),
      pct_financeiro: numeroOuNulo(linha.pct_financeiro),
      pct_financeiro_origem: numeroOuNulo(linha.pct_financeiro_origem),
      diferenca_financeiro_fisico: numeroOuNulo(linha.diferenca_financeiro_fisico),
    }))
    .reverse();
}
