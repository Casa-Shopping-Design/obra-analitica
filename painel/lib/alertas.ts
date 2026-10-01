// Texto dos alertas de marts.alertas_obra (migration 0024). O banco decide o que disparou e manda os
// números; aqui só se escolhe a frase e a tela que explica o alerta.
import { formatarMeses as meses, formatarPercentual, formatarReal } from "./formatar";
import { numeroOuNulo } from "./consultas/resumo-origem";

export const tiposAlerta = [
  "repasse_atrasado",
  "estoque_apos_entrega",
  "estouro_orcamento",
  "inadimplencia_alta",
  "pago_a_frente_do_fisico",
] as const;

export type TipoAlerta = (typeof tiposAlerta)[number];

export type AlertaObra = {
  centro_custo_id: string;
  obra: string;
  tipo: TipoAlerta;
  valor: number | null;
  referencia: number | null;
};

export type TextoAlerta = { titulo: string; detalhe: string; tela: string };

export function textoAlerta(alerta: AlertaObra): TextoAlerta {
  const valor = alerta.valor;
  const referencia = alerta.referencia;
  switch (alerta.tipo) {
    case "repasse_atrasado":
      return {
        titulo: "Repasse do banco atrasado",
        detalhe: `${formatarReal(valor ?? 0)} de repasse já venceu e não entrou.`,
        tela: "vendas",
      };
    case "estoque_apos_entrega":
      if (valor === null) {
        return {
          titulo: "Estoque parado",
          detalhe: "Não houve venda líquida nos últimos 6 meses; no ritmo atual o estoque não acaba.",
          tela: "estoque",
        };
      }
      if (referencia === 0) {
        return {
          titulo: "Obra entregue com estoque",
          detalhe: `No ritmo dos últimos 6 meses, o que sobrou leva ${meses(valor)} para vender.`,
          tela: "estoque",
        };
      }
      return {
        titulo: "Estoque não acaba antes da entrega",
        detalhe: `No ritmo dos últimos 6 meses, o estoque leva ${meses(valor)} para vender; a entrega é daqui a ${meses(referencia ?? 0)}.`,
        tela: "estoque",
      };
    case "estouro_orcamento":
      return {
        titulo: "Custo acima do orçamento",
        detalhe:
          referencia && referencia > 0
            ? `O custo lançado passou o orçamento em ${formatarReal(valor ?? 0)} (${formatarPercentual((valor ?? 0) / referencia)} do orçado).`
            : `Há ${formatarReal(valor ?? 0)} de custo lançado sem orçamento cadastrado.`,
        tela: "",
      };
    case "inadimplencia_alta":
      return {
        titulo: "Inadimplência alta",
        detalhe: `${formatarReal(valor ?? 0)} vencidos dos compradores, ${formatarPercentual(referencia ?? 0)} da carteira direta.`,
        tela: "inadimplencia",
      };
    case "pago_a_frente_do_fisico":
      return {
        titulo: "Pago à frente do físico",
        detalhe: `O pago está ${Math.round((valor ?? 0) * 100)} pontos à frente da medição. Vale conferir adiantamento ou medição atrasada.`,
        tela: "execucao",
      };
  }
}

// A ordem da lista é a de tiposAlerta: primeiro o que já está custando caixa, depois o que ameaça o prazo.
export function ordenarAlertas(alertas: AlertaObra[]): AlertaObra[] {
  const posicao = (tipo: TipoAlerta) => tiposAlerta.indexOf(tipo);
  return [...alertas].sort((a, b) => posicao(a.tipo) - posicao(b.tipo) || a.obra.localeCompare(b.obra, "pt-BR"));
}

// Tipo que a tela não conhece (view mais nova que o painel) fica fora em vez de quebrar a lista.
export function lerAlertas(linhas: Record<string, unknown>[]): AlertaObra[] {
  return linhas
    .filter((linha) => tiposAlerta.some((tipo) => tipo === linha.tipo))
    .map((linha) => ({
      centro_custo_id: String(linha.centro_custo_id),
      obra: String(linha.obra),
      tipo: linha.tipo as TipoAlerta,
      valor: numeroOuNulo(linha.valor),
      referencia: numeroOuNulo(linha.referencia),
    }));
}
