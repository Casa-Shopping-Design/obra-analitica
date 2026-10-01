"""Resumo semanal por e-mail: cada usuário recebe os alertas e os números das obras que ele vê no painel.

Sem argumento de envio, só grava a prévia em HTML, um arquivo por usuário, no diretório de --previa.
Com --enviar, manda pelo Resend. O log sai em JSON e só tem contagens.

    python scripts/enviar_resumo_semanal.py --previa /tmp/resumo
    python scripts/enviar_resumo_semanal.py --enviar
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path

import psycopg
from dotenv import load_dotenv

from resumo_semanal_dados import coletar, periodo_do_resumo
from resumo_semanal_email import FUSO, assunto, montar_html, montar_texto

URL_RESEND = "https://api.resend.com/emails"
# O plano gratuito do Resend aceita 2 requisições por segundo.
INTERVALO_ENVIO_S = 0.6
TENTATIVAS = 3
TEMPO_LIMITE_S = 20


class ErroEnvio(Exception):
    def __init__(self, status):
        super().__init__(f"Resend respondeu {status}")
        self.status = status


def registrar(evento, **contagens):
    print(json.dumps({"evento": evento, **contagens}, ensure_ascii=False), flush=True)


def ler_argumentos(argv=None):
    parser = argparse.ArgumentParser(description="Gera ou envia o resumo semanal das obras.")
    parser.add_argument("--previa", type=Path, help="diretório onde gravar um HTML por usuário")
    parser.add_argument("--enviar", action="store_true", help="manda os e-mails pelo Resend")
    argumentos = parser.parse_args(argv)
    if not argumentos.enviar and argumentos.previa is None:
        parser.error("informe --previa DIRETORIO ou --enviar")
    return argumentos


def nome_arquivo_previa(destinatario):
    # Sem e-mail no nome: o diretório da prévia pode acabar anexado num chamado ou num print.
    return f"{destinatario.perfil}_{destinatario.user_id[:8]}_{destinatario.tenant_id[:8]}.html"


def enviar_pelo_resend(chave_api, remetente, para, assunto_email, html, texto, chave_idempotencia,
                       abrir=urllib.request.urlopen, esperar=time.sleep):
    """Manda um e-mail. A chave de idempotência faz o Resend ignorar a repetição se o job rodar de novo no dia."""
    corpo = json.dumps({"from": remetente, "to": [para], "subject": assunto_email, "html": html, "text": texto}).encode()
    requisicao = urllib.request.Request(URL_RESEND, data=corpo, method="POST", headers={
        "Authorization": f"Bearer {chave_api}",
        "Content-Type": "application/json",
        "Idempotency-Key": chave_idempotencia,
        "User-Agent": "obra-analitica-resumo/1",
    })
    for tentativa in range(1, TENTATIVAS + 1):
        try:
            with abrir(requisicao, timeout=TEMPO_LIMITE_S) as resposta:
                return resposta.status
        except urllib.error.HTTPError as erro:
            erro.close()
            if (erro.code != 429 and erro.code < 500) or tentativa == TENTATIVAS:
                raise ErroEnvio(erro.code) from None
            espera = erro.headers.get("Retry-After") if erro.headers else None
            esperar(float(espera) if espera and espera.isdigit() else 2 ** tentativa)
        except urllib.error.URLError:
            if tentativa == TENTATIVAS:
                raise ErroEnvio("sem_conexao") from None
            esperar(2 ** tentativa)
    raise ErroEnvio("sem_resposta")


def variavel_obrigatoria(nome):
    valor = os.environ.get(nome, "").strip()
    if not valor:
        registrar("configuracao_incompleta", variavel=nome)
        sys.exit(2)
    return valor


def ler_painel_url_base(enviar):
    valor = os.environ.get("PAINEL_URL_BASE", "").strip()
    if not valor and not enviar:
        return "http://localhost:3000"
    if not valor:
        variavel_obrigatoria("PAINEL_URL_BASE")
    if enviar and urllib.parse.urlsplit(valor).scheme != "https":
        registrar("configuracao_incompleta", variavel="PAINEL_URL_BASE", motivo="precisa ser https")
        sys.exit(2)
    return valor


def coletar_do_banco(periodo):
    with psycopg.connect(os.environ["DATABASE_URL"]) as conexao:
        conexao.execute("set transaction read only")
        conexao.execute("set local statement_timeout = '60s'")
        coleta = coletar(conexao, periodo)
        conexao.rollback()
    return coleta


def main(argv=None):
    load_dotenv()
    argumentos = ler_argumentos(argv)
    painel_url_base = ler_painel_url_base(argumentos.enviar)
    if argumentos.enviar:
        chave_api = variavel_obrigatoria("RESEND_API_KEY")
        remetente = variavel_obrigatoria("RESUMO_REMETENTE")
    agora = datetime.now(FUSO)
    periodo = periodo_do_resumo(agora.date())
    try:
        coleta = coletar_do_banco(periodo)
    except psycopg.Error as erro:
        # Só a classe e o SQLSTATE: a mensagem do banco pode trazer valores das linhas.
        registrar("falha_banco", erro=type(erro).__name__, codigo=getattr(erro, "sqlstate", None))
        return 1

    if argumentos.previa:
        argumentos.previa.mkdir(parents=True, exist_ok=True)
    enviados = falhas = 0
    status_falhas = {}
    for indice, pacote in enumerate(coleta.pacotes):
        html = montar_html(pacote.obras, periodo, painel_url_base, agora)
        if argumentos.previa:
            (argumentos.previa / nome_arquivo_previa(pacote.destinatario)).write_text(html, encoding="utf-8")
        if not argumentos.enviar:
            continue
        if indice:
            time.sleep(INTERVALO_ENVIO_S)
        chave = f"resumo-semanal-{periodo.hoje:%Y-%m-%d}-{pacote.destinatario.user_id}-{pacote.destinatario.tenant_id}"
        try:
            enviar_pelo_resend(chave_api, remetente, pacote.destinatario.email, assunto(pacote.obras, periodo), html,
                               montar_texto(pacote.obras, periodo, painel_url_base, agora), chave)
            enviados += 1
        except ErroEnvio as erro:
            falhas += 1
            status_falhas[str(erro.status)] = status_falhas.get(str(erro.status), 0) + 1

    registrar(
        "resumo_semanal",
        modo="envio" if argumentos.enviar else "previa",
        destinatarios=coleta.destinatarios,
        com_resumo=len(coleta.pacotes),
        sem_obra=coleta.sem_obra,
        divergentes_rls=coleta.divergentes,
        obras_no_resumo=sum(len(pacote.obras) for pacote in coleta.pacotes),
        alertas_no_resumo=sum(len(obra.alertas) for pacote in coleta.pacotes for obra in pacote.obras),
        enviados=enviados,
        falhas=falhas,
        status_falhas=status_falhas,
    )
    # Divergência entre o filtro e o RLS é defeito: o job fica vermelho para alguém olhar.
    return 1 if falhas or coleta.divergentes else 0


if __name__ == "__main__":
    sys.exit(main())
