"""Gera os JSON do CRM da demo em dados/crm, coerentes com dados/sales.json e dados/units.json.

Cada contrato do ERP tem uma reserva vendida no CRM com o id do contrato em codigointerno. Contrato
com financiamento tem repasse: na Torre Comercial Sul, entregue, a maioria já teve recurso liberado
e os que o ERP ainda cobra estão atrasados; nas outras duas obras o repasse está em análise ou,
no Parque das Águas, perto das chaves, alguns já assinados. Há reservas canceladas que não viraram
venda, reservas em andamento nas unidades reservadas do ERP e leads por mês, só com campo agregável.
O banco do repasse sai de um sorteio próprio, com a Caixa na maioria, e o BANCO_LENTO demora bem mais
da assinatura à liberação. Nenhum registro traz nome, documento, contato ou renda.
"""

import json
import random
from datetime import date, timedelta
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
PASTA_DADOS = RAIZ / "dados"
PASTA_SAIDA = PASTA_DADOS / "crm"
HOJE = date(2026, 9, 22)

# id do empreendimento no CRM; o elo com o ERP é o codigointerno_empreendimento.
EMPREENDIMENTO_CRM = {101: 11, 102: 12, 103: 13}
CHAVES = {101: date(2027, 6, 30), 102: date(2027, 2, 28), 103: date(2026, 5, 31)}
BANCOS = [("Caixa Econômica Federal", 55), ("Itaú Unibanco", 12), ("Bradesco", 12), ("Santander", 11),
          ("Banco do Brasil", 10)]
BANCO_LENTO = "Santander"
# Com esse deslocamento cada banco tem ao menos dois repasses liberados na Torre, e a média por banco tem base.
DESLOCAMENTO_SEMENTE_BANCO = 35
ORIGENS = [("SITE", "Site"), ("FB", "Facebook"), ("IG", "Instagram"), ("PT", "Portal imobiliário"),
           ("ST", "Stand de vendas"), ("IND", "Indicação")]
MIDIAS = ["Google Ads", "Meta Ads", "Portal", "Placa na obra", "Indicação de cliente"]
MOTIVOS_LEAD = ["Sem retorno", "Preço acima do esperado", "Comprou outro imóvel", "Localização"]
MOTIVOS_RESERVA = ["Desistência", "Prazo vencido", "Troca de unidade"]


def momento(dia, sorteio):
    return f"{dia.isoformat()} {sorteio.randint(8, 19):02d}:{sorteio.randint(0, 59):02d}:00"


