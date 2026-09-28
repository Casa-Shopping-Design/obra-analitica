"""Carga incremental do ERP de origem para raw.registro, por tenant (decisão 0005).

Primeira carga de cada endpoint pega a janela inicial; as seguintes pedem só o que mudou desde a
marca em app.marca_carga. Cada tarefa grava numa transação, e a marca avança dentro dela. Registro
passa pela lista de campos permitidos antes de virar hash e payload, então dado pessoal não chega
ao banco. No fim recarrega o staging do tenant.

Antes do plano, os IDs avisados pelo webhook (app.evento_origem) são reconsultados na API e os
eventos saem da fila na mesma transação que grava o que veio. Fila vazia não muda nada.

Uso:
    python scripts/carregar_origem.py
    python scripts/carregar_origem.py --tenant <uuid>
"""

import argparse
import hashlib
import json
import logging
import os
import sys
from collections import Counter
from dataclasses import dataclass, field
from datetime import date, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from campos_permitidos import EndpointSemLista, filtrar  # noqa: E402
from cliente_origem import BulkIndisponivel, ClienteOrigem, ConfiguracaoOrigem, CotaEsgotada, ErroOrigem  # noqa: E402

log = logging.getLogger("carregar_origem")

RAIZ = Path(__file__).resolve().parent.parent
TAMANHO_LOTE = 1000
TITULOS_POR_CHAMADA = 100
DATA_MINIMA = "2000-01-01"


@dataclass(frozen=True)
class Tarefa:
    """Uma unidade de carga: endpoint gravado em raw, estratégia de busca e recurso da API.

    `completa` diz que a estratégia traz o conjunto inteiro; no fim, o que não veio sai de raw.
    """
    endpoint: str
    estrategia: str
    recurso: str
    completa: bool = False


# Campos que identificam o registro na origem. `grupo` quer dizer que a chave repete entre linhas
# (todas as parcelas de um título) e o conjunto inteiro da chave é trocado de uma vez.
@dataclass(frozen=True)
class Chave:
    campos: tuple
    grupo: bool = False


CHAVES = {
    "cost-centers": Chave(("id",)),
    "enterprises": Chave(("id",)),
    "units": Chave(("id",)),
    "indexers": Chave(("id", "lastValue.date")),
    "price-tables": Chave(("id", "version")),
    "accounts-balances": Chave(("accountNumber", "balanceDate")),
    "sales": Chave(("id",)),
    "sales-contracts": Chave(("id",)),
    "income": Chave(("billId", "installmentId")),
    "outcome": Chave(("billId", "installmentId")),
    "building-cost-estimation-items": Chave(("id",)),
    "bills": Chave(("id",)),
    "bills/installments": Chave(("billId",), grupo=True),
    "bills/buildings-cost": Chave(("billId",), grupo=True),
    "accounts-statements": Chave(("id",)),
    "defaulters-receivable-bills": Chave(("receivableBillId",)),
    "real-estate-map": Chave(("enterpriseData.enterpriseId", "enterpriseData.monthYear")),
    "building-projects/progress-logs/items": Chave(("buildingId", "measurementNumber", "buildingUnitId"), grupo=True),
    "defaulters-receivable-bills/by-aging": Chave(("receivableBillId",)),
}

# Planos como dados: acrescentar endpoint é acrescentar uma Tarefa (e a estratégia, se for nova).
PLANO_COMUM = (
    Tarefa("cost-centers", "cadastro", "cost-centers", completa=True),
    Tarefa("enterprises", "cadastro", "enterprises", completa=True),
    Tarefa("units", "cadastro", "units", completa=True),
    Tarefa("indexers", "cadastro", "indexers"),
    Tarefa("price-tables", "cadastro", "price-tables", completa=True),
    Tarefa("accounts-balances", "saldos_do_dia", "accounts-balances"),
    Tarefa("sales-contracts", "contratos_alterados", "sales-contracts"),
    Tarefa("real-estate-map", "mapa_imobiliario", "real-estate-map"),
    Tarefa("building-projects/progress-logs/items", "medicoes_obra", "building-projects/progress-logs"),
)

PLANO_BULK = PLANO_COMUM + (
    Tarefa("sales", "vendas_por_obra", "sales"),
    Tarefa("income", "receber_alterados", "income"),
    Tarefa("outcome", "pagar_alterados", "outcome"),
    Tarefa("building-cost-estimation-items", "bulk_completo", "building-cost-estimation-items", completa=True),
    Tarefa("defaulters-receivable-bills/by-aging", "inadimplencia_por_faixa",
           "defaulters-receivable-bills/by-aging", completa=True),
)

PLANO_SO_REST = PLANO_COMUM + (
    Tarefa("accounts-statements", "extrato", "accounts-statements"),
    Tarefa("bills", "titulos_rest", "bills"),
)


@dataclass
class Contexto:
    cliente: object
    hoje: date
    obras: list
    janela_dias: int = 400
    horizonte_dias: int = 3650
    dias_pagamento: int = 7
    indexador_correcao: str = ""
    concluidas: set = field(default_factory=set)
    compartilhado: dict = field(default_factory=dict)

    def inicio_janela(self):
        return (self.hoje - timedelta(days=self.janela_dias)).isoformat()

    def fim_horizonte(self):
        return (self.hoje + timedelta(days=self.horizonte_dias)).isoformat()


def cadastro(ctx, tarefa, marca):
    for pagina in ctx.cliente.listar(tarefa.recurso):
        for registro in pagina:
            yield tarefa.endpoint, registro


def saldos_do_dia(ctx, tarefa, marca):
    for pagina in ctx.cliente.listar(tarefa.recurso, {"balanceDate": ctx.hoje.isoformat()}):
        for registro in pagina:
            yield tarefa.endpoint, registro


