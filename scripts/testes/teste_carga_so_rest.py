"""Caminho só REST (ADR 0021): parcelas a receber por título, orçamento por planilha e a carga que roda duas
vezes sem duplicar. A API falsa segue o formato da documentação; parcela, rateio, extrato e orçamento ainda não
têm amostra real."""

import json
import sys
import unittest
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from api_falsa import ApiFalsa  # noqa: E402
from carregar_origem import RepositorioBanco, executar, releitura_adiada, Tarefa  # noqa: E402
from teste_carregar_origem import HOJE, OPCOES, Origem, banco_local, cliente_para  # noqa: E402
from teste_consumo_fila import RepositorioFilaFalso  # noqa: E402

TENANT = "0e000000-0000-4000-8000-0000000000a7"
AMANHA = HOJE + timedelta(days=1)
PARCELAS_RECEBER = "accounts-receivable/receivable-bills/{}/installments"
PLANILHAS = "building-cost-estimations/101/sheets"


def fora_do_rodizio(dia, quantidade, inicio=700):
    """Títulos que o rodízio do dia não pega, para o teste saber o que a noite relê só por motivo."""
    titulos, candidato = [], inicio
    while len(titulos) < quantidade:
        if candidato % 7 != dia.toordinal() % 7:
            titulos.append(candidato)
        candidato += 1
    return titulos


class OrigemSoRest(Origem):
    def __init__(self):
        super().__init__()
        self.titulo_a, self.titulo_b = fora_do_rodizio(AMANHA, 2)
        self.contratos = [
            {"id": 1, "enterpriseId": 101, "situation": "Emitido", "contractDate": "2026-01-10", "value": 300000,
             "receivableBillId": self.titulo_a, "salesContractUnits": [{"id": 1, "main": True}],
             "customers": [{"id": 9, "name": "NOME_PESSOAL"}]},
            {"id": 2, "enterpriseId": 101, "situation": "Emitido", "contractDate": "2026-02-10", "value": 200000,
             "receivableBillId": self.titulo_b, "customers": []},
        ]
        self.parcelas_receber = {
            self.titulo_a: [
                {"receivableBillId": self.titulo_a, "installmentId": 1, "carrierId": 3, "conditionTypeId": "PM",
                 "dueDate": "2026-10-10", "balanceDue": 1000.0, "generatedTicket": True},
                {"receivableBillId": self.titulo_a, "installmentId": 2, "conditionTypeId": "FI",
                 "dueDate": "2026-12-10", "balanceDue": 150000.0},
            ],
            self.titulo_b: [
                {"receivableBillId": self.titulo_b, "installmentId": 1, "conditionTypeId": "PM",
                 "dueDate": "2026-10-15", "balanceDue": 800.0},
            ],
        }
        self.extrato = [
            {"id": 7, "value": 1000.0, "date": "2026-09-10", "type": "Income", "billId": self.titulo_a,
             "installmentNumber": 3, "description": "NOME_PESSOAL", "documentNumber": "123"},
            {"id": 8, "value": 250.0, "date": "2026-09-20", "type": "Expense", "billId": 20,
             "installmentNumber": 1, "statementOrigin": "CP", "statementTypeNotes": "obs livre"},
        ]
        self.planilhas = [{"id": 1, "description": "Torre", "status": "UNLOCKED"},
                          {"id": 2, "description": "Lazer", "status": "UNLOCKED"}]
        self.itens = {
            1: [{"id": "a1", "wbsCode": "01", "description": "Fundação", "totalPrice": 300.0},
                {"id": "a2", "wbsCode": "01.001", "description": "Estaca", "totalPrice": 300.0,
                 "pricesByCategory": [{"category": "MATERIAL", "totalPrice": 300.0}]}],
            2: [{"id": "b1", "wbsCode": "01.001", "description": "Estaca", "totalPrice": 50.0}],
        }

    def rest(self):
        rotas = super().rest()
        rotas["sales-contracts"] = lambda consulta: [
            c for c in self.contratos if c.get("lastUpdateDate", "2026-09-01") >= consulta.get("modifiedAfter", "")]
        rotas["accounts-statements"] = lambda consulta: [
            e for e in self.extrato if consulta["startDate"] <= e["date"] <= consulta["endDate"]]
        rotas.pop("bills/20/buildings-cost")
        for titulo in (self.titulo_a, self.titulo_b):
            rotas[PARCELAS_RECEBER.format(titulo)] = lambda consulta, t=titulo: self.parcelas_receber[t]
        rotas[PLANILHAS] = lambda consulta: self.planilhas
        for planilha in (1, 2):
            rotas[f"{PLANILHAS}/{planilha}/items"] = lambda consulta, p=planilha: self.itens[p]
        return rotas


