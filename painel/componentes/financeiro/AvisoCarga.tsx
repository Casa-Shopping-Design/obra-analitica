import type { Referencia } from "@/lib/consultas/referencia";
import { formatarData } from "@/lib/formatar";
import { mensagens } from "@/lib/mensagens";
import { horaEmSaoPaulo } from "@/lib/periodo";

// Topo de cada tela: a data de referência dos números e a da última carga, com o aviso de carga atrasada.
export function AvisoCarga({ referencia }: { referencia: Referencia }) {
  const { situacao, dataReferencia, doBanco } = referencia;
  const ultimaCarga = situacao?.ultima_carga_em ?? null;

  return (
    <div className="flex flex-col gap-2">
      <p className="text-sm text-suave">
        Data de referência: <strong className="font-semibold text-texto">{formatarData(dataReferencia)}</strong>
        {!doBanco && <> ({mensagens.carga.referenciaLocal})</>}
        {ultimaCarga && !situacao?.desatualizada && (
          <>
            {" "}
            · Dados carregados em {formatarData(ultimaCarga)} às {horaEmSaoPaulo(ultimaCarga)}
          </>
        )}
      </p>
      {situacao?.desatualizada && ultimaCarga && (
        <p role="alert" className="rounded-lg border border-alerta bg-superficie px-3 py-2 text-sm text-alerta">
          <span aria-hidden="true">! </span>A carga de hoje não rodou. Os números são de{" "}
          {formatarData(ultimaCarga).slice(0, 5)} às {horaEmSaoPaulo(ultimaCarga)}.
        </p>
      )}
      {situacao === null && !doBanco && <p className="text-sm text-suave">{mensagens.carga.semConsulta}</p>}
      {situacao && !ultimaCarga && <p className="text-sm text-suave">{mensagens.carga.semRegistro}</p>}
    </div>
  );
}
