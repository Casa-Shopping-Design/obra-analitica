import { createServerClient } from "@supabase/ssr";
import type { NextRequest, NextResponse } from "next/server";
import { lerConfiguracaoSupabase } from "./configuracao";

type CookieRenovado = { name: string; value: string; options: Parameters<NextResponse["cookies"]["set"]>[2] };

export type SessaoRenovada = {
  usuarioId: string | null;
  cookiesRenovados: CookieRenovado[];
  cabecalhosSemCache: Record<string, string>;
};

// Renova o token vencido antes de a página renderizar. getClaims valida a assinatura do JWT;
// aqui só decide redirecionamento, a autorização de dado fica no RLS e em cada rota.
export async function renovarSessao(request: NextRequest): Promise<SessaoRenovada> {
  const { url, chavePublica } = lerConfiguracaoSupabase();
  const sessao: SessaoRenovada = { usuarioId: null, cookiesRenovados: [], cabecalhosSemCache: {} };

  const supabase = createServerClient(url, chavePublica, {
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll(cookiesParaGravar, cabecalhos) {
        cookiesParaGravar.forEach(({ name, value }) => request.cookies.set(name, value));
        sessao.cookiesRenovados = cookiesParaGravar;
        sessao.cabecalhosSemCache = cabecalhos;
      },
    },
  });

  const { data } = await supabase.auth.getClaims();
  sessao.usuarioId = data?.claims?.sub ?? null;
  return sessao;
}

// Resposta que grava cookie de sessão não pode ficar em cache de CDN, senão o token de um usuário vai para outro.
export function aplicarSessao(resposta: NextResponse, sessao: SessaoRenovada): NextResponse {
  sessao.cookiesRenovados.forEach(({ name, value, options }) => resposta.cookies.set(name, value, options));
  Object.entries(sessao.cabecalhosSemCache).forEach(([nome, valor]) => resposta.headers.set(nome, valor));
  return resposta;
}
