"""Diz se um usuário e senha entram na API do ERP de origem, e por qual porta.

Testa as duas formas que o carregador aceita: Basic em {gateway}/{subdominio}/public/api/v1 (usuário de API
da documentação pública) e token OAuth em {gateway}/group/v2/auth/token (a que a sondagem de 11/10 usou).
No máximo três chamadas, uma consulta de uma empresa cada. A senha é lida sem eco e não vai para a tela,
para arquivo nem para log; o token também não.

Uso:
    python3 scripts/testar_credencial_origem.py --gateway https://GATEWAY --subdominio SUBDOMINIO
    python3 scripts/testar_credencial_origem.py --gateway https://GATEWAY --subdominio SUBDOMINIO --usuario NOME

Sem --usuario, o script pergunta. A senha é sempre perguntada, nunca vem de argumento.
"""

import argparse
import base64
import getpass
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from cliente_origem import validar_url_base  # noqa: E402

CONSULTA_TESTE = "companies?limit=1"
TIMEOUT_SEGUNDOS = 30

SIGNIFICADOS = {
    200: "entrou e leu dados",
    400: "a requisição foi recusada como mal formada; confira o subdomínio",
    401: "usuário ou senha recusados nesta forma de acesso",
    403: "credencial aceita, mas sem permissão para ler empresas; peça ao administrador para liberar o recurso",
    404: "rota não existe; o subdomínio ou o gateway provavelmente está errado",
    429: "limite de requisições da conta atingido; espere um minuto e rode de novo",
}


def significado(status, motivo_rede=""):
    if status == 0:
        return f"não houve resposta ({motivo_rede}); confira o endereço do gateway e a conexão"
    if status >= 500:
        return "erro do lado do ERP; tente de novo mais tarde"
    return SIGNIFICADOS.get(status, "resposta inesperada")


def basic(usuario, senha):
    return "Basic " + base64.b64encode(f"{usuario}:{senha}".encode()).decode()


def requisitar(metodo, url, cabecalhos, corpo=None):
    """Devolve (status, corpo em texto, motivo de rede). Status 0 quando nem chegou resposta."""
    pedido = urllib.request.Request(url, data=corpo, headers={"Accept": "application/json", **cabecalhos},
                                    method=metodo)
    try:
        with urllib.request.urlopen(pedido, timeout=TIMEOUT_SEGUNDOS) as resposta:
            return resposta.status, resposta.read().decode("utf-8", errors="replace"), ""
    except urllib.error.HTTPError as erro:
        texto = erro.read().decode("utf-8", errors="replace")
        erro.close()
        return erro.code, texto, ""
    except (urllib.error.URLError, TimeoutError) as erro:
        return 0, "", str(getattr(erro, "reason", erro))


def mensagem_do_erp(texto):
    """Só a mensagem curta que o ERP põe no erro; o corpo inteiro pode trazer dado da empresa."""
    try:
        corpo = json.loads(texto)
    except ValueError:
        return ""
    if not isinstance(corpo, dict):
        return ""
    return str(corpo.get("clientMessage") or corpo.get("message") or corpo.get("error_description") or "")[:200]


def testar(base_v1, gateway, subdominio, usuario, senha, chamar=requisitar):
    """Lista de (forma, status, explicação). base_v1 é {gateway}/{subdominio}, separado para o teste local."""
    resultados = []

    status, texto, motivo = chamar("GET", f"{base_v1}/public/api/v1/{CONSULTA_TESTE}",
                                   {"Authorization": basic(usuario, senha)})
    resultados.append(("Basic, API v1", status, significado(status, motivo), mensagem_do_erp(texto)))

    corpo = urllib.parse.urlencode({"grant_type": "client_credentials", "tenant": subdominio}).encode()
    status, texto, motivo = chamar("POST", f"{gateway}/group/v2/auth/token", {
        "Authorization": basic(usuario, senha), "Content-Type": "application/x-www-form-urlencoded"}, corpo)
    token = ""
    if status == 200:
        try:
            token = json.loads(texto).get("access_token", "")
        except ValueError:
            token = ""
    if not token:
        explicacao = significado(status, motivo) if status != 200 else "respondeu 200 sem token"
        resultados.append(("Token OAuth, API v2", status, explicacao, mensagem_do_erp(texto)))
        return resultados

    status, texto, motivo = chamar("GET", f"{gateway}/group/v2/{CONSULTA_TESTE}", {"Authorization": f"Bearer {token}"})
    resultados.append(("Token OAuth, API v2", status, significado(status, motivo), mensagem_do_erp(texto)))
    return resultados


def conclusao(resultados, subdominio, usuario, gateway):
    aceitas = {forma for forma, status, _, _ in resultados if status in (200, 403)}
    if "Basic, API v1" in aceitas:
        return ("É usuário de API. No .env da pasta principal:\n"
                f"  ORIGEM_URL_BASE={gateway}/{subdominio}\n  ORIGEM_AUTENTICACAO=basic\n"
                f"  ORIGEM_USUARIO={usuario}\n  ORIGEM_SENHA=(a senha que você digitou)")
    if "Token OAuth, API v2" in aceitas:
        return ("É usuário de API, aceito só pela v2. No .env da pasta principal:\n"
                f"  ORIGEM_URL_BASE={gateway}\n  ORIGEM_AUTENTICACAO=oauth\n  ORIGEM_TENANT={subdominio}\n"
                f"  ORIGEM_CLIENT_ID={usuario}\n  ORIGEM_CLIENT_SECRET=(a senha que você digitou)")
    if all(status == 0 for _, status, _, _ in resultados):
        return "Nenhuma chamada chegou ao ERP. Confira o gateway e a internet antes de desconfiar da senha."
    if any(status == 404 for _, status, _, _ in resultados):
        return "O ERP não reconheceu o endereço. Confira o subdomínio (o que vem antes do domínio na tela de login)."
    return ("A API recusou a credencial nas duas formas. Ou a senha está errada, ou esse é um login de tela, "
            "que não serve para a API. Teste o mesmo usuário na tela de login do ERP; se entrar lá, peça ao "
            "administrador um usuário de API.")


def main():
    argumentos = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    argumentos.add_argument("--gateway", required=True, help="endereço do gateway da API, com https")
    argumentos.add_argument("--subdominio", required=True, help="subdomínio do cliente no ERP")
    argumentos.add_argument("--usuario", help="usuário a testar; sem ele, o script pergunta")
    opcoes = argumentos.parse_args()

    try:
        gateway = validar_url_base(opcoes.gateway)
    except ValueError:
        sys.exit("O gateway precisa começar com https://")
    subdominio = opcoes.subdominio.strip().strip("/")
    usuario = (opcoes.usuario or input("Usuário: ")).strip()
    senha = getpass.getpass("Senha (não aparece enquanto digita): ")
    if not usuario or not senha:
        sys.exit("Usuário e senha são obrigatórios.")

    resultados = testar(f"{gateway}/{urllib.parse.quote(subdominio)}", gateway, subdominio, usuario, senha)
    print()
    for forma, status, explicacao, mensagem in resultados:
        print(f"{forma}: {status or 'sem resposta'}, {explicacao}")
        if mensagem:
            print(f"  mensagem do ERP: {mensagem}")
    print()
    print(conclusao(resultados, subdominio, usuario, gateway))


if __name__ == "__main__":
    main()
