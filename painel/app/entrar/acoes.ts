"use server";

import { redirect } from "next/navigation";
import { mensagens } from "@/lib/mensagens";
import { criarClienteServidor } from "@/lib/supabase/servidor";

export type EstadoEntrar = { erro: string | null; email: string };

export async function entrar(_estadoAnterior: EstadoEntrar, formulario: FormData): Promise<EstadoEntrar> {
  const email = formulario.get("email");
  const senha = formulario.get("senha");
  if (typeof email !== "string" || typeof senha !== "string" || !email.trim() || !senha) {
    return { erro: mensagens.entrar.camposVazios, email: typeof email === "string" ? email : "" };
  }

  const supabase = await criarClienteServidor();
  const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password: senha });
  if (error) {
    const erro =
      error.code === "invalid_credentials"
        ? mensagens.entrar.credenciaisInvalidas
        : error.status === 429
          ? mensagens.entrar.muitasTentativas
          : mensagens.entrar.indisponivel;
    return { erro, email };
  }

  redirect("/");
}
