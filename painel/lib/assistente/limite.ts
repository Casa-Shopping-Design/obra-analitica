import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";

export const perguntasPorHora = 30;
const umaHoraEmMs = 60 * 60 * 1000;

export type SituacaoLimite = { permitido: boolean; restante: number };

export class ErroVerificacaoLimite extends Error {}

// O(log n) pelo índice (user_id, criado_em desc). Conta também as perguntas recusadas e as que
// falharam, porque cada uma já custou chamada ao modelo. Duas requisições simultâneas podem passar
// juntas na borda do limite; o teto serve para conter custo, não para contagem exata.
export async function verificarLimite(cliente: SupabaseClient, usuarioId: string, agora: Date = new Date()): Promise<SituacaoLimite> {
  const inicioJanela = new Date(agora.getTime() - umaHoraEmMs).toISOString();
  const { count, error } = await cliente
    .schema("app")
    .from("pergunta_assistente")
    .select("id", { count: "exact", head: true })
    .eq("user_id", usuarioId)
    .gte("criado_em", inicioJanela);

  // Sem a contagem não há como saber se o limite estourou; na dúvida, bloqueia.
  if (error || count === null) throw new ErroVerificacaoLimite(error?.code ?? "sem_contagem");

  const restante = Math.max(0, perguntasPorHora - count);
  return { permitido: restante > 0, restante };
}
