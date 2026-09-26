# Casos de teste financeiros

Versão 1, 26/09/2026. Casos pequenos, com resultado calculado à mão, para os testes pgTAP de `banco_eventos`, `banco_dre` e `banco_planejamento` e para a conferência independente do `revisor`. Nomes e regras seguem `docs/financeiro/contrato_dados.md`. Todo valor esperado é exato ao centavo. Onde o caso diz "linha ausente ou zerada", o teste aceita as duas formas.

## Como ler

- Cada caso é autocontido: roda dentro de `begin ... rollback` sobre a base F0 e insere só o que está descrito nele.
- "Nível raw" quer dizer que o teste grava payloads em `raw.registro` e chama `staging.recarregar(tenant)`; serve para testar o staging. "Nível staging" quer dizer que o teste grava direto nas tabelas de staging e confere as views de marts.
- Data de referência: `select set_config('app.data_referencia', 'AAAA-MM-DD', true);` antes das consultas.
- "Entrar como X": `select set_config('request.jwt.claims', '{"sub": "<uuid>", "role": "authenticated"}', true); set local role authenticated;`. Voltar com `reset role`.
- Parcela no nível staging, salvo indicação: `saldo_corrigido = saldo`, `valor_recebido` igual à soma dos recebimentos listados, `data_recebimento` igual à data do último, `valor_baixado_sem_caixa = 0`. Cada recebimento listado vira uma linha em `staging.recebimento` com `tipo_baixa = 'recebimento'` (ou `estorno` se negativo), `origem` pela condição (`FI` é `repasse`, o resto `direta`), sequência na ordem da lista.
- Título no nível staging, salvo indicação: uma apropriação `sequencia_obra = 1`, `sequencia_conta = 1`, `percentual = 1`, `principal = true`, `ajuste_baixa = 0`, `valor_pago` igual à soma dos pagamentos, `saldo = valor_original - valor_pago`; cada pagamento vira uma linha em `staging.pagamento` com as mesmas sequências. O cabeçalho `staging.titulo_pagar` é opcional, porque nenhuma view de marts o lê.
- Contrato no nível staging, salvo indicação: `situacao = '1'`, uma linha em `staging.contrato_unidade` com a unidade citada e `principal = true`.

## Base F0

Tenants:

| id | razao_social |
| --- | --- |
| `7e000000-0000-4000-8000-00000000000a` | Construtora Teste Financeiro A |
| `7e000000-0000-4000-8000-00000000000b` | Construtora Teste Financeiro B |

Centros de custo:

| id | tenant | id_origem | nome | tipo |
| --- | --- | --- | --- | --- |
| `7c000000-0000-4000-8000-0000000000a1` (T1) | A | 9001 | Obra Teste 1 | obra |
| `7c000000-0000-4000-8000-0000000000a2` (T2) | A | 9002 | Obra Teste 2 | obra |
| `7c000000-0000-4000-8000-0000000000ae` (EA) | A | nulo | Despesas sem obra | empresa |
| `7c000000-0000-4000-8000-0000000000b1` (B1) | B | 9001 | Obra Teste B1 | obra |
| `7c000000-0000-4000-8000-0000000000be` (EB) | B | nulo | Despesas sem obra | empresa |

Usuários (`auth.users` com e-mail `<papel>.financeiro@teste.invalid`):

| id | tenant | perfil | obras vinculadas |
| --- | --- | --- | --- |
| `7a000000-0000-4000-8000-00000000d00a` (DA) | A | diretor | todas pela regra do perfil |
| `7a000000-0000-4000-8000-00000000f00a` (FA) | A | financeiro | todas pela regra do perfil |
| `7a000000-0000-4000-8000-00000000c00a` (GA) | A | gerente_obra | T1 |
| `7a000000-0000-4000-8000-00000000d00b` (DB) | B | diretor | todas pela regra do perfil |

Os payloads de nível raw usam `enterpriseId`/`projectId`/`buildingId` 9001 para T1 e 9002 para T2 e o endpoint indicado. Quem grava é o dono do banco, como o carregador.

## C01 Venda contratada, receita reconhecida e valor recebido são números diferentes

Nível staging. Referência 2026-04-30. Sem linha em `app.criterio_reconhecimento`.

Dados em T1: unidade 90001 (`nome = 'T1-101'`). Contrato 5001, `valor = 300000.00`, `data_venda = 2026-01-10`, unidade 90001.

| parcela | condição | vencimento | valor_original | saldo | recebimentos |
| --- | --- | --- | --- | --- | --- |
| 1 | AT | 2026-01-10 | 30000.00 | 0 | 2026-01-10: 30000.00 |
| 2 | PM | 2026-02-10 | 10000.00 | 0 | 2026-02-10: 10000.00 |
| 3 | PM | 2026-03-10 | 10000.00 | 0 | 2026-03-10: 10000.00 |
| 4 | PM | 2026-04-10 | 10000.00 | 10000.00 | nenhum |
| 5 | FI | 2027-06-30 | 240000.00 | 240000.00 | nenhum |

Esperado:

| Consulta | Valor |
| --- | --- |
| `resumo_receitas_obra` T1 `vgv_contratado_ativo` | 300000.00 |
| idem `recebido_direto` | 50000.00 |
| idem `recebido_financiamento` | 0.00 |
| idem `vencido_direto` | 10000.00 |
| idem `a_vencer_financiamento` | 240000.00 |
| idem `previsto_proximo_mes_direto` e `_financiamento` (maio) | 0.00 e 0.00 |
| `dre_mensal` T1, `competencia = 2026-04-01`, `receita_bruta` | `disponivel = false`, `valor_mes` nulo, `motivo = 'criterio_nao_validado'` |
| idem `resultado_gerencial` | `disponivel = false`, `valor_mes` nulo |
| idem `deducoes` | `disponivel = true`, `valor_mes = 0.00` |
| `reconhecimento_obra_mensal` T1 abril `vgv_ativo_fim_mes` | 300000.00, `receita_reconhecida_acumulada` nula |

O caso C22 mostra os três números lado a lado com o critério validado.

## C02 Recebimento e pagamento parciais

Nível raw. Referência 2026-03-15.

`sales`: `{"id": 5101, "enterpriseId": 9001, "number": "T1-5101", "contractDate": "2026-01-01", "situation": "1", "value": 2000.00, "units": [{"id": 90011, "main": true}]}`

`income`:

```json
{"projectId": 9001, "billId": 5101, "installmentId": 1, "dueDate": "2026-01-10", "issueDate": "2026-01-01",
 "originalAmount": 1000.00, "balanceAmount": 0, "correctedBalanceAmount": 0, "paymentTerm": {"id": "PM"},
 "receipts": [{"paymentDate": "2026-02-05", "amount": 400.00}, {"paymentDate": "2026-03-07", "amount": 600.00}]}
{"projectId": 9001, "billId": 5101, "installmentId": 2, "dueDate": "2026-02-10", "issueDate": "2026-01-01",
 "originalAmount": 1000.00, "balanceAmount": 700.00, "correctedBalanceAmount": 700.00, "paymentTerm": {"id": "PM"},
 "receipts": [{"paymentDate": "2026-02-10", "amount": 300.00}]}
```

`outcome`:

