# 0006 Financiamento, medições e liberações como complemento manual

**Contexto.** A origem não traz medição bancária, RAE nem etapa do financiamento do comprador. Sem regra, a mesma entrada do banco poderia aparecer como parcela, liberação e medição ao mesmo tempo.

**Decisão.** A migration 0012 guarda operação de crédito da obra, etapa do financiamento por contrato, medição bancária e liberação em tabelas `app.*` próprias, escritas só por diretor e financeiro, com autor, fonte e auditoria. Dinheiro realizado vem só de `staging.recebimento`; crédito à produção sem registro na origem entra por liberação recebida com vínculo único a um lançamento. Liberação do contrato classifica prazo e elegibilidade da parcela FI, não soma valor. Medição aprovada nunca é caixa. Liberação de empreendimento ou lote não é rateada por unidade.

**Consequência.** A parcela FI projetada se divide em financiamento elegível e pendente. A soma das liberações de uma operação nunca passa do valor contratado. Retenção e modalidade dependem do contrato de cada banco (perguntas P6 a P9).
