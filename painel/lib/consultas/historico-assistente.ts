import "server-only";
import { ErroConsulta } from "@/lib/consultas/posicao";
import { criarClienteServidor } from "@/lib/supabase/servidor";

export type PerguntaRegistrada = {
  id: number;
  pergunta: string;
  resultado: "pendente" | "ok" | "recusada" | "erro";
  linhas_devolvidas: number | null;
  criado_em: string;
  sql_executado?: string | null;
};

export type Historico = { perguntas: PerguntaRegistrada[]; diretor: boolean };

export const tamanhoHistorico = 20;

type SqlDaPergunta = { id: number; sql_gerado: string | null; sql_executado: string | null };

// Uma consulta pelo índice (user_id, criado_em desc). O filtro por user_id é necessário porque o RLS
// deixa o diretor ver o tenant inteiro, e o histórico da tela é só de quem está logado.
// O grant da tabela não alcança as colunas de SQL; para o diretor elas vêm de app.sql_das_perguntas,
// numa chamada só com os ids da página, e o banco devolve vazio a quem não é diretor.
export async function listarHistorico(): Promise<Historico> {
  const supabase = await criarClienteServidor();
  const { data: dadosToken } = await supabase.auth.getClaims();
  const claims = dadosToken?.claims;
  if (!claims?.sub) throw new ErroConsulta("sem_usuario");
  const diretor = (claims.app_metadata as { perfil?: string } | undefined)?.perfil === "diretor";

  const { data, error } = await supabase
    .schema("app")
    .from("pergunta_assistente")
    .select("id, pergunta, resultado, linhas_devolvidas, criado_em")
    .eq("user_id", claims.sub)
    .order("criado_em", { ascending: false })
    .limit(tamanhoHistorico);
  if (error) throw new ErroConsulta(error.code);
  const perguntas = (data ?? []) as unknown as PerguntaRegistrada[];

  if (!diretor || perguntas.length === 0) return { perguntas, diretor };

  const { data: sqls, error: erroSql } = await supabase
    .schema("app")
    .rpc("sql_das_perguntas", { p_ids: perguntas.map((registro) => registro.id) });
  if (erroSql) throw new ErroConsulta(erroSql.code);
  const sqlPorId = new Map(((sqls ?? []) as SqlDaPergunta[]).map((linha) => [linha.id, linha.sql_executado]));
  return {
    perguntas: perguntas.map((registro) => ({ ...registro, sql_executado: sqlPorId.get(registro.id) ?? null })),
    diretor,
  };
}
