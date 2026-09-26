"use server";

import { refresh } from "next/cache";
import {
  categoriaServeParaOrigem,
  leitorDoFormulario,
  validarClassificacao,
  validarCriterio,
  valoresDoFormulario,
  type EstadoGravacao,
} from "@/componentes/financeiro/regras-classificacao";
import type { CategoriaGerencial } from "@/lib/consultas/dre";
import { fraseErroGravacao, mensagens } from "@/lib/mensagens";
import { criarClienteServidor } from "@/lib/supabase/servidor";

type Cliente = Awaited<ReturnType<typeof criarClienteServidor>>;
type Escritor = { supabase: Cliente; tenantId: string };

function falha(mensagem: string, valores: Record<string, string>, erros: Record<string, string> = {}): EstadoGravacao {
  return { situacao: "erro", mensagem, erros, valores };
}

// getUser valida o token no Auth. Tenant e perfil vêm das mesmas funções que o RLS usa (claims do JWT),
// nunca de user_metadata. A conferência só adianta a mensagem: quem decide a gravação é o RLS.
async function conferirEscritor(): Promise<Escritor | { erro: string }> {
  const supabase = await criarClienteServidor();
  const { data: dadosUsuario } = await supabase.auth.getUser();
  if (!dadosUsuario.user) return { erro: mensagens.gravacao.semSessao };
  const [tenant, perfil] = await Promise.all([
    supabase.schema("app").rpc("tenant_atual"),
    supabase.schema("app").rpc("perfil_atual"),
  ]);
  if (tenant.error || perfil.error || typeof tenant.data !== "string") return { erro: mensagens.gravacao.semPermissao };
  if (perfil.data !== "diretor" && perfil.data !== "financeiro") return { erro: mensagens.gravacao.semPermissao };
  return { supabase, tenantId: tenant.data };
}

// Insere ou troca a categoria de uma conta de origem. O gatilho da 0011 recusa categoria incompatível (23514)
// e grava autor e auditoria; aqui a mesma regra dá a mensagem antes de ir ao banco.
export async function classificarConta(_estado: EstadoGravacao, formulario: FormData): Promise<EstadoGravacao> {
  const valores = valoresDoFormulario(formulario);
  const validacao = validarClassificacao(leitorDoFormulario(formulario));
  if (!validacao.ok) return falha(mensagens.gravacao.corrijaCampos, valores, validacao.erros);
  const dados = validacao.dados;
  try {
    const escritor = await conferirEscritor();
    if ("erro" in escritor) return falha(escritor.erro, valores);
    const { supabase, tenantId } = escritor;

    const { data: categoria, error: erroCategoria } = await supabase
      .schema("app")
      .from("categoria_gerencial")
      .select("codigo, natureza, grupo_dre")
      .eq("codigo", dados.categoria_codigo)
      .maybeSingle<Pick<CategoriaGerencial, "codigo" | "natureza" | "grupo_dre">>();
    if (erroCategoria) return falha(fraseErroGravacao(erroCategoria.code), valores);
    if (!categoria || !categoriaServeParaOrigem(dados.tipo_origem, categoria)) {
      return falha(mensagens.gravacao.categoriaIncompativel, valores, {
        categoria_codigo: mensagens.gravacao.categoriaIncompativel,
      });
    }

    const { error } = await supabase
      .schema("app")
      .from("mapa_conta_origem")
      .upsert({ tenant_id: tenantId, ...dados }, { onConflict: "tenant_id,tipo_origem,conta_origem" });
    if (error) return falha(fraseErroGravacao(error.code), valores);
  } catch {
    return falha(mensagens.gravacao.indisponivel, valores);
  }
  refresh();
  return { situacao: "sucesso", mensagem: mensagens.gravacao.classificada, erros: {}, valores: {} };
}

// Registra o critério do tenant (escopo "tenant") ou de uma obra. validado_por e validado_em são gravados pelo
// gatilho com auth.uid() do próprio usuário; o valor mandado pelo formulário não existe.
export async function registrarCriterio(_estado: EstadoGravacao, formulario: FormData): Promise<EstadoGravacao> {
  const valores = valoresDoFormulario(formulario);
  const validacao = validarCriterio(leitorDoFormulario(formulario));
  if (!validacao.ok) return falha(mensagens.gravacao.corrijaCampos, valores, validacao.erros);
  const dados = validacao.dados;
  try {
    const escritor = await conferirEscritor();
    if ("erro" in escritor) return falha(escritor.erro, valores);
    const { supabase, tenantId } = escritor;

    if (dados.centro_custo_id) {
      const { data: obra, error: erroObra } = await supabase
        .schema("app")
        .from("centro_custo")
        .select("id")
        .eq("id", dados.centro_custo_id)
        .eq("tipo", "obra")
        .maybeSingle();
      if (erroObra) return falha(fraseErroGravacao(erroObra.code), valores);
      if (!obra)
        return falha(mensagens.gravacao.obraNaoEncontrada, valores, { escopo: mensagens.gravacao.obraNaoEncontrada });
    }

    const { error } = await supabase
      .schema("app")
      .from("criterio_reconhecimento")
      .upsert({ tenant_id: tenantId, ...dados }, { onConflict: "tenant_id,centro_custo_id" });
    if (error) return falha(fraseErroGravacao(error.code), valores);
  } catch {
    return falha(mensagens.gravacao.indisponivel, valores);
  }
  refresh();
  const mensagem =
    dados.metodo === "percentual_conclusao"
      ? mensagens.gravacao.criterioValidado
      : mensagens.gravacao.criterioDesligado;
  return { situacao: "sucesso", mensagem, erros: {}, valores: {} };
}
