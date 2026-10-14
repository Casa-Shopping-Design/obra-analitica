"""Confere o balancete sintético da demo sem banco: partida dobrada, passagens, identidades e privacidade."""

import contextlib
import io
import json
import sys
import tempfile
import unittest
from collections import defaultdict
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import gerar_dados_contabeis as gerador  # noqa: E402
from gerar_dados_demo import NOMES, SOBRENOMES  # noqa: E402

PASTA_BALANCETE = Path(__file__).resolve().parent.parent.parent / "dados"
PASTA_CONTABIL = PASTA_BALANCETE / "contabil"

# O balancete fica fora do git, como income.json; o gerador tem semente fixa e refaz o mesmo arquivo.
if not (PASTA_CONTABIL / "trial-balance.json").exists():
    with contextlib.redirect_stdout(io.StringIO()):
        gerador.main()

EMPRESAS_SPE = (11, 12, 13)
PARQUE = 12
TORRE = 13
MESES = [f"{ano}-{mes:02d}-01" for ano, mes in [(2025, m) for m in range(1, 13)] + [(2026, m) for m in range(1, 11)]]

# Catálogo de linhas do contrato (ids), por demonstrativo. Só o que o teste precisa: pertencimento.
CAIXA = {"bancos", "aplicacoes_financeiras", "caixa"}
FONTES_USOS = {
    "lucros_acumulados", "reserva_legal", "dividendos_pagar_participantes", "dividendos_pagar_ostensivos",
    "dividendos_pagar", "provisao_assistencia_tecnica", "resultado_diferido", "adiantamento_clientes",
    "emprestimos_bancarios", "fornecedores", "impostos_pagar", "obrigacoes_terreno", "salarios_pagar",
    "taxa_administracao_pagar", "receber_incorporacao", "receber_ajustes_pdd", "receber_cartao",
    "receber_outras_atividades", "taxa_administracao_receber", "estoque_imoveis_construcao",
    "estoque_almoxarifado", "estoque_projetos", "adiantamentos_terceiros", "impostos_recuperar",
    "depositos_judiciais", "corretagem_apropriada", "corretagem_apropriar", "marketing_institucional",
    "despesas_diferidas", "seguro_apropriar", "aporte_capital", "capital_especial", "mutuo_pagar",
    "saldo_pagar_terreno", "dividendos_receber", "mutuo_receber", "equivalencia_patrimonial", "participacoes_spe",
    "aplicacoes_longo_prazo", "depreciacao_acumulada", "imobilizado",
}
GRUPO_LUCROS_ACUMULADOS = {
    "lucros_acumulados", "reserva_legal", "dividendos_pagar_participantes", "dividendos_pagar_ostensivos",
    "dividendos_pagar",
}
DRE = {
    "receita_vendas_incorporacao", "juros_tabela_price", "ganho_distrato", "receita_servicos", "outras_receitas",
    "impostos_vendas", "perdas_vendas_canceladas", "vendas_canceladas_abatimentos", "custo_unidades_vendidas",
    "custo_assistencia_tecnica", "outros_custos", "juros_financiamento_obra", "custo_venda_terreno", "corretagem",
    "publicidade", "despesas_administrativas", "sentencas", "servicos_terceiros_despesa", "despesas_tributarias",
    "taxa_administracao_central", "depreciacao", "outras_despesas", "despesas_financeiras", "receitas_financeiras",
    "receita_equivalencia", "receita_participacao", "irpj_csll",
}
CUSTO_INCORRIDO = {
    "custo_terreno", "custo_projetos", "custo_legalizacao", "materiais_aplicados", "salarios_proventos",
    "encargos_sociais", "encargos_complementares", "servicos_terceiros_obra", "gastos_gerais_obra",
}
FORA = {"apropriacao_mao_obra", "transferencia_custo_estoque", "apuracao_resultado", "saldo_abertura"}
CATALOGO = CAIXA | FONTES_USOS | DRE | CUSTO_INCORRIDO | FORA
AJUSTE_TORRE = 3_675_000


def centavos(valor):
    return round(valor * 100)


def saldo_com_sinal(bloco):
    """Saldo devedor positivo, credor negativo, em centavos."""
    valor = centavos(bloco["value"])
    return valor if bloco["type"] == "D" else -valor


