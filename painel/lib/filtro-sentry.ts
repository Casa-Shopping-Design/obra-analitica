import type { ErrorEvent } from "@sentry/nextjs";

const cabecalhosSensiveis = ["cookie", "authorization", "x-supabase-auth"];

// Usuário vai ao Sentry só pelo UUID. E-mail, nome, IP, cookie e token de sessão ficam de fora,
// mesmo que alguma integração do SDK os preencha.
export function removerDadosPessoais(evento: ErrorEvent): ErrorEvent {
  if (evento.user) {
    delete evento.user.email;
    delete evento.user.username;
    delete evento.user.ip_address;
  }
  if (evento.request) {
    delete evento.request.cookies;
    const cabecalhos = evento.request.headers;
    if (cabecalhos) {
      for (const nome of Object.keys(cabecalhos)) {
        if (cabecalhosSensiveis.includes(nome.toLowerCase())) delete cabecalhos[nome];
      }
    }
  }
  return evento;
}

// O SDK coleta cabeçalho, cookie, corpo, query e variável local por padrão. Aqui entra só o que ajuda
// a achar o erro: o id_requisicao e o navegador. Corpo e variável local podem carregar nome de comprador.
export const coletaDeDados = {
  userInfo: false,
  cookies: false,
  httpHeaders: { request: { allow: ["x-id-requisicao", "user-agent"] }, response: false },
  httpBodies: [],
  urlQueryParams: false,
  databaseQueryData: false,
  stackFrameVariables: false,
  genAI: { inputs: false, outputs: false },
};
