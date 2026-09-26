import { mensagens } from "@/lib/mensagens";

// Caixa de aviso com título; o ícone e o texto dizem o tipo, a cor só reforça.
export function Aviso({ titulo, children }: { titulo: string; children: React.ReactNode }) {
  return (
    <section
      aria-label={titulo}
      className="flex flex-col gap-1.5 rounded-xl border-2 border-atencao bg-superficie p-4 text-sm leading-relaxed"
    >
      <p className="font-semibold text-atencao">
        <span aria-hidden="true">! </span>
        {titulo}
      </p>
      <div className="text-texto">{children}</div>
    </section>
  );
}

export function ErroBloco() {
  return (
    <p role="alert" className="text-alerta">
      {mensagens.bloco.indisponivel}
    </p>
  );
}

// Moldura de cada bloco da tela, com título h2 e uma linha de contexto (período e origem do número).
export function Bloco({
  id,
  titulo,
  contexto,
  children,
}: {
  id: string;
  titulo: string;
  contexto?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <section
      id={id}
      aria-labelledby={`titulo-${id}`}
      className="flex min-w-0 scroll-mt-4 flex-col gap-4 rounded-xl border border-borda bg-superficie p-4 md:p-5"
    >
      <div className="flex flex-col gap-1">
        <h2 id={`titulo-${id}`} className="font-serif text-2xl font-semibold">
          {titulo}
        </h2>
        {contexto && <p className="text-sm text-suave">{contexto}</p>}
      </div>
      {children}
    </section>
  );
}
