import type { ReactNode } from "react";
import { MarcaApo } from "@/componentes/MarcaApo";

// Moldura das telas fora do painel: entrar, segundo fator, página não encontrada, erro e manutenção. Sem
// faixa de apresentação nem frase de efeito; quem chega aqui precisa do formulário ou do aviso e de uma
// linha dizendo o que fazer em seguida.
export function MolduraAcesso({ children, nota }: { children: ReactNode; nota?: string }) {
  return (
    <div className="flex min-h-screen flex-col">
      <header className="border-b border-borda px-4 py-4 md:px-12">
        <MarcaApo comAssinatura className="text-lg md:flex-row md:items-center md:gap-4" />
      </header>
      <main className="flex flex-1 justify-center px-4 py-12 md:py-20">
        <div className="flex w-full max-w-[400px] flex-col gap-7">
          {children}
          {nota && <p className="secao text-sm leading-relaxed text-suave">{nota}</p>}
        </div>
      </main>
    </div>
  );
}
