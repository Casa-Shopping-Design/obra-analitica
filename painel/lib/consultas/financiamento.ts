import "server-only";
import { ErroConsulta } from "@/lib/consultas/posicao";
import { converterColunas } from "@/lib/consultas/referencia";
import { criarClienteServidor } from "@/lib/supabase/servidor";

// Tipos da seção 6.8 do contrato de dados; colunas iguais às tabelas e views da migration 0012.
export type ClassificacaoFinanciamento = "financiamento_elegivel" | "financiamento_pendente";
export type EtapaFinanciamento = "contratacao" | "aprovacao" | "elegivel" | "liberado";
export type ModalidadeCredito = "credito_producao" | "plano_empresario" | "credito_associativo" | "outra";
export type SituacaoLiberacao = "prevista" | "pendente" | "recebida" | "cancelada";
export type NivelLiberacao = "contrato" | "empreendimento" | "lote";

export type FinanciamentoContrato = {
  tenant_id: string;
  centro_custo_id: string;
  contrato_id_origem: number;
  contrato_numero: string | null;
  unidade: string | null;
  valor_contrato: number;
  valor_financiado: number | null;
  instituicao_financeira: string | null;
  data_financiamento_origem: string | null;
  credito_associativo: boolean | null;
  etapa: EtapaFinanciamento | null;
  pendencia: boolean | null;
  motivo_pendencia: string | null;
  data_etapa: string | null;
  data_prevista_liberacao: string | null;
  classificacao: ClassificacaoFinanciamento;
  saldo_financiamento_aberto: number;
  recebido_financiamento: number;
  // Etapa cadastrada ou, sem ela, a que a data do banco na origem indica (financiamento.data_origem_significa).
  etapa_efetiva: EtapaFinanciamento | null;
};

export type SaldoOperacaoCredito = {
  tenant_id: string;
  centro_custo_id: string;
  operacao_credito_id: string;
  modalidade: ModalidadeCredito;
  instituicao: string;
  valor_contratado: number;
  percentual_retencao: number | null;
  retencao_prevista: number | null;
  limite_antes_retencao: number;
  liberado_recebido: number;
  previsto_aberto: number;
  saldo_liberavel: number;
  saldo_nao_programado: number;
  medido_elegivel: number;
  elegivel_nao_liberado: number;
  excede_limite: boolean;
  // "operacao" quando a operação informa a retenção; "padrao" quando vem de financiamento.retencao_padrao.
  origem_retencao: "operacao" | "padrao" | null;
};

export type LinhaLiberacao = {
  id: string;
  tenant_id: string;
  centro_custo_id: string;
  nivel: NivelLiberacao;
  operacao_credito_id: string | null;
  contrato_id_origem: number | null;
  contrato_numero: string | null;
  medicao_id: string | null;
  descricao_lote: string | null;
  valor_previsto: number;
  data_prevista: string;
  situacao: SituacaoLiberacao;
  situacao_efetiva: SituacaoLiberacao | "atrasada";
  motivo: string | null;
  valor_recebido: number | null;
  data_recebimento: string | null;
  vinculo_tipo: "recebimento" | "lancamento_manual" | null;
  vinculo_chave: string | null;
  fonte: string;
  referencia_documento: string | null;
  dias_atraso: number | null;
  origem_dado: "complemento_manual";
};

export type MedicaoBancaria = {
  id: string;
  tenant_id: string;
  centro_custo_id: string;
  operacao_credito_id: string;
  numero: number;
  data_vistoria: string;
  avanco_fisico_informado: number;
  data_apresentacao: string | null;
  situacao: "apresentada" | "aprovada" | "reprovada";
  data_aprovacao: string | null;
  valor_medido: number | null;
  valor_elegivel: number | null;
  valor_retido: number | null;
  fonte: string;
  referencia_documento: string | null;
};

export type AlteracaoRegistro = {
  id: number;
  tabela: string;
  registro_id: string;
  operacao: "insert" | "update" | "delete";
  antes: Record<string, unknown> | null;
  depois: Record<string, unknown> | null;
  autor: string | null;
  alterado_em: string;
};

// Contratos com financiamento de uma obra: algumas centenas no máximo (800 contratos por tenant).
export async function listarFinanciamentoContratos(centroCustoId: string | null): Promise<FinanciamentoContrato[]> {
  const supabase = await criarClienteServidor();
  let consulta = supabase
    .schema("marts")
    .from("financiamento_contrato")
    .select(
      "centro_custo_id, contrato_id_origem, contrato_numero, unidade, valor_contrato, valor_financiado, instituicao_financeira, data_financiamento_origem, credito_associativo, etapa, pendencia, motivo_pendencia, data_etapa, data_prevista_liberacao, classificacao, saldo_financiamento_aberto, recebido_financiamento, etapa_efetiva",
    );
  if (centroCustoId) consulta = consulta.eq("centro_custo_id", centroCustoId);
  const { data, error } = await consulta.order("classificacao", { ascending: false }).order("contrato_numero");
  if (error) throw new ErroConsulta(error.code);
  return converterColunas<FinanciamentoContrato>(
    data ?? [],
    ["contrato_id_origem", "valor_contrato", "saldo_financiamento_aberto", "recebido_financiamento"],
    ["valor_financiado"],
  );
}

