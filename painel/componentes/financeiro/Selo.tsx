// Selo com ícone e texto: a cor nunca carrega o significado sozinha.
const estilos = {
  parcial: { classe: "border-atencao text-atencao", icone: "!" },
  alerta: { classe: "border-alerta text-alerta", icone: "!" },
  informativo: { classe: "border-borda text-suave", icone: "i" },
} as const;

export function Selo({ tipo, children }: { tipo: keyof typeof estilos; children: React.ReactNode }) {
  const estilo = estilos[tipo];
  return (
    <span
      className={`inline-flex w-fit items-center gap-1 rounded-full border px-2 py-0.5 text-xs font-semibold ${estilo.classe}`}
    >
      <span aria-hidden="true">{estilo.icone}</span>
      {children}
    </span>
  );
}
