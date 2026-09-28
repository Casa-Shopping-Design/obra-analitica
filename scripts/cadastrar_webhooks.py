"""Cadastra os webhooks das origens de um tenant.

Gera um token longo por origem, grava só o SHA-256 em app.webhook_origem e
desativa o token anterior da mesma origem, para a troca de um token vazado valer
na hora. No ERP, cadastra o hook por POST /hooks com o token em claro, que o ERP
manda de volta como Bearer, e remove os hooks antigos para o mesmo destino, senão
cada aviso chegaria duas vezes. O CRM não tem cadastro com token: o script
imprime a URL com o token mascarado e grava a URL completa em dados/brutos/
(fora do git, permissão 0600) para quem for colar no painel do CRM.

O token completo nunca vai para a tela nem para log.

Uso:
    python scripts/cadastrar_webhooks.py --tenant <uuid> --url-painel https://painel.exemplo.com.br
    python scripts/cadastrar_webhooks.py --tenant <uuid> --origem crm --simular
"""

import argparse
import hashlib
import os
import secrets
import sys
import uuid
from pathlib import Path
from urllib.parse import quote, urlsplit

from cliente_origem import ClienteOrigem, ConfiguracaoOrigem, ErroOrigem

RAIZ = Path(__file__).resolve().parent.parent
PASTA_SAIDA = RAIZ / "dados" / "brutos"

# Mesmos grupos aceitos por app.registrar_evento_origem; evento fora daqui seria recusado pela função.
EVENTOS_ERP = [
    "RECEIVABLE_INSTALLMENT_CREATED",
    "RECEIVABLE_INSTALLMENT_UPDATED",
    "RECEIVABLE_INSTALLMENT_REMOVED",
    "RECEIPT_PROCESSED",
    "PAYMENT_BILL_UPDATED",
    "PAYMENT_INSTALLMENT_CREATED",
    "PAYMENT_INSTALLMENT_UPDATE",
    "PAYMENT_INSTALLMENT_REMOVED",
    "PAYMENT_RECEIPT_PROCESSED",
    "PAYMENT_RECEIPT_UPDATED",
    "PAYMENT_RECEIPT_REMOVED",
    "PAYMENT_RECEIPT_CHARGEBACK_PROCESSED",
    "PAYMENT_RECEIPT_CHARGEBACK_REMOVED",
    "SALES_CONTRACT_CREATED",
    "SALES_CONTRACT_UPDATED",
    "SALES_CONTRACT_REMOVED",
    "SALES_CONTRACT_ISSUED",
    "SALES_CONTRACT_CANCELED",
    "UNIT_CREATED",
    "UNIT_UPDATED",
    "UNIT_REMOVED",
    "COST_CENTER_CREATED",
    "COST_CENTER_UPDATED",
    "COST_CENTER_REMOVED",
    "BUILDING_COST_ESTIMATIONS_VERSION_CREATED",
    "BUILDING_COST_ESTIMATION_UPDATED",
    "BUILDING_COST_ESTIMATION_STATUS_UPDATED",
    "BANK_MOVEMENT_CREATED",
    "BANK_MOVEMENT_UPDATED",
    "BANK_MOVEMENT_DELETED",
]

FUNCIONALIDADES_CRM = ["RS", "RP", "UN", "EV", "CV"]


def ler_env():
    arquivo = RAIZ / ".env"
    if arquivo.exists():
        for linha in arquivo.read_text(encoding="utf-8").splitlines():
            linha = linha.strip()
            if linha and not linha.startswith("#") and "=" in linha:
                chave, valor = linha.split("=", 1)
                os.environ.setdefault(chave.strip(), valor.strip().strip('"'))


def gerar_token():
    return secrets.token_urlsafe(48)


def hash_token(token):
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def mascarar(token):
    return f"{token[:4]}...({len(token)} caracteres)"


def validar_url_painel(url):
    partes = urlsplit(url)
    local = partes.hostname in ("localhost", "127.0.0.1")
    if partes.scheme != "https" and not (local and partes.scheme == "http"):
        sys.exit("A URL do painel precisa ser https; o token viaja nela ou no cabeçalho.")
    if partes.query or partes.fragment:
        sys.exit("Informe só a base da URL do painel, sem parâmetros.")
    return url.rstrip("/")


def urls_crm(url_painel, token):
    return {f: f"{url_painel}/api/origem/crm/{token}?funcionalidade={f}" for f in FUNCIONALIDADES_CRM}


def gravar_urls_crm(pasta, tenant_id, urls):
    pasta.mkdir(parents=True, exist_ok=True)
    destino = pasta / f"webhooks_crm_{tenant_id}.txt"
    # Cria já com 0600 para o token não ficar legível por outro usuário nem por um instante.
    descritor = os.open(destino, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descritor, "w", encoding="utf-8") as arquivo:
        for funcionalidade, url in urls.items():
            arquivo.write(f"{funcionalidade}\t{url}\n")
    os.chmod(destino, 0o600)
    return destino


def gravar_hash(conexao, tenant_id, origem, hash_hex):
    """Grava o hash novo e desativa os anteriores da origem na mesma transação."""
    with conexao.cursor() as cursor:
        cursor.execute(
            "insert into app.webhook_origem (tenant_id, origem, hash_token) values (%s, %s, %s) returning id",
            (tenant_id, origem, hash_hex),
        )
        id_novo = cursor.fetchone()[0]
        cursor.execute(
            "update app.webhook_origem set ativo = false where tenant_id = %s and origem = %s and id <> %s and ativo",
            (tenant_id, origem, id_novo),
        )
        return id_novo