def contratos_alterados(ctx, tarefa, marca):
    alteradas = ctx.compartilhado.setdefault("obras_venda_alterada", set())
    parametros = {"modifiedAfter": marca.isoformat()} if marca else {}
    for pagina in ctx.cliente.listar(tarefa.recurso, parametros):
        for registro in pagina:
            alteradas.add(registro.get("enterpriseId"))
            yield tarefa.endpoint, registro


def vendas_por_obra(ctx, tarefa, marca):
    """O Bulk de vendas exige obra e situação e não filtra por alteração; na carga incremental
    só as obras com contrato alterado desde a marca são pedidas de novo, para poupar cota."""
    obras = ctx.obras
    if marca and "sales-contracts" in ctx.concluidas:
        alteradas = ctx.compartilhado.get("obras_venda_alterada", set())
        obras = [obra for obra in ctx.obras if obra in alteradas]
    for obra in obras:
        for situacao in ("SOLD", "CANCELED"):
            parametros = {"enterpriseId": obra, "createdAfter": DATA_MINIMA,
                          "createdBefore": ctx.hoje.isoformat(), "situation": situacao}
            for bloco in ctx.cliente.bulk(tarefa.recurso, parametros):
                for registro in bloco:
                    yield tarefa.endpoint, registro


def receber_alterados(ctx, tarefa, marca):
    parametros = {"startDate": ctx.inicio_janela(), "endDate": ctx.fim_horizonte(), "selectionType": "D"}
    if marca:
        parametros["changeStartDate"] = marca.isoformat()
    for bloco in ctx.cliente.bulk(tarefa.recurso, parametros, assincrono=True):
        for registro in bloco:
            yield tarefa.endpoint, registro


def pagar_alterados(ctx, tarefa, marca):
    """O a pagar não tem filtro de alteração no Bulk. Incremental = pagamentos dos últimos dias
    mais os títulos alterados desde a marca, buscados por lista de IDs."""
    if not ctx.indexador_correcao:
        raise ValueError("ORIGEM_INDEXADOR_CORRECAO vazio; o a pagar exige indexador de correção")
    correcao = {"correctionIndexerId": ctx.indexador_correcao, "correctionDate": ctx.hoje.isoformat()}
    if not marca:
        parametros = {"startDate": ctx.inicio_janela(), "endDate": ctx.fim_horizonte(), "selectionType": "D", **correcao}
        for bloco in ctx.cliente.bulk(tarefa.recurso, parametros, assincrono=True):
            for registro in bloco:
                yield tarefa.endpoint, registro
        return
    inicio_pagamentos = (ctx.hoje - timedelta(days=ctx.dias_pagamento)).isoformat()
    parametros = {"startDate": inicio_pagamentos, "endDate": ctx.hoje.isoformat(), "selectionType": "P", **correcao}
    for bloco in ctx.cliente.bulk(tarefa.recurso, parametros, assincrono=True):
        for registro in bloco:
            yield tarefa.endpoint, registro
    titulos = set()
    for pagina in ctx.cliente.listar("bills/by-change-date", {"startDate": marca.isoformat(), "endDate": ctx.hoje.isoformat()}):
        titulos.update(t["id"] for t in pagina if t.get("id") is not None)
    ordenados = sorted(titulos)
    for inicio in range(0, len(ordenados), TITULOS_POR_CHAMADA):
        lote = ordenados[inicio:inicio + TITULOS_POR_CHAMADA]
        for bloco in ctx.cliente.bulk(f"{tarefa.recurso}/by-bills", {"billsIds": lote, **correcao}):
            for registro in bloco:
                yield tarefa.endpoint, registro


def bulk_completo(ctx, tarefa, marca):
    for bloco in ctx.cliente.bulk(tarefa.recurso, {}, assincrono=True):
        for registro in bloco:
            yield tarefa.endpoint, registro


def extrato(ctx, tarefa, marca):
    # lançamento retroativo no extrato entra pela sobreposição de alguns dias
    inicio = (marca - timedelta(days=ctx.dias_pagamento)).isoformat() if marca else ctx.inicio_janela()
    for pagina in ctx.cliente.listar(tarefa.recurso, {"startDate": inicio, "endDate": ctx.hoje.isoformat()}):
        for registro in pagina:
            yield tarefa.endpoint, registro


# O(t) chamadas por título alterado (parcelas e rateio): N+1 de rede, porque o caminho só REST
# não tem consulta em lote. Roda de madrugada; o limite é a cota diária, não o banco.
def titulos_rest(ctx, tarefa, marca):
    if marca:
        recurso, parametros = "bills/by-change-date", {"startDate": marca.isoformat(), "endDate": ctx.hoje.isoformat()}
    else:
        recurso, parametros = "bills", {"startDate": ctx.inicio_janela(), "endDate": ctx.hoje.isoformat()}
    for pagina in ctx.cliente.listar(recurso, parametros):
        for titulo in pagina:
            id_titulo = titulo.get("id")
            if id_titulo is None:
                continue
            yield "bills", titulo
            for sub in ("installments", "buildings-cost"):
                for itens in ctx.cliente.listar(f"bills/{id_titulo}/{sub}"):
                    for item in itens:
                        yield f"bills/{sub}", {**item, "billId": id_titulo}


OBRAS_POR_CHAMADA = 50
DIAS_REVISAO_MEDICAO = 90


def _inicio_mes(dia):
    return dia.replace(day=1)


