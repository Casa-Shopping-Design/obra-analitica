import "server-only";
import Anthropic from "@anthropic-ai/sdk";
import type { UsoModelo } from "@/lib/assistente/executar";
import {
  calcularUso,
  formatosColuna,
  modeloAssistente,
  montarMensagemGeracao,
  sistemaGeracaoSql,
  type FormatoColunaLivre,
} from "@/lib/assistente/prompt";

export type ClienteModelo = {
  messages: { create(parametros: Anthropic.MessageCreateParamsNonStreaming): Promise<Anthropic.Message> };
};

export type FormatoDevolvido = { coluna: string; formato: FormatoColunaLivre };

export type SqlGerado =
  | { ok: true; sql: string; formatos: FormatoDevolvido[]; uso: UsoModelo }
  | { ok: false; uso: UsoModelo };

const esquemaSaida = {
  type: "object",
  properties: {
    sql: { type: "string" },
    formatos: {
      type: "array",
      items: {
        type: "object",
        properties: {
          coluna: { type: "string" },
          formato: { type: "string", enum: [...formatosColuna] },
        },
        required: ["coluna", "formato"],
        additionalProperties: false,
      },
    },
  },
  required: ["sql", "formatos"],
  additionalProperties: false,
};

// Chave só no servidor; sem ela o assistente de texto livre fica fora do ar e as perguntas prontas seguem.
export function criarClienteModelo(): ClienteModelo | null {
  const chave = process.env.ANTHROPIC_API_KEY;
  if (!chave) return null;
  return new Anthropic({ apiKey: chave, timeout: 30_000, maxRetries: 1 });
}

export function lerTexto(resposta: Anthropic.Message): string | null {
  if (resposta.stop_reason !== "end_turn") return null;
  const bloco = resposta.content.find((parte) => parte.type === "text");
  return bloco?.type === "text" ? bloco.text : null;
}

function lerSaida(texto: string | null): { sql: string; formatos: FormatoDevolvido[] } | null {
  if (!texto) return null;
  try {
    const saida: unknown = JSON.parse(texto);
    if (typeof saida !== "object" || saida === null) return null;
    const { sql, formatos } = saida as { sql?: unknown; formatos?: unknown };
    if (typeof sql !== "string" || !Array.isArray(formatos)) return null;
    const validos = formatos.filter(
      (item): item is FormatoDevolvido =>
        typeof item?.coluna === "string" && (formatosColuna as readonly string[]).includes(item?.formato),
    );
    return { sql: sql.trim(), formatos: validos };
  } catch {
    return null;
  }
}

// Uma chamada: catálogo em cache no bloco de sistema, pergunta como dado na mensagem do usuário.
// Sql vazio quer dizer que o catálogo não responde à pergunta.
export async function gerarSql(cliente: ClienteModelo, pergunta: string, motivoRecusa?: string): Promise<SqlGerado> {
  const resposta = await cliente.messages.create({
    model: modeloAssistente,
    max_tokens: 4000,
    system: [{ type: "text", text: sistemaGeracaoSql, cache_control: { type: "ephemeral" } }],
    output_config: { effort: "low", format: { type: "json_schema", schema: esquemaSaida } },
    messages: [{ role: "user", content: montarMensagemGeracao(pergunta, motivoRecusa) }],
  });
  const uso = calcularUso(resposta.usage);
  const saida = lerSaida(lerTexto(resposta));
  if (!saida || saida.sql === "") return { ok: false, uso };
  return { ok: true, sql: saida.sql, formatos: saida.formatos, uso };
}
