import "server-only";
import { criarClienteServidor } from "@/lib/supabase/servidor";
import { ErroConsulta } from "@/lib/consultas/posicao";
import { numeroOuNulo, numeroOuZero } from "@/lib/consultas/resumo-origem";

export type EstoqueObra = {
  unidades_estoque: number;
  valor_estoque: number;
  unidades_vendidas: number;
  preco_medio_estoque: number | null;
  vendas_media_6m: number | null;
  meses_para_vender_estoque: number | null;
  data_entrega: string | null;
  meses_ate_entrega: number | null;
};

export type EstoqueTipologia = {
  tipologia: string;
  disponiveis: number;
  reservadas: number;
  propostas: number;
  vendidas: number;
  fora_de_venda: number;
  total: number;
  valor_estoque: number;
  preco_medio_estoque: number | null;
  preco_m2_estoque: number | null;
};

export type LinhaVso = {
  competencia: string;
  vendas: number;
  distratos: number;
  vendas_liquidas: number;
  estoque_inicio_mes: number;
  vso_pct: number | null;
};

export type CoberturaOrcamento = {
  custo_orcado: number;
  vgv_contratado: number;
  pct_cobertura: number | null;
  unidades_para_cobrir: number | null;
  meses_para_cobrir: number | null;
};

export const mesesVso = 12;

export async function buscarEstoqueObra(centroCustoId: string): Promise<EstoqueObra | null> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("estoque_obra")
    .select(
      "unidades_estoque, valor_estoque, unidades_vendidas, preco_medio_estoque, vendas_media_6m, meses_para_vender_estoque, data_entrega, meses_ate_entrega",
    )
    .eq("centro_custo_id", centroCustoId)
    .maybeSingle<Record<string, unknown>>();
  if (error) throw new ErroConsulta(error.code);
  if (!data) return null;
  return {
    unidades_estoque: numeroOuZero(data.unidades_estoque),
    valor_estoque: numeroOuZero(data.valor_estoque),
    unidades_vendidas: numeroOuZero(data.unidades_vendidas),
    preco_medio_estoque: numeroOuNulo(data.preco_medio_estoque),
    vendas_media_6m: numeroOuNulo(data.vendas_media_6m),
    meses_para_vender_estoque: numeroOuNulo(data.meses_para_vender_estoque),
    data_entrega: data.data_entrega ? String(data.data_entrega) : null,
    meses_ate_entrega: numeroOuNulo(data.meses_ate_entrega),
  };
}

// Poucas tipologias por obra (duas ou três na demo); a agregação vem pronta da view.
export async function listarEstoqueTipologia(centroCustoId: string): Promise<EstoqueTipologia[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("estoque_tipologia")
    .select(
      "tipologia, disponiveis, reservadas, propostas, vendidas, fora_de_venda, total, valor_estoque, preco_medio_estoque, preco_m2_estoque",
    )
    .eq("centro_custo_id", centroCustoId)
    .order("tipologia");
  if (error) throw new ErroConsulta(error.code);
  return (data as Record<string, unknown>[]).map((linha) => ({
    tipologia: String(linha.tipologia),
    disponiveis: numeroOuZero(linha.disponiveis),
    reservadas: numeroOuZero(linha.reservadas),
    propostas: numeroOuZero(linha.propostas),
    vendidas: numeroOuZero(linha.vendidas),
    fora_de_venda: numeroOuZero(linha.fora_de_venda),
    total: numeroOuZero(linha.total),
    valor_estoque: numeroOuZero(linha.valor_estoque),
    preco_medio_estoque: numeroOuNulo(linha.preco_medio_estoque),
    preco_m2_estoque: numeroOuNulo(linha.preco_m2_estoque),
  }));
}

// Os 12 meses mais recentes da migration 0015, do mais antigo para o mais novo.
export async function listarVsoObra(centroCustoId: string): Promise<LinhaVso[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("vso_mensal")
    .select("competencia, vendas, distratos, vendas_liquidas, estoque_inicio_mes, vso_pct")
    .eq("centro_custo_id", centroCustoId)
    .order("competencia", { ascending: false })
    .limit(mesesVso);
  if (error) throw new ErroConsulta(error.code);
  return (data as Record<string, unknown>[])
    .map((linha) => ({
      competencia: String(linha.competencia),
      vendas: numeroOuZero(linha.vendas),
      distratos: numeroOuZero(linha.distratos),
      vendas_liquidas: numeroOuZero(linha.vendas_liquidas),
      estoque_inicio_mes: numeroOuZero(linha.estoque_inicio_mes),
      vso_pct: numeroOuNulo(linha.vso_pct),
    }))
    .reverse();
}

export async function buscarCobertura(centroCustoId: string): Promise<CoberturaOrcamento | null> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("cobertura_orcamento_obra")
    .select("custo_orcado, vgv_contratado, pct_cobertura, unidades_para_cobrir, meses_para_cobrir")
    .eq("centro_custo_id", centroCustoId)
    .maybeSingle<Record<string, unknown>>();
  if (error) throw new ErroConsulta(error.code);
  if (!data) return null;
  return {
    custo_orcado: numeroOuZero(data.custo_orcado),
    vgv_contratado: numeroOuZero(data.vgv_contratado),
    pct_cobertura: numeroOuNulo(data.pct_cobertura),
    unidades_para_cobrir: numeroOuNulo(data.unidades_para_cobrir),
    meses_para_cobrir: numeroOuNulo(data.meses_para_cobrir),
  };
}
