# 0002 Staging por evento financeiro

**Contexto.** A 0002 guardava uma linha por parcela e por título e lia só o primeiro elemento de `receipts`, `payments` e `buildingsCosts`. Parcela quitada em dois recebimentos perdia o segundo, título pago em duas vezes caía inteiro na data do primeiro pagamento e título dividido entre obras ia todo para a primeira.

**Decisão.** A migration 0012 cria `staging.recebimento`, `staging.pagamento` e `staging.rateio_titulo`, uma linha por evento. `marts.fluxo_caixa_mensal` lê o realizado desses eventos e distribui cada pagamento, e o saldo a pagar, pela fração da obra no rateio. A fração é gravada na carga porque o gerente enxerga só a linha da obra dele. Título e pagamento aparecem para quem vê pelo menos uma obra do rateio. Título sem `buildingsCosts` fica com obra nula e não soma em obra nenhuma; a carga avisa quantos são.

**Consequência.** O total de cada obra passa a bater com a soma dos eventos, e as colunas das views não mudam. A despesa da empresa continua em staging para uma futura visão da empresa. O gerente vê o valor total de um título dividido com outra obra, mas só a parte da obra dele entra nos números.