def linha_da_conta(conta, mapa):
    if conta in mapa:
        return mapa[conta]
    partes = conta.split(".")
    for n in range(len(partes) - 1, 0, -1):
        prefixo = ".".join(partes[:n])
        if prefixo in mapa:
            return mapa[prefixo]
    return None


class Balancete:
    """Carrega os JSON uma vez e indexa por empresa, mês e passagem."""

    def __init__(self):
        self.registros = json.loads((PASTA_CONTABIL / "trial-balance.json").read_text(encoding="utf-8"))["results"]
        self.mapa = {i["conta"]: i["linha"] for i in json.loads(
            (PASTA_CONTABIL / "mapa-contas.json").read_text(encoding="utf-8"))}
        self.por_chave = defaultdict(dict)
        for r in self.registros:
            self.por_chave[(r["companyId"], r["initialPeriod"], r["desconsiderClosingBalance"])][r["account"]] = r

    def analiticas(self, empresa, mes, sem_zeramento):
        return {c: r for c, r in self.por_chave[(empresa, mes, sem_zeramento)].items()
                if r["accountType"] == "ANALYTICAL"}

    def soma_por_linha(self, empresa, mes, sem_zeramento, linhas, campo="current"):
        return sum(saldo_com_sinal(r["balances"][campo]) for c, r in self.analiticas(empresa, mes, sem_zeramento).items()
                   if linha_da_conta(c, self.mapa) in linhas)

    def sem_mapa(self, empresa, mes, sem_zeramento):
        return {c: r for c, r in self.analiticas(empresa, mes, sem_zeramento).items()
                if linha_da_conta(c, self.mapa) is None}


BALANCETE = Balancete()


class TesteFormato(unittest.TestCase):
    def test_um_registro_por_conta_empresa_mes_e_passagem(self):
        chaves = [(r["companyId"], r["account"], r["initialPeriod"], r["desconsiderClosingBalance"])
                  for r in BALANCETE.registros]
        self.assertEqual(len(chaves), len(set(chaves)))
        self.assertEqual({r["companyId"] for r in BALANCETE.registros}, set(EMPRESAS_SPE))

    def test_meses_de_janeiro_de_2025_a_outubro_de_2026_nas_duas_passagens(self):
        for empresa in EMPRESAS_SPE:
            for sem_zeramento in (False, True):
                meses = sorted({r["initialPeriod"] for r in BALANCETE.registros
                                if r["companyId"] == empresa and r["desconsiderClosingBalance"] is sem_zeramento})
                self.assertEqual(meses, MESES, (empresa, sem_zeramento))

    def test_mesmas_contas_nas_duas_passagens_e_em_todos_os_meses(self):
        for empresa in EMPRESAS_SPE:
            conjuntos = {frozenset(BALANCETE.por_chave[(empresa, mes, sem)]) for mes in MESES for sem in (False, True)}
            self.assertEqual(len(conjuntos), 1, empresa)

    def test_campos_do_contrato_e_tipos(self):
        campos = {"companyId", "reducedCode", "accountGroup", "account", "accountName", "accountType", "debit",
                  "credit", "operatingBalance", "balances", "initialPeriod", "desconsiderClosingBalance"}
        for r in BALANCETE.registros:
            self.assertEqual(set(r), campos)
            self.assertIn(r["accountType"], ("ANALYTICAL", "SYNTHETIC"))
            self.assertIn(r["accountGroup"], ("ASSETS", "LIABILITIES", "INCOME", "EXPENSES", "TRANSITION"))
            self.assertRegex(r["initialPeriod"], r"^\d{4}-\d{2}-01$")
            self.assertIsInstance(r["desconsiderClosingBalance"], bool)
            for bloco in (r["operatingBalance"], r["balances"]["previous"], r["balances"]["current"]):
                self.assertIn(bloco["type"], ("D", "C"))
                self.assertGreaterEqual(bloco["value"], 0)

    def test_codigo_reduzido_unico_por_conta_e_igual_entre_empresas(self):
        codigos = defaultdict(set)
        for r in BALANCETE.registros:
            codigos[r["account"]].add(r["reducedCode"])
        self.assertTrue(all(len(v) == 1 for v in codigos.values()))
        todos = [next(iter(v)) for v in codigos.values()]
        self.assertEqual(len(todos), len(set(todos)))

    def test_mascara_e_sintetica_so_com_filhas(self):
        for r in BALANCETE.registros:
            self.assertRegex(r["account"], r"^\d(\.\d(\.\d(\.\d{2}(\.\d{4})?)?)?)?$")
            niveis = r["account"].count(".")
            self.assertEqual(r["accountType"] == "ANALYTICAL", niveis == 4, r["account"])

    def test_sintetica_e_a_soma_das_analiticas_filhas(self):
        for empresa in EMPRESAS_SPE:
            for mes in (MESES[0], MESES[9], MESES[-1]):
                for sem in (False, True):
                    contas = BALANCETE.por_chave[(empresa, mes, sem)]
                    for conta, r in contas.items():
                        if r["accountType"] != "SYNTHETIC":
                            continue
                        filhas = [f for c, f in contas.items() if c.startswith(conta + ".") and
                                  f["accountType"] == "ANALYTICAL"]
                        self.assertEqual(sum(saldo_com_sinal(f["balances"]["current"]) for f in filhas),
                                         saldo_com_sinal(r["balances"]["current"]), (empresa, mes, conta))
                        self.assertEqual(sum(centavos(f["debit"]) for f in filhas), centavos(r["debit"]))


