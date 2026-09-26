"use server";

import type { EstadoAcao } from "@/componentes/planejamento/estado-acao";
import {
  validarAtualizacaoLiberacao,
  validarEtapa,
  validarLiberacao,
  validarMedicao,
  validarOperacao,
} from "@/componentes/planejamento/regras-financiamento";
import { leitorDeFormulario } from "@/componentes/planejamento/regras-planejamento";
import {
  listarFinanciamentoContratos,
  listarLiberacoes,
  listarMedicoes,
  listarSaldoOperacoes,
} from "@/lib/consultas/financiamento";
import { mensagensPlanejamento } from "@/lib/mensagens-planejamento";
import { executarGravacao, falhaBanco, falhaValidacao, sucesso } from "../gravacao";

// Complemento manual: grava em app.* com o cliente do usuário, nunca no staging. Autor e data vêm do
// gatilho do banco; o histórico fica na auditoria. Cada ação confere usuário, perfil e obra antes.

function frasePorCodigo(codigo: string | undefined): string | undefined {
  // O gatilho da liberação recusa com 23514 quando a soma passa do valor contratado da operação.
  return codigo === "23514" ? mensagensPlanejamento.acao.limiteOperacao : undefined;
}

export async function registrarOperacao(_estado: EstadoAcao, formulario: FormData): Promise<EstadoAcao> {
  return executarGravacao(formulario, async ({ supabase, obra, valores }) => {
    const validacao = validarOperacao(leitorDeFormulario(formulario));
    if (!validacao.ok) return falhaValidacao(validacao.erros, valores);
    const { error } = await supabase
      .schema("app")
      .from("operacao_credito_obra")
      .insert({ tenant_id: obra.tenant_id, centro_custo_id: obra.id, ...validacao.dados });
    if (error) return falhaBanco(error.code, valores);
    return sucesso("Operação de crédito registrada.");
  });
}

export async function registrarEtapa(_estado: EstadoAcao, formulario: FormData): Promise<EstadoAcao> {
  return executarGravacao(formulario, async ({ supabase, obra, valores }) => {
    const contratos = await listarFinanciamentoContratos(obra.id);
    const validacao = validarEtapa(
      leitorDeFormulario(formulario),
      new Set(contratos.map((contrato) => contrato.contrato_id_origem)),
    );
    if (!validacao.ok) return falhaValidacao(validacao.erros, valores);
    // Uma etapa por contrato: a nova informação substitui a anterior e a auditoria guarda o que era.
    const { error } = await supabase
      .schema("app")
      .from("etapa_financiamento_contrato")
      .upsert(
        { tenant_id: obra.tenant_id, centro_custo_id: obra.id, ...validacao.dados },
        { onConflict: "tenant_id,contrato_id_origem" },
      );
    if (error) return falhaBanco(error.code, valores);
    return sucesso("Etapa do financiamento registrada.");
  });
}

export async function registrarMedicao(_estado: EstadoAcao, formulario: FormData): Promise<EstadoAcao> {
  return executarGravacao(formulario, async ({ supabase, obra, valores }) => {
    const operacoes = await listarSaldoOperacoes(obra.id);
    const validacao = validarMedicao(
      leitorDeFormulario(formulario),
      new Set(operacoes.map((operacao) => operacao.operacao_credito_id)),
    );
    if (!validacao.ok) return falhaValidacao(validacao.erros, valores);
    const { error } = await supabase
      .schema("app")
      .from("medicao_bancaria")
      .insert({ tenant_id: obra.tenant_id, centro_custo_id: obra.id, ...validacao.dados });
    if (error) return falhaBanco(error.code, valores);
    return sucesso("Medição registrada. Medição aprovada não entra no caixa até a liberação ser recebida.");
  });
}

export async function registrarLiberacao(_estado: EstadoAcao, formulario: FormData): Promise<EstadoAcao> {
  return executarGravacao(formulario, async ({ supabase, obra, valores }) => {
    const [operacoes, contratos, medicoes] = await Promise.all([
      listarSaldoOperacoes(obra.id),
      listarFinanciamentoContratos(obra.id),
      listarMedicoes(obra.id),
    ]);
    const validacao = validarLiberacao(leitorDeFormulario(formulario), {
      operacoes: new Set(operacoes.map((operacao) => operacao.operacao_credito_id)),
      contratos: new Set(contratos.map((contrato) => contrato.contrato_id_origem)),
      medicoes: new Set(medicoes.map((medicao) => medicao.id)),
    });
    if (!validacao.ok) return falhaValidacao(validacao.erros, valores);
    const { error } = await supabase
      .schema("app")
      .from("liberacao_financiamento")
      .insert({ tenant_id: obra.tenant_id, centro_custo_id: obra.id, ...validacao.dados });
    if (error) return falhaBanco(error.code, valores, frasePorCodigo(error.code));
    return sucesso("Liberação registrada.");
  });
}

export async function atualizarLiberacao(_estado: EstadoAcao, formulario: FormData): Promise<EstadoAcao> {
  return executarGravacao(formulario, async ({ supabase, obra, dataReferencia, valores }) => {
    const liberacoes = await listarLiberacoes({ centroCustoId: obra.id });
    const validacao = validarAtualizacaoLiberacao(
      leitorDeFormulario(formulario),
      new Set(liberacoes.map((liberacao) => liberacao.id)),
      dataReferencia,
    );
    if (!validacao.ok) return falhaValidacao(validacao.erros, valores);
    const { id, ...mudanca } = validacao.dados;
    const { data, error } = await supabase
      .schema("app")
      .from("liberacao_financiamento")
      .update(mudanca)
      .eq("id", id)
      .eq("centro_custo_id", obra.id)
      .select("id");
    if (error) return falhaBanco(error.code, valores, frasePorCodigo(error.code));
    if (!data || data.length === 0)
      return falhaBanco(undefined, valores, mensagensPlanejamento.acao.registroNaoEncontrado);
    return sucesso("Situação da liberação atualizada. O valor anterior fica no histórico.");
  });
}
