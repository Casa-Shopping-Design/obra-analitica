"""Acha as especificacoes OpenAPI e as paginas de guia de um portal de documentacao.

Nao depende do layout do portal: varre o HTML, os scripts e as paginas filhas
atras de arquivos .json/.yaml que sejam OpenAPI ou configuracao do Swagger UI,
e tenta o llms.txt, que portais como o ReadMe publicam com a lista de paginas
em Markdown.
"""

import json
import re
import unicodedata
from pathlib import Path
from urllib.parse import urljoin, urlparse

try:
    import yaml
except ImportError:
    yaml = None

LIMITE_PAGINAS = 400
LIMITE_SCRIPTS = 40
CAMINHOS_COMUNS = ("swagger.json", "openapi.json", "swagger-config", "v3/api-docs", "api-docs", "openapi.yaml")
PADRAO_ARQUIVO = re.compile(r"""["'(]([^"'()\s<>]+?\.(?:json|ya?ml)(?:\?[^"'()\s<>]*)?)["')]""")
PADRAO_URL_CONFIG = re.compile(r"""\burl\s*:\s*["']([^"']+)["']""")
PADRAO_SCRIPT = re.compile(r"""<script[^>]+src=["']([^"']+)["']""", re.I)
PADRAO_LINK = re.compile(r"""href=["']([^"'#]+)["']""", re.I)
PADRAO_LINK_MD = re.compile(r"\[([^\]]*)\]\((https?://[^)\s]+)\)")
PADRAO_BLOCO = re.compile(r"```(?:json|yaml|yml)?[^\n]*\n(.*?)```", re.S)


def criar_slug(texto):
    texto = unicodedata.normalize("NFKD", texto).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "-", texto.lower()).strip("-") or "sem-nome"


def interpretar(texto):
    """Devolve o dict se o texto for JSON ou YAML com cara de OpenAPI ou de swagger-config."""
    texto = texto.strip()
    if not texto or texto.startswith("<"):
        return None
    try:
        conteudo = json.loads(texto)
    except ValueError:
        if yaml is None:
            return None
        try:
            conteudo = yaml.safe_load(texto)
        except yaml.YAMLError:
            return None
    if not isinstance(conteudo, dict):
        return None
    if ("openapi" in conteudo or "swagger" in conteudo) and "paths" in conteudo:
        return conteudo
    if isinstance(conteudo.get("urls"), list):
        return conteudo
    return None


def e_especificacao(conteudo):
    return conteudo is not None and "paths" in conteudo


def mesmo_dominio(url, base):
    host, host_base = urlparse(url).hostname or "", urlparse(base).hostname or ""
    raiz_base = ".".join(host_base.split(".")[-3:]) if host_base.endswith(".br") else ".".join(host_base.split(".")[-2:])
    return host == host_base or host.endswith("." + raiz_base) or host == raiz_base


def candidatos(texto, base):
    achados = PADRAO_ARQUIVO.findall(texto) + PADRAO_URL_CONFIG.findall(texto)
    urls = {urljoin(base, achado) for achado in achados if not achado.startswith(("data:", "javascript:"))}
    return {url for url in urls if mesmo_dominio(url, base)}


def nome_da_especificacao(url, especificacao, nomes_usados):
    base = Path(urlparse(url).path).stem
    if base.lower() in {"swagger", "openapi", "api-docs", "", "docs", "index"}:
        base = especificacao.get("info", {}).get("title", base)
    nome = criar_slug(base)
    sufixo = 2
    while nome in nomes_usados:
        nome = f"{criar_slug(base)}-{sufixo}"
        sufixo += 1
    return nome


def mesclar(destino, origem):
    """Junta paths e componentes de pedacos da mesma API (o ReadMe entrega uma operacao por pagina)."""
    for caminho, operacoes in origem.get("paths", {}).items():
        destino.setdefault("paths", {}).setdefault(caminho, {}).update(operacoes)
    for secao, itens in origem.get("components", {}).items():
        if isinstance(itens, dict):
            destino.setdefault("components", {}).setdefault(secao, {}).update(itens)
    for chave in ("definitions", "parameters"):
        if isinstance(origem.get(chave), dict):
            destino.setdefault(chave, {}).update(origem[chave])
    return destino


