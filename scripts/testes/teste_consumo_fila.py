import json
import logging
import sys
import unittest
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import carregar_crm  # noqa: E402
from api_falsa import ApiFalsa  # noqa: E402
from carregar_origem import RepositorioBanco, executar, planejar_fila  # noqa: E402
from teste_carregar_origem import (  # noqa: E402
    CPF, HOJE, OPCOES, Origem, RepositorioFalso, banco_local, cliente_para, contrato_com_dado_pessoal, parcela,
)

for nome in ("cliente_origem", "carregar_origem", "carregar_crm"):
    logging.getLogger(nome).addHandler(logging.NullHandler())
    logging.getLogger(nome).propagate = False

TENANT = "0e000000-0000-4000-8000-0000000000f5"
AMANHA = HOJE + timedelta(days=1)


class RepositorioFilaFalso(RepositorioFalso):
    """Repositório em memória com a fila de eventos: grava, remove e marca como uma transação só."""

    def __init__(self, obras=(101,)):
        super().__init__(obras)
        self.eventos = {}
        self.proximo = 1

    def avisar(self, tipo, ids):
        id_evento = self.proximo
        self.proximo += 1
        self.eventos[id_evento] = {"tipo": tipo, "ids": ids, "processado": False}
        return id_evento

    def pendentes(self):
        return sorted(i for i, e in self.eventos.items() if not e["processado"])

    def ler_eventos_pendentes(self, tenant, origem, limite):
        return [(i, self.eventos[i]["tipo"], self.eventos[i]["ids"]) for i in self.pendentes()][:limite]

    def marcar_processados(self, tenant, ids_eventos):
        for i in ids_eventos:
            self.eventos[i]["processado"] = True

    def gravar_fila(self, tenant, lote):
        marcas = dict(self.marcas)
        contagens = self.gravar_tarefa(tenant, lote, None)
        self.marcas = marcas
        removidos = {}
        for (t, endpoint, hash_atual), (chave, _) in list(self.raw.items()):
            if t == tenant and (endpoint, chave) in set(lote.remocoes_confirmadas()):
                del self.raw[(t, endpoint, hash_atual)]
                removidos[endpoint] = removidos.get(endpoint, 0) + 1
        self.marcar_processados(tenant, lote.ids_eventos)
        for endpoint, n in removidos.items():
            contagens.setdefault(endpoint, {"lidos": 0, "novos": 0, "substituidos": 0})["removidos"] = n
        for n in contagens.values():
            n.setdefault("removidos", 0)
        return contagens

    def chaves(self, endpoint):
        return sorted(c for (_, e, _), (c, _) in self.raw.items() if e == endpoint)


def rota_fixa(status, corpo):
    return lambda metodo, consulta, texto, autorizacao: (status, corpo)


def bulk_por_titulos(registros_de):
    def responder(consulta):
        ids = {int(i) for i in consulta["billsIds"].split(",")}
        return [r for r in registros_de() if r["billId"] in ids]
    return responder


class Cenario:
    def __init__(self, obras=(101,)):
        self.origem = Origem()
        self.repo = RepositorioFilaFalso(obras)
        self.rotas = {}

    def rodar(self, hoje=HOJE, fila=True, opcoes=None, ajustes_cliente=None, rest_extra=None, **ajustes_api):
        rest = {**self.origem.rest(), **(rest_extra or {})}
        bulk = self.origem.bulk()
        bulk["income/by-bills"] = bulk_por_titulos(lambda: self.origem.parcelas)
        with ApiFalsa(rest=rest, bulk=bulk, rotas=self.rotas, **ajustes_api) as api:
            extras = {"fila_eventos": self.repo} if fila else {}
            relatorio = executar(cliente_para(api, **(ajustes_cliente or {})), self.repo, TENANT, hoje,
                                 **{**OPCOES, **(opcoes or {}), **extras})
        return relatorio, api


def caminhos(api):
    return [(r["tipo"], r["caminho"]) for r in api.requisicoes]