class TestePartidaDobrada(unittest.TestCase):
    def test_soma_dos_saldos_finais_com_sinal_e_zero_nas_duas_passagens(self):
        for empresa in EMPRESAS_SPE:
            for mes in MESES:
                for sem in (False, True):
                    soma = sum(saldo_com_sinal(r["balances"]["current"]) for r in BALANCETE.analiticas(empresa, mes, sem).values())
                    self.assertEqual(soma, 0, (empresa, mes, sem))

    def test_soma_dos_saldos_anteriores_tambem_e_zero(self):
        for empresa in EMPRESAS_SPE:
            for mes in MESES:
                for sem in (False, True):
                    soma = sum(saldo_com_sinal(r["balances"]["previous"]) for r in BALANCETE.analiticas(empresa, mes, sem).values())
                    self.assertEqual(soma, 0, (empresa, mes, sem))

    def test_debito_total_igual_ao_credito_total(self):
        for empresa in EMPRESAS_SPE:
            for mes in MESES:
                for sem in (False, True):
                    analiticas = BALANCETE.analiticas(empresa, mes, sem).values()
                    self.assertEqual(sum(centavos(r["debit"]) for r in analiticas),
                                     sum(centavos(r["credit"]) for r in analiticas), (empresa, mes, sem))

    def test_saldo_final_e_saldo_anterior_mais_debito_menos_credito(self):
        for empresa in EMPRESAS_SPE:
            for mes in MESES:
                for sem in (False, True):
                    for conta, r in BALANCETE.por_chave[(empresa, mes, sem)].items():
                        esperado = (saldo_com_sinal(r["balances"]["previous"])
                                    + centavos(r["debit"]) - centavos(r["credit"]))
                        self.assertEqual(saldo_com_sinal(r["balances"]["current"]), esperado, (empresa, mes, conta))
                        self.assertEqual(saldo_com_sinal(r["operatingBalance"]),
                                         centavos(r["debit"]) - centavos(r["credit"]))

    def test_saldo_anterior_do_mes_e_o_saldo_final_do_mes_anterior(self):
        for empresa in EMPRESAS_SPE:
            for sem in (False, True):
                for anterior, mes in zip(MESES, MESES[1:]):
                    for conta, r in BALANCETE.por_chave[(empresa, mes, sem)].items():
                        final_anterior = BALANCETE.por_chave[(empresa, anterior, sem)][conta]["balances"]["current"]
                        self.assertEqual(saldo_com_sinal(r["balances"]["previous"]), saldo_com_sinal(final_anterior),
                                         (empresa, mes, sem, conta))


