"""Gera os JSON das rotas complementares do ERP em dados/complementos, coerentes com a demo.

Parte de dados/cost-centers.json, sales.json, units.json, income.json e building-cost-estimation-items.json:
- mapa imobiliário mensal por obra, com o custo incorrido na mesma curva em S do a pagar da demo
  (o Parque das Águas estoura o orçado em 6%) e o recebido pelo cronograma das condições de pagamento;
- medição física mensal por obra, uma tarefa por grupo do orçamento, chegando ao percentual concluído
  do orçamento; o Residencial Aurora mede no ritmo do custo incorrido e a última medição dele ainda está
  em aprovação, de modo que só o Parque das Águas aparece com o pago à frente do físico;
- inadimplência por faixa de atraso tirada das parcelas vencidas e em aberto de income.json, de modo que o
  total por obra bate com o vencido do comprador da posição financeira. O financiamento (FI) fica de fora,
  porque o painel o mostra à parte, como repasse atrasado;
- saldo contábil mensal por obra das contas de terreno, projetos, licenciamento, garantia, juros e
  despesas, sem sorteio: o valor do estudo em dados/viabilidade/estudos.json vezes um fator por obra e
  a fração do mês (parcelas fixas, POC do mapa, VGV vendido ou prazo decorrido até as chaves).

Nenhum registro traz nome, documento ou contato de cliente. Mesmos nomes de campo da API, para que
o staging leia a demo e a carga real do mesmo jeito.
"""

import json
from collections import defaultdict
from datetime import date, timedelta
from decimal import ROUND_HALF_UP, Decimal
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
PASTA_DADOS = RAIZ / "dados"
PASTA_SAIDA = PASTA_DADOS / "complementos"
HOJE = date(2026, 9, 22)
INICIO_OBRA = date(2024, 10, 1)

# Mesmas datas de chaves e o mesmo estouro de custo de scripts/gerar_dados_demo.py.
CHAVES = {101: date(2027, 6, 30), 102: date(2027, 2, 28), 103: date(2026, 5, 31)}
FATOR_CUSTO = {102: 1.06}
# O orçamento da Aurora saiu do sorteio com 55% concluído, atrás do custo que a curva da demo já incorreu, e
# mudar o avanço dele em gerar_dados_demo.py reembaralha as outras obras. A medição dela segue o custo.
MEDE_NO_RITMO_DO_CUSTO = {101}
ARQUIVOS = {
    "real-estate-map": "real-estate-map.json",
    "building-projects/progress-logs/items": "building-projects-progress-logs-items.json",
    "defaulters-receivable-bills/by-aging": "defaulters-receivable-bills-by-aging.json",
    "accountancy/accountCostCenterBalance": "accountancy-accountCostCenterBalance.json",
}
ARQUIVO_ESTUDOS = PASTA_DADOS / "viabilidade" / "estudos.json"

# Plano de contas fictício da demo, todas de natureza devedora, porque a DRE soma o saldo com sinal
# (devedor positivo). A garantia usa a conta de custo, não a provisão do passivo, que é credora.
# carregar_demo.py grava este mesmo mapa em app.conta_linha_resultado.
CONTAS_DEMO = {
    "1.1.05.01": "custo_terreno",
    "1.1.05.02": "custo_projetos",
    "1.1.05.03": "custo_licenciamento",
    "3.1.02.01": "assistencia_tecnica",
    "4.2.01.01": "juros_financiamento",
    "4.1.01.01": "despesas_comerciais",
    "4.1.02.01": "despesas_administrativas",
}
# Desvios da demo: a Aurora gastou mais em projetos; o Parque das Águas, em terreno, projetos e juros.
# Obra fora do dicionário fica no valor do estudo.
FATOR_CONTA = {
    "custo_terreno": {102: Decimal("1.02")},
    "custo_projetos": {101: Decimal("1.10"), 102: Decimal("1.25")},
    "juros_financiamento": {102: Decimal("1.15")},
}
MESES_PROJETOS = 6
MES_INICIO_LICENCIAMENTO, MES_FIM_LICENCIAMENTO = 3, 9
CENTAVO = Decimal("0.01")


def ler(nome):
    return json.loads((PASTA_DADOS / nome).read_text(encoding="utf-8"))["data"]


def ler_estudos(caminho=ARQUIVO_ESTUDOS):
    return json.loads(caminho.read_text(encoding="utf-8"))


