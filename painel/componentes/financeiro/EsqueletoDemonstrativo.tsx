// Esqueleto no lugar do conteúdo enquanto as consultas respondem; nunca tela em branco.
export function EsqueletoDemonstrativo({ titulo, cartoes = 4 }: { titulo: string; cartoes?: number }) {
  return (
    <div aria-busy="true" className="flex flex-col gap-6">
      <p className="sr-only">Carregando {titulo}.</p>
      <div className="h-10 w-64 max-w-full animate-pulse rounded-lg bg-trilho" />
      <div className="h-5 w-96 max-w-full animate-pulse rounded bg-trilho" />
      <div className="h-24 w-full animate-pulse rounded-xl bg-trilho" />
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {Array.from({ length: cartoes }, (_, posicao) => (
          <div key={posicao} className="h-28 animate-pulse rounded-xl bg-trilho" />
        ))}
      </div>
      <div className="h-72 w-full animate-pulse rounded-xl bg-trilho" />
    </div>
  );
}
