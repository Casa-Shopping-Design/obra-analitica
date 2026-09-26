import "server-only";
import { refresh } from "next/cache";
import { valoresDoFormulario, type EstadoAcao } from "@/componentes/planejamento/estado-acao";
import { buscarObraParaEscrita, conferirEscritor, type Escritor } from "@/lib/consultas/planejamento";
import { carregarReferencia } from "@/lib/consultas/referencia";
import { fraseErroGravacao, mensagensPlanejamento } from "@/lib/mensagens-planejamento";
import { lerIdCentro } from "@/lib/periodo";
import { criarClienteServidor } from "@/lib/supabase/servidor";

type Cliente = Awaited<ReturnType<typeof criarClienteServidor>>;

export type ContextoGravacao = {
  supabase: Cliente;
  obra: { id: string; tenant_id: string };
  dataReferencia: string;
  escritor: Escritor;
  valores: Record<string, string>;
};

export function falhaValidacao(erros: Record<string, string>, valores: Record<string, string>): EstadoAcao {
  return { situacao: "erro", mensagem: mensagensPlanejamento.acao.corrijaCampos, erros, valores };
}

// Código do banco vira frase; a mensagem crua, o SQL e o nome da tabela nunca voltam para a tela.
export function falhaBanco(codigo: string | undefined, valores: Record<string, string>, frase?: string): EstadoAcao {
  return { situacao: "erro", mensagem: frase ?? fraseErroGravacao(codigo), erros: {}, valores };
}

export function sucesso(mensagem: string): EstadoAcao {
  return { situacao: "sucesso", mensagem, erros: {}, valores: {} };
}

// Toda gravação passa por aqui: usuário validado pelo Auth (getUser), perfil diretor ou financeiro lido de
// app.usuario_tenant, obra visível pelo RLS e gravação com o cliente do próprio usuário. Nunca service_role.
export async function executarGravacao(
  formulario: FormData,
  gravar: (contexto: ContextoGravacao) => Promise<EstadoAcao>,
): Promise<EstadoAcao> {
  const valores = valoresDoFormulario(formulario);
  let estado: EstadoAcao;
  try {
    const supabase = await criarClienteServidor();
    const permissao = await conferirEscritor(supabase);
    if (!permissao.ok) {
      const frase =
        permissao.motivo === "sem_sessao"
          ? mensagensPlanejamento.acao.semSessao
          : mensagensPlanejamento.acao.semPermissao;
      return falhaBanco(undefined, valores, frase);
    }
    const obraTexto = formulario.get("obra");
    const obraId = lerIdCentro(typeof obraTexto === "string" ? obraTexto : undefined);
    const obra = obraId ? await buscarObraParaEscrita(supabase, obraId) : null;
    if (!obra) return falhaBanco(undefined, valores, mensagensPlanejamento.acao.obraNaoEncontrada);
    const referencia = await carregarReferencia();
    estado = await gravar({
      supabase,
      obra,
      dataReferencia: referencia.dataReferencia,
      escritor: permissao.escritor,
      valores,
    });
  } catch {
    return falhaBanco(undefined, valores);
  }
  if (estado.situacao === "sucesso") refresh();
  return estado;
}
