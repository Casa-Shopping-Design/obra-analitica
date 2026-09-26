---
name: api-sienge
description: Mapa das APIs públicas do Sienge (REST v1, Bulk Data e autenticação) com cada endpoint, parâmetro e campo de resposta. Use sempre que for escrever ou revisar ingestão, staging, sondagem ou qualquer código que chame o ERP de origem, quando perguntarem se o Sienge tem um dado ou endpoint, que campo traz tal informação, como paginar, qual o limite de requisições, ou quando um campo do payload bruto precisar ser entendido. Consulte antes de afirmar que um endpoint existe.
---

# APIs do Sienge

Referência gerada a partir de https://api.sienge.com.br/docs/ por `scripts/atualizar_documentacao_apis.py`. Para atualizar, use a skill `atualizar-docs-apis`.

## Como consultar

1. `referencia/INDICE.md` lista cada API com número de operações e aponta para `referencia/apis/<nome>.md`.
2. Cada arquivo de API traz, por operação, os parâmetros (nome, onde vai, tipo, obrigatório), o corpo aceito e os campos da resposta achatados em caminhos como `results[].paymentConditions[].conditionType`.
3. Para achar um campo sem saber a API: `grep -rn "conditionType" .claude/skills/api-sienge/referencia/apis/`.
4. `referencia/MUDANCAS.md` diz o que mudou em cada raspagem. Mudança em endpoint que o projeto consome vem marcada como "usado pelo projeto".
5. `referencia/guias/` guarda as páginas de texto do portal quando ele as publica.

Se `referencia/apis/` estiver vazia, a raspagem ainda não rodou. Nesse caso vale só o que está na seção abaixo, e qualquer outro endpoint precisa ser conferido na documentação antes de entrar em código.

## O que o projeto já verificou

Levantado antes da raspagem (ver `CONTEXTO.md`). A referência gerada prevalece quando divergir.

- REST: `https://{tenant}.sienge.com.br/sienge-api/public/api/v1/` ou pelo gateway `https://api.sienge.com.br/{tenant}/public/api/v1/`. Autenticação Basic com usuário de API.
- Bulk Data: mesma base com `/bulk-data/v1/`. Aceita `_async=true`, entrega em partes e avisa por webhook ao terminar. O usuário de API precisa da permissão "Massive".
- Token OAuth: `scripts/sondar_origem.py` testa `group/v2/auth/token` (Basic com client e secret, `grant_type=client_credentials` e `tenant` no corpo) e chama `group/v2/{recurso}` com Bearer. Ainda sem resposta de base real.
- Limite relatado por terceiros: 200 requisições por minuto por conta, dividido com outras integrações da construtora (o CV CRM entra nessa conta). Estouro devolve 429. O REST pagina em até 200 registros por `limit` e `offset`.
- Endpoints em uso: REST `companies`, `cost-centers`, `enterprises`, `units`, `customers`, `sales-contracts`; Bulk `income`, `outcome`, `sales`, `defaulters-receivable-bills`, `bank-movement`, `building-cost-estimation-items`, `customer-extract-history`.
- Separação entre receita direta e repasse: `paymentConditions[].conditionType` em `sales` e `paymentTerm` em `income`. `financialInstitutionNumber` e `financialInstitutionDate` marcam repasse. Condição `FI` é tratada como repasse.
- Situação da unidade: D disponível, C reservada, P proposta, V, O e G vendida, R reserva técnica.

## Regras do repositório ao usar esta referência

- Nome de campo da API só aparece em `raw` e nas funções de staging. Tabela, coluna, variável e arquivo seguem nomes neutros em português (`id_origem`, `conta_origem`, `ORIGEM_URL_BASE`).
- Carga pagina, respeita o limite compartilhado, trata 429 com `Retry-After` e é incremental por data ou hash.
- CPF, renda, score e dados bancários ficam fora do MVP mesmo quando o endpoint os devolve.
- Painel e assistente nunca chamam o ERP ao vivo.
