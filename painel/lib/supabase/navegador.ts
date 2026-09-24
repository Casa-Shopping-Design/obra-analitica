import { createBrowserClient } from "@supabase/ssr";
import { lerConfiguracaoSupabase } from "./configuracao";

export function criarClienteNavegador() {
  const { url, chavePublica } = lerConfiguracaoSupabase();
  return createBrowserClient(url, chavePublica);
}
