export default function CarregandoMapaUnidades() {
  return (
    <div aria-busy="true" className="flex flex-col gap-4">
      <p className="sr-only">Carregando o mapa de unidades.</p>
      <div className="h-10 w-72 max-w-full animate-pulse rounded-lg bg-trilho" />
      <div className="h-5 w-96 max-w-full animate-pulse rounded bg-trilho" />
      <div className="grid grid-cols-1 gap-8 xl:grid-cols-[minmax(0,56rem)_minmax(20rem,26rem)]">
        <div className="grid grid-cols-5 gap-1">
          {Array.from({ length: 30 }, (_, posicao) => (
            <div key={posicao} className="h-12 animate-pulse rounded-md bg-trilho" />
          ))}
        </div>
        <div className="h-64 animate-pulse rounded-xl bg-trilho" />
      </div>
    </div>
  );
}
