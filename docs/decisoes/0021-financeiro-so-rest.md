# 0021 Financeiro e orçamento pelo caminho só REST

**Contexto.** O Bulk só existe a partir do pacote Ultimate, e na sondagem de 11/10/2026 a rota dele na v2 deu 404. Sem Bulk, a carga já gravava em raw `bills`, `bills/installments`, `bills/buildings-cost`, `accounts-statements` e `accounts-balances`, mas nenhuma função de staging lia esses endpoints: a obra ficava sem a pagar, pago, recebido e caixa. O orçamento e as parcelas a receber saíam só do Bulk. A 0039 já tinha resolvido o contrato (ADR 0020).

O que se sabe do formato: `bills` respondeu 200 na sondagem e é só o cabeçalho do título (`id`, `totalInvoiceAmount`, `issueDate`, `installmentsNumber`, `status`), sem vencimento, saldo nem rateio. As parcelas (`/bills/{id}/installments`) trazem `installmentNumber`, `dueDate`, `amount` e `situation` (Não paga, Parcialmente paga, Totalmente paga), sem valor pago. O rateio (`/bills/{id}/buildings-cost`) vem em `percentage`. O extrato deu 403 para o usuário de teste. Parcelas a receber, rateio, parcelas a pagar e orçamento por planilha não foram pedidos na sondagem. Tudo isso, menos o cabeçalho do título, vem da documentação.

**Decisão.** A migration 0040 cria `staging.recarregar_financeiro_rest`, que o carregador chama logo depois de `staging.recarregar`, na mesma transação. Ela grava nas mesmas tabelas que o Bulk preenche, e marts, painel e assistente não mudam. A carga da demo não chama a função, porque a demo não tem dado REST.

A pagar. O título do REST vira uma linha em `staging.titulo_pagar`. O pago vem do extrato (`type` Expense, ou `statementOrigin` CP quando o tipo falta), ligado pelo título e pelo número da parcela; cada movimento vira uma linha em `staging.pagamento`. Parcela totalmente paga tem saldo zero; não paga, o valor inteiro; nos outros casos, o valor menos o pago no extrato. Sem valor, o saldo fica nulo, para não parecer quitado. O vencimento do título é o da primeira parcela em aberto (o da última, se quitado). O rateio vem em percentual do título, então a fração de cada obra é o percentual sobre 100 (sobre a soma, se ela passar de 100). A obra fora do painel, a parte de departamento e a linha sem percentual ficam com a parte delas, e nenhuma obra recebe a de outra. Percentual ausente vale 100 só quando o título tem uma obra.

A receber. Sem Bulk, a parcela só sai por título (`/accounts-receivable/receivable-bills/{id}/installments`), e o título vem do `receivableBillId` do contrato. A parcela entra em `staging.parcela_receber` com o código do contrato em `contrato_id_origem`, o mesmo que `contrato_venda` guarda. `balanceDue` é tratado como saldo sem correção. O recebimento vem do extrato (`type` Income, ou origem CR). Parcela que a API deixou de devolver e tem recebimento no extrato entra com o recebido e saldo zero, para o recebido não sumir do fluxo de caixa.

Orçamento. `/building-cost-estimations/{obra}/sheets` e, por planilha, `.../sheets/{id}/items`, uma obra por vez. Só o item folha entra; a etapa que agrupa outros itens somaria o valor deles duas vezes. O mesmo código em planilhas diferentes vira uma linha com a soma.

Bulk na frente. Como na 0039, o REST só entra na obra que não recebeu nada pelo Bulk naquele assunto. No a pagar a regra olha as obras do rateio: título do REST com alguma obra que tem título do Bulk fica de fora, e o título que veio pelos dois caminhos fica com a versão do Bulk.

Carga incremental. As parcelas a receber relidas numa noite são as dos títulos nunca lidos, dos contratos alterados, dos que tiveram recebimento no extrato, dos avisados pelo webhook (`RECEIVABLE_INSTALLMENT_*`, `RECEIPT_PROCESSED`, que no caminho só REST deixam de ser descartados) e um sétimo dos demais, em rodízio. O orçamento não tem filtro de alteração e é relido uma vez por semana, ou na noite seguinte a um aviso `BUILDING_COST_ESTIMATION_*`. Título lido sem parcela, ou sub-recurso de título a pagar vazio, grava só o código do título; assim o grupo é trocado inteiro e o que sumiu na origem sai de raw.

