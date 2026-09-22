"""Sonda a API do ERP de origem com um usuario de testes e guarda o que voltar.

Pega o token OAuth em group/v2/auth/token (Basic com client/secret, corpo
grant_type=client_credentials e tenant) e chama group/v2/{recurso} com
Bearer, paginando por limit/offset. Grava as respostas brutas em
dados/brutos/, que fica fora do git. So a primeira pagina de cada recurso.

Uso:
    python scripts/sondar_origem.py
    python scripts/sondar_origem.py --inicio 2025-01-01 --fim 2025-12-31
"""

import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, timedelta
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
PASTA_BRUTOS = RAIZ / "dados" / "brutos"
BASE = ""  # vem de ORIGEM_URL_BASE no .env
PAUSA = 0.5  # 120 req/min no pior caso, abaixo das 200 da conta


def ler_env():
    arquivo = RAIZ / ".env"
    if arquivo.exists():
        for linha in arquivo.read_text(encoding="utf-8").splitlines():
            linha = linha.strip()
            if linha and not linha.startswith("#") and "=" in linha:
                chave, valor = linha.split("=", 1)
                os.environ.setdefault(chave.strip(), valor.strip().strip('"'))
    faltando = [c for c in ("ORIGEM_URL_BASE", "ORIGEM_TENANT", "ORIGEM_CLIENT_ID", "ORIGEM_CLIENT_SECRET") if not os.environ.get(c)]
    if faltando:
        sys.exit(f"Faltam no .env: {', '.join(faltando)}")
    global BASE
    BASE = os.environ["ORIGEM_URL_BASE"].rstrip("/")
    return os.environ["ORIGEM_TENANT"], os.environ["ORIGEM_CLIENT_ID"], os.environ["ORIGEM_CLIENT_SECRET"]


def chamar(metodo, url, cabecalhos, corpo=None, tentativas=3):
    for tentativa in range(tentativas):
        req = urllib.request.Request(url, data=corpo, headers=cabecalhos, method=metodo)
        inicio = time.time()
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                texto = resp.read().decode("utf-8", errors="replace")
                return resp.status, texto, round(time.time() - inicio, 2)
        except urllib.error.HTTPError as erro:
            texto = erro.read().decode("utf-8", errors="replace")
            if erro.code == 429 and tentativa < tentativas - 1:
                espera = int(erro.headers.get("Retry-After", "30"))
                print(f"    429, esperando {espera}s")
                time.sleep(espera)
                continue
            return erro.code, texto, round(time.time() - inicio, 2)
        except urllib.error.URLError as erro:
            return 0, str(erro.reason), round(time.time() - inicio, 2)
    return 0, "sem resposta", 0


def pegar_token(tenant, cliente, segredo):
    credencial = base64.b64encode(f"{cliente}:{segredo}".encode()).decode()
    corpo = urllib.parse.urlencode({"grant_type": "client_credentials", "tenant": tenant}).encode()
    status, texto, _ = chamar("POST", f"{BASE}/group/v2/auth/token", {
        "Authorization": f"Basic {credencial}",
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept": "application/json",
    }, corpo)
    if status != 200:
        sys.exit(f"Token falhou ({status}): {texto[:300]}")
    return json.loads(texto)


def claims_do_jwt(token):
    try:
        parte = token.split(".")[1]
        parte += "=" * (-len(parte) % 4)
        return json.loads(base64.urlsafe_b64decode(parte))
    except Exception:
        return {}


