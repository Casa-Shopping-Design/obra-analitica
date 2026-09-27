import "server-only";
import { criarClienteServidor } from "@/lib/supabase/servidor";

// Colunas de marts.posicao_financeira_obra (migrations 0005 e 0007). Tipo escrito à mão até a geração automática.
export type PosicaoObra = {
  tenant_id: string;
  centro_custo_id: string;
  obra: string;
  recebido_direto: number;
  recebido_repasse: number;
  a_receber_direto: number;
  a_receber_repasse: number;
  vencido_direto: number;
  repasse_atrasado: number;
  estoque_a_vender: number;
  pago: number;
  a_pagar: number;
  custo_orcado: number;
  custo_a_incorrer: number;
  estouro_orcamento: number;
  caixa_atual: number;
  exposicao_maxima: number;
  resultado_contratado: number;
  resultado_projetado: number;
  vgv_vendido: number;
  vgv_total: number;
  // Fração de 0 a 1; nula quando a obra não tem unidade com preço.
  pct_vgv_vendido: number | null;
};

export type ValoresVgv = Pick<PosicaoObra, "vgv_total" | "vgv_vendido" | "estoque_a_vender" | "pct_vgv_vendido">;

export class ErroConsulta extends Error {}

// Uma linha por obra liberada ao usuário; o RLS filtra, a consulta não repete o filtro.
export async function listarPosicaoObras(): Promise<PosicaoObra[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("posicao_financeira_obra")
    .select("*")
    .order("obra");
  if (error) throw new ErroConsulta(error.code);
  return data as PosicaoObra[];
}

// Obra de outro tenant ou fora das obras do usuário volta nula pelo RLS, igual a uma obra que não existe.
export async function buscarPosicaoObra(centroCustoId: string): Promise<PosicaoObra | null> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("posicao_financeira_obra")
    .select("*")
    .eq("centro_custo_id", centroCustoId)
    .maybeSingle<PosicaoObra>();
  if (error) throw new ErroConsulta(error.code);
  return data;
}
