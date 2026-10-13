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
from carregar_demo import gravar_mapa_contas_demo, gravar_viabilidade_demo  # noqa: E402
from carregar_origem import PLANO_BULK, RepositorioBanco, executar  # noqa: E402
from teste_carregar_origem import HOJE, OPCOES, TENANT, Origem, RepositorioFalso, banco_local, cliente_para  # noqa: E402

for nome in ("cliente_origem", "carregar_origem"):
    logging.getLogger(nome).addHandler(logging.NullHandler())

MAPA = "real-estate-map"
ITENS = "building-projects/progress-logs/items"
AGING = "defaulters-receivable-bills/by-aging"
SALDO = "accountancy/accountCostCenterBalance"
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
                                    cls.parcelas, cls.data_posicao, gerador.ler_estudos())

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

    def test_so_o_parque_paga_a_frente_do_fisico(self):
        # Mesma conta do alerta de marts.alertas_obra, que dispara acima de 0,10: pago sobre orçado menos o
        # físico da última medição aprovada. Na demo só o Parque das Águas conta essa história.
        orcado, pago, fisico = defaultdict(float), defaultdict(float), {}
        for item in self.itens:
            orcado[item["buildingId"]] += item["totalPrice"]
        for titulo in gerador.ler("outcome.json"):
            pago_titulo = sum(p["amount"] for p in titulo["payments"])
            for rateio in titulo["buildingsCosts"]:
                pago[rateio["buildingId"]] += pago_titulo * rateio["amount"] / titulo["originalAmount"]
        for item in self.gerados[ITENS]:
            if item["summary"] and item["statusApproval"] == "APROVADA":
                fisico[item["buildingId"]] = item["cumulativeMeasuredQuantity"]
        diferenca = {obra: pago[obra] / orcado[obra] - fisico[obra] for obra in orcado}
        self.assertTrue(0.12 <= diferenca[102] <= 0.20, diferenca)
        self.assertTrue(all(0 <= diferenca[obra] <= 0.06 for obra in (101, 103)), diferenca)
        self.assertEqual(fisico[103], 1.0)

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


def dinheiro(valor):
    return Decimal(repr(valor))


