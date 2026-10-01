"""Testes do resumo semanal: formatação, HTML, filtro de obras por perfil e envio. O teste com banco roda
dentro de uma transação desfeita no fim, porque o Supabase local é compartilhado."""

import contextlib
import io
import json
import os
import re
import sys
import tempfile
import unittest
import urllib.error
import urllib.parse
from datetime import date, datetime, timedelta
from decimal import Decimal
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import enviar_resumo_semanal  # noqa: E402
import resumo_semanal_email as email  # noqa: E402
from resumo_semanal_dados import (  # noqa: E402
    Alerta, Coleta, Destinatario, Pacote, ResumoObra, agrupar_por_tenant, coletar, obras_do_destinatario,
    obras_pelo_rls, periodo_do_resumo,
)

TENANT_A = "0e000000-0000-4000-8000-0000000005aa"
TENANT_B = "0e000000-0000-4000-8000-0000000005bb"
OBRA_A1 = "0c000000-0000-4000-8000-0000000005a1"
OBRA_A2 = "0c000000-0000-4000-8000-0000000005a2"
OBRA_A3 = "0c000000-0000-4000-8000-0000000005a3"
OBRA_B1 = "0c000000-0000-4000-8000-0000000005b1"
DIRETOR_A = "0a000000-0000-4000-8000-0000000005d1"
FINANCEIRO_A = "0a000000-0000-4000-8000-0000000005f1"
GERENTE_A = "0a000000-0000-4000-8000-0000000005c1"
COMERCIAL_A = "0a000000-0000-4000-8000-0000000005e1"
DIRETOR_B = "0a000000-0000-4000-8000-0000000005d2"
SEM_CONFIRMAR = "0a000000-0000-4000-8000-000000000501"
EMAIL_GERENTE = "gerente.resumo@teste.invalid"
PAINEL = "https://painel.teste.invalid"
SEGUNDA = date(2026, 10, 5)
AGORA = datetime(2026, 10, 5, 7, 0, tzinfo=email.FUSO)
PALETA = {cor.lower() for cor in (email.COR_FUNDO, email.COR_SUPERFICIE, email.COR_TEXTO, email.COR_SUAVE,
                                  email.COR_BORDA, email.COR_TRILHO, email.COR_MENU, email.COR_MENU_TEXTO,
                                  email.COR_ENTRADA, email.COR_ATENCAO, email.COR_ALERTA)}


def obra(centro_custo_id, nome, tenant=TENANT_A, alertas=(), **campos):
    valores = dict(
        vendas_semana=2, valor_vendas_semana=Decimal("850000.00"), vendas_mes=3, valor_vendas_mes=Decimal("1275000.00"),
        distratos_mes=0, vso_mes_anterior=Decimal("0.0976"), vencido_direto=Decimal("236267.62"),
        fracao_inadimplencia=Decimal("0.0612"), caixa_atual=Decimal("-1520300.10"),
        exposicao_maxima=Decimal("4100000.00"), unidades_estoque=12, meses_para_vender_estoque=Decimal("3.4"),
        ultima_carga_em=AGORA - timedelta(hours=5),
    )
    valores.update(campos)
    return ResumoObra(tenant_id=tenant, centro_custo_id=centro_custo_id, obra=nome, alertas=tuple(alertas), **valores)


def destinatario(user_id, perfil, tenant=TENANT_A, vinculadas=(), endereco="pessoa@teste.invalid"):
    return Destinatario(user_id=user_id, tenant_id=tenant, perfil=perfil, email=endereco,
                        obras_vinculadas=frozenset(vinculadas))


