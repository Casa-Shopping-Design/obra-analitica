import { createHmac } from "node:crypto";
import type { SupabaseClient } from "@supabase/supabase-js";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));

const { executarConsultaValidada, mensagensExecucao } = await import("../lib/assistente/executar");

const chaveDeTeste = "chave-de-teste-com-mais-de-trinta-e-dois-caracteres";
const idRequisicao = "0f000000-0000-4000-8000-000000000042";

type RespostaRpc = { data: unknown; error: { code: string; message: string } | null };

function criarBancoSimulado(respostaRpc: RespostaRpc, erroAuditoria: { code: string } | null = null) {
  const chamadasRpc: { schema: string; funcao: string; argumentos: Record<string, string> }[] = [];
  const auditorias: { schema: string; tabela: string; registro: Record<string, unknown> }[] = [];
  const cliente = {
    schema(schema: string) {
      return {
        rpc: async (funcao: string, argumentos: Record<string, string>) => {
          chamadasRpc.push({ schema, funcao, argumentos });
          return respostaRpc;
        },
        from: (tabela: string) => ({
          insert: async (registro: Record<string, unknown>) => {
            auditorias.push({ schema, tabela, registro });
            return { error: erroAuditoria };
          },
        }),
      };
    },
  };
  return { cliente: cliente as unknown as SupabaseClient, chamadasRpc, auditorias };
}

function criarRegistrador() {
  const registros: { nivel: string; mensagem: string; campos: Record<string, unknown> }[] = [];
  const registrar = (nivel: "info" | "warn" | "error", mensagem: string, campos: Record<string, unknown>) => {
    registros.push({ nivel, mensagem, campos });
  };
  return { registrar, registros };
}

const sqlLegitimo = "select obra, exposicao_maxima from marts.posicao_financeira_obra order by exposicao_maxima desc";