```json
{"billId": 7101, "companyId": 1, "creditorName": "Fornecedor Teste", "dueDate": "2026-02-20", "issueDate": "2026-02-01",
 "originalAmount": 1000.00, "balanceAmount": 250.00, "buildingsCosts": [{"buildingId": 9001, "amount": 1000.00}],
 "payments": [{"paymentDate": "2026-02-20", "amount": 500.00}, {"paymentDate": "2026-03-10", "amount": 250.00}]}
```

Esperado no staging:

| Consulta | Valor |
| --- | --- |
| `staging.recebimento` | 3 linhas: (5101, 1, 1, 2026-02-05, 400.00), (5101, 1, 2, 2026-03-07, 600.00), (5101, 2, 1, 2026-02-10, 300.00), todas `tipo_baixa = 'recebimento'`, `origem = 'direta'` |
| `staging.parcela_receber` 5101/1 | `valor_recebido = 1000.00`, `data_recebimento = 2026-03-07` |
| `staging.parcela_receber` 5101/2 | `valor_recebido = 300.00`, `data_recebimento = 2026-02-10` |
| `staging.titulo_pagar` 7101 | `valor_pago = 750.00`, `ajuste_baixa = 0.00`, `data_pagamento = 2026-03-10`, `centro_custo_id = T1` |
| `staging.titulo_pagar_apropriacao` 7101 | 1 linha, T1, `percentual = 1.000000`, `valor_original = 1000.00`, `valor_pago = 750.00`, `saldo = 250.00`, `data_competencia = 2026-02-01` |
| `staging.pagamento` 7101 | (seq 1, 2026-02-20, 500.00), (seq 2, 2026-03-10, 250.00) |

Esperado em marts:

| Consulta | Valor |
| --- | --- |
| `fluxo_caixa_mensal` T1 | 2 linhas (fevereiro e março); nenhuma em janeiro |
| fevereiro | `entrada_direta_realizada = 700.00`, `entrada_direta_vencida = 700.00`, `saida_realizada = 500.00`, `saida_vencida = 250.00`, `saldo_mes = -50.00`, `saldo_acumulado = -50.00` |
| março | `entrada_direta_realizada = 600.00`, `saida_realizada = 250.00`, `saldo_mes = 350.00`, `saldo_acumulado = 300.00` |
| `carteira_recebiveis` 5101/1 | `situacao = 'quitada'`, `parcial = false`, `dias_atraso` nulo |
| `carteira_recebiveis` 5101/2 | `situacao = 'vencida'`, `parcial = true`, `saldo = 700.00`, `dias_atraso = 33` |
| `posicao_financeira_obra` T1 | `recebido_direto = 1300.00`, `vencido_direto = 700.00`, `pago = 750.00`, `a_pagar = 250.00`, `custo_lancado = 1000.00`, `ajuste_baixa = 0.00`, `caixa_atual = 550.00`, `exposicao_maxima = 50.00`, `orcamento_carregado = false` |
| `custo_obra_resumo` T1 | `custo_lancado = 1000.00`, `desembolsado = 750.00`, `em_aberto_vencido = 250.00`, `em_aberto_a_vencer = 0.00`, `ajuste_baixa = 0.00`, `orcamento_vigente` nulo, `remanescente_sem_titulo` nulo, `motivo = 'orcamento_ausente'` |

## C03 Competência diferente da data de pagamento

Nível raw. Referência 2026-03-10. Mapeamento: `('titulo_pagar', '2.01.001') -> materiais` no tenant A.

`outcome`:

```json
{"billId": 7201, "dueDate": "2026-02-15", "issueDate": "2026-01-20", "originalAmount": 5000.00, "balanceAmount": 0,
 "buildingsCosts": [{"buildingId": 9001, "amount": 5000.00}],
 "paymentsCategories": [{"financialCategoryId": "2.01.001", "financialCategoryRate": 100}],
 "payments": [{"paymentDate": "2026-02-14", "amount": 5000.00}]}
```

Esperado:

| Consulta | Valor |
| --- | --- |
| apropriação 7201 | `data_competencia = 2026-01-20`, `conta_origem = '2.01.001'` |
| `dre_mensal` T1 2026-01 `custo_obra_incorrido` | -5000.00 |
| `dre_mensal` T1 2026-01 `despesas_administrativas` | 0.00 (custo de obra não vira despesa) |
| `dre_mensal` T1 2026-02 `custo_obra_incorrido` | 0.00 |
| `dre_mensal` T1 2026-03 `custo_obra_incorrido`, `valor_acumulado` | -5000.00 |
| `dre_mensal` T1 2026-01 `cobertura` | 1.000000 |
| `dre_mensal` T1 2026-02 `cobertura` | nula (nada lançado em fevereiro) |
| `despesa_mensal` T1 materiais 2026-01 | `lancado_competencia = 5000.00`, `pago = 0.00` |
| `despesa_mensal` T1 materiais 2026-02 | `lancado_competencia = 0.00`, `pago = 5000.00` |
| `fluxo_caixa_mensal` T1 | só fevereiro, com `saida_realizada = 5000.00` |

## C04 Financiamento separado da entrada direta

Nível staging. Referência 2026-03-31.

Contratos em T1: 5301 (`valor = 400000.00`, `data_venda = 2026-01-05`, `valor_financiado = 300000.00`, `banco_repasse` e `data_repasse` nulos); 5302 (`valor = 200000.00`, `data_venda = 2025-06-01`, `valor_financiado = 150000.00`, `banco_repasse = '001'`, `data_repasse = 2026-02-10`).

| contrato/parcela | condição | vencimento | valor_original | saldo | recebimentos |
| --- | --- | --- | --- | --- | --- |
| 5301/1 | AT | 2026-01-05 | 40000.00 | 0 | 2026-01-05: 40000.00 |
| 5301/2 | PM | 2026-06-05 | 60000.00 | 60000.00 | nenhum |
| 5301/3 | FI | 2026-12-20 | 300000.00 | 300000.00 | nenhum |
| 5302/1 | AT | 2025-06-01 | 50000.00 | 0 | 2025-06-01: 50000.00 |
| 5302/2 | FI | 2026-02-10 | 150000.00 | 0 | 2026-02-12: 150000.00 |

Esperado:

| Consulta | Valor |
| --- | --- |
| `resumo_receitas_obra` T1 | `vgv_contratado_ativo = 600000.00`, `recebido_direto = 90000.00`, `recebido_financiamento = 150000.00`, `a_vencer_direto = 60000.00`, `a_vencer_financiamento = 300000.00`, `vencido_direto = 0.00`, `vencido_financiamento = 0.00` |
| `posicao_financeira_obra` T1 | `recebido_direto = 90000.00`, `recebido_repasse = 150000.00`, `a_receber_direto = 60000.00`, `a_receber_repasse = 300000.00` |
| `fluxo_caixa_mensal` T1 2026-02 | `repasse_realizado = 150000.00`, `entrada_direta_realizada = 0.00` |
| `recebimento_mensal` T1 2026-02 financiamento | `recebido = 150000.00`, `previsto_contratual = 150000.00` |
| `financiamento_contrato` 5301 | `classificacao = 'financiamento_pendente'`, `saldo_financiamento_aberto = 300000.00` |
| `financiamento_contrato` 5302 | `classificacao = 'financiamento_elegivel'`, `saldo_financiamento_aberto = 0.00`, `recebido_financiamento = 150000.00` |

