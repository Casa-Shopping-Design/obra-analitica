# 0005 DRE gerencial por categoria, com reconhecimento desligado até validação

**Contexto.** O painel mostra caixa, mas o gestor também quer resultado por competência. A origem traz conta financeira (hipótese a verificar), não categoria gerencial, e o piloto ainda não disse como reconhece receita de venda de imóvel.

**Decisão.** A migration 0011 cria uma lista fixa de categorias gerenciais, um mapeamento por tenant de conta de origem para categoria (com autor e auditoria) e a view `marts.dre_mensal` em formato longo. Conta sem mapeamento fica em "Sem categoria" e na lista de pendências; nunca vira "outros". Receita e custo reconhecidos saem por percentual de conclusão só quando o financeiro valida esse critério; até lá, as linhas de receita, custo, resultado bruto e resultado gerencial aparecem como indisponíveis. Custo de obra vai para estoque e não é despesa do mês. A última linha se chama "Resultado gerencial do período".

**Consequência.** Deduções e despesas comerciais, administrativas e financeiras aparecem desde já pela competência. O resultado depende das perguntas P1 a P5 e P14 do contrato de dados. Não há coluna de orçamento no DRE, por falta de fonte comparável.