def recursos(inicio, fim):
    """(nome, caminho em group/v2, parametros). Os de bulk-data ainda sao palpite."""
    periodo = {"startDate": inicio, "endDate": fim}
    return [
        ("companies", "companies", {"limit": 100, "offset": 0}),
        ("cost-centers", "cost-centers", {"limit": 100, "offset": 0}),
        ("enterprises", "enterprises", {"limit": 100, "offset": 0}),
        ("units", "units", {"limit": 100, "offset": 0}),
        ("customers", "customers", {"limit": 100, "offset": 0}),
        ("sales-contracts", "sales-contracts", {"limit": 100, "offset": 0}),
        ("professions", "professions", {"limit": 100, "offset": 0}),
        ("accounts-statements", "accounts-statements", {**periodo, "limit": 100, "offset": 0}),
        ("accounts-balances", "accounts-balances", {"balanceDate": fim}),
        ("bulk-income", "bulk-data/v1/income", {**periodo, "selectionType": "D"}),
        ("bulk-outcome", "bulk-data/v1/outcome", {**periodo, "selectionType": "D"}),
        ("bulk-bank-movement", "bulk-data/v1/bank-movement", periodo),
        ("bulk-defaulters", "bulk-data/v1/defaulters-receivable-bills", {}),
        ("bulk-customer-extract", "bulk-data/v1/customer-extract-history", {}),
    ]


def url_v2(caminho):
    """Na v2 o tenant vai no token, nao no caminho: group/v2/{recurso}."""
    return f"{BASE}/group/v2/{caminho}"


def contar_registros(texto):
    try:
        dados = json.loads(texto)
    except ValueError:
        return None
    if isinstance(dados, list):
        return len(dados)
    for chave in ("results", "data", "content", "items"):
        if isinstance(dados.get(chave), list):
            return len(dados[chave])
    return None


def main():
    parser = argparse.ArgumentParser()
    hoje = date.today()
    parser.add_argument("--inicio", default=(hoje - timedelta(days=90)).isoformat())
    parser.add_argument("--fim", default=hoje.isoformat())
    parser.add_argument("--so", help="nome de um recurso para testar sozinho")
    args = parser.parse_args()

    tenant, cliente, segredo = ler_env()
    PASTA_BRUTOS.mkdir(parents=True, exist_ok=True)

    print("Pedindo token...")
    token = pegar_token(tenant, cliente, segredo)
    claims = claims_do_jwt(token["access_token"])
    # guarda so o que ajuda a entender o acesso; o token em si nao vai pro disco
    (PASTA_BRUTOS / "_token_info.json").write_text(json.dumps({
        "expires_in": token.get("expires_in"),
        "scope": token.get("scope", "").split(),
        "claims": {k: v for k, v in claims.items() if k not in ("jti",)},
    }, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"  ok, expira em {token.get('expires_in')}s, {len(token.get('scope', '').split())} escopos")

    cabecalhos = {"Authorization": f"Bearer {token['access_token']}", "Accept": "application/json"}
    relatorio = []

    for nome, caminho, params in recursos(args.inicio, args.fim):
        if args.so and args.so != nome:
            continue
        for formato, url in [("v2", url_v2(caminho))]:
            completa = url + ("?" + urllib.parse.urlencode(params) if params else "")
            status, texto, segundos = chamar("GET", completa, cabecalhos)
            qtd = contar_registros(texto) if status == 200 else None
            print(f"  {status:>3} {formato:<14} {nome:<24} {segundos}s" + (f" ({qtd} reg.)" if qtd is not None else ""))
            relatorio.append({"recurso": nome, "formato": formato, "url": url, "params": params,
                              "status": status, "segundos": segundos, "registros": qtd,
                              "erro": None if status == 200 else texto[:400]})
            if status == 200:
                try:
                    conteudo = json.loads(texto)
                except ValueError:
                    conteudo = {"_texto": texto}
                (PASTA_BRUTOS / f"{nome}__{formato}.json").write_text(
                    json.dumps(conteudo, ensure_ascii=False, indent=1), encoding="utf-8")
            time.sleep(PAUSA)

    (PASTA_BRUTOS / "_relatorio_sondagem.json").write_text(
        json.dumps(relatorio, ensure_ascii=False, indent=1), encoding="utf-8")
    ok = sum(1 for r in relatorio if r["status"] == 200)
    print(f"\n{ok} de {len(relatorio)} chamadas com 200. Detalhes em dados/brutos/_relatorio_sondagem.json")
    print("Proximo passo: python scripts/sanitizar_amostras.py")


if __name__ == "__main__":
    main()
