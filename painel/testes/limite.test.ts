import type { SupabaseClient } from "@supabase/supabase-js";
import { describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));

const { ErroVerificacaoLimite, perguntasPorHora, verificarLimite } = await import("../lib/assistente/limite");

const usuarioId = "0a000000-0000-4000-8000-0000000007c1";
const agora = new Date("2026-10-16T14:00:00.000Z");

function criarBancoSimulado(resposta: { count: number | null; error: { code: string } | null }) {
  const filtros: { schema?: string; tabela?: string; colunas?: string; opcoes?: unknown; igual: [string, unknown][]; aPartirDe: [string, unknown][] } = {
    igual: [],
    aPartirDe: [],
  };
  const consulta = {
    select(colunas: string, opcoes: unknown) {
      filtros.colunas = colunas;
      filtros.opcoes = opcoes;
      return consulta;
    },
    eq(coluna: string, valor: unknown) {
      filtros.igual.push([coluna, valor]);
      return consulta;
    },
    gte(coluna: string, valor: unknown) {
      filtros.aPartirDe.push([coluna, valor]);
      return Promise.resolve(resposta);
    },
  };
  const cliente = {
    schema(schema: string) {
      filtros.schema = schema;
      return {
        from(tabela: string) {
          filtros.tabela = tabela;
          return consulta;
        },
      };
    },
  };
  return { cliente: cliente as unknown as SupabaseClient, filtros };
}

describe("verificarLimite", () => {
  it("conta só as perguntas do usuário na última hora, sem trazer linhas", async () => {
    const banco = criarBancoSimulado({ count: 0, error: null });

    const situacao = await verificarLimite(banco.cliente, usuarioId, agora);

    expect(situacao).toEqual({ permitido: true, restante: perguntasPorHora });
    expect(banco.filtros.schema).toBe("app");
    expect(banco.filtros.tabela).toBe("pergunta_assistente");
    expect(banco.filtros.opcoes).toEqual({ count: "exact", head: true });
    expect(banco.filtros.igual).toEqual([["user_id", usuarioId]]);
    expect(banco.filtros.aPartirDe).toEqual([["criado_em", "2026-10-16T13:00:00.000Z"]]);
  });

  it("libera a trigésima pergunta", async () => {
    const banco = criarBancoSimulado({ count: 29, error: null });
    expect(await verificarLimite(banco.cliente, usuarioId, agora)).toEqual({ permitido: true, restante: 1 });
  });

  it("bloqueia a trigésima primeira", async () => {
    const banco = criarBancoSimulado({ count: 30, error: null });
    expect(await verificarLimite(banco.cliente, usuarioId, agora)).toEqual({ permitido: false, restante: 0 });
  });

  it("não devolve restante negativo", async () => {
    const banco = criarBancoSimulado({ count: 45, error: null });
    expect(await verificarLimite(banco.cliente, usuarioId, agora)).toEqual({ permitido: false, restante: 0 });
  });

  it("bloqueia quando o banco não responde a contagem", async () => {
    const banco = criarBancoSimulado({ count: null, error: { code: "57014" } });
    await expect(verificarLimite(banco.cliente, usuarioId, agora)).rejects.toBeInstanceOf(ErroVerificacaoLimite);
  });
});