class TesteFormatacao(unittest.TestCase):
    def test_real(self):
        self.assertEqual(email.formatar_real(Decimal("1234.5")), "R$ 1.234,50")
        self.assertEqual(email.formatar_real(0), "R$ 0,00")
        self.assertEqual(email.formatar_real(Decimal("2078085.645")), "R$ 2.078.085,65")
        self.assertEqual(email.formatar_real(Decimal("-1520300.1")), "-R$ 1.520.300,10")
        self.assertEqual(email.formatar_real(Decimal("0.999")), "R$ 1,00")
        self.assertEqual(email.formatar_real(999), "R$ 999,00")

    def test_percentual_e_meses(self):
        self.assertEqual(email.formatar_percentual(Decimal("0.0612")), "6,1%")
        self.assertEqual(email.formatar_percentual(Decimal("-0.0364")), "-3,6%")
        self.assertEqual(email.formatar_percentual(Decimal("-0.0001")), "0,0%")
        self.assertEqual(email.formatar_meses(Decimal("1")), "1 mês")
        self.assertEqual(email.formatar_meses(Decimal("11.7")), "11,7 meses")
        self.assertEqual(email.formatar_meses(Decimal("4.0")), "4 meses")
        self.assertEqual(email.formatar_unidades(1), "1 unidade")
        self.assertEqual(email.formatar_unidades(1200), "1.200 unidades")
        self.assertEqual(email.formatar_vendas(0, Decimal(0)), "Nenhuma venda")
        self.assertEqual(email.formatar_vendas(2, Decimal("850000")), "2 unidades, R$\u00a0850.000,00")

    def test_vso(self):
        self.assertEqual(email.descrever_vso(Decimal("0.0976")), "9,8%")
        self.assertEqual(email.descrever_vso(Decimal("-0.036")), "Mais distratos que vendas")
        self.assertEqual(email.descrever_vso(None), "Sem estoque no início do mês")

    def test_datas(self):
        self.assertEqual(email.data_por_extenso(SEGUNDA), "segunda-feira, 5 de outubro de 2026")
        utc = datetime(2026, 9, 30, 21, 23, tzinfo=email.ZoneInfo("UTC"))
        self.assertEqual(email.formatar_data_hora(utc), "30/09/2026 às 18:23")

    def test_periodo(self):
        periodo = periodo_do_resumo(SEGUNDA)
        self.assertEqual(periodo.inicio_semana, date(2026, 9, 28))
        self.assertEqual(periodo.mes_atual, date(2026, 10, 1))
        self.assertEqual(periodo.mes_anterior, date(2026, 9, 1))
        self.assertEqual(periodo_do_resumo(date(2026, 1, 5)).mes_anterior, date(2025, 12, 1))

    def test_textos_dos_alertas(self):
        casos = {
            Alerta("estouro_orcamento", Decimal("240303.05"), Decimal("6200000")):
                ("Custo acima do orçamento", "O custo lançado passou o orçamento em R$ 240.303,05 (3,9% do orçado)."),
            Alerta("pago_a_frente_do_fisico", Decimal("0.1834"), None):
                ("Pago à frente do físico",
                 "O pago está 18 pontos à frente da medição. Vale conferir adiantamento ou medição atrasada."),
            Alerta("estoque_apos_entrega", None, Decimal("4")):
                ("Estoque parado", "Não houve venda líquida nos últimos 6 meses; no ritmo atual o estoque não acaba."),
            Alerta("estoque_apos_entrega", Decimal("3.4"), Decimal("0")):
                ("Obra entregue com estoque", "No ritmo dos últimos 6 meses, o que sobrou leva 3,4 meses para vender."),
            Alerta("inadimplencia_alta", Decimal("236267.62"), Decimal("0.0612")):
                ("Inadimplência alta", "R$ 236.267,62 vencidos dos compradores, 6,1% da carteira direta."),
        }
        for alerta, esperado in casos.items():
            self.assertEqual(email.texto_alerta(alerta), esperado)
        self.assertIsNone(email.texto_alerta(Alerta("tipo_novo", Decimal(1), None)))


