import { estadoDoValor } from "@/componentes/financeiro/montar-dre";
import { ValorEstado } from "@/componentes/financeiro/ValorEstado";
import { formatarPercentual } from "@/lib/formatar";

// Valor em real; nulo vira "Não informado" (ou o texto dado), nunca R$ 0,00.
export function Valor({ valor, ausente }: { valor: number | null | undefined; ausente?: string }) {
  return <ValorEstado estado={estadoDoValor(valor ?? null)} textoAusente={ausente} />;
}

export function Percentual({ fracao, ausente = "Não informado" }: { fracao: number | null | undefined; ausente?: string }) {
  if (fracao === null || fracao === undefined) return <span className="font-normal text-suave">{ausente}</span>;
  return <>{formatarPercentual(fracao)}</>;
}

export function Inteiro({ valor, ausente = "Não informado" }: { valor: number | null | undefined; ausente?: string }) {
  if (valor === null || valor === undefined) return <span className="font-normal text-suave">{ausente}</span>;
  return <>{new Intl.NumberFormat("pt-BR").format(valor)}</>;
}