def mapa_imobiliario(ctx, tarefa, marca):
    """Mês fechado só muda por lançamento retroativo; a carga diária pede de novo o mês anterior à
    marca e os seguintes, e a primeira carga pega a janela inicial inteira."""
    if marca:
        inicio = _inicio_mes(_inicio_mes(marca) - timedelta(days=1))
    else:
        inicio = _inicio_mes(ctx.hoje - timedelta(days=ctx.janela_dias))
    for posicao in range(0, len(ctx.obras), OBRAS_POR_CHAMADA):
        parametros = {"costCentersId": ctx.obras[posicao:posicao + OBRAS_POR_CHAMADA],
                      "startDate": inicio.isoformat(), "endDate": ctx.hoje.isoformat()}
        for pagina in ctx.cliente.listar(tarefa.recurso, parametros):
            for registro in pagina:
                yield tarefa.endpoint, registro


# O(m x u) chamadas REST para m medições e u unidades construtivas medidas: os itens só saem por
# medição e unidade. Medição é mensal por obra, então m fica na casa das dezenas por carga.
def medicoes_obra(ctx, tarefa, marca):
    """Medição em aprovação pode ser aprovada ou reprovada depois; a carga diária revê as medições
    dos últimos dias e troca o grupo de itens de cada uma, com a situação nova."""
    inicio = marca - timedelta(days=DIAS_REVISAO_MEDICAO) if marca else ctx.hoje - timedelta(days=ctx.janela_dias)
    obras = set(ctx.obras)
    parametros = {"measurementStartDate": inicio.isoformat(), "measurementEndDate": ctx.hoje.isoformat()}
    medicoes = [m for pagina in ctx.cliente.listar(tarefa.recurso, parametros) for m in pagina
                if m.get("buildingId") in obras and m.get("measurementNumber") is not None]
    for medicao in medicoes:
        obra, numero = medicao["buildingId"], medicao["measurementNumber"]
        cabecalho = {"buildingId": obra, "measurementNumber": numero, "date": medicao.get("date"),
                     "statusApproval": medicao.get("statusApproval"), "consistent": medicao.get("consistent")}
        # consulta de um objeto só, sem paginação; o cliente não tem outro método público para isso
        detalhe = ctx.cliente._get("rest", f"building-projects/{obra}/progress-logs/{numero}", {})
        for unidade in (detalhe or {}).get("buildingUnits") or []:
            if unidade.get("id") is None:
                continue
            id_unidade = int(unidade["id"])
            caminho = f"building-projects/{obra}/progress-logs/{numero}/items/{id_unidade}"
            for itens in ctx.cliente.listar(caminho):
                for item in itens:
                    yield tarefa.endpoint, {**item, **cabecalho, "buildingUnitId": id_unidade}


def inadimplencia_por_faixa(ctx, tarefa, marca):
    """Posição do dia, uma chamada Bulk por empresa. O registro final só com positionDate marca a
    leitura como completa: sem ele, um dia sem inadimplente repetiria a posição anterior no staging.

    Usuário de API sem permissão para este recurso (403 ou 404 do gateway) não tira o tenant do Bulk:
    a posição anterior fica, com a data dela, e o aviso vai para o log.
    """
    obras = set(ctx.obras)
    if not obras:
        return
    empresas = sorted({c["idCompany"] for pagina in ctx.cliente.listar("cost-centers") for c in pagina
                       if c.get("id") in obras and c.get("idCompany") is not None})
    posicao = ctx.hoje.isoformat()
    lidos = 0
    for empresa in empresas:
        parametros = {"companyId": empresa, "enterpriseId": sorted(obras), "dueDateLimit": posicao,
                      "correctionDate": posicao, "positionDate": posicao,
                      "includePartiallyPaidInstallments": "true"}
        try:
            for bloco in ctx.cliente.bulk(tarefa.recurso, parametros):
                for registro in bloco:
                    lidos += 1
                    yield tarefa.endpoint, {**registro, "positionDate": posicao}
        except BulkIndisponivel as erro:
            if lidos:
                raise ErroOrigem(erro.status, tarefa.recurso, "inadimplência lida só em parte") from None
            log.warning("inadimplência por faixa indisponível para o usuário de API (%s); posição anterior mantida",
                        erro.status)
            return
    yield tarefa.endpoint, {"positionDate": posicao}


ESTRATEGIAS = {
    "cadastro": cadastro,
    "saldos_do_dia": saldos_do_dia,
    "contratos_alterados": contratos_alterados,
    "vendas_por_obra": vendas_por_obra,
    "receber_alterados": receber_alterados,
    "pagar_alterados": pagar_alterados,
    "bulk_completo": bulk_completo,
    "extrato": extrato,
    "titulos_rest": titulos_rest,
    "mapa_imobiliario": mapa_imobiliario,
    "medicoes_obra": medicoes_obra,
    "inadimplencia_por_faixa": inadimplencia_por_faixa,
}


