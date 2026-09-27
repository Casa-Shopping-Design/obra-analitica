import "server-only";
import { createHmac } from "node:crypto";
import pino from "pino";
import { criarClienteServidor } from "@/lib/supabase/servidor";
import { validarSql } from "@/lib/validador-sql";

export type LinhaConsulta = Record<string, unknown>;

export type UsoModelo = { tokensEntrada: number; tokensSaida: number; custoEstimado: number };

// O código da falha é traduzido para texto na borda, por lib/mensagens.ts; SQL e erro do banco nunca saem daqui.
export type FalhaExecucao = "sem_usuario" | "recusada" | "execucao" | "configuracao";

export type ResultadoExecucao =
  | { ok: true; linhas: LinhaConsulta[]; totalLinhas: number; duracaoMs: number; idRequisicao: string }
  | { ok: false; falha: FalhaExecucao; idRequisicao: string };

type Cliente = Awaited<ReturnType<typeof criarClienteServidor>>;

type RegistroPergunta = {
  id_requisicao: string;
  pergunta: string;
  sql_gerado: string;
  sql_executado?: string;
  resultado: "ok" | "recusada" | "erro";
  linhas_devolvidas?: number;
  duracao_ms?: number;
  tokens_entrada: number | null;
  tokens_saida: number | null;
  custo_estimado: number | null;
};

type CamposLog = { id_requisicao: string; rota: string; user_id: string | null; tenant_id: string | null };

// Campos fixos da seção 4.2 do plano; sem pergunta, sem SQL e sem e-mail no log.
const log = pino({ base: null, messageKey: "mensagem" });

// Sem a chave não há assinatura, e o banco recusa a consulta; melhor falhar aqui com o motivo no log.
function lerChaveAssinatura(): string | null {
  const chave = process.env.ASSISTENTE_CHAVE_ASSINATURA;
  return chave && chave.length >= 32 ? chave : null;
}

// user_id e tenant_id ficam a cargo do banco (default e política de insert), então ninguém grava em nome de outro.
async function gravarPergunta(supabase: Cliente, registro: RegistroPergunta, campos: CamposLog): Promise<boolean> {
  const { error } = await supabase.schema("app").from("pergunta_assistente").insert(registro);
  if (error) log.error({ ...campos, resultado: "erro", codigo_erro: error.code }, "falha ao registrar pergunta do assistente");
  return !error;
}

export async function executarConsultaValidada(
  sqlGerado: string,
  idRequisicao: string,
  pergunta: string,
  uso?: UsoModelo,
): Promise<ResultadoExecucao> {
  const supabase = await criarClienteServidor();
  // getClaims valida o JWT; o tenant vem do claim que o hook do Auth grava, e não do registro do usuário.
  const { data: dadosToken } = await supabase.auth.getClaims();
  const claims = dadosToken?.claims;
  const campos: CamposLog = {
    id_requisicao: idRequisicao,
    rota: "assistente",
    user_id: claims?.sub ?? null,
    tenant_id: (claims?.app_metadata?.tenant_id as string | undefined) ?? null,
  };

  if (!claims?.sub) {
    log.warn({ ...campos, resultado: "sem_usuario" }, "consulta do assistente sem usuário autenticado");
    return { ok: false, falha: "sem_usuario", idRequisicao };
  }

  const registroBase = {
    id_requisicao: idRequisicao,
    pergunta,
    sql_gerado: sqlGerado,
    tokens_entrada: uso?.tokensEntrada ?? null,
    tokens_saida: uso?.tokensSaida ?? null,
    custo_estimado: uso?.custoEstimado ?? null,
  };

  const validacao = validarSql(sqlGerado);
  if (!validacao.ok) {
    log.warn({ ...campos, resultado: "recusada", motivo: validacao.motivo }, "consulta recusada pelo validador");
    await gravarPergunta(supabase, { ...registroBase, resultado: "recusada" }, campos);
    return { ok: false, falha: "recusada", idRequisicao };
  }

  const chave = lerChaveAssinatura();
  if (!chave) {
    log.error({ ...campos, resultado: "erro" }, "ASSISTENTE_CHAVE_ASSINATURA ausente ou curta");
    return { ok: false, falha: "configuracao", idRequisicao };
  }

  const assinatura = createHmac("sha256", chave).update(validacao.sql).digest("hex");
  const inicio = performance.now();
  const { data, error } = await supabase
    .schema("marts")
    .rpc("executar_consulta", { p_sql: validacao.sql, p_assinatura: assinatura });
  const duracaoMs = Math.round(performance.now() - inicio);
  const execucao = { ...registroBase, sql_executado: validacao.sql, duracao_ms: duracaoMs };

  if (error) {
    log.error({ ...campos, duracao_ms: duracaoMs, resultado: "erro", codigo_erro: error.code }, "falha ao executar consulta do assistente");
    await gravarPergunta(supabase, { ...execucao, resultado: "erro" }, campos);
    return { ok: false, falha: "execucao", idRequisicao };
  }

  const linhas: LinhaConsulta[] = Array.isArray(data) ? data : [];
  // Resposta sem registro não sai: a rastreabilidade de quem perguntou o quê vale mais que a resposta.
  const registrou = await gravarPergunta(
    supabase,
    { ...execucao, resultado: "ok", linhas_devolvidas: linhas.length },
    campos,
  );
  if (!registrou) return { ok: false, falha: "execucao", idRequisicao };

  log.info({ ...campos, duracao_ms: duracaoMs, resultado: "ok", linhas: linhas.length }, "consulta do assistente executada");
  return { ok: true, linhas, totalLinhas: linhas.length, duracaoMs, idRequisicao };
}
