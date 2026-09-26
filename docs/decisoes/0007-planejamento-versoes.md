# 0007 Planejamento em versões imutáveis e simulação que não grava

**Contexto.** O gestor quer comparar o planejado com o previsto de hoje e testar cenários de venda e de atraso. Projeção que se sobrescreve perde a referência, e custo sem título distribuído por uma curva inventada dá aporte falso.

**Decisão.** A migration 0013 grava metas e fotografias da projeção em versões numeradas, sem update nem delete para o usuário. `marts.fluxo_projetado_mensal` separa realizado, carteira direta, financiamento elegível e pendente, crédito à produção, títulos e custo sem título, e chama o acumulado de "caixa gerado acumulado", nunca saldo bancário. Custo sem título só é distribuído por premissa cadastrada com fonte; sem ela, fica num total à parte e a necessidade de aporte aparece como parcial. `marts.simular_fluxo` é determinística, parte do mesmo fluxo e devolve as premissas junto com o resultado.

**Consequência.** A comparação usa a primeira versão do mês como original. Simulação com premissas vazias reproduz o fluxo projetado, o que serve de teste. Os números novos de migration (0011 a 0013) precisam ser confirmados contra a reserva do PT-09.
