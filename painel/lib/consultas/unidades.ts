import "server-only";
import { criarClienteServidor } from "@/lib/supabase/servidor";
import { ErroConsulta, type ValoresVgv } from "@/lib/consultas/posicao";
import { normalizarSituacao, type UnidadeMapa } from "@/lib/grade-unidades";

export type ObraResumo = { id: string; nome: string };

const formatoUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Endereço com id malformado não chega ao banco; para o usuário é o mesmo que obra sem permissão.
export function idObraValido(id: string): boolean {
  return formatoUuid.test(id);
}

export async function listarObras(): Promise<ObraResumo[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase.schema("app").from("centro_custo").select("id, nome").order("nome");
  if (error) throw new ErroConsulta(error.code);
  return data as ObraResumo[];
}

export async function buscarObra(centroCustoId: string): Promise<ObraResumo | null> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("app")
    .from("centro_custo")
    .select("id, nome")
    .eq("id", centroCustoId)
    .maybeSingle<ObraResumo>();
  if (error) throw new ErroConsulta(error.code);
  return data;
}

type LinhaMapa = Omit<UnidadeMapa, "situacao"> & { situacao: string | null };

const colunasMapa =
  "unidade_id, unidade, tipologia, area_privativa, situacao, valor, origem_valor, valor_m2, tabela, indice, indice_referencia, indice_valor";

// Uma consulta por tela; o índice por obra e o distinct on da view ficam no Postgres (migration 0004).
// O teto de 1000 é o max_rows padrão da API do Supabase; a maior obra prevista tem algumas centenas.
export async function listarMapaUnidades(centroCustoId: string): Promise<UnidadeMapa[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("mapa_unidades")
    .select(colunasMapa)
    .eq("centro_custo_id", centroCustoId)
    .order("tipologia")
    .order("unidade")
    .limit(1000);
  if (error) throw new ErroConsulta(error.code);
  return (data as LinhaMapa[]).map((linha) => ({ ...linha, situacao: normalizarSituacao(linha.situacao) }));
}

// VGV e estoque vêm prontos da posição financeira, com a mesma regra da visão geral
// (vendida pelo contrato; disponível, reservada e proposta a preço de hoje).
export async function buscarVgvObra(centroCustoId: string): Promise<ValoresVgv | null> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("posicao_financeira_obra")
    .select("vgv_total, vgv_vendido, estoque_a_vender, pct_vgv_vendido")
    .eq("centro_custo_id", centroCustoId)
    .maybeSingle<ValoresVgv>();
  if (error) throw new ErroConsulta(error.code);
  return data;
}
