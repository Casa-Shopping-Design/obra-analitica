import { CarimboCarga } from "@/componentes/CarimboCarga";
import { MenuLateral } from "@/componentes/MenuLateral";
import { exigirIdentidade } from "@/lib/consultas/identidade";

// O proxy já redireciona quem não entrou; a checagem se repete aqui porque proxy sozinho não protege rota.
export default async function LayoutPainel({ children }: LayoutProps<"/">) {
  const identidade = await exigirIdentidade();

  return (
    <div className="flex min-h-screen flex-col md:flex-row">
      <MenuLateral perfil={identidade.perfil} construtora={identidade.construtora} />
      <div className="flex min-w-0 flex-1 flex-col">
        <main className="flex flex-1 flex-col gap-7 px-4 py-6 md:px-12 md:py-9">{children}</main>
        <footer className="border-t border-borda px-4 py-4 md:px-12">
          <CarimboCarga />
        </footer>
      </div>
    </div>
  );
}