def _erro_do_erp(erro):
    # Só o código: o corpo do erro pode ecoar o token enviado.
    if erro.status == 0:
        return RuntimeError("Não foi possível falar com o ERP; confira ORIGEM_URL_BASE e a rede.")
    return RuntimeError(f"O ERP recusou o cadastro do hook (HTTP {erro.status}).")


def cadastrar_hook_erp(cliente, url_destino, token, eventos):
    """Cadastra o hook novo e só depois remove os antigos do mesmo destino, para não ficar sem aviso.

    Devolve o id do hook novo e os ids antigos que o ERP não deixou remover.
    """
    try:
        antigos = [h.get("id") for pagina in cliente.listar("hooks") for h in pagina
                   if h.get("url") == url_destino and h.get("id")]
        retorno = cliente.enviar("POST", "hooks", {"url": url_destino, "token": token, "events": eventos}) or {}
    except ErroOrigem as erro:
        raise _erro_do_erp(erro) from None
    id_novo = retorno.get("id")
    nao_removidos = []
    for id_antigo in antigos:
        if id_antigo == id_novo:
            continue
        try:
            cliente.enviar("DELETE", f"hooks/{quote(str(id_antigo), safe='')}")
        except ErroOrigem:
            nao_removidos.append(str(id_antigo))
    return id_novo, nao_removidos


def processar_erp(args, conexao, token):
    url_destino = f"{args.url_painel}/api/origem/erp"
    print(f"ERP: hook para {url_destino}, token {mascarar(token)}, {len(EVENTOS_ERP)} eventos")
    if args.simular:
        print("ERP: simulação, nada gravado no banco nem enviado ao ERP")
        return
    try:
        # Mesma base, autenticação e cota da carga, para ORIGEM_URL_BASE valer igual nos dois scripts.
        cliente = ClienteOrigem(ConfiguracaoOrigem.de_ambiente())
    except ValueError as erro:
        sys.exit(str(erro))
    id_webhook = gravar_hash(conexao, args.tenant, "erp", hash_token(token))
    id_hook, nao_removidos = cadastrar_hook_erp(cliente, url_destino, token, EVENTOS_ERP)
    # Commit só depois do ERP aceitar, para não sobrar hash ativo sem hook do outro lado.
    conexao.commit()
    print(f"ERP: hook {id_hook} cadastrado; webhook_origem {id_webhook}; tokens anteriores do ERP desativados")
    if nao_removidos:
        print(f"ERP: o ERP não removeu {len(nao_removidos)} hook(s) antigo(s) para o mesmo destino; "
              f"remova por DELETE /hooks/<id>: {', '.join(nao_removidos)}")


def processar_crm(args, conexao, token):
    urls = urls_crm(args.url_painel, token)
    if not args.simular:
        id_webhook = gravar_hash(conexao, args.tenant, "crm", hash_token(token))
        conexao.commit()
        print(f"CRM: webhook_origem {id_webhook}; as URLs anteriores do CRM deixaram de valer")
    destino = gravar_urls_crm(args.pasta_saida, args.tenant, urls)
    for funcionalidade in urls:
        mascarada = f"{args.url_painel}/api/origem/crm/{mascarar(token)}?funcionalidade={funcionalidade}"
        print(f"CRM {funcionalidade}: {mascarada}")
    print(f"CRM: URLs completas em {destino} (permissão 0600). Cadastre no painel do CRM e apague o arquivo.")


def ler_argumentos(argv):
    parser = argparse.ArgumentParser(description="Cadastra os webhooks das origens de um tenant.")
    parser.add_argument("--tenant", required=True, help="uuid do tenant em app.tenant")
    parser.add_argument("--origem", choices=["erp", "crm", "ambas"], default="ambas")
    parser.add_argument("--url-painel", default=os.environ.get("PAINEL_URL_PUBLICA", ""))
    parser.add_argument("--pasta-saida", type=Path, default=PASTA_SAIDA)
    parser.add_argument("--simular", action="store_true", help="não grava no banco nem chama a rede")
    args = parser.parse_args(argv)
    try:
        args.tenant = str(uuid.UUID(args.tenant))
    except ValueError:
        parser.error("--tenant precisa ser um uuid")
    if not args.url_painel:
        parser.error("informe --url-painel ou PAINEL_URL_PUBLICA")
    args.url_painel = validar_url_painel(args.url_painel)
    return args


def main(argv=None):
    ler_env()
    args = ler_argumentos(argv)
    origens = ["erp", "crm"] if args.origem == "ambas" else [args.origem]

    conexao = None
    if not args.simular:
        import psycopg

        if not os.environ.get("DATABASE_URL"):
            sys.exit("Falta DATABASE_URL no .env")
        conexao = psycopg.connect(os.environ["DATABASE_URL"])
    try:
        for origem in origens:
            # Um token por origem: vazar a URL do CRM não abre a rota do ERP.
            token = gerar_token()
            if origem == "erp":
                processar_erp(args, conexao, token)
            else:
                processar_crm(args, conexao, token)
    except RuntimeError as erro:
        if conexao is not None:
            conexao.rollback()
        sys.exit(str(erro))
    finally:
        if conexao is not None:
            conexao.close()


if __name__ == "__main__":
    main()
