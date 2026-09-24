import { NextResponse } from "next/server";
import { lerConfiguracaoSupabase } from "@/lib/supabase/configuracao";

// Versão mínima: confere se o Supabase responde. O anônimo não lê nenhuma tabela, então o
// teste do banco e a idade da última carga entram no PT-08, com uma função própria para isso.
export async function GET() {
  const commit = process.env.VERCEL_GIT_COMMIT_SHA ?? "local";
  const { url, chavePublica } = lerConfiguracaoSupabase();

  let supabaseResponde = false;
  try {
    const resposta = await fetch(`${url}/auth/v1/health`, {
      headers: { apikey: chavePublica },
      cache: "no-store",
      signal: AbortSignal.timeout(5000),
    });
    supabaseResponde = resposta.ok;
  } catch {
    supabaseResponde = false;
  }

  return NextResponse.json(
    { ok: supabaseResponde, commit },
    { status: supabaseResponde ? 200 : 503, headers: { "cache-control": "no-store" } },
  );
}
