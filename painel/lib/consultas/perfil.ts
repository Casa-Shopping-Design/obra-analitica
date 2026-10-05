import "server-only";
import { criarClienteServidor } from "@/lib/supabase/servidor";

// getClaims valida o JWT. O perfil sai de app.perfil_atual, a mesma função que o RLS usa, que lê
// app_metadata ou a tabela de vínculo. Nunca user_metadata. Falha de leitura devolve nulo, que nenhuma
// regra de tela aceita.
export async function lerPerfilAtual(): Promise<string | null> {
  const supabase = await criarClienteServidor();
  const { data: sessao } = await supabase.auth.getClaims();
  if (!sessao?.claims?.sub) return null;
  const { data, error } = await supabase.schema("app").rpc("perfil_atual");
  if (error) return null;
  return typeof data === "string" ? data : null;
}