class TesteHtml(unittest.TestCase):
    def setUp(self):
        self.periodo = periodo_do_resumo(SEGUNDA)
        self.obras = [
            obra(OBRA_A1, "Torre <Sul> & Cia", alertas=[
                Alerta("inadimplencia_alta", Decimal("236267.62"), Decimal("0.0612")),
                Alerta("repasse_atrasado", Decimal("526203.86"), None),
                Alerta("tipo_que_o_script_nao_conhece", Decimal(1), None),
            ]),
            obra(OBRA_A2, "Residencial Aurora", vso_mes_anterior=None, unidades_estoque=0,
                 fracao_inadimplencia=None, vencido_direto=Decimal(0)),
        ]

    def test_conteudo(self):
        html = email.montar_html(self.obras, self.periodo, PAINEL, AGORA)
        self.assertIn("Pede atenção", html)
        self.assertIn("Torre &lt;Sul&gt; &amp; Cia", html)
        self.assertNotIn("Torre <Sul>", html)
        self.assertIn(f'href="{PAINEL}"', html)
        self.assertIn(f"{PAINEL}/obras/{OBRA_A1}", html)
        self.assertIn("Abrir o painel", html)
        self.assertIn("R$ 526.203,86 de repasse já venceu e não entrou.", html)
        self.assertIn("VSO de setembro", html)
        self.assertIn("Vendas em outubro", html)
        self.assertIn("9,8%", html)
        self.assertIn("Sem estoque no início do mês", html)
        self.assertIn("Sem unidades à venda", html)
        # os dois alertas da Torre ficam num cartão só, com o nome da obra uma vez
        self.assertEqual(html.count("Torre &lt;Sul&gt; &amp; Cia</td>"), 2)
        self.assertIn("Semana de 28/09 a 04/10", html)
        self.assertNotIn("tipo_que_o_script_nao_conhece", html)
        self.assertNotIn("desatualizados", html)
        # repasse atrasado vem antes da inadimplência, como na tela
        self.assertLess(html.index("Repasse do banco atrasado"), html.index("Inadimplência alta"))

    def test_visual_sem_azul_e_sem_estilo_externo(self):
        html = email.montar_html(self.obras, self.periodo, PAINEL, AGORA)
        cores = {cor.lower() for cor in re.findall(r"#[0-9a-fA-F]{6}\b", html)}
        self.assertTrue(cores)
        self.assertLessEqual(cores, PALETA)
        self.assertNotIn("<style", html)
        self.assertNotIn("<link", html)
        self.assertNotRegex(html, r"\bblue\b|\u2014|\u2013")

    def test_sem_alerta_e_carga_atrasada(self):
        velha = obra(OBRA_A3, "Parque", ultima_carga_em=AGORA - timedelta(hours=30))
        html = email.montar_html([velha], self.periodo, PAINEL, AGORA)
        self.assertIn("Nenhum alerta aberto nas suas obras.", html)
        self.assertIn("Os números podem estar desatualizados.", html)
        sem_carga = obra(OBRA_A3, "Parque", ultima_carga_em=None)
        self.assertIn("Ainda não há carga concluída", email.montar_html([sem_carga], self.periodo, PAINEL, AGORA))

    def test_assunto_e_texto(self):
        self.assertEqual(email.assunto(self.obras, self.periodo), "Resumo semanal das obras, 05/10/2026: 2 alertas")
        self.assertEqual(email.assunto([self.obras[1]], self.periodo), "Resumo semanal das obras, 05/10/2026")
        texto = email.montar_texto(self.obras, self.periodo, PAINEL, AGORA)
        self.assertIn("- Torre <Sul> & Cia: Repasse do banco atrasado.", texto)
        self.assertIn(f"Abrir o painel: {PAINEL}", texto)
        self.assertNotIn(" ", texto)


