import { Suspense } from "react";
import { buscarSituacaoCarga, type SituacaoCarga } from "@/lib/consultas/referencia";
import { formatarData } from "@/lib/formatar";
import { mensagens } from "@/lib/mensagens";
import { horaEmSaoPaulo } from "@/lib/periodo";

async function lerSituacao(): Promise<SituacaoCarga | null> {
  try {
    return await buscarSituacaoCarga();
  } catch {
    return null;
  }
}

// Sem registro de carga (ou sem resposta do banco), fica o texto da demo.
async function TextoCarga() {
  const situacao = await lerSituacao();
  const ultimaCarga = situacao?.ultima_carga_em;
  if (!situacao || !ultimaCarga) return <p className="text-sm text-suave">{mensagens.carga.semRegistro}</p>;

  const quando = `${formatarData(ultimaCarga)} às ${horaEmSaoPaulo(ultimaCarga)}`;
  return (
    <p className={`text-sm ${situacao.desatualizada ? "text-alerta" : "text-suave"}`}>
      {situacao.desatualizada ? (
        <>
          <span aria-hidden="true">! </span>A carga de hoje não rodou. Os números são de {quando}.
        </>
      ) : (
        <>Dados carregados em {quando}.</>
      )}{" "}
      Data de referência {formatarData(situacao.data_referencia)}.
    </p>
  );
}

// O Suspense deixa o rodapé esperar a consulta sem segurar o resto do layout.
export function CarimboCarga() {
  return (
    <Suspense fallback={<p className="h-5 w-72 max-w-full animate-pulse rounded bg-trilho" aria-hidden="true" />}>
      <TextoCarga />
    </Suspense>
  );
}
