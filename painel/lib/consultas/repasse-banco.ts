import "server-only";
import { criarClienteServidor } from "@/lib/supabase/servidor";
import { ErroConsulta } from "@/lib/consultas/posicao";
import { numeroOuNulo, numeroOuZero } from "@/lib/consultas/resumo-origem";

export type RepasseBanco = {
  banco: string;
  contratos_com_repasse: number;
  repasses_em_analise: number;
  valor_em_analise: number;
  repasses_assinados: number;
  valor_assinado: number;
  repasses_liberados: number;
  valor_liberado: number;
  repasses_atrasados: number;
  valor_atrasado: number;
  // Nulo quando o banco ainda não liberou nenhum repasse da obra.
  dias_medios_assinatura_liberacao: number | null;
  repasses_parados_analise: number;
  valor_parado_analise: number;
};

const colunasNumericas = [
  "contratos_com_repasse",
  "repasses_em_analise",
  "valor_em_analise",
  "repasses_assinados",
  "valor_assinado",
  "repasses_liberados",
  "valor_liberado",
  "repasses_atrasados",
  "valor_atrasado",
  "repasses_parados_analise",
  "valor_parado_analise",
] as const;

// Uma linha por banco da obra (migration 0026), do banco com mais contratos para o com menos.
// Uma consulta filtrada por obra; uma obra tem poucos bancos, então o teto de linhas é folga.
export async function listarRepasseBanco(centroCustoId: string): Promise<RepasseBanco[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("repasse_banco")
    .select(["banco", ...colunasNumericas, "dias_medios_assinatura_liberacao"].join(", "))
    .eq("centro_custo_id", centroCustoId)
    .order("contratos_com_repasse", { ascending: false })
    .order("banco")
    .limit(50);
  if (error) throw new ErroConsulta(error.code);
  return (data as unknown as Record<string, unknown>[]).map((linha) => ({
    ...(Object.fromEntries(colunasNumericas.map((coluna) => [coluna, numeroOuZero(linha[coluna])])) as Omit<
      RepasseBanco,
      "banco" | "dias_medios_assinatura_liberacao"
    >),
    banco: String(linha.banco),
    dias_medios_assinatura_liberacao: numeroOuNulo(linha.dias_medios_assinatura_liberacao),
  }));
}
