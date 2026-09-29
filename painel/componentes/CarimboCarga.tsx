import { buscarUltimaCarga } from "@/lib/consultas/carga";
import { avaliarIdadeCarga, formatarDataHoraCarga } from "@/lib/idade-carga";
import { mensagens } from "@/lib/mensagens";

// Ligado só no projeto da demo, por variável de ambiente pública: o piloto não mostra o aviso.
const mostrarAvisoDemo = process.env.NEXT_PUBLIC_MOSTRAR_AVISO_DEMO === "1";

function AvisoDemo() {
  if (!mostrarAvisoDemo) return null;
  return (
    <p className="text-sm text-alerta" role="note">
      {mensagens.carga.avisoDemo}
    </p>
  );
}

// Toda tela do painel passa por aqui: número nenhum aparece sem a data da carga que o produziu.
export async function CarimboCarga() {
  let ultimaCargaEm: string | null;
  try {
    ultimaCargaEm = await buscarUltimaCarga();
  } catch {
    return (
      <div className="flex flex-col gap-1">
        <p className="text-sm text-alerta" role="status">
          {mensagens.carga.semConferencia}
        </p>
        <AvisoDemo />
      </div>
    );
  }

  if (!ultimaCargaEm) {
    return (
      <div className="flex flex-col gap-1">
        <p className="text-sm text-alerta" role="status">
          {mensagens.carga.semCarga}
        </p>
        <AvisoDemo />
      </div>
    );
  }

  const dataHora = formatarDataHoraCarga(ultimaCargaEm);
  const atrasada = avaliarIdadeCarga(ultimaCargaEm, new Date()).atrasada;
  return (
    <div className="flex flex-col gap-1">
      {atrasada ? (
        <p className="text-sm text-alerta" role="status">
          {mensagens.carga.atrasada} {mensagens.carga.numerosDe} {dataHora}.
        </p>
      ) : (
        <p className="text-sm text-suave">
          {mensagens.carga.carregadaEm} {dataHora}
        </p>
      )}
      <AvisoDemo />
    </div>
  );
}
