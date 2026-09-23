# 0001 Cobertura do orçamento no lugar de ponto de equilíbrio

**Contexto.** A view `marts.break_even_obra` dividia o VGV vendido pelo orçamento e chamava o resultado de ponto de equilíbrio. Ponto de equilíbrio depende de quando o dinheiro entra e sai, de impostos e de despesas fora do orçamento. A conta mostrava outra coisa. A coluna de meses usava a média de vendas sem os meses zerados, então também saía otimista.

**Decisão.** A migration 0006 remove `marts.break_even_obra` e cria `marts.cobertura_orcamento_obra`, com custo orçado, VGV contratado, fração de cobertura, ticket médio e vendas que faltam para cobrir o orçamento. A coluna de meses fica de fora até o PT-06 refazer a VSO sobre um calendário contínuo.

**Consequência.** O painel e o assistente passam a dizer "cobertura do orçamento" e deixam claro que isso não é caixa. A pergunta sobre dinheiro próprio da obra fica com a exposição máxima de `marts.posicao_financeira_obra`.
