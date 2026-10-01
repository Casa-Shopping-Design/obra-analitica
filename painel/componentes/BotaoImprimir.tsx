"use client";

// O navegador abre a própria janela de impressão, onde o usuário escolhe a impressora ou salvar em PDF.
export function BotaoImprimir() {
  return (
    <button
      type="button"
      onClick={() => window.print()}
      className="inline-flex min-h-11 w-fit items-center rounded-lg bg-menu px-4 font-semibold text-menu-texto hover:bg-menu-ativo print:hidden"
    >
      Imprimir ou salvar em PDF
    </button>
  );
}