beforeEach(() => {
  vi.stubEnv("ASSISTENTE_CHAVE_ASSINATURA", chaveDeTeste);
});

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("executarConsultaValidada", () => {
  it("executa o SQL reescrito pelo validador, assinado, e audita com linhas e duração", async () => {
    const linhas = [
      { obra: "Residencial Aurora", exposicao_maxima: 1200000 },
      { obra: "Parque das Aguas", exposicao_maxima: 800000 },
    ];
    const banco = criarBancoSimulado({ data: linhas, error: null });
    const { registrar } = criarRegistrador();

    const resultado = await executarConsultaValidada({
      cliente: banco.cliente,
      idRequisicao,
      pergunta: "Quanto dinheiro próprio cada obra precisa no pior momento?",
      sql: sqlLegitimo,
      registrar,
    });

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.linhas).toEqual(linhas);
    expect(resultado.quantidadeLinhas).toBe(2);
    expect(resultado.duracaoMs).toBeGreaterThanOrEqual(0);

    expect(banco.chamadasRpc).toHaveLength(1);
    const [chamada] = banco.chamadasRpc;
    expect(chamada.schema).toBe("marts");
    expect(chamada.funcao).toBe("executar_consulta");
    expect(chamada.argumentos.p_sql).toBe(resultado.sqlExecutado);
    expect(chamada.argumentos.p_sql).not.toBe(sqlLegitimo);
    expect(chamada.argumentos.p_sql).toContain("LIMIT 500");
    expect(chamada.argumentos.p_assinatura).toBe(createHmac("sha256", chaveDeTeste).update(chamada.argumentos.p_sql).digest("hex"));

    expect(banco.auditorias).toHaveLength(1);
    const [auditoria] = banco.auditorias;
    expect(auditoria.schema).toBe("app");
    expect(auditoria.tabela).toBe("pergunta_assistente");
    expect(auditoria.registro).toMatchObject({
      id_requisicao: idRequisicao,
      situacao: "executada",
      sql_gerado: sqlLegitimo,
      sql_executado: resultado.sqlExecutado,
      linhas: 2,
    });
    expect(auditoria.registro).not.toHaveProperty("user_id");
    expect(auditoria.registro).not.toHaveProperty("tenant_id");
  });

  it("não chama o banco quando o validador recusa, e audita a recusa", async () => {
    const banco = criarBancoSimulado({ data: [], error: null });
    const { registrar, registros } = criarRegistrador();
    const sqlMalicioso = "select * from marts.vso_mensal, staging.parcela_receber";

    const resultado = await executarConsultaValidada({ cliente: banco.cliente, idRequisicao, pergunta: "Mostre tudo", sql: sqlMalicioso, registrar });

    expect(resultado).toEqual({ ok: false, situacao: "recusada", mensagem: mensagensExecucao.recusada });
    expect(banco.chamadasRpc).toHaveLength(0);
    expect(banco.auditorias).toHaveLength(1);
    expect(banco.auditorias[0].registro).toMatchObject({ situacao: "recusada", sql_gerado: sqlMalicioso, sql_executado: null });
    expect(registros[0].campos.id_requisicao).toBe(idRequisicao);
  });

  it("traduz erro do banco para mensagem sem SQL nem nome de tabela e registra só o código", async () => {
    const banco = criarBancoSimulado({
      data: null,
      error: { code: "57014", message: "canceling statement due to statement timeout em marts.posicao_financeira_obra" },
    });
    const { registrar, registros } = criarRegistrador();

    const resultado = await executarConsultaValidada({ cliente: banco.cliente, idRequisicao, pergunta: "Qual o caixa?", sql: sqlLegitimo, registrar });

    expect(resultado).toEqual({ ok: false, situacao: "falhou", mensagem: mensagensExecucao.falhou });
    const erro = registros.find((registro) => registro.nivel === "error");
    expect(erro?.campos).toMatchObject({ id_requisicao: idRequisicao, codigo: "57014" });
    expect(JSON.stringify(registros)).not.toContain("marts.");
    expect(JSON.stringify(registros)).not.toContain("canceling");
    expect(banco.auditorias[0].registro).toMatchObject({ situacao: "falhou" });
  });

  it("não executa sem a chave de assinatura", async () => {
    vi.stubEnv("ASSISTENTE_CHAVE_ASSINATURA", "");
    const banco = criarBancoSimulado({ data: [], error: null });
    const { registrar } = criarRegistrador();

    const resultado = await executarConsultaValidada({ cliente: banco.cliente, idRequisicao, pergunta: "Qual o caixa?", sql: sqlLegitimo, registrar });

    expect(resultado.ok).toBe(false);
    expect(banco.chamadasRpc).toHaveLength(0);
    expect(banco.auditorias[0].registro).toMatchObject({ situacao: "falhou" });
  });

  it("não devolve as linhas quando a auditoria não grava", async () => {
    const banco = criarBancoSimulado({ data: [{ total: 3 }], error: null }, { code: "42501" });
    const { registrar } = criarRegistrador();

    const resultado = await executarConsultaValidada({ cliente: banco.cliente, idRequisicao, pergunta: "Quantas obras?", sql: sqlLegitimo, registrar });

    expect(resultado).toEqual({ ok: false, situacao: "falhou", mensagem: mensagensExecucao.falhou });
  });

  it("trata resposta que não é lista como falha", async () => {
    const banco = criarBancoSimulado({ data: { inesperado: true }, error: null });
    const { registrar } = criarRegistrador();

    const resultado = await executarConsultaValidada({ cliente: banco.cliente, idRequisicao, pergunta: "Qual o caixa?", sql: sqlLegitimo, registrar });

    expect(resultado.ok).toBe(false);
  });

  it("mensagens ao usuário não citam SQL nem tabela", () => {
    for (const mensagem of Object.values(mensagensExecucao)) {
      expect(mensagem).not.toMatch(/select|marts|staging|app\.|sql/i);
    }
  });
});