class TestePlanejamento(unittest.TestCase):
    def test_junta_ids_repetidos_e_conta_chamadas_em_lote(self):
        eventos = [(i, "RECEIPT_PROCESSED", {"billId": i % 150, "installmentId": 1}) for i in range(1, 301)]
        plano = planejar_fila(eventos, True, {"rest": 0, "bulk": 2})
        self.assertEqual(len(plano.alvos["income"]), 150)
        self.assertEqual(len(plano.eventos["income"]), 300)
        self.assertEqual(plano.adiados, 0)

    def test_para_no_teto_por_ordem_de_chegada(self):
        eventos = [(1, "UNIT_UPDATED", {"unitId": 1}), (2, "UNIT_UPDATED", {"unitId": 1}),
                   (3, "UNIT_UPDATED", {"unitId": 2}), (4, "UNIT_UPDATED", {"unitId": 3})]
        plano = planejar_fila(eventos, True, {"rest": 2, "bulk": 0})
        self.assertEqual(plano.eventos["units"], [1, 2, 3])
        self.assertEqual(plano.alvos["units"], {1, 2})
        self.assertEqual(plano.adiados, 1)

    def test_remocao_so_com_titulo_e_parcela_e_cancelamento_nao_remove(self):
        eventos = [(1, "RECEIVABLE_INSTALLMENT_REMOVED", {"receivableBillId": 10, "installmentId": 2}),
                   (2, "PAYMENT_INSTALLMENT_REMOVED", {"billId": [20, 21], "installmentId": 1}),
                   (3, "SALES_CONTRACT_CANCELED", {"salesContractId": 5}),
                   (4, "SALES_CONTRACT_REMOVED", {"salesContractId": 6})]
        plano = planejar_fila(eventos, True, {"rest": 10, "bulk": 10})
        self.assertEqual(plano.remocoes["income"], {("income", "10|2")})
        self.assertEqual(plano.remocoes["outcome"], set(), "lista de títulos não diz qual parcela saiu")
        self.assertEqual(plano.remocoes["sales-contracts"], {("sales-contracts", "6")})
        self.assertEqual(plano.alvos["sales-contracts"], {5, 6})

    def test_tipo_sem_regra_ou_sem_id_sai_sem_busca_e_cadastro_fica_com_o_plano(self):
        eventos = [(1, "BANK_MOVEMENT_CREATED", {"bankMovementId": 3}), (2, "UNIT_UPDATED", {"outro": 1}),
                   (3, "UNIT_UPDATED", {"unitId": "7"}), (4, "COST_CENTER_UPDATED", {"costCenterId": 101}),
                   (5, "BUILDING_COST_ESTIMATION_UPDATED", {"buildingId": 101})]
        plano = planejar_fila(eventos, True, {"rest": 10, "bulk": 10})
        self.assertEqual(plano.sem_busca, [1, 2, 3])
        self.assertEqual(plano.cobertos, {"cost-centers": [4], "building-cost-estimation-items": [5]})
        self.assertEqual(plano.alvos, {})

    def test_so_rest_nao_usa_bulk(self):
        eventos = [(1, "RECEIPT_PROCESSED", {"billId": 10}), (2, "PAYMENT_BILL_UPDATED", {"billId": 20})]
        plano = planejar_fila(eventos, False, {"rest": 10, "bulk": 10})
        self.assertEqual((plano.sem_busca, plano.cobertos, plano.alvos), ([1], {"bills": [2]}, {}))


