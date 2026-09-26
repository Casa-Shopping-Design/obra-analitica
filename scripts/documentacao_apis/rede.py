"""Clientes HTTP para baixar a documentacao: urllib direto ou navegador headless.

O navegador existe porque paginas montadas por JavaScript so revelam os
arquivos de especificacao depois de rodar, e alguns portais recusam cliente
que nao parece navegador.
"""

import time
import urllib.error
import urllib.request

PAUSA = 0.4
AGENTE = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"


class ClienteHttp:
    def __init__(self):
        self.ja_baixados = {}

    def baixar(self, url, tentativas=3):
        """Devolve (status, texto). Guarda em memoria para nao pedir a mesma URL duas vezes."""
        if url in self.ja_baixados:
            return self.ja_baixados[url]
        resposta = (0, "")
        for tentativa in range(tentativas):
            req = urllib.request.Request(url, headers={"User-Agent": AGENTE, "Accept": "*/*"})
            try:
                with urllib.request.urlopen(req, timeout=60) as resp:
                    resposta = (resp.status, resp.read().decode("utf-8", errors="replace"))
                    break
            except urllib.error.HTTPError as erro:
                resposta = (erro.code, "")
                if erro.code != 429:
                    break
                time.sleep(int(erro.headers.get("Retry-After", "30")))
            except (urllib.error.URLError, TimeoutError) as erro:
                resposta = (0, str(getattr(erro, "reason", erro)))
                time.sleep(2 ** tentativa)
        time.sleep(PAUSA)
        self.ja_baixados[url] = resposta
        return resposta

    def abrir_pagina(self, url):
        """Devolve (html, urls carregadas pela pagina). Sem navegador so ha o html."""
        status, texto = self.baixar(url)
        return (texto if status == 200 else ""), []

    def fechar(self):
        pass


class ClienteNavegador(ClienteHttp):
    def __init__(self):
        super().__init__()
        try:
            from playwright.sync_api import sync_playwright
        except ImportError:
            raise SystemExit("Modo --navegador precisa do Playwright: pip install playwright && playwright install chromium")
        self.playwright = sync_playwright().start()
        self.navegador = self.playwright.chromium.launch()
        self.contexto = self.navegador.new_context(user_agent=AGENTE)

    def baixar(self, url, tentativas=3):
        if url in self.ja_baixados:
            return self.ja_baixados[url]
        resposta = (0, "")
        for tentativa in range(tentativas):
            try:
                resp = self.contexto.request.get(url, timeout=60000)
                resposta = (resp.status, resp.text())
                if resp.status != 429:
                    break
                time.sleep(30)
            except Exception as erro:
                resposta = (0, str(erro))
                time.sleep(2 ** tentativa)
        time.sleep(PAUSA)
        self.ja_baixados[url] = resposta
        return resposta

    def abrir_pagina(self, url):
        pagina = self.contexto.new_page()
        carregadas = []
        pagina.on("response", lambda resp: carregadas.append(resp.url))
        try:
            pagina.goto(url, wait_until="networkidle", timeout=90000)
            html = pagina.content()
        except Exception:
            html = ""
        finally:
            pagina.close()
        return html, carregadas

    def fechar(self):
        self.navegador.close()
        self.playwright.stop()
