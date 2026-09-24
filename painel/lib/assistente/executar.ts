import "server-only";
import { createHmac } from "node:crypto";
import type { SupabaseClient } from "@supabase/supabase-js";
import { validarSql } from "../validador-sql";

// Textos que o usuário vê. Não citam SQL, tabela nem o erro do banco.
export const mensagensExecucao = {
  recusada: "Não consegui montar uma consulta segura para essa pergunta. Tente perguntar de outro jeito.",
  falhou: "Não consegui executar essa pergunta. Tente reformular.",
} as const;

export type Registrador = (nivel: "info" | "warn" | "error", mensagem: string, campos: Record<string, unknown>) => void;

export type PedidoExecucao = {
  cliente: SupabaseClient;
  idRequisicao: string;
  pergunta: string;
  sql: string;
  registrar: Registrador;
};

export type ResultadoExecucao =
  | { ok: true; linhas: Record<string, unknown>[]; quantidadeLinhas: number; duracaoMs: number; sqlExecutado: string }
  | { ok: false; situacao: "recusada" | "falhou"; mensagem: string };

type RegistroPergunta = {
  situacao: "executada" | "recusada" | "falhou";
  sqlExecutado?: string;
  linhas?: number;
  duracaoMs?: number;
};

const tamanhoMinimoChave = 32;

// Mesma conta do banco (app.assinatura_consulta_valida): HMAC-SHA256 do texto, em hexadecimal.
function assinar(sql: string, chave: string): string {
  return createHmac("sha256", chave).update(sql, "utf8").digest("hex");
}

// user_id, tenant_id e criado_em ficam de fora: o banco preenche a partir do JWT de quem pergunta.
async function registrarPergunta(pedido: PedidoExecucao, registro: RegistroPergunta): Promise<boolean> {
  const { error } = await pedido.cliente
    .schema("app")
    .from("pergunta_assistente")
    .insert({
      id_requisicao: pedido.idRequisicao,
      pergunta: pedido.pergunta.slice(0, 2000),
      sql_gerado: pedido.sql.slice(0, 20000),
      sql_executado: registro.sqlExecutado ?? null,
      situacao: registro.situacao,
      linhas: registro.linhas ?? null,
      duracao_ms: registro.duracaoMs ?? null,
    });
  if (error) {
    pedido.registrar("error", "falha ao gravar a auditoria do assistente", { id_requisicao: pedido.idRequisicao, codigo: error.code });
    return false;
  }
  return true;
}

async function falhar(pedido: PedidoExecucao, registro: RegistroPergunta): Promise<ResultadoExecucao> {
  await registrarPergunta(pedido, registro);
  return { ok: false, situacao: "falhou", mensagem: mensagensExecucao.falhou };
}

// Valida, assina e executa com o cliente do usuário, para o RLS valer. Toda pergunta fica auditada;
// se a auditoria não grava, o resultado não sai.
export async function executarConsultaValidada(pedido: PedidoExecucao): Promise<ResultadoExecucao> {
  const { idRequisicao, registrar } = pedido;

  const validacao = await validarSql(pedido.sql);
  if (!validacao.ok) {
    registrar("warn", "consulta do assistente recusada pelo validador", { id_requisicao: idRequisicao, motivo: validacao.motivo });
    await registrarPergunta(pedido, { situacao: "recusada" });
    return { ok: false, situacao: "recusada", mensagem: mensagensExecucao.recusada };
  }

  const chave = process.env.ASSISTENTE_CHAVE_ASSINATURA;
  if (!chave || chave.length < tamanhoMinimoChave) {
    registrar("error", "chave de assinatura do assistente ausente ou curta", { id_requisicao: idRequisicao });
    return falhar(pedido, { situacao: "falhou", sqlExecutado: validacao.sql });
  }

  const inicio = performance.now();
  const { data: resposta, error } = await pedido.cliente
    .schema("marts")
    .rpc("executar_consulta", { p_sql: validacao.sql, p_assinatura: assinar(validacao.sql, chave) });
  const duracaoMs = Math.round(performance.now() - inicio);

  if (error || !Array.isArray(resposta)) {
    registrar("error", "falha ao executar consulta do assistente", {
      id_requisicao: idRequisicao,
      codigo: error?.code ?? "resposta_inesperada",
      duracao_ms: duracaoMs,
    });
    return falhar(pedido, { situacao: "falhou", sqlExecutado: validacao.sql, duracaoMs });
  }

  const linhas = resposta as Record<string, unknown>[];
  const auditada = await registrarPergunta(pedido, {
    situacao: "executada",
    sqlExecutado: validacao.sql,
    linhas: linhas.length,
    duracaoMs,
  });
  if (!auditada) return { ok: false, situacao: "falhou", mensagem: mensagensExecucao.falhou };

  registrar("info", "consulta do assistente executada", { id_requisicao: idRequisicao, linhas: linhas.length, duracao_ms: duracaoMs });
  return { ok: true, linhas, quantidadeLinhas: linhas.length, duracaoMs, sqlExecutado: validacao.sql };
}
