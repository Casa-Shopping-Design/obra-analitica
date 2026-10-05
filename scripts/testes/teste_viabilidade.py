import sys
import unittest
import uuid
from decimal import Decimal
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from carregar_demo import (  # noqa: E402
    MESES_HISTORICO_DEMO, fatores_historico_demo, gravar_historico_demo, gravar_viabilidade_demo, ler_estudos,
    registrar_posicao_dre,
)
from teste_carregar_origem import banco_local  # noqa: E402

LINHAS_DIGITAVEIS = {
    "vgv_bruto", "impostos", "custo_terreno", "custo_projetos", "custo_licenciamento", "custo_construcao",
    "assistencia_tecnica", "juros_financiamento", "estoque", "despesas_comerciais", "despesas_administrativas",
}
# Lucro operacional conferido a mao: VGV menos impostos, custo de vendas e despesas. A Torre tem aliquota de
# 6,32% (lucro presumido); Aurora e Parque, 4% (RET).
LUCRO_OPERACIONAL = {101: 5_320_000, 102: 3_350_000, 103: 829_120}


class TesteArquivoEstudos(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.estudos = ler_estudos()

    def test_tres_obras_da_demo(self):
        self.assertEqual(sorted(e["id_origem"] for e in self.estudos), [101, 102, 103])

    def test_onze_linhas_digitaveis_em_cada_obra(self):
        for estudo in self.estudos:
            self.assertEqual(set(estudo["linhas"]), LINHAS_DIGITAVEIS, estudo["id_origem"])

    def test_nenhum_valor_negativo(self):
        for estudo in self.estudos:
            self.assertTrue(all(valor >= 0 for valor in estudo["linhas"].values()), estudo["id_origem"])
            self.assertTrue(0 <= estudo["aliquota"] <= 0.2, estudo["id_origem"])

    def test_lucro_operacional_fecha_com_a_conta_do_plano(self):
        for estudo in self.estudos:
            linhas = estudo["linhas"]
            custo_vendas = sum(linhas[l] for l in ("custo_terreno", "custo_projetos", "custo_licenciamento",
                                                   "custo_construcao", "assistencia_tecnica", "juros_financiamento",
                                                   "estoque"))
            despesas = linhas["despesas_comerciais"] + linhas["despesas_administrativas"]
            lucro = linhas["vgv_bruto"] - linhas["impostos"] - custo_vendas - despesas
            self.assertEqual(lucro, LUCRO_OPERACIONAL[estudo["id_origem"]], estudo["id_origem"])

    def test_sem_arquivo_nao_ha_estudo(self):
        self.assertEqual(ler_estudos(Path("/caminho/que/nao/existe.json")), [])


class TesteHistoricoDemo(unittest.TestCase):
    """Fatores do historico ficticio: onze por linha, do mes -11 ao -1, terminando em 1,00 no mes -1."""

    @classmethod
    def setUpClass(cls):
        cls.estudos = ler_estudos()
        cls.historico = {e["id_origem"]: e["historico_demo"] for e in cls.estudos}

    def test_onze_fatores_para_vgv_e_construcao_em_cada_obra(self):
        for id_origem, historico in self.historico.items():
            self.assertEqual(set(historico), {"vgv_bruto", "custo_construcao"}, id_origem)
            for linha, fatores in historico.items():
                self.assertEqual(len(fatores), MESES_HISTORICO_DEMO, (id_origem, linha))
                self.assertTrue(all(0.9 <= fator <= 1.1 for fator in fatores), (id_origem, linha))
                self.assertEqual(fatores[-1], 1.0, (id_origem, linha))

    def test_aurora_e_torre_sobem_o_vgv_devagar_e_nao_mexem_no_custo(self):
        for id_origem, inicio in ((101, 0.97), (103, 0.99)):
            vgv = self.historico[id_origem]["vgv_bruto"]
            self.assertEqual(vgv[0], inicio, id_origem)
            self.assertEqual(vgv, sorted(vgv), id_origem)
            self.assertEqual(self.historico[id_origem]["custo_construcao"], [1.0] * MESES_HISTORICO_DEMO, id_origem)

    def test_parque_mostra_o_estouro_do_custo_nos_ultimos_meses(self):
        vgv = self.historico[102]["vgv_bruto"]
        custo = self.historico[102]["custo_construcao"]
        self.assertEqual(vgv[0], 1.03)
        self.assertEqual(vgv, sorted(vgv, reverse=True))
        self.assertEqual(custo[:6], [0.943] * 6)
        self.assertEqual(custo[5:], sorted(custo[5:]))
        self.assertLess(custo[5], custo[6])

    def test_fatores_viram_uma_tupla_por_obra_e_mes(self):
        fatores = fatores_historico_demo(self.estudos)
        self.assertEqual(len(fatores), 3 * MESES_HISTORICO_DEMO)
        self.assertEqual({meses_antes for _, meses_antes, _, _ in fatores}, set(range(1, MESES_HISTORICO_DEMO + 1)))
        obra, meses_antes, fator_vgv, fator_custo = fatores[0]
        self.assertEqual((obra, meses_antes, fator_vgv, fator_custo), (101, 11, Decimal("0.97"), Decimal("1.0")))
        self.assertEqual(fatores[-1][:2], (103, 1))

    def test_obra_sem_historico_fica_de_fora(self):
        self.assertEqual(fatores_historico_demo([{"id_origem": 1, "linhas": {}}]), [])

    def test_lista_com_tamanho_errado_e_recusada(self):
        estudo = {"id_origem": 1, "historico_demo": {"vgv_bruto": [1.0], "custo_construcao": [1.0]}}
        with self.assertRaises(ValueError):
            fatores_historico_demo([estudo])


@unittest.skipUnless(banco_local(), "DATABASE_URL local não definida")
class TesteBancoLocalViabilidade(unittest.TestCase):
    """Grava os estudos num tenant próprio do Supabase local e confere que repetir não cria versão."""

    def setUp(self):
        import psycopg
        self.conexao = psycopg.connect(banco_local(), autocommit=True)
        self.tenant = str(uuid.uuid4())
        self.estudos = ler_estudos()
        self.conexao.execute("insert into app.tenant (id, razao_social) values (%s, 'Teste viabilidade')", (self.tenant,))
        for estudo in self.estudos:
            self.conexao.execute("insert into app.centro_custo (tenant_id, id_origem, nome) values (%s, %s, %s)",
                                 (self.tenant, estudo["id_origem"], f"Obra {estudo['id_origem']}"))

    def tearDown(self):
        # Estudo, linhas e alíquota caem em cascata com o tenant.
        self.conexao.execute("delete from app.tenant where id = %s", (self.tenant,))
        self.conexao.close()

    def um(self, sql):
        return self.conexao.execute(sql, (self.tenant,)).fetchone()[0]

    def test_gravar_duas_vezes_deixa_uma_versao_por_obra(self):
        self.assertEqual(gravar_viabilidade_demo(self.conexao, self.tenant, self.estudos), 3)
        self.assertEqual(gravar_viabilidade_demo(self.conexao, self.tenant, self.estudos), 0)
        self.assertEqual(self.um("select count(*) from app.estudo_viabilidade where tenant_id = %s"), 3)
        self.assertEqual(self.um("select max(versao) from app.estudo_viabilidade where tenant_id = %s"), 1)
        self.assertEqual(self.um("select count(*) from app.estudo_viabilidade where tenant_id = %s and situacao = 'vigente'"), 3)
        self.assertEqual(self.um("select count(*) from app.estudo_viabilidade_linha where tenant_id = %s"), 33)
        self.assertEqual(self.um("select count(*) from app.aliquota_imposto_obra where tenant_id = %s"), 3)
        self.assertEqual(self.um("select count(*) from marts.dre_viabilidade where tenant_id = %s"), 51)

    def test_sem_estudos_nao_grava_nada(self):
        self.assertEqual(gravar_viabilidade_demo(self.conexao, self.tenant, []), 0)
        self.assertEqual(self.um("select count(*) from app.estudo_viabilidade where tenant_id = %s"), 0)

    def test_posicao_do_mes_e_historico_nao_duplicam(self):
        # Obra sem posicao financeira nao tem DRE, entao a conta parte do que a view devolve para o tenant.
        gravar_viabilidade_demo(self.conexao, self.tenant, self.estudos)
        obras_com_dre = self.um("select count(distinct centro_custo_id) from marts.dre_viabilidade where tenant_id = %s")
        linhas_mes = 11 * obras_com_dre
        self.assertEqual(registrar_posicao_dre(self.conexao, self.tenant), linhas_mes)
        self.assertEqual(registrar_posicao_dre(self.conexao, self.tenant), linhas_mes)
        self.assertEqual(self.um("select count(*) from app.posicao_dre_mensal where tenant_id = %s"), linhas_mes)
        self.assertEqual(gravar_historico_demo(self.conexao, self.tenant, self.estudos), MESES_HISTORICO_DEMO * linhas_mes)
        self.assertEqual(gravar_historico_demo(self.conexao, self.tenant, self.estudos), 0)
        self.assertEqual(
            self.um("select count(*) from app.posicao_dre_mensal where tenant_id = %s"),
            (MESES_HISTORICO_DEMO + 1) * linhas_mes,
        )
        self.assertEqual(
            self.um("select coalesce(min(n), 0) from (select count(distinct competencia) as n "
                    "from app.posicao_dre_mensal where tenant_id = %s group by centro_custo_id) c"),
            (MESES_HISTORICO_DEMO + 1) if obras_com_dre else 0,
        )


if __name__ == "__main__":
    unittest.main()
