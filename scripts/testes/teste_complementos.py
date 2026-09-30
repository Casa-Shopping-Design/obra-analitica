import json
import logging
import sys
import unittest
import uuid
from collections import defaultdict
from datetime import date, timedelta
from decimal import Decimal
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import gerar_dados_complementares as gerador  # noqa: E402
import gerar_dados_demo  # noqa: E402
from api_falsa import ApiFalsa  # noqa: E402
from campos_permitidos import filtrar  # noqa: E402
from carregar_origem import PLANO_BULK, RepositorioBanco, executar  # noqa: E402
from teste_carregar_origem import HOJE, OPCOES, TENANT, Origem, RepositorioFalso, banco_local, cliente_para  # noqa: E402

for nome in ("cliente_origem", "carregar_origem"):
    logging.getLogger(nome).addHandler(logging.NullHandler())

MAPA = "real-estate-map"
ITENS = "building-projects/progress-logs/items"
AGING = "defaulters-receivable-bills/by-aging"
NOME_CLIENTE = "Cliente Inadimplente Teste"


def mapa(obra, mes_ano, vgv=1000.0):
    return {"enterpriseData": {"companyId": 1, "companyName": "Construtora", "enterpriseId": obra,
                               "enterpriseName": "Obra A", "units": 2, "monthYear": mes_ano},
            "vgvData": {"vgv": vgv, "poc": 40.0},
            "budgetedAndIncurredCost": {"budgetedCost": 500.0, "accumulatedIncurredCost": 200.0},
            "margin": {"grossProfit": 10.0, "(%)": 0.1}}


def titulo_inadimplente(titulo, dias, obra=101):
    return {"companyId": 1, "clientId": 77, "clientName": NOME_CLIENTE, "receivableBillId": titulo,
            "documentNumber": "CT.123", "costCentersId": [obra], "units": "2Q-0101", "receivableBillValue": 1000.0,
            "defaulterInstallments": [{"installmentId": 1, "daysOfDelay": dias, "dueDate": "2026-08-01",
                                       "correctedValueWithoutAdditions": "100.00",
                                       "installmentSentToSPCSerasa": "S"}],
            "defaulterJudicialActivities": [{"observation": "cliente prometeu pagar", "situation": "C"}]}


class OrigemComplementos(Origem):
    """Origem da carga do N2 com as três rotas complementares."""

    def __init__(self):
        super().__init__()
        self.mapas = [mapa(101, "08/2026"), mapa(101, "09/2026")]
        self.inadimplentes = [titulo_inadimplente(501, 10), titulo_inadimplente(502, 95)]
        self.centros = [{"id": 101, "name": "Obra A", "idCompany": 1}]

    def rest(self):
        rotas = super().rest()
        rotas["cost-centers"] = self.centros
        rotas[MAPA] = lambda consulta: self.mapas
        rotas["building-projects/progress-logs"] = [
            {"buildingId": 101, "measurementNumber": 1, "date": "2026-09-15", "responsibleId": "R1",
             "responsibleName": "Engenheiro Responsavel", "consistent": True, "statusApproval": "APROVADA"},
            {"buildingId": 999, "measurementNumber": 1, "date": "2026-09-15", "statusApproval": "APROVADA"},
        ]
        rotas["building-projects/101/progress-logs/1/items/7"] = [
            {"taskId": 1, "summary": False, "description": "Alvenaria", "plannedQuantity": 100.0,
             "cumulativeMeasuredQuantity": 40.0, "unitPrice": 10.0},
            {"taskId": 2, "summary": True, "description": "Estrutura", "plannedQuantity": 1.0},
        ]
        return rotas

    def bulk(self):
        rotas = super().bulk()
        rotas[AGING] = lambda consulta: self.inadimplentes if consulta.get("companyId") == "1" else []
        return rotas


def detalhe_medicao(metodo, consulta, corpo, autorizacao):
    return 200, {"buildingId": 101, "measurementNumber": 1, "notes": "texto livre",
                 "buildingUnits": [{"id": 7.0, "description": "Bloco A"}]}


ROTAS = {"building-projects/101/progress-logs/1": detalhe_medicao}


def posicao_gravada():
    """Data de posição do arquivo gerado; o gerador usa o dia em que rodou, que pode não ser hoje."""
    aging = json.loads((gerador.PASTA_SAIDA / gerador.ARQUIVOS[AGING]).read_text(encoding="utf-8"))["data"]
    return date.fromisoformat(aging[0]["positionDate"])


