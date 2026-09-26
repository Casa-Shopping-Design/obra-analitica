"""Transforma uma especificacao OpenAPI (2 ou 3) num catalogo plano de operacoes e campos."""

METODOS = ("get", "post", "put", "patch", "delete")
PROFUNDIDADE_MAXIMA = 8
TAMANHO_DESCRICAO = 240


def resumir(texto):
    texto = " ".join(str(texto or "").split())
    return texto if len(texto) <= TAMANHO_DESCRICAO else texto[: TAMANHO_DESCRICAO - 3] + "..."


def resolver(especificacao, objeto, vistos=()):
    """Segue $ref locais. Devolve (objeto, nome da referencia) para detectar ciclo."""
    referencia = None
    while isinstance(objeto, dict) and "$ref" in objeto:
        referencia = objeto["$ref"]
        if not referencia.startswith("#/") or referencia in vistos:
            return {}, referencia
        alvo = especificacao
        for parte in referencia[2:].split("/"):
            alvo = alvo.get(parte.replace("~1", "/").replace("~0", "~"), {}) if isinstance(alvo, dict) else {}
        objeto = alvo
    return objeto, referencia


def referencia_ciclica(esquema):
    """Esquema que aponta para um ancestral: mostra o nome em vez de repetir os campos."""
    referencia = esquema.get("$ref", "") if isinstance(esquema, dict) else ""
    return f"object ({referencia.rsplit('/', 1)[-1]}, recursivo)" if referencia else "any"


def tipo_do_esquema(esquema):
    tipo = esquema.get("type") or ("object" if "properties" in esquema else "")
    if isinstance(tipo, list):
        tipo = "|".join(t for t in tipo if t != "null")
    if esquema.get("format"):
        tipo = f"{tipo}({esquema['format']})"
    return tipo or "any"


def achatar(especificacao, esquema, prefixo="", obrigatorio_pai=(), vistos=(), profundidade=0):
    """Lista de campos {caminho, tipo, obrigatorio, descricao, valores} de um esquema.

    Percorre cada no uma vez por ramo; o corte por profundidade e por $ref ja
    visitado impede recursao infinita em esquemas que se referenciam.
    """
    esquema, referencia = resolver(especificacao, esquema or {}, vistos)
    if referencia:
        vistos = vistos + (referencia,)
    if profundidade > PROFUNDIDADE_MAXIMA or not isinstance(esquema, dict):
        return []

    for combinador in ("allOf", "oneOf", "anyOf"):
        if combinador in esquema:
            juntos = {k: v for k, v in esquema.items() if k != combinador}
            propriedades = dict(juntos.get("properties", {}))
            obrigatorios = list(juntos.get("required", []))
            for parte in esquema[combinador]:
                parte, _ = resolver(especificacao, parte, vistos)
                propriedades.update(parte.get("properties", {}))
                obrigatorios += parte.get("required", []) if combinador == "allOf" else []
                if "items" in parte and "items" not in juntos:
                    juntos["items"], juntos["type"] = parte["items"], "array"
            if propriedades:
                juntos["properties"], juntos["type"] = propriedades, juntos.get("type", "object")
            juntos["required"] = obrigatorios
            esquema = juntos
            break

    campos = []
    if esquema.get("type") == "array" or "items" in esquema:
        return achatar(especificacao, esquema.get("items", {}), prefixo + "[]", (), vistos, profundidade + 1)

    obrigatorios = set(esquema.get("required", []))
    for nome, filho in (esquema.get("properties") or {}).items():
        filho_resolvido, _ = resolver(especificacao, filho, vistos)
        caminho = f"{prefixo}.{nome}" if prefixo else nome
        e_lista = filho_resolvido.get("type") == "array"
        campos.append({
            "caminho": caminho + ("[]" if e_lista else ""),
            "tipo": "array" if e_lista else tipo_do_esquema(filho_resolvido) if filho_resolvido else referencia_ciclica(filho),
            "obrigatorio": nome in obrigatorios,
            "descricao": resumir(filho_resolvido.get("description") or filho.get("description")),
            "valores": [str(v) for v in filho_resolvido.get("enum", [])],
        })
        if e_lista or filho_resolvido.get("properties") or any(c in filho_resolvido for c in ("allOf", "oneOf", "anyOf")):
            campos += achatar(especificacao, filho, caminho, (), vistos, profundidade + 1)
    return campos


def esquema_do_conteudo(especificacao, objeto):
    objeto, _ = resolver(especificacao, objeto or {})
    if "schema" in objeto:
        return objeto["schema"]
    conteudo = objeto.get("content") or {}
    for tipo_midia in ("application/json", "application/hal+json", "*/*"):
        if tipo_midia in conteudo:
            return conteudo[tipo_midia].get("schema", {})
    return next(iter(conteudo.values()), {}).get("schema", {}) if conteudo else {}


def ler_parametros(especificacao, lista):
    parametros = []
    for bruto in lista:
        parametro, _ = resolver(especificacao, bruto)
        if not parametro or parametro.get("in") == "body":
            continue
        esquema, _ = resolver(especificacao, parametro.get("schema", parametro))
        parametros.append({
            "nome": parametro.get("name", ""),
            "local": parametro.get("in", ""),
            "tipo": tipo_do_esquema(esquema),
            "obrigatorio": bool(parametro.get("required")),
            "descricao": resumir(parametro.get("description")),
            "valores": [str(v) for v in esquema.get("enum", [])],
        })
    return parametros


def servidores(especificacao):
    if "servers" in especificacao:
        return [s.get("url", "") for s in especificacao["servers"]]
    if "host" in especificacao:
        esquemas = especificacao.get("schemes") or ["https"]
        return [f"{esquemas[0]}://{especificacao['host']}{especificacao.get('basePath', '')}"]
    return []


def catalogar(especificacao):
    info = especificacao.get("info", {})
    operacoes = {}
    for caminho, item in sorted(especificacao.get("paths", {}).items()):
        item, _ = resolver(especificacao, item)
        comuns = item.get("parameters", [])
        for metodo in METODOS:
            operacao = item.get(metodo)
            if not isinstance(operacao, dict):
                continue
            todos = comuns + operacao.get("parameters", [])
            corpo = next((p for p in (resolver(especificacao, p)[0] for p in todos) if p.get("in") == "body"), None)
            esquema_corpo = corpo.get("schema") if corpo else esquema_do_conteudo(especificacao, operacao.get("requestBody"))
            respostas = operacao.get("responses", {})
            sucesso = next((c for c in sorted(respostas) if str(c).startswith("2")), None)
            operacoes[f"{metodo.upper()} {caminho}"] = {
                "resumo": resumir(operacao.get("summary")),
                "descricao": resumir(operacao.get("description")),
                "grupo": (operacao.get("tags") or [""])[0],
                "obsoleta": bool(operacao.get("deprecated")),
                "parametros": ler_parametros(especificacao, todos),
                "corpo": achatar(especificacao, esquema_corpo) if esquema_corpo else [],
                "resposta": achatar(especificacao, esquema_do_conteudo(especificacao, respostas.get(sucesso))) if sucesso else [],
                "status": sorted(str(c) for c in respostas),
            }
    return {
        "titulo": info.get("title", ""),
        "versao": str(info.get("version", "")),
        "descricao": resumir(info.get("description")),
        "servidores": servidores(especificacao),
        "seguranca": sorted((especificacao.get("components", {}).get("securitySchemes") or especificacao.get("securityDefinitions") or {}).keys()),
        "operacoes": operacoes,
    }
