import "server-only";
import { criarClienteServidor } from "@/lib/supabase/servidor";
import { ErroConsulta } from "@/lib/consultas/posicao";
import { lerPerfilAtual } from "@/lib/consultas/perfil";
import {
  colunasContaSemMapa,
  colunasControle,
  colunasMensal,
  colunasResumoEmpresa,
  lerContaSemMapa,
  lerControle,
  lerLinhaDemonstrativo,
  lerLinhaMensal,
  lerResumoEmpresa,
  perfilEditaMapa,
  perfilVeEmpresas,
  type ContaSemMapa,
  type ControleEmpresa,
  type LinhaDemonstrativo,
  type LinhaMensal,
  type ResumoEmpresa,
} from "@/lib/empresa";
import { parametrosDemonstrativo, type PeriodoEmpresa } from "@/lib/empresa-periodo";

export type Demonstrativo = "fontes_usos" | "dre_societaria" | "custo_incorrido";

const campoPercentual: Record<Demonstrativo, string | undefined> = {
  fontes_usos: undefined,
  dre_societaria: "pct_receita_liquida",
  custo_incorrido: "pct_custo_incorrido",
};

const viewMensal: Record<Demonstrativo, string> = {
  fontes_usos: "fontes_usos_mensal",
  dre_societaria: "dre_societaria_mensal",
  custo_incorrido: "custo_incorrido_mensal",
};

// Teto da grade: ~60 linhas do maior relatório vezes 12 meses, abaixo do limite de linhas do PostgREST.
const limiteLinhasGrade = 1000;
const limiteContasSemMapa = 200;

export type AcessoEmpresas = { ver: boolean; editarMapa: boolean };

// Uma leitura do perfil para as duas decisões da tela. Falha de leitura fecha as duas.
export async function lerAcessoEmpresas(): Promise<AcessoEmpresas> {
  try {
    const perfil = await lerPerfilAtual();
    return { ver: perfilVeEmpresas(perfil), editarMapa: perfilEditaMapa(perfil) };
  } catch {
    return { ver: false, editarMapa: false };
  }
}

// O RLS (app.empresas_permitidas) decide quais empresas voltam; a consulta não repete o filtro.
export async function listarEmpresas(): Promise<ResumoEmpresa[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase.schema("marts").from("empresa_resumo").select(colunasResumoEmpresa).order("nome");
  if (error) throw new ErroConsulta(error.code);
  return (data as Record<string, unknown>[]).map(lerResumoEmpresa);
}

export async function buscarEmpresa(empresaId: string): Promise<ResumoEmpresa | null> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("empresa_resumo")
    .select(colunasResumoEmpresa)
    .eq("empresa_id", empresaId)
    .maybeSingle<Record<string, unknown>>();
  if (error) throw new ErroConsulta(error.code);
  return data ? lerResumoEmpresa(data) : null;
}

// Uma chamada à função do banco, que já devolve totais e grupos compostos pelo catálogo, na ordem da planilha.
export async function listarDemonstrativo(
  demonstrativo: Demonstrativo,
  empresaId: string,
  periodo: PeriodoEmpresa,
): Promise<LinhaDemonstrativo[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .rpc(demonstrativo, parametrosDemonstrativo(empresaId, periodo))
    .order("ordem");
  if (error) throw new ErroConsulta(error.code);
  return ((data ?? []) as Record<string, unknown>[]).map((linha) => lerLinhaDemonstrativo(linha, campoPercentual[demonstrativo]));
}

// Uma consulta para os até doze meses da grade, filtrada por empresa e competência (as duas com índice no banco).
export async function listarDemonstrativoMensal(
  demonstrativo: Demonstrativo,
  empresaId: string,
  meses: string[],
): Promise<LinhaMensal[]> {
  if (meses.length === 0) return [];
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from(viewMensal[demonstrativo])
    .select(colunasMensal)
    .eq("empresa_id", empresaId)
    .gte("competencia", `${meses[0]}-01`)
    .lte("competencia", `${meses[meses.length - 1]}-01`)
    .order("ordem")
    .order("competencia")
    .limit(limiteLinhasGrade);
  if (error) throw new ErroConsulta(error.code);
  return (data as Record<string, unknown>[]).map(lerLinhaMensal);
}

export async function buscarControle(empresaId: string, mes: string): Promise<ControleEmpresa | null> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("controle_fontes_usos")
    .select(colunasControle)
    .eq("empresa_id", empresaId)
    .eq("competencia", `${mes}-01`)
    .maybeSingle<Record<string, unknown>>();
  if (error) throw new ErroConsulta(error.code);
  return data ? lerControle(data) : null;
}

// Na ordem do plano de contas, como o contador procura.
export async function listarContasSemMapa(empresaId: string): Promise<ContaSemMapa[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("conta_sem_mapa")
    .select(colunasContaSemMapa)
    .eq("empresa_id", empresaId)
    .order("conta")
    .limit(limiteContasSemMapa);
  if (error) throw new ErroConsulta(error.code);
  return (data as Record<string, unknown>[]).map(lerContaSemMapa);
}