## C05 Parcela vencida fica fora da previsão de entrada

Nível staging. Referência 2026-03-20. Contrato 5401 em T1 (`valor = 200000.00`, `data_venda = 2025-10-01`).

| parcela | condição | vencimento | valor_original | saldo |
| --- | --- | --- | --- | --- |
| 1 | PM | 2026-03-10 | 2000.00 | 2000.00 |
| 2 | PM | 2026-04-10 | 2000.00 | 2000.00 |
| 3 | FI | 2026-03-01 | 100000.00 | 100000.00 |

Esperado:

| Consulta | Valor |
| --- | --- |
| `resumo_receitas_obra` T1 | `previsto_proximo_mes_direto = 2000.00`, `previsto_proximo_mes_financiamento = 0.00`, `vencido_direto = 2000.00`, `vencido_financiamento = 100000.00`, `a_vencer_direto = 2000.00` |
| `fluxo_caixa_mensal` T1 2026-03 | `entrada_direta_vencida = 2000.00`, `repasse_vencido = 100000.00`, `entrada_direta_prevista = 0.00`, `saldo_mes = 0.00` |
| `fluxo_caixa_mensal` T1 2026-04 | `entrada_direta_prevista = 2000.00`, `saldo_mes = 2000.00` |
| `recebivel_projetado` 5401/3 | `classe = 'financiamento_pendente'`, `incluida_projecao = false` |
| `fluxo_projetado_mensal` T1 2026-03 | `previsto_direto = 0.00`, `vencido_a_receber = 102000.00`, `total_entradas = 0.00`, `saldo_mes = 0.00` |
| `fluxo_projetado_mensal` T1 2026-04 | `previsto_direto = 2000.00` |

## C06 Próximo mês na virada de dezembro para janeiro

Nível staging. Referência 2026-12-15. Contrato 5501 em T1, parcelas PM:

| parcela | vencimento | saldo |
| --- | --- | --- |
| 1 | 2026-12-10 | 800.00 |
| 2 | 2026-12-20 | 1000.00 |
| 3 | 2027-01-10 | 1500.00 |
| 4 | 2027-01-31 | 500.00 |
| 5 | 2027-02-01 | 700.00 |

Esperado:

| Consulta | Valor |
| --- | --- |
| `app.data_referencia()` | 2026-12-15 |
| `resumo_receitas_obra` T1 `previsto_proximo_mes_direto` | 2000.00 (parcelas 3 e 4) |
| idem `vencido_direto` | 800.00 |
| idem `a_vencer_direto` | 3700.00 |
| `carteira_recebiveis` 5501/2 com referência 2026-12-20 | `situacao = 'a_vencer'` (o próprio dia ainda não venceu) |
| `carteira_recebiveis` 5501/2 com referência 2026-12-21 | `situacao = 'vencida'`, `dias_atraso = 1` |
| `app.data_referencia()` depois de `set_config('app.data_referencia', '', true)` | igual a `(now() at time zone 'America/Sao_Paulo')::date` |

## C07 Distrato, estorno e renegociação sem duplicidade

Nível raw. Referência 2026-06-15. Mapeamento: `('titulo_pagar', '2.09.001') -> devolucao_distrato`.

`sales`:

```json
{"id": 5601, "enterpriseId": 9001, "contractDate": "2025-10-01", "situation": "3", "cancellationDate": "2026-05-10", "value": 250000.00, "units": [{"id": 90601, "main": true}]}
{"id": 5602, "enterpriseId": 9001, "contractDate": "2026-03-01", "situation": "1", "value": 100000.00, "units": [{"id": 90602, "main": true}]}
{"id": 5603, "enterpriseId": 9001, "contractDate": "2026-01-15", "situation": "1", "value": 120000.00, "units": [{"id": 90603, "main": true}]}
```

`income` (todos com `projectId` 9001):

| billId/installmentId | paymentTerm | dueDate | originalAmount | balanceAmount = correctedBalanceAmount | receipts |
| --- | --- | --- | --- | --- | --- |
| 5601/1 | AT | 2025-10-01 | 25000.00 | 0 | `[{"paymentDate": "2025-10-01", "amount": 25000.00}]` |
| 5601/2 | PM | 2026-06-10 | 5000.00 | 5000.00 | `[]` |
| 5602/1 | PM | 2026-04-10 | 3000.00 | 3000.00 | `[{"paymentDate": "2026-04-10", "amount": 3000.00}, {"paymentDate": "2026-04-20", "amount": -3000.00}]` |
| 5603/1 | PM | 2026-03-10 | 4000.00 | 0 | `[]` (renegociada) |
| 5603/2 | PM | 2026-07-10 | 2000.00 | 2000.00 | `[]` |
| 5603/3 | PM | 2026-08-10 | 2000.00 | 2000.00 | `[]` |

`outcome` (devolução ao comprador, sem obra):

```json
{"billId": 7601, "dueDate": "2026-06-01", "issueDate": "2026-05-20", "originalAmount": 10000.00, "balanceAmount": 10000.00,
 "paymentsCategories": [{"financialCategoryId": "2.09.001", "financialCategoryRate": 100}], "payments": []}
```

Esperado:

| Consulta | Valor |
| --- | --- |
| `staging.recebimento` 5602/1 | 2 linhas: seq 1 `3000.00` `recebimento`; seq 2 `-3000.00` `estorno` |
| `staging.parcela_receber` 5602/1 | `valor_recebido = 0.00`, `data_recebimento = 2026-04-20` |
| `carteira_recebiveis` 5601/1 | `quitada`, `valor_recebido = 25000.00` |
| `carteira_recebiveis` 5601/2 | `cancelada_distrato`, `saldo = 5000.00`, `dias_atraso` nulo |
| `carteira_recebiveis` 5602/1 | `vencida`, `parcial = false`, `saldo = 3000.00` |
| `carteira_recebiveis` 5603/1 | `baixada_sem_recebimento` |
| `resumo_receitas_obra` T1 | `contratos_ativos = 2`, `contratos_distratados = 1`, `vgv_contratado_ativo = 220000.00`, `recebido_direto = 25000.00`, `vencido_direto = 3000.00`, `a_vencer_direto = 4000.00`, `saldo_distratado = 5000.00` |
| `recebimento_mensal` T1 direta 2025-10 | `recebido = 25000.00`, `previsto_contratual = 25000.00` |
| `recebimento_mensal` T1 direta 2026-04 | `recebido = 0.00`, `previsto_contratual = 3000.00`, `saldo_em_aberto = 3000.00` |
| `recebimento_mensal` T1 direta 2026-03 e 2026-06 | linha ausente ou zerada |
| `recebimento_mensal` T1 direta 2026-07 e 2026-08 | `previsto_contratual = 2000.00` cada |
| `fluxo_caixa_mensal` T1 2026-04 | `entrada_direta_realizada = 0.00`, `entrada_direta_vencida = 3000.00` |
| `fluxo_caixa_mensal` T1 2026-06 | linha ausente ou com `entrada_direta_vencida = 0.00` (distrato fora) |
| `fluxo_caixa_mensal` T1 2026-07 | `entrada_direta_prevista = 2000.00` |
| apropriação 7601 | centro EA, `motivo_sem_obra = 'sem_rateio_na_origem'`, `percentual = 1.000000`, `saldo = 10000.00` |
| `fluxo_caixa_mensal` EA 2026-06 | `saida_vencida = 10000.00` |
| `dre_mensal` EA 2026-05 `fora_do_resultado` | -10000.00 |
| `dre_mensal` EA 2026-05 `resultado_gerencial` | 0.00, disponível |

