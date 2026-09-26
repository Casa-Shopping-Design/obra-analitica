"use server";

import type { EstadoAcao } from "@/componentes/planejamento/estado-acao";
import {
  leitorDeFormulario,
  validarDescricaoVersao,
  validarMetas,
  validarPremissaDistribuicao,
} from "@/componentes/planejamento/regras-planejamento";
import { executarGravacao, falhaBanco, falhaValidacao, sucesso } from "./gravacao";

// Cada ação confere usuário, perfil e obra em executarGravacao, valida a entrada aqui no servidor e chama a
// função do banco com o JWT do usuário. As funções são security invoker: o RLS decide se grava.

export async function registrarVersaoProjecao(_estado: EstadoAcao, formulario: FormData): Promise<EstadoAcao> {
  return executarGravacao(formulario, async ({ supabase, obra, valores }) => {
    const validacao = validarDescricaoVersao(leitorDeFormulario(formulario));
    if (!validacao.ok) return falhaValidacao(validacao.erros, valores);
    const { error } = await supabase
      .schema("app")
      .rpc("registrar_versao_projecao", { p_centro_custo_id: obra.id, p_descricao: validacao.descricao });
    if (error) return falhaBanco(error.code, valores);
    return sucesso("Projeção registrada numa versão nova. As versões anteriores continuam guardadas.");
  });
}

export async function registrarVersaoMeta(_estado: EstadoAcao, formulario: FormData): Promise<EstadoAcao> {
  return executarGravacao(formulario, async ({ supabase, obra, dataReferencia, valores }) => {
    const validacao = validarMetas(leitorDeFormulario(formulario), dataReferencia);
    if (!validacao.ok) return falhaValidacao(validacao.erros, valores);
    const { error } = await supabase.schema("app").rpc("registrar_versao_meta", {
      p_centro_custo_id: obra.id,
      p_descricao: validacao.descricao,
      p_metas: validacao.metas,
    });
    if (error) return falhaBanco(error.code, valores);
    return sucesso(
      `Metas de ${validacao.metas.length} ${validacao.metas.length === 1 ? "mês registradas" : "meses registradas"} numa versão nova.`,
    );
  });
}

export async function registrarPremissaDistribuicao(_estado: EstadoAcao, formulario: FormData): Promise<EstadoAcao> {
  return executarGravacao(formulario, async ({ supabase, obra, dataReferencia, valores }) => {
    const validacao = validarPremissaDistribuicao(leitorDeFormulario(formulario), dataReferencia);
    if (!validacao.ok) return falhaValidacao(validacao.erros, valores);
    const { error } = await supabase.schema("app").rpc("registrar_premissa_distribuicao", {
      p_centro_custo_id: obra.id,
      p_fonte: validacao.fonte,
      p_observacao: validacao.observacao,
      p_meses: validacao.meses,
    });
    if (error) return falhaBanco(error.code, valores);
    return sucesso("Premissa registrada. O fluxo passa a distribuir o custo sem título por ela.");
  });
}
