"""Le os JSON de dados/ e grava em raw.registro, depois recarrega o staging.

Na demo a fonte e o JSON; no MVP a carga vem de carregar_origem.py e carregar_crm.py, que
chamam a API e gravam no mesmo formato. Os arquivos de dados/complementos e dados/crm sao
opcionais: sem eles a demo carrega como antes e as recargas deles nao rodam.
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


def hash_registro(payload):
    return hashlib.sha256(json.dumps(payload, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def gravar_endpoint(cur, tenant, endpoint, registros, chave=None):
    """Na demo o arquivo substitui tudo do endpoint; no MVP indexers so acumula, porque a API manda so o ultimo valor."""
    cur.execute("delete from raw.registro where tenant_id = %s and endpoint = %s", (tenant, endpoint))
    cur.executemany(
        "insert into raw.registro (tenant_id, endpoint, payload, hash_registro, chave_origem) "
        "values (%s, %s, %s, %s, %s) on conflict do nothing",
        [(tenant, endpoint, json.dumps(r, ensure_ascii=False), hash_registro(r), chave(endpoint, r) if chave else None)
         for r in registros],
    )
    print(f"{endpoint}: {len(registros)} registros")


def ler_registros(caminho, campo_lista):
    return [r for r in json.loads(caminho.read_text(encoding="utf-8"))[campo_lista] if isinstance(r, dict)]


# O(n) no total de registros dos arquivos; uma instrucao de delete e um insert em lote por endpoint.
def main():
    tenant = os.environ["TENANT_DEMO_ID"]
    with psycopg.connect(os.environ["DATABASE_URL"]) as conexao:
        with conexao.cursor() as cur:
            # Tudo passa pela mesma lista de campos permitidos da carga real antes do raw: nome de
            # comprador e de credor, se vierem no arquivo, não chegam ao banco.
            for endpoint, arquivo in ARQUIVOS.items():
                registros = [filtrar_origem(endpoint, r) for r in ler_registros(PASTA_DADOS / arquivo, "data")]
                gravar_endpoint(cur, tenant, endpoint, registros, chave_origem)

            com_complementos = False
            for endpoint, arquivo in ARQUIVOS_COMPLEMENTOS.items():
                caminho = PASTA_DADOS / "complementos" / arquivo
                if caminho.exists():
                    registros = [filtrar_origem(endpoint, r) for r in ler_registros(caminho, "data")]
                    gravar_endpoint(cur, tenant, endpoint, registros, chave_origem)
                    com_complementos = True

            com_crm = False
            for endpoint, configuracao in ENDPOINTS_CRM.items():
                caminho = PASTA_DADOS / "crm" / configuracao["arquivo"]
                if caminho.exists():
                    registros = [filtrar_crm(endpoint, r) for r in ler_registros(caminho, "dados")]
                    gravar_endpoint(cur, tenant, endpoint, registros, chave_crm)
                    com_crm = True

            cur.execute("select staging.recarregar(%s)", (tenant,))
            cur.execute("select staging.recarregar_precos(%s)", (tenant,))
            if com_complementos:
                cur.execute("select staging.recarregar_complementos(%s)", (tenant,))
            # O CRM liga reserva e repasse ao contrato do ERP, que precisa estar no staging antes.
            if com_crm:
                cur.execute("select staging.recarregar_crm(%s)", (tenant,))
        conexao.commit()
    print("staging recarregado")


if __name__ == "__main__":
    main()
