"""Raspa a documentacao publica das APIs e atualiza a referencia das skills.

Grava em .claude/skills/api-<fonte>/referencia/ um Markdown por API, os guias,
o indice.json usado para comparar e o MUDANCAS.md com o que mudou desde a
ultima raspagem. As especificacoes brutas ficam em dados/brutos/documentacao/,
fora do git.

Uso:
    python scripts/atualizar_documentacao_apis.py
    python scripts/atualizar_documentacao_apis.py --fonte cvcrm
    python scripts/atualizar_documentacao_apis.py --navegador
    python scripts/atualizar_documentacao_apis.py --fonte sienge --pasta-local ~/Downloads/docs-sienge
"""

import argparse
import json
import sys
from pathlib import Path
from urllib.parse import urljoin

sys.path.insert(0, str(Path(__file__).resolve().parent))

from documentacao_apis.descoberta import descobrir_especificacoes, descobrir_guias, ler_pasta_local  # noqa: E402
from documentacao_apis.fontes import FONTES, PASTA_BRUTOS  # noqa: E402
from documentacao_apis.openapi import catalogar  # noqa: E402
from documentacao_apis.relatorio import gravar  # noqa: E402
from documentacao_apis.rede import ClienteHttp, ClienteNavegador  # noqa: E402


def raspar(fonte, cliente, pasta_local):
    if pasta_local:
        guias, especificacoes = ler_pasta_local(pasta_local)
        return especificacoes, guias
    especificacoes = descobrir_especificacoes(cliente, fonte.url_indice)
    guias, embutidas = descobrir_guias(cliente, fonte.url_indice)
    for titulo, especificacao in embutidas.items():
        especificacoes.setdefault(titulo, (urljoin(fonte.url_indice, "/llms.txt"), especificacao))
    return especificacoes, guias


def guardar_brutos(fonte, especificacoes):
    pasta = PASTA_BRUTOS / fonte.nome
    pasta.mkdir(parents=True, exist_ok=True)
    for nome, (url, especificacao) in especificacoes.items():
        (pasta / f"{nome}.json").write_text(
            json.dumps({"origem": url, "especificacao": especificacao}, ensure_ascii=False, indent=1), encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--fonte", choices=[*FONTES, "todas"], default="todas")
    parser.add_argument("--navegador", action="store_true", help="usa Chromium headless (Playwright) para portais montados por JavaScript")
    parser.add_argument("--pasta-local", help="pasta com especificacoes e paginas salvas pelo navegador, quando o portal barra robo")
    args = parser.parse_args()
    if args.pasta_local and args.fonte == "todas":
        sys.exit("--pasta-local precisa de --fonte")

    cliente = ClienteNavegador() if args.navegador else ClienteHttp()
    falhou = False
    try:
        for nome in (FONTES if args.fonte == "todas" else [args.fonte]):
            fonte = FONTES[nome]
            print(f"{nome}: lendo {args.pasta_local or fonte.url_indice}")
            especificacoes, guias = raspar(fonte, cliente, args.pasta_local)
            if not especificacoes and not guias:
                status, _ = cliente.baixar(fonte.url_indice)
                print(f"  nada encontrado (indice respondeu {status}); referencia anterior mantida")
                falhou = True
                continue
            guardar_brutos(fonte, especificacoes)
            catalogos = {n: (url, catalogar(e)) for n, (url, e) in especificacoes.items()}
            total = sum(len(c["operacoes"]) for _, c in catalogos.values())
            print(f"  {len(catalogos)} especificacoes, {total} operacoes, {len(guias)} guias")
            for linha in gravar(fonte, catalogos, guias):
                print(f"  - {linha}")
    finally:
        cliente.fechar()
    sys.exit(1 if falhou else 0)


if __name__ == "__main__":
    main()
