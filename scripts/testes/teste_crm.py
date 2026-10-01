"""Testes do cliente, do carregador e do gerador do CRM. Nenhum teste sai da máquina: a API é
um http.server local e o banco é um cursor falso que só registra as instruções."""

import json
import logging
import sys
import tempfile
import threading
import unittest
import urllib.parse
from datetime import date
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

PASTA_SCRIPTS = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PASTA_SCRIPTS))

import carregar_crm  # noqa: E402
import gerar_dados_crm  # noqa: E402
from cliente_crm import ClienteCrm, ErroCrm, LimitadorPorMinuto  # noqa: E402

EMAIL_TESTE = "integracao@teste.invalid"
TOKEN_TESTE = "token-de-teste-que-nao-pode-vazar"

CAMPOS_PESSOAIS = {
    "nome", "cliente", "nome_cliente", "email", "email_cliente", "telefone", "telefone_cliente",
    "documento", "documento_cliente", "cpf", "cep_cliente", "cidade", "estado", "renda", "renda_familiar",
    "score", "profissao", "sexo", "idade", "estado_civil", "data_nascimento_cliente", "agencia",
    "num_matricula", "corretor", "usuario", "idcliente", "idlead_vinculado", "valor_fgts", "valor_subsidio",
    "valor_divida", "campos_adicionais", "gestor", "imobiliaria", "nome_usuario", "usuario_aprovacao",
}


class ApiFalsa(BaseHTTPRequestHandler):
    respostas = []
    pedidos = []

    def do_GET(self):
        partes = urllib.parse.urlsplit(self.path)
        ApiFalsa.pedidos.append({
            "caminho": partes.path,
            "parametros": dict(urllib.parse.parse_qsl(partes.query)),
            "email": self.headers.get("email"),
            "token": self.headers.get("token"),
        })
        status, corpo = ApiFalsa.respostas.pop(0)
        conteudo = json.dumps(corpo).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(conteudo)))
        self.end_headers()
        self.wfile.write(conteudo)

    def log_message(self, formato, *argumentos):
        pass


