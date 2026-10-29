# Carga só REST: migration 0040 (15/10/2026)

Trabalho para a construtora sem Bulk, que é a primeira tarefa da entrega 1 se o Braga confirmar hoje que o piloto não tem o pacote Ultimate. Nada foi aplicado no xwqw e nada foi commitado. Decisão completa no ADR 0021.

## O que mudou

| Arquivo | Mudança |
| --- | --- |
| `supabase/migrations/0040_financeiro_so_rest.sql` | Função nova `staging.recarregar_financeiro_rest(uuid)`: lê `bills`, parcelas, rateio, extrato, parcelas a receber por título e itens de orçamento por planilha e grava em `titulo_pagar`, `rateio_titulo`, `pagamento`, `parcela_receber`, `recebimento` e `item_orcamento`. Não cria tabela nem view. `security definer`, `search_path = ''`, `revoke` de public, anon e authenticated. |
| `scripts/carregar_origem.py` | Duas tarefas no `PLANO_SO_REST`: parcelas a receber, uma chamada por título do contrato (rodízio semanal mais os alterados, os com recebimento no extrato e os avisados pelo webhook), e orçamento por planilha, relido a cada 7 dias ou depois de aviso do webhook. O sub-recurso vazio do título grava só o código, para o grupo ser trocado inteiro. A recarga chama a função nova logo depois de `staging.recarregar`. Aviso de parcela a receber no caminho só REST deixa de ser descartado. |
| `scripts/campos_permitidos.py` | Listas para `receivable-bills/installments` (sem portador nem boleto) e `building-cost-estimations/items` (só obra, planilha, código, descrição e valor). |
| `scripts/sondar_origem.py`, `scripts/conferir_amostras.py` | A sondagem pede parcelas e rateio de um título e a planilha e os itens de orçamento de uma obra; a conferência compara essas respostas com as listas da carga. |
| `supabase/tests/financeiro_so_rest.sql` | 31 testes pgTAP. |
| `scripts/testes/teste_carga_so_rest.py` | 11 testes com a API falsa e o banco local. |
| `teste_carregar_origem.py`, `teste_carga_contabil.py`, `teste_consumo_fila.py` | Repositório falso com o método novo; ordem da recarga; aviso de parcela a receber no caminho só REST. |
| `docs/decisoes/0021-financeiro-so-rest.md`, `CONTEXTO.md` | ADR novo; a linha do `buildingsCosts[0]` estava desatualizada desde a 0012. |

`carregar_demo.py` e os dados da demo não mudaram. A Carga noturna roda só `carregar_demo.py`, que não chama a função nova, e a demo não tem dado REST em raw. A demo de amanhã não é afetada.

## Testes rodados

Num Supabase local próprio (projeto `carga-so-rest-0040`, portas 564xx), sem tocar nos bancos locais das outras sessões, depois de `supabase db reset` com 0001 a 0040 e o seed:

- `supabase test db`: 30 arquivos, 725 testes, todos passam.
- Python (`unittest discover` com `DATABASE_URL` no banco local): 221 testes. Passam todos os da carga. Ficam 2 erros que existiam antes da mudança: `teste_complementos` precisa de `dados/income.json`, que o git ignora e não está no worktree. Rodando com o arquivo da pasta principal, um teste do gerador da demo falha comparando os arquivos commitados com o `income.json` local; a mudança não toca nesse código nem nesses dados.
- Três noites seguidas pelo caminho só REST contra o banco local (`TesteBancoLocalSoRest`): raw e as seis tabelas de staging ficam com a mesma contagem depois da segunda e da terceira noite.
- O teste pegou um erro antes da entrega: parcela sem valor e sem situação virava saldo zero, como se estivesse quitada (`greatest` ignora nulo). Corrigido; agora fica nulo.
- Painel não foi tocado, então a build não foi rodada.

## O que falta conferir com a base real

As fixtures de parcela, rateio, extrato, parcela a receber e orçamento seguem a documentação. Do formato real só se conhece o cabeçalho de `bills` (sondagem de 11/10). Antes de ligar o piloto:

