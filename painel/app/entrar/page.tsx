import type { Metadata } from "next";
import { FormularioEntrar } from "@/componentes/FormularioEntrar";
import { MarcaApo } from "@/componentes/MarcaApo";

export const metadata: Metadata = { title: "Entrar" };

export default function PaginaEntrar() {
  return (
    <div className="flex min-h-screen flex-col md:flex-row">
      <section
        aria-label="Apresentação"
        className="flex flex-col justify-between gap-10 bg-menu px-6 py-10 text-menu-texto md:w-[560px] md:shrink-0 md:px-14 md:py-16"
      >
        <MarcaApo comAssinatura className="text-2xl" />
        <div className="flex flex-col gap-5">
          <p className="font-serif text-3xl leading-tight font-semibold md:text-4xl">
            Cada obra, o caixa e o estoque numa tela só.
          </p>
          <p className="leading-relaxed text-menu-suave">
            Os números saem do ERP da construtora toda madrugada. Você vê só as obras liberadas para o seu perfil.
          </p>
        </div>
      </section>

      <main className="flex flex-1 items-center justify-center px-4 py-12">
        <div className="flex w-full max-w-[400px] flex-col gap-7">
          <div className="flex flex-col gap-2">
            <h1 className="font-serif text-3xl font-semibold">Entrar</h1>
            <p className="text-[15px] text-suave">Use o e-mail do convite que você recebeu.</p>
          </div>
          <FormularioEntrar />
          <p className="border-t border-borda pt-5 text-sm leading-relaxed text-suave">
            Não tem acesso? Peça um convite ao administrador da sua construtora. Não existe cadastro aberto.
          </p>
        </div>
      </main>
    </div>
  );
}
