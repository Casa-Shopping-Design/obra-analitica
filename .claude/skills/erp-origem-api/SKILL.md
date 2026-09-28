---
name: erp-origem-api
description: APIs REST, Bulk-Data e webhooks do ERP de origem (Sienge Plataforma, 369 endpoints e 100 eventos, levantamento de 28/09/2026 a partir da documentação pública). Use ao escrever ou revisar o carregador (sondar_origem.py, carregar_origem.py), ao ajustar o staging contra o payload real, ao planejar carga incremental, ao escolher endpoint para um mart novo, ao dimensionar consumo contra o pacote do cliente ou ao desenhar recepção de webhook.
---

# API do ERP de origem

Referência completa em `referencias/api_webhooks.md` (1,1 MB). Nunca ler inteiro. Índice nas linhas 49 a 435, webhooks de 436 a 1160, Bulk-Data de 1163 a 1186, detalhe por módulo depois (`### 5. <módulo>`, endpoint em `#### \`MÉTODO /caminho\``).

```bash
grep -n '^#### `GET /income' .claude/skills/erp-origem-api/referencias/api_webhooks.md
sed -n 15242,15370p .claude/skills/erp-origem-api/referencias/api_webhooks.md
```

## Acesso

- REST: `https://api.sienge.com.br/{subdominio}/public/api/v1/{recurso}`. Bulk: `.../public/api/bulk-data/v1/{recurso}`. No projeto a base vem de `ORIGEM_URL_BASE`.
- Autenticação documentada: Basic com usuário e senha de API criados pelo admin do cliente em Integrações, Usuários de APIs.
- **Divergência aberta:** `scripts/sondar_origem.py` pede token OAuth em `group/v2/auth/token` (client_id, client_secret, `grant_type=client_credentials`) e chama `group/v2/{recurso}`. Nada disso aparece na documentação pública. Antes do PT-09, confirmar com a sondagem real qual dos dois o piloto aceita.

## Limites, e por que eles mudam o plano

| | REST | Bulk |
|---|---|---|
| Por minuto, por subdomínio | 200 | 20 |
| Por dia, pacote Free a Enterprise | 100 a 10.000 | 10 a 200 |
| Por dia, Business / Ultimate / Infinity | 30.000 / 75.000 / 200.000 | 600 / 28.800 / 30.000 |

- **Bulk-Data só existe a partir do pacote Ultimate.** A carga planejada usa Bulk para `income`, `outcome`, `sales`, `bank-movement` e orçamento. Construtora em pacote menor precisa do caminho só REST abaixo, que é mais lento e consome cota diária.
- O limite é compartilhado com as outras integrações do cliente (o CRM de vendas incluído). Pausa entre chamadas, uma requisição por vez, 429 com `Retry-After`.
- Pergunta obrigatória ao piloto: qual pacote contratou e quanto da cota diária as outras integrações já consomem. A tela Integrações, Consumo de APIs mostra isso.

## Endpoints por mart

| Mart | Bulk (Ultimate) | Só REST |
|---|---|---|
| Recebido e a receber | `GET /income` | `accounts-receivable/receivable-bills` exige `customerId` (percorre cliente a cliente); parcelas em `.../{id}/installments` sem as baixas. Recebimentos efetivos por `GET /accounts-statements` (`type` Income, `billId`, `installmentNumber`) |
| Pago e a pagar | `GET /outcome` | `GET /bills/by-change-date`, parcelas em `/bills/{id}/installments` (sem valor pago), rateio em `/bills/{id}/buildings-cost`; pagamentos em `/accounts-statements` |
| Contratos, VSO, VGV | `GET /sales` | `GET /sales-contracts` com `modifiedAfter`; traz `paymentConditions[]` e `financialInstitutionNumber`/`Date` |
| Caixa | `GET /bank-movement` | `GET /accounts-balances` (`balanceDate`), `/checking-accounts` |
| Orçamento | `GET /building-cost-estimation-items` | `/building-cost-estimations/{buildingId}/sheets` e `.../items`, uma obra por vez |
| Inadimplência | `GET /defaulters-receivable-bills`, `/by-aging` | parcelas vencidas do a receber |
| Unidades e preço | | `GET /units`, `/price-tables` (`units[].indexedQuantity`), `/indexers` (só último valor) |

No caminho só REST, parcela e rateio por título é N+1 de rede. Aceitável porque roda de madrugada e a API não oferece lote; o limite é a cota diária, não o banco. Medir chamadas por carga e gravar em `app.carga_execucao`.

