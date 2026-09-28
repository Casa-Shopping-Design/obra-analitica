import "server-only";
import { criarClienteServidor } from "@/lib/supabase/servidor";
import { ErroConsulta } from "@/lib/consultas/posicao";
import { numeroOuNulo, numeroOuZero, type LinhaFunil } from "@/lib/consultas/resumo-origem";

export const mesesFunil = 12;

// Os 12 meses mais recentes do calendário da view (migration 0018), do mais antigo para o mais novo.
// Uma consulta, filtrada por obra, com teto de linhas: a obra mais antiga do piloto tem poucas dezenas de meses.
export async function listarFunilObra(centroCustoId: string): Promise<LinhaFunil[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("funil_vendas_mensal")
    .select("competencia, leads, reservas, reservas_canceladas, vendas, distratos, conversao_lead_reserva, conversao_reserva_venda")
    .eq("centro_custo_id", centroCustoId)
    .order("competencia", { ascending: false })
    .limit(mesesFunil);
  if (error) throw new ErroConsulta(error.code);
  return (data as Record<string, unknown>[])
    .map((linha) => ({
      competencia: String(linha.competencia),
      leads: numeroOuZero(linha.leads),
      reservas: numeroOuZero(linha.reservas),
      reservas_canceladas: numeroOuZero(linha.reservas_canceladas),
      vendas: numeroOuZero(linha.vendas),
      distratos: numeroOuZero(linha.distratos),
      conversao_lead_reserva: numeroOuNulo(linha.conversao_lead_reserva),
      conversao_reserva_venda: numeroOuNulo(linha.conversao_reserva_venda),
    }))
    .reverse();
}
