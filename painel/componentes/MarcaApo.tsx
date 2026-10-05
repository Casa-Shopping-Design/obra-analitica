// Cores fixas do logo, fora dos tokens: a marca não acompanha mudança na paleta de entrada e repasse.
const blocos = [
  { letra: "A", fundo: "bg-[#4f7a19]" },
  { letra: "P", fundo: "bg-[#0f7fa8]" },
  { letra: "O", fundo: "bg-[#84b625]" },
];

// Tamanho e espaçamento vêm de quem usa: o menu pede a marca menor que a tela de entrar.
// Os blocos medem em em e crescem com a fonte da classe recebida. As letras são desenho e ficam fora do
// leitor de tela, que lê só "APO"; assim o branco sobre o verde claro, de contraste baixo, não atrapalha a leitura.
export function MarcaApo({ comAssinatura = false, className = "" }: { comAssinatura?: boolean; className?: string }) {
  return (
    <div className={`flex flex-col gap-2 ${className}`}>
      <p className="flex gap-[0.12em] font-serif leading-none font-semibold">
        <span className="sr-only">APO</span>
        {blocos.map(({ letra, fundo }) => (
          <span
            key={letra}
            aria-hidden="true"
            className={`flex size-[1.5em] items-center justify-center rounded-[0.18em] text-white ${fundo}`}
          >
            {letra}
          </span>
        ))}
      </p>
      {comAssinatura && <p className="text-sm text-menu-suave">Agente da Governança Financeira</p>}
    </div>
  );
}
