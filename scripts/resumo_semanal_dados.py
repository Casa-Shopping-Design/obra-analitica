"""Lê do banco quem recebe o resumo semanal e os números de cada obra.

O script conecta com a credencial do servidor, que passa por fora do RLS. Por isso as obras de cada
destinatário são escolhidas duas vezes: em Python, pela regra de perfil, e no banco, por app.obras_permitidas()
com os claims do próprio usuário, que é o mesmo predicado das políticas de staging. Se as duas listas
discordarem, o usuário fica sem e-mail.
"""

import json
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from decimal import Decimal

PERFIS_TODAS_AS_OBRAS = frozenset({"diretor", "financeiro"})
PERFIS_DESTINATARIOS = PERFIS_TODAS_AS_OBRAS | {"gerente_obra"}


@dataclass(frozen=True)
class Destinatario:
    user_id: str
    tenant_id: str
    perfil: str
    email: str
    obras_vinculadas: frozenset


@dataclass(frozen=True)
class Alerta:
    tipo: str
    valor: Decimal | None
    referencia: Decimal | None


@dataclass(frozen=True)
class ResumoObra:
    tenant_id: str
    centro_custo_id: str
    obra: str
    vendas_semana: int
    valor_vendas_semana: Decimal
    vendas_mes: int
    valor_vendas_mes: Decimal
    distratos_mes: int
    vso_mes_anterior: Decimal | None
    vencido_direto: Decimal
    fracao_inadimplencia: Decimal | None
    caixa_atual: Decimal
    exposicao_maxima: Decimal
    unidades_estoque: int
    meses_para_vender_estoque: Decimal | None
    ultima_carga_em: datetime | None
    alertas: tuple = ()


@dataclass(frozen=True)
class Periodo:
    hoje: date
    inicio_semana: date
    mes_atual: date
    mes_anterior: date


def periodo_do_resumo(hoje):
    """A semana são os sete dias antes de hoje; rodando na segunda, vai de segunda a domingo."""
    mes_atual = hoje.replace(day=1)
    mes_anterior = (mes_atual - timedelta(days=1)).replace(day=1)
    return Periodo(hoje=hoje, inicio_semana=hoje - timedelta(days=7), mes_atual=mes_atual, mes_anterior=mes_anterior)


SQL_DESTINATARIOS = """
select ut.user_id::text, ut.tenant_id::text, ut.perfil, u.email::text,
  coalesce(array_agg(ucc.centro_custo_id::text) filter (where ucc.centro_custo_id is not null), '{}') as vinculadas
from app.usuario_tenant ut
join app.tenant t on t.id = ut.tenant_id and t.status = 'ativo'
join auth.users u on u.id = ut.user_id
left join app.usuario_centro_custo ucc on ucc.user_id = ut.user_id and ucc.tenant_id = ut.tenant_id
where ut.perfil = any (%(perfis)s)
  and u.email is not null
  and u.email_confirmed_at is not null
  and u.deleted_at is null
  and (u.banned_until is null or u.banned_until < now())
group by 1, 2, 3, 4
order by 2, 1
"""

# Uma consulta para todas as obras de todos os tenants ativos. As views de marts recalculam o fluxo
# inteiro de cada obra: O(p + c) em parcelas e contratos, alguns milhares por tenant no piloto.
SQL_OBRAS = """
with semana as (
  select tenant_id, centro_custo_id, count(*) as vendas, coalesce(sum(valor), 0) as valor
  from staging.contrato_venda
  where situacao in ('1', '3') and data_venda >= %(inicio_semana)s and data_venda < %(hoje)s
  group by 1, 2
), mes as (
  select tenant_id, centro_custo_id,
    sum(vendas) filter (where competencia = %(mes_atual)s) as vendas,
    sum(vgv_vendido) filter (where competencia = %(mes_atual)s) as valor,
    sum(distratos) filter (where competencia = %(mes_atual)s) as distratos,
    max(vso_pct) filter (where competencia = %(mes_anterior)s) as vso_mes_anterior
  from marts.vso_mensal
  where competencia in (%(mes_atual)s, %(mes_anterior)s)
  group by 1, 2
), alertas as (
  -- valor em texto para o numeric não virar float no JSON
  select tenant_id, centro_custo_id,
    jsonb_agg(jsonb_build_object('tipo', tipo, 'valor', valor::text, 'referencia', referencia::text)
              order by tipo) as lista
  from marts.alertas_obra
  group by 1, 2
)
select p.tenant_id::text, p.centro_custo_id::text, p.obra,
  coalesce(s.vendas, 0), coalesce(s.valor, 0),
  coalesce(m.vendas, 0), coalesce(m.valor, 0), coalesce(m.distratos, 0), m.vso_mes_anterior,
  p.vencido_direto,
  p.vencido_direto / nullif(p.recebido_direto + p.a_receber_direto + p.vencido_direto, 0),
  p.caixa_atual, p.exposicao_maxima,
  coalesce(e.unidades_estoque, 0), e.meses_para_vender_estoque,
  u.ultima_carga_em,
  coalesce(a.lista, '[]'::jsonb)
from marts.posicao_financeira_obra p
join app.tenant t on t.id = p.tenant_id and t.status = 'ativo'
left join marts.estoque_obra e on e.tenant_id = p.tenant_id and e.centro_custo_id = p.centro_custo_id
left join semana s on s.tenant_id = p.tenant_id and s.centro_custo_id = p.centro_custo_id
left join mes m on m.tenant_id = p.tenant_id and m.centro_custo_id = p.centro_custo_id
left join alertas a on a.tenant_id = p.tenant_id and a.centro_custo_id = p.centro_custo_id
left join marts.ultima_carga u on u.tenant_id = p.tenant_id
order by p.tenant_id, p.obra
"""


