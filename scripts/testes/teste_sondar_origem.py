import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import sondar_origem  # noqa: E402
from api_falsa import ApiFalsa  # noqa: E402

EMPRESAS = {"companies": [{"id": 7, "name": "Empresa A"}], "units": [{"id": 1, "enterpriseId": 3}]}


def sondar(ambiente, argumentos):
    """Roda a sondagem com o .env do teste e uma pasta temporária; devolve o relatório gravado."""
    with tempfile.TemporaryDirectory() as pasta, \
            mock.patch.dict(os.environ, ambiente, clear=True), \
            mock.patch.object(sondar_origem, "PASTA_BRUTOS", Path(pasta)), \
            mock.patch.object(sondar_origem, "RAIZ", Path(pasta)), \
            mock.patch.object(sondar_origem, "PAUSA", 0), \
            mock.patch.object(sondar_origem.time, "sleep", lambda _: None), \
            mock.patch.object(sys, "argv", ["sondar_origem.py", *argumentos]), \
            contextlib.redirect_stdout(io.StringIO()):
        sondar_origem.main()
        return json.loads((Path(pasta) / "_relatorio_sondagem.json").read_text(encoding="utf-8"))


class TesteSondagem(unittest.TestCase):
    def test_basic_usa_os_caminhos_da_v1(self):
        with ApiFalsa(rest=EMPRESAS) as api:
            relatorio = sondar({"ORIGEM_URL_BASE": api.url_base, "ORIGEM_AUTENTICACAO": "basic",
                                "ORIGEM_USUARIO": "usuario-teste", "ORIGEM_SENHA": "senha-teste"},
                               ["--so", "companies"])
            pedidos_token = api.chamadas(caminho="auth/token")
        self.assertEqual([(r["recurso"], r["formato"], r["status"]) for r in relatorio], [("companies", "v1", 200)])
        self.assertTrue(relatorio[0]["url"].endswith("/public/api/v1/companies"))
        self.assertEqual(pedidos_token, [])

    def test_basic_manda_bulk_para_o_prefixo_da_v1(self):
        with ApiFalsa(bulk={"income": [{"id": 1}]}) as api:
            relatorio = sondar({"ORIGEM_URL_BASE": api.url_base, "ORIGEM_AUTENTICACAO": "basic",
                                "ORIGEM_USUARIO": "usuario-teste", "ORIGEM_SENHA": "senha-teste"},
                               ["--so", "bulk-income"])
        self.assertTrue(relatorio[0]["url"].endswith("/public/api/bulk-data/v1/income"))
        self.assertEqual(relatorio[0]["status"], 200)

    def test_oauth_continua_na_v2(self):
        with ApiFalsa(rest=EMPRESAS) as api:
            relatorio = sondar({"ORIGEM_URL_BASE": api.url_base, "ORIGEM_AUTENTICACAO": "oauth",
                                "ORIGEM_TENANT": "casa", "ORIGEM_CLIENT_ID": "cliente-teste",
                                "ORIGEM_CLIENT_SECRET": "segredo-teste"}, ["--so", "companies"])
        self.assertEqual([(r["recurso"], r["formato"], r["status"]) for r in relatorio], [("companies", "v2", 200)])
        self.assertTrue(relatorio[0]["url"].endswith("/group/v2/companies"))

    def test_basic_sem_senha_para_antes_de_chamar(self):
        with self.assertRaises(SystemExit) as saida:
            sondar({"ORIGEM_URL_BASE": "https://api.teste.invalid/casa", "ORIGEM_AUTENTICACAO": "basic",
                    "ORIGEM_USUARIO": "u"}, [])
        self.assertIn("ORIGEM_SENHA", str(saida.exception))

    def test_senha_nao_vai_para_o_relatorio(self):
        with ApiFalsa(rest=EMPRESAS) as api:
            relatorio = sondar({"ORIGEM_URL_BASE": api.url_base, "ORIGEM_AUTENTICACAO": "basic",
                                "ORIGEM_USUARIO": "usuario-teste", "ORIGEM_SENHA": "senha-teste"},
                               ["--so", "companies"])
        self.assertNotIn("senha-teste", json.dumps(relatorio))

    def test_timeout_de_leitura_vira_status_zero_sem_derrubar(self):
        with mock.patch.object(sondar_origem.urllib.request, "urlopen", side_effect=TimeoutError) as abrir, \
                mock.patch.object(sondar_origem.time, "sleep", lambda _: None), \
                contextlib.redirect_stdout(io.StringIO()):
            status, texto, _ = sondar_origem.chamar("GET", "https://api.teste.invalid/casa", {})
        self.assertEqual(status, 0)
        self.assertIn("TimeoutError", texto)
        self.assertEqual(abrir.call_count, 3)


if __name__ == "__main__":
    unittest.main()
