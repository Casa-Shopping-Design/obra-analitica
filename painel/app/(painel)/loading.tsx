// Aparece assim que a navegação começa, enquanto as consultas da tela rodam no servidor. O menu continua
// na tela; o mapa de unidades tem o seu próprio, no formato da grade.
export default function CarregandoTela() {
  return (
    <div aria-busy="true" className="flex flex-col gap-7">
      <p role="status" className="sr-only">
        Carregando os números da tela.
      </p>
      <div className="h-10 w-72 max-w-full motion-safe:animate-pulse rounded-lg bg-trilho" />
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {Array.from({ length: 4 }, (_, posicao) => (
          <div key={posicao} className="h-24 motion-safe:animate-pulse rounded-sm bg-trilho" />
        ))}
      </div>
      <div className="h-72 motion-safe:animate-pulse rounded-sm bg-trilho" />
    </div>
  );
}
