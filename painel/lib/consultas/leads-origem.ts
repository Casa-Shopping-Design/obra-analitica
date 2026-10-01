import "server-only";
import { criarClienteServidor } from "@/lib/supabase/servidor";
import { ErroConsulta } from "@/lib/consultas/posicao";
import { numeroOuNulo, numeroOuZero, type LinhaLeadOrigem } from "@/lib/consultas/resumo-origem";

// Leads dos últimos 12 meses por origem e mídia (migration 0026), do maior volume para o menor.
// Uma consulta filtrada por obra; o CRM costuma ter poucas dezenas de pares de origem e mídia.
export async function listarLeadsOrigem(centroCustoId: string): Promise<LinhaLeadOrigem[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("leads_origem")
    .select("origem, midia, leads, leads_descartados, pct_descartados, motivo_principal_descarte, leads_motivo_principal")
    .eq("centro_custo_id", centroCustoId)
    .order("leads", { ascending: false })
    .order("origem")
    .order("midia")
    .limit(200);
  if (error) throw new ErroConsulta(error.code);
  return (data as Record<string, unknown>[]).map((linha) => ({
    origem: String(linha.origem),
    midia: String(linha.midia),
    leads: numeroOuZero(linha.leads),
    leads_descartados: numeroOuZero(linha.leads_descartados),
    pct_descartados: numeroOuNulo(linha.pct_descartados),
    motivo_principal_descarte: linha.motivo_principal_descarte === null ? null : String(linha.motivo_principal_descarte),
    leads_motivo_principal: numeroOuNulo(linha.leads_motivo_principal),
  }));
}