## C08 Título rateado entre duas obras com resíduo de centavo, e despesa sem obra

Nível raw. Referência 2026-02-28.

`outcome`:

```json
{"billId": 7801, "dueDate": "2026-03-20", "issueDate": "2026-02-01", "originalAmount": 1000.00, "balanceAmount": 899.95,
 "buildingsCosts": [{"buildingId": 9001, "amount": 500.00}, {"buildingId": 9002, "amount": 500.00}],
 "payments": [{"paymentDate": "2026-02-10", "amount": 100.05}]}
{"billId": 7802, "dueDate": "2026-02-15", "issueDate": "2026-02-05", "originalAmount": 800.00, "balanceAmount": 0,
 "payments": [{"paymentDate": "2026-02-15", "amount": 800.00}]}
{"billId": 7803, "dueDate": "2026-03-05", "issueDate": "2026-02-10", "originalAmount": 50.00, "balanceAmount": 50.00,
 "buildingsCosts": [{"buildingId": 9999, "amount": 50.00}], "payments": []}
```

Cálculo do 7801: percentuais 0,5 e 0,5; empate, principal é T1 (menor sequência). Pagamento acumulado 100.05: T2 `round(50.025, 2) = 50.03`; T1 `100.05 - 50.03 = 50.02`.

Esperado:

| Consulta | Valor |
| --- | --- |
| apropriação 7801 T1 | `sequencia_obra = 1`, `principal = true`, `percentual = 0.500000`, `valor_original = 500.00`, `valor_pago = 50.02`, `ajuste_baixa = 0.00`, `saldo = 449.98` |
| apropriação 7801 T2 | `sequencia_obra = 2`, `principal = false`, `valor_original = 500.00`, `valor_pago = 50.03`, `saldo = 449.97` |
| `staging.pagamento` 7801 | T1 `50.02`, T2 `50.03`, ambos em 2026-02-10 |
| `staging.titulo_pagar` 7801 | `centro_custo_id = T1`, `valor_pago = 100.05`, `quantidade_apropriacoes = 2` |
| apropriação 7802 | centro EA, `motivo_sem_obra = 'sem_rateio_na_origem'`, `valor_pago = 800.00` |
| apropriação 7803 | centro EA, `motivo_sem_obra = 'obra_nao_cadastrada'`, `id_origem_obra = 9999`, `saldo = 50.00` |
| `fluxo_caixa_mensal` 2026-02 `saida_realizada` | T1 50.02; T2 50.03; EA 800.00; soma dos três 900.05 = soma de `staging.pagamento` do tenant |
| `fluxo_caixa_mensal` 2026-03 `saida_prevista` | T1 449.98; T2 449.97; EA 50.00 |
| `posicao_financeira_obra` como DA | 2 linhas (T1 e T2), nenhuma de EA |
| `posicao_financeira_obra` T1 | `pago = 50.02`, `a_pagar = 449.98`, `custo_lancado = 500.00` |
| `fluxo_caixa_mensal` como GA | só linhas de T1 |

Variante com segundo pagamento: acrescentar `{"paymentDate": "2026-03-10", "amount": 899.95}` em 7801 e mudar `balanceAmount` para 0. Acumulado 1000.00: T2 `500.00`, T1 `500.00`. Segundo pagamento: T1 `449.98`, T2 `449.97`. Saldos das duas apropriações 0.00.

## C09 Custo futuro sem duplicar os títulos existentes

Nível staging. Referência 2026-09-15.

T1: itens de orçamento `01` 600000.00 e `02` 400000.00. Títulos sem conta:

| título | vencimento | competência | valor_original | pagamentos | saldo |
| --- | --- | --- | --- | --- | --- |
| 7901 | 2026-08-10 | 2026-08-01 | 300000.00 | 2026-08-10: 300000.00 | 0 |
| 7902 | 2026-10-05 | 2026-09-01 | 150000.00 | nenhum | 150000.00 |
| 7903 | 2026-09-01 | 2026-08-15 | 50000.00 | nenhum | 50000.00 |

Como FA: `app.registrar_premissa_distribuicao(T1, 'Cronograma de teste', null, '[{"competencia": "2026-10-01", "fracao": 0.5}, {"competencia": "2026-11-01", "fracao": 0.5}]')`.

Esperado:

| Consulta | Valor |
| --- | --- |
| `custo_obra_resumo` T1 | `orcamento_vigente = 1000000.00`, `custo_lancado = 500000.00`, `desembolsado = 300000.00`, `em_aberto_vencido = 50000.00`, `em_aberto_a_vencer = 150000.00`, `ajuste_baixa = 0.00`, `remanescente_sem_titulo = 500000.00`, `estimativa_conclusao = 1000000.00`, `desvio = 0.00` |
| `posicao_financeira_obra` T1 | `custo_a_incorrer = 500000.00`, `estouro_orcamento = 0.00` |

`fluxo_projetado_mensal` T1:

| competencia | pago | a_pagar_vencido | a_pagar | custo_sem_titulo_distribuido | total_saidas | caixa_gerado_acumulado | necessidade_aporte_acumulada | aporte_incremental_mes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-08-01 | 300000.00 | 0.00 | 0.00 | 0.00 | 300000.00 | -300000.00 | 300000.00 | 300000.00 |
| 2026-09-01 | 0.00 | 50000.00 | 0.00 | 0.00 | 50000.00 | -350000.00 | 350000.00 | 50000.00 |
| 2026-10-01 | 0.00 | 0.00 | 150000.00 | 250000.00 | 400000.00 | -750000.00 | 750000.00 | 400000.00 |
| 2026-11-01 | 0.00 | 0.00 | 0.00 | 250000.00 | 250000.00 | -1000000.00 | 1000000.00 | 250000.00 |

`resumo_projecao_obra` T1: `exposicao_maxima_projetada = 1000000.00`, `mes_exposicao_maxima = 2026-11-01`, `custo_sem_titulo_total = 500000.00`, `custo_sem_titulo_distribuido_total = 500000.00`, `custo_sem_titulo_nao_distribuido = 0.00`, `exposicao_parcial = false`. Saídas futuras (setembro a novembro) somam 700000.00 = em aberto 200000.00 + remanescente 500000.00; o orçamento nunca soma com os títulos.

Variante sem premissa: linhas de agosto a outubro; outubro `total_saidas = 150000.00`, `caixa_gerado_acumulado = -500000.00`. Resumo: `exposicao_maxima_projetada = 500000.00`, `mes_exposicao_maxima = 2026-10-01`, `custo_sem_titulo_nao_distribuido = 500000.00`, `exposicao_parcial = true`, `motivo_distribuicao = 'sem_premissa_distribuicao'`.