class TesteCamposComplementos(unittest.TestCase):
    def test_inadimplencia_sem_cliente_spc_nem_observacao(self):
        filtrado = filtrar(AGING, {**titulo_inadimplente(1, 10), "positionDate": "2026-09-28"})
        texto = json.dumps(filtrado, ensure_ascii=False)
        for proibido in (NOME_CLIENTE, "clientId", "2Q-0101", "CT.123", "SPC", "prometeu"):
            self.assertNotIn(proibido, texto)
        self.assertEqual(filtrado["positionDate"], "2026-09-28")
        self.assertEqual(filtrado["defaulterInstallments"][0]["daysOfDelay"], 10)

    def test_mapa_sem_nome_e_com_margem_percentual(self):
        filtrado = filtrar(MAPA, mapa(101, "08/2026"))
        self.assertNotIn("companyName", filtrado["enterpriseData"])
        self.assertNotIn("enterpriseName", filtrado["enterpriseData"])
        self.assertEqual(filtrado["margin"]["(%)"], 0.1)

    def test_item_de_medicao_sem_responsavel(self):
        filtrado = filtrar(ITENS, {"taskId": 1, "responsibleName": "Engenheiro", "notes": "obs"})
        self.assertEqual(filtrado, {"taskId": 1})


class TesteGerador(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.obras = gerador.ler("cost-centers.json")
        cls.contratos = gerador.ler("sales.json")
        cls.itens = gerador.ler("building-cost-estimation-items.json")
        cls.parcelas = gerador.ler("income.json")
        cls.data_posicao = posicao_gravada()
        cls.gerados = gerador.gerar(cls.obras, cls.contratos, gerador.ler("units.json"), cls.itens,
                                    cls.parcelas, cls.data_posicao)

    def test_arquivos_gravados_sao_os_do_gerador(self):
        for endpoint, registros in self.gerados.items():
            arquivo = gerador.PASTA_SAIDA / gerador.ARQUIVOS[endpoint]
            self.assertEqual(json.loads(arquivo.read_text(encoding="utf-8"))["data"], registros, endpoint)

    def test_registro_gerado_passa_inteiro_pela_lista_de_permitidos(self):
        for endpoint, registros in self.gerados.items():
            for registro in registros:
                self.assertEqual(filtrar(endpoint, registro), registro, endpoint)

    def test_mapa_fecha_com_o_orcamento_e_cresce_no_tempo(self):
        orcado = defaultdict(float)
        for item in self.itens:
            orcado[item["buildingId"]] += item["totalPrice"]
        por_obra = defaultdict(list)
        for registro in self.gerados[MAPA]:
            por_obra[registro["enterpriseData"]["enterpriseId"]].append(registro)
        self.assertEqual(set(por_obra), {o["id"] for o in self.obras})
        for obra, registros in por_obra.items():
            custos = [r["budgetedAndIncurredCost"] for r in registros]
            self.assertTrue(all(abs(c["budgetedCost"] - orcado[obra]) < 0.01 for c in custos))
            incorridos = [c["accumulatedIncurredCost"] for c in custos]
            self.assertEqual(incorridos, sorted(incorridos))
            recebidos = [r["accumulatedReceipts"]["accumulatedReceipt"] for r in registros]
            self.assertEqual(recebidos, sorted(recebidos))
        entregue = por_obra[103][-1]["budgetedAndIncurredCost"]
        self.assertEqual(entregue["accumulatedIncurredCost"], entregue["budgetedCost"])
        estouro = por_obra[102][-1]["budgetedAndIncurredCost"]
        self.assertLess(estouro["costToIncur"], 0.05 * estouro["budgetedCost"])

    def test_orcamento_em_centavos_fecha_no_total_da_obra(self):
        total = defaultdict(Decimal)
        for item in self.itens:
            valor = Decimal(repr(item["totalPrice"]))
            self.assertEqual(valor, valor.quantize(Decimal("0.01")), item["wbsCode"])
            total[item["buildingId"]] += valor
        self.assertEqual(dict(total), {o["id"]: Decimal(o["orcamento"]) for o in gerar_dados_demo.OBRAS})

    def test_medicao_acumulada_nao_recua_e_nao_passa_do_planejado(self):
        ultimo = {}
        for item in self.gerados[ITENS]:
            chave = (item["buildingId"], item["taskId"])
            self.assertLessEqual(item["cumulativeMeasuredQuantity"], item["plannedQuantity"])
            self.assertGreaterEqual(item["cumulativeMeasuredQuantity"], ultimo.get(chave, 0.0))
            ultimo[chave] = item["cumulativeMeasuredQuantity"]
        situacoes = {(i["buildingId"], i["statusApproval"]) for i in self.gerados[ITENS]}
        self.assertIn((101, "EM_APROVACAO"), situacoes)
        self.assertNotIn((102, "EM_APROVACAO"), situacoes)

    def test_inadimplencia_coerente_com_a_posicao(self):
        contratos = {c["id"]: c for c in self.contratos}
        parcelas = {(p["billId"], p["installmentId"]): p for p in self.parcelas}
        self.assertGreater(len(self.gerados[AGING]), 0)
        self.assertGreaterEqual(self.data_posicao, gerador.HOJE)
        for titulo in self.gerados[AGING]:
            contrato = contratos[titulo["receivableBillId"]]
            self.assertEqual(contrato["situation"], "1")
            self.assertEqual(titulo["costCentersId"], [contrato["enterpriseId"]])
            self.assertEqual(titulo["positionDate"], self.data_posicao.isoformat())
            for atrasada in titulo["defaulterInstallments"]:
                parcela = parcelas[(titulo["receivableBillId"], atrasada["installmentId"])]
                vencimento = date.fromisoformat(atrasada["dueDate"])
                self.assertEqual(atrasada["dueDate"], parcela["dueDate"])
                self.assertEqual(atrasada["correctedValueWithoutAdditions"], f"{parcela['correctedBalanceAmount']:.2f}")
                self.assertNotEqual(atrasada["conditionType"], "FI")
                self.assertGreater(atrasada["daysOfDelay"], 0)
                self.assertEqual(vencimento + timedelta(days=atrasada["daysOfDelay"]), self.data_posicao)
                self.assertGreaterEqual(vencimento, date.fromisoformat(contrato["contractDate"]))
                self.assertGreaterEqual(float(atrasada["correctedValueWithAdditions"]),
                                        float(atrasada["correctedValueWithoutAdditions"]))

    def test_inadimplencia_soma_o_vencido_do_comprador_por_obra(self):
        # Mesma regra de marts.fluxo_caixa_mensal: saldo em aberto, vencido, fora FI e fora distrato.
        distratados = {c["id"] for c in self.contratos if c["situation"] == "3"}
        vencido = defaultdict(int)
        for parcela in self.parcelas:
            if (parcela["billId"] not in distratados and parcela["paymentTerm"]["id"] != "FI"
                    and parcela["correctedBalanceAmount"] > 0
                    and date.fromisoformat(parcela["dueDate"]) < self.data_posicao):
                vencido[parcela["projectId"]] += round(parcela["correctedBalanceAmount"] * 100)
        aging = defaultdict(int)
        for titulo in self.gerados[AGING]:
            for atrasada in titulo["defaulterInstallments"]:
                aging[titulo["costCentersId"][0]] += round(float(atrasada["correctedValueWithoutAdditions"]) * 100)
        self.assertEqual(set(vencido), {o["id"] for o in self.obras})
        self.assertEqual(dict(aging), dict(vencido))

    def test_parcela_de_financiamento_vencida_fica_fora(self):
        obras = [{"id": 101, "idCompany": 1}]
        contratos = [{"id": 1, "situation": "1", "contractDate": "2026-01-10", "value": 1000.0}]
        base = {"billId": 1, "projectId": 101, "installmentNumber": "1/1", "balanceAmount": 100.0,
                "correctedBalanceAmount": 100.0, "dueDate": "2026-09-01"}
        parcelas = [{**base, "installmentId": 1, "paymentTerm": {"id": "PM"}},
                    {**base, "installmentId": 2, "paymentTerm": {"id": "FI"}},
                    {**base, "installmentId": 3, "paymentTerm": {"id": "PM"}, "dueDate": "2026-09-22"}]
        registros = gerador.gerar_inadimplencia(obras, contratos, parcelas, date(2026, 9, 22))
        self.assertEqual([p["installmentId"] for p in registros[0]["defaulterInstallments"]], [1])
        self.assertEqual(registros[0]["defaulterInstallments"][0]["daysOfDelay"], 21)


class TesteCargaComplementos(unittest.TestCase):
    def rodar(self, origem, repositorio, hoje=HOJE, rotas=None):
        with ApiFalsa(rest=origem.rest(), bulk=origem.bulk(), rotas={**ROTAS, **(rotas or {})}) as api:
            relatorio = executar(cliente_para(api), repositorio, TENANT, hoje, **OPCOES)
            return relatorio, api

    def test_primeira_carga_grava_as_tres_rotas_filtradas(self):
        origem, repo = OrigemComplementos(), RepositorioFalso()
        relatorio, api = self.rodar(origem, repo)
        self.assertEqual(relatorio.falhas, [])
        self.assertEqual(relatorio.caminho, "bulk")
        contagem = repo.contagem()
        self.assertEqual((contagem[MAPA], contagem[ITENS], contagem[AGING]), (2, 2, 3))

        consulta = api.chamadas("rest", MAPA)[0]["consulta"]
        inicio = (HOJE - timedelta(days=400)).replace(day=1)
        self.assertEqual((consulta["costCentersId"], consulta["startDate"]), ("101", inicio.isoformat()))

        itens = repo.payloads(ITENS)
        self.assertEqual({(i["buildingId"], i["measurementNumber"], i["buildingUnitId"]) for i in itens}, {(101, 1, 7)})
        self.assertEqual({(i["date"], i["statusApproval"]) for i in itens}, {("2026-09-15", "APROVADA")})
        self.assertEqual(len(api.chamadas("rest", "building-projects/999/progress-logs/1")), 0)

        aging = api.chamadas("bulk", AGING)[0]["consulta"]
        self.assertEqual((aging["companyId"], aging["enterpriseId"], aging["dueDateLimit"]), ("1", "101", HOJE.isoformat()))
        self.assertTrue(all(p["positionDate"] == HOJE.isoformat() for p in repo.payloads(AGING)))

        tudo = json.dumps([p for (_, p) in repo.raw.values()], ensure_ascii=False)
        for proibido in (NOME_CLIENTE, "Engenheiro", "texto livre", "prometeu", "Bloco A"):
            self.assertNotIn(proibido, tudo)

    def test_carga_seguinte_revisa_janela_curta_e_tira_quem_saiu_da_inadimplencia(self):
        origem, repo = OrigemComplementos(), RepositorioFalso()
        self.rodar(origem, repo)
        origem.inadimplentes = [titulo_inadimplente(502, 96)]
        amanha = HOJE + timedelta(days=1)
        relatorio, api = self.rodar(origem, repo, hoje=amanha)
        self.assertEqual(relatorio.falhas, [])

        self.assertEqual(api.chamadas("rest", MAPA)[0]["consulta"]["startDate"], "2026-08-01")
        medicoes = api.chamadas("rest", "building-projects/progress-logs")[0]["consulta"]
        self.assertEqual(medicoes["measurementStartDate"], (HOJE - timedelta(days=90)).isoformat())

        posicoes = sorted((p.get("receivableBillId", 0), p["positionDate"]) for p in repo.payloads(AGING))
        self.assertEqual(posicoes, [(0, amanha.isoformat()), (502, amanha.isoformat())])
        self.assertEqual(repo.contagem()[MAPA], 2, "mesmo mês e obra não duplica")

    def test_dia_sem_inadimplente_deixa_so_o_marcador(self):
        origem, repo = OrigemComplementos(), RepositorioFalso()
        self.rodar(origem, repo)
        origem.inadimplentes = []
        self.rodar(origem, repo, hoje=HOJE + timedelta(days=1))
        self.assertEqual(repo.payloads(AGING), [{"positionDate": (HOJE + timedelta(days=1)).isoformat()}])

    def test_sem_permissao_na_inadimplencia_mantem_bulk_e_posicao_anterior(self):
        origem, repo = OrigemComplementos(), RepositorioFalso()
        self.rodar(origem, repo)
        antes = sorted(json.dumps(p, sort_keys=True) for p in repo.payloads(AGING))
        negado = {AGING: lambda metodo, consulta, corpo, autorizacao: (403, {"status": 403, "clientMessage": "sem acesso"})}
        relatorio, _ = self.rodar(origem, repo, hoje=HOJE + timedelta(days=1), rotas=negado)
        self.assertEqual(relatorio.caminho, "bulk")
        self.assertEqual(relatorio.falhas, [])
        self.assertIsNone(repo.modo)
        self.assertEqual(sorted(json.dumps(p, sort_keys=True) for p in repo.payloads(AGING)), antes)

    def test_falha_na_segunda_empresa_nao_grava_posicao_pela_metade(self):
        origem, repo = OrigemComplementos(), RepositorioFalso(obras=(101, 102))
        origem.centros = [{"id": 101, "idCompany": 1}, {"id": 102, "idCompany": 2}]
        self.rodar(origem, repo)
        antes = repo.contagem()[AGING]

        def segunda_negada(metodo, consulta, corpo, autorizacao):
            if consulta.get("companyId") == "2":
                return 403, {"status": 403, "clientMessage": "sem acesso"}
            return 200, {"data": [titulo_inadimplente(503, 20)]}

        relatorio, _ = self.rodar(origem, repo, hoje=HOJE + timedelta(days=1), rotas={AGING: segunda_negada})
        self.assertEqual([e for e, _ in relatorio.falhas], [AGING])
        self.assertEqual(repo.contagem()[AGING], antes)
        self.assertNotIn(503, [p.get("receivableBillId") for p in repo.payloads(AGING)])

    def test_inadimplencia_so_no_caminho_bulk(self):
        tarefas = {t.endpoint: t for t in PLANO_BULK}
        self.assertTrue(tarefas[AGING].completa)
        origem, repo = OrigemComplementos(), RepositorioFalso()
        with ApiFalsa(rest=origem.rest(), bulk=origem.bulk(), rotas=ROTAS, bulk_indisponivel=True) as api:
            relatorio = executar(cliente_para(api), repo, TENANT, HOJE, **OPCOES)
        self.assertEqual(relatorio.caminho, "so_rest")
        self.assertEqual(repo.contagem()[AGING], 0)
        self.assertEqual(repo.contagem()[MAPA], 2)


@unittest.skipUnless(banco_local(), "DATABASE_URL local não definida")
class TesteBancoLocalComplementos(unittest.TestCase):
    """Grava os JSON da demo num tenant próprio do Supabase local e confere staging e marts."""

    def setUp(self):
        import psycopg
        self.conexao = psycopg.connect(banco_local(), autocommit=True)
        self.tenant = str(uuid.uuid4())
        self.conexao.execute("insert into app.tenant (id, razao_social) values (%s, 'Teste complementos')", (self.tenant,))
        for obra in gerador.ler("cost-centers.json"):
            self.conexao.execute("insert into app.centro_custo (tenant_id, id_origem, nome) values (%s, %s, %s)",
                                 (self.tenant, obra["id"], obra["name"]))

    def tearDown(self):
        for tabela in ("mapa_imobiliario_mensal", "medicao_obra", "inadimplencia"):
            self.conexao.execute(f"delete from staging.{tabela} where tenant_id = %s", (self.tenant,))
        self.conexao.execute("delete from app.tenant where id = %s", (self.tenant,))
        self.conexao.close()

    def test_demo_carrega_e_marts_batem_com_o_gerador(self):
        from carregar_origem import hash_registro
        for endpoint, arquivo in gerador.ARQUIVOS.items():
            registros = json.loads((gerador.PASTA_SAIDA / arquivo).read_text(encoding="utf-8"))["data"]
            with self.conexao.cursor() as cur:
                cur.executemany(
                    "insert into raw.registro (tenant_id, endpoint, payload, hash_registro) values (%s, %s, %s, %s)",
                    [(self.tenant, endpoint, json.dumps(r), hash_registro(r)) for r in registros])
        RepositorioBanco(self.conexao).recarregar(self.tenant)

        def um(sql):
            return self.conexao.execute(sql, (self.tenant,)).fetchone()[0]

        self.assertEqual(um("select count(*) from staging.mapa_imobiliario_mensal where tenant_id = %s"), 72)
        self.assertEqual(um("select count(*) from staging.medicao_obra where tenant_id = %s"), 748)
        aging = json.loads((gerador.PASTA_SAIDA / gerador.ARQUIVOS[AGING]).read_text(encoding="utf-8"))["data"]
        esperado = sum(float(p["correctedValueWithoutAdditions"]) for t in aging for p in t["defaulterInstallments"])
        self.assertAlmostEqual(float(um("select sum(valor_atrasado) from marts.inadimplencia_faixa where tenant_id = %s")),
                               esperado, places=2)
        self.assertEqual(um("select count(*) from marts.inadimplencia_faixa where tenant_id = %s"), 12)
        fisico = um("select max(pct_fisico) from marts.execucao_fisica_obra where tenant_id = %s")
        self.assertTrue(0 < fisico <= 1)


if __name__ == "__main__":
    unittest.main()
