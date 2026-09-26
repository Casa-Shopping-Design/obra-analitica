"""Gera os JSON da demo no formato dos endpoints do ERP de origem.

Tres obras ficticias, 24 meses de historico (out/2024 a set/2026) e parcelas
projetadas para os 24 meses seguintes. Os nomes de campo seguem a API do
ERP de origem para que o carregador nao mude quando os dados reais entrarem.
"""

import json
import random
from datetime import date, timedelta
from pathlib import Path

random.seed(2026)
# Os casos de eventos financeiros sorteiam numa sequência própria, para não mudar vendas, parcelas e
# títulos que já existiam na demo.
SORTEIO_CASOS = random.Random(2027)

PASTA_SAIDA = Path(__file__).resolve().parent.parent / "dados"
HOJE = date(2026, 9, 22)
INICIO_HISTORICO = date(2024, 10, 1)

EMPRESA = {"id": 1, "name": "Construtora Demo Ltda", "tradeName": "Demo", "cnpj": "12.345.678/0001-90"}

# Cada obra e ao mesmo tempo centro de custo, empreendimento e obra de orcamento.
OBRAS = [
    {
        "id": 101, "name": "Residencial Aurora", "tipologias": {"2Q": 60, "3Q": 60},
        "ticket": {"2Q": 290_000, "3Q": 350_000}, "pct_vendido": 0.70, "pct_obra": 0.60,
        "orcamento": 26_000_000, "vso_faixa": (5, 8), "distratos": 2, "inicio_vendas": date(2024, 10, 1),
        "chaves": date(2027, 6, 30), "entregue": False,
    },
    {
        "id": 102, "name": "Parque das Aguas", "tipologias": {"2Q": 40, "3Q": 40},
        "ticket": {"2Q": 250_000, "3Q": 310_000}, "pct_vendido": 0.35, "pct_obra": 0.80,
        "orcamento": 17_500_000, "vso_faixa": (1, 2), "distratos": 6, "inicio_vendas": date(2024, 11, 1),
        "chaves": date(2027, 2, 28), "entregue": False,
    },
    {
        "id": 103, "name": "Torre Comercial Sul", "tipologias": {"SALA": 40},
        "ticket": {"SALA": 210_000}, "pct_vendido": 0.90, "pct_obra": 1.00,
        "orcamento": 6_200_000, "vso_faixa": (3, 5), "distratos": 0, "inicio_vendas": date(2024, 10, 1),
        "chaves": date(2026, 5, 31), "entregue": True,
    },
]

# Condicao de pagamento no padrao do ERP de origem: sinal, mensal, balao, chaves, financiamento.
CONDICOES = ["AT", "PM", "BA", "CH", "FI"]

NOMES = ["Ana", "Bruno", "Carla", "Diego", "Elisa", "Fabio", "Gisele", "Heitor", "Iara", "Julio",
         "Karen", "Leandro", "Marta", "Nuno", "Olivia", "Paulo", "Renata", "Sergio", "Tania", "Vitor"]
SOBRENOMES = ["Silva", "Souza", "Costa", "Oliveira", "Pereira", "Lima", "Gomes", "Ribeiro", "Martins", "Rocha"]


