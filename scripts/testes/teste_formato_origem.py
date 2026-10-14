"""O que a sondagem de 11/10/2026 na API v2 mostrou e a carga passou a tratar: unidade com valor em evaluation e
tabela em specialValues, 403 por recurso não liberado, rota do Bulk na v2 configurável e 404 de rota inexistente."""

import sys
import unittest
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from campos_permitidos import filtrar  # noqa: E402
from carregar_origem import Contexto, Tarefa, cadastro, motivo_falha  # noqa: E402
from cliente_origem import ClienteOrigem, ConfiguracaoOrigem, ErroOrigem, _bulk_indisponivel  # noqa: E402

AMBIENTE_OAUTH = {
    "ORIGEM_AUTENTICACAO": "oauth", "ORIGEM_URL_BASE": "https://api.exemplo.invalid",
    "ORIGEM_TENANT": "base-teste", "ORIGEM_CLIENT_ID": "cliente", "ORIGEM_CLIENT_SECRET": "segredo-de-teste",
}

# Formato da resposta real de group/v2/units, com campos que a carga não guarda.
UNIDADE_API = {
    "id": 501, "enterpriseId": 31, "name": "Apto 101", "propertyType": "Apto", "commercialStock": "D",
    "privateArea": 58.4, "deliveryDate": None, "scheduledDeliveryDate": "2027-03-01", "indexerId": 0,
    "evaluation": {"evaluationDate": "2026-01-10", "evaluationPrice": 150000.0,
                   "saleValueDate": "2026-01-10", "saleValuePrice": 120000.0},
    "specialValues": [{"tablePricesId": 9, "indexedQuantity": 265000.0}],
    "note": "texto livre do cadastro", "address": {"streetName": "Rua do Teste", "number": "10"},
    "legalRegistrationNumber": "123", "latitude": "-9.6", "longitude": "-35.7",
}


class TesteUnidade(unittest.TestCase):
    def test_guarda_valor_tabela_e_entrega_prevista_no_formato_da_api(self):
        guardado = filtrar("units", UNIDADE_API)
        self.assertEqual(guardado["evaluation"], {"saleValueDate": "2026-01-10", "saleValuePrice": 120000.0})
        self.assertEqual(guardado["specialValues"], [{"tablePricesId": 9, "indexedQuantity": 265000.0}])
        self.assertEqual(guardado["scheduledDeliveryDate"], "2027-03-01")

    def test_descarta_texto_livre_endereco_e_registro(self):
        guardado = filtrar("units", UNIDADE_API)
        for campo in ("note", "address", "legalRegistrationNumber", "latitude", "longitude"):
            self.assertNotIn(campo, guardado)
        self.assertNotIn("evaluationPrice", guardado["evaluation"])

    def test_formato_antigo_continua_guardado(self):
        antigo = {"id": 1, "enterpriseId": 31, "saleValuePrice": 300000, "saleValueDate": "2026-02-01",
                  "tablePricesID": 7}
        self.assertEqual(filtrar("units", antigo), antigo)

    def test_unidades_pedem_todos_os_dados_adicionais(self):
        class Cliente:
            def __init__(self):
                self.chamadas = []

            def listar(self, recurso, parametros=None):
                self.chamadas.append((recurso, parametros))
                return iter([])

        cliente = Cliente()
        ctx = Contexto(cliente=cliente, hoje=date(2026, 10, 11), obras=[31])
        list(cadastro(ctx, Tarefa("units", "cadastro", "units", completa=True), None))
        list(cadastro(ctx, Tarefa("cost-centers", "cadastro", "cost-centers", completa=True), None))
        self.assertEqual(cliente.chamadas, [("units", {"additionalData": "ALL"}), ("cost-centers", {})])


class TesteContrato(unittest.TestCase):
    def test_contrato_rest_guarda_o_que_o_staging_le_sem_nome_de_cliente(self):
        contrato = {
            "id": 2019, "enterpriseId": 31, "number": "C-2019", "situation": "Emitido",
            "contractDate": "2026-10-01", "value": 175000.0, "financialInstitutionNumber": None,
            "salesContractUnits": [{"id": 501, "main": True, "name": "Apto 101"}],
            "salesContractCustomers": [{"id": 9, "main": True, "name": "Cliente de Teste"}],
        }
        guardado = filtrar("sales-contracts", contrato)
        self.assertEqual(guardado["situation"], "Emitido")
        self.assertEqual(guardado["salesContractUnits"], [{"id": 501, "main": True, "name": "Apto 101"}])
        self.assertEqual(guardado["salesContractCustomers"], [{"id": 9, "main": True}])


class TesteRotaEPermissao(unittest.TestCase):
    def test_rota_do_bulk_na_v2_vem_da_variavel(self):
        padrao = ClienteOrigem(ConfiguracaoOrigem.de_ambiente(AMBIENTE_OAUTH))
        self.assertEqual(padrao.base["bulk"], "https://api.exemplo.invalid/group/v2/bulk-data/v1")
        outra = ClienteOrigem(ConfiguracaoOrigem.de_ambiente({**AMBIENTE_OAUTH, "ORIGEM_CAMINHO_BULK": "/group/bulk-data/v2/"}))
        self.assertEqual(outra.base["bulk"], "https://api.exemplo.invalid/group/bulk-data/v2")
        self.assertEqual(outra.base["rest"], "https://api.exemplo.invalid/group/v2")
        for invalido in ("../outro", "group/v2/../x", "https://outro.host/bulk", "group v2"):
            with self.assertRaises(ValueError):
                ConfiguracaoOrigem.de_ambiente({**AMBIENTE_OAUTH, "ORIGEM_CAMINHO_BULK": invalido})

    def test_rota_inexistente_do_gateway_tira_o_tenant_do_bulk(self):
        self.assertTrue(_bulk_indisponivel(404, '{"msg":"Unknown endpoint","status":404}'))
        self.assertFalse(_bulk_indisponivel(404, '{"status":404,"developerMessage":"Nenhuma parcela"}'))

    def test_403_diz_qual_recurso_liberar(self):
        motivo = motivo_falha(ErroOrigem(403, "trial-balance"))
        self.assertIn("sem permissão para trial-balance", motivo)
        self.assertIn("usuário de API", motivo)
        self.assertEqual(motivo_falha(ErroOrigem(500, "units")), "500 em units")


if __name__ == "__main__":
    unittest.main()
