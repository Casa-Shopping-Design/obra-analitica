"""Gera um tenant sintético no volume do piloto (plano 4.4) e mede a recarga do staging.

Volume: 10 obras, 1.000 unidades, 800 contratos, 30.000 parcelas, 20.000 títulos e 2.000 itens de
orçamento, no mesmo formato dos JSON de dados/. Tudo é sintético e identificado como tal: razão social
"Volume sintético do piloto (revisão)", obras "Obra Volume NN", compradores e credores numerados.

Uso: DATABASE_URL=... TENANT=<uuid> python3 scripts/gerar_volume_piloto.py
O tenant é criado se não existir. A carga apaga e regrava só os registros desse tenant em raw.registro,
chama staging.recarregar e staging.recarregar_precos duas vezes e confere que as contagens não mudam.
"""

import hashlib
import json
import os
import random
import time
from datetime import date, timedelta

import psycopg

RAZAO_SOCIAL = "Volume sintético do piloto (revisão)"
QUANTIDADE_OBRAS = 10
UNIDADES_POR_OBRA = 100
CONTRATOS_POR_OBRA = 80
TITULOS = 20_000
ITENS_POR_OBRA = 200
PARCELAS = 30_000
HOJE = date(2026, 9, 26)
TABELAS_STAGING = ["unidade", "contrato_venda", "contrato_unidade", "parcela_receber", "recebimento", "titulo_pagar",
                   "titulo_pagar_apropriacao", "pagamento", "item_orcamento", "tabela_preco", "tabela_preco_unidade",
                   "unidade_valor", "indice_valor"]
CONTAS_TITULO = ["2.01.001", "2.01.002", "2.01.003", "2.01.004", "2.02.001", "2.03.001", "2.05.001"]
MAPA_CONTAS = [("parcela_receber", "1.01.001", "venda_imoveis"), ("titulo_pagar", "2.01.001", "materiais"),
               ("titulo_pagar", "2.01.002", "mao_de_obra"), ("titulo_pagar", "2.01.003", "empreiteiros"),
               ("titulo_pagar", "2.01.004", "projetos"), ("titulo_pagar", "2.02.001", "tributos_receita"),
               ("titulo_pagar", "2.03.001", "corretagem"), ("titulo_pagar", "2.04.001", "despesas_administrativas"),
               ("titulo_pagar", "2.05.001", "despesas_financeiras"), ("titulo_pagar", "2.09.001", "devolucao_distrato")]


def somar_meses(dia, meses):
    total = dia.month - 1 + meses
    ano, mes = dia.year + total // 12, total % 12 + 1
    return date(ano, mes, min(dia.day, 28))


def iso(dia):
    return dia.isoformat() if dia else None


def centavos(valor):
    return round(valor, 2)


def obras():
    return [{"id": 5001 + i, "nome": f"Obra Volume {i + 1:02d}", "inicio": date(2024, 1 + i, 1),
             "entrega": date(2027, 1 + i, 30 if i != 1 else 28)} for i in range(QUANTIDADE_OBRAS)]


def gerar_unidades(sorteio, lista_obras):
    unidades = []
    for obra in lista_obras:
        for k in range(UNIDADES_POR_OBRA):
            unidades.append({
                "id": obra["id"] * 1000 + k + 1, "enterpriseId": obra["id"], "name": f"V-{k // 4 + 1:02d}{k % 4 + 1:02d}",
                "propertyType": "2Q" if k % 3 else "3Q", "privateArea": 50 + (k % 3) * 12,
                "commercialStock": "D", "deliveryDate": iso(obra["entrega"]), "indexerId": 7,
                "tablePricesID": obra["id"] * 10, "saleValuePrice": centavos(sorteio.uniform(280_000, 420_000)),
                "saleValueDate": "2026-09-01",
            })
    return unidades