def meses_entre(inicio, fim):
    atual = date(inicio.year, inicio.month, 1)
    while atual <= fim:
        yield atual
        atual = date(atual.year + (atual.month // 12), atual.month % 12 + 1, 1)


def somar_meses(d, n):
    mes = d.month - 1 + n
    return date(d.year + mes // 12, mes % 12 + 1, min(d.day, 28))


def nome_cliente():
    return f"{random.choice(NOMES)} {random.choice(SOBRENOMES)} {random.choice(SOBRENOMES)}"


def gerar_unidades(obra):
    unidades = []
    seq = 1
    for tipologia, qtd in obra["tipologias"].items():
        for i in range(qtd):
            andar = i // 4 + 1
            area = {"2Q": 58, "3Q": 74, "SALA": 38}[tipologia] + random.randint(-3, 3)
            valor = obra["ticket"][tipologia] * (1 + random.uniform(-0.15, 0.15)) * (1 + 0.004 * andar)
            unidades.append({
                "id": obra["id"] * 1000 + seq,
                "enterpriseId": obra["id"],
                "name": f"{tipologia}-{andar:02d}{(i % 4) + 1:02d}",
                "propertyType": tipologia,
                "privateArea": area,
                "commercialStock": "D",
                "deliveryDate": obra["chaves"].isoformat(),
                "valorTabela": round(valor, 2),
            })
            seq += 1
    return unidades


def gerar_vendas(obra, unidades):
    """Distribui as vendas do inicio das vendas ate hoje respeitando o ritmo da obra.

    Sorteia um peso por mes dentro da faixa de VSO e escala para fechar no alvo.
    Sem isso o alvo era batido cedo e os ultimos meses ficavam com VSO zero.
    """
    alvo = int(len(unidades) * obra["pct_vendido"])
    disponiveis = unidades[:]
    random.shuffle(disponiveis)
    meses = list(meses_entre(obra["inicio_vendas"], HOJE))
    pesos = []
    for mes in meses:
        baixo, alto = obra["vso_faixa"]
        # Parque das Aguas vende bem no comeco e desacelera.
        if obra["id"] == 102 and mes < date(2025, 6, 1):
            baixo, alto = 5, 7
        pesos.append(random.randint(baixo, alto))
    total_pesos = sum(pesos)
    # arredondamento acumulado: a soma fecha exata no alvo, O(meses)
    quantidades, acumulado, anterior = [], 0.0, 0
    for peso in pesos:
        acumulado += peso * alvo / total_pesos
        quantidades.append(round(acumulado) - anterior)
        anterior = round(acumulado)

    contratos = []
    contador = 1
    for mes, qtd in zip(meses, quantidades):
        for _ in range(min(qtd, len(disponiveis))):
            unidade = disponiveis.pop()
            unidade["commercialStock"] = "V"
            dias_no_mes = 27 if mes.month != HOJE.month or mes.year != HOJE.year else HOJE.day - 1
            data_venda = mes + timedelta(days=random.randint(0, dias_no_mes))
            investidor = random.random() < 0.15
            contratos.append(montar_contrato(obra, unidade, data_venda, contador, investidor))
            contador += 1

    # parte do estoque sai de venda: C reservada, P proposta em analise, R reserva tecnica
    reservadas = max(1, len(disponiveis) // 15)
    for unidade in disponiveis[:reservadas]:
        unidade["commercialStock"] = "C"
    if len(disponiveis) >= 20:
        for unidade in disponiveis[reservadas:reservadas + 2]:
            unidade["commercialStock"] = "P"
        disponiveis[reservadas + 2]["commercialStock"] = "R"
    aplicar_distratos(obra, contratos)
    return contratos


def montar_contrato(obra, unidade, data_venda, seq, investidor):
    valor = unidade["valorTabela"]
    if investidor:
        condicoes = [("AT", 0.20, 1), ("PM", 0.80, 36)]
    else:
        condicoes = [("AT", 0.10, 1), ("PM", 0.20, 24), ("BA", 0.10, 2), ("FI", 0.60, 1)]
    ja_repassou = (not investidor) and obra["entregue"] and random.random() < 0.85
    if obra["id"] == 102 and not investidor:
        ja_repassou = False
    return {
        "id": obra["id"] * 10000 + seq,
        "enterpriseId": obra["id"],
        "number": f"{obra['id']}-{seq:04d}",
        "contractDate": data_venda.isoformat(),
        "situation": "1",
        "cancellationDate": None,
        "value": valor,
        "totalSellingValue": valor,
        "financialInstitutionNumber": None if investidor else "104",
        "financialInstitutionDate": obra["chaves"].isoformat() if ja_repassou else None,
        "associativeCredit": "N",
        "customers": [{"id": 5000 + seq, "main": True, "name": nome_cliente()}],
        "units": [{"id": unidade["id"], "main": True, "name": unidade["name"], "propertyType": unidade["propertyType"]}],
        "paymentConditions": [
            {"conditionType": tipo, "totalValue": round(valor * pct, 2), "installmentsNumber": n}
            for tipo, pct, n in condicoes
        ],
    }


def aplicar_distratos(obra, contratos):
    candidatos = [c for c in contratos if date.fromisoformat(c["contractDate"]) < somar_meses(HOJE, -3)]
    for contrato in random.sample(candidatos, min(obra["distratos"], len(candidatos))):
        contrato["situation"] = "3"
        cancelamento = date.fromisoformat(contrato["contractDate"]) + timedelta(days=random.randint(120, 400))
        contrato["cancellationDate"] = min(cancelamento, HOJE).isoformat()


def gerar_parcelas(obra, contratos, unidades_por_id):
    """Uma linha por parcela, no formato do bulk income."""
    parcelas = []
    seq = 1
    for contrato in contratos:
        cancelado = contrato["situation"] == "3"
        data_cancel = date.fromisoformat(contrato["cancellationDate"]) if cancelado else None
        inicio = date.fromisoformat(contrato["contractDate"])
        for cond in contrato["paymentConditions"]:
            n = cond["installmentsNumber"]
            valor_parcela = cond["totalValue"] / n
            for i in range(n):
                if cond["conditionType"] == "AT":
                    vencimento = inicio
                elif cond["conditionType"] == "BA":
                    vencimento = somar_meses(inicio, 6 * (i + 1))
                elif cond["conditionType"] in ("FI", "CH"):
                    vencimento = obra["chaves"]
                else:
                    vencimento = somar_meses(inicio, i + 1)
                if cancelado and vencimento > data_cancel:
                    continue
                meses_corridos = max(0, (vencimento.year - inicio.year) * 12 + vencimento.month - inicio.month)
                corrigido = valor_parcela * ((1.004 ** meses_corridos) if cond["conditionType"] in ("PM", "BA") else 1)
                recebida = vencimento <= HOJE
                inadimplente = False
                if recebida and cond["conditionType"] == "PM":
                    chance = 0.15 if obra["entregue"] else 0.06
                    if vencimento > somar_meses(HOJE, -6):
                        chance *= 1.6
                    inadimplente = random.random() < chance
                if cond["conditionType"] == "FI":
                    recebida = contrato["financialInstitutionDate"] is not None
                saldo = 0 if (recebida and not inadimplente) else corrigido
                parcelas.append({
                    "companyId": EMPRESA["id"],
                    "projectId": obra["id"],
                    "projectName": obra["name"],
                    "clientId": contrato["customers"][0]["id"],
                    "clientName": contrato["customers"][0]["name"],
                    "billId": contrato["id"],
                    "installmentId": seq,
                    "installmentNumber": f"{i + 1}/{n}",
                    "dueDate": vencimento.isoformat(),
                    "issueDate": inicio.isoformat(),
                    "originalAmount": round(valor_parcela, 2),
                    "balanceAmount": round(saldo, 2),
                    "correctedBalanceAmount": round(saldo, 2),
                    "indexerName": "INCC" if cond["conditionType"] in ("PM", "BA") else None,
                    "defaulterSituation": "S" if inadimplente else "N",
                    "mainUnit": contrato["units"][0]["name"],
                    "paymentTerm": {"id": cond["conditionType"]},
                    "receiptsCategories": categorias(CONTA_VENDA),
                    "receipts": [] if saldo else [{"paymentDate": vencimento.isoformat(), "amount": round(corrigido, 2)}],
                })
                seq += 1
    return parcelas


def gerar_orcamento(obra):
    grupos = ["Fundacoes", "Estrutura", "Alvenaria", "Instalacoes", "Revestimentos", "Esquadrias",
              "Cobertura", "Pintura", "Acabamentos", "Areas comuns"]
    itens = []
    # em centavos inteiros, para a soma dos itens fechar exatamente no orcamento da obra
    restante_centavos = obra["orcamento"] * 100
    for g, grupo in enumerate(grupos):
        n_itens = 4
        for i in range(n_itens):
            ultimo = g == len(grupos) - 1 and i == n_itens - 1
            valor_centavos = restante_centavos if ultimo else round(obra["orcamento"] * 100 / 40 * random.uniform(0.6, 1.4))
            restante_centavos -= valor_centavos
            valor = valor_centavos / 100
            posicao = (g * n_itens + i) / (len(grupos) * n_itens)
            pct = 100 if posicao < obra["pct_obra"] - 0.1 else (0 if posicao > obra["pct_obra"] + 0.1 else random.randint(20, 80))
            itens.append({
                "buildingId": obra["id"],
                "buildingName": obra["name"],
                "wbsCode": f"{g + 1:02d}.{i + 1:02d}",
                "description": f"{grupo} - item {i + 1}",
                "unitOfMeasure": "vb",
                "quantity": 1,
                "unitPrice": valor,
                "totalPrice": valor,
                "percentComplete": pct,
                "measuredQuantity": round(pct / 100, 2),
            })
    return itens


def gerar_desembolso(obra, itens):
    """Titulos a pagar numa curva em S coerente com o avanco fisico."""
    titulos = []
    meses = list(meses_entre(INICIO_HISTORICO, somar_meses(obra["chaves"], 0)))
    total = sum(i["totalPrice"] for i in itens)
    fator = 1.06 if obra["id"] == 102 else 1.0
    seq = 1
    for k, mes in enumerate(meses):
        x = (k + 1) / len(meses)
        peso = (3 * x ** 2 - 2 * x ** 3) - (3 * ((k) / len(meses)) ** 2 - 2 * ((k) / len(meses)) ** 3)
        valor_mes = total * peso * fator
        for _ in range(random.randint(4, 8)):
            valor = valor_mes / 6 * random.uniform(0.7, 1.3)
            vencimento = mes + timedelta(days=random.randint(1, 27))
            pago = vencimento <= HOJE
            titulos.append({
                "companyId": EMPRESA["id"],
                "creditorName": random.choice(["Cimento Norte", "Aco Forte", "Eletrica SA", "Ceramica Sul",
                                               "Mao de obra Silva", "Vidros Lux", "Hidraulica Total"]),
                "billId": obra["id"] * 100000 + seq,
                "dueDate": vencimento.isoformat(),
                "originalAmount": round(valor, 2),
                "balanceAmount": 0 if pago else round(valor, 2),
                "buildingsCosts": [{"buildingId": obra["id"], "amount": round(valor, 2)}],
                "payments": [{"paymentDate": vencimento.isoformat(), "amount": round(valor, 2)}] if pago else [],
            })
            seq += 1
    return titulos


# Códigos sintéticos de conta (docs/financeiro/contrato_dados.md, seção 5.2). 2.99.001 fica sem mapeamento.
CONTA_VENDA = "1.01.001"
CONTAS_OBRA = [("2.01.001", 40), ("2.01.002", 25), ("2.01.003", 25), ("2.01.004", 6), ("2.02.001", 2),
               ("2.03.001", 1), ("2.05.001", 1)]
CONTA_ADMINISTRATIVA = "2.04.001"
CONTA_DEVOLUCAO = "2.09.001"
CONTA_SEM_MAPEAMENTO = "2.99.001"


def categorias(conta):
    return [{"financialCategoryId": conta, "financialCategoryRate": 100}]


def dividir_recebimentos(parcelas):
    """Recebe em duas vezes (40% e 60%) uma em cada dez parcelas mensais já quitadas."""
    for parcela in parcelas:
        if parcela["paymentTerm"]["id"] != "PM" or len(parcela["receipts"]) != 1:
            continue
        if SORTEIO_CASOS.random() >= 0.10:
            continue
        unico = parcela["receipts"][0]
        vencimento = date.fromisoformat(unico["paymentDate"])
        primeira = round(unico["amount"] * 0.4, 2)
        segunda_data = min(vencimento + timedelta(days=SORTEIO_CASOS.randint(20, 45)), HOJE)
        parcela["receipts"] = [
            {"paymentDate": vencimento.isoformat(), "amount": primeira},
            {"paymentDate": segunda_data.isoformat(), "amount": round(unico["amount"] - primeira, 2)},
        ]


def estornar_recebimento(parcelas):
    """Um recebimento seguido do estorno de mesmo valor: a parcela volta a ficar em aberto."""
    candidatas = [p for p in parcelas if p["paymentTerm"]["id"] == "PM" and len(p["receipts"]) == 1
                  and date.fromisoformat(p["dueDate"]) < somar_meses(HOJE, -2)]
    parcela = SORTEIO_CASOS.choice(candidatas)
    recebido = parcela["receipts"][0]
    data_estorno = date.fromisoformat(recebido["paymentDate"]) + timedelta(days=10)
    parcela["receipts"].append({"paymentDate": data_estorno.isoformat(), "amount": -recebido["amount"]})
    parcela["balanceAmount"] = recebido["amount"]
    parcela["correctedBalanceAmount"] = recebido["amount"]


def renegociar(obra, parcelas, contratos):
    """Parcela vencida de contrato ativo zerada sem recebimento e trocada por duas novas no mesmo contrato."""
    ativos = {c["id"] for c in contratos if c["situation"] == "1"}
    candidatas = [p for p in parcelas if p["projectId"] == obra["id"] and p["billId"] in ativos
                  and p["paymentTerm"]["id"] == "PM" and p["balanceAmount"] > 0
                  and not p["receipts"] and date.fromisoformat(p["dueDate"]) < HOJE]
    if not candidatas:
        return []
    original = SORTEIO_CASOS.choice(candidatas)
    saldo = original["correctedBalanceAmount"]
    original["balanceAmount"] = 0
    original["correctedBalanceAmount"] = 0
    original["defaulterSituation"] = "N"
    original["receipts"] = []
    proximo_id = max(p["installmentId"] for p in parcelas) + 1
    primeira = round(saldo / 2, 2)
    novas = []
    for ordem, valor in enumerate([primeira, round(saldo - primeira, 2)]):
        novas.append({**original, "installmentId": proximo_id + ordem, "installmentNumber": f"{ordem + 1}/2",
                      "dueDate": somar_meses(HOJE, ordem + 1).isoformat(), "issueDate": HOJE.isoformat(),
                      "originalAmount": valor, "balanceAmount": valor, "correctedBalanceAmount": valor,
                      "receipts": []})
    return novas


def completar_titulos(titulos, ids_obras):
    """Emissão, conta, pagamento em duas vezes e rateio entre duas obras nos títulos de obra."""
    for titulo in titulos:
        vencimento = date.fromisoformat(titulo["dueDate"])
        titulo["issueDate"] = (vencimento - timedelta(days=SORTEIO_CASOS.randint(5, 40))).isoformat()
        conta = SORTEIO_CASOS.choices([c for c, _ in CONTAS_OBRA], weights=[p for _, p in CONTAS_OBRA])[0]
        if SORTEIO_CASOS.random() < 0.01:
            conta = CONTA_SEM_MAPEAMENTO
        titulo["paymentsCategories"] = categorias(conta)
        if titulo["payments"] and SORTEIO_CASOS.random() < 0.05:
            valor = titulo["originalAmount"]
            primeira = round(valor / 2, 2)
            segunda_data = vencimento + timedelta(days=SORTEIO_CASOS.randint(10, 30))
            titulo["payments"] = [{"paymentDate": vencimento.isoformat(), "amount": primeira}]
            if segunda_data <= HOJE:
                titulo["payments"].append({"paymentDate": segunda_data.isoformat(), "amount": round(valor - primeira, 2)})
            else:
                titulo["balanceAmount"] = round(valor - primeira, 2)
        if SORTEIO_CASOS.random() < 0.05:
            valor = titulo["originalAmount"]
            obra = titulo["buildingsCosts"][0]["buildingId"]
            outra = SORTEIO_CASOS.choice([i for i in ids_obras if i != obra])
            titulo["buildingsCosts"] = [{"buildingId": obra, "amount": round(valor * 0.6, 2)},
                                        {"buildingId": outra, "amount": round(valor - round(valor * 0.6, 2), 2)}]


def pagar_em_parte(titulos):
    """Um título vencido há pouco com metade paga e metade em aberto."""
    candidatos = [t for t in titulos if len(t["payments"]) == 1
                  and somar_meses(HOJE, -2) <= date.fromisoformat(t["dueDate"]) <= HOJE]
    titulo = SORTEIO_CASOS.choice(candidatos)
    metade = round(titulo["originalAmount"] / 2, 2)
    titulo["payments"][0]["amount"] = metade
    titulo["balanceAmount"] = round(titulo["originalAmount"] - metade, 2)


def titulo_empresa(bill_id, vencimento, valor, conta, credor):
    pago = vencimento <= HOJE
    return {
        "companyId": EMPRESA["id"],
        "creditorName": credor,
        "billId": bill_id,
        "dueDate": vencimento.isoformat(),
        "issueDate": (vencimento - timedelta(days=SORTEIO_CASOS.randint(5, 40))).isoformat(),
        "originalAmount": valor,
        "balanceAmount": 0 if pago else valor,
        "paymentsCategories": categorias(conta),
        "payments": [{"paymentDate": vencimento.isoformat(), "amount": valor}] if pago else [],
    }


def gerar_titulos_sem_obra(obras, contratos, parcelas):
    """Dois títulos administrativos por obra e uma devolução por contrato distratado, todos sem rateio."""
    titulos = []
    seq = 1
    for _ in obras:
        for _ in range(2):
            vencimento = INICIO_HISTORICO + timedelta(days=SORTEIO_CASOS.randint(0, (HOJE - INICIO_HISTORICO).days + 60))
            valor = round(SORTEIO_CASOS.uniform(3_000, 15_000), 2)
            titulos.append(titulo_empresa(900_000 + seq, vencimento, valor, CONTA_ADMINISTRATIVA, "Escritorio Contabil"))
            seq += 1
    recebido_por_contrato = {}
    for parcela in parcelas:
        recebido_por_contrato[parcela["billId"]] = (recebido_por_contrato.get(parcela["billId"], 0)
                                                    + sum(r["amount"] for r in parcela["receipts"]))
    for contrato in contratos:
        if contrato["situation"] != "3":
            continue
        # devolve 90% do que o comprador pagou; o resto fica como multa retida
        valor = round(recebido_por_contrato.get(contrato["id"], 0) * 0.9, 2)
        if valor <= 0:
            continue
        vencimento = date.fromisoformat(contrato["cancellationDate"]) + timedelta(days=30)
        titulos.append(titulo_empresa(950_000 + seq, vencimento, valor, CONTA_DEVOLUCAO, "Devolucao a comprador"))
        seq += 1
    return titulos


INDEXADOR = {"id": 7, "name": "INCC"}


def gerar_indice():
    """Serie mensal ficticia no formato de /indexers.

    A API so devolve o ultimo valor, entao em producao cada carga noturna guarda
    um registro e a serie se forma com o tempo. Aqui ela ja vem inteira.
    """
    sorteio = random.Random(77)  # separado para nao alterar os outros dados sorteados
    valor = 1000.0
    serie = []
    for mes in meses_entre(INICIO_HISTORICO, HOJE):
        variacao = round(sorteio.uniform(0.25, 0.65), 2) if serie else 0.0
        valor = round(valor * (1 + variacao / 100), 4)
        serie.append({**INDEXADOR, "lastValue": {"date": mes.isoformat(), "value": valor, "percentage": variacao}})
    return serie


def gerar_tabela_preco(obra, unidades, indice):
    """Tabela vigente no formato de /price-tables, com preco em quantidade indexada.

    O valor em reais de cada unidade e quantidade x indice do mes, por isso muda
    todo mes ate a venda. Depois da venda vale o valor do contrato.
    """
    indice_base = indice[0]["lastValue"]
    indice_atual = indice[-1]["lastValue"]
    tabela_id = obra["id"] * 10
    itens = []
    for u in unidades:
        quantidade = round(u["valorTabela"] / indice_base["value"], 4)
        itens.append({"id": u["id"], "indexedQuantity": quantidade})
        u["indexerId"] = INDEXADOR["id"]
        u["tablePricesID"] = tabela_id
        u["saleValuePrice"] = round(quantidade * indice_atual["value"], 2)
        u["saleValueDate"] = indice_atual["date"]
    condicoes = [
        {"order": ordem, "paymentConditionType": tipo, "installmentsNumber": parcelas, "unitValuePercentage": pct,
         "indexer": {"id": INDEXADOR["id"]}, "baseDate": indice_base["date"]}
        for ordem, (tipo, pct, parcelas) in enumerate([("AT", 10, 1), ("PM", 20, 24), ("BA", 10, 2), ("FI", 60, 1)], 1)
    ]
    return {
        "id": tabela_id, "version": len(indice), "companyId": EMPRESA["id"], "enterpriseId": obra["id"],
        "tableName": f"Tabela {obra['name']}", "tableVersionName": HOJE.strftime("%m/%Y"),
        "startOfTerm": date(HOJE.year, HOJE.month, 1).isoformat(), "endOfTerm": None,
        "paymentConditions": condicoes, "units": itens,
    }


def salvar(nome, conteudo):
    caminho = PASTA_SAIDA / nome
    caminho.write_text(json.dumps({"data": conteudo}, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"{nome}: {len(conteudo)} registros")


def main():
    PASTA_SAIDA.mkdir(exist_ok=True)
    salvar("companies.json", [EMPRESA])
    salvar("cost-centers.json", [{"id": o["id"], "name": o["name"], "idCompany": EMPRESA["id"]} for o in OBRAS])
    salvar("enterprises.json", [{"id": o["id"], "name": o["name"], "commercialName": o["name"],
                                 "companyId": EMPRESA["id"], "type": "1"} for o in OBRAS])

    indice = gerar_indice()
    todas_unidades, todas_vendas, todas_parcelas, todo_orcamento, todo_desembolso = [], [], [], [], []
    tabelas = []
    for obra in OBRAS:
        unidades = gerar_unidades(obra)
        vendas = gerar_vendas(obra, unidades)
        for contrato in vendas:
            if contrato["situation"] == "3":
                for u in unidades:
                    if u["id"] == contrato["units"][0]["id"]:
                        u["commercialStock"] = "D"
        parcelas = gerar_parcelas(obra, vendas, {u["id"]: u for u in unidades})
        orcamento = gerar_orcamento(obra)
        desembolso = gerar_desembolso(obra, orcamento)
        tabelas.append(gerar_tabela_preco(obra, unidades, indice))
        for u in unidades:
            u.pop("valorTabela", None)
        todas_unidades += unidades
        todas_vendas += vendas
        todas_parcelas += parcelas
        todo_orcamento += orcamento
        todo_desembolso += desembolso
        print(f"{obra['name']}: {len(vendas)} contratos, {sum(1 for c in vendas if c['situation'] == '3')} distratos")

    ids_obras = [o["id"] for o in OBRAS]
    dividir_recebimentos(todas_parcelas)
    estornar_recebimento(todas_parcelas)
    for obra in OBRAS:
        todas_parcelas += renegociar(obra, todas_parcelas, todas_vendas)
    completar_titulos(todo_desembolso, ids_obras)
    pagar_em_parte(todo_desembolso)
    todo_desembolso += gerar_titulos_sem_obra(OBRAS, todas_vendas, todas_parcelas)

    salvar("units.json", todas_unidades)
    salvar("sales.json", todas_vendas)
    salvar("income.json", todas_parcelas)
    salvar("outcome.json", todo_desembolso)
    salvar("building-cost-estimation-items.json", todo_orcamento)
    salvar("indexers.json", indice)
    salvar("price-tables.json", tabelas)


if __name__ == "__main__":
    main()
