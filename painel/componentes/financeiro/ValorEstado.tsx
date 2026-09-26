import type { EstadoValor } from "@/componentes/financeiro/montar-dre";
import { formatarReal } from "@/lib/formatar";

// Indisponível mostra um hífen com o motivo (visível ou só para leitor de tela); ausente mostra "Não informado". Nenhum dos dois vira R$ 0,00.
export function ValorEstado({
  estado,
  mostrarMotivo = true,
  textoAusente = "Não informado",
}: {
  estado: EstadoValor;
  mostrarMotivo?: boolean;
  textoAusente?: string;
}) {
  if (estado.tipo === "valor") return <>{formatarReal(estado.valor)}</>;
  if (estado.tipo === "ausente") return <span className="font-normal text-suave">{textoAusente}</span>;
  return (
    <span className="inline-flex flex-col gap-0.5">
      <span aria-hidden="true" title={estado.motivo}>
        -
      </span>
      <span className={mostrarMotivo ? "text-xs leading-snug font-normal text-suave" : "sr-only"}>
        Indisponível. {estado.motivo}
      </span>
    </span>
  );
}