class TestePassagens(unittest.TestCase):
    def contas_de_resultado(self, empresa, mes, sem):
        return {c: r for c, r in BALANCETE.analiticas(empresa, mes, sem).items() if c[0] in "3456"}

    def test_com_zeramento_o_resultado_fica_zerado_no_fim_do_mes(self):
        for empresa in EMPRESAS_SPE:
            for mes in MESES:
                for conta, r in self.contas_de_resultado(empresa, mes, False).items():
                    self.assertEqual(saldo_com_sinal(r["balances"]["current"]), 0, (empresa, mes, conta))
                    self.assertEqual(saldo_com_sinal(r["balances"]["previous"]), 0, (empresa, mes, conta))

    def test_com_zeramento_o_lucro_do_mes_passa_para_lucros_acumulados(self):
        conta_lucros = gerador.LUCROS
        for empresa in EMPRESAS_SPE:
            for mes in MESES:
                resultado_sem = -sum(centavos(r["debit"]) - centavos(r["credit"])
                                     for c, r in self.contas_de_resultado(empresa, mes, True).items() if c[0] in "34")
                lucros_com = BALANCETE.por_chave[(empresa, mes, False)][conta_lucros]
                lucros_sem = BALANCETE.por_chave[(empresa, mes, True)][conta_lucros]
                # Na passagem sem zeramento o lucro não é transferido; na outra, entra pelo crédito.
                transferido = (centavos(lucros_com["credit"]) - centavos(lucros_com["debit"])) - (
                    centavos(lucros_sem["credit"]) - centavos(lucros_sem["debit"]))
                self.assertEqual(transferido, resultado_sem, (empresa, mes))

    def test_sem_zeramento_o_resultado_acumula_desde_o_inicio(self):
        for empresa in EMPRESAS_SPE:
            receita = gerador.RECEITA_VENDAS
            antes = saldo_com_sinal(BALANCETE.por_chave[(empresa, MESES[0], True)][receita]["balances"]["previous"])
            self.assertLess(antes, 0, "o resultado de antes de jan/2025 continua no saldo anterior")
            saldos = [-saldo_com_sinal(BALANCETE.por_chave[(empresa, mes, True)][receita]["balances"]["current"])
                      for mes in MESES]
            self.assertTrue(all(b >= a for a, b in zip(saldos, saldos[1:])), "a receita acumulada nunca diminui")
            self.assertGreater(saldos[-1], saldos[0])

    def test_sem_zeramento_o_resultado_nao_tem_lancamento_de_zeramento(self):
        for empresa in EMPRESAS_SPE:
            for mes in MESES:
                apuracao = BALANCETE.por_chave[(empresa, mes, True)][gerador.APURACAO]
                self.assertEqual((apuracao["debit"], apuracao["credit"]), (0, 0), (empresa, mes))
                com = BALANCETE.por_chave[(empresa, mes, False)][gerador.APURACAO]
                self.assertGreater(com["debit"] + com["credit"], 0, (empresa, mes))

    def test_balancos_patrimoniais_iguais_nas_duas_passagens_exceto_lucros_acumulados(self):
        for empresa in EMPRESAS_SPE:
            for mes in MESES:
                com, sem = BALANCETE.analiticas(empresa, mes, False), BALANCETE.analiticas(empresa, mes, True)
                for conta in com:
                    if conta[0] in "12" and conta != gerador.LUCROS:
                        self.assertEqual(com[conta]["balances"]["current"], sem[conta]["balances"]["current"],
                                         (empresa, mes, conta))