Variante com estouro (com premissa): acrescentar título 7904, vencimento 2026-10-20, competência 2026-09-10, 600000.00 em aberto. `custo_lancado = 1100000.00`, `remanescente_sem_titulo = 0.00`, `estimativa_conclusao = 1100000.00`, `desvio = 100000.00`, `posicao.estouro_orcamento = 100000.00`, `posicao.custo_a_incorrer = 0.00`, `custo_sem_titulo_distribuido_total = 0.00`.

## C10 Categoria não mapeada e dado ausente diferente de zero

Nível staging. Referência 2026-06-10. Mapeamento `('titulo_pagar', '2.01.001') -> materiais`. Critério do tenant A: `percentual_conclusao`. T1 sem itens de orçamento.

Títulos em T1, todos em aberto, vencimento 2026-07-10:

| título | conta_origem | competência | valor_original |
| --- | --- | --- | --- |
| 7911 | `9.99.999` | 2026-05-05 | 2000.00 |
| 7912 | nula | 2026-05-06 | 1000.00 |
| 7913 | `2.01.001` | 2026-05-07 | 7000.00 |
| 7914 | `2.01.001` | nula | 500.00 |

Contrato ativo 5801 em T1 com `data_venda = 2026-05-01` e a parcela 5801/1 PM, vencimento 2026-07-10, saldo 1000.00.

Esperado:

| Consulta | Valor |
| --- | --- |
| `pendencia_classificacao` `('titulo_pagar', '9.99.999')` | `quantidade_lancamentos = 1`, `valor_envolvido = 2000.00`, `participacao = 0.190476`, `primeira_competencia = 2026-05-01` |
| `pendencia_classificacao` `('titulo_pagar', conta nula)` | `quantidade_lancamentos = 1`, `valor_envolvido = 1000.00`, `participacao = 0.095238` |
| `pendencia_classificacao` com `conta_origem = '2.01.001'` | nenhuma linha |
| `dre_mensal` T1 2026-05 | `valor_total_lancado = 10000.00`, `valor_com_categoria = 7000.00`, `cobertura = 0.700000`, `sem_categoria = -3000.00`, `custo_obra_incorrido = -7000.00` |
| `dre_mensal` T1 `competencia` nula, `sem_data_competencia` | -500.00 |
| `dre_mensal` T1 2026-06 `deducoes` | 0.00, disponível (zero conhecido) |
| `reconhecimento_obra_mensal` T1 2026-05 | `disponivel = false`, `motivo = 'orcamento_ausente'`, `poc` nulo, `custo_incorrido_acumulado = 7000.00` |
| `custo_obra_resumo` T1 | `orcamento_vigente`, `remanescente_sem_titulo`, `estimativa_conclusao`, `desvio`, `orcamento_original`, `compromissos_nao_faturados` todos nulos; `motivo = 'orcamento_ausente'`; `cobertura_classificacao = 0.714286` |
| `posicao_financeira_obra` T1 | `custo_orcado = 0.00` (compatibilidade), `orcamento_carregado = false` |
| `carteira_recebiveis` 5801/1 | `situacao = 'a_vencer'`, `dias_atraso` nulo (não zero) |
| Como FA, `insert into app.mapa_conta_origem` de `('titulo_pagar', '9.99.998') -> venda_imoveis` | erro `23514` |

Ao mapear `9.99.999` para `materiais`, a linha some de `pendencia_classificacao` e a `cobertura` de maio passa a 0.900000.

## C11 Reprocessamento sem duplicar

Nível raw. Payloads de C02 e de C08 juntos, referência 2026-02-28. Chamar `staging.recarregar(tenant A)` duas vezes.

| Consulta após a segunda chamada | Valor |
| --- | --- |
| `count(*)` de `staging.recebimento` do tenant A | 3 |
| `count(*)` de `staging.parcela_receber` | 2 |
| `count(*)` de `staging.titulo_pagar` | 4 |
| `count(*)` de `staging.titulo_pagar_apropriacao` | 5 |
| `count(*)` de `staging.pagamento` | 5 |
| `sum(valor)` de `staging.pagamento` | 1650.05 |
| `count(*)` de `app.centro_custo` com `tipo = 'empresa'` no tenant A | 1 |
| Regravar os mesmos payloads em `raw.registro` com `on conflict do nothing` e recarregar | mesmas contagens e somas |

Também: `scripts/carregar_demo.py` rodado duas vezes seguidas deixa as mesmas contagens em todas as tabelas de staging (conferir com `count(*)` antes e depois).

## C12 Usuário sem acesso a outra obra ou tenant

Nível raw: payloads de C08 no tenant A e, no tenant B, um título `{"billId": 7999, "dueDate": "2026-02-10", "originalAmount": 100.00, "balanceAmount": 0, "buildingsCosts": [{"buildingId": 9001, "amount": 100.00}], "payments": [{"paymentDate": "2026-02-10", "amount": 100.00}]}` recarregado para o tenant B. Referência 2026-02-28.

| Quem | Consulta | Esperado |
| --- | --- | --- |
| GA | `select distinct centro_custo_id from marts.fluxo_caixa_mensal` | só T1 |
| GA | `count(*)` de `staging.pagamento` | 1 |
| GA | `count(*)` de `app.centro_custo` | 1 |
| GA | `count(*)` de `marts.custo_obra_categoria` com centro diferente de T1 | 0 |
| GA | `marts.simular_fluxo(T2, '{}')` | 0 linhas |
| GA | `insert into app.mapa_conta_origem` no tenant A | erro `42501` |
| GA | `app.registrar_versao_projecao(T1, 'teste')` | erro `42501` |
| GA | `insert into app.liberacao_financiamento` em T1 | erro `42501` |
| DA | `select * from staging.titulo_pagar` | erro `42501` (sem grant) |
| DA | `count(*)` de `app.centro_custo` | 3 (T1, T2, EA) |
| DA | `update app.versao_planejamento set descricao = 'x'` | erro `42501` |
| DB | `count(*)` de `staging.pagamento` | 1 (só o do tenant B) |
| DB | linhas de `carteira_recebiveis`, `custo_obra_resumo`, `dre_mensal`, `fluxo_projetado_mensal`, `financiamento_contrato`, `liberacao_status` com `tenant_id` do tenant A | 0 em cada |
| FA | `insert into app.mapa_conta_origem (tenant_id, tipo_origem, conta_origem, categoria_codigo, autor) values (A, 'titulo_pagar', '2.01.001', 'materiais', '<DA>')` | aceito; `autor` gravado é FA; uma linha nova em `app.auditoria_alteracao` com `autor = FA` e `operacao = 'insert'` |
| GA | `count(*)` de `app.auditoria_alteracao` | 0 |

## C13 Unidades não vendidas não geram liberação

Nível staging. Referência 2026-09-15. T2 com 10 unidades (92001 a 92010); 92001 a 92003 vendidas (`situacao = 'V'`), as outras `D`. Contratos 6301, 6302 e 6303, um por unidade vendida, cada um com `valor = 250000.00`, `valor_financiado = 100000.00` e uma parcela FI de 100000.00 com vencimento 2027-03-10 em aberto. Sem etapa cadastrada.

