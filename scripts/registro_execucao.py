"""Linha de app.carga_execucao para cada etapa da carga real (migration 0021).

Mesmo formato que carregar_demo.py grava e que marts.ultima_carga, public.ultima_carga() e /api/saude
leem: uma linha por tarefa e uma na etapa "staging". A linha abre e é confirmada antes do trabalho, para
uma carga que trava aparecer como "executando", e fecha como "ok" ou "falha" na saída, mesmo quando a
etapa levanta exceção. Em erro_resumo vai só a classe do erro e o SQLSTATE: a mensagem do banco pode
trazer valor de registro e a da API pode trazer corpo de resposta.
"""

import logging
from contextlib import contextmanager

log = logging.getLogger("registro_execucao")


def resumo_erro(erro):
    codigo = getattr(erro, "sqlstate", None)
    nome = type(erro).__name__
    return f"{nome} {codigo}" if codigo else nome


class Etapa:
    """Contagens que a etapa informa antes de fechar; a etapa de staging não conta registros."""

    def __init__(self, id_execucao):
        self.id_execucao = id_execucao
        self.lidos = None
        self.novos = None

    def contar(self, contagens):
        self.lidos = sum(n["lidos"] for n in contagens.values())
        self.novos = sum(n["novos"] for n in contagens.values())


class RegistroExecucao:
    """Grava com a conexão em autocommit do carregador: cada instrução confirma na hora, então a linha
    aberta sobrevive ao rollback da transação da tarefa."""

    def __init__(self, conexao):
        self.conexao = conexao

    def abrir(self, tenant, endpoint):
        with self.conexao.cursor() as cur:
            cur.execute(
                "insert into app.carga_execucao (tenant_id, endpoint) values (%s, %s) returning id",
                (tenant, endpoint),
            )
            return cur.fetchone()[0]

    def concluir(self, id_execucao, lidos=None, novos=None):
        with self.conexao.cursor() as cur:
            cur.execute(
                "update app.carga_execucao set situacao = 'ok', terminado_em = clock_timestamp(), "
                "registros_lidos = %s, registros_novos = %s, "
                "duracao_ms = (extract(epoch from clock_timestamp() - iniciado_em) * 1000)::integer "
                "where id = %s and situacao = 'executando'",
                (lidos, novos, id_execucao),
            )

    def falhar(self, id_execucao, erro):
        try:
            with self.conexao.cursor() as cur:
                cur.execute(
                    "update app.carga_execucao set situacao = 'falha', terminado_em = clock_timestamp(), "
                    "erro_resumo = %s, "
                    "duracao_ms = (extract(epoch from clock_timestamp() - iniciado_em) * 1000)::integer "
                    "where id = %s and situacao = 'executando'",
                    (resumo_erro(erro), id_execucao),
                )
        except Exception as erro_registro:
            # Conexão caída: não dá para fechar a linha, e o erro que importa é o da etapa.
            log.error("falha não registrada em carga_execucao: %s", type(erro_registro).__name__)

    @contextmanager
    def etapa(self, tenant, endpoint):
        """Fecha a linha como ok ao sair do bloco ou como falha se ele levantar; a exceção segue adiante."""
        etapa = Etapa(self.abrir(tenant, endpoint))
        try:
            yield etapa
        except BaseException as erro:
            self.falhar(etapa.id_execucao, erro)
            raise
        self.concluir(etapa.id_execucao, etapa.lidos, etapa.novos)
