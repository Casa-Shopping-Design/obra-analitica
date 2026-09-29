import { redirect } from "next/navigation";
import { CarimboCarga } from "@/componentes/CarimboCarga";
import { MenuLateral } from "@/componentes/MenuLateral";
import { exigirIdentidade } from "@/lib/consultas/identidade";
import { caminhosAcesso, decidirDestino } from "@/lib/supabase/nivel-acesso";
import { criarClienteServidor } from "@/lib/supabase/servidor";
import { lerNivelSessao } from "@/lib/supabase/sessao";

// getUser (em exigirIdentidade) valida no Auth; getClaims traz perfil e aal para o segundo fator.
async function exigirSegundoFator() {
  const supabase = await criarClienteServidor();
  const destino = decidirDestino({ ...(await lerNivelSessao(supabase)), caminho: "/" });
  if (destino !== "liberado") redirect(caminhosAcesso[destino]);
}

// O proxy já redireciona quem não entrou ou não passou pelo segundo fator; a checagem se repete aqui
// porque proxy sozinho não protege rota.
export default async function LayoutPainel({ children }: LayoutProps<"/">) {
  const identidade = await exigirIdentidade();
  await exigirSegundoFator();

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
