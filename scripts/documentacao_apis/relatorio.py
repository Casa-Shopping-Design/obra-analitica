"""Grava a referencia em Markdown, o indice compacto e o registro de mudancas."""

import hashlib
import json
import shutil
from datetime import date

ARQUIVO_INDICE = "indice.json"
ARQUIVO_MUDANCAS = "MUDANCAS.md"


def celula(texto):
    return str(texto or "").replace("|", "\\|").replace("\n", " ")


def tabela(cabecalho, linhas):
    if not linhas:
        return ""
    saida = ["| " + " | ".join(cabecalho) + " |", "|" + " --- |" * len(cabecalho)]
    saida += ["| " + " | ".join(celula(c) for c in linha) + " |" for linha in linhas]
    return "\n".join(saida) + "\n"


def texto_valores(item):
    return f"Valores: {', '.join(item['valores'])}." if item.get("valores") else ""


def descricao_com_valores(item):
    return " ".join(t for t in (item["descricao"], texto_valores(item)) if t)


def markdown_da_api(nome, url, catalogo):
    partes = [f"# {catalogo['titulo'] or nome}\n"]
    partes.append(f"Arquivo de origem: {url}\n")
    detalhes = [f"- Versão: {catalogo['versao']}" if catalogo["versao"] else "",
                f"- Servidor: {', '.join(catalogo['servidores'])}" if catalogo["servidores"] else "",
                f"- Autenticação: {', '.join(catalogo['seguranca'])}" if catalogo["seguranca"] else ""]
    if any(detalhes):
        partes.append("\n".join(d for d in detalhes if d) + "\n")
    if catalogo["descricao"]:
        partes.append(catalogo["descricao"] + "\n")

    partes.append("## Operações\n")
    partes.append(tabela(["Operação", "Grupo", "Resumo"], [
        [f"`{op}`" + (" (obsoleta)" if dados["obsoleta"] else ""), dados["grupo"], dados["resumo"]]
        for op, dados in catalogo["operacoes"].items()
    ]))
    for op, dados in catalogo["operacoes"].items():
        partes.append(f"## {op}\n")
        if dados["obsoleta"]:
            partes.append("Marcada como obsoleta na documentação.\n")
        if dados["resumo"]:
            partes.append(dados["resumo"] + "\n")
        if dados["descricao"] and dados["descricao"] != dados["resumo"]:
            partes.append(dados["descricao"] + "\n")
        if dados["parametros"]:
            partes.append("Parâmetros:\n")
            partes.append(tabela(["Nome", "Onde", "Tipo", "Obrigatório", "Descrição"], [
                [p["nome"], p["local"], p["tipo"], "sim" if p["obrigatorio"] else "", descricao_com_valores(p)]
                for p in dados["parametros"]
            ]))
        for titulo, chave in (("Corpo da requisição", "corpo"), ("Resposta de sucesso", "resposta")):
            if dados[chave]:
                partes.append(f"{titulo}:\n")
                partes.append(tabela(["Campo", "Tipo", "Obrigatório", "Descrição"], [
                    [f"`{c['caminho']}`", c["tipo"], "sim" if c["obrigatorio"] else "", descricao_com_valores(c)]
                    for c in dados[chave]
                ]))
        partes.append(f"Códigos de retorno: {', '.join(dados['status']) or 'não informados'}.\n")
    return "\n".join(partes)


def indice_compacto(catalogos, guias):
    return {
        "apis": {
            nome: {
                "titulo": catalogo["titulo"],
                "versao": catalogo["versao"],
                "servidores": catalogo["servidores"],
                "operacoes": {
                    op: {
                        "resumo": dados["resumo"],
                        "obsoleta": dados["obsoleta"],
                        "parametros": {f"{p['local']}:{p['nome']}": p["tipo"] + ("!" if p["obrigatorio"] else "") for p in dados["parametros"]},
                        "corpo": {c["caminho"]: c["tipo"] for c in dados["corpo"]},
                        "resposta": {c["caminho"]: c["tipo"] for c in dados["resposta"]},
                    }
                    for op, dados in catalogo["operacoes"].items()
                },
            }
            for nome, (_, catalogo) in sorted(catalogos.items())
        },
        "guias": {slug: hashlib.sha256(texto.encode()).hexdigest()[:16] for slug, texto in sorted(guias.items())},
    }


def comparar_dicionarios(anterior, atual, rotulo):
    linhas = [f"{rotulo} novo: `{k}` ({atual[k]})" for k in sorted(atual.keys() - anterior.keys())]
    linhas += [f"{rotulo} removido: `{k}`" for k in sorted(anterior.keys() - atual.keys())]
    linhas += [f"{rotulo} mudou de tipo: `{k}` ({anterior[k]} para {atual[k]})"
               for k in sorted(anterior.keys() & atual.keys()) if anterior[k] != atual[k]]
    return linhas