class TesteIdentidades(unittest.TestCase):
    def test_caixa_no_fim_do_mes_e_fontes_menos_usos(self):
        for empresa in EMPRESAS_SPE:
            for mes in MESES:
                caixa = BALANCETE.soma_por_linha(empresa, mes, False, CAIXA)
                fontes_menos_usos = -BALANCETE.soma_por_linha(empresa, mes, False, FONTES_USOS)
                sem_mapa = sum(saldo_com_sinal(r["balances"]["current"])
                               for r in BALANCETE.sem_mapa(empresa, mes, False).values())
                # Conta de balanço sem linha fica de fora dos dois lados e aparece como diferença.
                self.assertEqual(fontes_menos_usos - caixa, sem_mapa, (empresa, mes))
                if empresa != PARQUE:
                    self.assertEqual(fontes_menos_usos, caixa, (empresa, mes))

    def test_caixa_nunca_fica_negativo(self):
        for empresa in EMPRESAS_SPE:
            for mes in MESES:
                self.assertGreaterEqual(BALANCETE.soma_por_linha(empresa, mes, False, CAIXA), 0, (empresa, mes))

    def test_custo_incorrido_e_estoque_mais_cmv(self):
        for empresa in EMPRESAS_SPE:
            for mes in MESES:
                custo = BALANCETE.soma_por_linha(empresa, mes, True, CUSTO_INCORRIDO)
                estoque = BALANCETE.soma_por_linha(empresa, mes, False, {"estoque_imoveis_construcao"})
                cmv = BALANCETE.soma_por_linha(empresa, mes, True, {"custo_unidades_vendidas"})
                self.assertEqual(custo, estoque + cmv, (empresa, mes))

    def test_percentual_levado_ao_resultado_fica_entre_zero_e_cem(self):
        for empresa in EMPRESAS_SPE:
            custo = BALANCETE.soma_por_linha(empresa, MESES[-1], True, CUSTO_INCORRIDO)
            cmv = BALANCETE.soma_por_linha(empresa, MESES[-1], True, {"custo_unidades_vendidas"})
            self.assertTrue(0 < cmv / custo < 1, empresa)

    def test_lucro_da_dre_fecha_com_lucros_acumulados_exceto_o_ajuste_de_exercicio_anterior(self):
        for empresa in EMPRESAS_SPE:
            for mes in MESES:
                lucro_dre = -BALANCETE.soma_por_linha(empresa, mes, True, DRE)
                lucros_acumulados = -BALANCETE.soma_por_linha(empresa, mes, False, GRUPO_LUCROS_ACUMULADOS)
                ajuste = lucros_acumulados - lucro_dre
                esperado = AJUSTE_TORRE if empresa == TORRE and mes >= "2026-03-01" else 0
                self.assertEqual(ajuste, esperado, (empresa, mes))

    def test_ajuste_de_exercicio_anterior_nao_passa_pelo_resultado(self):
        resultado = [r for r in BALANCETE.analiticas(TORRE, "2026-03-01", True).values()
                     if r["account"][0] in "345" and r["account"] != gerador.TRANSFERENCIA_ESTOQUE]
        movimento_ajuste = BALANCETE.por_chave[(TORRE, "2026-03-01", True)][gerador.AJUSTE_ANTERIOR]
        self.assertEqual(centavos(movimento_ajuste["credit"]), AJUSTE_TORRE)
        self.assertTrue(resultado)

    def test_as_tres_spes_tem_perfil_proprio(self):
        lucros = {e: -BALANCETE.soma_por_linha(e, MESES[-1], True, DRE) for e in EMPRESAS_SPE}
        self.assertGreater(lucros[11], 0)
        self.assertGreater(lucros[13], 0)
        self.assertLess(lucros[PARQUE], 0)