# Uma parcela por item de income. Vencida é paga em 92% dos casos, 10% delas em duas vezes; 3% ficam parciais.
def parcela(sorteio, obra, contrato, numero, total, tipo, vencimento, valor, distratado):
    recebimentos, saldo = [], valor
    if vencimento <= HOJE and not (distratado and vencimento > contrato["distrato"]):
        sorte = sorteio.random()
        if sorte < 0.03:
            parte = centavos(valor * 0.4)
            recebimentos, saldo = [{"paymentDate": iso(vencimento + timedelta(days=3)), "amount": parte}], centavos(valor - parte)
        elif sorte < 0.95:
            if sorteio.random() < 0.10:
                parte = centavos(valor * 0.4)
                recebimentos = [{"paymentDate": iso(vencimento), "amount": parte},
                                {"paymentDate": iso(vencimento + timedelta(days=20)), "amount": centavos(valor - parte)}]
            else:
                recebimentos = [{"paymentDate": iso(vencimento + timedelta(days=sorteio.randint(0, 5))), "amount": valor}]
            saldo = 0
    return {
        "companyId": 1, "projectId": obra["id"], "projectName": obra["nome"], "clientId": contrato["cliente"],
        "clientName": f"Comprador sintetico {contrato['cliente']:05d}", "billId": contrato["id"],
        "installmentId": numero, "installmentNumber": f"{numero}/{total}", "dueDate": iso(vencimento),
        "issueDate": iso(contrato["data"]), "originalAmount": valor, "balanceAmount": saldo, "correctedBalanceAmount": saldo,
        "indexerName": "INCC", "defaulterSituation": "S" if saldo and vencimento < HOJE else "N",
        "mainUnit": contrato["unidade_nome"], "paymentTerm": {"id": tipo},
        "receiptsCategories": [{"financialCategoryId": "1.01.001", "financialCategoryRate": 100}], "receipts": recebimentos,
    }


# 800 contratos, 5% distratados, 40% com financiamento registrado na origem. PM alterna 33 e 34 parcelas
# para o total dar exatamente 30.000 (1 AT + PM + 2 BA + 1 FI por contrato).
def gerar_vendas(sorteio, lista_obras, unidades):
    vendas, parcelas, sequencia = [], [], 0
    por_obra = {obra["id"]: [u for u in unidades if u["enterpriseId"] == obra["id"]] for obra in lista_obras}
    for obra in lista_obras:
        vendidas = sorteio.sample(por_obra[obra["id"]], CONTRATOS_POR_OBRA)
        for unidade in vendidas:
            sequencia += 1
            data_venda = obra["inicio"] + timedelta(days=sorteio.randint(0, (HOJE - obra["inicio"]).days - 30))
            valor = unidade["saleValuePrice"]
            distratado = sorteio.random() < 0.05
            contrato = {"id": 50_000_000 + sequencia, "cliente": sequencia, "data": data_venda,
                        "unidade_nome": unidade["name"],
                        "distrato": data_venda + timedelta(days=sorteio.randint(60, 300)) if distratado else None}
            if contrato["distrato"] and contrato["distrato"] > HOJE:
                contrato["distrato"] = HOJE - timedelta(days=1)
            unidade["commercialStock"] = "D" if distratado else "V"
            quantidade_pm = 33 + sequencia % 2
            partes = {"AT": centavos(valor * 0.10), "PM": centavos(valor * 0.20), "BA": centavos(valor * 0.10)}
            partes["FI"] = centavos(valor - partes["AT"] - partes["PM"] - partes["BA"])
            financiado_origem = sorteio.random() < 0.40
            vendas.append({
                "id": contrato["id"], "enterpriseId": obra["id"], "number": f"{obra['id']}-{sequencia:04d}",
                "contractDate": iso(data_venda), "situation": "3" if distratado else "1",
                "cancellationDate": iso(contrato["distrato"]), "value": valor, "totalSellingValue": valor,
                "financialInstitutionNumber": "104" if financiado_origem else None,
                "financialInstitutionDate": iso(data_venda + timedelta(days=90)) if financiado_origem else None,
                "associativeCredit": "S" if financiado_origem else "N",
                "customers": [{"id": sequencia, "main": True, "name": f"Comprador sintetico {sequencia:05d}"}],
                "units": [{"id": unidade["id"], "main": True, "name": unidade["name"], "propertyType": unidade["propertyType"]}],
                "paymentConditions": [{"conditionType": tipo, "totalValue": total,
                                       "installmentsNumber": {"AT": 1, "PM": quantidade_pm, "BA": 2, "FI": 1}[tipo]}
                                      for tipo, total in partes.items()],
            })
            total = 4 + quantidade_pm
            itens = [("AT", data_venda, partes["AT"])]
            valor_pm = centavos(partes["PM"] / quantidade_pm)
            for k in range(quantidade_pm):
                ultimo = centavos(partes["PM"] - valor_pm * (quantidade_pm - 1))
                itens.append(("PM", somar_meses(data_venda, k + 1), ultimo if k == quantidade_pm - 1 else valor_pm))
            meio_ba = centavos(partes["BA"] / 2)
            itens.append(("BA", somar_meses(data_venda, 12), meio_ba))
            itens.append(("BA", somar_meses(data_venda, 24), centavos(partes["BA"] - meio_ba)))
            itens.append(("FI", obra["entrega"], partes["FI"]))
            for numero, (tipo, vencimento, valor_parcela) in enumerate(itens, start=1):
                parcelas.append(parcela(sorteio, obra, contrato, numero, total, tipo, vencimento, valor_parcela, distratado))
    return vendas, parcelas