class TesteFilaErp(unittest.TestCase):
    def test_fila_vazia_nao_muda_nada(self):
        com, sem = Cenario(), Cenario()
        relatorio_com, api_com = com.rodar()
        relatorio_sem, api_sem = sem.rodar(fila=False)
        self.assertEqual(caminhos(api_com), caminhos(api_sem))
        self.assertEqual(com.repo.raw.keys(), sem.repo.raw.keys())
        self.assertEqual(relatorio_com.fila, {})
        self.assertNotIn("fila", relatorio_com.texto())

    def test_parcela_avisada_e_buscada_antes_do_plano_e_marcada(self):
        cenario = Cenario()
        cenario.rodar()
        cenario.origem.parcelas = [parcela(10, 1), parcela(10, 2, saldo=0.0)]
        evento = cenario.repo.avisar("RECEIVABLE_INSTALLMENT_UPDATED", {"receivableBillId": 10, "installmentId": 2})
        relatorio, api = cenario.rodar(hoje=AMANHA)

        ordem = caminhos(api)
        self.assertLess(ordem.index(("bulk", "income/by-bills")), ordem.index(("bulk", "income")))
        self.assertEqual(api.chamadas("bulk", "income/by-bills")[0]["consulta"]["billsIds"], "10")
        self.assertTrue(cenario.repo.eventos[evento]["processado"])
        saldos = sorted((p["installmentId"], p["balanceAmount"]) for p in cenario.repo.payloads("income"))
        self.assertEqual(saldos, [(1, 1000.0), (2, 0.0)])
        self.assertEqual(relatorio.fila["processados"], 1)
        self.assertIn("fila: 1 eventos processados, 0 ficaram para a próxima execução", relatorio.texto())
        self.assertNotIn("Maria", relatorio.texto())
        self.assertNotIn(CPF, json.dumps([p for (_, p) in cenario.repo.raw.values()], ensure_ascii=False))

    def test_parcela_removida_sai_de_raw(self):
        cenario = Cenario()
        cenario.rodar()
        self.assertEqual(cenario.repo.chaves("income"), ["10|1", "10|2"])
        cenario.origem.parcelas = [parcela(10, 1)]
        evento = cenario.repo.avisar("RECEIVABLE_INSTALLMENT_REMOVED", {"receivableBillId": 10, "installmentId": 2})
        relatorio, _ = cenario.rodar(hoje=AMANHA)
        self.assertEqual(cenario.repo.chaves("income"), ["10|1"])
        self.assertTrue(cenario.repo.eventos[evento]["processado"])
        linha = dict(relatorio.fila["linhas"])["income"]
        self.assertEqual(linha["removidos"], 1)

    def test_aviso_de_remocao_que_a_origem_desmente_nao_apaga(self):
        cenario = Cenario()
        cenario.rodar()
        cenario.repo.avisar("RECEIVABLE_INSTALLMENT_REMOVED", {"receivableBillId": 10, "installmentId": 2})
        cenario.rodar(hoje=AMANHA)
        self.assertEqual(cenario.repo.chaves("income"), ["10|1", "10|2"])

    def test_contrato_removido_sai_das_vendas_e_do_contrato(self):
        cenario = Cenario()
        cenario.rodar()
        self.assertEqual(cenario.repo.chaves("sales"), ["1", "2"])
        cenario.origem.contratos = [contrato_com_dado_pessoal(1)]
        cenario.rotas["sales-contracts/2"] = rota_fixa(404, {"status": 404, "clientMessage": "nao encontrado"})
        evento = cenario.repo.avisar("SALES_CONTRACT_REMOVED", {"salesContractId": 2})
        cenario.rodar(hoje=AMANHA)
        self.assertEqual(cenario.repo.chaves("sales"), ["1"])
        self.assertEqual(cenario.repo.chaves("sales-contracts"), ["1"])
        self.assertTrue(cenario.repo.eventos[evento]["processado"])

    def test_contrato_cancelado_e_reconsultado_e_a_obra_volta_ao_bulk_de_vendas(self):
        cenario = Cenario(obras=(101, 102))
        cenario.rodar()
        cancelado = {**contrato_com_dado_pessoal(3, obra=102), "situation": "3"}
        cancelado["salesContractCustomers"] = cancelado["customers"]
        cenario.rotas["sales-contracts/3"] = rota_fixa(200, cancelado)
        cenario.repo.avisar("SALES_CONTRACT_CANCELED", {"salesContractId": 3})
        _, api = cenario.rodar(hoje=AMANHA, rest_extra={"sales-contracts": []})
        self.assertIn("3", cenario.repo.chaves("sales-contracts"))
        self.assertEqual({c["consulta"]["enterpriseId"] for c in api.chamadas("bulk", "sales")}, {"102"})
        gravado = next(p for p in cenario.repo.payloads("sales-contracts") if p["id"] == 3)
        self.assertNotIn("Maria", json.dumps(gravado, ensure_ascii=False))
        self.assertNotIn("customers", gravado)

    def test_teto_por_execucao_deixa_o_resto_pendente(self):
        cenario = Cenario()
        for id_unidade in (1, 2, 3):
            cenario.rotas[f"units/{id_unidade}"] = rota_fixa(200, {"id": id_unidade, "enterpriseId": 101})
            cenario.repo.avisar("UNIT_UPDATED", {"unitId": id_unidade})
        relatorio, api = cenario.rodar(opcoes={"limite_fila_rest": 2})
        self.assertEqual([c["caminho"] for c in api.chamadas("rest") if c["caminho"].startswith("units/")],
                         ["units/1", "units/2"])
        self.assertEqual(cenario.repo.pendentes(), [3])
        self.assertEqual((relatorio.fila["processados"], relatorio.fila["adiados"]), (2, 1))
        cenario.rodar(hoje=AMANHA, opcoes={"limite_fila_rest": 2})
        self.assertEqual(cenario.repo.pendentes(), [])

    def test_falha_no_meio_do_grupo_nao_grava_nem_marca(self):
        cenario = Cenario()
        cenario.rotas["units/1"] = rota_fixa(200, {"id": 1, "enterpriseId": 101, "name": "versao-da-fila"})
        cenario.rotas["units/2"] = rota_fixa(400, {"status": 400, "clientMessage": "erro"})
        primeiro = cenario.repo.avisar("UNIT_UPDATED", {"unitId": 1})
        segundo = cenario.repo.avisar("UNIT_UPDATED", {"unitId": 2})
        recebimento = cenario.repo.avisar("RECEIPT_PROCESSED", {"billId": 10, "installmentId": 1})
        relatorio, _ = cenario.rodar(fila=True, rest_extra={"units": []})
        self.assertIn("fila:units", [e for e, _ in relatorio.falhas])
        self.assertEqual(cenario.repo.pendentes(), [primeiro, segundo])
        self.assertTrue(cenario.repo.eventos[recebimento]["processado"])
        self.assertNotIn("versao-da-fila", json.dumps(cenario.repo.payloads("units")))

    def test_pagar_sem_indexador_fica_pendente(self):
        cenario = Cenario()
        evento = cenario.repo.avisar("PAYMENT_BILL_UPDATED", {"billId": 20})
        relatorio, api = cenario.rodar(opcoes={"indexador_correcao": ""})
        self.assertIn("fila:outcome", [e for e, _ in relatorio.falhas])
        self.assertEqual(api.chamadas("bulk", "outcome/by-bills"), [])
        self.assertEqual(cenario.repo.pendentes(), [evento])

    def test_tipos_sem_busca_e_cobertos_pelo_plano(self):
        cenario = Cenario()
        banco = cenario.repo.avisar("BANK_MOVEMENT_CREATED", {"bankMovementId": 3})
        centro = cenario.repo.avisar("COST_CENTER_UPDATED", {"costCenterId": 101})
        orcamento = cenario.repo.avisar("BUILDING_COST_ESTIMATION_UPDATED", {"buildingId": 101})
        cenario.rotas["cost-centers"] = rota_fixa(400, {"status": 400, "clientMessage": "erro"})
        relatorio, _ = cenario.rodar()
        self.assertEqual(cenario.repo.pendentes(), [centro], "centro de custo espera o plano gravar de novo")
        self.assertTrue(cenario.repo.eventos[banco]["processado"])
        self.assertTrue(cenario.repo.eventos[orcamento]["processado"])
        self.assertEqual(relatorio.fila["adiados"], 1)
        del cenario.rotas["cost-centers"]
        cenario.rodar(hoje=AMANHA)
        self.assertEqual(cenario.repo.pendentes(), [])

    def test_so_rest_nao_gasta_bulk_com_a_fila(self):
        cenario = Cenario()
        cenario.repo.modo = (True, datetime.now(timezone.utc))
        pagar = cenario.repo.avisar("PAYMENT_BILL_UPDATED", {"billId": 20})
        receber = cenario.repo.avisar("RECEIPT_PROCESSED", {"billId": 10})
        relatorio, api = cenario.rodar(bulk_indisponivel=True)
        self.assertEqual(relatorio.caminho, "so_rest")
        self.assertEqual(api.chamadas("bulk"), [])
        self.assertEqual(cenario.repo.pendentes(), [])
        self.assertTrue(cenario.repo.eventos[pagar]["processado"] and cenario.repo.eventos[receber]["processado"])

    def test_cota_esgotada_na_fila_nao_roda_o_plano(self):
        cenario = Cenario()
        evento = cenario.repo.avisar("RECEIPT_PROCESSED", {"billId": 10})
        relatorio, api = cenario.rodar(ajustes_cliente={"cota_diaria_bulk": 0})
        self.assertTrue(relatorio.cota_esgotada)
        self.assertEqual(api.requisicoes, [])
        self.assertEqual(cenario.repo.pendentes(), [evento])
        self.assertEqual(cenario.repo.marcas, {})


