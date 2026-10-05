import "server-only";
import { criarClienteServidor } from "@/lib/supabase/servidor";
import { ErroConsulta } from "@/lib/consultas/posicao";
import { lerPerfilAtual } from "@/lib/consultas/perfil";
import {
  lerAliquotaVigente,
  lerCabecalhoDre,
  lerEstudoVigente,
  lerLinhaDre,
  lerResumoCarteiraDre,
  lerResumoDre,
  lerVersaoEstudo,
  perfilVeDre,
  type AliquotaVigente,
  type CabecalhoDre,
  type EstudoVigente,
  type LinhaDre,
  type ResumoCarteiraDre,
  type ResumoDre,
  type VersaoEstudo,
} from "@/lib/dre";
import { hojeEmBrasilia } from "@/lib/estudo-digitado";

export type DreObra = { cabecalho: CabecalhoDre; linhas: LinhaDre[] };

export const versoesPorPagina = 20;

export type PaginaVersoes = { versoes: VersaoEstudo[]; total: number; pagina: number };

export async function podeVerDre(): Promise<boolean> {
  return perfilVeDre(await lerPerfilAtual());
}

// Uma leitura só, já somada no banco; o RLS deixa a lista vazia para quem não é diretor, financeiro ou
// leitura. A tela chama podeVerDre antes, para dizer que a tela é restrita em vez de mostrar lista vazia.
export async function listarResumoDre(): Promise<ResumoDre[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("dre_resumo_obra")
    .select(
      "centro_custo_id, obra, competencia, estudo_versao, margem_operacional_viabilidade, margem_operacional_tendencia, desvio_margem_operacional",
    )
    .order("obra");
  if (error) throw new ErroConsulta(error.code);
  return (data as Record<string, unknown>[]).map(lerResumoDre);
}

// Dezessete linhas por obra com estudo vigente; nulo quando a obra não tem estudo.
export async function listarDreObra(centroCustoId: string): Promise<DreObra | null> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("dre_viabilidade")
    .select(
      "obra, competencia, estudo_versao, estudo_data_base, linha, ordem, nivel, natureza, linha_de_total, fonte_realizado, viabilidade, pct_viabilidade, apropriado, a_apropriar, a_contratar, a_realizar, tendencia, pct_tendencia, desvio, desvio_pct, desvio_favoravel",
    )
    .eq("centro_custo_id", centroCustoId)
    .order("ordem");
  if (error) throw new ErroConsulta(error.code);
  const linhas = data as Record<string, unknown>[];
  if (linhas.length === 0) return null;
  return { cabecalho: lerCabecalhoDre(linhas[0]), linhas: linhas.map(lerLinhaDre) };
}

// Uma consulta: o estudo vigente com as onze linhas embutidas pela chave estrangeira. O índice parcial da
// vigente atende o filtro. Nulo para obra sem estudo ou fora do perfil.
export async function buscarEstudoVigente(centroCustoId: string): Promise<EstudoVigente | null> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("app")
    .from("estudo_viabilidade")
    .select("id, versao, descricao, data_base, estudo_viabilidade_linha(linha, valor)")
    .eq("centro_custo_id", centroCustoId)
    .eq("situacao", "vigente")
    .maybeSingle<Record<string, unknown>>();
  if (error) throw new ErroConsulta(error.code);
  return data ? lerEstudoVigente(data) : null;
}

// Da mais nova para a mais antiga, 20 por página, com o total contado na mesma consulta.
export async function listarVersoesEstudo(centroCustoId: string, pagina = 1): Promise<PaginaVersoes> {
  const supabase = await criarClienteServidor();
  const inicio = (pagina - 1) * versoesPorPagina;
  const { data, error, count } = await supabase
    .schema("app")
    .from("estudo_viabilidade")
    .select("versao, descricao, data_base, situacao, criado_em, criado_por", { count: "exact" })
    .eq("centro_custo_id", centroCustoId)
    .order("versao", { ascending: false })
    .range(inicio, inicio + versoesPorPagina - 1);
  if (error) throw new ErroConsulta(error.code);
  return { versoes: (data as Record<string, unknown>[]).map(lerVersaoEstudo), total: count ?? 0, pagina };
}

// A mesma regra da view: maior vigência até hoje e, no empate, a gravada por último.
export async function buscarAliquotaVigente(centroCustoId: string): Promise<AliquotaVigente | null> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("app")
    .from("aliquota_imposto_obra")
    .select("aliquota, vigencia_inicio")
    .eq("centro_custo_id", centroCustoId)
    .lte("vigencia_inicio", hojeEmBrasilia())
    .order("vigencia_inicio", { ascending: false })
    .order("criado_em", { ascending: false })
    .order("id", { ascending: false })
    .limit(1)
    .maybeSingle<Record<string, unknown>>();
  if (error) throw new ErroConsulta(error.code);
  return data ? lerAliquotaVigente(data) : null;
}

// Uma linha por tenant, somada no banco sobre as obras com estudo que o RLS libera; nulo para quem não é
// diretor nem financeiro, e aí a visão geral esconde a faixa.
export async function buscarResumoCarteira(): Promise<ResumoCarteiraDre | null> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("dre_resumo_carteira")
    .select(
      "obras, vgv_bruto_tendencia, vgv_vendido, pct_vendido, receita_apropriada, poc, custo_apropriado, recebido_acumulado, lucro_operacional_viabilidade, lucro_operacional_tendencia, margem_operacional_viabilidade, margem_operacional_tendencia, desvio_margem_operacional",
    )
    .maybeSingle<Record<string, unknown>>();
  if (error) throw new ErroConsulta(error.code);
  return data ? lerResumoCarteiraDre(data) : null;
}
