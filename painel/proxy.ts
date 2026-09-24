import { NextResponse, type NextRequest } from "next/server";
import { aplicarSessao, renovarSessao } from "@/lib/supabase/sessao";
import { montarPoliticaConteudo } from "@/lib/politica-conteudo";

const rotasPublicas = new Set(["/entrar", "/api/saude"]);

export async function proxy(request: NextRequest) {
  const idRequisicao = crypto.randomUUID();
  const nonce = Buffer.from(crypto.randomUUID()).toString("base64");
  const politicaConteudo = montarPoliticaConteudo(nonce);
  const caminho = request.nextUrl.pathname;

  const sessao = await renovarSessao(request);

  let resposta: NextResponse;
  if (!sessao.usuarioId && !rotasPublicas.has(caminho) && !caminho.startsWith("/api/")) {
    resposta = NextResponse.redirect(new URL("/entrar", request.url));
  } else if (sessao.usuarioId && caminho === "/entrar") {
    resposta = NextResponse.redirect(new URL("/", request.url));
  } else {
    // Cabeçalhos montados depois da renovação, para a página já ler o cookie novo.
    const cabecalhosRequisicao = new Headers(request.headers);
    cabecalhosRequisicao.set("x-id-requisicao", idRequisicao);
    cabecalhosRequisicao.set("x-nonce", nonce);
    cabecalhosRequisicao.set("content-security-policy", politicaConteudo);
    resposta = NextResponse.next({ request: { headers: cabecalhosRequisicao } });
  }

  resposta.headers.set("content-security-policy", politicaConteudo);
  resposta.headers.set("x-id-requisicao", idRequisicao);
  return aplicarSessao(resposta, sessao);
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|robots.txt).*)"],
};