def rodar(origem, repo, hoje=HOJE, fila=False):
    with ApiFalsa(rest=origem.rest(), bulk=origem.bulk()) as api:
        opcoes = {**OPCOES, "fila_eventos": repo} if fila else OPCOES
        relatorio = executar(cliente_para(api), repo, TENANT, hoje, **opcoes)
        return relatorio, api


def repositorio_so_rest():
    repo = RepositorioFilaFalso()
    repo.modo = (True, datetime.now(timezone.utc))
    return repo


class TesteParcelasReceber(unittest.TestCase):
    def test_primeira_carga_le_cada_titulo_dos_contratos_uma_vez(self):
        origem, repo = OrigemSoRest(), repositorio_so_rest()
        relatorio, api = rodar(origem, repo)
        self.assertEqual((relatorio.caminho, relatorio.falhas), ("so_rest", []))
        self.assertEqual(api.chamadas("bulk"), [])
        for titulo in (origem.titulo_a, origem.titulo_b):
            self.assertEqual(len(api.chamadas("rest", PARCELAS_RECEBER.format(titulo))), 1)
        parcelas = repo.payloads("receivable-bills/installments")
        self.assertEqual(len(parcelas), 3)
        self.assertEqual({p["receivableBillId"] for p in parcelas}, {origem.titulo_a, origem.titulo_b})
        self.assertNotIn("carrierId", json.dumps(parcelas))
        self.assertNotIn("generatedTicket", json.dumps(parcelas))

    def test_segunda_noite_rele_so_o_titulo_com_recebimento_e_nao_duplica(self):
        origem, repo = OrigemSoRest(), repositorio_so_rest()
        rodar(origem, repo)
        antes = repo.contagem()
        origem.extrato = origem.extrato + [
            {"id": 9, "value": 800.0, "date": AMANHA.isoformat(), "type": "Income", "billId": origem.titulo_b,
             "installmentNumber": 1}]
        origem.parcelas_receber[origem.titulo_b] = []
        relatorio, api = rodar(origem, repo, hoje=AMANHA)
        self.assertEqual(relatorio.falhas, [])
        self.assertEqual(api.chamadas("rest", PARCELAS_RECEBER.format(origem.titulo_a)), [],
                         "título sem movimento e fora do rodízio espera outra noite")
        self.assertEqual(len(api.chamadas("rest", PARCELAS_RECEBER.format(origem.titulo_b))), 1)
        restantes = repo.payloads("receivable-bills/installments")
        self.assertEqual(sorted(p.get("installmentId", 0) for p in restantes if p["receivableBillId"] == origem.titulo_b),
                         [0], "parcela quitada que sumiu da resposta sai de raw e fica só o marcador do título")
        self.assertEqual(repo.contagem()["accounts-statements"], antes["accounts-statements"] + 1)
        self.assertEqual(repo.contagem()["receivable-bills/installments"], antes["receivable-bills/installments"])

    def test_titulo_ja_lido_sem_parcela_nao_volta_toda_noite(self):
        origem, repo = OrigemSoRest(), repositorio_so_rest()
        origem.parcelas_receber[origem.titulo_b] = []
        rodar(origem, repo)
        _, api = rodar(origem, repo, hoje=AMANHA)
        self.assertEqual(api.chamadas("rest", PARCELAS_RECEBER.format(origem.titulo_b)), [])

    def test_contrato_novo_tem_o_titulo_lido_na_mesma_noite(self):
        origem, repo = OrigemSoRest(), repositorio_so_rest()
        rodar(origem, repo)
        novo = fora_do_rodizio(AMANHA, 1, inicio=origem.titulo_b + 1)[0]
        origem.contratos.append({"id": 3, "enterpriseId": 101, "situation": "Emitido", "receivableBillId": novo,
                                 "lastUpdateDate": AMANHA.isoformat()})
        origem.parcelas_receber[novo] = [{"receivableBillId": novo, "installmentId": 1, "dueDate": "2027-01-10",
                                          "balanceDue": 500.0}]
        rotas = origem.rest()
        rotas[PARCELAS_RECEBER.format(novo)] = lambda consulta: origem.parcelas_receber[novo]
        with ApiFalsa(rest=rotas, bulk=origem.bulk()) as api:
            executar(cliente_para(api), repo, TENANT, AMANHA, **OPCOES)
        self.assertEqual(len(api.chamadas("rest", PARCELAS_RECEBER.format(novo))), 1)

    def test_aviso_do_webhook_rele_o_titulo_e_sai_da_fila(self):
        origem, repo = OrigemSoRest(), repositorio_so_rest()
        rodar(origem, repo)
        evento = repo.avisar("RECEIVABLE_INSTALLMENT_UPDATED", {"receivableBillId": origem.titulo_a})
        _, api = rodar(origem, repo, hoje=AMANHA, fila=True)
        self.assertEqual(len(api.chamadas("rest", PARCELAS_RECEBER.format(origem.titulo_a))), 1)
        self.assertTrue(repo.eventos[evento]["processado"])
        self.assertEqual(api.chamadas("bulk"), [])


