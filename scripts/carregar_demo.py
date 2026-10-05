"""Le os JSON de dados/ e grava em raw.registro, depois recarrega o staging.

Na demo a fonte e o JSON; no MVP a carga vem de carregar_origem.py e carregar_crm.py, que
chamam a API e gravam no mesmo formato. Os arquivos de dados/complementos e dados/crm sao
opcionais: sem eles a demo carrega como antes e as recargas deles nao rodam. Cada endpoint
e o staging deixam uma linha em app.carga_execucao, que alimenta a data da ultima carga.
O estudo de viabilidade de dados/viabilidade nao e dado do ERP: vai direto para as tabelas
de app, so para obra que ainda nao tem estudo.
"""

import hashlib
import json
import os
from pathlib import Path

import psycopg
from dotenv import load_dotenv

from campos_permitidos import filtrar as filtrar_origem
from carregar_crm import ENDPOINTS as ENDPOINTS_CRM
from carregar_crm import chave_registro as chave_crm
from carregar_crm import filtrar_campos as filtrar_crm
from carregar_origem import chave_origem

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
ARQUIVOS_COMPLEMENTOS = {
    "real-estate-map": "real-estate-map.json",
    "building-projects/progress-logs/items": "building-projects-progress-logs-items.json",
    "defaulters-receivable-bills/by-aging": "defaulters-receivable-bills-by-aging.json",
}
ARQUIVO_VIABILIDADE = PASTA_DADOS / "viabilidade" / "estudos.json"
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


def gravar_endpoint(cur, tenant, endpoint, registros, chave=None):
    """Na demo o arquivo substitui tudo do endpoint; no MVP indexers so acumula, porque a API manda so o ultimo valor."""
    cur.execute("delete from raw.registro where tenant_id = %s and endpoint = %s", (tenant, endpoint))
    cur.executemany(
        "insert into raw.registro (tenant_id, endpoint, payload, hash_registro, chave_origem) "
        "values (%s, %s, %s, %s, %s) on conflict do nothing",
        [(tenant, endpoint, json.dumps(r, ensure_ascii=False), hash_registro(r), chave(endpoint, r) if chave else None)
         for r in registros],
    )
    return cur.rowcount


def ler_registros(caminho, campo_lista):
    return [r for r in json.loads(caminho.read_text(encoding="utf-8"))[campo_lista] if isinstance(r, dict)]


def carregar_endpoint(conexao, tenant, endpoint, registros, chave):
    id_execucao = abrir_execucao(conexao, tenant, endpoint)
    try:
        with conexao.cursor() as cur:
            novos = gravar_endpoint(cur, tenant, endpoint, registros, chave)
            fechar_execucao_ok(cur, id_execucao, len(registros), novos)
        conexao.commit()
    except Exception as erro:
        registrar_falha(conexao, id_execucao, erro)
        raise
    print(f"{endpoint}: {len(registros)} registros lidos, {novos} novos")


def recarregar_staging(conexao, tenant, com_complementos, com_crm):
    id_execucao = abrir_execucao(conexao, tenant, ETAPA_STAGING)
    try:
        with conexao.cursor() as cur:
            cur.execute("select staging.recarregar(%s)", (tenant,))
            cur.execute("select staging.recarregar_precos(%s)", (tenant,))
            if com_complementos:
                cur.execute("select staging.recarregar_complementos(%s)", (tenant,))
            # O CRM liga reserva e repasse ao contrato do ERP, que precisa estar no staging antes.
            if com_crm:
                cur.execute("select staging.recarregar_crm(%s)", (tenant,))
            fechar_execucao_ok(cur, id_execucao, None, None)
        conexao.commit()
    except Exception as erro:
        registrar_falha(conexao, id_execucao, erro)
        raise
    print("staging recarregado")


def ler_estudos(caminho=ARQUIVO_VIABILIDADE):
    if not caminho.exists():
        return []
    return [e for e in json.loads(caminho.read_text(encoding="utf-8")) if isinstance(e, dict)]