class TesteFiltroPorPerfil(unittest.TestCase):
    def setUp(self):
        self.por_tenant = agrupar_por_tenant([
            obra(OBRA_A1, "A1"), obra(OBRA_A2, "A2"), obra(OBRA_A3, "A3"), obra(OBRA_B1, "B1", tenant=TENANT_B),
        ])

    def ids(self, quem):
        return [o.centro_custo_id for o in obras_do_destinatario(quem, self.por_tenant)]

    def test_diretor_e_financeiro_veem_todas_do_proprio_tenant(self):
        self.assertEqual(self.ids(destinatario(DIRETOR_A, "diretor")), [OBRA_A1, OBRA_A2, OBRA_A3])
        self.assertEqual(self.ids(destinatario(FINANCEIRO_A, "financeiro")), [OBRA_A1, OBRA_A2, OBRA_A3])
        self.assertEqual(self.ids(destinatario(DIRETOR_B, "diretor", tenant=TENANT_B)), [OBRA_B1])

    def test_gerente_ve_so_a_vinculada(self):
        self.assertEqual(self.ids(destinatario(GERENTE_A, "gerente_obra", vinculadas=[OBRA_A1])), [OBRA_A1])
        self.assertEqual(self.ids(destinatario(GERENTE_A, "gerente_obra")), [])

    def test_vinculo_com_obra_de_outro_tenant_nao_vale(self):
        gerente = destinatario(GERENTE_A, "gerente_obra", vinculadas=[OBRA_A2, OBRA_B1])
        self.assertEqual(self.ids(gerente), [OBRA_A2])

    def test_perfil_fora_da_lista_nao_recebe(self):
        self.assertEqual(self.ids(destinatario(COMERCIAL_A, "comercial", vinculadas=[OBRA_A1])), [])
        self.assertEqual(self.ids(destinatario(DIRETOR_A, "diretor", tenant="tenant-sem-obra")), [])


class RespostaFalsa:
    status = 200

    def __enter__(self):
        return self

    def __exit__(self, *erro):
        return False


class TesteEnvio(unittest.TestCase):
    def setUp(self):
        self.pedidos, self.esperas = [], []

    def abrir_com(self, *codigos):
        fila = list(codigos)

        def abrir(requisicao, timeout):
            self.pedidos.append(requisicao)
            codigo = fila.pop(0)
            if codigo == 200:
                return RespostaFalsa()
            raise urllib.error.HTTPError(requisicao.full_url, codigo, "erro", {"Retry-After": "1"}, None)
        return abrir

    def enviar(self, abrir):
        return enviar_resumo_semanal.enviar_pelo_resend(
            "re_chave_teste", "Painel <resumo@teste.invalid>", EMAIL_GERENTE, "Assunto", "<p>oi</p>", "oi", "chave-1",
            abrir=abrir, esperar=self.esperas.append)

    def test_pedido(self):
        self.assertEqual(self.enviar(self.abrir_com(200)), 200)
        pedido = self.pedidos[0]
        self.assertEqual(pedido.full_url, "https://api.resend.com/emails")
        self.assertEqual(pedido.get_header("Authorization"), "Bearer re_chave_teste")
        self.assertEqual(pedido.get_header("Idempotency-key"), "chave-1")
        corpo = json.loads(pedido.data)
        self.assertEqual(corpo["to"], [EMAIL_GERENTE])
        self.assertEqual(set(corpo), {"from", "to", "subject", "html", "text"})

    def test_repete_no_429_e_desiste_no_422(self):
        self.assertEqual(self.enviar(self.abrir_com(429, 200)), 200)
        self.assertEqual(self.esperas, [1.0])
        with self.assertRaises(enviar_resumo_semanal.ErroEnvio) as erro:
            self.enviar(self.abrir_com(422))
        self.assertEqual(erro.exception.status, 422)
        self.assertNotIn("re_chave_teste", str(erro.exception))

    def test_log_e_previa_sem_email_nem_chave(self):
        periodo = periodo_do_resumo(SEGUNDA)
        gerente = destinatario(GERENTE_A, "gerente_obra", vinculadas=[OBRA_A1], endereco=EMAIL_GERENTE)
        coleta = Coleta(pacotes=[Pacote(gerente, [obra(OBRA_A1, "Obra Sigilosa")])], destinatarios=2, sem_obra=1)
        ambiente = {"RESEND_API_KEY": "re_chave_teste", "RESUMO_REMETENTE": "Painel <resumo@teste.invalid>",
                    "PAINEL_URL_BASE": PAINEL}
        enviados = []
        saida = io.StringIO()
        with tempfile.TemporaryDirectory() as pasta, mock.patch.dict(os.environ, ambiente), \
                mock.patch.object(enviar_resumo_semanal, "load_dotenv"), \
                mock.patch.object(enviar_resumo_semanal, "coletar_do_banco", return_value=coleta), \
                mock.patch.object(enviar_resumo_semanal, "enviar_pelo_resend",
                                  side_effect=lambda *args: enviados.append(args)), \
                contextlib.redirect_stdout(saida):
            codigo = enviar_resumo_semanal.main(["--previa", pasta, "--enviar"])
            arquivos = [p.name for p in Path(pasta).iterdir()]
            conteudo = Path(pasta, arquivos[0]).read_text(encoding="utf-8")
        self.assertEqual(codigo, 0)
        self.assertEqual(len(enviados), 1)
        self.assertEqual(enviados[0][2], EMAIL_GERENTE)
        self.assertEqual(arquivos, ["gerente_obra_0a000000_0e000000.html"])
        self.assertNotIn(EMAIL_GERENTE, conteudo)
        log = saida.getvalue()
        registro = json.loads(log)
        self.assertEqual((registro["enviados"], registro["sem_obra"], registro["obras_no_resumo"]), (1, 1, 1))
        for segredo in (EMAIL_GERENTE, "re_chave_teste", "Obra Sigilosa", OBRA_A1, "resumo@teste.invalid"):
            self.assertNotIn(segredo, log)

    def test_envio_exige_https(self):
        ambiente = {"RESEND_API_KEY": "x", "RESUMO_REMETENTE": "y", "PAINEL_URL_BASE": "http://painel.invalid"}
        with mock.patch.dict(os.environ, ambiente), mock.patch.object(enviar_resumo_semanal, "load_dotenv"), \
                contextlib.redirect_stdout(io.StringIO()), self.assertRaises(SystemExit):
            enviar_resumo_semanal.main(["--enviar"])


