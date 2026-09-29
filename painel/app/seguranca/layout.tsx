import { redirect } from "next/navigation";
import { caminhosAcesso } from "@/lib/supabase/nivel-acesso";
import { criarClienteServidor } from "@/lib/supabase/servidor";

// Telas de segurança ficam fora do grupo (painel) para serem alcançáveis em aal1, mas exigem usuário entrado.
export default async function LayoutSeguranca({ children }: LayoutProps<"/seguranca">) {
  const supabase = await criarClienteServidor();
  const { data: dadosUsuario } = await supabase.auth.getUser();
  if (!dadosUsuario.user) redirect(caminhosAcesso.entrar);

  return (
    <div className="flex min-h-screen flex-col md:flex-row">
      <section
        aria-label="Apresentação"
        className="flex flex-col justify-between gap-10 bg-menu px-6 py-10 text-menu-texto md:w-[560px] md:shrink-0 md:px-14 md:py-16"
      >
        <p className="font-serif text-2xl font-semibold">obra analítica</p>
        <div className="flex flex-col gap-5">
          <p className="font-serif text-3xl leading-tight font-semibold md:text-4xl">
            Uma senha roubada não pode abrir o caixa da construtora.
          </p>
          <p className="leading-relaxed text-menu-suave">
            Diretor e financeiro confirmam a entrada com um código do aplicativo autenticador do celular.
          </p>
        </div>
      </section>

      <main className="flex flex-1 items-center justify-center px-4 py-12">
        <div className="flex w-full max-w-[400px] flex-col gap-7">
          {children}
          <form action="/sair" method="post" className="border-t border-borda pt-5">
            <button type="submit" className="cursor-pointer text-sm text-suave underline underline-offset-4 hover:text-texto">
              Sair desta conta
            </button>
          </form>
        </div>
      </main>
    </div>
  );
}
