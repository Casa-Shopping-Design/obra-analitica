import base64
import contextlib
import hashlib
import io
import json
import os
import stat
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import cadastrar_webhooks  # noqa: E402
from cliente_origem import ClienteOrigem, ConfiguracaoOrigem  # noqa: E402

TENANT = "0e000000-0000-4000-8000-0000000000e1"


class ApiFalsa(BaseHTTPRequestHandler):
    recebidas = []
    removidas = []
    status = 200
    status_delete = 200
    existentes = []

    def _responder(self, status, corpo):
        conteudo = json.dumps(corpo).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(conteudo)))
        self.end_headers()
        self.wfile.write(conteudo)

    def do_GET(self):
        ApiFalsa.recebidas.append((self.path, dict(self.headers), None))
        self._responder(200, {"resultSetMetadata": {"count": len(ApiFalsa.existentes)},
                              "results": ApiFalsa.existentes})

    def do_POST(self):
        corpo = self.rfile.read(int(self.headers["Content-Length"]))
        ApiFalsa.recebidas.append((self.path, dict(self.headers), json.loads(corpo)))
        self._responder(ApiFalsa.status, {"id": "hook-teste"} if ApiFalsa.status == 200 else {"eco": "token"})

    def do_DELETE(self):
        ApiFalsa.removidas.append(self.path)
        self._responder(ApiFalsa.status_delete, {})

    def log_message(self, *args):
        pass


class CursorFalso:
    def __init__(self, conexao):
        self.conexao = conexao

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def execute(self, sql, parametros):
        self.conexao.comandos.append((sql, parametros))

    def fetchone(self):
        return ("id-webhook-teste",)


class ConexaoFalsa:
    def __init__(self):
        self.comandos = []
        self.commits = 0

    def cursor(self):
        return CursorFalso(self)

    def commit(self):
        self.commits += 1


class TesteSimulacao(unittest.TestCase):
    def rodar(self, *argumentos):
        saida = io.StringIO()
        with contextlib.redirect_stdout(saida), mock.patch.object(cadastrar_webhooks, "ler_env"), \
                mock.patch("urllib.request.urlopen", side_effect=AssertionError("simulação não usa a rede")):
            cadastrar_webhooks.main(list(argumentos))
        return saida.getvalue()

    def test_crm_grava_arquivo_0600_e_nao_imprime_token(self):
        with tempfile.TemporaryDirectory() as pasta:
            saida = self.rodar("--tenant", TENANT, "--origem", "crm", "--simular",
                               "--url-painel", "https://painel.teste.invalid", "--pasta-saida", pasta)
            arquivo = Path(pasta) / f"webhooks_crm_{TENANT}.txt"
            self.assertEqual(stat.S_IMODE(arquivo.stat().st_mode), 0o600)
            linhas = arquivo.read_text().splitlines()
            self.assertEqual([linha.split("\t")[0] for linha in linhas], ["RS", "RP", "UN", "EV", "CV"])
            token = linhas[0].split("/api/origem/crm/")[1].split("?")[0]
            self.assertGreaterEqual(len(token), 64)
            self.assertNotIn(token, saida)
            self.assertNotIn(token[4:20], saida)
            self.assertIn("funcionalidade=RS", saida)

    def test_erp_simulado_nao_toca_banco_nem_rede(self):
        with mock.patch.dict(sys.modules, {"psycopg": None}):
            saida = self.rodar("--tenant", TENANT, "--origem", "erp", "--simular",
                               "--url-painel", "https://painel.teste.invalid")
        self.assertIn("simulação", saida)
        self.assertIn("/api/origem/erp", saida)

    def test_recusa_url_sem_https(self):
        with self.assertRaises(SystemExit):
            self.rodar("--tenant", TENANT, "--simular", "--url-painel", "http://painel.teste.invalid")

    def test_recusa_tenant_que_nao_e_uuid(self):
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            self.rodar("--tenant", "1; drop table x", "--simular", "--url-painel", "https://painel.teste.invalid")