class CursorCrm:
    def __init__(self, eventos, marcas=None):
        self.eventos = eventos
        self.marcas = marcas or {}
        self.instrucoes = []
        self._resultado = []

    def __enter__(self):
        return self

    def __exit__(self, *argumentos):
        return False

    def execute(self, sql, parametros=None):
        self.instrucoes.append((sql, parametros))
        if "from app.evento_origem" in sql:
            self._resultado = [(i,) for i in self.eventos]
        elif "from app.marca_carga" in sql:
            self._resultado = list(self.marcas.items())
        else:
            self._resultado = []

    def executemany(self, sql, linhas):
        self.instrucoes.append((sql, list(linhas)))

    def fetchall(self):
        return self._resultado


class ConexaoCrm:
    def __init__(self, eventos):
        self.cursor_falso = CursorCrm(eventos)
        self.confirmada = False
        self.desfeita = False

    def cursor(self):
        return self.cursor_falso

    def commit(self):
        self.confirmada = True

    def rollback(self):
        self.desfeita = True

    def posicao(self, trecho):
        return [i for i, (sql, _) in enumerate(self.cursor_falso.instrucoes) if trecho in sql]


class FonteCrm:
    def __init__(self, falhar=False):
        self.pedidos = []
        self.falhar = falhar

    def paginas(self, endpoint, a_partir):
        self.pedidos.append(endpoint)
        if self.falhar and endpoint == "crm/reservas":
            raise carregar_crm.ErroCrm("falha simulada")
        if endpoint == "crm/reservas":
            yield [{"idreserva": 7, "referencia_data": "2026-09-28 10:00:00", "cliente": "Pessoa Qualquer"}]


