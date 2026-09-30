import "server-only";
import { criarClienteServidor } from "@/lib/supabase/servidor";
import { lerAlertas, ordenarAlertas, type AlertaObra } from "@/lib/alertas";
import { ErroConsulta } from "@/lib/consultas/posicao";
import { numeroOuNulo, numeroOuZero } from "@/lib/consultas/resumo-origem";

export type PosicaoCarteira = {
  obras: number;
  vgv_total: number;
  vgv_vendido: number;
  pct_vgv_vendido: number | null;
  estoque_a_vender: number;
  caixa_atual: number;
  resultado_projetado: number;
  vencido_direto: number;
  repasse_atrasado: number;
  exposicao_maxima: number;
  mes_exposicao_maxima: string | null;
  soma_exposicao_obras: number;
};

// Uma linha por tenant, já somada no banco sobre as obras que o RLS libera.
export async function buscarCarteira(): Promise<PosicaoCarteira | null> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("posicao_carteira")
    .select(
      "obras, vgv_total, vgv_vendido, pct_vgv_vendido, estoque_a_vender, caixa_atual, resultado_projetado, vencido_direto, repasse_atrasado, exposicao_maxima, mes_exposicao_maxima, soma_exposicao_obras",
    )
    .maybeSingle<Record<string, unknown>>();
  if (error) throw new ErroConsulta(error.code);
  if (!data) return null;
  return {
    obras: numeroOuZero(data.obras),
    vgv_total: numeroOuZero(data.vgv_total),
    vgv_vendido: numeroOuZero(data.vgv_vendido),
    pct_vgv_vendido: numeroOuNulo(data.pct_vgv_vendido),
    estoque_a_vender: numeroOuZero(data.estoque_a_vender),
    caixa_atual: numeroOuZero(data.caixa_atual),
    resultado_projetado: numeroOuZero(data.resultado_projetado),
    vencido_direto: numeroOuZero(data.vencido_direto),
    repasse_atrasado: numeroOuZero(data.repasse_atrasado),
    exposicao_maxima: numeroOuZero(data.exposicao_maxima),
    mes_exposicao_maxima: data.mes_exposicao_maxima ? String(data.mes_exposicao_maxima) : null,
    soma_exposicao_obras: numeroOuZero(data.soma_exposicao_obras),
  };
}

// Sem obra, a lista vem da carteira inteira que o usuário vê; com obra, só dela.
export async function listarAlertas(centroCustoId?: string): Promise<AlertaObra[]> {
  const supabase = await criarClienteServidor();
  let consulta = supabase.schema("marts").from("alertas_obra").select("centro_custo_id, obra, tipo, valor, referencia");
  if (centroCustoId) consulta = consulta.eq("centro_custo_id", centroCustoId);
  const { data, error } = await consulta;
  if (error) throw new ErroConsulta(error.code);
  return ordenarAlertas(lerAlertas(data as Record<string, unknown>[]));
}