class TesteClienteCrm(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.servidor = HTTPServer(("127.0.0.1", 0), ApiFalsa)
        cls.linha = threading.Thread(target=cls.servidor.serve_forever, daemon=True)
        cls.linha.start()
        cls.url_base = f"http://127.0.0.1:{cls.servidor.server_address[1]}"

    @classmethod
    def tearDownClass(cls):
        cls.servidor.shutdown()
        cls.servidor.server_close()

    def setUp(self):
        ApiFalsa.respostas = []
        ApiFalsa.pedidos = []
        self.esperas = []
        self.cliente = ClienteCrm(self.url_base, EMAIL_TESTE, TOKEN_TESTE, limite_por_minuto=100,
                                  dormir=self.esperas.append)

    def test_pagina_ate_o_total_com_cabecalhos_e_data_de_referencia(self):
        ApiFalsa.respostas = [
            (200, {"pagina": 1, "total_de_paginas": 2, "dados": [{"idrepasse": 1}, {"idrepasse": 2}]}),
            (200, {"pagina": 2, "total_de_paginas": 2, "dados": [{"idrepasse": 3}]}),
        ]
        paginas = list(self.cliente.paginas("repasses", a_partir_data_referencia="2026-09-01"))
        self.assertEqual([len(p) for p in paginas], [2, 1])
        self.assertEqual(len(ApiFalsa.pedidos), 2)
        primeiro = ApiFalsa.pedidos[0]
        self.assertEqual(primeiro["caminho"], "/api/v1/cvdw/repasses")
        self.assertEqual(primeiro["parametros"],
                         {"pagina": "1", "registros_por_pagina": "500", "a_partir_data_referencia": "2026-09-01"})
        self.assertEqual((primeiro["email"], primeiro["token"]), (EMAIL_TESTE, TOKEN_TESTE))
        self.assertEqual(ApiFalsa.pedidos[1]["parametros"]["pagina"], "2")

    def test_pagina_vazia_encerra_sem_total(self):
        ApiFalsa.respostas = [(200, {"dados": []})]
        self.assertEqual(list(self.cliente.paginas("leads")), [])
        self.assertNotIn("a_partir_data_referencia", ApiFalsa.pedidos[0]["parametros"])

    def test_429_espera_um_minuto_e_tenta_de_novo(self):
        ApiFalsa.respostas = [
            (429, {"erro": "limite"}),
            (200, {"pagina": 1, "total_de_paginas": 1, "dados": [{"idreserva": 1}]}),
        ]
        with self.assertLogs("cliente_crm", level=logging.WARNING) as capturado:
            paginas = list(self.cliente.paginas("reservas"))
        self.assertEqual(len(paginas), 1)
        self.assertIn(60, self.esperas)
        self.assertIn("limite estourado", capturado.output[0])

    def test_401_nao_mostra_credencial_nem_no_log(self):
        ApiFalsa.respostas = [(401, {"erro": "E-mail e/ou token incorreto(s)."})]
        with self.assertLogs("cliente_crm", level=logging.DEBUG) as capturado:
            logging.getLogger("cliente_crm").debug("inicio")
            with self.assertRaises(ErroCrm) as contexto:
                list(self.cliente.paginas("repasses"))
        mensagem = str(contexto.exception)
        self.assertIn("401", mensagem)
        texto_log = "\n".join(capturado.output)
        for segredo in (EMAIL_TESTE, TOKEN_TESTE):
            self.assertNotIn(segredo, mensagem)
            self.assertNotIn(segredo, texto_log)
            self.assertNotIn(segredo, repr(self.cliente))

    def test_url_sem_https_fora_da_maquina_e_recusada(self):
        with self.assertRaises(ErroCrm):
            ClienteCrm("http://cliente.exemplo.invalid", EMAIL_TESTE, TOKEN_TESTE)
        with self.assertRaises(ErroCrm):
            ClienteCrm("https://cliente.exemplo.invalid", EMAIL_TESTE, "")


class TesteLimitador(unittest.TestCase):
    def test_terceira_chamada_no_mesmo_minuto_espera(self):
        instante = [0.0]
        esperas = []

        def dormir(segundos):
            esperas.append(segundos)
            instante[0] += segundos

        limitador = LimitadorPorMinuto(2, relogio=lambda: instante[0], dormir=dormir)
        limitador.aguardar_vez()
        instante[0] = 10
        limitador.aguardar_vez()
        instante[0] = 20
        limitador.aguardar_vez()
        self.assertEqual(esperas, [40])
        instante[0] = 200
        limitador.aguardar_vez()
        self.assertEqual(esperas, [40])


class TesteCamposPermitidos(unittest.TestCase):
    def test_lista_de_permitidos_nao_tem_campo_pessoal(self):
        for endpoint, configuracao in carregar_crm.ENDPOINTS.items():
            with self.subTest(endpoint=endpoint):
                self.assertFalse(configuracao["campos"] & CAMPOS_PESSOAIS)
                self.assertIn(configuracao["chave"], configuracao["campos"])
                self.assertIn("referencia_data", configuracao["campos"])
                self.assertTrue(endpoint.startswith("crm/"))

    def test_filtro_descarta_pessoal_aninhado_e_campo_novo(self):
        bruto = {
            "idrepasse": 7, "referencia_data": "2026-09-01 10:00:00", "situacao": "Análise",
            "cliente": "Pessoa Qualquer", "documento_cliente": "00000000000", "email_cliente": "x@teste.invalid",
            "campos_adicionais": [{"nome": "obs", "valor": "texto livre"}], "campo_que_a_api_criou": "?",
            "valor_financiado": 1000.5,
        }
        self.assertEqual(carregar_crm.filtrar_campos("crm/repasses", bruto),
                         {"idrepasse": 7, "referencia_data": "2026-09-01 10:00:00", "situacao": "Análise",
                          "valor_financiado": 1000.5})

    def test_data_referencia(self):
        self.assertEqual(carregar_crm.data_referencia({"referencia_data": "2026-01-15 15:26:15"}), "2026-01-15")
        self.assertIsNone(carregar_crm.data_referencia({"referencia_data": "15/01/2026"}))
        self.assertIsNone(carregar_crm.data_referencia({}))


class CursorFalso:
    def __init__(self, marcas):
        self.marcas = marcas
        self.instrucoes = []
        self._resultado = []

    def __enter__(self):
        return self

    def __exit__(self, *argumentos):
        return False

    def execute(self, sql, parametros=None):
        self.instrucoes.append((sql, parametros))
        self._resultado = list(self.marcas.items()) if "from app.marca_carga" in sql else []

    def executemany(self, sql, linhas):
        self.instrucoes.append((sql, list(linhas)))

    def fetchall(self):
        return self._resultado


class ConexaoFalsa:
    def __init__(self, marcas=None):
        self.cursor_falso = CursorFalso(marcas or {})
        self.confirmada = False
        self.desfeita = False

    def cursor(self):
        return self.cursor_falso

    def commit(self):
        self.confirmada = True

    def rollback(self):
        self.desfeita = True


class FonteFalsa:
    def __init__(self, paginas_por_endpoint, falhar_em=None):
        self.paginas_por_endpoint = paginas_por_endpoint
        self.falhar_em = falhar_em
        self.pedidos = []

    def paginas(self, endpoint, a_partir):
        self.pedidos.append((endpoint, a_partir))
        if endpoint == self.falhar_em:
            raise ErroCrm("falha simulada")
        yield from self.paginas_por_endpoint.get(endpoint, [])


TENANT = "0e000000-0000-4000-8000-0000000000d1"


class TesteChaveRegistro(unittest.TestCase):
    def test_referencia_separa_linhas_com_o_mesmo_id(self):
        self.assertEqual(carregar_crm.chave_registro("crm/reservas", {"idreserva": 193, "referencia": "193_30"}),
                         "193_30")
        self.assertEqual(carregar_crm.chave_registro("crm/reservas", {"idreserva": 193}), "193")
        self.assertIsNone(carregar_crm.chave_registro("crm/reservas", {"referencia": " "}))

    def test_linha_nova_de_mesmo_id_nao_apaga_a_irma(self):
        cursor = CursorFalso({})
        carregar_crm.gravar_lote(cursor, TENANT, "crm/reservas",
                                 [{"idreserva": 193, "referencia": "193_30", "referencia_data": "2026-09-01"}])
        apagar = [p for sql, p in cursor.instrucoes if sql.startswith("delete from raw.registro")]
        self.assertEqual(apagar, [(TENANT, "crm/reservas", ["193_30"])])


class TesteCarregador(unittest.TestCase):
    def test_carga_incremental_filtra_grava_recarrega_e_avanca_marca(self):
        conexao = ConexaoFalsa({"crm/repasses": "2026-09-01"})
        fonte = FonteFalsa({"crm/repasses": [[
            {"idrepasse": 1, "referencia_data": "2026-09-03 08:00:00", "cliente": "Pessoa Qualquer"},
            {"idrepasse": 2, "referencia_data": "2026-09-05 08:00:00"},
        ]]})
        resumo = carregar_crm.carregar(conexao, TENANT, fonte)

        self.assertEqual(resumo["crm/repasses"], 2)
        self.assertIn(("crm/repasses", "2026-09-01"), fonte.pedidos)
        self.assertIn(("crm/leads", None), fonte.pedidos)
        self.assertTrue(conexao.confirmada)
        instrucoes = conexao.cursor_falso.instrucoes
        insercoes = [p for sql, p in instrucoes if sql.startswith("insert into raw.registro")]
        self.assertEqual(len(insercoes), 1)
        payloads = [json.loads(linha[2]) for linha in insercoes[0]]
        self.assertTrue(all("cliente" not in p for p in payloads))
        self.assertEqual([linha[4] for linha in insercoes[0]], ["1", "2"])
        apagadas = [p for sql, p in instrucoes if sql.startswith("delete from raw.registro")]
        self.assertEqual(apagadas, [(TENANT, "crm/repasses", ["1", "2"])])
        posicao_recarga = next(i for i, (sql, _) in enumerate(instrucoes) if "staging.recarregar_crm" in sql)
        marcas = [(i, p) for i, (sql, p) in enumerate(instrucoes) if sql.startswith("insert into app.marca_carga")]
        self.assertEqual([p for _, p in marcas], [(TENANT, "crm/repasses", "2026-09-05")])
        self.assertTrue(all(i > posicao_recarga for i, _ in marcas))

    def test_falha_no_meio_desfaz_tudo_e_nao_avanca_marca(self):
        conexao = ConexaoFalsa()
        fonte = FonteFalsa({"crm/repasses": [[{"idrepasse": 1, "referencia_data": "2026-09-03 08:00:00"}]]},
                           falhar_em="crm/reservas")
        with self.assertRaises(ErroCrm):
            carregar_crm.carregar(conexao, TENANT, fonte)
        self.assertTrue(conexao.desfeita)
        self.assertFalse(conexao.confirmada)

    def test_carga_completa_ignora_marca(self):
        conexao = ConexaoFalsa({"crm/repasses": "2026-09-01"})
        fonte = FonteFalsa({})
        carregar_crm.carregar(conexao, TENANT, fonte, completa=True)
        self.assertIn(("crm/repasses", None), fonte.pedidos)

    def test_fonte_pasta_filtra_por_data_como_a_api(self):
        with tempfile.TemporaryDirectory() as pasta:
            Path(pasta, "leads.json").write_text(json.dumps({"dados": [
                {"idlead": 1, "referencia_data": "2026-08-01 10:00:00"},
                {"idlead": 2, "referencia_data": "2026-09-10 10:00:00"},
            ]}), encoding="utf-8")
            fonte = carregar_crm.FontePasta(pasta)
            self.assertEqual([r["idlead"] for p in fonte.paginas("crm/leads", "2026-09-01") for r in p], [2])
            self.assertEqual(list(fonte.paginas("crm/repasses", None)), [])


class TesteGerador(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.contratos = gerar_dados_crm.ler("sales.json")
        cls.unidades = gerar_dados_crm.ler("units.json")
        cls.arquivos = gerar_dados_crm.gerar(cls.contratos, cls.unidades)

    def test_deterministico(self):
        self.assertEqual(gerar_dados_crm.gerar(self.contratos, self.unidades), self.arquivos)

    def test_nenhum_campo_pessoal_e_tudo_passa_no_filtro(self):
        por_arquivo = {c["arquivo"]: endpoint for endpoint, c in carregar_crm.ENDPOINTS.items()}
        for nome, registros in self.arquivos.items():
            with self.subTest(arquivo=nome):
                endpoint = por_arquivo[nome]
                for registro in registros:
                    self.assertFalse(set(registro) & CAMPOS_PESSOAIS)
                    self.assertEqual(carregar_crm.filtrar_campos(endpoint, registro), registro)

    def test_reserva_vendida_aponta_para_contrato_do_erp(self):
        ids_contrato = {c["id"] for c in self.contratos}
        vendidas = [r for r in self.arquivos["reservas.json"] if r.get("venda") == "Sim"]
        self.assertEqual(len(vendidas), len(self.contratos))
        self.assertEqual({int(r["codigointerno"]) for r in vendidas}, ids_contrato)
        self.assertEqual({int(v["codigointerno"]) for v in self.arquivos["reservas_vinculo_erp.json"]}, ids_contrato)
        nomes_unidade = {u["name"] for u in self.unidades}
        self.assertTrue(all(r["unidade"] in nomes_unidade for r in self.arquivos["reservas.json"]))

    def test_repasse_so_para_contrato_financiado_e_com_as_quatro_etapas(self):
        financiados = {c["number"] for c in self.contratos if c["financialInstitutionNumber"]}
        repasses = self.arquivos["repasses.json"]
        self.assertEqual({r["numero_contrato"] for r in repasses}, financiados)
        ids_reserva = {r["idreserva"] for r in self.arquivos["reservas.json"]}
        self.assertTrue(all(r["reserva"] in ids_reserva for r in repasses))
        liberados = [r for r in repasses if r["data_recurso_liberado"]]
        assinados = [r for r in repasses if r["data_assinatura_de_contrato"] and not r["data_recurso_liberado"]]
        em_analise = [r for r in repasses if not r["data_assinatura_de_contrato"] and r["situacao"] != "Cancelado"]
        # atrasado: obra entregue, sem recurso liberado, com a FI ainda aberta no ERP
        atrasados = [r for r in repasses if r["codigointerno_empreendimento"] == "103" and not r["data_recurso_liberado"]]
        for etapa in (liberados, assinados, em_analise, atrasados):
            self.assertTrue(etapa)
        repassados_no_erp = {c["number"] for c in self.contratos if c["financialInstitutionDate"]}
        self.assertEqual({r["numero_contrato"] for r in liberados}, repassados_no_erp)
        for repasse in liberados:
            self.assertLessEqual(repasse["data_assinatura_de_contrato"], repasse["data_recurso_liberado"])

    def test_caixa_na_maioria_e_banco_lento_demora_mais(self):
        repasses = self.arquivos["repasses.json"]
        por_banco = {}
        for repasse in repasses:
            por_banco.setdefault(repasse["banco"], []).append(repasse)
        self.assertEqual(set(por_banco), {nome for nome, _ in gerar_dados_crm.BANCOS})
        self.assertGreater(len(por_banco["Caixa Econômica Federal"]), len(repasses) / 2)

        def prazo_medio(banco):
            prazos = [
                (date.fromisoformat(r["data_recurso_liberado"]) - date.fromisoformat(r["data_assinatura_de_contrato"])).days
                for r in por_banco[banco] if r["data_recurso_liberado"]
            ]
            self.assertGreaterEqual(len(prazos), 2, banco)
            return sum(prazos) / len(prazos)

        lento = prazo_medio(gerar_dados_crm.BANCO_LENTO)
        for banco in por_banco:
            if banco != gerar_dados_crm.BANCO_LENTO:
                self.assertGreater(lento, prazo_medio(banco) * 1.5, banco)

    def test_leads_por_obra_da_demo(self):
        codigos = {c for lead in self.arquivos["leads.json"] for c in lead["codigointerno_empreendimento"].split(";")}
        self.assertEqual(codigos, {"101", "102", "103"})


if __name__ == "__main__":
    unittest.main()
