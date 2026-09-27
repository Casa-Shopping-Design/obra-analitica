"""Le os JSON de dados/ e grava em raw.registro, depois recarrega o staging.

Na demo a fonte e o JSON; no MVP este mesmo script passa a chamar a API do
ERP de origem e o restante nao muda. Cada endpoint e o staging deixam uma
linha em app.carga_execucao, que alimenta a data da ultima carga no painel.
"""

import hashlib
import json
import os
from pathlib import Path

import psycopg
from dotenv import load_dotenv

load_dotenv()

PASTA_DADOS = Path(__file__).resolve().parent.parent / "dados"
ARQUIVOS = {
    "cost-centers": "cost-centers.json",
    "units": "units.json",
    "sales": "sales.json",
    "income": "income.json",
    "outcome": "outcome.json",
    "building-cost-estimation-items": "building-cost-estimation-items.json",
    "indexers": "indexers.json",
    "price-tables": "price-tables.json",
}
# marts.ultima_carga so considera a carga feita quando esta etapa termina com sucesso.
ETAPA_STAGING = "staging"


def hash_registro(payload):
    return hashlib.sha256(json.dumps(payload, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def abrir_execucao(conexao, tenant, endpoint):
    # Gravada e confirmada antes do trabalho, para uma carga que trava ficar visivel como "executando".
    with conexao.cursor() as cur:
        cur.execute(
            "insert into app.carga_execucao (tenant_id, endpoint) values (%s, %s) returning id",
            (tenant, endpoint),
        )
        id_execucao = cur.fetchone()[0]
    conexao.commit()
    return id_execucao


def fechar_execucao_ok(cur, id_execucao, lidos, novos):
    cur.execute(
        "update app.carga_execucao set situacao = 'ok', terminado_em = clock_timestamp(), "
        "registros_lidos = %s, registros_novos = %s, "
        "duracao_ms = (extract(epoch from clock_timestamp() - iniciado_em) * 1000)::integer "
        "where id = %s",
        (lidos, novos, id_execucao),
    )


def registrar_falha(conexao, id_execucao, erro):
    # So a classe do erro e o codigo SQLSTATE: a mensagem do banco pode trazer valores do registro.
    resumo = type(erro).__name__
    codigo = getattr(erro, "sqlstate", None)
    if codigo:
        resumo = f"{resumo} {codigo}"
    conexao.rollback()
    with conexao.cursor() as cur:
        cur.execute(
            "update app.carga_execucao set situacao = 'falha', terminado_em = clock_timestamp(), erro_resumo = %s, "
            "duracao_ms = (extract(epoch from clock_timestamp() - iniciado_em) * 1000)::integer "
            "where id = %s",
            (resumo, id_execucao),
        )
    conexao.commit()


def carregar_endpoint(conexao, tenant, endpoint, arquivo):
    id_execucao = abrir_execucao(conexao, tenant, endpoint)
    try:
        registros = json.loads((PASTA_DADOS / arquivo).read_text(encoding="utf-8"))["data"]
        with conexao.cursor() as cur:
            # na demo o arquivo substitui tudo; no MVP indexers so acumula, porque a API manda so o ultimo valor
            cur.execute("delete from raw.registro where tenant_id = %s and endpoint = %s", (tenant, endpoint))
            cur.executemany(
                "insert into raw.registro (tenant_id, endpoint, payload, hash_registro) values (%s, %s, %s, %s) "
                "on conflict do nothing",
                [(tenant, endpoint, json.dumps(r, ensure_ascii=False), hash_registro(r)) for r in registros],
            )
            novos = cur.rowcount
            fechar_execucao_ok(cur, id_execucao, len(registros), novos)
        conexao.commit()
    except Exception as erro:
        registrar_falha(conexao, id_execucao, erro)
        raise
    print(f"{endpoint}: {len(registros)} registros lidos, {novos} novos")


def recarregar_staging(conexao, tenant):
    id_execucao = abrir_execucao(conexao, tenant, ETAPA_STAGING)
    try:
        with conexao.cursor() as cur:
            cur.execute("select staging.recarregar(%s)", (tenant,))
            cur.execute("select staging.recarregar_precos(%s)", (tenant,))
            fechar_execucao_ok(cur, id_execucao, None, None)
        conexao.commit()
    except Exception as erro:
        registrar_falha(conexao, id_execucao, erro)
        raise
    print("staging recarregado")


def main():
    tenant = os.environ["TENANT_DEMO_ID"]
    with psycopg.connect(os.environ["DATABASE_URL"]) as conexao:
        # Um endpoint que falha interrompe a carga; o staging nao e recarregado pela metade.
        for endpoint, arquivo in ARQUIVOS.items():
            carregar_endpoint(conexao, tenant, endpoint, arquivo)
        recarregar_staging(conexao, tenant)


if __name__ == "__main__":
    main()
