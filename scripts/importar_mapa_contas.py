"""Importa o de-para conta contábil para linha de relatório a partir da planilha do cliente.

Lê a aba "Plano de Contas" (coluna B: conta com máscara; coluna F: "Linha Dasboard"), casa o
rótulo e o grupo da conta (primeiro dígito) com marts.linha_relatorio e grava em
app.mapa_conta_linha, com origem 'importacao', só as contas cujo mapa vigente mudou. Tudo numa
transação. A planilha é do cliente e não entra no repositório; o relatório não mostra nome de
conta, que pode ter nome de pessoa.

Uso:
    python scripts/importar_mapa_contas.py --arquivo <planilha.xlsx> --tenant <uuid> --simular
    python scripts/importar_mapa_contas.py --arquivo <planilha.xlsx> --tenant <uuid>
"""

import argparse
import os
import re
import sys
import uuid
from dataclasses import dataclass, field
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
ABA = "Plano de Contas"
COLUNA_CONTA = 1
COLUNA_LINHA = 5
CONTA_COM_MASCARA = re.compile(r"^\d+(\.\d+)*$")
CODIGOS_POR_ROTULO = 5


def normalizar(rotulo):
    return " ".join(str(rotulo).split()).casefold()


def ler_planilha(caminho):
    """Pares (conta, rótulo) das linhas com conta válida e rótulo preenchido. Cabeçalho e linha em
    branco caem fora pela máscara da conta. Só as colunas B e F são lidas."""
    from openpyxl import load_workbook

    pasta = load_workbook(caminho, read_only=True, data_only=True)
    try:
        if ABA not in pasta.sheetnames:
            raise ValueError(f'a planilha não tem a aba "{ABA}"')
        pares = []
        for linha in pasta[ABA].iter_rows(values_only=True):
            if len(linha) <= COLUNA_LINHA:
                continue
            conta, rotulo = linha[COLUNA_CONTA], linha[COLUNA_LINHA]
            conta = str(conta).strip() if conta is not None else ""
            if not CONTA_COM_MASCARA.match(conta) or rotulo is None or not str(rotulo).strip():
                continue
            pares.append((conta, str(rotulo).strip()))
        return pares
    finally:
        pasta.close()


def montar_catalogo(linhas_catalogo):
    """(rótulo normalizado, grupo) -> linha. Rótulo que aponta para duas linhas no mesmo grupo fica
    de fora e é avisado: casar por palpite gravaria conta na linha errada."""
    catalogo, ambiguos = {}, set()
    for linha, rotulo, grupo in linhas_catalogo:
        chave = (normalizar(rotulo), str(grupo) if grupo is not None else None)
        if chave in catalogo and catalogo[chave] != linha:
            ambiguos.add(chave)
        catalogo.setdefault(chave, linha)
    for chave in ambiguos:
        del catalogo[chave]
    return catalogo, ambiguos


@dataclass
class PlanoImportacao:
    gravar: list = field(default_factory=list)
    iguais: int = 0
    sem_correspondencia: dict = field(default_factory=dict)
    conflitos: list = field(default_factory=list)


# O(n) em contas da planilha: catálogo e mapa vigente ficam em dicionário.
def planejar(pares, catalogo, vigente):
    plano = PlanoImportacao()
    destino, rotulos_vistos = {}, {}
    for conta, rotulo in pares:
        chave = (normalizar(rotulo), conta[0])
        linha = catalogo.get(chave)
        if linha is None:
            rotulos_vistos.setdefault((rotulo.strip(), conta[0]), []).append(conta)
            continue
        if conta in destino and destino[conta] != linha:
            plano.conflitos.append(conta)
            continue
        destino[conta] = linha
    for conta in plano.conflitos:
        destino.pop(conta, None)
    for conta, linha in sorted(destino.items()):
        if conta in vigente and vigente[conta] == linha:
            plano.iguais += 1
        else:
            plano.gravar.append((conta, linha))
    plano.sem_correspondencia = rotulos_vistos
    plano.conflitos = sorted(set(plano.conflitos))
    return plano