class TesteFilaCrm(unittest.TestCase):
    def test_eventos_pendentes_saem_na_mesma_transacao_da_carga(self):
        conexao = ConexaoCrm([4, 9])
        carregar_crm.carregar(conexao, TENANT, FonteCrm())
        atualizacoes = conexao.posicao("update app.evento_origem")
        self.assertEqual(len(atualizacoes), 1)
        self.assertGreater(atualizacoes[0], max(conexao.posicao("staging.recarregar_crm")))
        self.assertGreater(atualizacoes[0], max(conexao.posicao("insert into app.marca_carga")))
        self.assertEqual(conexao.cursor_falso.instrucoes[atualizacoes[0]][1], (TENANT, [4, 9]))
        self.assertTrue(conexao.confirmada)
        self.assertFalse(conexao.desfeita)

    def test_fila_vazia_nao_muda_a_carga(self):
        conexao = ConexaoCrm([])
        fonte = FonteCrm()
        resumo = carregar_crm.carregar(conexao, TENANT, fonte)
        self.assertEqual(conexao.posicao("update app.evento_origem"), [])
        self.assertEqual(fonte.pedidos, list(carregar_crm.ENDPOINTS))
        self.assertEqual(resumo["crm/reservas"], 1)

    def test_so_com_eventos_e_fila_vazia_nao_chama_a_api(self):
        conexao = ConexaoCrm([])
        fonte = FonteCrm()
        self.assertEqual(carregar_crm.carregar(conexao, TENANT, fonte, so_com_eventos=True), {})
        self.assertEqual(fonte.pedidos, [])
        self.assertFalse(conexao.confirmada)

    def test_so_com_eventos_carrega_quando_ha_aviso(self):
        conexao = ConexaoCrm([3])
        fonte = FonteCrm()
        carregar_crm.carregar(conexao, TENANT, fonte, so_com_eventos=True)
        self.assertEqual(fonte.pedidos, list(carregar_crm.ENDPOINTS))
        self.assertEqual(len(conexao.posicao("update app.evento_origem")), 1)

    def test_falha_desfaz_e_evento_continua_pendente(self):
        conexao = ConexaoCrm([5])
        with self.assertRaises(carregar_crm.ErroCrm):
            carregar_crm.carregar(conexao, TENANT, FonteCrm(falhar=True))
        self.assertEqual(conexao.posicao("update app.evento_origem"), [])
        self.assertTrue(conexao.desfeita)
        self.assertFalse(conexao.confirmada)


