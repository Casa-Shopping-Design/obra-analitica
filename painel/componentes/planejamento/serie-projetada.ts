// Série do gráfico do fluxo projetado. Mês passado mostra o total como realizado; do mês de referência
// em diante o total é realizado mais previsto e aparece hachurado. Só escolhe a coluna, não soma nada.
import type { LinhaFluxoProjetado } from "../../lib/consultas/fluxo";

export type PontoFluxoProjetado = {
  competencia: string;
  entradasRealizadas: number | null;
  entradasPrevistas: number | null;
  saidasRealizadas: number | null;
  saidasPrevistas: number | null;
  caixa: number;
  caixaConservador: number;
};

export function montarSerieProjetada(
  linhas: readonly Pick<
    LinhaFluxoProjetado,
    "competencia" | "eh_passado" | "total_entradas" | "total_saidas" | "caixa_gerado_acumulado" | "caixa_gerado_acumulado_conservador"
  >[],
): PontoFluxoProjetado[] {
  return linhas.map((linha) => ({
    competencia: linha.competencia.slice(0, 10),
    entradasRealizadas: linha.eh_passado ? linha.total_entradas : null,
    entradasPrevistas: linha.eh_passado ? null : linha.total_entradas,
    saidasRealizadas: linha.eh_passado ? linha.total_saidas : null,
    saidasPrevistas: linha.eh_passado ? null : linha.total_saidas,
    caixa: linha.caixa_gerado_acumulado,
    caixaConservador: linha.caixa_gerado_acumulado_conservador,
  }));
}
