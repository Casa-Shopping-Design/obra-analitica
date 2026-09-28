import "server-only";
import { criarClienteServidor } from "@/lib/supabase/servidor";
import { ErroConsulta } from "@/lib/consultas/posicao";
import { numeroOuNulo, numeroOuZero, perfilVeConferencia } from "@/lib/consultas/resumo-origem";

export type ItemConferencia = {
  painel: number;
  origem: number;
  diferenca: number;
  // Fração sobre o valor do ERP; nula quando o ERP mostra zero.
  diferencaPct: number | null;
};

export type ConferenciaObra = {
  competenciaOrigem: string;
  vgv: ItemConferencia;
  custoOrcado: ItemConferencia;
  custoIncorrido: ItemConferencia;
  recebido: ItemConferencia;
};

// getClaims valida o JWT. O perfil sai de app.perfil_atual, a mesma função que o RLS usa, que lê
// app_metadata ou a tabela de vínculo. Nunca user_metadata. Falha de leitura conta como sem permissão.
export async function podeVerConferencia(): Promise<boolean> {
  const supabase = await criarClienteServidor();
  const { data: sessao } = await supabase.auth.getClaims();
  if (!sessao?.claims?.sub) return false;
  const { data, error } = await supabase.schema("app").rpc("perfil_atual");
  if (error) return false;
  return perfilVeConferencia(typeof data === "string" ? data : null);
}

function item(linha: Record<string, unknown>, painel: string, origem: string, diferenca: string, pct: string | null) {
  return {
    painel: numeroOuZero(linha[painel]),
    origem: numeroOuZero(linha[origem]),
    diferenca: numeroOuZero(linha[diferenca]),
    diferencaPct: pct ? numeroOuNulo(linha[pct]) : null,
  };
}

// Uma linha por obra, no último mês fechado pelo ERP. A tela chama podeVerConferencia antes.
export async function buscarConferenciaObra(centroCustoId: string): Promise<ConferenciaObra | null> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("conferencia_origem")
    .select(
      "competencia_origem, vgv_painel, vgv_origem, diferenca_vgv, diferenca_vgv_pct, custo_orcado_painel, custo_orcado_origem, diferenca_custo_orcado, custo_incorrido_painel, custo_incorrido_origem, diferenca_custo_incorrido, diferenca_custo_incorrido_pct, recebido_painel, recebido_origem, diferenca_recebido, diferenca_recebido_pct",
    )
    .eq("centro_custo_id", centroCustoId)
    .maybeSingle<Record<string, unknown>>();
  if (error) throw new ErroConsulta(error.code);
  if (!data) return null;
  const custoOrcadoOrigem = numeroOuZero(data.custo_orcado_origem);
  const custoOrcado = item(data, "custo_orcado_painel", "custo_orcado_origem", "diferenca_custo_orcado", null);
  return {
    competenciaOrigem: String(data.competencia_origem),
    vgv: item(data, "vgv_painel", "vgv_origem", "diferenca_vgv", "diferenca_vgv_pct"),
    // A view não traz o percentual do orçamento; a razão é a mesma das outras linhas.
    custoOrcado: {
      ...custoOrcado,
      diferencaPct: custoOrcadoOrigem !== 0 ? custoOrcado.diferenca / custoOrcadoOrigem : null,
    },
    custoIncorrido: item(
      data,
      "custo_incorrido_painel",
      "custo_incorrido_origem",
      "diferenca_custo_incorrido",
      "diferenca_custo_incorrido_pct",
    ),
    recebido: item(data, "recebido_painel", "recebido_origem", "diferenca_recebido", "diferenca_recebido_pct"),
  };
}