| Consulta | Valor |
| --- | --- |
| `count(*)` de `financiamento_contrato` em T2 | 3 |
| `count(*)` de `recebivel_projetado` FI em T2 | 3 |
| `fluxo_projetado_mensal` T2 2027-03 `previsto_financiamento_pendente` | 300000.00 |
| idem `previsto_financiamento_elegivel` | 0.00 |
| Como FA, liberação nível `contrato` com `contrato_id_origem = 6399` (não existe) | erro `23514` |
| Como FA, liberação nível `contrato` sem `contrato_id_origem` | erro `23514` |
| Como FA, etapa para `contrato_id_origem = 6399` | erro `23514` |

## C14 Venda sem financiamento elegível não vira entrada bancária automática

Nível staging. Referência 2026-09-15. Contratos em T2:

| contrato | valor | valor_financiado | parcela | vencimento | saldo | etapa |
| --- | --- | --- | --- | --- | --- | --- |
| 6401 | 200000.00 | 180000.00 | FI | 2027-01-10 | 180000.00 | nenhuma; `data_repasse` nula |
| 6402 | 250000.00 | 200000.00 | FI | 2027-01-10 | 200000.00 | `elegivel`, sem pendência, sem data prevista |
| 6403 | 150000.00 | 0.00 | PM | 2027-01-10 | 150000.00 | não se aplica |

| Consulta | Valor |
| --- | --- |
| `financiamento_contrato` 6401 | `financiamento_pendente` |
| `financiamento_contrato` 6402 | `financiamento_elegivel` |
| `financiamento_contrato` 6403 | sem linha |
| `fluxo_projetado_mensal` T2 2027-01 | `previsto_financiamento_elegivel = 200000.00`, `previsto_financiamento_pendente = 180000.00`, `previsto_direto = 150000.00`, `saldo_mes = 530000.00` |
| idem `caixa_gerado_acumulado` e `caixa_gerado_acumulado_conservador` | 530000.00 e 350000.00 |
| `resumo_projecao_obra` T2 `financiamento_pendente_total` | 180000.00 |

Variantes: etapa de 6402 com `pendencia = true` e motivo "documentação do comprador" leva 6402 para `financiamento_pendente` e o pendente de janeiro para 380000.00. `data_repasse = 2026-09-01` em 6401 leva 6401 para `financiamento_elegivel` (pergunta P9).

## C15 Contratos com valores diferentes sem rateio uniforme

Nível staging. Referência 2026-09-15. Em T2, contratos 6501, 6502 e 6503 com parcela FI em aberto de 100000.00, 150000.00 e 250000.00, vencimento 2027-02-10, todos com etapa `elegivel` e `data_prevista_liberacao = 2026-11-10`. Operação `7b000000-0000-4000-8000-000000000015` em T2, `credito_producao`, `valor_contratado = 1000000.00`, `percentual_retencao = 0.05`. Liberação nível `empreendimento` prevista de 500000.00 em 2026-12-10.

| Consulta | Valor |
| --- | --- |
| `financiamento_contrato` `saldo_financiamento_aberto` | 6501 100000.00; 6502 150000.00; 6503 250000.00 (nenhum 166666.67) |
| `recebivel_projetado` `data_prevista` dos três | 2026-11-10 |
| `fluxo_projetado_mensal` T2 2026-11 `previsto_financiamento_elegivel` | 500000.00 |
| idem 2027-02 | 0.00 |
| `fluxo_projetado_mensal` T2 2026-12 `credito_producao_previsto` | 500000.00 |
| `liberacao_status` da liberação de empreendimento | `contrato_id_origem` nulo |

## C16 Medição aprovada sem recebimento fica fora do realizado

Nível staging. Referência 2026-09-15. Em T1: operação `7b000000-0000-4000-8000-000000000016`, `credito_producao`, `valor_contratado = 1000000.00`, `percentual_retencao = 0.05`. Medição 1 aprovada em 2026-08-20, `valor_elegivel = 200000.00`. Liberação L1, nível `empreendimento`, `medicao_id` da medição 1, `valor_previsto = 200000.00`, `data_prevista = 2026-09-05`, `situacao = 'prevista'`.

| Consulta | Valor |
| --- | --- |
| `liberacao_status` L1 | `situacao_efetiva = 'atrasada'`, `dias_atraso = 10` |
| `fluxo_projetado_mensal` T1, qualquer mês | `credito_producao_recebido = 0.00` e `credito_producao_previsto = 0.00` |
| `fluxo_caixa_mensal` T1 | nenhuma entrada realizada |
| `saldo_operacao_credito` | `medido_elegivel = 200000.00`, `liberado_recebido = 0.00`, `elegivel_nao_liberado = 200000.00`, `previsto_aberto = 200000.00`, `retencao_prevista = 50000.00`, `limite_antes_retencao = 950000.00`, `saldo_liberavel = 950000.00`, `saldo_nao_programado = 750000.00` |
| `explicacao_desvio` T1 2026-09 | uma linha `liberacao_prevista_vencida`, `quantidade = 1`, `valor = 200000.00`, `origem_dado = 'complemento_manual'` |

## C17 Liberação parcial respeitando saldo e limite

Nível staging. Referência 2026-09-15. Operação igual à de C16 (id `7b000000-0000-4000-8000-000000000017`), sem medição.

| liberação | nível | valor_previsto | data_prevista | situação | recebido |
| --- | --- | --- | --- | --- | --- |
| L1 | empreendimento | 300000.00 | 2026-07-05 | recebida | 300000.00 em 2026-07-10, `vinculo_tipo = 'lancamento_manual'`, `vinculo_chave = 'extrato-2026-07-10-001'` |
| L2 | empreendimento | 600000.00 | 2026-10-10 | prevista | |

| Consulta ou ação | Esperado |
| --- | --- |
| `saldo_operacao_credito` | `retencao_prevista = 50000.00`, `limite_antes_retencao = 950000.00`, `liberado_recebido = 300000.00`, `previsto_aberto = 600000.00`, `saldo_liberavel = 650000.00`, `saldo_nao_programado = 50000.00`, `excede_limite = false` |
| `fluxo_projetado_mensal` T1 2026-07 `credito_producao_recebido` | 300000.00 |
| `fluxo_projetado_mensal` T1 2026-10 `credito_producao_previsto` | 600000.00 |
| Inserir L3 prevista 150000.00 (soma 1050000.00) | erro `23514` |
| Inserir L3 prevista 100000.00 (soma 1000000.00) | aceito; `excede_limite = true`, `saldo_nao_programado = 0.00` |
| Inserir L4 recebida com `vinculo_tipo = 'lancamento_manual'` e a mesma `vinculo_chave` de L1 | erro `23505` |
| Sem L3, inserir L5 nível `lote` (`descricao_lote = 'Lote teste'`), `valor_previsto = 50000.00`, recebida 50000.00 em 2026-08-01 com `vinculo_tipo = 'recebimento'` e `vinculo_chave = '6601|1|1'` | aceito; `credito_producao_recebido` de 2026-08 continua 0.00, porque o dinheiro já estaria em `staging.recebimento` |

## C18 Nova venda simulada entra pelo cronograma

Nível staging. Referência 2026-09-15. T2 com quatro unidades `D` (92101 a 92104), sem tabela de preço, com `staging.unidade_valor.valor_sugerido` 200000.00, 220000.00, 240000.00 e 260000.00. Sem contratos nem títulos. Ticket = 920000.00 / 4 = 230000.00.

