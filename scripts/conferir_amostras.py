"""Confere as respostas da sondagem (dados/brutos/*__v2.json) contra a documentação do ERP de origem e contra os
campos que a carga guarda (campos_permitidos.py). Não chama a API: lê só o que a sondagem gravou.

Para cada endpoint diz quantos campos a documentação promete, quantos vieram, quantos a carga guarda e quais
deles não vieram em nenhum registro, além do que veio e não está na documentação. Imprime só nomes de campo,
nunca valores, porque as amostras podem ter dado pessoal.

Uso:
    python scripts/conferir_amostras.py
"""

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from campos_permitidos import CAMPOS_PERMITIDOS  # noqa: E402

RAIZ = Path(__file__).resolve().parent.parent
PASTA_BRUTOS = RAIZ / "dados" / "brutos"
REFERENCIA = RAIZ / ".claude" / "skills" / "erp-origem-api" / "referencias" / "api_webhooks.md"

# amostra da sondagem -> (caminho na documentação, lista de campos da carga)
AMOSTRAS = {
    "companies": ("/companies", "companies"),
    "cost-centers": ("/cost-centers", "cost-centers"),
    "enterprises": ("/enterprises", "enterprises"),
    "units": ("/units", "units"),
    "indexers": ("/indexers", "indexers"),
    "price-tables": ("/price-tables", "price-tables"),
    "accounts-balances": ("/accounts-balances", "accounts-balances"),
    "sales-contracts": ("/sales-contracts", "sales-contracts"),
    "real-estate-map": ("/real-estate-map", "real-estate-map"),
    "progress-logs": ("/building-projects/progress-logs", None),
    "progress-logs-items": ("/building-projects/{buildingId}/progress-logs/{measurementNumber}/items/{buildingUnitId}",
                            "building-projects/progress-logs/items"),
    "accounts-statements": ("/accounts-statements", "accounts-statements"),
    "bills": ("/bills", "bills"),
    "receivable-installments": ("/accounts-receivable/receivable-bills/{receivableBillId}/installments", None),
    "bulk-sales": ("/sales", "sales"),
    "bulk-income": ("/income", "income"),
    "bulk-outcome": ("/outcome", "outcome"),
    "bulk-building-cost-estimation-items": ("/building-cost-estimation-items", "building-cost-estimation-items"),
    "bulk-defaulters-by-aging": ("/defaulters-receivable-bills/by-aging", "defaulters-receivable-bills/by-aging"),
    "trial-balance": ("/trial-balance", "trial-balance"),
    "trial-balance-sem-zeramento": ("/trial-balance", "trial-balance"),
}
# Campos que a carga acrescenta ao registro; não vêm da API.
ACRESCENTADOS = {"initialPeriod", "desconsiderClosingBalance", "positionDate", "billId", "buildingId",
                 "measurementNumber", "date", "statusApproval", "consistent", "buildingUnitId"}
PREFIXO_LISTA = re.compile(r"^(results|data)\[\]\.")


def campos_da_documentacao(texto, caminho):
    """Campos da resposta 200 da seção `GET caminho`, sem o prefixo da lista (results[]. ou data[].)."""
    inicio = texto.find(f"#### `GET {caminho}`")
    if inicio < 0:
        return None
    fim = texto.find("\n#### ", inicio + 1)
    secao = texto[inicio:fim if fim > 0 else len(texto)]
    resposta = secao.find("Campos da resposta 200")
    if resposta < 0:
        return set()
    campos = set()
    for nome in re.findall(r"^\| `([^`]+)` \|", secao[resposta:], flags=re.M):
        if nome.startswith("resultSetMetadata") or nome in ("results", "data"):
            continue
        campos.add(PREFIXO_LISTA.sub("", nome))
    return campos


def registros(conteudo):
    if isinstance(conteudo, list):
        return conteudo
    if isinstance(conteudo, dict):
        for chave in ("results", "data"):
            if isinstance(conteudo.get(chave), list):
                return conteudo[chave]
        return [conteudo]
    return []


def folhas(valor, caminho=""):
    """Caminhos com valor não nulo; lista vira `[]` e vale a união dos elementos."""
    if isinstance(valor, dict):
        for chave, filho in valor.items():
            yield from folhas(filho, f"{caminho}.{chave}" if caminho else chave)
    elif isinstance(valor, list):
        for item in valor:
            yield from folhas(item, f"{caminho}[]")
    elif valor is not None and valor != "":
        yield caminho


def chaves(valor, caminho=""):
    """Todos os caminhos que existem na resposta, com valor ou não."""
    if isinstance(valor, dict):
        for chave, filho in valor.items():
            atual = f"{caminho}.{chave}" if caminho else chave
            yield atual
            yield from chaves(filho, atual)
    elif isinstance(valor, list):
        for item in valor:
            yield from chaves(item, f"{caminho}[]")


def presente(campo, conjunto):
    return campo in conjunto or any(c.startswith(campo + ".") or c.startswith(campo + "[]") for c in conjunto)


def main():
    texto = REFERENCIA.read_text(encoding="utf-8")
    achou = False
    for nome, (caminho_doc, lista) in AMOSTRAS.items():
        arquivo = PASTA_BRUTOS / f"{nome}__v2.json"
        if not arquivo.exists():
            continue
        achou = True
        lidos = registros(json.loads(arquivo.read_text(encoding="utf-8")))
        com_valor, existentes = set(), set()
        for registro in lidos:
            com_valor.update(folhas(registro))
            existentes.update(chaves(registro))
        documentados = campos_da_documentacao(texto, caminho_doc) or set()
        guardados = [c for c in CAMPOS_PERMITIDOS.get(lista, []) if c not in ACRESCENTADOS] if lista else []
        print(f"\n{nome}  ({len(lidos)} registros)")
        print(f"  documentação: {len(documentados)} campos | vieram com valor: {len(com_valor)} | carga guarda: {len(guardados)}")
        ausentes = [c for c in guardados if not presente(c, existentes)]
        vazios = [c for c in guardados if presente(c, existentes) and not presente(c, com_valor)]
        if ausentes:
            print(f"  guardados que NÃO existem na resposta: {', '.join(ausentes)}")
        if vazios:
            print(f"  guardados que vieram sempre vazios: {', '.join(vazios)}")
        fora = sorted(c for c in existentes if documentados and not presente(c, documentados)
                      and not any(c.startswith(d + ".") or c.startswith(d + "[]") for d in documentados))
        if fora:
            print(f"  na resposta e fora da documentação: {', '.join(fora[:15])}" + (" ..." if len(fora) > 15 else ""))
        faltando_doc = sorted(d for d in documentados if not presente(d, existentes))
        if faltando_doc:
            print(f"  documentados que não vieram: {len(faltando_doc)} (ex.: {', '.join(faltando_doc[:8])})")
    if not achou:
        sys.exit("Nenhuma amostra em dados/brutos. Rode antes: python scripts/sondar_origem.py --plano carga")


if __name__ == "__main__":
    main()