class TesteOrcamentoRest(unittest.TestCase):
    def test_le_cada_planilha_da_obra_e_acrescenta_obra_e_planilha(self):
        origem, repo = OrigemSoRest(), repositorio_so_rest()
        _, api = rodar(origem, repo)
        self.assertEqual(len(api.chamadas("rest", PLANILHAS)), 1)
        itens = repo.payloads("building-cost-estimations/items")
        self.assertEqual(sorted((i["buildingUnitId"], i["wbsCode"]) for i in itens),
                         [(1, "01"), (1, "01.001"), (2, "01.001")])
        self.assertTrue(all(i["buildingId"] == 101 for i in itens))
        self.assertNotIn("pricesByCategory", json.dumps(itens))

    def test_releitura_semanal_e_antecipada_pelo_webhook(self):
        origem, repo = OrigemSoRest(), repositorio_so_rest()
        rodar(origem, repo)
        _, api = rodar(origem, repo, hoje=AMANHA)
        self.assertEqual(api.chamadas("rest", PLANILHAS), [], "orçamento lido ontem não gasta cota hoje")
        self.assertEqual(repo.marcas[(TENANT, "building-cost-estimations/items")], HOJE)

        evento = repo.avisar("BUILDING_COST_ESTIMATION_UPDATED", {"buildingId": 101})
        origem.itens[2] = []
        _, api = rodar(origem, repo, hoje=AMANHA + timedelta(days=1), fila=True)
        self.assertEqual(len(api.chamadas("rest", PLANILHAS)), 1)
        self.assertTrue(repo.eventos[evento]["processado"])
        self.assertEqual(sorted(i["wbsCode"] for i in repo.payloads("building-cost-estimations/items")),
                         ["01", "01.001"], "planilha esvaziada na origem sai de raw")

        _, api = rodar(origem, repo, hoje=AMANHA + timedelta(days=9))
        self.assertEqual(len(api.chamadas("rest", PLANILHAS)), 1, "sete dias depois relê sem aviso")

    def test_aviso_fica_pendente_quando_a_releitura_falha(self):
        origem, repo = OrigemSoRest(), repositorio_so_rest()
        rodar(origem, repo)
        evento = repo.avisar("BUILDING_COST_ESTIMATION_UPDATED", {"buildingId": 101})
        rotas = origem.rest()
        rotas.pop(PLANILHAS)
        with ApiFalsa(rest=rotas, bulk=origem.bulk(),
                      rotas={PLANILHAS: lambda *_: (500, {"status": 500})}) as api:
            relatorio = executar(cliente_para(api, tentativas=1), repo, TENANT, AMANHA, fila_eventos=repo, **OPCOES)
        self.assertIn("building-cost-estimations/items", [e for e, _ in relatorio.falhas])
        self.assertFalse(repo.eventos[evento]["processado"])

    def test_intervalo_so_vale_com_marca(self):
        tarefa = Tarefa("x", "orcamento_rest", "x", intervalo_dias=7)
        self.assertFalse(releitura_adiada(tarefa, None, HOJE, set()))
        self.assertTrue(releitura_adiada(tarefa, HOJE - timedelta(days=6), HOJE, set()))
        self.assertFalse(releitura_adiada(tarefa, HOJE - timedelta(days=7), HOJE, set()))
        self.assertFalse(releitura_adiada(Tarefa("y", "cadastro", "y"), HOJE, HOJE, set()))