Premissas:

```json
{"novas_vendas": [{"competencia": "2026-10-01", "quantidade": 2}], "desconto_tabela": 0.05,
 "composicao": {"entrada": 0.10, "parcelas_mensais": 0.30, "quantidade_parcelas_mensais": 3, "financiamento": 0.60},
 "meses_ate_liberacao_financiamento": 4}
```

Cálculo: V = round(2 × 230000.00 × 0.95, 2) = 437000.00. Entrada 43700.00 em outubro. Financiamento 262200.00 em outubro + 4 = fevereiro de 2027. Parcelas: 437000.00 - 43700.00 - 262200.00 = 131100.00, em 3 de 43700.00 (novembro, dezembro, janeiro).

`marts.simular_fluxo(T2, premissas)`:

| competencia | novas_vendas_unidades | novas_vendas_valor | entradas_novas_vendas_direta | entradas_novas_vendas_financiamento | caixa_gerado_acumulado |
| --- | --- | --- | --- | --- | --- |
| 2026-09-01 | 0 | 0.00 | 0.00 | 0.00 | 0.00 |
| 2026-10-01 | 2 | 437000.00 | 43700.00 | 0.00 | 43700.00 |
| 2026-11-01 | 0 | 0.00 | 43700.00 | 0.00 | 87400.00 |
| 2026-12-01 | 0 | 0.00 | 43700.00 | 0.00 | 131100.00 |
| 2027-01-01 | 0 | 0.00 | 43700.00 | 0.00 | 174800.00 |
| 2027-02-01 | 0 | 0.00 | 0.00 | 262200.00 | 437000.00 |

A coluna `premissas` traz `"atraso_liberacao_bancaria_meses": 0`, `"deslocamento_cronograma_meses": 0`, `"fator_cronograma": 1` e os demais padrões preenchidos. Nenhuma tabela muda (contar linhas de `app.projecao_mensal` e do staging antes e depois).

Variantes:

| Premissa alterada | Esperado |
| --- | --- |
| `quantidade = 6` | outubro `novas_vendas_unidades = 4`, `novas_vendas_valor = 874000.00`, entrada 87400.00, parcelas de 87400.00, financiamento 524400.00 em 2027-02, `aviso = 'vendas_limitadas_ao_estoque'` |
| `quantidade_parcelas_mensais = 7` | parcelas de 18728.57 de novembro de 2026 a abril de 2027 e 18728.58 em maio de 2027 (131100.00 no total) |
| `atraso_liberacao_bancaria_meses = 2` | financiamento de 262200.00 em 2027-04 |
| `composicao.entrada = 0.09` (soma 0.99) | erro `22023` |
| `novas_vendas[0].competencia = "2026-08-01"` | erro `22023` |
| `'{}'` | `caixa_gerado_acumulado` igual ao de `fluxo_projetado_mensal` em todos os meses (R16) |

## C19 Cancelamento muda a projeção sem apagar o recebido

Nível staging. Referência 2026-09-15. Contrato 6901 em T1 (`valor = 100000.00`, `data_venda = 2026-03-01`), sem etapa:

| parcela | condição | vencimento | valor_original | saldo | recebimentos |
| --- | --- | --- | --- | --- | --- |
| 1 | AT | 2026-03-01 | 20000.00 | 0 | 2026-03-01: 20000.00 |
| 2 | PM | 2026-10-10 | 10000.00 | 10000.00 | nenhum |
| 3 | FI | 2027-03-10 | 70000.00 | 70000.00 | nenhum |

| Consulta | Esperado |
| --- | --- |
| `fluxo_projetado_mensal` T1 | 2026-03 `recebido_direto = 20000.00`; 2026-10 `previsto_direto = 10000.00`; 2027-03 `previsto_financiamento_pendente = 70000.00` |
| `simular_fluxo(T1, '{"cancelar_contratos": [6901]}')` | 2026-03 `recebido = 20000.00`; `carteira_prevista = 0.00` em todos os meses; `caixa_gerado_acumulado` do último mês 20000.00 |
| Depois de `update staging.contrato_venda set situacao = '3', data_distrato = '2026-09-10' where id_origem = 6901` | `fluxo_projetado_mensal` 2026-03 `recebido_direto = 20000.00`; nenhum mês com `previsto_direto` ou `previsto_financiamento_*` diferente de 0.00 |
| idem, `resumo_receitas_obra` T1 | `contratos_distratados = 1`, `saldo_distratado = 80000.00`, `recebido_direto = 20000.00`, `vgv_contratado_ativo = 0.00` |
| idem, `carteira_recebiveis` 6901/2 e 6901/3 | `cancelada_distrato` |

## C20 Dado agregado sem falsa precisão por unidade

Nível staging. Referência 2026-09-15. T2 com a operação de C15 e uma liberação nível `empreendimento` recebida de 500000.00 em 2026-08-20, `vinculo_tipo = 'lancamento_manual'`, `vinculo_chave = 'extrato-2026-08-20-001'`. Contratos de C15.

| Consulta | Esperado |
| --- | --- |
| `count(*)` de `liberacao_status` com `nivel = 'empreendimento'` e `contrato_id_origem` não nulo | 0 |
| `hasnt_column('marts', 'financiamento_contrato', 'valor_liberado')` e `hasnt_column('marts', 'carteira_recebiveis', 'valor_liberado')` | verdadeiro |
| `fluxo_projetado_mensal` T2 2026-08 `credito_producao_recebido` | 500000.00, numa linha da obra |
| `financiamento_contrato` `recebido_financiamento` dos três contratos | 0.00 cada (a liberação agregada não é distribuída) |

## C21 Versão anterior da projeção fica preservada

Nível staging. Referência 2026-09-15. T1 sem orçamento, com o título 8101 (vencimento 2026-10-10, competência 2026-09-01, 1000.00 em aberto).

1. Como FA: `v1 := app.registrar_versao_projecao(T1, 'Projeção de setembro')`.
2. Como dono: acrescentar a apropriação do título 8102 (vencimento 2026-10-20, 500.00 em aberto).
3. Como FA: `v2 := app.registrar_versao_projecao(T1, 'Projeção revisada')`.

| Consulta | Esperado |
| --- | --- |
| `app.versao_planejamento` de T1 | 2 linhas, `numero` 1 e 2, `tipo = 'projecao'`, `data_referencia = 2026-09-15`, `autor = FA` |
| `app.projecao_mensal` de v1 | 2 linhas (2026-09 e 2026-10); 2026-10 `a_pagar = 1000.00`, `caixa_gerado_acumulado = -1000.00` |
| `app.projecao_mensal` de v2, 2026-10 | `a_pagar = 1500.00`, `caixa_gerado_acumulado = -1500.00` |
| `comparativo_projecao` T1 2026-10 | `versao_original_numero = 1`, `original_total_saidas = 1000.00`, `atual_total_saidas = 1500.00`, `original_caixa_gerado_acumulado = -1000.00`, `atual_caixa_gerado_acumulado = -1500.00`, `diferenca_caixa_acumulado = -500.00`, `realizado_saidas` nulo |
| Como DA, `update app.versao_planejamento` ou `delete from app.projecao_mensal` | erro `42501` |
| Como GA, `select count(*) from app.versao_planejamento` | 2 (leitura liberada na obra dele) |

