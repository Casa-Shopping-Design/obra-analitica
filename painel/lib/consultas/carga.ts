import "server-only";
import { createClient } from "@supabase/supabase-js";
import { lerConfiguracaoSupabase } from "@/lib/supabase/configuracao";
import { criarClienteServidor } from "@/lib/supabase/servidor";

export class ErroConsultaCarga extends Error {}

// Última carga do tenant de quem está logado; o RLS escolhe o tenant, a consulta não repete o filtro.
export async function buscarUltimaCarga(): Promise<string | null> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("ultima_carga")
    .select("ultima_carga_em")
    .maybeSingle<{ ultima_carga_em: string }>();
  if (error) throw new ErroConsultaCarga(error.code);
  return data?.ultima_carga_em ?? null;
}

// A rota de saúde não tem usuário: chama como anônimo app.saude_carga, a única função que o anônimo
// executa. Erro aqui quer dizer banco ou API fora do ar.
export async function buscarSaudeCarga(limiteMs: number): Promise<string | null> {
  const { url, chavePublica } = lerConfiguracaoSupabase();
  const supabase = createClient(url, chavePublica, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
  const { data, error } = await supabase.schema("app").rpc("saude_carga").abortSignal(AbortSignal.timeout(limiteMs));
  if (error) throw new ErroConsultaCarga(error.code);
  return (data as string | null) ?? null;
}
