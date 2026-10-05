// Tamanho e espaçamento vêm de quem usa: o menu pede a marca menor que a tela de entrar.
export function MarcaApo({ comAssinatura = false, className = "" }: { comAssinatura?: boolean; className?: string }) {
  return (
    <div className={`flex flex-col gap-1 ${className}`}>
      <p className="font-serif font-semibold tracking-wide">APO</p>
      {comAssinatura && <p className="text-sm text-menu-suave">Agente da Governança Financeira</p>}
    </div>
  );
}
