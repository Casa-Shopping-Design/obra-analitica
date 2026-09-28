import pino from "pino";
import {
  executarConsultaValidada,
  lerChaveAssinatura,
  type LinhaConsulta,
  type UsoModelo,
} from "@/lib/assistente/executar";
import { criarClienteModelo, gerarSql, type ClienteModelo, type SqlGerado } from "@/lib/assistente/gerar-sql";
import { verificarLimite } from "@/lib/assistente/limite";
import { montarTabela, redigirResposta } from "@/lib/assistente/responder";
import { mensagens } from "@/lib/mensagens";
import { criarClienteServidor } from "@/lib/supabase/servidor";
import { validarSql } from "@/lib/validador-sql";

const log = pino({ base: null, messageKey: "mensagem" });
const formatoUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const tamanhoMinimo = 3;
const tamanhoMaximo = 500;

type CamposLog = { id_requisicao: string; rota: string; user_id: string | null; tenant_id: string | null };

function somar(a: UsoModelo, b: UsoModelo): UsoModelo {
  return {
    tokensEntrada: a.tokensEntrada + b.tokensEntrada,
    tokensSaida: a.tokensSaida + b.tokensSaida,
    custoEstimado: a.custoEstimado + b.custoEstimado,
  };
}

function hojeEmBrasilia(): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Sao_Paulo" }).format(new Date());
}

// Só JSON: formulário de outro site não consegue mandar esse tipo sem passar pelo CORS.
async function lerPergunta(request: Request): Promise<string | null> {
  if (!request.headers.get("content-type")?.startsWith("application/json")) return null;
  try {
    const corpo: unknown = await request.json();
    const pergunta = typeof corpo === "object" && corpo !== null ? (corpo as { pergunta?: unknown }).pergunta : null;
    if (typeof pergunta !== "string") return null;
    const limpa = pergunta.trim();
    return limpa.length >= tamanhoMinimo && limpa.length <= tamanhoMaximo ? limpa : null;
  } catch {
    return null;
  }
}

// Até duas gerações: a segunda recebe o motivo da recusa. O validador é o mesmo que o executor usa.
async function gerarSqlValido(cliente: ClienteModelo, pergunta: string) {
  const primeira: SqlGerado = await gerarSql(cliente, pergunta);
  if (!primeira.ok) return { geracao: primeira, valido: false, uso: primeira.uso };
  const validacao = validarSql(primeira.sql);
  if (validacao.ok) return { geracao: primeira, valido: true, uso: primeira.uso };

  const segunda = await gerarSql(cliente, pergunta, validacao.motivo);
  const uso = somar(primeira.uso, segunda.uso);
  if (!segunda.ok) return { geracao: primeira, valido: false, uso };
  return { geracao: segunda, valido: validarSql(segunda.sql).ok, uso };
}

function responderErro(status: number, erro: string, idRequisicao: string): Response {
  return Response.json({ ok: false, erro, idRequisicao }, { status, headers: { "cache-control": "no-store" } });
}