# O(obras x linhas): uma consulta para achar as obras sem estudo e tres inserts por obra gravada.
def gravar_viabilidade_demo(conexao, tenant, estudos):
    """Grava estudo e aliquota so para obra sem estudo, entao a carga noturna nao cria versao nova."""
    if not estudos:
        return 0
    with conexao.cursor() as cur:
        cur.execute(
            "select cc.id_origem, cc.id from app.centro_custo cc "
            "where cc.tenant_id = %s and not exists ("
            "  select 1 from app.estudo_viabilidade e where e.tenant_id = cc.tenant_id and e.centro_custo_id = cc.id)",
            (tenant,),
        )
        obras_sem_estudo = dict(cur.fetchall())
        gravados = 0
        for estudo in estudos:
            centro_custo = obras_sem_estudo.get(estudo["id_origem"])
            if centro_custo is None:
                continue
            cur.execute(
                "insert into app.estudo_viabilidade (tenant_id, centro_custo_id, versao, descricao, data_base, situacao) "
                "values (%s, %s, 1, %s, %s, 'vigente') returning id",
                (tenant, centro_custo, estudo.get("descricao"), estudo["data_base"]),
            )
            id_estudo = cur.fetchone()[0]
            cur.executemany(
                "insert into app.estudo_viabilidade_linha (estudo_id, tenant_id, centro_custo_id, linha, valor) "
                "values (%s, %s, %s, %s, %s)",
                [(id_estudo, tenant, centro_custo, linha, valor) for linha, valor in estudo["linhas"].items()],
            )
            if estudo.get("aliquota") is not None:
                cur.execute(
                    "insert into app.aliquota_imposto_obra (tenant_id, centro_custo_id, vigencia_inicio, aliquota) "
                    "values (%s, %s, %s, %s)",
                    (tenant, centro_custo, estudo["vigencia_inicio"], estudo["aliquota"]),
                )
            gravados += 1
    conexao.commit()
    print(f"viabilidade: {gravados} estudos gravados, {len(estudos) - gravados} obras ja tinham estudo")
    return gravados


# O(n) no total de registros dos arquivos; uma instrucao de delete e um insert em lote por endpoint.
def main():
    tenant = os.environ["TENANT_DEMO_ID"]
    with psycopg.connect(os.environ["DATABASE_URL"]) as conexao:
        # Tudo passa pela mesma lista de campos permitidos da carga real antes do raw: nome de
        # comprador e de credor, se vierem no arquivo, não chegam ao banco. Um endpoint que
        # falha interrompe a carga; o staging nao e recarregado pela metade.
        for endpoint, arquivo in ARQUIVOS.items():
            registros = [filtrar_origem(endpoint, r) for r in ler_registros(PASTA_DADOS / arquivo, "data")]
            carregar_endpoint(conexao, tenant, endpoint, registros, chave_origem)

        com_complementos = False
        for endpoint, arquivo in ARQUIVOS_COMPLEMENTOS.items():
            caminho = PASTA_DADOS / "complementos" / arquivo
            if caminho.exists():
                registros = [filtrar_origem(endpoint, r) for r in ler_registros(caminho, "data")]
                carregar_endpoint(conexao, tenant, endpoint, registros, chave_origem)
                com_complementos = True

        com_crm = False
        for endpoint, configuracao in ENDPOINTS_CRM.items():
            caminho = PASTA_DADOS / "crm" / configuracao["arquivo"]
            if caminho.exists():
                registros = [filtrar_crm(endpoint, r) for r in ler_registros(caminho, "dados")]
                carregar_endpoint(conexao, tenant, endpoint, registros, chave_crm)
                com_crm = True

        recarregar_staging(conexao, tenant, com_complementos, com_crm)
        gravar_viabilidade_demo(conexao, tenant, ler_estudos())


if __name__ == "__main__":
    main()