const colunasSaldoValor = [
  "valor_contratado",
  "limite_antes_retencao",
  "liberado_recebido",
  "previsto_aberto",
  "saldo_liberavel",
  "saldo_nao_programado",
  "medido_elegivel",
  "elegivel_nao_liberado",
] as const;

export async function listarSaldoOperacoes(centroCustoId: string | null): Promise<SaldoOperacaoCredito[]> {
  const supabase = await criarClienteServidor();
  let consulta = supabase
    .schema("marts")
    .from("saldo_operacao_credito")
    .select(
      `centro_custo_id, operacao_credito_id, modalidade, instituicao, percentual_retencao, retencao_prevista, excede_limite, origem_retencao, ${colunasSaldoValor.join(", ")}`,
    );
  if (centroCustoId) consulta = consulta.eq("centro_custo_id", centroCustoId);
  const { data, error } = await consulta.order("centro_custo_id").order("instituicao");
  if (error) throw new ErroConsulta(error.code);
  return converterColunas<SaldoOperacaoCredito>(data ?? [], colunasSaldoValor, ["percentual_retencao", "retencao_prevista"]);
}

export type FiltroLiberacoes = { centroCustoId: string | null; situacoesEfetivas?: LinhaLiberacao["situacao_efetiva"][] };

export async function listarLiberacoes(filtro: FiltroLiberacoes): Promise<LinhaLiberacao[]> {
  const supabase = await criarClienteServidor();
  let consulta = supabase
    .schema("marts")
    .from("liberacao_status")
    .select(
      "id, centro_custo_id, nivel, operacao_credito_id, contrato_id_origem, contrato_numero, medicao_id, descricao_lote, valor_previsto, data_prevista, situacao, situacao_efetiva, motivo, valor_recebido, data_recebimento, vinculo_tipo, vinculo_chave, fonte, referencia_documento, dias_atraso, origem_dado",
    );
  if (filtro.centroCustoId) consulta = consulta.eq("centro_custo_id", filtro.centroCustoId);
  if (filtro.situacoesEfetivas?.length) consulta = consulta.in("situacao_efetiva", filtro.situacoesEfetivas);
  const { data, error } = await consulta.order("data_prevista");
  if (error) throw new ErroConsulta(error.code);
  return converterColunas<LinhaLiberacao>(data ?? [], ["valor_previsto"], ["contrato_id_origem", "valor_recebido", "dias_atraso"]);
}

export async function listarMedicoes(centroCustoId: string): Promise<MedicaoBancaria[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("app")
    .from("medicao_bancaria")
    .select(
      "id, centro_custo_id, operacao_credito_id, numero, data_vistoria, avanco_fisico_informado, data_apresentacao, situacao, data_aprovacao, valor_medido, valor_elegivel, valor_retido, fonte, referencia_documento",
    )
    .eq("centro_custo_id", centroCustoId)
    .order("operacao_credito_id")
    .order("numero");
  if (error) throw new ErroConsulta(error.code);
  return converterColunas<MedicaoBancaria>(
    data ?? [],
    ["numero", "avanco_fisico_informado"],
    ["valor_medido", "valor_elegivel", "valor_retido"],
  );
}

export const tabelasComplemento = [
  "app.operacao_credito_obra",
  "app.etapa_financiamento_contrato",
  "app.medicao_bancaria",
  "app.liberacao_financiamento",
] as const;

// A auditoria não tem coluna de obra: o filtro lê o centro gravado no próprio registro (antes ou depois).
// Só diretor e financeiro enxergam as linhas; os demais recebem lista vazia pelo RLS. Volume pequeno
// (complemento manual), com teto de linhas.
// O id entra no texto do filtro .or(), por isso só passa no formato de UUID.
const formatoUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function listarHistoricoComplemento(centroCustoId: string, limite = 30): Promise<AlteracaoRegistro[]> {
  if (!formatoUuid.test(centroCustoId)) return [];
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("app")
    .from("auditoria_alteracao")
    .select("id, tabela, registro_id, operacao, antes, depois, autor, alterado_em")
    .in("tabela", tabelasComplemento)
    .or(`depois->>centro_custo_id.eq.${centroCustoId},antes->>centro_custo_id.eq.${centroCustoId}`)
    .order("alterado_em", { ascending: false })
    .limit(limite);
  if (error) throw new ErroConsulta(error.code);
  return (data ?? []) as AlteracaoRegistro[];
}