export async function POST(request: Request): Promise<Response> {
  const inicio = performance.now();
  const cabecalho = request.headers.get("x-id-requisicao");
  const idRequisicao = cabecalho && formatoUuid.test(cabecalho) ? cabecalho : crypto.randomUUID();
  const campos: CamposLog = { id_requisicao: idRequisicao, rota: "api/assistente", user_id: null, tenant_id: null };
  const registrar = (resultado: string, extra: Record<string, unknown> = {}) =>
    log.info({ ...campos, ...extra, resultado, duracao_ms: Math.round(performance.now() - inicio) }, "pergunta livre ao assistente");

  // getUser valida o token no Auth; getClaims dá o perfil e o tenant que o hook gravou no JWT validado.
  const supabase = await criarClienteServidor();
  const { data: dadosUsuario } = await supabase.auth.getUser();
  const usuario = dadosUsuario.user;
  if (!usuario) {
    registrar("sem_usuario");
    return responderErro(401, mensagens.assistente.semUsuario, idRequisicao);
  }
  const { data: dadosToken } = await supabase.auth.getClaims();
  const appMetadata = dadosToken?.claims?.app_metadata as { tenant_id?: string; perfil?: string } | undefined;
  campos.user_id = usuario.id;
  campos.tenant_id = appMetadata?.tenant_id ?? null;
  const diretor = appMetadata?.perfil === "diretor";

  // Sem tenant o registro da pergunta não grava, e pergunta sem registro não conta no limite:
  // cada tentativa gastaria chamadas ao modelo sem teto. O banco é consultado só quando o claim falta.
  if (!campos.tenant_id) {
    const { data: tenantBanco } = await supabase.schema("app").rpc("tenant_atual");
    campos.tenant_id = typeof tenantBanco === "string" ? tenantBanco : null;
  }
  if (!campos.tenant_id) {
    registrar("sem_tenant");
    return responderErro(403, mensagens.assistente.semAcesso, idRequisicao);
  }

  const pergunta = await lerPergunta(request);
  if (!pergunta) {
    registrar("pergunta_invalida");
    return responderErro(400, mensagens.assistente.perguntaInvalida, idRequisicao);
  }

  try {
    const limite = await verificarLimite(usuario.id);
    if (!limite.permitido) {
      registrar("limite");
      return responderErro(429, mensagens.assistente.limite, idRequisicao);
    }
  } catch {
    registrar("erro_limite");
    return responderErro(503, mensagens.assistente.indisponivel, idRequisicao);
  }

  // Sem a chave de assinatura nada executa nem grava; conferir antes evita pagar o modelo à toa.
  if (!lerChaveAssinatura()) {
    log.error({ ...campos, resultado: "erro" }, "ASSISTENTE_CHAVE_ASSINATURA ausente ou curta");
    return responderErro(503, mensagens.assistente.indisponivel, idRequisicao);
  }

  const cliente = criarClienteModelo();
  if (!cliente) {
    log.error({ ...campos, resultado: "erro" }, "ANTHROPIC_API_KEY ausente");
    return responderErro(503, mensagens.assistente.indisponivel, idRequisicao);
  }

  try {
    const { geracao, valido, uso } = await gerarSqlValido(cliente, pergunta);
    if (!geracao.ok) {
      await executarConsultaValidada("", idRequisicao, pergunta, uso);
      registrar("fora_do_catalogo");
      return responderErro(422, mensagens.assistente.foraDoCatalogo, idRequisicao);
    }

    let texto: string = mensagens.assistente.respostaSoTabela;
    // A redação roda antes da gravação para o registro levar o custo das duas chamadas.
    const complementar = async (linhas: LinhaConsulta[]) => {
      try {
        const redigida = await redigirResposta(cliente, pergunta, linhas, geracao.formatos);
        texto = redigida.texto;
        return redigida.uso;
      } catch {
        log.warn({ ...campos, resultado: "erro_redacao" }, "falha ao redigir a resposta; segue só a tabela");
        return { tokensEntrada: 0, tokensSaida: 0, custoEstimado: 0 };
      }
    };

    const execucao = await executarConsultaValidada(geracao.sql, idRequisicao, pergunta, uso, valido ? complementar : undefined);
    if (!execucao.ok) {
      registrar(execucao.falha);
      if (execucao.falha === "recusada") return responderErro(422, mensagens.assistente.consultaInsegura, idRequisicao);
      if (execucao.falha === "sem_usuario") return responderErro(401, mensagens.assistente.semUsuario, idRequisicao);
      if (execucao.falha === "configuracao") return responderErro(503, mensagens.assistente.indisponivel, idRequisicao);
      return responderErro(502, mensagens.assistente.execucao, idRequisicao);
    }

    const validacao = validarSql(geracao.sql);
    registrar("ok", { linhas: execucao.totalLinhas });
    return Response.json(
      {
        ok: true,
        idRequisicao,
        pergunta,
        texto,
        tabela: montarTabela(execucao.linhas, geracao.formatos),
        consultadoEm: hojeEmBrasilia(),
        // SQL só para o diretor; os demais perfis nunca recebem o texto da consulta.
        sql: diretor && validacao.ok ? validacao.sql : undefined,
      },
      { headers: { "cache-control": "no-store" } },
    );
  } catch (erro) {
    log.error({ ...campos, resultado: "erro", tipo_erro: erro instanceof Error ? erro.name : "desconhecido" }, "falha no assistente");
    return responderErro(503, mensagens.assistente.indisponivel, idRequisicao);
  }
}
