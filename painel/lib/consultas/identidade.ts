import "server-only";
import { redirect } from "next/navigation";
import { criarClienteServidor } from "@/lib/supabase/servidor";

export type Identidade = { usuarioId: string; perfil: string; construtora: string };

const nomesPerfil: Record<string, string> = {
  diretor: "Diretor",
  financeiro: "Financeiro",
  comercial: "Comercial",
  gerente_obra: "Gerente de obra",
  leitura: "Leitura",
};

// getUser valida o token no servidor do Auth; getSession só leria o cookie.
export async function exigirIdentidade(): Promise<Identidade> {
  const supabase = await criarClienteServidor();
  const { data: dadosUsuario } = await supabase.auth.getUser();
  if (!dadosUsuario.user) redirect("/entrar");

  const { data: vinculo } = await supabase
    .schema("app")
    .from("usuario_tenant")
    .select("perfil, tenant:tenant_id(razao_social)")
    .limit(1)
    .maybeSingle<{ perfil: string; tenant: { razao_social: string } | null }>();

  return {
    usuarioId: dadosUsuario.user.id,
    perfil: vinculo ? (nomesPerfil[vinculo.perfil] ?? vinculo.perfil) : "Sem perfil",
    construtora: vinculo?.tenant?.razao_social ?? "",
  };
}