def meses_entre(inicio, fim):
    atual = date(inicio.year, inicio.month, 1)
    while atual <= fim:
        yield atual
        atual = date(atual.year + atual.month // 12, atual.month % 12 + 1, 1)


def fim_do_mes(mes):
    return date(mes.year + mes.month // 12, mes.month % 12 + 1, 1) - timedelta(days=1)


def somar_meses(dia, n):
    mes = dia.month - 1 + n
    return date(dia.year + mes // 12, mes % 12 + 1, min(dia.day, 28))


def curva_s(x):
    return 3 * x ** 2 - 2 * x ** 3


def dinheiro(valor):
    return round(valor, 2)


def ativo_em(contrato, dia):
    if date.fromisoformat(contrato["contractDate"]) > dia:
        return False
    cancelamento = contrato.get("cancellationDate")
    return contrato["situation"] == "1" or (cancelamento is not None and date.fromisoformat(cancelamento) > dia)


def custo_incorrido_ate(obra, orcado, mes):
    """Mesma curva do gerar_desembolso da demo: o custo do mês k é o salto da curva entre k e k+1."""
    meses = list(meses_entre(INICIO_OBRA, CHAVES[obra]))
    k = sum(1 for m in meses if m <= mes)
    return orcado * FATOR_CUSTO.get(obra, 1.0) * curva_s(k / len(meses))


def carteira_da_obra(id_obra, contratos, unidades):
    """Contratos e unidades da obra; reserva técnica não entra no VGV."""
    contratos_obra = [c for c in contratos if c["enterpriseId"] == id_obra]
    unidades_obra = [u for u in unidades if u["enterpriseId"] == id_obra and u["commercialStock"] != "R"]
    return contratos_obra, unidades_obra


def vendido_e_estoque(contratos_obra, unidades_obra, dia):
    ativos = [c for c in contratos_obra if ativo_em(c, dia)]
    vendidas = {c["units"][0]["id"] for c in ativos}
    vgv_vendido = sum(c["value"] for c in ativos)
    estoque = sum(u.get("saleValuePrice") or 0 for u in unidades_obra if u["id"] not in vendidas)
    return vgv_vendido, estoque


def vencimentos(contrato, chaves):
    """Cronograma de cada condição, com o valor da parcela; FI só entra com o repasse feito."""
    inicio = date.fromisoformat(contrato["contractDate"])
    for condicao in contrato["paymentConditions"]:
        n = condicao["installmentsNumber"]
        valor = condicao["totalValue"] / n
        for i in range(n):
            tipo = condicao["conditionType"]
            if tipo == "AT":
                yield inicio, valor
            elif tipo == "BA":
                yield somar_meses(inicio, 6 * (i + 1)), valor
            elif tipo == "CH":
                yield chaves, valor
            elif tipo == "FI":
                if contrato.get("financialInstitutionDate"):
                    yield date.fromisoformat(contrato["financialInstitutionDate"]), valor
            else:
                yield somar_meses(inicio, i + 1), valor


# O(o x m x (c + u)) com o obras, m meses, c contratos e u unidades por obra: algumas dezenas de milhares
# de passos na demo, sem necessidade de índice.
def gerar_mapa(obras, contratos, unidades, itens):
    registros = []
    for obra in obras:
        id_obra = obra["id"]
        orcado = dinheiro(sum(i["totalPrice"] for i in itens if i["buildingId"] == id_obra))
        contratos_obra, unidades_obra = carteira_da_obra(id_obra, contratos, unidades)
        recebiveis = []
        for contrato in contratos_obra:
            cancelamento = contrato.get("cancellationDate")
            limite = date.fromisoformat(cancelamento) if cancelamento else None
            recebiveis += [(dia, valor) for dia, valor in vencimentos(contrato, CHAVES[id_obra])
                           if dia <= HOJE and (limite is None or dia <= limite)]
        incorrido_anterior, recebido_anterior = 0.0, 0.0
        for mes in meses_entre(INICIO_OBRA, HOJE):
            fim = min(fim_do_mes(mes), HOJE)
            vgv_vendido, estoque = vendido_e_estoque(contratos_obra, unidades_obra, fim)
            incorrido = custo_incorrido_ate(id_obra, orcado, mes)
            recebido = sum(valor for dia, valor in recebiveis if dia <= fim)
            poc = min(incorrido / orcado, 1.0) if orcado else 0.0
            receita = vgv_vendido * poc
            vgv = vgv_vendido + estoque
            custo_apropriado = incorrido * (vgv_vendido / vgv) if vgv else 0.0
            lucro = receita - custo_apropriado
            registros.append({
                "enterpriseData": {"companyId": obra["idCompany"], "enterpriseId": id_obra,
                                   "units": len(unidades_obra), "monthYear": f"{mes.month:02d}/{mes.year}"},
                "vgvData": {"vgv": dinheiro(vgv), "poc": round(poc * 100, 2)},
                "accumulatedReceipts": {"accumulatedReceipt": dinheiro(recebido),
                                        "monthlyReceipt": dinheiro(recebido - recebido_anterior),
                                        "receivingDistractedUnit": 0.0},
                "budgetedAndIncurredCost": {"budgetedCost": orcado,
                                            "accumulatedIncurredCost": dinheiro(incorrido),
                                            "costToIncur": dinheiro(max(orcado - incorrido, 0)),
                                            "monthlyIncurredCost": dinheiro(incorrido - incorrido_anterior)},
                "margin": {"accumulatedRevenue": dinheiro(receita), "accruedCost": dinheiro(custo_apropriado),
                           "grossProfit": dinheiro(lucro), "(%)": round(lucro / receita, 4) if receita else 0.0},
            })
            incorrido_anterior, recebido_anterior = incorrido, recebido
    return registros


def tarefas_da_obra(id_obra, itens):
    """Uma tarefa por grupo do orçamento (prefixo do wbsCode); percentual final ponderado pelo valor."""
    grupos = {}
    for item in itens:
        if item["buildingId"] != id_obra:
            continue
        codigo = item["wbsCode"].split(".")[0]
        nome = item["description"].split(" - ")[0]
        grupo = grupos.setdefault(codigo, {"descricao": nome, "valor": 0.0, "medido": 0.0})
        grupo["valor"] += item["totalPrice"]
        grupo["medido"] += item["totalPrice"] * item["percentComplete"] / 100
    return [{"taskId": int(codigo), "description": g["descricao"], "valor": dinheiro(g["valor"]),
             "final": g["medido"] / g["valor"] if g["valor"] else 0.0}
            for codigo, g in sorted(grupos.items())]


def concluir_em_ordem(tarefas, avanco):
    """Acumulado de cada tarefa quando a obra conclui as tarefas na ordem do orçamento até o avanço dado."""
    restante = avanco * sum(t["valor"] for t in tarefas)
    acumulados = []
    for tarefa in tarefas:
        acumulados.append(min(max(restante / tarefa["valor"], 0.0), 1.0) if tarefa["valor"] else 0.0)
        restante -= tarefa["valor"]
    return acumulados


# O(o x m x t): uma linha por obra, medição mensal e tarefa, mais o agrupador da obra; custo_incorrido_ate
# conta os meses da obra, O(m), o que leva a Aurora a O(m² + m x t), ainda poucas centenas de passos.
def gerar_medicoes(obras, itens):
    registros = []
    for obra in obras:
        id_obra = obra["id"]
        tarefas = tarefas_da_obra(id_obra, itens)
        orcado = sum(t["valor"] for t in tarefas)
        ultimo_mes = min(HOJE, CHAVES[id_obra])
        meses = list(meses_entre(INICIO_OBRA, ultimo_mes))
        anterior = {t["taskId"]: 0.0 for t in tarefas}
        for numero, mes in enumerate(meses, start=1):
            data_medicao = min(date(mes.year, mes.month, 25), HOJE)
            situacao = "EM_APROVACAO" if id_obra == 101 and mes == meses[-1] else "APROVADA"
            if id_obra in MEDE_NO_RITMO_DO_CUSTO:
                acumulados = concluir_em_ordem(tarefas, custo_incorrido_ate(id_obra, orcado, mes) / orcado)
            else:
                acumulados = [t["final"] * curva_s(numero / len(meses)) for t in tarefas]
            cabecalho = {"buildingId": id_obra, "measurementNumber": numero, "buildingUnitId": 1,
                         "date": data_medicao.isoformat(), "statusApproval": situacao, "consistent": True}
            medido_obra = 0.0
            for tarefa, fracao in zip(tarefas, acumulados):
                acumulado = round(fracao, 4)
                medido_obra += acumulado * tarefa["valor"]
                registros.append({
                    **cabecalho, "taskId": tarefa["taskId"], "presentationId": tarefa["taskId"], "summary": False,
                    "description": tarefa["description"], "unitOfMeasurement": "vb", "plannedQuantity": 1.0,
                    "measuredQuantity": round(acumulado - anterior[tarefa["taskId"]], 4),
                    "unitPrice": tarefa["valor"], "cumulativeMeasuredQuantity": acumulado,
                    "cumulativePercentage": round(acumulado * 100, 2), "measureBalance": round(1 - acumulado, 4),
                })
                anterior[tarefa["taskId"]] = acumulado
            # agrupador da obra inteira: a API devolve junto, e o painel precisa deixá-lo de fora
            registros.append({
                **cabecalho, "taskId": 0, "presentationId": 0, "summary": True, "description": obra["name"],
                "unitOfMeasurement": "vb", "plannedQuantity": 1.0, "measuredQuantity": None,
                "unitPrice": dinheiro(orcado), "cumulativeMeasuredQuantity": round(medido_obra / orcado, 4),
                "cumulativePercentage": round(medido_obra / orcado * 100, 2), "measureBalance": None,
            })
    return registros


def data_posicao_padrao():
    """Dia em que o gerador roda, nunca antes de HOJE.

    A posição financeira conta como vencida a parcela que venceu antes de current_date, e a carga real
    pede o relatório com a data do dia. Com a posição presa em HOJE, a parcela que vence depois dele
    apareceria no vencido do painel e não na inadimplência.
    """
    return max(HOJE, date.today())


def saldo_corrigido(parcela):
    # Mesmo coalesce(saldo_corrigido, saldo) de marts.fluxo_caixa_mensal.
    corrigido = parcela.get("correctedBalanceAmount")
    return corrigido if corrigido is not None else (parcela.get("balanceAmount") or 0)


# O(p log p) nas parcelas: um passe agrupando por título num dicionário e a ordenação da saída.
def gerar_inadimplencia(obras, contratos, parcelas, data_posicao):
    empresa = {o["id"]: o["idCompany"] for o in obras}
    ativos = {c["id"]: c for c in contratos if c["situation"] != "3"}
    vencidas = defaultdict(list)
    for parcela in parcelas:
        vencimento = date.fromisoformat(parcela["dueDate"])
        if (parcela["billId"] in ativos and parcela["projectId"] in empresa
                and parcela["paymentTerm"]["id"] != "FI" and saldo_corrigido(parcela) > 0
                and vencimento < data_posicao):
            vencidas[parcela["billId"]].append(parcela)

    registros = []
    for id_titulo, lista in sorted(vencidas.items(), key=lambda par: (par[1][0]["projectId"], par[0])):
        contrato = ativos[id_titulo]
        id_obra = lista[0]["projectId"]
        atrasadas = []
        for parcela in sorted(lista, key=lambda p: (p["dueDate"], p["installmentId"])):
            valor = saldo_corrigido(parcela)
            dias = (data_posicao - date.fromisoformat(parcela["dueDate"])).days
            multa = dinheiro(valor * 0.02)
            juros = dinheiro(valor * 0.01 * dias / 30)
            atrasadas.append({
                "installmentId": parcela["installmentId"], "installmentNumber": parcela["installmentNumber"],
                "conditionType": parcela["paymentTerm"]["id"], "dueDate": parcela["dueDate"], "daysOfDelay": dias,
                "correctedValueWithoutAdditions": f"{valor:.2f}", "proRata": "0.00",
                "interest": f"{juros:.2f}", "fine": f"{multa:.2f}", "totalAdditions": f"{multa + juros:.2f}",
                "correctedValueWithAdditions": f"{valor + multa + juros:.2f}",
            })
        registros.append({
            "companyId": empresa[id_obra], "receivableBillId": id_titulo,
            "issueDate": contrato["contractDate"], "costCentersId": [id_obra],
            "receivableBillValue": contrato["value"], "positionDate": data_posicao.isoformat(),
            "defaulterInstallments": atrasadas,
        })
    return registros


def fracao_do_mes(linha, numero_mes, prazo, poc, vendido):
    """Quanto do valor do estudo a conta acumula no mês numero_mes, contado a partir de 1 em INICIO_OBRA."""
    if linha == "custo_terreno":
        return Decimal(1)
    if linha == "custo_projetos":
        return Decimal(min(numero_mes, MESES_PROJETOS)) / MESES_PROJETOS
    if linha == "custo_licenciamento":
        parcelas = MES_FIM_LICENCIAMENTO - MES_INICIO_LICENCIAMENTO + 1
        pagas = min(max(numero_mes - MES_INICIO_LICENCIAMENTO + 1, 0), parcelas)
        return Decimal(pagas) / parcelas
    if linha == "assistencia_tecnica":
        return poc
    if linha == "despesas_comerciais":
        return vendido
    return min(Decimal(numero_mes) / prazo, Decimal(1))


def saldo_contabil(id_obra, id_empresa, conta, mes, anterior, atual):
    """Registro no formato do endpoint; débito e crédito são o movimento do mês, nunca negativos."""
    movimento = atual - anterior
    return {
        "costCenterId": id_obra, "companyId": id_empresa, "id": int(conta.replace(".", "")), "accountId": conta,
        "previousBalance": float(anterior), "previousBalanceType": "D",
        "debitBalance": float(max(movimento, 0)), "creditBalance": float(max(-movimento, 0)),
        "balanceCarriedForward": float(atual), "balanceCarriedForwardType": "D",
        "monthYear": f"{mes.month:02d}/{mes.year}",
    }


# O(o x m x (k + c + u)) com o obras, m meses, k contas, c contratos e u unidades: o vendido do mês percorre a
# carteira da obra, como no mapa. Cerca de 500 registros na demo, sem laço sobre parcelas.
def gerar_saldos_contabeis(obras, contratos, unidades, mapas, estudos):
    poc_do_mapa = {(r["enterpriseData"]["enterpriseId"], r["enterpriseData"]["monthYear"]):
                   Decimal(repr(r["vgvData"]["poc"])) / 100 for r in mapas}
    estudo_da_obra = {e["id_origem"]: e["linhas"] for e in estudos}
    registros = []
    for obra in obras:
        id_obra = obra["id"]
        linhas = estudo_da_obra.get(id_obra)
        if linhas is None:
            continue
        contratos_obra, unidades_obra = carteira_da_obra(id_obra, contratos, unidades)
        prazo = len(list(meses_entre(INICIO_OBRA, CHAVES[id_obra])))
        anterior = {conta: Decimal(0) for conta in CONTAS_DEMO}
        for numero_mes, mes in enumerate(meses_entre(INICIO_OBRA, HOJE), start=1):
            vgv_vendido, estoque = vendido_e_estoque(contratos_obra, unidades_obra, min(fim_do_mes(mes), HOJE))
            vgv = vgv_vendido + estoque
            vendido = Decimal(repr(vgv_vendido)) / Decimal(repr(vgv)) if vgv else Decimal(0)
            poc = poc_do_mapa.get((id_obra, f"{mes.month:02d}/{mes.year}"), Decimal(0))
            for conta, linha in CONTAS_DEMO.items():
                fator = FATOR_CONTA.get(linha, {}).get(id_obra, Decimal(1))
                fracao = fracao_do_mes(linha, numero_mes, prazo, poc, vendido)
                atual = (Decimal(repr(linhas[linha])) * fator * fracao).quantize(CENTAVO, rounding=ROUND_HALF_UP)
                registros.append(saldo_contabil(id_obra, obra["idCompany"], conta, mes, anterior[conta], atual))
                anterior[conta] = atual
    return registros


def gerar(obras, contratos, unidades, itens, parcelas, data_posicao, estudos):
    mapas = gerar_mapa(obras, contratos, unidades, itens)
    return {
        "real-estate-map": mapas,
        "building-projects/progress-logs/items": gerar_medicoes(obras, itens),
        "defaulters-receivable-bills/by-aging": gerar_inadimplencia(obras, contratos, parcelas, data_posicao),
        "accountancy/accountCostCenterBalance": gerar_saldos_contabeis(obras, contratos, unidades, mapas, estudos),
    }


def salvar(endpoint, registros):
    # Um registro por linha: o diff do arquivo mostra o que mudou quando o gerador mudar.
    linhas = ",\n".join(json.dumps(r, ensure_ascii=False, sort_keys=True) for r in registros)
    (PASTA_SAIDA / ARQUIVOS[endpoint]).write_text('{"data": [\n' + linhas + "\n]}\n", encoding="utf-8")
    print(f"complementos/{ARQUIVOS[endpoint]}: {len(registros)} registros")


def main():
    PASTA_SAIDA.mkdir(exist_ok=True)
    gerados = gerar(ler("cost-centers.json"), ler("sales.json"), ler("units.json"),
                    ler("building-cost-estimation-items.json"), ler("income.json"), data_posicao_padrao(),
                    ler_estudos())
    for endpoint, registros in gerados.items():
        salvar(endpoint, registros)


if __name__ == "__main__":
    main()
