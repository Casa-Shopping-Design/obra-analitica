import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from api_falsa import ApiFalsa  # noqa: E402
from testar_credencial_origem import conclusao, testar  # noqa: E402

EMPRESAS = {"companies": [{"id": 1, "name": "Empresa A"}]}


def status_por_forma(resultados):
    return {forma: status for forma, status, _, _ in resultados}


class TesteCredencial(unittest.TestCase):
    def test_usuario_de_api_entra_pela_v1(self):
        with ApiFalsa(rest=EMPRESAS) as api:
            resultados = testar(api.url_base, api.url_base, "casa", "usuario-teste", "senha-teste")
        self.assertEqual(status_por_forma(resultados), {"Basic, API v1": 200, "Token OAuth, API v2": 401})
        self.assertIn("ORIGEM_AUTENTICACAO=basic", conclusao(resultados, "casa", "usuario-teste", "https://g"))

    def test_credencial_da_v2_pega_token_e_le_empresas(self):
        with ApiFalsa(rest=EMPRESAS, cliente_oauth="cliente-v2", segredo_oauth="segredo-v2") as api:
            resultados = testar(api.url_base, api.url_base, "casa", "cliente-v2", "segredo-v2")
            pedido_token = api.chamadas(caminho="auth/token")
        self.assertEqual(status_por_forma(resultados), {"Basic, API v1": 401, "Token OAuth, API v2": 200})
        self.assertEqual(len(pedido_token), 1)
        self.assertIn("ORIGEM_AUTENTICACAO=oauth", conclusao(resultados, "casa", "cliente-v2", "https://g"))

    def test_senha_errada_aponta_login_de_tela(self):
        with ApiFalsa(rest=EMPRESAS) as api:
            resultados = testar(api.url_base, api.url_base, "casa", "usuario-teste", "errada")
        self.assertEqual(set(status_por_forma(resultados).values()), {401})
        self.assertIn("login de tela", conclusao(resultados, "casa", "usuario-teste", "https://g"))

    def test_sem_permissao_conta_como_usuario_de_api(self):
        def proibido(metodo, consulta, corpo, autorizacao):
            return 403, {"clientMessage": "recurso nao liberado"}

        with ApiFalsa(rotas={"companies": proibido}) as api:
            resultados = testar(api.url_base, api.url_base, "casa", "usuario-teste", "senha-teste")
        self.assertEqual(resultados[0][1], 403)
        self.assertEqual(resultados[0][3], "recurso nao liberado")
        self.assertIn("É usuário de API", conclusao(resultados, "casa", "usuario-teste", "https://g"))

    def test_sem_rede_nao_culpa_a_senha(self):
        resultados = testar("http://127.0.0.1:9", "http://127.0.0.1:9", "casa", "u", "s")
        self.assertEqual(set(status_por_forma(resultados).values()), {0})
        self.assertIn("Nenhuma chamada chegou", conclusao(resultados, "casa", "u", "https://g"))

    def test_senha_nao_aparece_no_resultado(self):
        with ApiFalsa(rest=EMPRESAS) as api:
            resultados = testar(api.url_base, api.url_base, "casa", "usuario-teste", "senha-teste")
        texto = repr(resultados) + conclusao(resultados, "casa", "usuario-teste", "https://g")
        self.assertNotIn("senha-teste", texto)


if __name__ == "__main__":
    unittest.main()