## C22 Percentual de conclusão com números conhecidos, e o mesmo caso sem critério

Nível staging. Referência 2026-02-20. Mapeamentos no tenant A: `2.01.001 -> materiais`, `2.02.001 -> tributos_receita`, `2.03.001 -> corretagem`, `2.04.001 -> despesas_administrativas`, `2.05.001 -> despesas_financeiras`. Critério do tenant A: `metodo = 'percentual_conclusao'`, inserido por FA.

T1: 10 unidades (91001 a 91010). Item de orçamento `01` com 2000000.00. Contratos 7001 a 7004, um por unidade 91001 a 91004, `valor = 250000.00` cada, `data_venda = 2026-01-15`.

Títulos em T1, todos em aberto, vencimento 2026-03-10:

| título | conta | competência | valor |
| --- | --- | --- | --- |
| 8201 | 2.01.001 | 2026-01-20 | 200000.00 |
| 8202 | 2.01.001 | 2026-02-10 | 300000.00 |
| 8203 | 2.02.001 | 2026-02-11 | 5000.00 |
| 8204 | 2.03.001 | 2026-02-12 | 10000.00 |
| 8205 | 2.04.001 | 2026-02-13 | 3000.00 |
| 8206 | 2.05.001 | 2026-02-14 | 2000.00 |

Cálculo: custo total estimado = maior entre 2000000.00 e 500000.00 (custo de obra lançado) = 2000000.00. Janeiro: POC = 200000 / 2000000 = 0,1; receita acumulada = 1000000 × 0,1 = 100000.00; fração vendida 4/10; custo reconhecido acumulado = 200000 × 0,4 = 80000.00. Fevereiro: POC = 500000 / 2000000 = 0,25; receita acumulada 250000.00; custo acumulado 200000.00.

`reconhecimento_obra_mensal` T1:

| competencia | custo_incorrido_acumulado | poc | vgv_ativo_fim_mes | fracao_vendida | receita_reconhecida_acumulada | receita_reconhecida_mes | custo_reconhecido_acumulado | custo_reconhecido_mes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-01-01 | 200000.00 | 0.100000 | 1000000.00 | 0.400000 | 100000.00 | 100000.00 | 80000.00 | 80000.00 |
| 2026-02-01 | 500000.00 | 0.250000 | 1000000.00 | 0.400000 | 250000.00 | 150000.00 | 200000.00 | 120000.00 |

`dre_mensal` T1 (`valor_mes`):

| linha | 2026-01 | 2026-02 | acumulado em 2026-02 |
| --- | --- | --- | --- |
| receita_bruta | 100000.00 | 150000.00 | 250000.00 |
| deducoes | 0.00 | -5000.00 | -5000.00 |
| receita_liquida | 100000.00 | 145000.00 | 245000.00 |
| custo_imovel_vendido | -80000.00 | -120000.00 | -200000.00 |
| resultado_bruto | 20000.00 | 25000.00 | 45000.00 |
| despesas_comerciais | 0.00 | -10000.00 | -10000.00 |
| despesas_administrativas | 0.00 | -3000.00 | -3000.00 |
| resultado_financeiro | 0.00 | -2000.00 | -2000.00 |
| resultado_gerencial | 20000.00 | 10000.00 | 30000.00 |
| custo_obra_incorrido | -200000.00 | -300000.00 | -500000.00 |

Fevereiro: `valor_total_lancado = 320000.00`, `cobertura = 1.000000`. `dre_periodo('2026-01-01', '2026-02-01', T1)`: `resultado_gerencial = 30000.00`, `receita_bruta = 250000.00`. `custo_obra_resumo` T1: `custo_lancado = 520000.00`, `remanescente_sem_titulo = 1480000.00` (pergunta P14: hoje toda conta da obra conta contra o orçamento).

Os três números de C01 aqui: VGV contratado 1000000.00; receita reconhecida acumulada em fevereiro 250000.00; recebido 0.00 (nenhum recebimento cadastrado).

Variante com distrato: contrato 7003 com `situacao = '3'` e `data_distrato = 2026-02-10`. Janeiro não muda. Fevereiro: `vgv_ativo_fim_mes = 750000.00`, `fracao_vendida = 0.300000`, receita acumulada = 750000 × 0,25 = 187500.00, `receita_reconhecida_mes = 87500.00`, custo acumulado = 500000 × 0,3 = 150000.00, `custo_reconhecido_mes = 70000.00`, `resultado_bruto = 12500.00`, `resultado_gerencial = -2500.00`.

Variante sem critério (update para `metodo = 'nao_definido'`): em janeiro e fevereiro, as linhas `receita_bruta`, `receita_liquida`, `custo_imovel_vendido`, `resultado_bruto` e `resultado_gerencial` têm `disponivel = false`, `motivo = 'criterio_nao_validado'`, `valor_mes` e `valor_acumulado` nulos. `deducoes = -5000.00`, `despesas_comerciais = -10000.00` e `custo_obra_incorrido = -300000.00` em fevereiro continuam disponíveis. `reconhecimento_obra_mensal`: `poc` nulo, `custo_incorrido_acumulado` 200000.00 e 500000.00. `dre_mensal_consolidado` como DA em fevereiro, `resultado_gerencial`: `disponivel = false`, `motivo = 'criterio_nao_validado'` (EA não tem evento). `validado_por` e `validado_em` nulos.

## C23 Desvio contra a meta

Nível staging. Referência 2026-09-15. Como FA: `app.registrar_versao_meta(T1, 'Meta de agosto', '[{"competencia": "2026-08-01", "unidades": 3, "valor_contratado": 900000.00}]')`. Contrato 7101 em T1, `valor = 300000.00`, `data_venda = 2026-08-12`, com a parcela 7101/1 AT de 30000.00, vencimento 2026-08-12, recebida no mesmo dia (garante a linha de agosto no fluxo projetado).

| Consulta | Esperado |
| --- | --- |
| `explicacao_desvio` T1 2026-08 | uma linha `vendas_abaixo_meta`, `quantidade = -2`, `valor = -600000.00`, `origem_dado = 'versao_planejamento'` |
| `visao_gerencial_mensal` T1 2026-08 | `meta_unidades = 3`, `vendas_unidades = 1`, `meta_valor_contratado = 900000.00`, `vendas_valor = 300000.00` |
| `explicacao_desvio` T1 2026-07 | nenhuma linha (sem meta, sem evento) |

## Mapa dos casos para os arquivos de teste

| Caso | Arquivo pgTAP |
| --- | --- |
| C02, C03 (parte de staging), C07, C08, C11 | `supabase/tests/eventos_financeiros.sql` |
| C12 (staging e views da 0007) | `supabase/tests/isolamento_eventos.sql` |
| C01, C03 (DRE), C04, C05 (receitas), C06, C10, C22 | `supabase/tests/dre_gerencial.sql` |
| C04 e C05 (financiamento), C13, C14, C15, C16, C17, C20 | `supabase/tests/financiamento_medicoes.sql` |
| C09, C18, C19, C21, C23, C12 (planejamento) | `supabase/tests/planejamento_projecoes.sql` |
| Todos, recalculados sem olhar o código das views | `supabase/tests/revisao_independente.sql` |