def comparar(anterior, atual, caminhos_usados):
    """Lista de mudancas em texto. Custo linear no tamanho dos dois indices (so conjuntos e dicts)."""
    def marca(op):
        return " **(usado pelo projeto)**" if any(c in op.split(" ", 1)[-1] for c in caminhos_usados) else ""

    linhas = []
    apis_ant, apis_atu = anterior.get("apis", {}), atual["apis"]
    linhas += [f"API nova: `{n}` ({apis_atu[n]['titulo']}, {len(apis_atu[n]['operacoes'])} operações)" for n in sorted(apis_atu.keys() - apis_ant.keys())]
    linhas += [f"API removida: `{n}`" for n in sorted(apis_ant.keys() - apis_atu.keys())]
    for nome in sorted(apis_ant.keys() & apis_atu.keys()):
        ant, atu = apis_ant[nome], apis_atu[nome]
        if ant["versao"] != atu["versao"]:
            linhas.append(f"`{nome}` mudou de versão: {ant['versao']} para {atu['versao']}")
        if ant["servidores"] != atu["servidores"]:
            linhas.append(f"`{nome}` mudou de servidor: {ant['servidores']} para {atu['servidores']}")
        ops_ant, ops_atu = ant["operacoes"], atu["operacoes"]
        linhas += [f"`{nome}` operação nova: `{op}`{marca(op)}" for op in sorted(ops_atu.keys() - ops_ant.keys())]
        linhas += [f"`{nome}` operação removida: `{op}`{marca(op)}" for op in sorted(ops_ant.keys() - ops_atu.keys())]
        for op in sorted(ops_ant.keys() & ops_atu.keys()):
            o_ant, o_atu = ops_ant[op], ops_atu[op]
            detalhes = []
            if o_atu["obsoleta"] and not o_ant["obsoleta"]:
                detalhes.append("passou a obsoleta")
            detalhes += comparar_dicionarios(o_ant["parametros"], o_atu["parametros"], "parâmetro")
            detalhes += comparar_dicionarios(o_ant["corpo"], o_atu["corpo"], "campo do corpo")
            detalhes += comparar_dicionarios(o_ant["resposta"], o_atu["resposta"], "campo da resposta")
            if detalhes:
                linhas.append(f"`{nome}` `{op}`{marca(op)}: " + "; ".join(detalhes))
    guias_ant, guias_atu = anterior.get("guias", {}), atual["guias"]
    linhas += [f"Guia novo: `{g}`" for g in sorted(guias_atu.keys() - guias_ant.keys())]
    linhas += [f"Guia removido: `{g}`" for g in sorted(guias_ant.keys() - guias_atu.keys())]
    linhas += [f"Guia com texto alterado: `{g}`" for g in sorted(guias_ant.keys() & guias_atu.keys()) if guias_ant[g] != guias_atu[g]]
    return linhas


def registrar_mudancas(pasta, fonte, anterior, atual):
    arquivo = pasta / ARQUIVO_MUDANCAS
    historico = arquivo.read_text(encoding="utf-8").split("\n", 2)[-1] if arquivo.exists() else ""
    total_ops = sum(len(api["operacoes"]) for api in atual["apis"].values())
    if not anterior:
        linhas = [f"Primeira raspagem: {len(atual['apis'])} APIs, {total_ops} operações, {len(atual['guias'])} guias."]
    else:
        linhas = comparar(anterior, atual, fonte.caminhos_usados) or ["Nada mudou desde a raspagem anterior."]
    secao = f"## {date.today().strftime('%d/%m/%Y')}\n\n" + "\n".join(f"- {linha}" for linha in linhas) + "\n\n"
    arquivo.write_text(f"# Mudanças na documentação ({fonte.nome})\n\n" + secao + historico.lstrip("\n"), encoding="utf-8")
    return linhas


def gravar(fonte, catalogos, guias):
    """Regrava a pasta de referencia inteira e devolve as mudancas em relacao a raspagem anterior."""
    pasta = fonte.pasta_referencia
    pasta.mkdir(parents=True, exist_ok=True)
    arquivo_indice = pasta / ARQUIVO_INDICE
    anterior = json.loads(arquivo_indice.read_text(encoding="utf-8")) if arquivo_indice.exists() else {}

    for sub in ("apis", "guias"):
        shutil.rmtree(pasta / sub, ignore_errors=True)
        (pasta / sub).mkdir()
    for nome, (url, catalogo) in catalogos.items():
        (pasta / "apis" / f"{nome}.md").write_text(markdown_da_api(nome, url, catalogo), encoding="utf-8")
    for slug, texto in guias.items():
        (pasta / "guias" / f"{slug}.md").write_text(texto, encoding="utf-8")

    atual = indice_compacto(catalogos, guias)
    linhas_indice = [[f"[{nome}](apis/{nome}.md)", api["titulo"], api["versao"], len(api["operacoes"])]
                     for nome, api in atual["apis"].items()]
    (pasta / "INDICE.md").write_text(
        f"# Índice da documentação ({fonte.nome})\n\n"
        f"Gerado por `scripts/atualizar_documentacao_apis.py` em {date.today().strftime('%d/%m/%Y')} a partir de {fonte.url_indice}. "
        "Não editar à mão: a próxima raspagem sobrescreve.\n\n"
        "## APIs\n\n" + (tabela(["Arquivo", "Título", "Versão", "Operações"], linhas_indice) or "Nenhuma especificação encontrada.\n")
        + "\n## Guias\n\n" + ("\n".join(f"- [{s}](guias/{s}.md)" for s in atual["guias"]) or "Nenhum guia encontrado.") + "\n",
        encoding="utf-8")
    linhas = registrar_mudancas(pasta, fonte, anterior, atual)
    arquivo_indice.write_text(json.dumps(atual, ensure_ascii=False, indent=1, sort_keys=True), encoding="utf-8")
    return linhas
