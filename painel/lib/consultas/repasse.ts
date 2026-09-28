import "server-only";
import { criarClienteServidor } from "@/lib/supabase/servidor";
import { ErroConsulta } from "@/lib/consultas/posicao";
import { numeroOuNulo, numeroOuZero } from "@/lib/consultas/resumo-origem";

export type RepasseObra = {
  contratos_financiados_origem: number;
  contratos_com_repasse: number;
  contratos_sem_repasse: number;
  repasses_em_analise: number;
  valor_em_analise: number;
  repasses_assinados: number;
  valor_assinado: number;
  repasses_liberados: number;
  valor_liberado: number;
  repasses_atrasados: number;
  valor_atrasado: number;
  // Nulo quando nenhum repasse da obra chegou ao recurso liberado.
  dias_medios_assinatura_liberacao: number | null;
  a_receber_repasse_origem: number;
  repasse_atrasado_origem: number;
  liberado_sem_baixa_origem: number;
};

const colunas = [
  "contratos_financiados_origem",
  "contratos_com_repasse",
  "contratos_sem_repasse",
  "repasses_em_analise",
  "valor_em_analise",
  "repasses_assinados",
  "valor_assinado",
  "repasses_liberados",
  "valor_liberado",
  "repasses_atrasados",
  "valor_atrasado",
  "dias_medios_assinatura_liberacao",
  "a_receber_repasse_origem",
  "repasse_atrasado_origem",
  "liberado_sem_baixa_origem",
] as const;

// Uma linha por obra (migration 0018); obra sem repasse no CRM ou fora do perfil volta nula pelo RLS.
export async function buscarRepasseObra(centroCustoId: string): Promise<RepasseObra | null> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("repasse_obra")
    .select(colunas.join(", "))
    .eq("centro_custo_id", centroCustoId)
    .maybeSingle<Record<string, unknown>>();
  if (error) throw new ErroConsulta(error.code);
  if (!data) return null;
  const repasse = Object.fromEntries(colunas.map((coluna) => [coluna, numeroOuZero(data[coluna])]));
  return {
    ...repasse,
    dias_medios_assinatura_liberacao: numeroOuNulo(data.dias_medios_assinatura_liberacao),
  } as RepasseObra;
}