class TesteTitulosPagarRest(unittest.TestCase):
    def test_rateio_vazio_grava_so_o_titulo_para_trocar_o_grupo(self):
        origem, repo = OrigemSoRest(), repositorio_so_rest()
        rodar(origem, repo)
        self.assertEqual(repo.payloads("bills/buildings-cost"), [{"billId": 20}])
        self.assertNotIn("obs livre", json.dumps(repo.payloads("accounts-statements")))
        self.assertNotIn("NOME_PESSOAL", json.dumps(repo.payloads("accounts-statements")))


@unittest.skipUnless(banco_local(), "DATABASE_URL local não definida")
class TesteBancoLocalSoRest(unittest.TestCase):
    """Duas noites só REST contra o Supabase local: raw e staging ficam iguais, e o staging tem a pagar, pago,
    a receber, recebido e orçamento."""

    def setUp(self):
        import psycopg
        self.conexao = psycopg.connect(banco_local(), autocommit=True)
        self.tenant = str(uuid.uuid4())
        self.conexao.execute("insert into app.tenant (id, razao_social) values (%s, 'Teste só REST')", (self.tenant,))
        self.conexao.execute("insert into app.centro_custo (tenant_id, id_origem, nome) values (%s, 101, 'Obra A')",
                             (self.tenant,))

    def tearDown(self):
        self.conexao.execute("delete from app.tenant where id = %s", (self.tenant,))
        self.conexao.close()

    def contar(self):
        consulta = """
          select 'raw:' || endpoint, count(*) from raw.registro where tenant_id = %(t)s group by endpoint
          union all select 'titulo_pagar', count(*) from staging.titulo_pagar where tenant_id = %(t)s
          union all select 'rateio_titulo', count(*) from staging.rateio_titulo where tenant_id = %(t)s
          union all select 'pagamento', count(*) from staging.pagamento where tenant_id = %(t)s
          union all select 'parcela_receber', count(*) from staging.parcela_receber where tenant_id = %(t)s
          union all select 'recebimento', count(*) from staging.recebimento where tenant_id = %(t)s
          union all select 'item_orcamento', count(*) from staging.item_orcamento where tenant_id = %(t)s
          union all select 'contrato_venda', count(*) from staging.contrato_venda where tenant_id = %(t)s"""
        return dict(self.conexao.execute(consulta, {"t": self.tenant}).fetchall())

    def test_duas_noites_so_rest_nao_duplicam(self):
        origem = OrigemSoRest()
        repo = RepositorioBanco(self.conexao)
        repo.gravar_modo(self.tenant, True)
        with ApiFalsa(rest=origem.rest(), bulk=origem.bulk()) as api:
            primeira = executar(cliente_para(api), repo, self.tenant, HOJE, **OPCOES)
            antes = self.contar()
            segunda = executar(cliente_para(api), repo, self.tenant, AMANHA, **OPCOES)
            depois = self.contar()
            terceira = executar(cliente_para(api), repo, self.tenant, AMANHA + timedelta(days=1), **OPCOES)
        self.assertEqual((primeira.falhas, segunda.falhas, terceira.falhas), ([], [], []))
        self.assertEqual(depois, antes)
        self.assertEqual(self.contar(), antes)
        self.assertEqual(api.chamadas("bulk"), [])
        self.assertEqual({k: antes[k] for k in ("titulo_pagar", "rateio_titulo", "pagamento", "parcela_receber",
                                                "recebimento", "item_orcamento", "contrato_venda")},
                         {"titulo_pagar": 1, "rateio_titulo": 0, "pagamento": 1, "parcela_receber": 4,
                          "recebimento": 1, "item_orcamento": 1, "contrato_venda": 2})
        orcado = self.conexao.execute("select codigo, valor_total from staging.item_orcamento where tenant_id = %s",
                                      (self.tenant,)).fetchall()
        self.assertEqual([(c, float(v)) for c, v in orcado], [("01.001", 350.0)],
                         "etapa fica fora e o mesmo código nas duas planilhas é somado")


if __name__ == "__main__":
    unittest.main()
