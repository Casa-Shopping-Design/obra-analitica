import "server-only";
import { ErroConsulta } from "@/lib/consultas/posicao";
import { criarClienteServidor } from "@/lib/supabase/servidor";

export const perguntasPorHora = 30;

export type SituacaoLimite = { permitido: boolean; restante: number };

// Uma contagem só, pelo índice (user_id, criado_em desc) de app.pergunta_assistente: O(log n) mais as linhas da hora.
// Falha na contagem vira erro, e não permissão, para o limite não abrir quando o banco falha.
export async function verificarLimite(userId: string): Promise<SituacaoLimite> {
  const supabase = await criarClienteServidor();
  const umaHoraAtras = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const { count, error } = await supabase
    .schema("app")
    .from("pergunta_assistente")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .gte("criado_em", umaHoraAtras);

  if (error || count === null) throw new ErroConsulta(error?.code ?? "contagem_ausente");
  const restante = Math.max(perguntasPorHora - count, 0);
  return { permitido: restante > 0, restante };
}