@unittest.skipUnless(banco_local(), "DATABASE_URL local não definida")
class TesteFilaBancoLocal(unittest.TestCase):
    """RepositorioBanco de verdade no Supabase local, com tenant próprio apagado no fim."""

    def setUp(self):
        import psycopg
        self.conexao = psycopg.connect(banco_local(), autocommit=True)
        self.tenant = str(uuid.uuid4())
        self.conexao.execute("insert into app.tenant (id, razao_social) values (%s, 'Teste fila')", (self.tenant,))
        self.conexao.execute("insert into app.centro_custo (tenant_id, id_origem, nome) values (%s, 101, 'Obra A')",
                             (self.tenant,))

    def tearDown(self):
        self.conexao.execute("delete from app.tenant where id = %s", (self.tenant,))
        self.conexao.close()

    def avisar(self, id_evento, tipo, ids):
        self.conexao.execute(
            "insert into app.evento_origem (tenant_id, origem, id_evento, tipo_evento, ids) "
            "values (%s, 'erp', %s, %s, %s::jsonb)", (self.tenant, id_evento, tipo, json.dumps(ids)))

    def rodar(self, origem, hoje):
        repo = RepositorioBanco(self.conexao)
        bulk = origem.bulk()
        bulk["income/by-bills"] = bulk_por_titulos(lambda: origem.parcelas)
        with ApiFalsa(rest=origem.rest(), bulk=bulk) as api:
            return executar(cliente_para(api), repo, self.tenant, hoje, fila_eventos=repo, **OPCOES)

    def test_reconsulta_remove_e_marca_processado(self):
        origem = Origem()
        primeira = self.rodar(origem, HOJE)
        self.assertEqual(primeira.falhas, [])
        origem.parcelas = [parcela(10, 1, saldo=0.0)]
        self.avisar("evt-1", "RECEIVABLE_INSTALLMENT_UPDATED", {"receivableBillId": 10, "installmentId": 1})
        self.avisar("evt-2", "RECEIVABLE_INSTALLMENT_REMOVED", {"receivableBillId": 10, "installmentId": 2})
        self.avisar("evt-3", "BANK_MOVEMENT_CREATED", {"bankMovementId": 1})
        segunda = self.rodar(origem, AMANHA)
        self.assertEqual(segunda.falhas, [])
        self.assertEqual(segunda.fila["processados"], 3)

        pendentes = self.conexao.execute(
            "select count(*) from app.evento_origem where tenant_id = %s and processado_em is null",
            (self.tenant,)).fetchone()[0]
        self.assertEqual(pendentes, 0)
        parcelas = self.conexao.execute(
            "select chave_origem, (payload->>'balanceAmount')::numeric from raw.registro "
            "where tenant_id = %s and endpoint = 'income' order by 1", (self.tenant,)).fetchall()
        self.assertEqual([(c, float(s)) for c, s in parcelas], [("10|1", 0.0)])
        no_staging = self.conexao.execute(
            "select count(*) from staging.parcela_receber where tenant_id = %s", (self.tenant,)).fetchone()[0]
        self.assertEqual(no_staging, 1)

    def test_fila_vazia_nao_escreve_nada_na_fila(self):
        relatorio = self.rodar(Origem(), HOJE)
        self.assertEqual((relatorio.falhas, relatorio.fila), ([], {}))


if __name__ == "__main__":
    unittest.main()
