"""Monta o e-mail do resumo semanal: formatação brasileira dos números, HTML com CSS inline e texto puro."""

from datetime import timedelta
from decimal import ROUND_HALF_UP, Decimal
from html import escape
from zoneinfo import ZoneInfo

FUSO = ZoneInfo("America/Sao_Paulo")
ESPACO_FIXO = " "
# Carga mais velha que isso ganha aviso no e-mail, o mesmo limite da rota de saúde.
HORAS_CARGA_ATRASADA = 26

NOMES_MES = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro",
             "outubro", "novembro", "dezembro"]
NOMES_DIA = ["segunda-feira", "terça-feira", "quarta-feira", "quinta-feira", "sexta-feira", "sábado", "domingo"]

# Paleta de painel/app/globals.css.
COR_FUNDO = "#f3f5f1"
COR_SUPERFICIE = "#ffffff"
COR_TEXTO = "#16211f"
COR_SUAVE = "#52605c"
COR_BORDA = "#d5dcd6"
COR_TRILHO = "#e3e8e3"
COR_MENU = "#0b4357"
COR_MENU_TEXTO = "#eef4f2"
COR_ENTRADA = "#4f7a19"
COR_ATENCAO = "#8a5a0b"
COR_ALERTA = "#b3261e"
FONTE = "Arial, Helvetica, sans-serif"

# A ordem repete tiposAlerta de painel/lib/alertas.ts: primeiro o que já custa caixa, depois o prazo.
ORDEM_ALERTAS = ["repasse_atrasado", "estoque_apos_entrega", "estouro_orcamento", "inadimplencia_alta",
                 "pago_a_frente_do_fisico"]


def _agrupar_milhar(inteiro):
    return f"{inteiro:,}".replace(",", ".")


