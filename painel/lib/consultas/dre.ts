import "server-only";
import { criarClienteServidor } from "@/lib/supabase/servidor";
import { ErroConsulta } from "@/lib/consultas/posicao";
import { lerPerfilAtual } from "@/lib/consultas/perfil";
import {
  lerCabecalhoDre,
  lerLinhaDre,
  lerResumoCarteiraDre,
  lerResumoDre,
  perfilVeDre,
  type CabecalhoDre,
  type LinhaDre,
  type ResumoCarteiraDre,
  type ResumoDre,
} from "@/lib/dre";

export type DreObra = { cabecalho: CabecalhoDre; linhas: LinhaDre[] };

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