def _decimal(valor):
    return None if valor is None else Decimal(str(valor))


def ler_destinatarios(conexao):
    with conexao.cursor() as cur:
        cur.execute(SQL_DESTINATARIOS, {"perfis": sorted(PERFIS_DESTINATARIOS)})
        return [
            Destinatario(user_id=user_id, tenant_id=tenant_id, perfil=perfil, email=email,
                         obras_vinculadas=frozenset(vinculadas))
            for user_id, tenant_id, perfil, email, vinculadas in cur.fetchall()
        ]


def ler_obras(conexao, periodo):
    parametros = {"hoje": periodo.hoje, "inicio_semana": periodo.inicio_semana,
                  "mes_atual": periodo.mes_atual, "mes_anterior": periodo.mes_anterior}
    with conexao.cursor() as cur:
        cur.execute(SQL_OBRAS, parametros)
        linhas = cur.fetchall()
    obras = []
    for linha in linhas:
        alertas = tuple(Alerta(tipo=item["tipo"], valor=_decimal(item["valor"]), referencia=_decimal(item["referencia"]))
                        for item in linha[16])
        obras.append(ResumoObra(
            tenant_id=linha[0], centro_custo_id=linha[1], obra=linha[2],
            vendas_semana=int(linha[3]), valor_vendas_semana=_decimal(linha[4]),
            vendas_mes=int(linha[5]), valor_vendas_mes=_decimal(linha[6]), distratos_mes=int(linha[7]),
            vso_mes_anterior=_decimal(linha[8]),
            vencido_direto=_decimal(linha[9]), fracao_inadimplencia=_decimal(linha[10]),
            caixa_atual=_decimal(linha[11]), exposicao_maxima=_decimal(linha[12]),
            unidades_estoque=int(linha[13]), meses_para_vender_estoque=_decimal(linha[14]),
            ultima_carga_em=linha[15], alertas=alertas,
        ))
    return obras


def agrupar_por_tenant(obras):
    por_tenant = {}
    for obra in obras:
        por_tenant.setdefault(obra.tenant_id, []).append(obra)
    return por_tenant


def obras_do_destinatario(destinatario, obras_por_tenant):
    """Diretor e financeiro veem todas as obras do tenant; gerente de obra, só as vinculadas a ele."""
    do_tenant = obras_por_tenant.get(destinatario.tenant_id, [])
    if destinatario.perfil in PERFIS_TODAS_AS_OBRAS:
        return list(do_tenant)
    if destinatario.perfil not in PERFIS_DESTINATARIOS:
        return []
    return [obra for obra in do_tenant if obra.centro_custo_id in destinatario.obras_vinculadas]


def obras_pelo_rls(conexao, destinatario):
    """Pergunta ao banco quais obras o usuário vê, como se ele estivesse logado no tenant do resumo.

    O claim leva só o tenant; o perfil o banco lê de app.usuario_tenant, para não repetir o que o script já
    decidiu. O papel e os claims valem dentro do savepoint e voltam ao que eram no rollback.
    """
    claims = json.dumps({
        "sub": destinatario.user_id,
        "role": "authenticated",
        "app_metadata": {"tenant_id": destinatario.tenant_id},
    })
    with conexao.cursor() as cur:
        cur.execute("savepoint conferencia_rls")
        try:
            cur.execute("select set_config('request.jwt.claims', %s, true)", (claims,))
            cur.execute("set local role authenticated")
            cur.execute("select id::text from app.obras_permitidas() as id")
            return frozenset(linha[0] for linha in cur.fetchall())
        finally:
            cur.execute("rollback to savepoint conferencia_rls")
            cur.execute("release savepoint conferencia_rls")


@dataclass
class Pacote:
    destinatario: Destinatario
    obras: list


@dataclass
class Coleta:
    pacotes: list
    destinatarios: int = 0
    sem_obra: int = 0
    divergentes: int = 0


# O(u * o) com u destinatários e o obras do tenant, dezenas de cada. Os números vêm da consulta em lote;
# por usuário roda só a conferência no RLS, que é uma busca por índice.
def coletar(conexao, periodo):
    destinatarios = ler_destinatarios(conexao)
    obras_por_tenant = agrupar_por_tenant(ler_obras(conexao, periodo))
    coleta = Coleta(pacotes=[], destinatarios=len(destinatarios))
    for destinatario in destinatarios:
        obras = obras_do_destinatario(destinatario, obras_por_tenant)
        if not obras:
            coleta.sem_obra += 1
            continue
        if {obra.centro_custo_id for obra in obras} != obras_pelo_rls(conexao, destinatario):
            coleta.divergentes += 1
            continue
        coleta.pacotes.append(Pacote(destinatario=destinatario, obras=obras))
    return coleta