class TesteMapa(unittest.TestCase):
    def test_so_linhas_do_catalogo_e_sem_repeticao(self):
        contas = list(BALANCETE.mapa)
        itens = json.loads((PASTA_CONTABIL / "mapa-contas.json").read_text(encoding="utf-8"))
        self.assertEqual(len(itens), len(contas))
        for item in itens:
            self.assertEqual(set(item), {"conta", "linha"})
            self.assertIn(item["linha"], CATALOGO)

    def test_todo_prefixo_mapeado_existe_no_plano_como_sintetica(self):
        sinteticas = {r["account"] for r in BALANCETE.registros if r["accountType"] == "SYNTHETIC"}
        analiticas = {r["account"] for r in BALANCETE.registros if r["accountType"] == "ANALYTICAL"}
        prefixos = [c for c in BALANCETE.mapa if c in sinteticas]
        self.assertGreaterEqual(len(prefixos), 3, "a herança por prefixo precisa de exemplos")
        self.assertTrue(all(c in sinteticas or c in analiticas for c in BALANCETE.mapa))

    def test_herdeira_de_prefixo_e_a_conta_propria_vence(self):
        mapa = BALANCETE.mapa
        self.assertNotIn(gerador.BANCO_VINCULADO, mapa)
        self.assertEqual(linha_da_conta(gerador.BANCO_VINCULADO, mapa), "bancos")
        self.assertEqual(linha_da_conta(gerador.SEGUROS, mapa), "despesas_administrativas")
        self.assertEqual(linha_da_conta(gerador.OUTRAS_DESPESAS, mapa), "outras_despesas")
        self.assertEqual(linha_da_conta(gerador.SENTENCAS, mapa), "sentencas")

    def test_cada_linha_de_conta_do_catalogo_usada_tem_conta_na_demo(self):
        usadas = {linha_da_conta(r["account"], BALANCETE.mapa) for r in BALANCETE.registros if r["accountType"] == "ANALYTICAL"}
        sem_conta_na_demo = (FONTES_USOS | DRE | CUSTO_INCORRIDO) - usadas
        # Linhas que só fazem sentido em holding ou em outro tipo de empresa ficam de fora de propósito.
        esperado_fora = {
            "resultado_diferido", "receber_cartao", "receber_outras_atividades", "taxa_administracao_receber",
            "estoque_projetos", "marketing_institucional", "despesas_diferidas", "dividendos_receber",
            "mutuo_receber", "equivalencia_patrimonial", "participacoes_spe", "aplicacoes_longo_prazo",
            "custo_venda_terreno", "receita_equivalencia", "receita_participacao",
        }
        self.assertEqual(sem_conta_na_demo, esperado_fora)

    def test_conta_sem_mapa_so_na_spe_do_parque(self):
        for empresa in EMPRESAS_SPE:
            sem_mapa = BALANCETE.sem_mapa(empresa, MESES[-1], False)
            if empresa == PARQUE:
                self.assertEqual(list(sem_mapa), [gerador.ADIANTAMENTO_CONCILIAR])
                conta = sem_mapa[gerador.ADIANTAMENTO_CONCILIAR]
                self.assertGreater(saldo_com_sinal(conta["balances"]["current"]), 0)
                self.assertLess(saldo_com_sinal(conta["balances"]["current"]), 5_000_000)
                self.assertGreater(sum(centavos(r["debit"]) for r in
                                       [BALANCETE.por_chave[(empresa, m, False)][gerador.ADIANTAMENTO_CONCILIAR]
                                        for m in MESES]), 0)
            else:
                self.assertEqual(sem_mapa, {}, empresa)


class TesteCadastro(unittest.TestCase):
    def test_construtora_e_tres_spes(self):
        empresas = json.loads((PASTA_BALANCETE / "companies.json").read_text(encoding="utf-8"))["data"]
        self.assertEqual([e["id"] for e in empresas], [1, 11, 12, 13])
        self.assertEqual(empresas[1]["name"], "Aurora Empreendimento SPE Ltda")
        self.assertEqual(empresas[2]["name"], "Parque das Águas Empreendimento SPE Ltda")
        self.assertEqual(empresas[3]["name"], "Torre Sul Empreendimento SPE Ltda")
        self.assertEqual(json.loads((PASTA_CONTABIL / "companies.json").read_text(encoding="utf-8"))["data"], empresas)

    def test_cada_obra_aponta_para_a_sua_spe_e_a_holding_nao_tem_obra(self):
        centros = json.loads((PASTA_BALANCETE / "cost-centers.json").read_text(encoding="utf-8"))["data"]
        self.assertEqual({c["id"]: c["idCompany"] for c in centros}, {101: 11, 102: 12, 103: 13})

    def test_seed_aponta_as_mesmas_empresas(self):
        seed = (Path(__file__).resolve().parent.parent.parent / "supabase" / "seed.sql").read_text(encoding="utf-8")
        for obra, empresa in ((101, 11), (102, 12), (103, 13)):
            self.assertRegex(seed, rf"', {obra}, '[^']+', {empresa}\)")


class TestePrivacidade(unittest.TestCase):
    def test_nenhum_nome_de_pessoa_no_plano_de_contas(self):
        proibidos = set(NOMES) | set(SOBRENOMES)
        for r in BALANCETE.registros:
            palavras = set(r["accountName"].replace("-", " ").replace("(", " ").replace(")", " ").split())
            self.assertFalse(palavras & proibidos, r["accountName"])

    def test_sem_terceiros_nem_campos_extras(self):
        texto = (PASTA_CONTABIL / "trial-balance.json").read_text(encoding="utf-8")
        self.assertNotIn("thirdParties", texto)

    def test_cnpj_das_empresas_e_de_demo(self):
        empresas = json.loads((PASTA_BALANCETE / "companies.json").read_text(encoding="utf-8"))["data"]
        self.assertTrue(all(e["cnpj"].startswith("12.345.") for e in empresas))


