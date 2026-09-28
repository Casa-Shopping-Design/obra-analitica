import { buscarUltimaCarga } from "@/lib/consultas/carga";
import { avaliarIdadeCarga, formatarDataHoraCarga } from "@/lib/idade-carga";

// Toda tela do painel passa por aqui: número nenhum aparece sem a data da carga que o produziu.
export async function CarimboCarga() {
  let ultimaCargaEm: string | null;
  try {
    ultimaCargaEm = await buscarUltimaCarga();
  } catch {
    return (
      <p className="text-sm text-alerta" role="status">
        Atenção: não foi possível conferir a data da última carga. Recarregue a página em alguns minutos.
      </p>
    );
  }

  if (!ultimaCargaEm) {
    return (
      <p className="text-sm text-alerta" role="status">
        Atenção: nenhuma carga de dados foi concluída ainda. Os números aparecem depois da primeira carga.
      </p>
    );
  }

  const dataHora = formatarDataHoraCarga(ultimaCargaEm);
  if (avaliarIdadeCarga(ultimaCargaEm, new Date()).atrasada) {
    return (
      <p className="text-sm text-alerta" role="status">
        Atenção: a carga de hoje não rodou. Os números são de {dataHora}.
      </p>
    );
  }

  return <p className="text-sm text-suave">Dados carregados em {dataHora}</p>;
}