def descobrir_especificacoes(cliente, url_indice):
    """Devolve {nome: (url, especificacao)}.

    Busca em largura limitada a LIMITE_PAGINAS paginas do mesmo dominio;
    cada URL e baixada uma vez so, entao o custo e linear no numero de URLs.
    """
    html, carregadas = cliente.abrir_pagina(url_indice)
    fila = list(candidatos(html, url_indice)) + carregadas + [urljoin(url_indice, c) for c in CAMINHOS_COMUNS]
    for script in PADRAO_SCRIPT.findall(html)[:LIMITE_SCRIPTS]:
        url_script = urljoin(url_indice, script)
        if mesmo_dominio(url_script, url_indice):
            status, texto = cliente.baixar(url_script)
            if status == 200:
                fila += list(candidatos(texto, url_script))

    prefixo = url_indice.rsplit("/", 1)[0]
    paginas = [urljoin(url_indice, link) for link in PADRAO_LINK.findall(html)]
    paginas = [p for p in dict.fromkeys(paginas) if p.startswith(prefixo) and p != url_indice][:LIMITE_PAGINAS]

    vistas, especificacoes = set(), {}
    while fila or paginas:
        if not fila:
            pagina = paginas.pop(0)
            if pagina in vistas:
                continue
            vistas.add(pagina)
            status, texto = cliente.baixar(pagina)
            if status == 200:
                fila += list(candidatos(texto, pagina))
            continue
        url = fila.pop(0)
        if url in vistas:
            continue
        vistas.add(url)
        status, texto = cliente.baixar(url)
        conteudo = interpretar(texto) if status == 200 else None
        if conteudo is None:
            continue
        if e_especificacao(conteudo):
            especificacoes[nome_da_especificacao(url, conteudo, especificacoes)] = (url, conteudo)
        else:
            fila += [urljoin(url, item.get("url", "")) for item in conteudo["urls"] if isinstance(item, dict)]
    return especificacoes


def endereco_markdown(url):
    caminho = urlparse(url).path
    return url if caminho.endswith((".md", ".txt")) else url.rstrip("/") + ".md"


def descobrir_guias(cliente, url_indice):
    """Le o llms.txt e baixa cada pagina em Markdown.

    Devolve ({slug: markdown}, {titulo_api: especificacao}) juntando as
    definicoes OpenAPI que vem embutidas nas paginas de referencia.
    """
    status, lista = cliente.baixar(urljoin(url_indice, "/llms.txt"))
    if status != 200 or not lista.strip() or lista.lstrip().startswith("<"):
        return {}, {}
    guias, especificacoes = {}, {}
    enderecos = dict.fromkeys(url for _, url in PADRAO_LINK_MD.findall(lista) if mesmo_dominio(url, url_indice))
    for url in list(enderecos)[:LIMITE_PAGINAS * 2]:
        status, texto = cliente.baixar(endereco_markdown(url))
        if status != 200 or texto.lstrip().startswith("<"):
            continue
        slug = criar_slug(urlparse(url).path.removesuffix(".md"))
        guias[slug] = texto
        for bloco in PADRAO_BLOCO.findall(texto):
            conteudo = interpretar(bloco)
            if e_especificacao(conteudo):
                titulo = criar_slug(conteudo.get("info", {}).get("title", "api"))
                if titulo in especificacoes:
                    mesclar(especificacoes[titulo], conteudo)
                else:
                    especificacoes[titulo] = conteudo
    return guias, especificacoes


def ler_pasta_local(pasta):
    """Para quando o portal barra robo: arquivos salvos pelo navegador numa pasta."""
    guias, especificacoes = {}, {}
    for arquivo in sorted(Path(pasta).rglob("*")):
        if not arquivo.is_file():
            continue
        texto = arquivo.read_text(encoding="utf-8", errors="replace")
        conteudo = interpretar(texto)
        if e_especificacao(conteudo):
            especificacoes[nome_da_especificacao(arquivo.name, conteudo, especificacoes)] = (str(arquivo), conteudo)
        elif arquivo.suffix in {".md", ".txt"} and arquivo.name != "llms.txt":
            guias[criar_slug(arquivo.stem)] = texto
            for bloco in PADRAO_BLOCO.findall(texto):
                embutida = interpretar(bloco)
                if e_especificacao(embutida):
                    titulo = criar_slug(embutida.get("info", {}).get("title", arquivo.stem))
                    atual = especificacoes.get(titulo)
                    if atual:
                        mesclar(atual[1], embutida)
                    else:
                        especificacoes[titulo] = (str(arquivo), embutida)
    return guias, especificacoes