class TesteDeterminismo(unittest.TestCase):
    def test_gerar_de_novo_reproduz_os_arquivos_gravados(self):
        with tempfile.TemporaryDirectory() as pasta, mock.patch.object(gerador, "PASTA_SAIDA", Path(pasta)):
            with contextlib.redirect_stdout(io.StringIO()):
                gerador.main()
            for arquivo in ("companies.json", "trial-balance.json", "mapa-contas.json"):
                self.assertEqual((Path(pasta) / arquivo).read_bytes(), (PASTA_CONTABIL / arquivo).read_bytes(), arquivo)


class TesteCarregadorDemo(unittest.TestCase):
    """Parte do carregar_demo que não precisa de banco: leitura, filtro, chave e gravação do mapa."""

    @classmethod
    def setUpClass(cls):
        import carregar_demo
        from carregar_origem import chave_origem
        cls.carregar_demo = carregar_demo
        cls.chave_origem = staticmethod(chave_origem)

    def test_leitura_filtra_pelos_campos_permitidos_e_as_chaves_nao_repetem(self):
        from campos_permitidos import CAMPOS_PERMITIDOS
        if "trial-balance" not in CAMPOS_PERMITIDOS or "companies" not in CAMPOS_PERMITIDOS:
            self.skipTest("campos_permitidos ainda sem companies e trial-balance")
        contabeis = self.carregar_demo.ler_dados_contabeis()
        self.assertEqual(set(contabeis), {"companies", "trial-balance"})
        self.assertEqual(len(contabeis["companies"]), 4)
        self.assertEqual(len(contabeis["trial-balance"]), len(BALANCETE.registros))
        chaves = [self.chave_origem("trial-balance", r) for r in contabeis["trial-balance"]]
        self.assertNotIn(None, chaves)
        self.assertEqual(len(chaves), len(set(chaves)))
        self.assertEqual(sorted(self.chave_origem("companies", r) for r in contabeis["companies"]),
                         ["1", "11", "12", "13"])

    def test_pasta_inexistente_mantem_o_comportamento_anterior(self):
        with tempfile.TemporaryDirectory() as pasta:
            vazia = Path(pasta) / "nao_existe"
            self.assertEqual(self.carregar_demo.ler_dados_contabeis(vazia), {})
            self.assertEqual(self.carregar_demo.ler_mapa_demo(vazia / "mapa-contas.json"), [])

    def test_mapa_da_demo_vira_pares_conta_linha(self):
        itens = self.carregar_demo.ler_mapa_demo()
        self.assertEqual(dict(itens), BALANCETE.mapa)

    def test_mapa_so_e_gravado_no_tenant_sem_mapa(self):
        itens = [("1.1.1.02", "bancos"), ("1.1.1.01.0001", "caixa")]
        for ja_tem_mapa, esperado in ((False, 2), (True, 0)):
            conexao = ConexaoFalsa(ja_tem_mapa)
            with contextlib.redirect_stdout(io.StringIO()):
                gravados = self.carregar_demo.gravar_mapa_demo(conexao, "tenant-teste", itens)
            self.assertEqual(gravados, esperado)
            self.assertEqual(len(conexao.insercoes), esperado)
            self.assertEqual(conexao.confirmacoes, 1 if esperado else 0)
            if esperado:
                self.assertEqual(conexao.insercoes[0], ("tenant-teste", "1.1.1.02", "bancos", "demo"))

    def test_sem_itens_nao_consulta_o_banco(self):
        conexao = ConexaoFalsa(False)
        self.assertEqual(self.carregar_demo.gravar_mapa_demo(conexao, "tenant-teste", []), 0)
        self.assertEqual(conexao.consultas, [])


class ConexaoFalsa:
    def __init__(self, ja_tem_mapa):
        self.ja_tem_mapa = ja_tem_mapa
        self.consultas, self.insercoes, self.confirmacoes = [], [], 0

    def cursor(self):
        return self

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def execute(self, sql, parametros=None):
        self.consultas.append(sql)

    def fetchone(self):
        return (self.ja_tem_mapa,)

    def executemany(self, sql, linhas):
        self.insercoes.extend(linhas)

    def commit(self):
        self.confirmacoes += 1


if __name__ == "__main__":
    unittest.main()
