import "server-only";
import { ErroConsulta } from "@/lib/consultas/posicao";
import { criarClienteServidor } from "@/lib/supabase/servidor";

export type PerguntaRegistrada = {
  id: number;
  pergunta: string;
  resultado: "ok" | "recusada" | "erro";
  linhas_devolvidas: number | null;
  criado_em: string;
  sql_executado?: string | null;
};

export type Historico = { perguntas: PerguntaRegistrada[]; diretor: boolean };

export const tamanhoHistorico = 20;

// Uma consulta pelo índice (user_id, criado_em desc). O filtro por user_id é necessário porque o RLS
// deixa o diretor ver o tenant inteiro, e o histórico da tela é só de quem está logado.
// O SQL só é pedido ao banco quando o perfil do JWT validado é diretor.
export async function listarHistorico(): Promise<Historico> {
  const supabase = await criarClienteServidor();
  const { data: dadosToken } = await supabase.auth.getClaims();
  const claims = dadosToken?.claims;
  if (!claims?.sub) throw new ErroConsulta("sem_usuario");
  const diretor = (claims.app_metadata as { perfil?: string } | undefined)?.perfil === "diretor";

  const colunas = diretor
    ? "id, pergunta, resultado, linhas_devolvidas, criado_em, sql_executado"
    : "id, pergunta, resultado, linhas_devolvidas, criado_em";
  const { data, error } = await supabase
    .schema("app")
    .from("pergunta_assistente")
    .select(colunas)
    .eq("user_id", claims.sub)
    .order("criado_em", { ascending: false })
    .limit(tamanhoHistorico);

  if (error) throw new ErroConsulta(error.code);
  return { perguntas: (data ?? []) as unknown as PerguntaRegistrada[], diretor };
}