`accounts-balances` continua só em raw. O caixa do painel é recebido menos pago por obra, e o saldo bancário é da empresa, sem obra.

**Chamadas por noite.** Estimativa para o piloto (5 obras, 300 contratos, 20 títulos a pagar alterados por dia, 2 empresas no balancete):

| Tarefa | Complexidade | Noite comum | Primeira carga |
|---|---|---|---|
| Cadastros, saldo, contratos, mapa, medições | já existentes | cerca de 45 | cerca de 45 |
| Balancete | O(e × m × 2 × p) | cerca de 36 | cerca de 500 |
| Extrato | O(p) | 1 a 2 | cerca de 10 |
| A pagar | 1 + 2 por título alterado | cerca de 41 | 1 + 2 por título dos 400 dias |
| A receber | 1 por título da noite, O(c/7 + a) | cerca de 58 | c, cerca de 300 |
| Orçamento | O(o × (1 + s × p)) | cerca de 5 (35 por semana) | cerca de 35 |
| Total | | cerca de 190 | milhares, conforme o volume de títulos a pagar |

Limites diários de REST: 100 a 10.000 do Free ao Enterprise, 30.000 no Business. A noite comum não cabe no Free (100) e cabe a partir de um pacote de algumas centenas por dia, desde que as outras integrações do cliente, o CRM incluído, deixem essa folga. A primeira carga do a pagar é o ponto fraco: a tarefa grava numa transação só e, se a cota acabar no meio, recomeça do zero na noite seguinte. Com 3.000 títulos em 400 dias ela pede cerca de 6.000 chamadas e nunca termina num pacote menor que isso. Antes do piloto, reduzir `ORIGEM_JANELA_INICIAL_DIAS` na primeira execução ou dividir a primeira carga em lotes.

**Consequência.** O teste `financeiro_so_rest.sql` cobre rateio 60/40, com obra fora do painel e com uma obra sem percentual, percentual, valor e data ausentes, parcela paga em parte, extrato sem `type`, a parcela quitada que só aparece no extrato, item folha do orçamento, a obra com Bulk que não recebe o REST, a recarga repetida e os privilégios da função. `teste_carga_so_rest.py` cobre as tarefas novas com a API falsa e roda três noites seguidas contra o banco local sem duplicar nada em raw nem em staging.

Falta conferir com amostra real, porque as fixtures seguem a documentação:

- o sinal e o `type` do extrato (Income e Expense, ou Entrada e Saída), e como aparece o estorno, que hoje somaria como pagamento;
- se `installmentNumber` do extrato é o mesmo `installmentId` da parcela a receber;
- se `balanceDue` é o saldo em aberto ou o valor original da parcela, e se a API devolve parcela quitada;
- os textos de `situation` da parcela a pagar e o que é `status` (S ou N) no título;
- se os itens da planilha de orçamento incluem as etapas, e se o código de obra do orçamento é o mesmo do centro de custo.

A sondagem passa a pedir parcelas e rateio de um título, a planilha e os itens de orçamento de uma obra (`sondar_origem.py --plano carga`), e `conferir_amostras.py` compara as respostas com a lista de campos da carga. O extrato só responde depois que o recurso for liberado para o usuário de API.

Fica aberto também: o Bulk liga `parcela_receber.contrato_id_origem` ao `billId` do `income`, que no ERP real é o título a receber e não o contrato. Na demo os dois números coincidem; com dado real, as views que cruzam parcela com contrato (distrato, repasse) precisam do mesmo de-para que a 0040 faz no caminho só REST. E `staging.titulo_pagar` guarda uma linha por título enquanto o `outcome` vem por parcela. Num banco local, dois `outcome` do mesmo título derrubaram `staging.recarregar`: a fração do rateio soma as duas parcelas, passa de 1 e viola a checagem de `rateio_titulo`. A demo não tem título com duas parcelas; o primeiro cliente com Bulk terá.
