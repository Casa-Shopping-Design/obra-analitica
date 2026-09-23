"""Liga os dois usuarios de teste ao tenant da demo e a gerente a obra Aurora.

Os usuarios sao criados antes no Supabase Auth. Os UUIDs chegam por argumento
para nao ficarem em arquivo versionado.
"""

import argparse
import os
import uuid

import psycopg
from dotenv import load_dotenv

load_dotenv()

ID_ORIGEM_AURORA = 101


def ler_argumentos():
    parser = argparse.ArgumentParser(description="Vincula os usuarios de teste ao tenant da demo.")
    parser.add_argument("--diretor", type=uuid.UUID, required=True, help="UUID do diretor em auth.users")
    parser.add_argument("--gerente", type=uuid.UUID, required=True, help="UUID da gerente da Aurora em auth.users")
    return parser.parse_args()


def main():
    argumentos = ler_argumentos()
    tenant = os.environ["TENANT_DEMO_ID"]
    with psycopg.connect(os.environ["DATABASE_URL"]) as conexao:
        with conexao.cursor() as cur:
            cur.executemany(
                "insert into app.usuario_tenant (user_id, tenant_id, perfil) values (%s, %s, %s) "
                "on conflict do nothing",
                [(argumentos.diretor, tenant, "diretor"), (argumentos.gerente, tenant, "gerente_obra")],
            )
            vinculos_tenant = cur.rowcount
            cur.execute(
                "insert into app.usuario_centro_custo (user_id, tenant_id, centro_custo_id) "
                "select %s, tenant_id, id from app.centro_custo where tenant_id = %s and id_origem = %s "
                "on conflict do nothing",
                (argumentos.gerente, tenant, ID_ORIGEM_AURORA),
            )
            vinculos_obra = cur.rowcount
        conexao.commit()
    print(f"usuario_tenant: {vinculos_tenant} linhas novas")
    print(f"usuario_centro_custo: {vinculos_obra} linhas novas")


if __name__ == "__main__":
    main()