# 20.000 títulos: 5% rateados entre duas obras, 1% sem obra, 1% com conta sem mapeamento; pagos em 95% dos
# vencidos, 5% deles em duas vezes, 3% com saldo parcial.
def gerar_titulos(sorteio, lista_obras):
    titulos = []
    fim = date(2027, 6, 30)
    for n in range(TITULOS):
        obra = lista_obras[n % QUANTIDADE_OBRAS]
        vencimento = obra["inicio"] + timedelta(days=sorteio.randint(0, (fim - obra["inicio"]).days))
        valor = centavos(sorteio.uniform(2_000, 60_000))
        sorte = sorteio.random()
        if sorte < 0.01:
            rateio = None
        elif sorte < 0.06:
            outra = lista_obras[(n + 3) % QUANTIDADE_OBRAS]
            parte = centavos(valor * 0.6)
            rateio = [{"buildingId": obra["id"], "amount": parte}, {"buildingId": outra["id"], "amount": centavos(valor - parte)}]
        else:
            rateio = [{"buildingId": obra["id"], "amount": valor}]
        conta = "2.04.001" if rateio is None else ("2.99.001" if sorteio.random() < 0.01 else sorteio.choice(CONTAS_TITULO))
        pagamentos, saldo = [], valor
        if vencimento <= HOJE and sorteio.random() < 0.95:
            if sorteio.random() < 0.03:
                pagamentos, saldo = [{"paymentDate": iso(vencimento), "amount": centavos(valor * 0.5)}], centavos(valor - centavos(valor * 0.5))
            elif sorteio.random() < 0.05:
                parte = centavos(valor * 0.3)
                pagamentos = [{"paymentDate": iso(vencimento), "amount": parte},
                              {"paymentDate": iso(vencimento + timedelta(days=15)), "amount": centavos(valor - parte)}]
                saldo = 0
            else:
                pagamentos, saldo = [{"paymentDate": iso(vencimento), "amount": valor}], 0
        titulo = {"companyId": 1, "creditorName": f"Credor sintetico {n % 500:03d}", "billId": 60_000_000 + n + 1,
                  "dueDate": iso(vencimento), "originalAmount": valor, "balanceAmount": saldo, "payments": pagamentos,
                  "issueDate": iso(vencimento - timedelta(days=sorteio.randint(5, 40))),
                  "paymentsCategories": [{"financialCategoryId": conta, "financialCategoryRate": 100}]}
        if rateio is not None:
            titulo["buildingsCosts"] = rateio
        titulos.append(titulo)
    return titulos


def gerar_orcamento(sorteio, lista_obras):
    return [{"buildingId": obra["id"], "buildingName": obra["nome"], "wbsCode": f"{k // 10 + 1:02d}.{k % 10 + 1:02d}",
             "description": f"Item sintetico {k + 1}", "unitOfMeasure": "vb", "quantity": 1,
             "unitPrice": (v := centavos(sorteio.uniform(20_000, 90_000))), "totalPrice": v,
             "percentComplete": sorteio.randint(0, 100), "measuredQuantity": 1.0}
            for obra in lista_obras for k in range(ITENS_POR_OBRA)]


def gerar_precos(lista_obras, unidades):
    indices, valor, mes = [], 1000.0, date(2024, 1, 1)
    while mes <= date(2026, 9, 1):
        indices.append({"id": 7, "name": "INCC", "lastValue": {"date": iso(mes), "value": round(valor, 4), "percentage": 0.4}})
        valor *= 1.004
        mes = somar_meses(mes, 1)
    tabelas = [{"id": obra["id"] * 10, "version": 1, "companyId": 1, "enterpriseId": obra["id"],
                "tableName": f"Tabela {obra['nome']}", "tableVersionName": "09/2026", "startOfTerm": "2026-09-01",
                "endOfTerm": None, "paymentConditions": [{"order": 1, "paymentConditionType": "AT", "indexer": {"id": 7},
                                                          "baseDate": "2024-01-01"}],
                "units": [{"id": u["id"], "indexedQuantity": round(u["saleValuePrice"] / valor, 4)}
                          for u in unidades if u["enterpriseId"] == obra["id"]]}
               for obra in lista_obras]
    return indices, tabelas