## Campos que decidem regra de negócio

- `income`: `paymentTerm.id/description` e `bearerId` separam repasse de pagamento direto. **Não existe `financialInstitution*` em `income`**; esse campo está só no contrato (`sales` e `sales-contracts`).
- `income.receipts[]`: `paymentDate`, `netAmount`, `grossAmount`, juros, multa, desconto, `bankMovements[]`.
- `outcome.buildingsCosts[]`: `buildingId`, `buildingUnitId`, `costEstimationSheetId`, `rate`. É um array de rateio; a 0012 já explode todos os elementos em `staging.rateio_titulo` (decisão 0002).
- `outcome` exige `correctionIndexerId` e `correctionDate`.
- `selectionType` em `income` e `outcome`: `I` emissão, `D` vencimento, `P` pagamento, `B` competência.

## Carga incremental

- `income` aceita `changeStartDate`: só títulos e parcelas alterados desde a data (até hoje). É o filtro da carga diária.
- `outcome` não tem filtro de alteração. Opções: janela por `selectionType=P` dos últimos dias para pagamentos, mais `GET /bills/by-change-date` (REST) para descobrir títulos alterados e buscá-los por `/outcome/by-bills`.
- `sales-contracts` e `customers` aceitam `modifiedAfter`.
- Bulk assíncrono (`_async=true`, `_asyncChunkMaxSize`, consulta em `/async/{id}` e `/async/{id}/result/{chunk}`) guarda o resultado por 24 horas. Chunk baixado e gravado com o mesmo `hash_registro` não duplica se a carga cair no meio.

## Rotas ainda não usadas que valem a pena

- `GET /real-estate-map` (Mapa Imobiliário Consolidado): por mês, VGV, POC, recebido acumulado, custo orçado, incorrido e a incorrer, margem. Serve de conferência automática do VGV e do custo do painel, e resolve em parte a pendência do custo sem título.
- `GET /building-projects/progress-logs` e itens: medição física acumulada por item. Resolve "custo realizado à frente da execução física".
- `GET /building-projects/{b}/sheets/{u}/tasks`: curva planejada mensal por tarefa, ligada ao item de orçamento. Dá a distribuição mensal do custo a incorrer.
- Bulk `business-budget`: orçado mensal por centro de custo.
- Bulk `defaulters-receivable-bills/by-aging`: faixa de atraso por cliente e unidade.
- `GET /commissions`: custo comercial por obra.
- Fora do MVP por dado pessoal: `current-debit-balance` (consulta por CPF/CNPJ), `customer-income-tax`, `customer-financial-statements`.
- Reserva de unidade só tem `POST` e `PATCH`, sem consulta. Reserva em andamento vem do CRM (skill `crm-vendas-api`).

## Webhooks

- Cadastro por `POST /hooks` com `url`, `events` e `token` opcional, enviado como Bearer no header. Sem assinatura HMAC. O token é a única autenticação; gerar um longo por tenant e comparar em tempo constante.
- Cabeçalhos: `x-sienge-tenant`, `x-sienge-event`, `x-sienge-hook-id`, `x-sienge-id` (id único do evento, chave de idempotência), `user-agent: sienge-hooks`.
- Payload só com IDs. Espera 2,5 s pela resposta; depois tenta 5 vezes em cerca de 10 horas e descarta.
- Eventos úteis: `RECEIVABLE_INSTALLMENT_*`, `RECEIPT_PROCESSED`, `PAYMENT_INSTALLMENT_*`, `PAYMENT_RECEIPT_*`, `PAYMENT_BILL_UPDATED`, `SALES_CONTRACT_*`, `UNIT_*`, `COST_CENTER_*`, `BUILDING_COST_ESTIMATION_*`, `BANK_MOVEMENT_*` (não há GET REST por `bankMovementId`; só Bulk).
- Desenho que cabe no projeto: a Route Handler valida o token, grava `(tenant_id, x-sienge-id, evento, ids)` numa fila com chave única e responde 200 na hora. Quem busca o dado na API é a carga, não a rota. O webhook vira lista de IDs sujos para a carga seguinte, o que economiza cota em pacote sem Bulk. Painel continua sem chamar o ERP ao vivo.

## Cuidados

- Nome de campo do payload só em `raw` e nas funções de staging. Nada com o nome do ERP em tabela, coluna, variável ou arquivo.
- CPF, e-mail, telefone, renda e dado bancário saem no carregador, antes de gravar em `raw`.
- A rede das sessões do Claude bloqueia a API do ERP. Sondagem roda no terminal do Mac.
