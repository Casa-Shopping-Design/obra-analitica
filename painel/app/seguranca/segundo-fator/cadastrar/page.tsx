import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { CadastroSegundoFator } from "@/componentes/CadastroSegundoFator";
import { caminhosAcesso, decidirDestino } from "@/lib/supabase/nivel-acesso";
import { criarClienteServidor } from "@/lib/supabase/servidor";
import { lerNivelSessao } from "@/lib/supabase/sessao";

export const metadata: Metadata = { title: "Cadastrar segundo fator" };

export default async function PaginaCadastrarSegundoFator() {
  const supabase = await criarClienteServidor();
  const destino = decidirDestino({ ...(await lerNivelSessao(supabase)), caminho: caminhosAcesso.cadastrar });
  if (destino !== "liberado") redirect(caminhosAcesso[destino]);

  return (
    <>
      <div className="flex flex-col gap-2">
        <h1 className="font-serif text-3xl font-semibold">Cadastrar aplicativo autenticador</h1>
        <p className="text-[15px] leading-relaxed text-suave">
          O seu perfil exige um segundo fator. Instale um aplicativo autenticador no celular (Google Authenticator,
          Microsoft Authenticator ou outro que gere códigos de seis dígitos) e siga os passos abaixo.
        </p>
      </div>
      <CadastroSegundoFator />
    </>
  );
}
