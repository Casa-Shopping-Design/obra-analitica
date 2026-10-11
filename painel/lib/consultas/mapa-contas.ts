import "server-only";
import { criarClienteServidor } from "@/lib/supabase/servidor";
import { ErroConsulta } from "@/lib/consultas/posicao";
import {
  colunasLinhaCatalogo,
  colunasMapaContas,
  contasPorPagina,
  lerContaMapa,
  lerLinhaCatalogo,
  type ContaMapa,
  type FiltroMapa,
  type LinhaCatalogo,
} from "@/lib/mapa-contas";

export type PaginaMapa = { contas: ContaMapa[]; total: number };

// Uma página do plano de contas com o total contado na mesma consulta. O filtro "sem mapa" olha a linha
// efetiva: conta que herda do prefixo sintético já está mapeada.
export async function listarMapaContas(filtro: FiltroMapa): Promise<PaginaMapa> {
  const supabase = await criarClienteServidor();
  const inicio = (filtro.pagina - 1) * contasPorPagina;
  let consulta = supabase.schema("marts").from("mapa_contas").select(colunasMapaContas, { count: "exact" });
  if (filtro.semMapa) consulta = consulta.is("linha_efetiva", null);
  if (filtro.grupo) consulta = consulta.eq("grupo", filtro.grupo);
  const { data, error, count } = await consulta.order("conta").range(inicio, inicio + contasPorPagina - 1);
  if (error) throw new ErroConsulta(error.code);
  return { contas: (data as Record<string, unknown>[]).map(lerContaMapa), total: count ?? 0 };
}

// Só as linhas do tipo conta podem receber conta contábil; totais e grupos saem da composição do catálogo.
export async function listarLinhasConta(): Promise<LinhaCatalogo[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("linha_relatorio")
    .select(colunasLinhaCatalogo)
    .eq("tipo", "conta")
    .order("demonstrativo")
    .order("ordem");
  if (error) throw new ErroConsulta(error.code);
  return (data as Record<string, unknown>[]).map(lerLinhaCatalogo);
}
