import sys
import unittest
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from carregar_demo import gravar_viabilidade_demo, ler_estudos  # noqa: E402
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


if __name__ == "__main__":
    unittest.main()
