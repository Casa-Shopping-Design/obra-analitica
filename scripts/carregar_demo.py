"""Le os JSON de dados/ e grava em raw.registro, depois recarrega o staging.

Na demo a fonte e o JSON; no MVP este mesmo script passa a chamar a API do
ERP de origem e o restante nao muda.
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


def hash_registro(payload):
    return hashlib.sha256(json.dumps(payload, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def main():
    tenant = os.environ["TENANT_DEMO_ID"]
    with psycopg.connect(os.environ["DATABASE_URL"]) as conexao:
        with conexao.cursor() as cur:
            for endpoint, arquivo in ARQUIVOS.items():
                registros = json.loads((PASTA_DADOS / arquivo).read_text(encoding="utf-8"))["data"]
                # na demo o arquivo substitui tudo; no MVP indexers so acumula, porque a API manda so o ultimo valor
                cur.execute("delete from raw.registro where tenant_id = %s and endpoint = %s", (tenant, endpoint))
                cur.executemany(
                    "insert into raw.registro (tenant_id, endpoint, payload, hash_registro) values (%s, %s, %s, %s) "
                    "on conflict do nothing",
                    [(tenant, endpoint, json.dumps(r, ensure_ascii=False), hash_registro(r)) for r in registros],
                )
                print(f"{endpoint}: {len(registros)} registros")
            cur.execute("select staging.recarregar(%s)", (tenant,))
            cur.execute("select staging.recarregar_precos(%s)", (tenant,))
        conexao.commit()
    print("staging recarregado")


if __name__ == "__main__":
    main()
