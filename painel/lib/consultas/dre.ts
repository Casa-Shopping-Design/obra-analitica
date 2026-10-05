import "server-only";
import { criarClienteServidor } from "@/lib/supabase/servidor";
import { ErroConsulta } from "@/lib/consultas/posicao";
import { lerCabecalhoDre, lerLinhaDre, lerResumoDre, type CabecalhoDre, type LinhaDre, type ResumoDre } from "@/lib/dre";

export type DreObra = { cabecalho: CabecalhoDre; linhas: LinhaDre[] };

// Uma leitura só, já somada no banco; o RLS deixa a lista vazia para quem não é diretor nem financeiro.
// A tela chama podeVerConferencia antes, para dizer que a tela é restrita em vez de mostrar lista vazia.
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