def banco_local():
    url = os.environ.get("DATABASE_URL", "")
    host = urllib.parse.urlsplit(url).hostname or ""
    return url if host in ("localhost", "127.0.0.1", "::1") else None


@unittest.skipUnless(banco_local(), "DATABASE_URL local não definida")
class TesteBancoLocal(unittest.TestCase):
    """Dois tenants e cinco usuários criados numa transação que o tearDown desfaz."""

    def setUp(self):
        import psycopg
        self.conexao = psycopg.connect(banco_local())
        executar = self.conexao.execute
        executar("insert into app.tenant (id, razao_social) values (%s, 'Resumo A'), (%s, 'Resumo B')",
                 (TENANT_A, TENANT_B))
        executar("insert into app.centro_custo (id, tenant_id, id_origem, nome) values "
                 "(%s, %s, 9501, 'Obra A1'), (%s, %s, 9502, 'Obra A2'), (%s, %s, 9503, 'Obra A3'), "
                 "(%s, %s, 9501, 'Obra B1')",
                 (OBRA_A1, TENANT_A, OBRA_A2, TENANT_A, OBRA_A3, TENANT_A, OBRA_B1, TENANT_B))
        usuarios = [(DIRETOR_A, "diretor.a"), (FINANCEIRO_A, "financeiro.a"), (GERENTE_A, "gerente.a"),
                    (COMERCIAL_A, "comercial.a"), (DIRETOR_B, "diretor.b")]
        for user_id, nome in usuarios:
            executar("insert into auth.users (id, email, email_confirmed_at) values (%s, %s, now())",
                     (user_id, f"{nome}@teste.invalid"))
        executar("insert into auth.users (id, email) values (%s, 'convite.pendente@teste.invalid')", (SEM_CONFIRMAR,))
        executar("insert into app.usuario_tenant (user_id, tenant_id, perfil) values "
                 "(%s, %s, 'diretor'), (%s, %s, 'financeiro'), (%s, %s, 'gerente_obra'), (%s, %s, 'comercial'), "
                 "(%s, %s, 'diretor'), (%s, %s, 'diretor')",
                 (DIRETOR_A, TENANT_A, FINANCEIRO_A, TENANT_A, GERENTE_A, TENANT_A, COMERCIAL_A, TENANT_A,
                  DIRETOR_B, TENANT_B, SEM_CONFIRMAR, TENANT_A))
        # o vínculo com a obra B1 é de propósito: o filtro tem que ignorá-lo
        executar("insert into app.usuario_centro_custo (user_id, tenant_id, centro_custo_id) values "
                 "(%s, %s, %s), (%s, %s, %s), (%s, %s, %s)",
                 (GERENTE_A, TENANT_A, OBRA_A1, GERENTE_A, TENANT_A, OBRA_B1, COMERCIAL_A, TENANT_A, OBRA_A2))
        executar("insert into staging.contrato_venda (tenant_id, centro_custo_id, id_origem, data_venda, valor, situacao) "
                 "values (%s, %s, 1, %s, 500000, '1'), (%s, %s, 2, %s, 300000, '1'), (%s, %s, 3, %s, 900000, '1')",
                 (TENANT_A, OBRA_A1, SEGUNDA - timedelta(days=3), TENANT_A, OBRA_A1, SEGUNDA - timedelta(days=9),
                  TENANT_B, OBRA_B1, SEGUNDA - timedelta(days=2)))

    def tearDown(self):
        self.conexao.rollback()
        self.conexao.close()

    def pacotes_de_teste(self, coleta):
        return {(p.destinatario.user_id, p.destinatario.tenant_id): p for p in coleta.pacotes
                if p.destinatario.tenant_id in (TENANT_A, TENANT_B)}

    def test_cada_perfil_recebe_so_o_que_ve(self):
        coleta = coletar(self.conexao, periodo_do_resumo(SEGUNDA))
        pacotes = self.pacotes_de_teste(coleta)
        obras = {chave[0]: sorted(o.centro_custo_id for o in p.obras) for chave, p in pacotes.items()}
        self.assertEqual(obras, {
            DIRETOR_A: [OBRA_A1, OBRA_A2, OBRA_A3],
            FINANCEIRO_A: [OBRA_A1, OBRA_A2, OBRA_A3],
            GERENTE_A: [OBRA_A1],
            DIRETOR_B: [OBRA_B1],
        })
        self.assertEqual(coleta.divergentes, 0)
        self.assertEqual(pacotes[(GERENTE_A, TENANT_A)].destinatario.email, "gerente.a@teste.invalid")
        # só a venda de três dias atrás cai na semana
        a1 = pacotes[(GERENTE_A, TENANT_A)].obras[0]
        self.assertEqual((a1.vendas_semana, a1.valor_vendas_semana), (1, Decimal("500000")))
        self.assertEqual(self.conexao.execute("select current_user").fetchone()[0], "postgres")

    def test_rls_confere_o_filtro(self):
        gerente = destinatario(GERENTE_A, "gerente_obra", vinculadas=[OBRA_A1, OBRA_B1])
        self.assertEqual(obras_pelo_rls(self.conexao, gerente), {OBRA_A1})
        self.assertEqual(obras_pelo_rls(self.conexao, destinatario(DIRETOR_B, "diretor", tenant=TENANT_B)), {OBRA_B1})
        # perfil lido errado do lado do script: o banco lê o perfil da própria tabela e discorda
        falso_diretor = destinatario(GERENTE_A, "diretor")
        por_tenant = agrupar_por_tenant([obra(OBRA_A1, "A1"), obra(OBRA_A2, "A2"), obra(OBRA_A3, "A3")])
        pelo_script = {o.centro_custo_id for o in obras_do_destinatario(falso_diretor, por_tenant)}
        self.assertNotEqual(pelo_script, obras_pelo_rls(self.conexao, falso_diretor))
        self.assertEqual(self.conexao.execute("select current_user").fetchone()[0], "postgres")


if __name__ == "__main__":
    unittest.main()