1. Liberar `accounts-statements` para o usuário de API (deu 403) e rodar `python scripts/sondar_origem.py --plano carga` no terminal do Mac, depois `python scripts/sanitizar_amostras.py` e `python scripts/conferir_amostras.py`.
2. Conferir no extrato o `type` (Income e Expense, ou Entrada e Saída), o sinal do valor e como vem o estorno, que hoje somaria como pagamento.
3. Conferir se `installmentNumber` do extrato é o `installmentId` da parcela a receber, se `balanceDue` é saldo em aberto e se a API devolve parcela quitada.
4. Conferir os textos de `situation` da parcela a pagar e o significado de `status` (S ou N) no título.
5. Conferir se os itens da planilha incluem as etapas e se o código de obra do orçamento é o do centro de custo.
6. Conciliar uma obra com o controller: pago e a pagar do mês, recebido do mês e custo orçado contra os relatórios do ERP.

## Riscos que ficam abertos

- Cota: a noite comum do caminho só REST pede cerca de 190 chamadas para o tamanho do piloto. Não cabe no Free (100 por dia). A primeira carga do a pagar pede 1 + 2 chamadas por título dos últimos 400 dias, numa transação só; num pacote menor que isso ela recomeça todo dia e não termina. Na primeira execução, reduzir `ORIGEM_JANELA_INICIAL_DIAS` ou dividir a carga inicial em lotes.
- Bulk: dois `outcome` do mesmo título (título com mais de uma parcela) derrubam `staging.recarregar` no banco local, porque a fração do rateio passa de 1. E o Bulk liga a parcela a receber ao título a receber, não ao contrato. Os dois valem para o primeiro cliente com Bulk, não para a demo.

## Revisão de segurança

Uma revisão independente leu a mudança contra a seção de segurança do CLAUDE.md:

- RLS: a 0040 não cria tabela. As seis tabelas em que ela grava já têm `enable` e `force` com política por tenant e obra (0002 e 0012), sem `using (true)`.
- Views: nenhuma criada ou alterada.
- Função: `security definer` com `search_path = ''`, todo objeto do projeto qualificado, `revoke` de public, anon e authenticated, conferido no pgTAP. Toda leitura de `raw.registro`, `app.centro_custo` e staging filtra `tenant_id = p_tenant`, inclusive a junção com `sales-contracts` no recebimento.
- LGPD: as listas novas não levam portador, boleto, cliente nem texto livre; o extrato continua sem `description`, `documentNumber` e `statementTypeNotes`.
- Carregador: SQL parametrizado, nenhum log novo com dado, e os IDs que entram no caminho da URL são inteiros. Aviso do webhook só faz buscar título que já é de contrato do tenant.

Ela achou um problema funcional, corrigido antes da entrega: com uma obra sem percentual (ou percentuais somando menos de 100), a outra obra ficava com o título inteiro. Agora a fração é o percentual sobre 100, com teste. Também foram feitos três ajustes menores: o código do título a pagar passa por inteiro antes de entrar na URL, a lista do orçamento perdeu quatro campos que o staging não lê, e a fixture usa um marcador neutro no lugar de nome de pessoa.

Fica registrado, sem correção nesta entrega: num tenant que misture Bulk e REST, o `contrato_id_origem` da parcela a receber guarda números de origens diferentes (título no Bulk, contrato no REST), e uma colisão faria o REST perder a parcela sem aviso. É o mesmo de-para pendente do Bulk citado no ADR 0021.

## Comandos para o João

Em 20/10 esta entrega foi juntada no worktree `apis-liberadas-9451ef`, depois da sondagem pelo usuário de API (Basic na v1) e do testador de credencial, e vai em três commits: sondagem, testador e este. Os `scripts/sondar_origem.py` e `scripts/conferir_amostras.py` entraram por merge em três vias com a sondagem nova.

Aplicar no xwqw só depois do commit e antes de rodar `carregar_origem.py` contra ele, porque o carregador novo chama a função da 0040. Rodar numa pasta vinculada ao xwqw; a CLI da pasta principal estava vinculada ao projeto antigo, então confira o vínculo antes:

```bash
supabase db push
```