class TesteCadastroErp(unittest.TestCase):
    def setUp(self):
        ApiFalsa.recebidas = []
        ApiFalsa.removidas = []
        ApiFalsa.status = 200
        ApiFalsa.status_delete = 200
        ApiFalsa.existentes = []
        self.servidor = HTTPServer(("127.0.0.1", 0), ApiFalsa)
        threading.Thread(target=self.servidor.serve_forever, daemon=True).start()
        # Mesma base que a carga usa: o subdomínio, sem /public/api/v1.
        self.url_base = f"http://127.0.0.1:{self.servidor.server_port}/sub"
        self.ambiente = {"ORIGEM_URL_BASE": self.url_base, "ORIGEM_USUARIO": "usuario-teste",
                         "ORIGEM_SENHA": "senha-teste", "ORIGEM_AUTENTICACAO": "basic"}

    def tearDown(self):
        self.servidor.shutdown()
        self.servidor.server_close()

    def cliente(self):
        return ClienteOrigem(ConfiguracaoOrigem.de_ambiente(self.ambiente), dormir=lambda s: None)

    def posts(self):
        return [r for r in ApiFalsa.recebidas if r[2] is not None]

    def test_envia_basic_auth_url_token_e_eventos_na_mesma_base_da_carga(self):
        id_hook, nao_removidos = cadastrar_webhooks.cadastrar_hook_erp(
            self.cliente(), "https://painel.teste.invalid/api/origem/erp", "token-de-teste", ["UNIT_UPDATED"],
        )
        self.assertEqual((id_hook, nao_removidos), ("hook-teste", []))
        caminho, cabecalhos, corpo = self.posts()[0]
        self.assertEqual(caminho, "/sub/public/api/v1/hooks")
        self.assertTrue((self.cliente().base["rest"] + "/hooks").endswith(caminho))
        esperado = base64.b64encode(b"usuario-teste:senha-teste").decode()
        self.assertEqual(cabecalhos["Authorization"], f"Basic {esperado}")
        self.assertEqual(corpo, {
            "url": "https://painel.teste.invalid/api/origem/erp",
            "token": "token-de-teste",
            "events": ["UNIT_UPDATED"],
        })

    def test_remove_hook_antigo_do_mesmo_destino_depois_do_novo(self):
        destino = "https://painel.teste.invalid/api/origem/erp"
        ApiFalsa.existentes = [{"id": "hook-velho", "url": destino},
                               {"id": "hook-de-outra-integracao", "url": "https://outra.invalid/hook"}]
        cadastrar_webhooks.cadastrar_hook_erp(self.cliente(), destino, "token-de-teste", ["UNIT_UPDATED"])
        self.assertEqual(ApiFalsa.removidas, ["/sub/public/api/v1/hooks/hook-velho"])

    def test_hook_antigo_que_nao_sai_vira_aviso(self):
        destino = "https://painel.teste.invalid/api/origem/erp"
        ApiFalsa.existentes = [{"id": "hook-velho", "url": destino}]
        ApiFalsa.status_delete = 400
        _, nao_removidos = cadastrar_webhooks.cadastrar_hook_erp(self.cliente(), destino, "t", ["UNIT_UPDATED"])
        self.assertEqual(nao_removidos, ["hook-velho"])

    def test_erro_do_erp_nao_mostra_token(self):
        ApiFalsa.status = 400
        with self.assertRaises(RuntimeError) as contexto:
            cadastrar_webhooks.cadastrar_hook_erp(self.cliente(), "https://x.invalid", "token-secreto", [])
        self.assertIn("HTTP 400", str(contexto.exception))
        self.assertNotIn("token-secreto", str(contexto.exception))

    def test_grava_hash_desativa_anteriores_e_commita_depois_do_erp(self):
        conexao = ConexaoFalsa()
        argumentos = mock.Mock(url_painel="https://painel.teste.invalid", simular=False, tenant=TENANT)
        with mock.patch.dict(os.environ, self.ambiente), contextlib.redirect_stdout(io.StringIO()) as saida:
            cadastrar_webhooks.processar_erp(argumentos, conexao, "token-de-teste-longo")
        sql, parametros = conexao.comandos[0]
        self.assertIn("insert into app.webhook_origem", sql)
        self.assertEqual(parametros, (TENANT, "erp", hashlib.sha256(b"token-de-teste-longo").hexdigest()))
        sql, parametros = conexao.comandos[1]
        self.assertIn("set ativo = false", sql)
        self.assertEqual(parametros, (TENANT, "erp", "id-webhook-teste"))
        self.assertEqual(conexao.commits, 1)
        self.assertEqual(self.posts()[0][2]["events"], cadastrar_webhooks.EVENTOS_ERP)
        self.assertNotIn("token-de-teste-longo", saida.getvalue())

    def test_erp_recusou_nao_commita_nem_repete_o_post(self):
        ApiFalsa.status = 500
        conexao = ConexaoFalsa()
        argumentos = mock.Mock(url_painel="https://painel.teste.invalid", simular=False, tenant=TENANT)
        with mock.patch.dict(os.environ, self.ambiente), contextlib.redirect_stdout(io.StringIO()), \
                self.assertRaises(RuntimeError):
            cadastrar_webhooks.processar_erp(argumentos, conexao, "token-de-teste-longo")
        self.assertEqual(conexao.commits, 0)
        self.assertEqual(len(self.posts()), 1)

    def test_recusa_base_do_erp_sem_https(self):
        conexao = ConexaoFalsa()
        argumentos = mock.Mock(url_painel="https://painel.teste.invalid", simular=False, tenant=TENANT)
        ambiente = {**self.ambiente, "ORIGEM_URL_BASE": "http://api.teste.invalid/sub"}
        with mock.patch.dict(os.environ, ambiente), contextlib.redirect_stdout(io.StringIO()), \
                self.assertRaises(SystemExit):
            cadastrar_webhooks.processar_erp(argumentos, conexao, "token-de-teste-longo")
        self.assertEqual(conexao.comandos, [])


if __name__ == "__main__":
    unittest.main()