def meses_entre(inicio, fim):
    atual = date(inicio.year, inicio.month, 1)
    while atual <= fim:
        yield atual
        atual = date(atual.year + atual.month // 12, atual.month % 12 + 1, 1)


def ler(nome):
    return json.loads((PASTA_DADOS / nome).read_text(encoding="utf-8"))["data"]


def base_reserva(id_reserva, obra, unidade, id_unidade_crm):
    return {
        "idreserva": id_reserva, "referencia": str(id_reserva), "ativo": "S",
        "idempreendimento": EMPREENDIMENTO_CRM[obra], "codigointerno_empreendimento": str(obra),
        "etapa": "Única", "bloco": "Torre A", "unidade": unidade, "idunidade": id_unidade_crm,
    }


def gerar_reservas_de_contratos(contratos, unidades_crm, sorteio):
    reservas, vinculos, historico = [], [], []
    for indice, contrato in enumerate(contratos, 1):
        id_reserva = 30000 + indice
        data_venda = date.fromisoformat(contrato["contractDate"])
        data_cad = data_venda - timedelta(days=sorteio.randint(3, 20))
        unidade = contrato["units"][0]["name"]
        reserva = base_reserva(id_reserva, contrato["enterpriseId"], unidade, unidades_crm[unidade])
        financiado = contrato["financialInstitutionNumber"] is not None
        reserva.update({
            "data_cad": momento(data_cad, sorteio), "codigointerno": str(contrato["id"]),
            "numero_venda": contrato["number"], "aprovada": "Sim", "data_venda": momento(data_venda, sorteio),
            "data_contrato": data_venda.isoformat(), "venda": "Sim", "valor_contrato": contrato["value"],
            "situacao": "Vendida", "idsituacao": 3, "situacao_comercial": "Vendas",
            "tipovenda": "Financiamento" if financiado else "Direta", "idtipovenda": 2 if financiado else 1,
            "midia": sorteio.choice(MIDIAS),
        })
        ultima = data_venda
        historico.append((id_reserva, data_cad + timedelta(days=1), 1, 2, "Em análise", "Aprovada"))
        historico.append((id_reserva, data_venda, 2, 3, "Aprovada", "Vendida"))
        if contrato["situation"] == "3":
            cancelamento = date.fromisoformat(contrato["cancellationDate"])
            reserva.update({"situacao": "Distrato", "idsituacao": 4, "data_cancelamento": cancelamento.isoformat(),
                            "motivo_cancelamento": "Desistência"})
            historico.append((id_reserva, cancelamento, 3, 4, "Vendida", "Distrato"))
            ultima = cancelamento
        reserva["referencia_data"] = momento(ultima, sorteio)
        reserva["data_ultima_alteracao_situacao"] = reserva["referencia_data"]
        reserva["data_modificacao"] = reserva["referencia_data"]
        reservas.append(reserva)
        vinculos.append({
            "idreserva": id_reserva, "referencia": str(id_reserva), "ativo": "S",
            "codigointerno": str(contrato["id"]), "titulo_erp": contrato["number"],
            "data_contrato": data_venda.isoformat(), "data_venda": reserva["data_venda"], "enviado": "Sim",
            "data_envio": reserva["data_venda"], "referencia_data": reserva["data_venda"],
        })
    return reservas, vinculos, historico


def gerar_reservas_sem_venda(contratos, unidades, unidades_crm, sorteio, proximo_id):
    """Reservas canceladas antes da venda e reservas em andamento nas unidades C e P do ERP."""
    reservas, historico = [], []
    disponiveis = {}
    for unidade in unidades:
        if unidade["commercialStock"] == "D":
            disponiveis.setdefault(unidade["enterpriseId"], []).append(unidade["name"])
    for obra in sorted(EMPREENDIMENTO_CRM):
        datas = sorted(date.fromisoformat(c["contractDate"]) for c in contratos if c["enterpriseId"] == obra)
        for _ in range(max(2, len(datas) // 4)):
            data_cad = sorteio.choice(datas) - timedelta(days=sorteio.randint(0, 25))
            cancelamento = min(data_cad + timedelta(days=sorteio.randint(5, 20)), HOJE)
            nome = sorteio.choice(disponiveis.get(obra) or [c["units"][0]["name"] for c in contratos
                                                              if c["enterpriseId"] == obra])
            reserva = base_reserva(proximo_id, obra, nome, unidades_crm[nome])
            reserva.update({
                "data_cad": momento(data_cad, sorteio), "aprovada": "Não", "venda": "Não", "situacao": "Cancelada",
                "idsituacao": 5, "situacao_comercial": "Vendas", "data_cancelamento": cancelamento.isoformat(),
                "motivo_cancelamento": sorteio.choice(MOTIVOS_RESERVA), "midia": sorteio.choice(MIDIAS),
                "referencia_data": momento(cancelamento, sorteio),
            })
            historico.append((proximo_id, cancelamento, 1, 5, "Em análise", "Cancelada"))
            reservas.append(reserva)
            proximo_id += 1
    for unidade in unidades:
        if unidade["commercialStock"] not in ("C", "P"):
            continue
        data_cad = HOJE - timedelta(days=sorteio.randint(1, 20))
        em_analise = unidade["commercialStock"] == "C"
        reserva = base_reserva(proximo_id, unidade["enterpriseId"], unidade["name"], unidades_crm[unidade["name"]])
        reserva.update({
            "data_cad": momento(data_cad, sorteio), "aprovada": "Não", "venda": "Não",
            "situacao": "Em análise" if em_analise else "Aguardando aprovação", "idsituacao": 1 if em_analise else 2,
            "situacao_comercial": "Vendas", "valor_contrato": unidade["saleValuePrice"],
            "midia": sorteio.choice(MIDIAS), "referencia_data": momento(data_cad, sorteio),
        })
        reservas.append(reserva)
        proximo_id += 1
    return reservas, historico


def etapa_repasse(contrato, sorteio):
    """Situação, assinatura e recurso liberado do repasse, coerentes com a parcela FI do ERP."""
    obra = contrato["enterpriseId"]
    chaves = CHAVES[obra]
    if contrato["situation"] == "3":
        return "Cancelado", None, None
    if contrato["financialInstitutionDate"]:
        liberado = date.fromisoformat(contrato["financialInstitutionDate"]) - timedelta(days=sorteio.randint(0, 6))
        return "Recurso liberado", liberado - timedelta(days=sorteio.randint(15, 45)), liberado
    if chaves < HOJE:
        # O ERP ainda cobra a FI depois das chaves: repasse atrasado, parado antes do recurso.
        if sorteio.random() < 0.5:
            return "Contrato assinado", HOJE - timedelta(days=sorteio.randint(30, 90)), None
        return "Análise de crédito", None, None
    if obra == 102 and sorteio.random() < 0.3:
        return "Contrato assinado", HOJE - timedelta(days=sorteio.randint(5, 60)), None
    return sorteio.choices(["Aguardando documentação", "Análise de crédito", "Crédito aprovado"],
                           weights=[4, 4, 2])[0], None, None


def atrasar_assinatura(assinatura, liberado, data_venda, sorteio_banco):
    """No banco lento a assinatura vem bem antes da liberação, sem passar da data da venda."""
    if not (assinatura and liberado):
        return assinatura
    return max(assinatura - timedelta(days=sorteio_banco.randint(45, 75)), min(assinatura, data_venda))


def gerar_repasses(contratos, reservas_por_contrato, sorteio, sorteio_banco):
    repasses, historico = [], []
    nomes_banco = [nome for nome, _ in BANCOS]
    pesos_banco = [peso for _, peso in BANCOS]
    sequencia = ["Aguardando documentação", "Análise de crédito", "Crédito aprovado", "Contrato assinado",
                 "Recurso liberado"]
    for indice, contrato in enumerate(c for c in contratos if c["financialInstitutionNumber"]):
        id_repasse = 70001 + indice
        reserva = reservas_por_contrato[contrato["id"]]
        situacao, assinatura, liberado = etapa_repasse(contrato, sorteio)
        financiado = sum(p["totalValue"] for p in contrato["paymentConditions"] if p["conditionType"] == "FI")
        data_venda = date.fromisoformat(contrato["contractDate"])
        banco = sorteio_banco.choices(nomes_banco, weights=pesos_banco)[0]
        if banco == BANCO_LENTO:
            assinatura = atrasar_assinatura(assinatura, liberado, data_venda, sorteio_banco)
        cadastro = min(data_venda + timedelta(days=sorteio.randint(1, 10)), HOJE)
        if liberado:
            cadastro = min(cadastro, assinatura)
        elif assinatura and assinatura < cadastro:
            assinatura = cadastro
        alteracao = liberado or assinatura or min(cadastro + timedelta(days=sorteio.randint(10, 200)), HOJE)
        if situacao == "Cancelado":
            alteracao = date.fromisoformat(contrato["cancellationDate"])
        instante = momento(alteracao, sorteio)
        repasses.append({
            "idrepasse": id_repasse, "referencia": str(id_repasse), "ativo": "S",
            "idsituacao": sequencia.index(situacao) + 1 if situacao in sequencia else 9, "situacao": situacao,
            "reserva": reserva["idreserva"], "idempreendimento": reserva["idempreendimento"],
            "codigointerno_empreendimento": reserva["codigointerno_empreendimento"], "etapa": reserva["etapa"],
            "bloco": reserva["bloco"], "unidade": reserva["unidade"], "idunidade": reserva["idunidade"],
            "idcontrato": contrato["number"], "numero_contrato": contrato["number"],
            "valor_previsto": round(financiado, 2), "valor_financiado": round(financiado, 2),
            "valor_contrato": contrato["value"], "banco": banco,
            "data_venda": reserva["data_venda"],
            "data_assinatura_de_contrato": assinatura.isoformat() if assinatura else None,
            "data_recurso_liberado": liberado.isoformat() if liberado else None,
            "data_alteracao_status": instante, "data_cadastro": momento(cadastro, sorteio),
            "referencia_data": instante, "data_modificacao": instante,
        })
        anterior, dia = sequencia[0], cadastro
        destino = situacao if situacao in sequencia else None
        for proxima in sequencia[1:sequencia.index(destino) + 1] if destino else []:
            dia = {"Contrato assinado": assinatura, "Recurso liberado": liberado}.get(proxima) or min(
                dia + timedelta(days=sorteio.randint(5, 30)), assinatura or alteracao)
            historico.append((id_repasse, dia, sequencia.index(anterior) + 1, sequencia.index(proxima) + 1,
                              anterior, proxima))
            anterior = proxima
    return repasses, historico


def gerar_leads(contratos, sorteio):
    vendas_por_mes = {}
    for contrato in contratos:
        chave = (contrato["enterpriseId"], contrato["contractDate"][:7])
        vendas_por_mes[chave] = vendas_por_mes.get(chave, 0) + 1
    leads = []
    id_lead = 500001
    for obra in sorted(EMPREENDIMENTO_CRM):
        primeira = min(date.fromisoformat(c["contractDate"]) for c in contratos if c["enterpriseId"] == obra)
        for mes in meses_entre(primeira, HOJE):
            ultimo_dia = HOJE.day if (mes.year, mes.month) == (HOJE.year, HOJE.month) else 28
            quantidade = vendas_por_mes.get((obra, mes.isoformat()[:7]), 0) * 8 + sorteio.randint(3, 12)
            for _ in range(quantidade):
                cadastro = mes.replace(day=sorteio.randint(1, ultimo_dia))
                origem, origem_nome = sorteio.choice(ORIGENS)
                codigos = str(obra)
                if sorteio.random() < 0.08:
                    outra = sorteio.choice([o for o in EMPREENDIMENTO_CRM if o != obra])
                    codigos = f"{obra};{outra}"
                lead = {
                    "idlead": id_lead, "referencia": str(id_lead), "ativo": "S",
                    "data_cad": momento(cadastro, sorteio), "origem": origem, "origem_nome": origem_nome,
                    "midia_original": sorteio.choice(MIDIAS), "idempreendimento": str(EMPREENDIMENTO_CRM[obra]),
                    "codigointerno_empreendimento": codigos,
                }
                ultima = cadastro
                antigo = (HOJE - cadastro).days > 60
                if antigo and sorteio.random() < 0.6:
                    ultima = min(cadastro + timedelta(days=sorteio.randint(7, 45)), HOJE)
                    lead.update({"situacao": "Descartado", "idsituacao": 5, "data_cancelamento": ultima.isoformat(),
                                 "motivo_cancelamento": sorteio.choice(MOTIVOS_LEAD)})
                else:
                    lead.update({"situacao": "Em atendimento", "idsituacao": 2})
                lead["referencia_data"] = momento(ultima, sorteio)
                leads.append(lead)
                id_lead += 1
    return leads


def historico_para_registros(historico, campo_id, id_inicial):
    registros = []
    for deslocamento, (id_pai, dia, de, para, de_nome, para_nome) in enumerate(historico):
        id_historico = id_inicial + deslocamento
        registros.append({
            "idhistorico": id_historico, "referencia": str(id_historico), "ativo": "S", campo_id: id_pai,
            "data_cad": f"{dia.isoformat()} 12:00:00", "de": de, "para": para, "de_nome": de_nome,
            "para_nome": para_nome, "referencia_data": f"{dia.isoformat()} 12:00:00",
        })
    return registros


def salvar(nome, registros):
    # Um registro por linha: o diff do arquivo mostra o que mudou quando o gerador mudar.
    linhas = ",\n".join(json.dumps(r, ensure_ascii=False, sort_keys=True) for r in registros)
    (PASTA_SAIDA / nome).write_text('{"dados": [\n' + linhas + "\n]}\n", encoding="utf-8")
    print(f"crm/{nome}: {len(registros)} registros")


def gerar(contratos, unidades, semente=2026):
    sorteio = random.Random(semente)
    contratos = sorted(contratos, key=lambda c: c["id"])
    unidades_crm = {u["name"]: 800001 + i for i, u in enumerate(sorted(unidades, key=lambda u: u["id"]))}
    reservas, vinculos, historico_reservas = gerar_reservas_de_contratos(contratos, unidades_crm, sorteio)
    reservas_por_contrato = {int(r["codigointerno"]): r for r in reservas}
    extras, historico_extras = gerar_reservas_sem_venda(contratos, unidades, unidades_crm, sorteio,
                                                        30001 + len(reservas))
    # Sorteio separado: o banco não desloca a sequência do resto, e reservas e leads não mudam.
    repasses, historico_repasses = gerar_repasses(contratos, reservas_por_contrato, sorteio,
                                                  random.Random(semente + DESLOCAMENTO_SEMENTE_BANCO))
    return {
        "reservas.json": reservas + extras,
        "reservas_vinculo_erp.json": vinculos,
        "reservas_historico_situacoes.json": historico_para_registros(historico_reservas + historico_extras,
                                                                      "idreserva", 40001),
        "repasses.json": repasses,
        "repasses_historico_situacoes.json": historico_para_registros(historico_repasses, "idrepasse", 90001),
        "leads.json": gerar_leads(contratos, sorteio),
    }


def main():
    PASTA_SAIDA.mkdir(exist_ok=True)
    for nome, registros in gerar(ler("sales.json"), ler("units.json")).items():
        salvar(nome, registros)


if __name__ == "__main__":
    main()
