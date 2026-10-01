import { CartaoValor } from "@/componentes/CartaoValor";
import type { CoberturaOrcamento, EstoqueObra } from "@/lib/consultas/estoque";
import { formatarData, formatarDecimal, formatarMeses, formatarPercentual, formatarReal } from "@/lib/formatar";

function textoRitmo(estoque: EstoqueObra): string {
  if (estoque.vendas_media_6m === null) return "Sem venda";
  return `${formatarDecimal(estoque.vendas_media_6m)} por mês`;
}

function textoPrazoEstoque(estoque: EstoqueObra): string {
  if (estoque.unidades_estoque === 0) return "Estoque vendido";
  if (estoque.meses_para_vender_estoque === null) return "Sem ritmo para projetar";
  return formatarMeses(estoque.meses_para_vender_estoque);
}

function notaEntrega(estoque: EstoqueObra): string | undefined {
  if (!estoque.data_entrega) return undefined;
  if (estoque.meses_ate_entrega === 0) return `Obra entregue em ${formatarData(estoque.data_entrega)}.`;
  return `Entrega em ${formatarData(estoque.data_entrega)}, daqui a ${formatarMeses(estoque.meses_ate_entrega ?? 0)}.`;
}

function textoCobertura(cobertura: CoberturaOrcamento | null): { valor: string; nota?: string } {
  if (!cobertura || cobertura.pct_cobertura === null) return { valor: "Sem orçamento" };
  const valor = formatarPercentual(cobertura.pct_cobertura);
  if (cobertura.unidades_para_cobrir === null) return { valor, nota: "Sem contrato ativo para calcular o ticket médio." };
  if (cobertura.unidades_para_cobrir === 0) return { valor, nota: "Os contratos ativos já cobrem o custo orçado." };
  const prazo =
    cobertura.meses_para_cobrir === null
      ? "sem ritmo de venda para projetar o prazo"
      : `cerca de ${formatarMeses(cobertura.meses_para_cobrir)} no ritmo atual`;
  return { valor, nota: `Faltam ${cobertura.unidades_para_cobrir} vendas ao ticket médio, ${prazo}.` };
}

// Os quatro números do estoque, na tela de estoque e no relatório, que tem largura de folha e fica em duas colunas.
export function ResumoEstoque({
  estoque,
  cobertura,
  estreito = false,
}: {
  estoque: EstoqueObra;
  cobertura: CoberturaOrcamento | null;
  estreito?: boolean;
}) {
  const coberturaTexto = textoCobertura(cobertura);
  const colunas = estreito ? "sm:grid-cols-2" : "sm:grid-cols-2 xl:grid-cols-4";
  return (
    <section aria-label="Resumo do estoque" className={`grid grid-cols-1 gap-4 break-inside-avoid ${colunas}`}>
      <CartaoValor
        rotulo="Unidades em estoque"
        chave="unidades_estoque"
        valor={String(estoque.unidades_estoque)}
        nota={`${formatarReal(estoque.valor_estoque)} a preço de hoje.`}
      />
      <CartaoValor
        rotulo="Ritmo de vendas"
        chave="ritmo_vendas"
        valor={textoRitmo(estoque)}
        nota={`${estoque.unidades_vendidas} unidades vendidas até hoje.`}
      />
      <CartaoValor
        rotulo="Tempo para vender o estoque"
        chave="meses_para_vender_estoque"
        valor={textoPrazoEstoque(estoque)}
        nota={notaEntrega(estoque)}
      />
      <CartaoValor rotulo="Cobertura do orçamento" chave="cobertura_orcamento" valor={coberturaTexto.valor} nota={coberturaTexto.nota} />
    </section>
  );
}
