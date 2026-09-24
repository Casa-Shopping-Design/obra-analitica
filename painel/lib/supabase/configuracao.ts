// URL e chave publicável: podem ir ao navegador, o acesso aos dados é decidido pelo RLS.
// A service_role nunca entra no painel.
export function lerConfiguracaoSupabase(): { url: string; chavePublica: string } {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const chavePublica = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !chavePublica) {
    throw new Error("NEXT_PUBLIC_SUPABASE_URL e NEXT_PUBLIC_SUPABASE_ANON_KEY precisam estar definidas");
  }
  return { url, chavePublica };
}
