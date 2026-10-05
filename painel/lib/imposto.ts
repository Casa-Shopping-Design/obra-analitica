// Leitura e textos da gestão de imposto (marts.imposto_obra, migration 0034). Sem acesso ao banco e sem conta:
// cada imposto, a diferença e a soma chegam prontos da view.
import { numeroOuNulo, numeroOuZero } from "./consultas/resumo-origem";
import { formatarData } from "./formatar";

export type ImpostoObra = {
  obra: string;
  competencia: string;
  aliquota: number;
  aliquotaVigenciaInicio: string;
  aliquotaInformadaEm: string;
  vgvTotal: number;
  receitaApropriada: number;
  receitaAApropriar: number;
  vgvEstoque: number;
  recebidoAcumulado: number;
  impostoReceitaApropriada: number;
  impostoRecebimento: number;
  impostoDiferido: number;
  impostoVgvEstoque: number;
  impostoReceitaAApropriar: number;
  impostoVgvTotal: number;
  impostoARealizar: number;
  impostoViabilidade: number | null;
};

export const colunasImposto =
  "obra, competencia, aliquota, aliquota_vigencia_inicio, aliquota_informada_em, vgv_total, receita_apropriada, receita_a_apropriar, vgv_estoque, recebido_acumulado, imposto_receita_apropriada, imposto_recebimento, imposto_diferido, imposto_vgv_estoque, imposto_receita_a_apropriar, imposto_vgv_total, imposto_a_realizar, imposto_viabilidade";

export function lerImpostoObra(linha: Record<string, unknown>): ImpostoObra {
  return {
    obra: String(linha.obra),
    competencia: String(linha.competencia),
    aliquota: numeroOuZero(linha.aliquota),
    aliquotaVigenciaInicio: String(linha.aliquota_vigencia_inicio),
    aliquotaInformadaEm: String(linha.aliquota_informada_em),
    vgvTotal: numeroOuZero(linha.vgv_total),
    receitaApropriada: numeroOuZero(linha.receita_apropriada),
    receitaAApropriar: numeroOuZero(linha.receita_a_apropriar),
    vgvEstoque: numeroOuZero(linha.vgv_estoque),
    recebidoAcumulado: numeroOuZero(linha.recebido_acumulado),
    impostoReceitaApropriada: numeroOuZero(linha.imposto_receita_apropriada),
    impostoRecebimento: numeroOuZero(linha.imposto_recebimento),
    impostoDiferido: numeroOuZero(linha.imposto_diferido),
    impostoVgvEstoque: numeroOuZero(linha.imposto_vgv_estoque),
    impostoReceitaAApropriar: numeroOuZero(linha.imposto_receita_a_apropriar),
    impostoVgvTotal: numeroOuZero(linha.imposto_vgv_total),
    impostoARealizar: numeroOuZero(linha.imposto_a_realizar),
    impostoViabilidade: numeroOuNulo(linha.imposto_viabilidade),
  };
}

// A alíquota vem com até seis casas no banco; uma casa só, como o resto do painel, mostraria 6,3% no lugar de 6,32%.
const formatoAliquota = new Intl.NumberFormat("pt-BR", {
  style: "percent",
  minimumFractionDigits: 2,
  maximumFractionDigits: 4,
});

export function formatarAliquota(fracao: number): string {
  return formatoAliquota.format(fracao);
}

export const avisoEstimativa = "Valores estimados pela alíquota informada. Não substituem a apuração do contador.";

export function notaImposto(imposto: ImpostoObra): string {
  return `Alíquota de ${formatarAliquota(imposto.aliquota)}, vigente desde ${formatarData(imposto.aliquotaVigenciaInicio)} e informada em ${formatarData(imposto.aliquotaInformadaEm)}.`;
}