def hash_registro(payload):
    return hashlib.sha256(json.dumps(payload, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def contar(cur, tenant):
    cur.execute(" union all ".join(f"select '{t}', count(*) from staging.{t} where tenant_id = %s" for t in TABELAS_STAGING),
                [tenant] * len(TABELAS_STAGING))
    return dict(cur.fetchall())


def main():
    tenant = os.environ["TENANT"]
    sorteio = random.Random(44)
    lista_obras = obras()
    unidades = gerar_unidades(sorteio, lista_obras)
    vendas, parcelas = gerar_vendas(sorteio, lista_obras, unidades)
    titulos = gerar_titulos(sorteio, lista_obras)
    orcamento = gerar_orcamento(sorteio, lista_obras)
    indices, tabelas = gerar_precos(lista_obras, unidades)
    assert len(parcelas) == PARCELAS and len(vendas) == QUANTIDADE_OBRAS * CONTRATOS_POR_OBRA
    por_endpoint = {"units": unidades, "sales": vendas, "income": parcelas, "outcome": titulos,
                    "building-cost-estimation-items": orcamento, "indexers": indices, "price-tables": tabelas}

    with psycopg.connect(os.environ["DATABASE_URL"]) as conexao, conexao.cursor() as cur:
        cur.execute("insert into app.tenant (id, razao_social) values (%s, %s) on conflict (id) do nothing",
                    (tenant, RAZAO_SOCIAL))
        cur.executemany("insert into app.centro_custo (tenant_id, id_origem, nome) values (%s, %s, %s) "
                        "on conflict (tenant_id, id_origem) do nothing",
                        [(tenant, obra["id"], obra["nome"]) for obra in lista_obras])
        inicio = time.perf_counter()
        for endpoint, registros in por_endpoint.items():
            cur.execute("delete from raw.registro where tenant_id = %s and endpoint = %s", (tenant, endpoint))
            with cur.copy("copy raw.registro (tenant_id, endpoint, payload, hash_registro) from stdin") as copia:
                for registro in registros:
                    copia.write_row((tenant, endpoint, json.dumps(registro, ensure_ascii=False), hash_registro(registro)))
        conexao.commit()
        tempo_raw = time.perf_counter() - inicio

        medicoes = []
        for rodada in (1, 2):
            inicio = time.perf_counter()
            cur.execute("select staging.recarregar(%s)", (tenant,))
            meio = time.perf_counter()
            cur.execute("select staging.recarregar_precos(%s)", (tenant,))
            conexao.commit()
            fim = time.perf_counter()
            medicoes.append({"rodada": rodada, "recarregar_s": round(meio - inicio, 3),
                             "recarregar_precos_s": round(fim - meio, 3), "contagens": contar(cur, tenant)})

        # Mapeamento das contas sintéticas e critério validado, para o DRE percorrer o caminho completo.
        cur.executemany("insert into app.mapa_conta_origem (tenant_id, tipo_origem, conta_origem, categoria_codigo, observacao, autor) "
                        "values (%s, %s, %s, %s, 'volume sintetico', '00000000-0000-0000-0000-000000000000') "
                        "on conflict (tenant_id, tipo_origem, conta_origem) do nothing",
                        [(tenant, *m) for m in MAPA_CONTAS])
        cur.execute("insert into app.criterio_reconhecimento (tenant_id, metodo, autor) "
                    "values (%s, 'percentual_conclusao', '00000000-0000-0000-0000-000000000000') "
                    "on conflict (tenant_id, centro_custo_id) do nothing", (tenant,))
        cur.execute("analyze")
        conexao.commit()

    resumo = {"registros_raw": {e: len(r) for e, r in por_endpoint.items()}, "gravacao_raw_s": round(tempo_raw, 3),
              "recargas": medicoes, "contagens_iguais": medicoes[0]["contagens"] == medicoes[1]["contagens"]}
    print(json.dumps(resumo, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
