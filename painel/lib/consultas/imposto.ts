import "server-only";
import { criarClienteServidor } from "@/lib/supabase/servidor";
import { ErroConsulta } from "@/lib/consultas/posicao";
import { colunasImposto, lerImpostoObra, type ImpostoObra } from "@/lib/imposto";

// Uma linha por obra com estudo e alíquota; nulo quando falta um dos dois ou quando o RLS esconde a obra.
// A tela chama podeVerDre antes, para dizer que é restrita em vez de dizer que falta alíquota.
export async function buscarImpostoObra(centroCustoId: string): Promise<ImpostoObra | null> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("imposto_obra")
    .select(colunasImposto)
    .eq("centro_custo_id", centroCustoId)
    .maybeSingle<Record<string, unknown>>();
  if (error) throw new ErroConsulta(error.code);
  return data ? lerImpostoObra(data) : null;
}
