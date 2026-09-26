import "server-only";
import { refresh } from "next/cache";
import { valoresDoFormulario, type EstadoAcao } from "@/componentes/planejamento/estado-acao";
import { lerEscopo, mensagensConfiguracao } from "@/lib/configuracao";
import { buscarObraParaEscrita } from "@/lib/consultas/planejamento";
import { fraseErroGravacao } from "@/lib/mensagens";
import { criarClienteServidor } from "@/lib/supabase/servidor";

type Cliente = Awaited<ReturnType<typeof criarClienteServidor>>;

export type ContextoConfiguracao = {
  supabase: Cliente;
  tenantId: string;
  usuarioId: string;
  valores: Record<string, string>;
};

export function falhaValidacao(erros: Record<string, string>, valores: Record<string, string>): EstadoAcao {
  return { situacao: "erro", mensagem: mensagensConfiguracao.corrijaCampos, erros, valores };
}

// Código do banco vira frase; a mensagem crua, o SQL e o nome da tabela nunca voltam para a tela.
export function falhaBanco(codigo: string | undefined, valores: Record<string, string>, frase?: string): EstadoAcao {
  return { situacao: "erro", mensagem: frase ?? fraseErroGravacao(codigo), erros: {}, valores };
}

export function sucesso(mensagem: string): EstadoAcao {
  return { situacao: "sucesso", mensagem, erros: {}, valores: {} };
}

// Toda gravação de configuração passa por aqui: usuário validado pelo Auth (getUser), tenant e perfil pelas
// mesmas funções que o RLS usa (claims do JWT, nunca user_metadata) e gravação com o cliente do próprio
// usuário. A conferência de perfil só adianta a mensagem: quem decide é o RLS. Nunca service_role.
export async function executarConfiguracao(
  formulario: FormData,
  gravar: (contexto: ContextoConfiguracao) => Promise<EstadoAcao>,
): Promise<EstadoAcao> {
  const valores = valoresDoFormulario(formulario);
  let estado: EstadoAcao;
  try {
    const supabase = await criarClienteServidor();
    const { data: dadosUsuario } = await supabase.auth.getUser();
    if (!dadosUsuario.user) return falhaBanco(undefined, valores, mensagensConfiguracao.semSessao);
    const [tenant, perfil] = await Promise.all([
      supabase.schema("app").rpc("tenant_atual"),
      supabase.schema("app").rpc("perfil_atual"),
    ]);
    if (tenant.error || perfil.error || typeof tenant.data !== "string") {
      return falhaBanco(undefined, valores, mensagensConfiguracao.semPermissao);
    }
    if (perfil.data !== "diretor" && perfil.data !== "financeiro") {
      return falhaBanco(undefined, valores, mensagensConfiguracao.semPermissao);
    }
    estado = await gravar({ supabase, tenantId: tenant.data, usuarioId: dadosUsuario.user.id, valores });
  } catch {
    return falhaBanco(undefined, valores);
  }
  if (estado.situacao === "sucesso") refresh();
  return estado;
}

export type EscopoLido = { ok: true; centroId: string | null } | { ok: false; estado: EstadoAcao };

// Escopo "construtora" ou uma obra do mesmo tenant que o RLS deixa ver. O banco confere de novo.
export async function lerEscopoDoFormulario(contexto: ContextoConfiguracao): Promise<EscopoLido> {
  const escopo = lerEscopo(contexto.valores.escopo);
  if (!escopo.ok) {
    return { ok: false, estado: falhaBanco(undefined, contexto.valores, mensagensConfiguracao.obraNaoEncontrada) };
  }
  if (escopo.centroId === null) return { ok: true, centroId: null };
  const obra = await buscarObraParaEscrita(contexto.supabase, escopo.centroId);
  if (!obra || obra.tenant_id !== contexto.tenantId) {
    return { ok: false, estado: falhaBanco(undefined, contexto.valores, mensagensConfiguracao.obraNaoEncontrada) };
  }
  return { ok: true, centroId: obra.id };
}
