---
name: crm-vendas-api
description: APIs e webhooks do CRM de vendas imobiliárias que fica antes do ERP (CV CRM, 625 endpoints, levantamento de 28/09/2026). Use ao planejar ou escrever carga de leads, reservas, repasses, espelho de unidades, tabelas de preço, comissões ou distratos vindos do CRM, ao cruzar dado do CRM com o do ERP, ao decidir se um indicador comercial (funil, repasse real, previsão de venda) cabe no painel, ou ao cadastrar webhook do CRM.
---

# API do CRM de vendas

Referência completa em `referencias/api_webhooks.md` (1,5 MB). Nunca ler inteiro. Índice de endpoints nas linhas 252 a 1050; detalhe por grupo depois disso (`### <grupo>`, endpoint em `#### \`MÉTODO /caminho\``).

```bash
grep -n '^#### `GET /v1/cvdw/repasses' .claude/skills/crm-vendas-api/referencias/api_webhooks.md
sed -n 20617,20700p .claude/skills/crm-vendas-api/referencias/api_webhooks.md
```

## Onde entra no projeto

O CRM é uma segunda origem, opcional por tenant. Hoje o painel só lê o ERP. O que o CRM acrescenta e o ERP não tem:

| Indicador | Por que o ERP não basta | Rota do CRM |
|---|---|---|
| Repasse real (situação, assinatura, recurso liberado, valor financiado) | O ERP só mostra a parcela `FI`; a regra "FI é repasse" é chute e o cenário de atraso desloca o repasse sem saber em que etapa ele está | `/v1/cvdw/repasses` (tem `banco`, `data_assinatura_de_contrato`, `data_recurso_liberado`, `valor_financiado`, `data_alteracao_status`), `/v1/cvdw/repasses/historico/situacoes` |
| Funil comercial (lead, reserva, venda, distrato) | O ERP só vê a venda depois do contrato | `/v1/cvdw/leads`, `/leads/conversoes`, `/leads/perdas`, `/reservas`, `/vendas`, `/distratos` |
| Reserva em andamento | Unidade reservada no CRM ainda aparece disponível no ERP até o contrato | `/v1/cvdw/reservas` e `/reservas/historico/situacoes` |
| Tempo de cada etapa | Não existe no ERP | `/reservas/workflow/tempo`, `/repasses/workflow/tempo` |

O que continua vindo do ERP: financeiro, orçamento, contratos, parcelas, tabela de preço oficial. Se os dois divergirem num valor de contrato, vale o ERP.

## Como ligar CRM e ERP

- Reserva: `/v1/cvdw/reservas/sienge` devolve em lote `idsienge_reserva`, `codigointerno` e `titulo_erp` (linhas 18093 a 18163). Por reserva: `/v1/comercial/reservas/{id}/erp/sienge` (linha 6916).
- Venda e repasse: `contrato_interno` e `numero_contrato`, mais `codigointerno_*` de empreendimento, etapa, bloco e unidade (linhas 7336 a 7360).
- Unidade: campos `*_int` (`idunidade_int`, `idempreendimento_int`). A doc diz só "identificador no sistema externo"; na integração padrão guardam o código do ERP. Confirmar na amostra do piloto antes de usar como chave.

No banco, a chave continua `id_origem` com uma coluna que diz a origem. Nada de coluna com nome do CRM ou do ERP fora de `raw` e do staging.

## Carga

- Autenticação v1: headers `email` e `token` do usuário de integração (Painel do Gestor, Usuários Administrativos, Token). O e-mail tem de existir no mesmo domínio consultado. v3: `POST /api/v3/auth/token`, Bearer de 6 horas.
- Base: `https://{dominio}.cvcrm.com.br/api/...`. Rota `/api/cvio/...` é legada; usar `/api/v1/...`.
- CVDW é contratado à parte. Todas as rotas aceitam `pagina`, `registros_por_pagina` (até 500) e `a_partir_data_referencia` (linhas 17317 a 17321). Carga incremental por `a_partir_data_referencia` com a última `referencia_data` gravada; cada registro traz a sua.
- Limite: 200 req/min na REST, 429 bloqueia o minuto seguinte. CVDW tem limite menor, sem número publicado. Tratar como lote noturno, uma requisição por vez.
- `/v1/financeiro/repasses` (não CVDW) pagina por `limit` e `offset`, filtra só por `ID`, `documento` e `empreendimento`, sem filtro de data. Serve para reconsulta pontual, não para carga.
- Log de toda chamada em `https://{dominio}.cvcrm.com.br/cvio` por cerca de 30 dias. Guardar o número da requisição CVIO no log de erro da carga.

## Dado pessoal que sai antes de gravar em `raw`

O CVDW devolve muito dado pessoal. O descarte acontece no carregador, antes do `insert`:

- Leads: `nome`, `email`, `telefone`, `documento_cliente`, `cep_cliente`, `renda_familiar`, `score`, `profissao`, `cidade`, `estado`.
- Reservas e vendas: `documento_cliente`, `cliente`, `email`, `renda`, `sexo`, `idade`, `estado_civil`, `cep_cliente`.
- Repasses v1: `nome_cliente`, `telefone_cliente`, `email_cliente`, `data_nascimento_cliente`.
- Unidades: `situacao_nome` no CVDW é nome de pessoa. No mapa de disponibilidade, `documento_bloqueio` é CPF.
- `/v1/cvdw/pessoas` e sub-rotas (`bancarios`, `financeiros`, `patrimoniais`) ficam fora.

Lista de campos permitidos por rota é mais segura que lista de proibidos: campo novo que a API passar a devolver não entra sem revisão.

## Webhooks

- Cadastro por funcionalidade e gatilho: `POST /api/v1/integracoes/webhooks` com `nome`, `funcionalidade`, `endereco`, `gatilho`, `ativoPainel` e filtro opcional por empreendimento. Gatilhos do ambiente em `GET /api/v1/integracoes/webhooks/gatilhos`; mudam de cliente para cliente.
- Funcionalidades úteis aqui: `RS` reservas, `RP` repasse, `UN` unidades, `EV` espelho de vendas, `CV` contrato de venda.
- O disparo não traz segredo, assinatura nem cabeçalho de autenticação, e o payload não está documentado. Nossa rota trata o corpo como aviso não confiável: valida um token longo na URL, grava só o ID e reconsulta a API. Nunca grava o corpo recebido como dado.
- Para o MVP, a carga noturna por `a_partir_data_referencia` resolve. Webhook só se o piloto pedir atualização no mesmo dia.

## Antes de usar

- O CVDW e o usuário de integração são do cliente. Não usar credencial de outra empresa nem ambiente de trabalho de João.
- A integração usa a API contratada pelo próprio cliente para entregar análise que o CRM não oferece. Não reproduz função do CRM.
