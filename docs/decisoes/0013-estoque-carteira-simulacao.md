# 0013 Estoque, carteira, alertas e simulação de venda

**Contexto.** VSO, estoque e cobertura do orçamento existiam no banco (0015) e só apareciam pelo assistente. A visão geral mostrava cada obra solta, sem a soma da carteira nem o que pedia atenção. Faltava responder, na tela, "e se o estoque vendesse neste ritmo?".

**Decisão.** A migration 0024 cria quatro views e duas funções. Todas rodam como quem consulta (`security_invoker`), e o RLS de staging decide quais obras entram:

- `marts.estoque_tipologia` e `marts.estoque_obra`: estoque é disponível, reservada e proposta, como no VGV da 0011. O ritmo é o `vendas_media_6m` da cobertura, para as duas telas não darem prazos diferentes.
- `marts.posicao_carteira`: soma as obras que o usuário vê. A exposição máxima da carteira sai do saldo acumulado das obras juntas, mês a mês, e não da soma das exposições, porque os piores meses de cada obra não coincidem. Na demo, R$ 32,7 mi contra R$ 37,2 mi somando uma a uma.
- `marts.alertas_obra`: uma linha por alerta que disparou. Os limites ficam no SQL: estouro de orçamento acima de zero, repasse vencido, vencido do comprador acima de 5% da carteira direta, pago mais de 10 pontos à frente do físico (o mesmo da tela de execução) e estoque que, no ritmo recente, não acaba antes da entrega. O texto fica no painel.
- `marts.simular_venda_estoque` e `marts.resumo_venda_estoque`: vendem o estoque a partir do mês que vem, no ritmo e com o desconto escolhidos, pelo preço de tabela de hoje. Proposta e reserva vendem primeiro, depois a unidade mais barata. Cada venda recebe do banco a fração que o repasse tem nos contratos ativos da obra. A parte do comprador entra em parcelas iguais até o mês anterior à entrega, e o repasse entra nas chaves. Depois da entrega, a parte do comprador entra no mês da venda e o repasse dois meses depois. O ponto de partida é o fluxo de caixa da migration 0012.

O painel ganha a faixa da carteira e a lista "Pede atenção" na visão geral, os alertas na tela da obra, as telas de estoque e de simulação e um relatório da obra com largura de folha A4, para imprimir ou salvar em PDF.

**Consequência.** A simulação herda a limitação do fluxo: custo do orçamento que ainda não virou título não entra, então a exposição simulada é otimista quando há muito custo a incorrer. Os parâmetros da simulação são uma lista fechada (1, 2, 4, 6 ou 8 unidades por mês; 0, 5% ou 10% de desconto), para a URL não levar valor arbitrário ao banco. Na carga da demo só a Parque das Águas dispara "pago à frente do físico", de propósito, para a apresentação mostrar o alerta numa obra e não nas outras. Os limites dos alertas foram escolhidos olhando só os dados da demo; o controller do piloto precisa revê-los.