class RepositorioMapa:
    def __init__(self, conexao):
        self.conexao = conexao

    def transacao(self):
        return self.conexao.transaction()

    def ler_catalogo(self):
        with self.conexao.cursor() as cur:
            cur.execute("select linha, rotulo, grupo_conta from marts.linha_relatorio where tipo = 'conta'")
            return cur.fetchall()

    def ler_vigente(self, tenant):
        with self.conexao.cursor() as cur:
            cur.execute("select distinct on (conta) conta, linha from app.mapa_conta_linha "
                        "where tenant_id = %s order by conta, id desc", (tenant,))
            return dict(cur.fetchall())

    def gravar(self, tenant, itens):
        contas, linhas = map(list, zip(*itens))
        with self.conexao.cursor() as cur:
            cur.execute("insert into app.mapa_conta_linha (tenant_id, conta, linha, origem) "
                        "select %s, c, l, 'importacao' from unnest(%s::text[], %s::text[]) as t(c, l)",
                        (tenant, contas, linhas))


def importar(repositorio, tenant, pares, simular):
    """Lê o mapa vigente e grava na mesma transação, para a comparação valer no que for gravado."""
    with repositorio.transacao():
        catalogo, ambiguos = montar_catalogo(repositorio.ler_catalogo())
        plano = planejar(pares, catalogo, repositorio.ler_vigente(tenant))
        if plano.gravar and not simular:
            repositorio.gravar(tenant, plano.gravar)
    return plano, ambiguos


def texto_relatorio(plano, ambiguos, simular):
    verbo = "seriam gravadas" if simular else "gravadas"
    saida = [f"contas mapeadas ({verbo}): {len(plano.gravar)}",
             f"contas já iguais ao mapa vigente: {plano.iguais}"]
    if plano.conflitos:
        saida.append(f"contas com rótulos diferentes na planilha, não gravadas: {', '.join(plano.conflitos)}")
    if ambiguos:
        saida.append("rótulos do catálogo repetidos no mesmo grupo, não usados: "
                     + "; ".join(f"{r} (grupo {g})" for r, g in sorted(ambiguos, key=str)))
    saida.append(f"rótulos sem correspondência no catálogo: {len(plano.sem_correspondencia)}")
    for (rotulo, grupo), contas in sorted(plano.sem_correspondencia.items()):
        codigos = ", ".join(contas[:CODIGOS_POR_ROTULO]) + (" ..." if len(contas) > CODIGOS_POR_ROTULO else "")
        saida.append(f"  {rotulo} (grupo {grupo}): {len(contas)} contas: {codigos}")
    return "\n".join(saida)


def ler_argumentos(argv=None):
    parser = argparse.ArgumentParser(description="Importa o mapa de contas para linhas de relatório.")
    parser.add_argument("--arquivo", required=True, type=Path, help="planilha .xlsx do cliente")
    parser.add_argument("--tenant", default=os.environ.get("TENANT_ID"), help="UUID do tenant")
    parser.add_argument("--simular", action="store_true", help="mostra o que faria, sem gravar")
    return parser.parse_args(argv)


def main(argv=None):
    import psycopg
    from dotenv import load_dotenv

    load_dotenv(RAIZ / ".env")
    args = ler_argumentos(argv)
    if not os.environ.get("DATABASE_URL"):
        sys.exit("Informe DATABASE_URL no .env")
    try:
        tenant = str(uuid.UUID(args.tenant or ""))
    except ValueError:
        sys.exit("Informe --tenant com o UUID do tenant (ou TENANT_ID no .env)")
    if not args.arquivo.is_file():
        sys.exit("Arquivo da planilha não encontrado")
    try:
        pares = ler_planilha(args.arquivo)
    except ValueError as erro:
        sys.exit(str(erro))
    with psycopg.connect(os.environ["DATABASE_URL"], autocommit=True) as conexao:
        plano, ambiguos = importar(RepositorioMapa(conexao), tenant, pares, args.simular)
    print(texto_relatorio(plano, ambiguos, args.simular))


if __name__ == "__main__":
    main()