class TesteSaldoContabil(unittest.TestCase):
    """Valores esperados tirados de dados/viabilidade/estudos.json e dos fatores do gerador."""

    @classmethod
    def setUpClass(cls):
        cls.registros = gerador.gerar(gerador.ler("cost-centers.json"), gerador.ler("sales.json"),
                                      gerador.ler("units.json"), gerador.ler("building-cost-estimation-items.json"),
                                      gerador.ler("income.json"), posicao_gravada(), gerador.ler_estudos())[SALDO]
        cls.serie = defaultdict(list)
        for registro in cls.registros:
            cls.serie[(registro["costCenterId"], registro["accountId"])].append(registro)

    def saldos(self, obra, conta):
        return [dinheiro(r["balanceCarriedForward"]) for r in self.serie[(obra, conta)]]

    def test_um_registro_por_obra_conta_e_mes_de_10_2024_a_09_2026(self):
        self.assertEqual(len(self.registros), 3 * 7 * 24)
        chaves = {(r["costCenterId"], r["accountId"], r["monthYear"]) for r in self.registros}
        self.assertEqual(len(chaves), len(self.registros))
        meses = [r["monthYear"] for r in self.serie[(101, "1.1.05.01")]]
        self.assertEqual((meses[0], meses[-1], len(meses)), ("10/2024", "09/2026", 24))

    def test_aurora_terreno_inteiro_desde_o_primeiro_mes(self):
        self.assertEqual(self.saldos(101, "1.1.05.01"), [Decimal("3200000.00")] * 24)

    def test_aurora_projetos_em_seis_parcelas_com_dez_por_cento_acima_do_estudo(self):
        projetos = self.saldos(101, "1.1.05.02")
        self.assertEqual(projetos[0], Decimal("100833.33"))
        self.assertEqual(projetos[5:], [Decimal("605000.00")] * 19)

    def test_parque_terreno_projetos_e_juros_acima_do_estudo(self):
        self.assertEqual(self.saldos(102, "1.1.05.01")[-1], Decimal("1224000.00"))
        self.assertEqual(self.saldos(102, "1.1.05.02")[-1], Decimal("375000.00"))
        # 400.000 x 1,15 x 24 dos 29 meses até as chaves de 02/2027.
        self.assertEqual(self.saldos(102, "4.2.01.01")[-1], Decimal("380689.66"))

    def test_licenciamento_do_terceiro_ao_nono_mes(self):
        licenciamento = self.saldos(101, "1.1.05.03")
        self.assertEqual(licenciamento[:2], [Decimal("0.00")] * 2)
        self.assertEqual(licenciamento[2], Decimal("42857.14"))
        self.assertLess(licenciamento[7], Decimal("300000.00"))
        self.assertEqual(licenciamento[8:], [Decimal("300000.00")] * 16)

    def test_torre_entregue_fecha_juros_e_administrativas_no_estudo(self):
        self.assertEqual(self.saldos(103, "4.2.01.01")[-1], Decimal("120000.00"))
        self.assertEqual(self.saldos(103, "4.1.02.01")[-1], Decimal("100000.00"))
        self.assertEqual(self.saldos(103, "3.1.02.01")[-1], Decimal("50000.00"))

    def test_saldo_anterior_mais_debito_menos_credito_da_o_saldo_final(self):
        for (obra, conta), registros in self.serie.items():
            anterior = Decimal("0")
            for registro in registros:
                self.assertEqual(dinheiro(registro["previousBalance"]), anterior, (obra, conta, registro["monthYear"]))
                final = (dinheiro(registro["previousBalance"]) + dinheiro(registro["debitBalance"])
                         - dinheiro(registro["creditBalance"]))
                self.assertEqual(final, dinheiro(registro["balanceCarriedForward"]), (obra, conta, registro["monthYear"]))
                self.assertGreaterEqual(min(registro["debitBalance"], registro["creditBalance"]), 0)
                self.assertEqual((registro["previousBalanceType"], registro["balanceCarriedForwardType"]), ("D", "D"))
                anterior = final

    def test_nenhuma_conta_passa_do_estudo_fora_dos_fatores(self):
        estudos = {e["id_origem"]: e["linhas"] for e in gerador.ler_estudos()}
        for (obra, conta), registros in self.serie.items():
            linha = gerador.CONTAS_DEMO[conta]
            fator = gerador.FATOR_CONTA.get(linha, {}).get(obra, Decimal(1))
            teto = (Decimal(repr(estudos[obra][linha])) * fator).quantize(Decimal("0.01"))
            self.assertLessEqual(max(dinheiro(r["balanceCarriedForward"]) for r in registros), teto, (obra, conta))

    def test_filtro_de_campos_nao_tira_nada_do_registro(self):
        for registro in self.registros:
            self.assertEqual(filtrar(SALDO, registro), registro)

    def test_mapa_de_contas_so_usa_linhas_fora_do_orcamento(self):
        permitidas = {"custo_terreno", "custo_projetos", "custo_licenciamento", "assistencia_tecnica",
                      "juros_financiamento", "estoque", "despesas_comerciais", "despesas_administrativas"}
        self.assertLessEqual(set(gerador.CONTAS_DEMO.values()), permitidas)
        self.assertEqual(len(set(gerador.CONTAS_DEMO.values())), len(gerador.CONTAS_DEMO))


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
        for tabela in ("mapa_imobiliario_mensal", "medicao_obra", "inadimplencia", "saldo_contabil_mensal"):
            self.conexao.execute(f"delete from staging.{tabela} where tenant_id = %s", (self.tenant,))
        self.conexao.execute("delete from app.tenant where id = %s", (self.tenant,))
        self.conexao.close()

    def gravar_raw(self):
        from carregar_origem import hash_registro
        for endpoint, arquivo in gerador.ARQUIVOS.items():
            registros = json.loads((gerador.PASTA_SAIDA / arquivo).read_text(encoding="utf-8"))["data"]
            with self.conexao.cursor() as cur:
                cur.executemany(
                    "insert into raw.registro (tenant_id, endpoint, payload, hash_registro) values (%s, %s, %s, %s)",
                    [(self.tenant, endpoint, json.dumps(r), hash_registro(r)) for r in registros])

    def test_demo_carrega_e_marts_batem_com_o_gerador(self):
        self.gravar_raw()
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

    def test_saldo_contabil_chega_na_dre_da_aurora(self):
        self.gravar_raw()
        RepositorioBanco(self.conexao).recarregar(self.tenant)
        for _ in range(2):
            self.conexao.execute("select staging.recarregar_saldo_contabil(%s)", (self.tenant,))
        self.assertEqual(self.conexao.execute(
            "select count(*) from staging.saldo_contabil_mensal where tenant_id = %s", (self.tenant,)).fetchone()[0],
            3 * 7 * 24)
        gravar_viabilidade_demo(self.conexao, self.tenant, gerador.ler_estudos())
        self.assertEqual(gravar_mapa_contas_demo(self.conexao, self.tenant), 7)
        self.assertEqual(gravar_mapa_contas_demo(self.conexao, self.tenant), 0)

        consulta = self.conexao.execute(
            "select d.linha, d.apropriado, d.tendencia, d.desvio, d.fonte_realizado from marts.dre_viabilidade d "
            "join app.centro_custo cc on cc.id = d.centro_custo_id "
            "where d.tenant_id = %s and cc.id_origem = 101", (self.tenant,))
        linhas = {linha: tuple(medidas) for linha, *medidas in consulta.fetchall()}
        self.assertEqual(linhas["custo_terreno"], (Decimal("3200000.00"), Decimal("3200000.00"), 0, "contabil"))
        self.assertEqual(linhas["custo_projetos"],
                         (Decimal("605000.00"), Decimal("605000.00"), Decimal("55000.00"), "contabil"))
        sem_fonte = [linha for linha, (_, _, _, fonte) in linhas.items() if fonte == "sem_fonte"]
        self.assertEqual(sem_fonte, ["estoque"])


if __name__ == "__main__":
    unittest.main()
