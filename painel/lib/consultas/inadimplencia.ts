import "server-only";
import { criarClienteServidor } from "@/lib/supabase/servidor";
import { ErroConsulta } from "@/lib/consultas/posicao";
import { numeroOuZero, type LinhaInadimplencia } from "@/lib/consultas/resumo-origem";

// Quatro linhas por obra, uma por faixa de atraso (migration 0019), sem cliente identificado.
export async function listarInadimplenciaObra(centroCustoId: string): Promise<LinhaInadimplencia[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("inadimplencia_faixa")
    .select("data_posicao, ordem, faixa, titulos, parcelas, valor_atrasado, valor_atualizado")
    .eq("centro_custo_id", centroCustoId)
    .order("ordem");
  if (error) throw new ErroConsulta(error.code);
  return (data as Record<string, unknown>[]).map((linha) => ({
    data_posicao: String(linha.data_posicao),
    ordem: numeroOuZero(linha.ordem),
    faixa: String(linha.faixa),
    titulos: numeroOuZero(linha.titulos),
    parcelas: numeroOuZero(linha.parcelas),
    valor_atrasado: numeroOuZero(linha.valor_atrasado),
    valor_atualizado: numeroOuZero(linha.valor_atualizado),
  }));
}
