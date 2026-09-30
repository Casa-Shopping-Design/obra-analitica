import Link from "next/link";
import { textoAlerta, type AlertaObra } from "@/lib/alertas";
import { mensagens } from "@/lib/mensagens";

// Na visão geral cada alerta leva o nome da obra; na obra e no relatório, não. Relatório impresso não tem link.
export function ListaAlertas({
  alertas,
  mostrarObra,
  comLinks = true,
}: {
  alertas: AlertaObra[];
  mostrarObra: boolean;
  comLinks?: boolean;
}) {
  return (
    <ul className="flex flex-col divide-y divide-borda">
      {alertas.map((alerta) => {
        const texto = textoAlerta(alerta);
        const destino = `/obras/${alerta.centro_custo_id}${texto.tela ? `/${texto.tela}` : ""}`;
        return (
          <li
            key={`${alerta.centro_custo_id}-${alerta.tipo}`}
            className="flex flex-col gap-1 py-3 first:pt-0 last:pb-0 sm:flex-row sm:items-start sm:justify-between sm:gap-6"
          >
            <div className="flex min-w-0 gap-3">
              <span aria-hidden="true" className="mt-2 size-2 shrink-0 rounded-full bg-atencao" />
              <div className="flex min-w-0 flex-col gap-0.5">
                <p className="font-semibold">
                  {mostrarObra && <span className="text-suave">{alerta.obra}: </span>}
                  {texto.titulo}
                </p>
                <p className="text-sm text-suave">{texto.detalhe}</p>
              </div>
            </div>
            {comLinks && (
              <Link
                href={destino}
                className="ml-5 w-fit shrink-0 text-sm font-semibold underline underline-offset-4 hover:text-menu sm:ml-0"
              >
                Ver detalhes
                <span className="sr-only">
                  {" "}
                  de {texto.titulo.toLowerCase()} em {alerta.obra}
                </span>
              </Link>
            )}
          </li>
        );
      })}
    </ul>
  );
}

// Uma coluna por obra, na ordem de gravidade que a lista já traz; o Map guarda a ordem de chegada.
function AlertasPorObra({ alertas, comLinks }: { alertas: AlertaObra[]; comLinks: boolean }) {
  const grupos = new Map<string, AlertaObra[]>();
  for (const alerta of alertas) {
    grupos.set(alerta.centro_custo_id, [...(grupos.get(alerta.centro_custo_id) ?? []), alerta]);
  }
  return (
    <div className="grid grid-cols-1 gap-6 lg:grid-cols-2 2xl:grid-cols-3">
      {[...grupos.values()].map((grupo) => (
        <div key={grupo[0].centro_custo_id} className="flex flex-col gap-3">
          <h3 className="font-serif text-lg font-semibold">
            {comLinks ? (
              <Link href={`/obras/${grupo[0].centro_custo_id}`} className="underline underline-offset-4 hover:text-menu">
                {grupo[0].obra}
              </Link>
            ) : (
              grupo[0].obra
            )}
          </h3>
          <ListaAlertas alertas={grupo} mostrarObra={false} comLinks={comLinks} />
        </div>
      ))}
    </div>
  );
}

// Seção pronta para a visão geral e a obra: título, contagem e a lista, ou a frase de que está tudo em ordem.
export function SecaoAlertas({
  alertas,
  mostrarObra,
  comLinks = true,
}: {
  alertas: AlertaObra[] | null;
  mostrarObra: boolean;
  comLinks?: boolean;
}) {
  return (
    <section aria-labelledby="titulo-alertas" className="flex flex-col gap-4 rounded-xl border border-borda bg-superficie p-5">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 id="titulo-alertas" className="font-serif text-2xl font-semibold">
          Pede atenção
        </h2>
        {alertas && alertas.length > 0 && (
          <p className="text-sm text-suave">
            {alertas.length === 1 ? "1 alerta" : `${alertas.length} alertas`}
          </p>
        )}
      </div>
      {alertas === null && (
        <p role="alert" className="text-alerta">
          {mensagens.alertas.indisponivel}
        </p>
      )}
      {alertas?.length === 0 && <p className="text-suave">{mensagens.alertas.nenhum}</p>}
      {alertas && alertas.length > 0 &&
        (mostrarObra ? (
          <AlertasPorObra alertas={alertas} comLinks={comLinks} />
        ) : (
          <ListaAlertas alertas={alertas} mostrarObra={false} comLinks={comLinks} />
        ))}
    </section>
  );
}