def formatar_real(valor):
    """1234.5 vira "R$ 1.234,50", com espaço que não quebra linha, como o Intl do painel."""
    centavos = Decimal(str(valor)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    sinal = "-" if centavos < 0 else ""
    inteiro, fracao = f"{abs(centavos):.2f}".split(".")
    return f"{sinal}R${ESPACO_FIXO}{_agrupar_milhar(int(inteiro))},{fracao}"


def formatar_percentual(fracao):
    """Recebe fração: 0.0612 vira "6,1%"."""
    pontos = (Decimal(str(fracao)) * 100).quantize(Decimal("0.1"), rounding=ROUND_HALF_UP)
    if pontos == 0:
        pontos = abs(pontos)
    return f"{pontos}%".replace(".", ",")


def descrever_vso(vso):
    """VSO negativo é mês com mais distrato que venda; dito assim, o leitor não acha que é erro."""
    if vso is None:
        return "Sem estoque no início do mês"
    if vso < 0:
        return "Mais distratos que vendas"
    return formatar_percentual(vso)


def formatar_decimal(valor):
    arredondado = Decimal(str(valor)).quantize(Decimal("0.1"), rounding=ROUND_HALF_UP)
    texto = f"{arredondado:.1f}".replace(".", ",")
    return texto[:-2] if texto.endswith(",0") else texto


def formatar_meses(quantidade):
    texto = formatar_decimal(quantidade)
    return "1 mês" if texto == "1" else f"{texto} meses"


def formatar_unidades(quantidade):
    return "1 unidade" if quantidade == 1 else f"{_agrupar_milhar(quantidade)} unidades"


def formatar_vendas(quantidade, valor):
    if quantidade == 0:
        return "Nenhuma venda"
    return f"{formatar_unidades(quantidade)}, {formatar_real(valor)}"


def formatar_data_hora(momento):
    local = momento.astimezone(FUSO)
    return f"{local:%d/%m/%Y} às {local:%H:%M}"


def data_por_extenso(dia):
    return f"{NOMES_DIA[dia.weekday()]}, {dia.day} de {NOMES_MES[dia.month - 1]} de {dia.year}"


def texto_alerta(alerta):
    """Título e detalhe do alerta, com as mesmas frases de painel/lib/alertas.ts."""
    valor, referencia = alerta.valor, alerta.referencia
    if alerta.tipo == "repasse_atrasado":
        return "Repasse do banco atrasado", f"{formatar_real(valor or 0)} de repasse já venceu e não entrou."
    if alerta.tipo == "estoque_apos_entrega":
        if valor is None:
            return ("Estoque parado",
                    "Não houve venda líquida nos últimos 6 meses; no ritmo atual o estoque não acaba.")
        if referencia == 0:
            return ("Obra entregue com estoque",
                    f"No ritmo dos últimos 6 meses, o que sobrou leva {formatar_meses(valor)} para vender.")
        return ("Estoque não acaba antes da entrega",
                f"No ritmo dos últimos 6 meses, o estoque leva {formatar_meses(valor)} para vender; "
                f"a entrega é daqui a {formatar_meses(referencia or 0)}.")
    if alerta.tipo == "estouro_orcamento":
        if referencia and referencia > 0:
            return ("Custo acima do orçamento",
                    f"O custo lançado passou o orçamento em {formatar_real(valor or 0)} "
                    f"({formatar_percentual((valor or 0) / referencia)} do orçado).")
        return "Custo acima do orçamento", f"Há {formatar_real(valor or 0)} de custo lançado sem orçamento cadastrado."
    if alerta.tipo == "inadimplencia_alta":
        return ("Inadimplência alta",
                f"{formatar_real(valor or 0)} vencidos dos compradores, "
                f"{formatar_percentual(referencia or 0)} da carteira direta.")
    if alerta.tipo == "pago_a_frente_do_fisico":
        pontos = int(((valor or Decimal(0)) * 100).quantize(Decimal("1"), rounding=ROUND_HALF_UP))
        return ("Pago à frente do físico",
                f"O pago está {pontos} pontos à frente da medição. Vale conferir adiantamento ou medição atrasada.")
    return None


def alertas_ordenados(obras):
    """Pares (obra, título, detalhe). Tipo que este script não conhece fica fora em vez de quebrar o e-mail."""
    itens = []
    for obra in obras:
        for alerta in obra.alertas:
            texto = texto_alerta(alerta)
            if texto and alerta.tipo in ORDEM_ALERTAS:
                itens.append((ORDEM_ALERTAS.index(alerta.tipo), obra.obra, texto[0], texto[1]))
    itens.sort(key=lambda item: (item[0], item[1]))
    return [(obra, titulo, detalhe) for _, obra, titulo, detalhe in itens]


def assunto(obras, periodo):
    quantidade = len(alertas_ordenados(obras))
    base = f"Resumo semanal das obras, {periodo.hoje:%d/%m/%Y}"
    if quantidade == 0:
        return base
    return f"{base}: {quantidade} {'alerta' if quantidade == 1 else 'alertas'}"


def linhas_da_obra(obra, periodo):
    """Pares (rótulo, valor) já formatados, na ordem em que aparecem no e-mail."""
    mes = NOMES_MES[periodo.mes_atual.month - 1]
    mes_anterior = NOMES_MES[periodo.mes_anterior.month - 1]
    vendas_mes = formatar_vendas(obra.vendas_mes, obra.valor_vendas_mes)
    if obra.distratos_mes:
        vendas_mes += f"; {obra.distratos_mes} {'distrato' if obra.distratos_mes == 1 else 'distratos'}"
    if obra.fracao_inadimplencia is None:
        inadimplencia = formatar_real(obra.vencido_direto)
    else:
        inadimplencia = (f"{formatar_real(obra.vencido_direto)} "
                         f"({formatar_percentual(obra.fracao_inadimplencia)} da carteira direta)")
    if obra.unidades_estoque == 0:
        estoque = "Sem unidades à venda"
    elif obra.meses_para_vender_estoque is None:
        estoque = f"{formatar_unidades(obra.unidades_estoque)}, sem ritmo de venda nos últimos 6 meses"
    else:
        estoque = (f"{formatar_unidades(obra.unidades_estoque)}, "
                   f"{formatar_meses(obra.meses_para_vender_estoque)} no ritmo atual")
    return [
        ("Vendas na semana", formatar_vendas(obra.vendas_semana, obra.valor_vendas_semana)),
        (f"Vendas em {mes}", vendas_mes),
        (f"VSO de {mes_anterior}", descrever_vso(obra.vso_mes_anterior)),
        ("Vencido dos compradores", inadimplencia),
        ("Caixa atual", formatar_real(obra.caixa_atual)),
        ("Exposição máxima", formatar_real(obra.exposicao_maxima)),
        ("Estoque", estoque),
    ]


def ultima_carga(obras):
    datas = [obra.ultima_carga_em for obra in obras if obra.ultima_carga_em is not None]
    return min(datas) if datas else None


def aviso_carga(obras, agora):
    momento = ultima_carga(obras)
    if momento is None:
        return "Ainda não há carga concluída para estas obras; os números podem estar zerados."
    if agora - momento > timedelta(hours=HORAS_CARGA_ATRASADA):
        return (f"A última carga terminou em {formatar_data_hora(momento)}. "
                "Os números podem estar desatualizados.")
    return None


def _link_obra(painel_url_base, obra):
    return f"{painel_url_base.rstrip('/')}/obras/{obra.centro_custo_id}"


def _agrupar_alertas_por_obra(alertas):
    """Um grupo por obra, na ordem do alerta mais grave de cada uma."""
    grupos = {}
    for obra, titulo, detalhe in alertas:
        grupos.setdefault(obra, []).append((titulo, detalhe))
    return list(grupos.items())


def _bloco_alertas(alertas):
    titulo = (f'<tr><td style="padding:24px 24px 8px 24px;font-family:{FONTE};font-size:18px;font-weight:bold;'
              f'color:{COR_ATENCAO};">Pede atenção</td></tr>')
    if not alertas:
        return titulo + (f'<tr><td style="padding:0 24px 8px 24px;font-family:{FONTE};font-size:15px;'
                         f'color:{COR_SUAVE};">Nenhum alerta aberto nas suas obras.</td></tr>')
    cartoes = []
    for obra, itens in _agrupar_alertas_por_obra(alertas):
        linhas = "".join(
            f'<tr><td style="padding:6px 0 0 0;font-family:{FONTE};font-size:15px;line-height:21px;color:{COR_TEXTO};">'
            f'{escape(titulo_alerta)}<br><span style="color:{COR_SUAVE};font-size:14px;">{escape(detalhe)}</span>'
            f'</td></tr>'
            for titulo_alerta, detalhe in itens
        )
        cartoes.append(
            f'<tr><td style="padding:0 24px 12px 24px;">'
            f'<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" '
            f'style="border-left:3px solid {COR_ALERTA};background:{COR_FUNDO};">'
            f'<tr><td style="padding:10px 12px 12px 12px;">'
            f'<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">'
            f'<tr><td style="font-family:{FONTE};font-size:16px;font-weight:bold;color:{COR_TEXTO};">{escape(obra)}</td></tr>'
            f'{linhas}</table></td></tr></table></td></tr>'
        )
    return titulo + "".join(cartoes)


def _bloco_obra(obra, periodo, painel_url_base):
    linhas = []
    for rotulo, valor in linhas_da_obra(obra, periodo):
        linhas.append(
            f'<tr><td style="padding:8px 0;border-top:1px solid {COR_TRILHO};font-family:{FONTE};font-size:14px;'
            f'color:{COR_SUAVE};vertical-align:top;width:42%;">{escape(rotulo)}</td>'
            f'<td style="padding:8px 0 8px 12px;border-top:1px solid {COR_TRILHO};font-family:{FONTE};font-size:15px;'
            f'color:{COR_TEXTO};text-align:right;vertical-align:top;">{escape(valor)}</td></tr>'
        )
    return (
        f'<tr><td style="padding:16px 24px 8px 24px;">'
        f'<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" '
        f'style="border:1px solid {COR_BORDA};border-radius:6px;">'
        f'<tr><td style="padding:14px 16px 4px 16px;font-family:{FONTE};font-size:17px;font-weight:bold;'
        f'color:{COR_TEXTO};">{escape(obra.obra)}</td></tr>'
        f'<tr><td style="padding:0 16px 8px 16px;">'
        f'<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">{"".join(linhas)}</table>'
        f'</td></tr>'
        f'<tr><td style="padding:4px 16px 14px 16px;font-family:{FONTE};font-size:14px;">'
        f'<a href="{escape(_link_obra(painel_url_base, obra))}" style="color:{COR_ENTRADA};">Ver a obra no painel</a>'
        f'</td></tr></table></td></tr>'
    )


def montar_html(obras, periodo, painel_url_base, agora):
    alertas = alertas_ordenados(obras)
    aviso = aviso_carga(obras, agora)
    momento = ultima_carga(obras)
    carga = f"Dados carregados em {formatar_data_hora(momento)}." if momento else ""
    resumo_oculto = (f"{len(alertas)} {'alerta' if len(alertas) == 1 else 'alertas'} e os números de "
                     f"{len(obras)} {'obra' if len(obras) == 1 else 'obras'}.")
    bloco_aviso = ""
    if aviso:
        bloco_aviso = (f'<tr><td style="padding:16px 24px 0 24px;font-family:{FONTE};font-size:14px;'
                       f'color:{COR_ATENCAO};">{escape(aviso)}</td></tr>')
    obras_html = "".join(_bloco_obra(obra, periodo, painel_url_base) for obra in obras)
    return f"""<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light">
<title>Resumo semanal das obras</title>
</head>
<body style="margin:0;padding:0;background:{COR_FUNDO};">
<div style="display:none;max-height:0;overflow:hidden;">{escape(resumo_oculto)}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:{COR_FUNDO};">
<tr><td align="center" style="padding:16px 8px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:600px;background:{COR_SUPERFICIE};border-radius:8px;">
<tr><td style="padding:20px 24px;background:{COR_MENU};border-radius:8px 8px 0 0;font-family:{FONTE};">
<div style="font-size:13px;color:{COR_MENU_TEXTO};letter-spacing:0.5px;">APO</div>
<div style="font-size:22px;font-weight:bold;color:{COR_MENU_TEXTO};padding-top:4px;">Resumo da semana</div>
<div style="font-size:14px;color:{COR_MENU_TEXTO};padding-top:4px;">{escape(data_por_extenso(periodo.hoje))}</div>
</td></tr>
{bloco_aviso}
{_bloco_alertas(alertas)}
<tr><td style="padding:16px 24px 0 24px;font-family:{FONTE};font-size:18px;font-weight:bold;color:{COR_TEXTO};">Suas obras</td></tr>
{obras_html}
<tr><td align="center" style="padding:20px 24px 8px 24px;">
<a href="{escape(painel_url_base)}" style="display:inline-block;padding:12px 28px;background:{COR_ENTRADA};color:{COR_SUPERFICIE};font-family:{FONTE};font-size:16px;font-weight:bold;text-decoration:none;border-radius:6px;">Abrir o painel</a>
</td></tr>
<tr><td style="padding:16px 24px 24px 24px;font-family:{FONTE};font-size:12px;line-height:18px;color:{COR_SUAVE};">
{escape(carga)} Semana de {periodo.inicio_semana:%d/%m} a {periodo.hoje - timedelta(days=1):%d/%m}.
Vencido dos compradores é o que passou do vencimento e não foi pago, sem contar repasse do banco.
Exposição máxima é o dinheiro próprio que a obra exige no pior mês.<br>
Você recebe este resumo porque tem acesso ao painel. O detalhe de cada número está nele.
</td></tr>
</table>
</td></tr>
</table>
</body>
</html>
"""


def montar_texto(obras, periodo, painel_url_base, agora):
    """Versão em texto puro, para quem lê sem HTML e para o filtro de spam."""
    partes = [f"Resumo da semana, {data_por_extenso(periodo.hoje)}", ""]
    aviso = aviso_carga(obras, agora)
    if aviso:
        partes += [aviso, ""]
    partes.append("Pede atenção")
    alertas = alertas_ordenados(obras)
    if not alertas:
        partes.append("Nenhum alerta aberto nas suas obras.")
    for obra, titulo, detalhe in alertas:
        partes.append(f"- {obra}: {titulo}. {detalhe}")
    for obra in obras:
        partes += ["", obra.obra]
        partes += [f"  {rotulo}: {valor}" for rotulo, valor in linhas_da_obra(obra, periodo)]
    partes += ["", f"Abrir o painel: {painel_url_base}", ""]
    return "\n".join(partes).replace(ESPACO_FIXO, " ")