def hash_registro(payload):
    return hashlib.sha256(json.dumps(payload, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def _valor_caminho(registro, caminho):
    valor = registro
    for parte in caminho.split("."):
        if not isinstance(valor, dict):
            return None
        valor = valor.get(parte)
    return valor


def chave_origem(endpoint, registro):
    chave = CHAVES.get(endpoint)
    if chave is None:
        return None
    valores = [_valor_caminho(registro, campo) for campo in chave.campos]
    if all(v is None for v in valores):
        return None
    return "|".join("" if v is None else str(v) for v in valores)


class LoteTarefa:
    """Filtra, calcula hash e chave de cada registro da estratégia e guarda o que está vigente.

    vigentes[(endpoint, chave)] = hashes da versão atual. Chave única fica com a última versão
    lida na execução; chave de grupo acumula todas as linhas do grupo.
    """

    def __init__(self, tarefa, fonte):
        self.tarefa = tarefa
        self.fonte = fonte
        self.vigentes = {}
        self.lidos = Counter()

    # O(n) em registros; memória O(n) só das chaves e hashes, não dos payloads.
    def registros(self):
        for endpoint, bruto in self.fonte:
            payload = filtrar(endpoint, bruto)
            hash_atual = hash_registro(payload)
            chave = chave_origem(endpoint, payload)
            grupo = CHAVES[endpoint].grupo if endpoint in CHAVES else False
            if chave is None or grupo:
                self.vigentes.setdefault((endpoint, chave), set()).add(hash_atual)
            else:
                self.vigentes[(endpoint, chave)] = {hash_atual}
            self.lidos[endpoint] += 1
            yield endpoint, chave, hash_atual, json.dumps(payload, ensure_ascii=False)

    def endpoints_completos(self):
        """Só apaga o que não veio quando a leitura trouxe algo; resposta vazia não zera o cadastro."""
        if not self.tarefa.completa:
            return []
        return [e for e in self.lidos if self.lidos[e] > 0]


def em_lotes(iteravel, tamanho):
    lote = []
    for item in iteravel:
        lote.append(item)
        if len(lote) == tamanho:
            yield lote
            lote = []
    if lote:
        yield lote


class RepositorioBanco:
    """Acesso ao Postgres. A conexão vem com autocommit, então cada transaction() é uma transação real."""

    def __init__(self, conexao):
        self.conexao = conexao

    def ler_estado(self, tenant):
        with self.conexao.cursor() as cur:
            cur.execute("select endpoint, ultima_referencia from app.marca_carga where tenant_id = %s", (tenant,))
            marcas = dict(cur.fetchall())
            cur.execute("select so_rest, verificado_em from app.modo_carga where tenant_id = %s", (tenant,))
            modo = cur.fetchone()
            cur.execute("select id_origem from app.centro_custo where tenant_id = %s order by id_origem", (tenant,))
            obras = [linha[0] for linha in cur.fetchall()]
        return marcas, modo, obras

    def gravar_modo(self, tenant, so_rest):
        with self.conexao.transaction(), self.conexao.cursor() as cur:
            cur.execute(
                "insert into app.modo_carga (tenant_id, so_rest, verificado_em) values (%s, %s, now()) "
                "on conflict (tenant_id) do update set so_rest = excluded.so_rest, verificado_em = now()",
                (tenant, so_rest),
            )

    @staticmethod
    def _gravar_registros(cur, tenant, lote):
        """Grava o lote em raw e troca a versão antiga de cada chave. Roda dentro da transação de quem chama."""
        novos, substituidos = Counter(), Counter()
        cur.execute("create temp table carga_atual (endpoint text not null, chave text, hash text not null) "
                    "on commit drop")
        for bloco in em_lotes(lote.registros(), TAMANHO_LOTE):
            endpoints, chaves, hashes, payloads = map(list, zip(*bloco))
            cur.execute(
                "insert into raw.registro (tenant_id, endpoint, payload, hash_registro, chave_origem) "
                "select %s, e, p::jsonb, h, c from unnest(%s::text[], %s::text[], %s::text[], %s::text[]) "
                "as t(e, p, h, c) on conflict (tenant_id, endpoint, hash_registro) do nothing returning endpoint",
                (tenant, endpoints, payloads, hashes, chaves),
            )
            novos.update(linha[0] for linha in cur.fetchall())
        vigentes = [(e, c, h) for (e, c), hs in lote.vigentes.items() for h in hs]
        for bloco in em_lotes(vigentes, 5 * TAMANHO_LOTE):
            e, c, h = map(list, zip(*bloco))
            cur.execute("insert into carga_atual select * from unnest(%s::text[], %s::text[], %s::text[])", (e, c, h))
        cur.execute("analyze carga_atual")
        cur.execute(
            "delete from raw.registro r "
            "using (select distinct endpoint, chave from carga_atual where chave is not null) k "
            "where r.tenant_id = %s and r.endpoint = k.endpoint and r.chave_origem = k.chave "
            "and not exists (select 1 from carga_atual c where c.endpoint = r.endpoint "
            "and c.chave = r.chave_origem and c.hash = r.hash_registro) returning r.endpoint",
            (tenant,),
        )
        substituidos.update(linha[0] for linha in cur.fetchall())
        for endpoint in lote.endpoints_completos():
            cur.execute(
                "delete from raw.registro r where r.tenant_id = %s and r.endpoint = %s "
                "and not exists (select 1 from carga_atual c where c.endpoint = r.endpoint "
                "and c.hash = r.hash_registro) returning r.endpoint",
                (tenant, endpoint),
            )
            substituidos.update(linha[0] for linha in cur.fetchall())
        return novos, substituidos

    def gravar_tarefa(self, tenant, lote, nova_marca):
        with self.conexao.transaction(), self.conexao.cursor() as cur:
            novos, substituidos = self._gravar_registros(cur, tenant, lote)
            cur.execute(
                "insert into app.marca_carga (tenant_id, endpoint, ultima_referencia) values (%s, %s, %s) "
                "on conflict (tenant_id, endpoint) do update "
                "set ultima_referencia = excluded.ultima_referencia, atualizado_em = now()",
                (tenant, lote.tarefa.endpoint, nova_marca),
            )
        return {e: {"lidos": lote.lidos[e], "novos": novos[e], "substituidos": substituidos[e]}
                for e in set(lote.lidos) | set(substituidos)}

    def recarregar(self, tenant):
        with self.conexao.transaction(), self.conexao.cursor() as cur:
            cur.execute("select staging.recarregar(%s)", (tenant,))
            cur.execute("select staging.recarregar_precos(%s)", (tenant,))
            cur.execute("select staging.recarregar_complementos(%s)", (tenant,))

    def ler_eventos_pendentes(self, tenant, origem, limite):
        with self.conexao.cursor() as cur:
            cur.execute(
                "select id, tipo_evento, ids from app.evento_origem "
                "where tenant_id = %s and origem = %s and processado_em is null order by id limit %s",
                (tenant, origem, limite),
            )
            return cur.fetchall()

    @staticmethod
    def _marcar_processados(cur, tenant, ids_eventos):
        cur.execute(
            "update app.evento_origem set processado_em = now() "
            "where tenant_id = %s and id = any(%s::bigint[]) and processado_em is null",
            (tenant, list(ids_eventos)),
        )

    def limpar_eventos_processados(self, tenant, origem, dias=None):
        with self.conexao.transaction(), self.conexao.cursor() as cur:
            cur.execute(
                "delete from app.evento_origem where tenant_id = %s and origem = %s "
                "and processado_em < now() - make_interval(days => %s)",
                (tenant, origem, dias or DIAS_RETENCAO_EVENTOS),
            )

    def marcar_processados(self, tenant, ids_eventos):
        if not ids_eventos:
            return
        with self.conexao.transaction(), self.conexao.cursor() as cur:
            self._marcar_processados(cur, tenant, ids_eventos)

    def gravar_fila(self, tenant, lote):
        """Registros reconsultados, remoções e processado_em dos eventos do grupo na mesma transação."""
        removidos = Counter()
        with self.conexao.transaction(), self.conexao.cursor() as cur:
            novos, substituidos = self._gravar_registros(cur, tenant, lote)
            remocoes = lote.remocoes_confirmadas()
            if remocoes:
                endpoints, chaves = map(list, zip(*remocoes))
                cur.execute(
                    "delete from raw.registro r using unnest(%s::text[], %s::text[]) as k(endpoint, chave) "
                    "where r.tenant_id = %s and r.endpoint = k.endpoint and r.chave_origem = k.chave "
                    "returning r.endpoint",
                    (endpoints, chaves, tenant),
                )
                removidos.update(linha[0] for linha in cur.fetchall())
            self._marcar_processados(cur, tenant, lote.ids_eventos)
        return {e: {"lidos": lote.lidos[e], "novos": novos[e], "substituidos": substituidos[e],
                    "removidos": removidos[e]}
                for e in set(lote.lidos) | set(substituidos) | set(removidos)}


@dataclass
class Relatorio:
    linhas: list = field(default_factory=list)
    falhas: list = field(default_factory=list)
    cota_esgotada: bool = False
    caminho: str = "bulk"
    chamadas: dict = field(default_factory=dict)
    fila: dict = field(default_factory=dict)

    def texto(self):
        saida = [f"caminho: {self.caminho}"]
        if self.fila:
            saida.append(f"fila: {self.fila.get('processados', 0)} eventos processados, "
                         f"{self.fila.get('adiados', 0)} ficaram para a próxima execução")
            for endpoint, n in sorted(self.fila.get("linhas", []), key=lambda linha: linha[0]):
                saida.append(f"fila {endpoint}: {n['lidos']} lidos, {n['novos']} novos, "
                             f"{n['substituidos']} substituidos, {n['removidos']} removidos")
        for endpoint, n in sorted(self.linhas, key=lambda linha: linha[0]):
            saida.append(f"{endpoint}: {n['lidos']} lidos, {n['novos']} novos, {n['substituidos']} substituidos")
        saida += [f"falhou: {endpoint} ({motivo})" for endpoint, motivo in self.falhas]
        saida.append(f"chamadas: {self.chamadas.get('rest', 0)} REST, {self.chamadas.get('bulk', 0)} Bulk")
        if self.cota_esgotada:
            saida.append("carga interrompida: teto da cota diária atingido")
        return "\n".join(saida)


MAXIMO_EVENTOS_LIDOS = 2000
# Evento processado só serve para auditoria recente; sem limpeza a fila cresce sem fim.
DIAS_RETENCAO_EVENTOS = 30
GRUPOS_POR_TITULO = ("income", "outcome")


@dataclass(frozen=True)
class RegraEvento:
    """Como a carga trata um tipo de aviso do webhook (0016).

    `grupo` é o endpoint reconsultado por ID, ou o endpoint do plano que já relê tudo a cada
    execução. `remove` diz que o aviso é de exclusão na origem.
    """
    prefixo: str
    grupo: str
    chaves_id: tuple = ()
    remove: bool = False


# A primeira regra cujo prefixo casa vale; tipo sem regra é marcado como processado sem busca.
# Contrato cancelado continua na origem como distrato e entra no VSO, por isso só o removido sai.
REGRAS_EVENTO = (
    RegraEvento("RECEIVABLE_INSTALLMENT_REMOVED", "income", ("receivableBillId", "billId"), remove=True),
    RegraEvento("RECEIVABLE_INSTALLMENT_", "income", ("receivableBillId", "billId")),
    RegraEvento("RECEIPT_PROCESSED", "income", ("billId", "receivableBillId")),
    RegraEvento("PAYMENT_INSTALLMENT_REMOVED", "outcome", ("billId",), remove=True),
    RegraEvento("PAYMENT_INSTALLMENT_", "outcome", ("billId",)),
    RegraEvento("PAYMENT_RECEIPT_", "outcome", ("billId",)),
    RegraEvento("PAYMENT_BILL_UPDATED", "outcome", ("billId",)),
    RegraEvento("SALES_CONTRACT_REMOVED", "sales-contracts", ("salesContractId",), remove=True),
    RegraEvento("SALES_CONTRACT_", "sales-contracts", ("salesContractId",)),
    RegraEvento("UNIT_REMOVED", "units", ("unitId",), remove=True),
    RegraEvento("UNIT_", "units", ("unitId",)),
    RegraEvento("COST_CENTER_", "cost-centers"),
    RegraEvento("BUILDING_COST_ESTIMATION", "building-cost-estimation-items"),
)

# Endpoints em raw que guardam o mesmo registro do grupo; a remoção apaga de todos.
ENDPOINTS_DO_GRUPO = {"sales-contracts": ("sales-contracts", "sales")}


def regra_do_evento(tipo_evento):
    return next((r for r in REGRAS_EVENTO if tipo_evento.startswith(r.prefixo)), None)


def _inteiros(valor):
    if isinstance(valor, bool):
        return []
    if isinstance(valor, int):
        return [valor]
    if isinstance(valor, list):
        return [v for v in valor if isinstance(v, int) and not isinstance(v, bool)]
    return []


def ids_do_evento(regra, ids):
    alvos = set()
    for chave in regra.chaves_id:
        alvos.update(_inteiros(ids.get(chave)))
    return alvos


def remocoes_do_evento(regra, ids, alvos):
    """Chave em raw (a mesma de CHAVES) de cada registro que o aviso diz ter saído da origem."""
    if not regra.remove:
        return set()
    if regra.grupo in GRUPOS_POR_TITULO:
        parcela = _inteiros(ids.get("installmentId"))
        if len(alvos) != 1 or len(parcela) != 1:
            return set()
        return {(regra.grupo, f"{next(iter(alvos))}|{parcela[0]}")}
    return {(regra.grupo, str(alvo)) for alvo in alvos}


def _buscar_por_titulos(ctx, recurso, endpoint, titulos, parametros):
    ordenados = sorted(titulos)
    for inicio in range(0, len(ordenados), TITULOS_POR_CHAMADA):
        lote = ordenados[inicio:inicio + TITULOS_POR_CHAMADA]
        for bloco in ctx.cliente.bulk(recurso, {"billsIds": lote, **parametros}):
            for registro in bloco:
                yield endpoint, registro


def receber_da_fila(ctx, titulos):
    yield from _buscar_por_titulos(ctx, "income/by-bills", "income", titulos, {})


def pagar_da_fila(ctx, titulos):
    if not ctx.indexador_correcao:
        raise ValueError("ORIGEM_INDEXADOR_CORRECAO vazio; o a pagar exige indexador de correção")
    correcao = {"correctionIndexerId": ctx.indexador_correcao, "correctionDate": ctx.hoje.isoformat()}
    yield from _buscar_por_titulos(ctx, "outcome/by-bills", "outcome", titulos, correcao)


# Uma chamada por ID: a API não consulta contrato nem unidade em lote. O teto da fila limita o total.
def _buscar_um_a_um(ctx, recurso, ids):
    for id_registro in sorted(ids):
        # o cliente só expõe listagem paginada; _get devolve o objeto, ou None no 404
        resposta = ctx.cliente._get("rest", f"{recurso}/{id_registro}", {})
        if isinstance(resposta, dict):
            yield recurso, resposta


def contratos_da_fila(ctx, ids):
    # a obra do contrato alterado entra na lista do Bulk de vendas, que é o que o staging lê
    obras = ctx.compartilhado.setdefault("obras_venda_alterada", set())
    for endpoint, contrato in _buscar_um_a_um(ctx, "sales-contracts", ids):
        obras.add(contrato.get("enterpriseId"))
        yield endpoint, contrato


def unidades_da_fila(ctx, ids):
    yield from _buscar_um_a_um(ctx, "units", ids)


BUSCAS_FILA = {
    "income": receber_da_fila,
    "outcome": pagar_da_fila,
    "sales-contracts": contratos_da_fila,
    "units": unidades_da_fila,
}


def _custo_chamadas(grupo, quantidade):
    if grupo in GRUPOS_POR_TITULO:
        return "bulk", -(-quantidade // TITULOS_POR_CHAMADA)
    return "rest", quantidade


@dataclass
class PlanoFila:
    alvos: dict = field(default_factory=dict)
    remocoes: dict = field(default_factory=dict)
    eventos: dict = field(default_factory=dict)
    cobertos: dict = field(default_factory=dict)
    sem_busca: list = field(default_factory=list)
    adiados: int = 0


# O(E·k) para E eventos lidos e k IDs por evento (no máximo 10 chaves de 100). Nenhuma consulta
# por evento; os eventos entram por ordem de chegada até o teto de chamadas da execução.
def planejar_fila(eventos, usar_bulk, limites):
    plano = PlanoFila()
    gasto = {"rest": 0, "bulk": 0}
    for posicao, (id_evento, tipo_evento, ids) in enumerate(eventos):
        ids = ids if isinstance(ids, dict) else {}
        regra = regra_do_evento(tipo_evento or "")
        if regra is None:
            plano.sem_busca.append(id_evento)
            continue
        grupo = regra.grupo
        if grupo in GRUPOS_POR_TITULO and not usar_bulk:
            # Só REST: o a pagar vem de bills/by-change-date no plano e o a receber não é carregado.
            if grupo == "outcome":
                plano.cobertos.setdefault("bills", []).append(id_evento)
            else:
                plano.sem_busca.append(id_evento)
            continue
        if grupo not in BUSCAS_FILA:
            plano.cobertos.setdefault(grupo, []).append(id_evento)
            continue
        novos = ids_do_evento(regra, ids)
        if not novos:
            plano.sem_busca.append(id_evento)
            continue
        atuais = plano.alvos.get(grupo, set())
        tipo_chamada, antes = _custo_chamadas(grupo, len(atuais))
        _, depois = _custo_chamadas(grupo, len(atuais | novos))
        if gasto[tipo_chamada] - antes + depois > limites[tipo_chamada]:
            plano.adiados = len(eventos) - posicao
            break
        gasto[tipo_chamada] += depois - antes
        plano.alvos[grupo] = atuais | novos
        plano.remocoes.setdefault(grupo, set()).update(remocoes_do_evento(regra, ids, novos))
        plano.eventos.setdefault(grupo, []).append(id_evento)
    return plano


class LoteFila(LoteTarefa):
    def __init__(self, grupo, fonte, remocoes, ids_eventos):
        super().__init__(Tarefa(f"fila:{grupo}", "fila", grupo), fonte)
        self.grupo = grupo
        self.remocoes = remocoes
        self.ids_eventos = sorted(ids_eventos)

    def remocoes_confirmadas(self):
        """Aviso de remoção só apaga o que a reconsulta não trouxe de volta, em todo endpoint do grupo."""
        confirmadas = set()
        for endpoint, chave in self.remocoes:
            if (endpoint, chave) in self.vigentes:
                continue
            for destino in ENDPOINTS_DO_GRUPO.get(endpoint, (endpoint,)):
                confirmadas.add((destino, chave))
        return sorted(confirmadas)


def consumir_fila(ctx, fila, tenant, usar_bulk, limites, relatorio):
    """Reconsulta os IDs avisados pelo webhook antes da carga incremental.

    Cada grupo grava numa transação que também marca os eventos dele como processados; se a
    busca falhar, os eventos ficam pendentes para a próxima execução.
    """
    try:
        eventos = fila.ler_eventos_pendentes(tenant, "erp", MAXIMO_EVENTOS_LIDOS)
    except Exception as erro:
        # sem a fila, a carga incremental ainda cobre o dia; o evento espera a próxima execução
        log.error("fila: leitura falhou: %s", type(erro).__name__)
        relatorio.falhas.append(("fila", type(erro).__name__))
        return None
    if not eventos:
        return None
    plano = planejar_fila(eventos, usar_bulk, limites)
    processados = 0
    linhas = []
    try:
        fila.marcar_processados(tenant, plano.sem_busca)
        processados += len(plano.sem_busca)
    except Exception as erro:
        log.error("fila: marcar eventos sem busca falhou: %s", type(erro).__name__)
        relatorio.falhas.append(("fila", type(erro).__name__))
    for grupo, busca in BUSCAS_FILA.items():
        if grupo not in plano.eventos:
            continue
        lote = LoteFila(grupo, busca(ctx, plano.alvos[grupo]), plano.remocoes.get(grupo, set()), plano.eventos[grupo])
        try:
            contagens = fila.gravar_fila(tenant, lote)
        except CotaEsgotada:
            relatorio.cota_esgotada = True
            relatorio.falhas.append((f"fila:{grupo}", "cota diária"))
            break
        except BulkIndisponivel:
            # o plano descobre o pacote sem Bulk e troca de caminho; o evento espera a próxima execução
            log.warning("fila: Bulk indisponível para %s; eventos ficam pendentes", grupo)
            continue
        except (ErroOrigem, EndpointSemLista, ValueError) as erro:
            log.error("fila:%s falhou: %s", grupo, erro)
            relatorio.falhas.append((f"fila:{grupo}", str(erro)))
            continue
        except Exception as erro:
            log.error("fila:%s falhou no banco: %s", grupo, type(erro).__name__)
            relatorio.falhas.append((f"fila:{grupo}", type(erro).__name__))
            continue
        ctx.concluidas.add(f"fila:{grupo}")
        processados += len(lote.ids_eventos)
        linhas.extend(contagens.items())
    adiados = plano.adiados
    if len(eventos) == MAXIMO_EVENTOS_LIDOS:
        log.info("fila: leitura chegou a %s eventos; o restante fica para a próxima execução", MAXIMO_EVENTOS_LIDOS)
    relatorio.fila = {"processados": processados, "adiados": adiados, "linhas": linhas}
    return plano


def marcar_cobertos(fila, tenant, plano, concluidas, tentadas, relatorio):
    """Evento de tipo que o plano relê inteiro sai da fila quando o endpoint do plano foi gravado,
    ou quando o endpoint não está no caminho deste tenant (não há o que reler)."""
    if plano is None or relatorio.cota_esgotada:
        return
    ids = [i for endpoint, lista in plano.cobertos.items()
           if endpoint in concluidas or endpoint not in tentadas for i in lista]
    try:
        fila.marcar_processados(tenant, ids)
    except Exception as erro:
        log.error("fila: marcar eventos cobertos falhou: %s", type(erro).__name__)
        relatorio.falhas.append(("fila", type(erro).__name__))
        return
    total = sum(len(lista) for lista in plano.cobertos.values())
    relatorio.fila["processados"] = relatorio.fila.get("processados", 0) + len(ids)
    relatorio.fila["adiados"] = relatorio.fila.get("adiados", 0) + total - len(ids)


def ordenar_pela_marca(plano, marcas):
    """Tarefas do plano comum na ordem fixa; as demais pela marca mais antiga primeiro.

    A cota esgotada desfaz a tarefa sem avançar a marca. Com ordem fixa, a mesma tarefa falharia todo
    dia e as de trás nunca rodariam; pela marca, quem ficou sem carga vai para a frente na execução
    seguinte. O(T log T) em tarefas.
    """
    comuns = [t for t in plano if t in PLANO_COMUM]
    demais = [t for t in plano if t not in PLANO_COMUM]
    demais.sort(key=lambda t: (marcas.get(t.endpoint) is not None, marcas.get(t.endpoint) or date.min))
    return comuns + demais


def _usar_bulk(modo, hoje, reverificar_dias):
    if not modo or not modo[0]:
        return True
    return (hoje - modo[1].date()).days >= reverificar_dias


# O(T) tarefas; cada tarefa é O(n) nos registros dela.
def executar(cliente, repositorio, tenant, hoje, **opcoes):
    reverificar_dias = opcoes.pop("reverificar_bulk_dias", 30)
    fila_eventos = opcoes.pop("fila_eventos", None)
    limites_fila = {"rest": opcoes.pop("limite_fila_rest", 100), "bulk": opcoes.pop("limite_fila_bulk", 4)}
    marcas, modo, obras = repositorio.ler_estado(tenant)
    ctx = Contexto(cliente=cliente, hoje=hoje, obras=obras, **opcoes)
    usar_bulk = _usar_bulk(modo, hoje, reverificar_dias)
    relatorio = Relatorio(caminho="bulk" if usar_bulk else "so_rest")
    plano_fila = None
    if fila_eventos is not None:
        plano_fila = consumir_fila(ctx, fila_eventos, tenant, usar_bulk, limites_fila, relatorio)
    fila = [] if relatorio.cota_esgotada else ordenar_pela_marca(PLANO_BULK if usar_bulk else PLANO_SO_REST, marcas)
    tentadas = set()
    bulk_respondeu = False
    while fila:
        tarefa = fila.pop(0)
        tentadas.add(tarefa.endpoint)
        try:
            lote = LoteTarefa(tarefa, ESTRATEGIAS[tarefa.estrategia](ctx, tarefa, marcas.get(tarefa.endpoint)))
            contagens = repositorio.gravar_tarefa(tenant, lote, hoje)
        except BulkIndisponivel:
            log.warning("Bulk indisponível para o tenant; seguindo pelo caminho só REST")
            repositorio.gravar_modo(tenant, True)
            relatorio.caminho = "so_rest"
            usar_bulk = False
            fila = [t for t in ordenar_pela_marca(PLANO_SO_REST, marcas) if t.endpoint not in tentadas]
            continue
        except CotaEsgotada:
            relatorio.cota_esgotada = True
            relatorio.falhas.append((tarefa.endpoint, "cota diária"))
            marca = marcas.get(tarefa.endpoint)
            if marca is None or (hoje - marca).days >= 2:
                # Sem carga há mais de um dia: a cota configurada não cabe no plano do tenant.
                log.warning("%s sem carga desde %s por cota diária; confira ORIGEM_COTA_DIARIA e "
                            "ORIGEM_COTA_DIARIA_BULK contra o pacote do cliente",
                            tarefa.endpoint, marca.isoformat() if marca else "a primeira execução")
            break
        except (ErroOrigem, EndpointSemLista, ValueError) as erro:
            log.error("%s falhou: %s", tarefa.endpoint, erro)
            relatorio.falhas.append((tarefa.endpoint, str(erro)))
            continue
        except Exception as erro:
            # erro do banco pode trazer valor de linha no detalhe; o log leva só o tipo
            log.error("%s falhou no banco: %s", tarefa.endpoint, type(erro).__name__)
            relatorio.falhas.append((tarefa.endpoint, type(erro).__name__))
            continue
        ctx.concluidas.add(tarefa.endpoint)
        if tarefa in PLANO_BULK and tarefa not in PLANO_COMUM:
            bulk_respondeu = True
        relatorio.linhas.extend(contagens.items())
    if usar_bulk and bulk_respondeu and modo and modo[0]:
        repositorio.gravar_modo(tenant, False)
    if fila_eventos is not None:
        marcar_cobertos(fila_eventos, tenant, plano_fila, ctx.concluidas, tentadas, relatorio)
    if ctx.concluidas:
        try:
            repositorio.recarregar(tenant)
        except Exception as erro:
            log.error("recarga do staging falhou: %s", type(erro).__name__)
            relatorio.falhas.append(("staging", type(erro).__name__))
    relatorio.chamadas = dict(cliente.chamadas)
    return relatorio


def opcoes_de_ambiente(ambiente=None):
    amb = os.environ if ambiente is None else ambiente
    return {
        "janela_dias": int(amb.get("ORIGEM_JANELA_INICIAL_DIAS") or 400),
        "horizonte_dias": int(amb.get("ORIGEM_HORIZONTE_DIAS") or 3650),
        "dias_pagamento": int(amb.get("ORIGEM_DIAS_PAGAMENTO") or 7),
        "indexador_correcao": amb.get("ORIGEM_INDEXADOR_CORRECAO", ""),
        "reverificar_bulk_dias": int(amb.get("ORIGEM_REVERIFICAR_BULK_DIAS") or 30),
        "limite_fila_rest": int(amb.get("ORIGEM_FILA_LIMITE_REST") or 100),
        "limite_fila_bulk": int(amb.get("ORIGEM_FILA_LIMITE_BULK") or 4),
    }


def main():
    import psycopg
    from dotenv import load_dotenv

    load_dotenv(RAIZ / ".env")
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    parser = argparse.ArgumentParser()
    parser.add_argument("--tenant", default=os.environ.get("TENANT_ID"))
    args = parser.parse_args()
    if not args.tenant or not os.environ.get("DATABASE_URL"):
        sys.exit("Informe TENANT_ID (ou --tenant) e DATABASE_URL no .env")
    try:
        config = ConfiguracaoOrigem.de_ambiente()
    except ValueError as erro:
        sys.exit(str(erro))
    cliente = ClienteOrigem(config)
    with psycopg.connect(os.environ["DATABASE_URL"], autocommit=True) as conexao:
        repositorio = RepositorioBanco(conexao)
        relatorio = executar(cliente, repositorio, args.tenant, date.today(), fila_eventos=repositorio,
                             **opcoes_de_ambiente())
        repositorio.limpar_eventos_processados(args.tenant, "erp")
    print(relatorio.texto())
    if relatorio.cota_esgotada:
        sys.exit(2)
    if relatorio.falhas:
        sys.exit(1)


if __name__ == "__main__":
    main()
