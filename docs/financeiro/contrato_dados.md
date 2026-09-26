# Contrato de dados: eventos financeiros, DRE gerencial, receitas, despesas, financiamento e planejamento

As regras que variam por construtora ou por obra estão em `configuracao.md`, que complementa este contrato; onde os dois divergirem, vale `configuracao.md`.

Versão 1, 26/09/2026. Fonte de verdade para os agentes `banco_eventos` (migration 0007), `banco_dre` (0011), `banco_planejamento` (0012 e 0013), `painel_demonstrativos`, `painel_planejamento` e `revisor`. Nome de tabela, coluna, função, código de motivo e rótulo escritos aqui são finais. Quem precisar mudar um deles pede ao coordenador antes, porque outro agente depende do nome.

Casos de teste com valores calculados à mão: `docs/financeiro/casos_teste.md`. Decisões resumidas: ADRs 0002, 0005, 0006 e 0007 em `docs/decisoes/`.

## 0. Convenções

- Dinheiro em `numeric(18,2)`, índice em `numeric(18,6)`, percentual e fração em `numeric(9,6)` guardando fração (0,05 é 5%). Colunas antigas criadas como `numeric` sem precisão continuam como estão; toda coluna nova segue esta regra.
- Mês é sempre o primeiro dia do mês, tipo `date`, em coluna chamada `competencia`.
- `ref` nas fórmulas é `app.data_referencia()`. `mes_ref` é `date_trunc('month', ref)::date`. `proximo_mes` é `(date_trunc('month', ref) + interval '1 month')::date`, que em 15/12/2026 dá 01/01/2027.
- Vencido é `vencimento < ref`. O próprio dia da referência ainda é "a vencer". A regra vale para parcela, título e liberação.
- Sinal: views de caixa (`fluxo_*`, `recebimento_*`, `custo_*`) guardam valores positivos e o nome da coluna diz se é entrada ou saída. O DRE usa valor com sinal: receita positiva, custo e despesa negativos.
- `origem` de recebível: no staging continua `'direta'` ou `'repasse'` (coluna gerada da 0002). Nas views novas de marts a coluna `origem` vale `'direta'` ou `'financiamento'`, com `'repasse'` traduzido para `'financiamento'`. As views antigas mantêm `repasse` no nome das colunas.
- Nulo quer dizer "não se sabe" ou "não se aplica". Zero quer dizer "sabemos que é zero". Nenhuma view nova troca nulo por zero com `coalesce` numa coluna de valor sem dizer isso neste contrato.
- Motivo de indisponibilidade é um código em texto (lista na seção 9). O painel traduz o código em frase por `painel/lib/mensagens.ts`.
- Política de RLS padrão por obra, chamada aqui de **P-obra**:
  `using (tenant_id = (select app.tenant_atual()) and centro_custo_id in (select app.obras_permitidas()))`
- Política de escrita, chamada aqui de **P-escrita**, usada em `with check` de insert e em `using` e `with check` de update:
  `tenant_id = (select app.tenant_atual()) and centro_custo_id in (select app.obras_permitidas()) and (select app.perfil_atual()) in ('diretor', 'financeiro')`
- Política por tenant, chamada aqui de **P-tenant**: `using (tenant_id = (select app.tenant_atual()))`.
- Toda tabela nova: `enable` e `force row level security` na mesma migration, uma política permissiva por ação, `grant` só do que a política permite. Toda view nova: `with (security_invoker = true)` e `grant select ... to authenticated`. Toda função nova: `set search_path = ''`, nomes qualificados com schema no corpo, `revoke execute ... from public, anon` e `grant execute ... to authenticated` quando o usuário chama; `revoke ... from public, anon, authenticated` quando não chama.

## 1. Inventário do que existe hoje

### 1.1 Views e funções de marts

| Objeto | Criado em | Colunas | Fórmula e data que posiciona no tempo | Quem consome | Compatibilidade |
| --- | --- | --- | --- | --- | --- |
| `marts.fluxo_caixa_mensal` | 0005 | `tenant_id, centro_custo_id, competencia, entrada_direta_realizada, repasse_realizado, entrada_direta_prevista, repasse_previsto, entrada_direta_vencida, repasse_vencido, saida_realizada, saida_prevista, saida_vencida, saldo_mes, saldo_acumulado` | Realizado de entrada pelo mês de `data_recebimento` da parcela (hoje só o primeiro recebimento). Previsto e vencido pelo mês do vencimento, com saldo `coalesce(saldo_corrigido, saldo)`, contrato distratado fora, vencido quando `vencimento < current_date`. Saída realizada pelo mês do primeiro pagamento, valor `valor_original - saldo`. Saída prevista e vencida pelo vencimento, valor `saldo`. `saldo_mes` soma realizado e previsto de entrada e subtrai as três saídas; entrada vencida fica fora. `saldo_acumulado` é a soma corrida por obra | Tela da obra (`listarFluxoMensal`), perguntas `repasse-parque-6-meses` e `mes-mais-negativo-aurora`, catálogo do assistente, `fluxo_caixa_cenario`, `posicao_financeira_obra` | Manter nome, colunas, ordem e semântica. A 0007 troca as fontes (eventos) e `current_date` por `ref` |
| `marts.fluxo_caixa_cenario(p_meses_atraso integer default 0)` | 0005 | `centro_custo_id, competencia, entrada_direta, repasse, saida, saldo_acumulado` | Desloca só `repasse_previsto` em N meses | Tela da obra (`listarFluxoCenario`, cenários 0, 1, 3, 6) | Manter assinatura e colunas. Não é recriada: lê a view |
| `marts.posicao_financeira_obra` | 0005 | `tenant_id, centro_custo_id, obra, recebido_direto, recebido_repasse, a_receber_direto, a_receber_repasse, vencido_direto, repasse_atrasado, estoque_a_vender, pago, a_pagar, custo_orcado, custo_a_incorrer, estouro_orcamento, caixa_atual, exposicao_maxima, resultado_contratado, resultado_projetado` | Somas de `fluxo_caixa_mensal` por obra; `estoque_a_vender` de `mapa_unidades` (disponível, reservada, proposta); `custo_orcado` dos itens de orçamento; `custo_a_incorrer = greatest(custo_orcado - pago - a_pagar, 0)`; `estouro = greatest(pago + a_pagar - custo_orcado, 0)`; `caixa_atual = recebido_direto + recebido_repasse - pago`; `exposicao_maxima = -least(min(saldo_acumulado), 0)`; resultados somam todas as entradas contratadas (e o estoque, no projetado) e subtraem `greatest(custo_orcado, pago + a_pagar)` | Visão geral (cartões e `TabelaObras`), tela da obra, mapa de unidades (`estoque_a_vender`), perguntas `a-receber-aurora`, `exposicao-maxima`, `estouro-orcamento`, `a-receber-banco`, `mais-vencido`, `estoque-preco-hoje`, teste `isolamento_perfis.sql` (3 linhas para diretor, 1 para gerente) | Manter nome, as 19 colunas na ordem e a semântica. A 0007 acrescenta colunas no fim e ajusta `custo_a_incorrer`, `estouro_orcamento` e os resultados para o custo lançado (seção 3.1.9) |
| `marts.vso_mensal` | 0003 | `tenant_id, centro_custo_id, competencia, vendas, distratos, vgv_vendido` | Contagem por mês de `data_venda`; distrato cai no mês da venda (defeito conhecido, PT-06) | Pergunta `distratos-ano`, catálogo | Fora deste trabalho. Não recriar |
| `marts.estoque_atual` | 0003 | `tenant_id, centro_custo_id, tipologia, disponiveis, reservadas, propostas, vendidas, indisponiveis, total` | Contagem de `staging.unidade` por situação | Pergunta `unidades-disponiveis`, catálogo | Fora deste trabalho |
| `marts.mapa_unidades` | 0004 | `tenant_id, centro_custo_id, unidade_id, unidade, tipologia, area_privativa, situacao_origem, situacao, tabela, tabela_versao, quantidade_indexada, indice, indice_referencia, indice_valor, valor_contrato, data_venda, valor_tabela, valor_sugerido, data_valor_sugerido, valor, origem_valor, valor_m2` | Valor de hoje: contrato, senão tabela vigente vezes índice, senão valor sugerido. Usa `current_date` | Mapa de unidades, perguntas de preço e disponíveis, `posicao_financeira_obra`, `simular_fluxo` (0013) | Fora deste trabalho. `current_date` fica até o PT-06 |
| `marts.cobertura_orcamento_obra` | 0006 | `tenant_id, centro_custo_id, obra, custo_orcado, vgv_contratado, pct_cobertura, ticket_medio, unidades_para_cobrir` | VGV de contratos ativos sobre o orçamento | Pergunta `cobertura-parque`, catálogo, teste de isolamento | Manter colunas. A 0007 recria só para filtrar `tipo = 'obra'` |
| `marts.consolidado_centro_custo` | 0003 | `tenant_id, centro_custo_id, obra, receita_contratada, receita_recebida, saldo_a_receber, custo_orcado, custo_realizado, saldo_a_pagar` | Soma saldo de contrato distratado e lê `staging.titulo_pagar.centro_custo_id` | Ninguém (fora do catálogo; teste do painel proíbe o nome) | A 0007 remove com `drop view` |

### 1.2 Tabelas lidas pelo painel

- `app.centro_custo (id, nome)`: `listarObras`, `buscarObra`, `idsObrasPorNome`, `incluirNomeObra`. Depois da 0007 passa a ter uma linha `tipo = 'empresa'` por tenant, visível para diretor e financeiro. Toda lista de obras precisa filtrar `tipo = 'obra'` (pedido ao coordenador na seção 11).
- `app.usuario_tenant (perfil, tenant.razao_social)`: identidade.

### 1.3 Staging hoje

| Tabela | Chave | Fonte | Limitação que a 0007 corrige |
| --- | --- | --- | --- |
| `staging.unidade` | `(tenant_id, id_origem)` | `units` | nenhuma |
| `staging.contrato_venda` | `(tenant_id, id_origem)` | `sales` | lê só `units[0]` e `customers[0]`; não guarda condições de pagamento nem crédito associativo |
| `staging.parcela_receber` | `(tenant_id, contrato_id_origem, id_origem)` | `income` | lê só `receipts[0]`; parcela de obra não cadastrada some |
| `staging.titulo_pagar` | `(tenant_id, id_origem)` | `outcome` | lê só `buildingsCosts[0]` e `payments[0]`; título sem obra some; rateio vai inteiro para a primeira obra |
| `staging.item_orcamento` | `(tenant_id, centro_custo_id, codigo)` | `building-cost-estimation-items` | nenhuma |
| `staging.indice_valor`, `tabela_preco`, `tabela_preco_unidade`, `unidade_valor` | ver 0004 | `indexers`, `price-tables`, `units` | nenhuma |

## 2. Glossário de eventos

| Evento | O que é | Granularidade | Data que o posiciona | Fonte |
| --- | --- | --- | --- | --- |
| Venda contratada | Contrato de venda ativo (`situacao = '1'`). O valor é o VGV contratado. Não é receita nem caixa | Uma linha por contrato em `staging.contrato_venda` | `data_venda` (assinatura). Distrato pela `data_distrato` | Origem, endpoint `sales` |
| Parcela | Direito de receber uma parte do contrato numa data | Uma linha por parcela em `staging.parcela_receber` | Vencimento | Origem, `income` |
| Recebimento | Dinheiro que entrou por uma parcela. Estorno é recebimento de valor negativo | Uma linha por item de `receipts[]` em `staging.recebimento` | Data do recebimento (caixa) | Origem, `income.receipts[]` |
| Título a pagar | Obrigação lançada contra a construtora | Cabeçalho em `staging.titulo_pagar` (não exposto) | Vencimento para caixa; emissão para competência | Origem, `outcome` |
| Apropriação | Parte do título que pertence a uma obra e a uma conta de origem | Uma linha por obra do rateio e conta em `staging.titulo_pagar_apropriacao` | Competência (emissão) e vencimento | Derivada de `buildingsCosts[]` e da lista de contas do título |
| Pagamento | Dinheiro que saiu por um título, já rateado por apropriação | Uma linha por pagamento e apropriação em `staging.pagamento` | Data do pagamento (caixa) | Origem, `outcome.payments[]` |
| Custo lançado | Soma das apropriações de uma obra, pago ou não | Agregado por obra | Competência, ou total até a carga | Derivado |
| Desembolso | Soma dos pagamentos de uma obra | Agregado por obra e mês | Data do pagamento | Derivado |
| Ajuste de baixa | Parte do custo lançado que foi baixada sem sair dinheiro (desconto) menos o que saiu a mais (juros, multa) | Por apropriação | Sem data própria | Derivado: `valor_original - valor_pago - saldo` no título, rateado |
| Compromisso | Pedido de compra ou contrato de empreiteiro ainda sem título | Não existe | Não existe | Sem fonte hoje. Coluna presente e indisponível |
| Custo remanescente sem título | Parte do orçamento vigente que ainda não virou título | Por obra | Sem data até alguém cadastrar a distribuição mensal | `greatest(orçamento - custo lançado, 0)` |
| Receita reconhecida | Receita de venda que entra no DRE pelo critério escolhido | Por obra e mês | Competência | Derivada, só com `percentual_conclusao` validado |
| Custo reconhecido | Custo dos imóveis vendidos que entra no DRE | Por obra e mês | Competência | Derivado, só com `percentual_conclusao` validado |
| Liberação | Dinheiro que o banco solta: financiamento do comprador (nível contrato) ou crédito à produção (nível empreendimento ou lote) | Uma linha por liberação em `app.liberacao_financiamento` | Data prevista; data do recebimento quando recebida | Complemento manual |
| Medição | Vistoria do banco que mede o avanço da obra e define o valor elegível | Uma linha por medição em `app.medicao_bancaria` | Data da vistoria e da aprovação | Complemento manual (RAE) |

Regra geral: nenhuma view soma VGV com parcela, parcela com recebimento, nem medição com recebimento. Dinheiro realizado vem só de `staging.recebimento`, de `staging.pagamento` e, para crédito à produção sem registro na origem, de liberação recebida com vínculo `lancamento_manual`.

## 3. Objetos por migration

### 3.1 Migration 0007 `0007_eventos_financeiros.sql` (dono: `banco_eventos`)

#### 3.1.1 `app.data_referencia()`

```sql
create function app.data_referencia() returns date
language sql stable security invoker set search_path = '' as $$
  select coalesce(nullif(current_setting('app.data_referencia', true), '')::date,
                  (now() at time zone 'America/Sao_Paulo')::date)
$$;
revoke execute on function app.data_referencia() from public, anon;
grant execute on function app.data_referencia() to authenticated, service_role;
```

Só testes e reprocessamento preenchem `app.data_referencia` (`select set_config('app.data_referencia', '2026-12-15', true)`). O usuário da API não tem como chamar `set_config` porque `pg_catalog` não está exposto.

#### 3.1.2 `app.centro_custo` (alterada)

- `alter table app.centro_custo add column tipo text not null default 'obra' check (tipo in ('obra', 'empresa'))`.
- `alter column id_origem drop not null`.
- `check ((tipo = 'obra' and id_origem is not null) or (tipo = 'empresa' and id_origem is null))`, nome `centro_custo_tipo_origem`.
- Índice único parcial `centro_custo_empresa_unico on app.centro_custo (tenant_id) where tipo = 'empresa'`.
- Índice `(tenant_id, tipo)`.
- A migration insere a linha empresa de cada tenant existente: `insert into app.centro_custo (tenant_id, id_origem, nome, tipo) select id, null, 'Despesas sem obra', 'empresa' from app.tenant on conflict (tenant_id) where tipo = 'empresa' do nothing`. `staging.recarregar` faz o mesmo insert no começo, para tenant novo.
- RLS continua a da 0001. Diretor e financeiro enxergam a linha empresa por `app.obras_permitidas()`; gerente não, porque não tem vínculo.
- Nome exibido: "Despesas sem obra".

#### 3.1.3 `app.auditoria_alteracao` e gatilhos comuns

Criados na 0007 para que 0011 e 0012, feitas em paralelo, usem o mesmo mecanismo.

| Coluna | Tipo | Nulo | Significado |
| --- | --- | --- | --- |
| `id` | `bigserial` | não | chave |
| `tenant_id` | `uuid` | não | tenant do registro alterado |
| `tabela` | `text` | não | nome qualificado, ex. `app.mapa_conta_origem` |
| `registro_id` | `text` | não | chave primária do registro em texto; chave composta com as colunas unidas por `|` na ordem da chave |
| `operacao` | `text` | não | `insert`, `update` ou `delete` |
| `antes` | `jsonb` | sim | `to_jsonb(old)` |
| `depois` | `jsonb` | sim | `to_jsonb(new)` |
| `autor` | `uuid` | sim | `auth.uid()`; nulo quando quem altera é o carregador |
| `alterado_em` | `timestamptz` | não | `now()` |

Índice `(tenant_id, tabela, registro_id, alterado_em desc)`. RLS: select com `tenant_id = (select app.tenant_atual()) and (select app.perfil_atual()) in ('diretor', 'financeiro')`. Sem grant de insert, update ou delete para `authenticated`.

Funções de gatilho:

- `app.registrar_auditoria() returns trigger`, `security definer`, `set search_path = ''`, `revoke execute ... from public, anon, authenticated`. Grava uma linha em `app.auditoria_alteracao` por linha alterada. Usada em `after insert or update or delete ... for each row`. Recebe em `TG_ARGV` os nomes das colunas da chave.
- `app.definir_autor() returns trigger`, `security invoker`, `set search_path = ''`. Em `before insert or update`, força `new.autor := auth.uid()` e, se a tabela tiver a coluna, `new.atualizado_em := now()`. O valor de `autor` mandado pelo cliente é sempre ignorado.

#### 3.1.4 `app.situacao_parcela` e `app.situacao_carga`

```sql
create function app.situacao_parcela(p_saldo numeric, p_valor_recebido numeric, p_vencimento date,
                                     p_contrato_distratado boolean, p_referencia date) returns text
language sql immutable security invoker set search_path = '' as $$
  select case
    when coalesce(p_saldo, 0) > 0 and p_contrato_distratado then 'cancelada_distrato'
    when coalesce(p_saldo, 0) > 0 and p_vencimento < p_referencia then 'vencida'
    when coalesce(p_saldo, 0) > 0 then 'a_vencer'
    when coalesce(p_valor_recebido, 0) > 0 then 'quitada'
    else 'baixada_sem_recebimento'
  end
$$;
```

Grant execute a `authenticated`; revoke de `public, anon`. `p_saldo` recebe `coalesce(saldo_corrigido, saldo)`. É a única implementação da regra de situação: 0011 e 0012 chamam esta função, nunca reescrevem o `case`.

```sql
create function app.situacao_carga()
returns table (data_referencia date, ultima_carga_em timestamptz, horas_desde_carga numeric(9,1), desatualizada boolean)
language sql stable security definer set search_path = '' as $$ ... $$;
```

Lê `max(carregado_em)` de `raw.registro where tenant_id = app.tenant_atual()`. `horas_desde_carga = round(extract(epoch from now() - ultima_carga_em) / 3600, 1)`. `desatualizada = ultima_carga_em is null or now() - ultima_carga_em > interval '26 hours'` (regra da rota de saúde, plano 4.2). É `security definer` porque `raw` não é legível pelo usuário; devolve só o carimbo do tenant de quem chama. Grant execute a `authenticated`; revoke de `public, anon`. Índice novo `raw.registro (tenant_id, carregado_em desc)`. Quando o PT-08 criar `app.carga_execucao`, esta função passa a ler de lá sem mudar a assinatura.

#### 3.1.5 `staging.contrato_venda` (alterada) e `staging.contrato_unidade` (nova)

Colunas novas em `staging.contrato_venda`, no fim:

| Coluna | Tipo | Nulo | Leitura e significado |
| --- | --- | --- | --- |
| `valor_financiado` | `numeric(18,2)` | sim | soma de `paymentConditions[].totalValue` com `conditionType = 'FI'`. Zero quando a lista existe sem FI. Nulo quando o payload não traz `paymentConditions` |
| `credito_associativo` | `boolean` | sim | `associativeCredit`: `'S'` vira true, `'N'` vira false, outro valor ou ausente vira nulo |

`banco_repasse` e `data_repasse` continuam como estão e são, respectivamente, a instituição financeira e a data do financiamento que a origem informa (`financialInstitutionNumber`, `financialInstitutionDate`). Nas views novas elas aparecem como `instituicao_financeira` e `data_financiamento_origem`. Não se criam colunas duplicadas (objeção 2 do relatório). `unidade_id_origem` passa a ser a unidade com `main = true` em `units[]`; sem marcação, a de menor posição. `nome_cliente` continua lendo o comprador principal e nunca sai do staging.

Índice novo: `staging.contrato_venda (tenant_id, centro_custo_id, data_venda)`.

`staging.contrato_unidade` (uma linha por item de `units[]`):

| Coluna | Tipo | Nulo | Significado |
| --- | --- | --- | --- |
| `tenant_id` | `uuid` | não | |
| `centro_custo_id` | `uuid` | não | obra do contrato |
| `contrato_id_origem` | `integer` | não | `sales.id` |
| `sequencia` | `integer` | não | posição em `units[]` (`with ordinality`) |
| `unidade_id_origem` | `integer` | não | `units[].id` |
| `principal` | `boolean` | não | `units[].main`, ou a primeira quando nenhuma é marcada |

Chave `(tenant_id, contrato_id_origem, sequencia)`. Índice `(tenant_id, centro_custo_id)` e `(tenant_id, unidade_id_origem)`. RLS P-obra, grant select.

#### 3.1.6 `staging.parcela_receber` (alterada)

Colunas novas, no fim:

| Coluna | Tipo | Nulo | Leitura e significado |
| --- | --- | --- | --- |
| `data_emissao` | `date` | sim | `issueDate` |
| `numero_parcela` | `text` | sim | `installmentNumber`, ex. `3/24` |
| `conta_origem` | `text` | sim | código da conta quando a lista de contas da parcela (hipótese `receiptsCategories[].financialCategoryId`) tem exatamente um elemento; nulo quando falta ou tem mais de um |
| `id_origem_obra` | `integer` | sim | `projectId` como veio |
| `motivo_sem_obra` | `text` | sim | `obra_nao_cadastrada` quando `projectId` não existe em `app.centro_custo`; a parcela vai para o centro empresa |
| `valor_baixado_sem_caixa` | `numeric(18,2)` | não, default 0 | soma de recebimentos com `tipo_baixa = 'baixa_sem_caixa'` |

Colunas existentes que mudam de regra:

- `valor_recebido = coalesce(sum(r.valor) filter (where r.tipo_baixa in ('recebimento', 'estorno')), 0)` sobre `staging.recebimento` da parcela. Antes era nulo sem recebimento; passa a zero, porque lista vazia é recebimento zero conhecido.
- `data_recebimento = max(r.data_recebimento) filter (where r.tipo_baixa in ('recebimento', 'estorno'))`; nulo sem recebimento.
- `centro_custo_id`: obra do `projectId`; se não cadastrada, o centro empresa do tenant.

#### 3.1.7 `staging.recebimento` (nova)

Uma linha por item de `receipts[]`.

| Coluna | Tipo | Nulo | Leitura e significado |
| --- | --- | --- | --- |
| `tenant_id` | `uuid` | não | |
| `centro_custo_id` | `uuid` | não | o mesmo da parcela |
| `contrato_id_origem` | `integer` | não | `billId` |
| `parcela_id_origem` | `integer` | não | `installmentId` |
| `sequencia` | `integer` | não | posição em `receipts[]` |
| `data_recebimento` | `date` | não | `receipts[].paymentDate`. Item sem data não entra; `raise notice` com a contagem |
| `valor` | `numeric(18,2)` | não | `receipts[].amount` (sintético). Pode ser negativo |
| `origem` | `text` | não | a `origem` da parcela: `direta` ou `repasse` |
| `tipo_condicao` | `text` | sim | a da parcela |
| `tipo_operacao_origem` | `text` | sim | hipótese `receipts[].operationTypeName`, guardado como veio |
| `tipo_baixa` | `text` | não | `check in ('recebimento', 'estorno', 'baixa_sem_caixa')`. `estorno` quando `valor < 0`; `recebimento` nos demais. `baixa_sem_caixa` fica reservado até a amostra real mostrar como a origem marca renegociação e desconto (seção 5) |

Chave `(tenant_id, contrato_id_origem, parcela_id_origem, sequencia)`. Índices `(tenant_id, centro_custo_id, data_recebimento)`. RLS P-obra, grant select.

Caixa realizado de entrada é sempre `sum(valor) filter (where tipo_baixa in ('recebimento', 'estorno'))`.

#### 3.1.8 Títulos: `staging.titulo_pagar`, `staging.titulo_pagar_apropriacao`, `staging.pagamento`

`staging.titulo_pagar` continua com a mesma chave. Mudanças:

- `alter column centro_custo_id drop not null`. Valor: o centro da apropriação principal (regra abaixo).
- `data_pagamento`: data do último pagamento.
- Colunas novas: `empresa_id_origem integer null` (`companyId`), `data_emissao date null` (hipótese `issueDate`), `valor_pago numeric(18,2) not null default 0` (soma de `payments[].amount`), `ajuste_baixa numeric(18,2) not null default 0` (`valor_original - valor_pago - saldo`), `quantidade_apropriacoes integer not null`.
- `revoke select on staging.titulo_pagar from authenticated`. RLS continua ligada. Nenhuma view de marts lê o cabeçalho; `credor` não sai do staging.

Regra de rateio (vale para valor original, cada pagamento e ajuste):

1. Percentual da obra `i`: `buildingsCosts[i].amount / sum(amount)` (sintético). Se a origem trouxer percentual (hipótese `rate`) em todos os itens do título, usar `rate / sum(rate)`; se só parte dos itens o trouxer, usar `amount` em todos, para nenhum item sumir do rateio. Lista ausente ou vazia: uma apropriação 100% no centro empresa com `motivo_sem_obra = 'sem_rateio_na_origem'`. Lista sem nenhum valor: idem, com `motivo_sem_obra = 'rateio_sem_valor'`. `buildingId` sem obra cadastrada: a parte vai para o centro empresa com `motivo_sem_obra = 'obra_nao_cadastrada'` e `id_origem_obra` guardado.
2. Percentual da conta `j`: `rate_j / sum(rate)` da lista de contas do título (hipótese `paymentsCategories[].financialCategoryId` e `financialCategoryRate`). Lista ausente, vazia ou sem percentual: uma conta nula com 100%.
3. Percentual da apropriação `p_k = p_obra × p_conta`, calculado em precisão cheia. A coluna `percentual` guarda o valor arredondado a 6 casas só para leitura.
4. Apropriação principal `k*`: maior `p_k`; empate, menor `(sequencia_obra, sequencia_conta)`.
5. Para um valor `V` do título: `alocar_k(V) = round(V × p_k, 2)` para `k ≠ k*`, e `alocar_k*(V) = V - soma dos demais`. A soma das partes é sempre `V`.
6. Pagamento pelo acumulado: com os pagamentos ordenados por `sequencia_pagamento` e `C_j` o acumulado até o pagamento `j` (`C_0 = 0`), a parte da apropriação é `alocar_k(C_j) - alocar_k(C_{j-1})`. Assim, título quitado termina com pago igual ao valor original em cada obra, sem sobra de centavo.
7. `saldo_k = valor_original_k - valor_pago_k - ajuste_baixa_k`. Soma dos `saldo_k` é o `balanceAmount` do título.

`staging.titulo_pagar_apropriacao`:

| Coluna | Tipo | Nulo | Significado |
| --- | --- | --- | --- |
| `tenant_id` | `uuid` | não | |
| `centro_custo_id` | `uuid` | não | obra, ou centro empresa |
| `titulo_id_origem` | `integer` | não | `billId` |
| `sequencia_obra` | `integer` | não | posição em `buildingsCosts[]`; 1 quando não há lista |
| `sequencia_conta` | `integer` | não | posição na lista de contas; 1 quando não há lista |
| `id_origem_obra` | `integer` | sim | `buildingId` como veio |
| `motivo_sem_obra` | `text` | sim | `sem_rateio_na_origem`, `rateio_sem_valor`, `obra_nao_cadastrada` ou nulo |
| `conta_origem` | `text` | sim | código da conta; nulo quando a origem não manda |
| `percentual` | `numeric(9,6)` | não | `p_k` arredondado |
| `principal` | `boolean` | não | true só em `k*` |
| `valor_original` | `numeric(18,2)` | não | `alocar_k(originalAmount)` |
| `valor_pago` | `numeric(18,2)` | não | soma de `staging.pagamento` da apropriação |
| `ajuste_baixa` | `numeric(18,2)` | não | `alocar_k(ajuste do título)` |
| `saldo` | `numeric(18,2)` | não | item 7 acima |
| `vencimento` | `date` | não | `dueDate` do título |
| `data_competencia` | `date` | sim | `data_emissao` do título. Sem ela, nulo. Nunca cai no vencimento |
| `data_ultimo_pagamento` | `date` | sim | |

Chave `(tenant_id, titulo_id_origem, sequencia_obra, sequencia_conta)`. Índices `(tenant_id, centro_custo_id, vencimento)`, `(tenant_id, centro_custo_id, data_competencia)`, `(tenant_id, conta_origem)`. RLS P-obra, grant select.

`staging.pagamento`:

| Coluna | Tipo | Nulo | Significado |
| --- | --- | --- | --- |
| `tenant_id` | `uuid` | não | |
| `centro_custo_id` | `uuid` | não | o da apropriação |
| `titulo_id_origem` | `integer` | não | |
| `sequencia_pagamento` | `integer` | não | posição em `payments[]` |
| `sequencia_obra` | `integer` | não | |
| `sequencia_conta` | `integer` | não | |
| `data_pagamento` | `date` | não | `payments[].paymentDate`. Item sem data não entra; `raise notice` |
| `valor` | `numeric(18,2)` | não | parte da apropriação pela regra 6. Pode ser negativo (estorno de pagamento) |
| `conta_origem` | `text` | sim | cópia da apropriação |

Chave `(tenant_id, titulo_id_origem, sequencia_pagamento, sequencia_obra, sequencia_conta)`. Índice `(tenant_id, centro_custo_id, data_pagamento)`. RLS P-obra, grant select.

#### 3.1.9 Views recriadas pela 0007

Todas com `security_invoker = true` e grant select.

`marts.fluxo_caixa_mensal`: mesmas 14 colunas, mesma ordem, mesmos nomes. Fontes novas:

| Coluna | Fórmula |
| --- | --- |
| `entrada_direta_realizada`, `repasse_realizado` | `sum(r.valor)` de `staging.recebimento` com `tipo_baixa in ('recebimento','estorno')`, por `date_trunc('month', data_recebimento)` e `origem` |
| `entrada_direta_prevista`, `repasse_previsto` | `sum(coalesce(p.saldo_corrigido, p.saldo))` de parcelas com saldo > 0, contrato não distratado, `vencimento >= ref`, por mês do vencimento |
| `entrada_direta_vencida`, `repasse_vencido` | idem com `vencimento < ref` |
| `saida_realizada` | `sum(pg.valor)` de `staging.pagamento` por mês de `data_pagamento` |
| `saida_prevista` | `sum(a.saldo)` de apropriações com `saldo > 0` e `vencimento >= ref`, por mês do vencimento |
| `saida_vencida` | idem com `vencimento < ref` |
| `saldo_mes`, `saldo_acumulado` | fórmulas da 0005, sem mudança |

Inclui linhas do centro empresa. O painel e as perguntas já filtram por obra.

`marts.fluxo_caixa_cenario`: não muda (lê a view).

`marts.posicao_financeira_obra`: filtra `cc.tipo = 'obra'`. As 19 colunas atuais ficam na ordem. Mudanças de fórmula e colunas novas no fim:

| Coluna | Fórmula |
| --- | --- |
| `pago` | soma de `saida_realizada` (igual a hoje, nova fonte) |
| `a_pagar` | soma de `saida_prevista + saida_vencida` |
| `custo_a_incorrer` | `greatest(custo_orcado - custo_lancado, 0)` |
| `estouro_orcamento` | `greatest(custo_lancado - custo_orcado, 0)` |
| `resultado_contratado`, `resultado_projetado` | como na 0005, trocando `greatest(custo_orcado, pago + a_pagar)` por `greatest(custo_orcado, custo_lancado)` |
| `custo_lancado` (nova) | `sum(a.valor_original)` das apropriações da obra, todas as contas |
| `ajuste_baixa` (nova) | `custo_lancado - pago - a_pagar` |
| `orcamento_carregado` (nova, boolean) | existe item de orçamento na obra |

Sem desconto nem juros, `custo_lancado = pago + a_pagar` e as fórmulas antigas e novas dão o mesmo número.

`marts.cobertura_orcamento_obra`: mesmas colunas, filtra `cc.tipo = 'obra'`.

`drop view marts.consolidado_centro_custo`.

#### 3.1.10 `staging.recarregar(p_tenant uuid)`

Mesmo cabeçalho, `security definer`, `set search_path = ''`, `revoke execute ... from public, anon, authenticated`. Uma transação. Ordem: garante o centro empresa; apaga e regrava `unidade`, `contrato_venda`, `contrato_unidade`, `recebimento`, `parcela_receber` (com `valor_recebido` já somado), `titulo_pagar`, `titulo_pagar_apropriacao`, `pagamento`, `item_orcamento`, todos `where tenant_id = p_tenant`. Uma instrução `insert ... select` por tabela, com `jsonb_array_elements ... with ordinality`. Sem laço por linha. Rodar duas vezes deixa as mesmas linhas.

#### 3.1.11 Gerador e carga (dono: `banco_eventos`)

`scripts/gerar_dados_demo.py` passa a gerar, mantendo `random.seed(2026)`: recebimento em duas vezes (40% e 60%) em 10% das parcelas PM recebidas; pagamento em duas vezes em 5% dos títulos pagos; rateio 60/40 entre duas obras em 5% dos títulos; dois títulos por obra sem `buildingsCosts`; um título de devolução de distrato por contrato distratado, sem obra, com conta de devolução; uma renegociação por obra (parcela original com saldo 0 e `receipts` vazio, duas parcelas novas no mesmo contrato); um estorno (recebimento seguido de valor negativo igual); `issueDate` nos títulos, de 5 a 40 dias antes do vencimento; `paymentsCategories` nos títulos e `receiptsCategories` nas parcelas, com os códigos da tabela da seção 5.2. Tudo que é hipótese está na seção 5.

### 3.2 Migration 0011 `0011_dre_gerencial.sql` (dono: `banco_dre`)

#### 3.2.1 `app.categoria_gerencial` (global, sem tenant)

| Coluna | Tipo | Nulo | Significado |
| --- | --- | --- | --- |
| `codigo` | `text` | não, chave | |
| `nome` | `text` | não | rótulo de tela |
| `grupo_dre` | `text` | não | `check in ('receita_bruta','deducao_receita','custo_imovel','despesa_comercial','despesa_administrativa','resultado_financeiro','fora_do_resultado')` |
| `natureza` | `text` | não | `check in ('entrada','saida')` |
| `ordem` | `integer` | não | ordem de exibição |

Carga fixa na migration:

| codigo | nome | grupo_dre | natureza | ordem |
| --- | --- | --- | --- | --- |
| `venda_imoveis` | Venda de imóveis | receita_bruta | entrada | 10 |
| `tributos_receita` | Tributos sobre a receita | deducao_receita | saida | 20 |
| `terreno` | Terreno | custo_imovel | saida | 30 |
| `materiais` | Materiais | custo_imovel | saida | 31 |
| `mao_de_obra` | Mão de obra | custo_imovel | saida | 32 |
| `empreiteiros` | Empreiteiros | custo_imovel | saida | 33 |
| `projetos` | Projetos | custo_imovel | saida | 34 |
| `licencas_taxas` | Licenças e taxas | custo_imovel | saida | 35 |
| `outros_custos_obra` | Outros custos de obra | custo_imovel | saida | 36 |
| `corretagem` | Corretagem | despesa_comercial | saida | 40 |
| `marketing` | Marketing | despesa_comercial | saida | 41 |
| `despesas_administrativas` | Despesas administrativas | despesa_administrativa | saida | 50 |
| `despesas_financeiras` | Despesas financeiras | resultado_financeiro | saida | 60 |
| `receitas_financeiras` | Receitas financeiras | resultado_financeiro | entrada | 61 |
| `devolucao_distrato` | Devolução de distrato | fora_do_resultado | saida | 70 |
| `credito_producao_entrada` | Crédito à produção (entrada) | fora_do_resultado | entrada | 71 |
| `amortizacao_credito_producao` | Amortização de crédito à produção | fora_do_resultado | saida | 72 |
| `aporte_socios` | Aporte dos sócios | fora_do_resultado | entrada | 73 |
| `transferencia` | Transferência entre contas | fora_do_resultado | saida | 74 |

`outros_custos_obra` só recebe conta que alguém mapeou para ela. Conta sem mapeamento nunca cai aqui. `devolucao_distrato` fica fora do resultado porque o efeito do distrato no resultado já vem pela queda da receita reconhecida (pergunta pendente P5).

RLS: `enable` e `force`. Política de select `using ((select auth.uid()) is not null)`, porque a lista é global e não tem tenant. Grant select a `authenticated`. Sem escrita pela API.

#### 3.2.2 `app.mapa_conta_origem`

| Coluna | Tipo | Nulo | Significado |
| --- | --- | --- | --- |
| `tenant_id` | `uuid` | não | |
| `tipo_origem` | `text` | não | `check in ('titulo_pagar','parcela_receber','orcamento')` |
| `conta_origem` | `text` | não | código como veio da origem; para `orcamento`, o `codigo` do item |
| `categoria_codigo` | `text` | não | `references app.categoria_gerencial(codigo)` |
| `observacao` | `text` | sim | |
| `autor` | `uuid` | não | preenchido por `app.definir_autor()` |
| `atualizado_em` | `timestamptz` | não | idem |

Chave `(tenant_id, tipo_origem, conta_origem)`. Gatilho de validação (`errcode 23514`): `titulo_pagar` só mapeia para categoria de natureza `saida`; `parcela_receber` só para natureza `entrada`; `orcamento` só para o grupo `custo_imovel`. Assim toda conta mapeada cai numa linha do DRE. Gatilhos: `app.definir_autor()` antes; `app.registrar_auditoria('tenant_id','tipo_origem','conta_origem')` depois. RLS: select P-tenant; insert `with check (tenant_id = (select app.tenant_atual()) and (select app.perfil_atual()) in ('diretor','financeiro'))`; update `using` e `with check` com a mesma cláusula; delete `using` com a mesma cláusula. Grant select, insert, update, delete a `authenticated`.

#### 3.2.3 `app.criterio_reconhecimento`

| Coluna | Tipo | Nulo | Significado |
| --- | --- | --- | --- |
| `id` | `uuid` | não, chave, `default gen_random_uuid()` | |
| `tenant_id` | `uuid` | não | |
| `centro_custo_id` | `uuid` | sim | nulo é o padrão do tenant; preenchido vale só para a obra |
| `metodo` | `text` | não, default `'nao_definido'` | `check in ('nao_definido','percentual_conclusao')` |
| `base_fracao_vendida` | `text` | não, default `'unidades'` | `check in ('unidades')`. Área e valor dependem da pergunta P2 |
| `validado_por` | `uuid` | sim | `auth.uid()` gravado pelo gatilho quando `metodo = 'percentual_conclusao'`; nulo em `nao_definido` |
| `validado_em` | `timestamptz` | sim | idem, `now()` |
| `observacao` | `text` | sim | |
| `autor`, `atualizado_em` | `uuid`, `timestamptz` | não | `app.definir_autor()` |

`unique nulls not distinct (tenant_id, centro_custo_id)`. Método efetivo de uma obra: a linha da obra, senão a do tenant, senão `nao_definido`. Auditoria por `app.registrar_auditoria('id')`. RLS: select `using (tenant_id = (select app.tenant_atual()) and (centro_custo_id is null or centro_custo_id in (select app.obras_permitidas())))`; insert e update com a cláusula de select mais `(select app.perfil_atual()) in ('diretor','financeiro')`. Sem delete (volta a `nao_definido` por update). Grant select, insert, update.

#### 3.2.4 Base comum das views da 0011

`apropriacao_classificada` (CTE ou view interna `marts.apropriacao_classificada`, `security_invoker`, sem grant ao painel se ficar só como apoio): cada linha de `staging.titulo_pagar_apropriacao` com `categoria_codigo` e `grupo_dre` pelo `left join app.mapa_conta_origem m on m.tenant_id = a.tenant_id and m.tipo_origem = 'titulo_pagar' and m.conta_origem = a.conta_origem` e `app.categoria_gerencial`. Conta nula ou sem mapeamento dá `categoria_codigo` nulo.

#### 3.2.5 `marts.carteira_recebiveis`

Uma linha por parcela. Sem nome de comprador.

| Coluna | Tipo | Fórmula |
| --- | --- | --- |
| `tenant_id` | uuid | |
| `centro_custo_id` | uuid | |
| `contrato_id_origem` | integer | |
| `contrato_numero` | text | `contrato_venda.numero` |
| `unidade_id_origem` | integer | `contrato_venda.unidade_id_origem` |
| `unidade` | text | `staging.unidade.nome` |
| `parcela_id_origem` | integer | |
| `numero_parcela` | text | |
| `tipo_condicao` | text | |
| `origem` | text | `case p.origem when 'repasse' then 'financiamento' else 'direta' end` |
| `vencimento` | date | |
| `valor_original` | numeric(18,2) | |
| `valor_recebido` | numeric(18,2) | `p.valor_recebido` |
| `saldo` | numeric(18,2) | `coalesce(p.saldo_corrigido, p.saldo, 0)` |
| `data_ultimo_recebimento` | date | `p.data_recebimento` |
| `situacao` | text | `app.situacao_parcela(saldo, valor_recebido, vencimento, c.situacao = '3', ref)` |
| `parcial` | boolean | `valor_recebido > 0 and saldo > 0` |
| `dias_atraso` | integer | `ref - vencimento` quando `situacao = 'vencida'`; nulo nos demais |
| `situacao_contrato` | text | `'ativo'` para `'1'`, `'distratado'` para `'3'`, `'outra'` para o resto, nulo sem contrato |
| `inadimplente_origem` | boolean | `p.inadimplente` |

#### 3.2.6 `marts.resumo_receitas_obra`

Uma linha por centro de custo que tenha contrato ou parcela.

| Coluna | Fórmula |
| --- | --- |
| `tenant_id`, `centro_custo_id`, `obra`, `tipo_centro` | de `app.centro_custo` |
| `vgv_contratado_ativo` | `sum(valor)` de contratos com `situacao = '1'` |
| `contratos_ativos` | `count(*)` com `situacao = '1'` |
| `contratos_distratados` | `count(*)` com `situacao = '3'` |
| `recebido_direto`, `recebido_financiamento` | `sum(valor_recebido)` da carteira por `origem`, todas as situações |
| `vencido_direto`, `vencido_financiamento` | `sum(saldo)` com `situacao = 'vencida'` |
| `a_vencer_direto`, `a_vencer_financiamento` | `sum(saldo)` com `situacao = 'a_vencer'` |
| `previsto_proximo_mes_direto`, `previsto_proximo_mes_financiamento` | `sum(saldo)` com `situacao = 'a_vencer'` e `date_trunc('month', vencimento) = proximo_mes`. Vencida nunca entra |
| `saldo_distratado` | `sum(saldo)` com `situacao = 'cancelada_distrato'`. Informativo, fora da carteira |
| `data_referencia` | `ref` |

Somas sem linha dão 0 (a carteira existe e está vazia naquele recorte).

#### 3.2.7 `marts.recebimento_mensal`

Uma linha por centro, mês e origem.

| Coluna | Fórmula |
| --- | --- |
| `tenant_id`, `centro_custo_id`, `competencia`, `origem` | `origem` em `direta` ou `financiamento` |
| `recebido` | recebimentos de caixa (`recebimento`, `estorno`) pelo mês de `data_recebimento` |
| `previsto_contratual` | `sum(valor_original)` de parcelas pelo mês do vencimento, sem as de situação `cancelada_distrato` e `baixada_sem_recebimento` (a renegociação não conta duas vezes) |
| `saldo_em_aberto` | `sum(saldo)` de parcelas `vencida` e `a_vencer` pelo mês do vencimento |

#### 3.2.8 `marts.custo_obra_categoria`

Uma linha por centro e categoria (`categoria_codigo` nulo é "Sem categoria"), para centros de qualquer tipo.

| Coluna | Fórmula |
| --- | --- |
| `tenant_id`, `centro_custo_id`, `tipo_centro` | |
| `categoria_codigo`, `categoria_nome`, `grupo_dre` | da classificação; nome `'Sem categoria'` quando nulo |
| `orcamento_vigente` | `sum(valor_total)` dos itens de orçamento mapeados para a categoria (`tipo_origem = 'orcamento'`); na linha sem categoria, os itens sem mapeamento. Nulo quando a obra não tem orçamento |
| `custo_lancado` | `sum(valor_original)` das apropriações |
| `desembolsado` | `sum(valor)` de `staging.pagamento` das apropriações |
| `em_aberto_vencido` | `sum(saldo)` com `saldo > 0` e `vencimento < ref` |
| `em_aberto_a_vencer` | `sum(saldo)` com `saldo > 0` e `vencimento >= ref` |
| `ajuste_baixa` | `custo_lancado - desembolsado - em_aberto_vencido - em_aberto_a_vencer` |

Remanescente, estimativa e desvio não ficam aqui: por categoria eles contariam o mesmo real duas vezes quando o orçamento não está mapeado nas mesmas categorias dos títulos (objeção 3). Ficam em `custo_obra_resumo`.

#### 3.2.9 `marts.custo_obra_resumo`

Uma linha por centro.

| Coluna | Fórmula |
| --- | --- |
| `tenant_id`, `centro_custo_id`, `obra`, `tipo_centro` | |
| `orcamento_vigente` | soma dos itens; nulo sem itens |
| `orcamento_original` | sempre nulo; motivo `sem_fonte` |
| `custo_lancado`, `desembolsado`, `em_aberto_vencido`, `em_aberto_a_vencer`, `ajuste_baixa` | somas das mesmas colunas de `custo_obra_categoria` |
| `remanescente_sem_titulo` | `greatest(orcamento_vigente - custo_lancado, 0)`; nulo sem orçamento |
| `estimativa_conclusao` | `custo_lancado + remanescente_sem_titulo`; nulo sem orçamento |
| `desvio` | `estimativa_conclusao - orcamento_vigente` (positivo é acima do orçamento; igual a `estouro_orcamento`) |
| `compromissos_nao_faturados` | sempre nulo; motivo `sem_fonte` |
| `cobertura_classificacao` | `sum(custo_lancado com categoria) / nullif(custo_lancado, 0)` |
| `motivo` | `orcamento_ausente` quando não há orçamento; nulo nos demais |

#### 3.2.10 `marts.despesa_mensal`

Uma linha por centro, mês e categoria, com dois eixos de tempo em colunas separadas.

| Coluna | Fórmula |
| --- | --- |
| `tenant_id`, `centro_custo_id`, `competencia`, `categoria_codigo`, `categoria_nome`, `grupo_dre` | |
| `lancado_competencia` | `sum(valor_original)` pelo mês de `data_competencia` |
| `pago` | `sum(pagamento.valor)` pelo mês de `data_pagamento` |
| `a_pagar` | `sum(saldo)` com `saldo > 0`, `vencimento >= ref`, pelo mês do vencimento |
| `vencido` | `sum(saldo)` com `saldo > 0`, `vencimento < ref`, pelo mês do vencimento |

Apropriações sem `data_competencia` não entram em `lancado_competencia`; aparecem na linha `sem_data_competencia` do DRE.

#### 3.2.11 `marts.pendencia_classificacao`

Uma linha por tipo de origem e conta sem categoria.

| Coluna | Fórmula |
| --- | --- |
| `tenant_id`, `tipo_origem`, `conta_origem` | `conta_origem` nulo é "sem código na origem" |
| `quantidade_lancamentos` | apropriações, parcelas ou itens de orçamento |
| `valor_envolvido` | `sum(valor_original)` (título e parcela) ou `sum(valor_total)` (orçamento) |
| `participacao` | `valor_envolvido / sum(valor de todas as linhas do mesmo tipo_origem visíveis)`, `numeric(9,6)` |
| `primeira_competencia`, `ultima_competencia` | `min` e `max` do mês de `data_competencia` (título), `data_emissao` (parcela); nulo em orçamento |

Parcelas mapeadas para `venda_imoveis` não são pendência. Parcelas sem conta aparecem aqui mas não entram no DRE (a receita vem do reconhecimento).

#### 3.2.12 `marts.reconhecimento_obra_mensal`

Uma linha por obra (`tipo = 'obra'`) e mês, do primeiro mês com contrato ou apropriação até `mes_ref`, em calendário contínuo.

| Coluna | Fórmula |
| --- | --- |
| `tenant_id`, `centro_custo_id`, `competencia` | `fim_mes = (competencia + interval '1 month' - interval '1 day')::date` |
| `metodo` | método efetivo |
| `disponivel` | true só quando `metodo = 'percentual_conclusao'` e nenhum motivo abaixo se aplica |
| `motivo` | primeiro que se aplicar: `criterio_nao_validado`; `orcamento_ausente`; `unidades_ausentes` (obra sem `staging.unidade`); `custo_sem_categoria` (alguma apropriação da obra com `data_competencia <= fim_mes` e categoria nula); `custo_sem_competencia` (alguma apropriação da obra com `data_competencia` nula) |
| `custo_incorrido_acumulado` | `sum(valor_original)` das apropriações da obra com `grupo_dre = 'custo_imovel'` e `data_competencia <= fim_mes`. Fato, sempre calculado |
| `custo_total_estimado` | `greatest(orcamento_vigente, sum(valor_original) de todas as apropriações custo_imovel da obra)`; nulo sem orçamento |
| `poc` | `numeric(9,6)`: `least(custo_incorrido_acumulado / custo_total_estimado, 1)`. Nulo quando não disponível |
| `vgv_ativo_fim_mes` | `sum(valor)` de contratos com `data_venda <= fim_mes` e (`situacao = '1'` ou (`situacao = '3'` e `data_distrato > fim_mes`)) |
| `unidades_obra` | `count(*)` de `staging.unidade` da obra (cadastro atual; premissa) |
| `unidades_vendidas_fim_mes` | `count(distinct unidade_id_origem)` de `staging.contrato_unidade` dos contratos ativos no fim do mês pela regra acima |
| `fracao_vendida` | `unidades_vendidas_fim_mes / nullif(unidades_obra, 0)`, 6 casas; nulo quando não disponível |
| `receita_reconhecida_acumulada` | `round(vgv_ativo_fim_mes × custo_incorrido_acumulado / custo_total_estimado, 2)` com o teto do `least(..., 1)`; nulo quando não disponível |
| `custo_reconhecido_acumulado` | `round(custo_incorrido_acumulado × unidades_vendidas_fim_mes / unidades_obra, 2)`; nulo quando não disponível |
| `receita_reconhecida_mes` | acumulado menos o acumulado do mês anterior (0 no primeiro mês); nulo quando não disponível |
| `custo_reconhecido_mes` | idem |

O cálculo usa precisão cheia e arredonda só o valor final. Distrato reduz a receita no mês do distrato porque o contrato sai de `vgv_ativo_fim_mes`.

#### 3.2.13 `marts.dre_mensal`

Formato longo. Uma linha por centro (obra e empresa), mês e linha do DRE, do primeiro mês com evento até `mes_ref`, mais uma linha por centro com `competencia` nula para `sem_data_competencia`.

Colunas: `tenant_id uuid, centro_custo_id uuid, tipo_centro text, competencia date (nula só em sem_data_competencia), linha_codigo text, linha_ordem integer, linha_nome text, valor_mes numeric(18,2) null, valor_acumulado numeric(18,2) null, disponivel boolean, motivo text null, valor_com_categoria numeric(18,2), valor_total_lancado numeric(18,2), cobertura numeric(9,6) null`.

Fontes por mês `m` (apropriações classificadas pela competência; títulos entram com sinal negativo, parcelas com sinal positivo):

| linha_ordem | linha_codigo | linha_nome | valor_mes |
| --- | --- | --- | --- |
| 10 | `receita_bruta` | Receita bruta reconhecida | `receita_reconhecida_mes`; no centro empresa, 0 |
| 20 | `deducoes` | Deduções e tributos sobre a receita | `-sum` dos títulos do grupo `deducao_receita` |
| 30 | `receita_liquida` | Receita líquida | 10 + 20 |
| 40 | `custo_imovel_vendido` | Custo reconhecido dos imóveis vendidos | `-custo_reconhecido_mes`; no centro empresa, 0 |
| 50 | `resultado_bruto` | Resultado bruto | 30 + 40 |
| 60 | `despesas_comerciais` | Despesas comerciais | `-sum` dos títulos do grupo `despesa_comercial` |
| 70 | `despesas_administrativas` | Despesas administrativas | `-sum` dos títulos do grupo `despesa_administrativa` |
| 80 | `resultado_financeiro` | Resultado financeiro | `sum` das parcelas mapeadas para `receitas_financeiras` pelo mês de `data_emissao` menos `sum` dos títulos do grupo `resultado_financeiro` |
| 90 | `resultado_gerencial` | Resultado gerencial do período | 50 + 60 + 70 + 80 |
| 100 | `custo_obra_incorrido` | Custo de obra lançado no mês (vai para o estoque) | `-sum` dos títulos do grupo `custo_imovel`. Informativo, fora das somas |
| 110 | `fora_do_resultado` | Movimentos fora do resultado | parcelas mais títulos do grupo `fora_do_resultado`, com o sinal da regra. Informativo |
| 120 | `sem_categoria` | Lançamentos sem categoria | `-sum` dos títulos com categoria nula. Informativo |
| 130 | `sem_data_competencia` | Lançamentos sem data de competência | `-sum` dos títulos com `data_competencia` nula, todas as categorias, mais as parcelas classificadas em `receitas_financeiras` ou `fora_do_resultado` sem `data_emissao`. Só na linha de `competencia` nula |

Disponibilidade: linhas 10, 30, 40, 50 e 90 copiam `disponivel` e `motivo` de `reconhecimento_obra_mensal` (no centro empresa são disponíveis). Quando indisponíveis, `valor_mes` e `valor_acumulado` são nulos. As demais são sempre disponíveis. `valor_acumulado` é a soma corrida de `valor_mes` do primeiro mês até `m` no centro. `valor_com_categoria` e `valor_total_lancado` são a soma dos títulos do centro no mês com categoria e no total (iguais em todas as linhas do mês); `cobertura = valor_com_categoria / nullif(valor_total_lancado, 0)`. O custo de obra nunca entra como despesa do período.

Não há coluna de orçamento no DRE: não existe fonte comparável (motivo `sem_fonte`, mostrado no cabeçalho da tela).

#### 3.2.14 `marts.dre_mensal_consolidado`

Agrupa `marts.dre_mensal` por `tenant_id, competencia, linha_codigo, linha_ordem, linha_nome` sobre os centros que o RLS libera (obras permitidas e, para diretor e financeiro, o centro empresa).

| Coluna | Fórmula |
| --- | --- |
| `valor_mes`, `valor_acumulado` | `sum` quando `bool_and(disponivel)`; nulo senão |
| `disponivel` | `bool_and(disponivel)` |
| `motivo` | nulo quando disponível; o motivo comum quando todos os centros estão indisponíveis pelo mesmo motivo; `consolidado_parcial` nos demais casos |
| `valor_com_categoria`, `valor_total_lancado` | somas; `cobertura` recalculada |
| `quantidade_centros` | `count(distinct centro_custo_id)` |

#### 3.2.15 Funções de período da 0011

Todas `language sql stable security invoker set search_path = ''`, grant execute a `authenticated`, revoke de `public, anon`. `p_centro_custo_id` nulo quer dizer consolidado do que o usuário enxerga. Mês de `p_inicio` e `p_fim` é truncado.

- `marts.dre_periodo(p_inicio date, p_fim date, p_centro_custo_id uuid default null) returns table (linha_codigo text, linha_ordem integer, linha_nome text, valor_periodo numeric(18,2), disponivel boolean, motivo text, cobertura numeric(9,6))`. Soma `valor_mes` das linhas de `dre_mensal` no intervalo; disponível só quando todas as linhas somadas estão disponíveis; `motivo` pela regra do consolidado. `sem_data_competencia` sai com o total do centro, sem filtro de período.
- `marts.recebimento_periodo(p_inicio date, p_fim date, p_centro_custo_id uuid default null) returns table (origem text, recebido numeric(18,2), previsto_contratual numeric(18,2))`.
- `marts.desembolso_periodo(p_inicio date, p_fim date, p_centro_custo_id uuid default null) returns table (categoria_codigo text, categoria_nome text, grupo_dre text, lancado_competencia numeric(18,2), pago numeric(18,2))`.

#### 3.2.16 Totais consolidados da 0011

Pedidos pelo painel para os cartões do consolidado, porque a tela não soma em TypeScript. Todas com `security_invoker = true` e grant select; somam só o que o usuário enxerga.

- `marts.recebimento_mensal_consolidado`: `tenant_id, competencia, origem, recebido, previsto_contratual, saldo_em_aberto`. Soma dos centros `tipo = 'obra'`.
- `marts.resumo_receitas_consolidado`: uma linha por tenant com `quantidade_obras, vgv_contratado_ativo, contratos_ativos, contratos_distratados, recebido_direto, recebido_financiamento, vencido_direto, vencido_financiamento, a_vencer_direto, a_vencer_financiamento, previsto_proximo_mes_direto, previsto_proximo_mes_financiamento, saldo_distratado, data_referencia`. Só obras.
- `marts.custo_obra_resumo_consolidado`: uma linha por tenant e `grupo` (`obras` ou `despesas_sem_obra`) com `quantidade_centros, centros_sem_orcamento, orcamento_vigente, custo_lancado, desembolsado, em_aberto_vencido, em_aberto_a_vencer, ajuste_baixa, remanescente_sem_titulo, estimativa_conclusao, desvio, cobertura_classificacao, motivo`. No grupo sem obra, orçamento e o que depende dele ficam nulos. No grupo de obras, ficam nulos com `motivo = 'consolidado_parcial'` quando alguma obra não tem orçamento, ou `'orcamento_ausente'` quando nenhuma tem. Remanescente, estimativa e desvio são a soma dos valores de cada obra.

### 3.3 Migration 0012 `0012_financiamento_medicoes.sql` (dono: `banco_planejamento`)

Tudo que não vem da origem é complemento manual em `app.*`, nunca escrito no staging. Toda tabela tem `autor uuid not null`, `criado_em timestamptz not null default now()`, `atualizado_em timestamptz not null default now()`, `fonte text not null` (de onde veio a informação, em texto), `referencia_documento text null` (número do RAE, contrato, extrato), gatilho `app.definir_autor()` e gatilho `app.registrar_auditoria('id')`. RLS: select P-obra; insert `with check` P-escrita; update `using` e `with check` P-escrita; sem delete (cancelar por situação). Grant select, insert, update a `authenticated`. Índice `(tenant_id, centro_custo_id)` em todas.

#### 3.3.1 `app.operacao_credito_obra`

| Coluna | Tipo | Nulo | Significado |
| --- | --- | --- | --- |
| `id` | `uuid` | não, chave | |
| `tenant_id`, `centro_custo_id` | `uuid` | não | obra |
| `modalidade` | `text` | não | `check in ('credito_producao','plano_empresario','credito_associativo','outra')` |
| `instituicao` | `text` | não | nome do banco |
| `numero_contrato` | `text` | sim | |
| `valor_contratado` | `numeric(18,2)` | não | `check (valor_contratado > 0)` |
| `percentual_retencao` | `numeric(9,6)` | sim | fração retida até o habite-se, conforme o contrato do banco. Nulo é "não informado" |
| `data_contratacao` | `date` | sim | |
| `situacao` | `text` | não, default `'ativa'` | `check in ('ativa','encerrada','cancelada')` |
| `observacao` | `text` | sim | |

Separada do financiamento do comprador.

#### 3.3.2 `app.etapa_financiamento_contrato`

| Coluna | Tipo | Nulo | Significado |
| --- | --- | --- | --- |
| `tenant_id`, `centro_custo_id` | `uuid` | não | |
| `contrato_id_origem` | `integer` | não | contrato de venda |
| `etapa` | `text` | não | `check in ('contratacao','aprovacao','elegivel','liberado')` |
| `pendencia` | `boolean` | não, default false | |
| `motivo_pendencia` | `text` | sim | obrigatório quando `pendencia` (check) |
| `data_etapa` | `date` | não | |
| `data_prevista_liberacao` | `date` | sim | |
| `observacao` | `text` | sim | |

Chave `(tenant_id, contrato_id_origem)`. Gatilho de validação (security invoker) em insert e update: o contrato existe em `staging.contrato_venda` com o mesmo tenant e centro e `situacao = '1'`; senão `raise exception using errcode = '23514'`. Histórico fica na auditoria.

#### 3.3.3 `app.medicao_bancaria`

| Coluna | Tipo | Nulo | Significado |
| --- | --- | --- | --- |
| `id` | `uuid` | não, chave | |
| `tenant_id`, `centro_custo_id` | `uuid` | não | |
| `operacao_credito_id` | `uuid` | não | `references app.operacao_credito_obra` |
| `numero` | `integer` | não | sequência da medição na operação |
| `data_vistoria` | `date` | não | |
| `avanco_fisico_informado` | `numeric(9,6)` | não | fração acumulada informada pelo banco |
| `data_apresentacao` | `date` | sim | |
| `situacao` | `text` | não | `check in ('apresentada','aprovada','reprovada')` |
| `data_aprovacao` | `date` | sim | obrigatória quando aprovada |
| `valor_medido` | `numeric(18,2)` | sim | |
| `valor_elegivel` | `numeric(18,2)` | sim | quanto o banco aceita liberar pela medição |
| `valor_retido` | `numeric(18,2)` | sim | |

`unique (operacao_credito_id, numero)`. Medição aprovada nunca é caixa.

#### 3.3.4 `app.liberacao_financiamento`

| Coluna | Tipo | Nulo | Significado |
| --- | --- | --- | --- |
| `id` | `uuid` | não, chave | |
| `tenant_id`, `centro_custo_id` | `uuid` | não | |
| `nivel` | `text` | não | `check in ('contrato','empreendimento','lote')` |
| `operacao_credito_id` | `uuid` | sim | obrigatório em `empreendimento` e `lote` |
| `contrato_id_origem` | `integer` | sim | obrigatório em `contrato`, proibido nos outros (check) |
| `medicao_id` | `uuid` | sim | `references app.medicao_bancaria` |
| `descricao_lote` | `text` | sim | obrigatório em `lote` |
| `valor_previsto` | `numeric(18,2)` | não | `> 0` |
| `data_prevista` | `date` | não | |
| `situacao` | `text` | não | `check in ('prevista','pendente','recebida','cancelada')` |
| `motivo` | `text` | sim | obrigatório em `pendente` e `cancelada` |
| `valor_recebido` | `numeric(18,2)` | sim | obrigatório em `recebida` |
| `data_recebimento` | `date` | sim | obrigatório em `recebida` |
| `vinculo_tipo` | `text` | sim | `check in ('recebimento','lancamento_manual')`; obrigatório em `recebida` |
| `vinculo_chave` | `text` | sim | `recebimento`: `'<contrato_id_origem>|<parcela_id_origem>|<sequencia>'` de `staging.recebimento`; `lancamento_manual`: identificador do extrato ou documento |

Índice único parcial `(tenant_id, vinculo_tipo, vinculo_chave) where vinculo_chave is not null`: um recebimento ou lançamento liga a uma liberação só. Gatilho de validação: nível `contrato` exige contrato ativo (como em 3.3.2); nível `empreendimento` ou `lote` exige que a soma de `valor_previsto` das liberações não canceladas da operação, contando a nova, seja no máximo `valor_contratado` (`errcode 23514`). Sem rateio por unidade: liberação de empreendimento ou lote nunca é distribuída entre contratos.

Regra contra duplicidade: liberação de nível `contrato` só classifica prazo e elegibilidade; o dinheiro vem da parcela FI em `staging.recebimento`. Liberação de `empreendimento` ou `lote` recebida com `vinculo_tipo = 'recebimento'` também não soma (o dinheiro já está no staging). Só `vinculo_tipo = 'lancamento_manual'` soma como `credito_producao_recebido`.

#### 3.3.5 `marts.financiamento_contrato`

Uma linha por contrato ativo com `valor_financiado > 0` ou com parcela FI.

| Coluna | Fórmula |
| --- | --- |
| `tenant_id`, `centro_custo_id`, `contrato_id_origem`, `contrato_numero`, `unidade` | |
| `valor_contrato`, `valor_financiado` | de `staging.contrato_venda` |
| `instituicao_financeira`, `data_financiamento_origem` | `banco_repasse`, `data_repasse` |
| `credito_associativo` | |
| `etapa`, `pendencia`, `motivo_pendencia`, `data_etapa`, `data_prevista_liberacao` | de `app.etapa_financiamento_contrato`; nulos sem etapa cadastrada |
| `classificacao` | `financiamento_elegivel` quando (`etapa in ('elegivel','liberado')` e `not pendencia`) ou `data_financiamento_origem is not null`; `financiamento_pendente` nos demais |
| `saldo_financiamento_aberto` | `sum(saldo)` das parcelas FI em situação `vencida` ou `a_vencer` |
| `recebido_financiamento` | `sum(valor_recebido)` das parcelas FI |

Não há coluna com valor de liberação agregada por contrato (sem falsa precisão por unidade).

#### 3.3.6 `marts.recebivel_projetado`

Uma linha por parcela com situação `vencida` ou `a_vencer`.

| Coluna | Fórmula |
| --- | --- |
| `tenant_id`, `centro_custo_id`, `contrato_id_origem`, `parcela_id_origem` | |
| `origem` | `direta` ou `financiamento` |
| `classe` | `direta`; para FI, a `classificacao` do contrato |
| `vencimento`, `saldo`, `situacao` | `situacao` por `app.situacao_parcela` |
| `data_prevista` | FI: `coalesce(data_prevista_liberacao da etapa, vencimento)`; direta: `vencimento` |
| `incluida_projecao` | `data_prevista >= ref` |

Reconciliação obrigatória com `carteira_recebiveis` na seção 7.

#### 3.3.7 `marts.saldo_operacao_credito`

Uma linha por operação.

| Coluna | Fórmula |
| --- | --- |
| `tenant_id`, `centro_custo_id`, `operacao_credito_id`, `modalidade`, `instituicao`, `valor_contratado`, `percentual_retencao` | |
| `retencao_prevista` | `round(valor_contratado × percentual_retencao, 2)`; nulo sem percentual |
| `limite_antes_retencao` | `valor_contratado - coalesce(retencao_prevista, 0)` |
| `liberado_recebido` | `sum(valor_recebido)` das liberações `recebida` da operação |
| `previsto_aberto` | `sum(valor_previsto)` das liberações `prevista` e `pendente` |
| `saldo_liberavel` | `greatest(limite_antes_retencao - liberado_recebido, 0)` |
| `saldo_nao_programado` | `greatest(limite_antes_retencao - liberado_recebido - previsto_aberto, 0)` |
| `medido_elegivel` | `sum(valor_elegivel)` das medições aprovadas |
| `elegivel_nao_liberado` | `greatest(medido_elegivel - liberado_recebido, 0)` |
| `excede_limite` | `liberado_recebido + previsto_aberto > limite_antes_retencao` |

#### 3.3.8 `marts.liberacao_status`

Uma linha por liberação, com as colunas da tabela (menos `autor`) e mais `contrato_numero`, `situacao_efetiva` (`recebida`, `cancelada`, `pendente`, `atrasada` quando `prevista` e `data_prevista < ref`, `prevista`), `dias_atraso` (`ref - data_prevista` quando atrasada, nulo senão) e `origem_dado = 'complemento_manual'`.

### 3.4 Migration 0013 `0013_planejamento_projecoes.sql` (dono: `banco_planejamento`)

#### 3.4.1 Tabelas de versão (imutáveis)

`app.versao_planejamento`:

| Coluna | Tipo | Nulo | Significado |
| --- | --- | --- | --- |
| `id` | `uuid` | não, chave | |
| `tenant_id`, `centro_custo_id` | `uuid` | não | obra |
| `tipo` | `text` | não | `check in ('meta','projecao')` |
| `numero` | `integer` | não | sequência por `(tenant_id, centro_custo_id, tipo)`, começando em 1 |
| `descricao` | `text` | não | |
| `data_referencia` | `date` | não | `app.data_referencia()` no momento do registro |
| `premissas` | `jsonb` | não | o que a versão assumiu (ex. `{"premissa_distribuicao_id": ...}`) |
| `autor` | `uuid` | não | `auth.uid()` |
| `criada_em` | `timestamptz` | não | `now()` |

`unique (tenant_id, centro_custo_id, tipo, numero)`. RLS: select P-obra; insert P-escrita. Sem política nem grant de update e delete.

`app.meta_mensal`: `versao_id uuid not null references app.versao_planejamento on delete restrict, tenant_id uuid not null, centro_custo_id uuid not null, competencia date not null, unidades integer null, valor_contratado numeric(18,2) null, fracao_financiada numeric(9,6) null, recebimento_esperado numeric(18,2) null, limite_aporte_proprio numeric(18,2) null`. Chave `(versao_id, competencia)`. Gatilho de validação: a versão é do tipo `meta` e do mesmo tenant e centro. RLS e grants como a versão.

`app.projecao_mensal`: `versao_id`, `tenant_id`, `centro_custo_id`, `competencia` e todas as colunas numéricas de `marts.fluxo_projetado_mensal` (3.4.3) com o mesmo nome e tipo. Chave `(versao_id, competencia)`. Versão do tipo `projecao`. RLS e grants como a versão.

`app.premissa_distribuicao_custo`: `id uuid` chave, `tenant_id`, `centro_custo_id`, `metodo text not null check in ('fracao_mensal')`, `fonte text not null`, `observacao text null`, `autor`, `criada_em`. `app.premissa_distribuicao_custo_mes`: `premissa_id uuid references ... on delete restrict`, `tenant_id`, `centro_custo_id`, `competencia date`, `fracao numeric(9,6) check (fracao > 0 and fracao <= 1)`; chave `(premissa_id, competencia)`. Premissa vigente da obra: a de maior `criada_em`. Válida só quando a soma das frações é exatamente 1. RLS: select P-obra; insert P-escrita; sem update e delete.

#### 3.4.2 Distribuição do custo sem título

Com premissa vigente válida e `remanescente = posicao_financeira_obra.custo_a_incorrer` (só quando `orcamento_carregado`): frações de meses anteriores a `mes_ref` somam-se à fração de `mes_ref` (o que não aconteceu passa para o mês corrente; pergunta P11). Valor do mês `m`: `round(remanescente × fracao_m, 2)`, e o resíduo vai para o mês de maior fração (empate, o mais cedo). Sem premissa, premissa inválida ou sem orçamento, nada é distribuído.

#### 3.4.3 `marts.fluxo_projetado_mensal`

Uma linha por obra (`tipo = 'obra'`) e mês, em calendário contínuo de `least(primeiro mês com item, mes_ref)` a `greatest(último mês com item, mes_ref)`.

| Coluna | Tipo | Fórmula |
| --- | --- | --- |
| `tenant_id`, `centro_custo_id`, `competencia` | | |
| `eh_passado` | boolean | `competencia < mes_ref` |
| `recebido_direto` | numeric(18,2) | recebimentos de caixa `origem = 'direta'` pelo mês |
| `recebido_financiamento` | numeric(18,2) | idem `origem = 'repasse'` |
| `credito_producao_recebido` | numeric(18,2) | liberações `recebida`, nível `empreendimento` ou `lote`, `vinculo_tipo = 'lancamento_manual'`, pelo mês de `data_recebimento` |
| `previsto_direto` | numeric(18,2) | `recebivel_projetado` com `incluida_projecao` e `classe = 'direta'`, pelo mês de `data_prevista` |
| `previsto_financiamento_elegivel` | numeric(18,2) | idem `classe = 'financiamento_elegivel'` |
| `previsto_financiamento_pendente` | numeric(18,2) | idem `classe = 'financiamento_pendente'` |
| `credito_producao_previsto` | numeric(18,2) | liberações `prevista`, nível `empreendimento` ou `lote`, `data_prevista >= ref`, pelo mês de `data_prevista` |
| `vencido_a_receber` | numeric(18,2) | só em `mes_ref`: `sum(saldo)` de `recebivel_projetado` sem `incluida_projecao`. Informativo, fora do saldo |
| `pago` | numeric(18,2) | `staging.pagamento` da obra pelo mês |
| `a_pagar` | numeric(18,2) | apropriações com `saldo > 0` e `vencimento >= ref`, pelo mês do vencimento |
| `a_pagar_vencido` | numeric(18,2) | só em `mes_ref`: apropriações com `saldo > 0` e `vencimento < ref` |
| `custo_sem_titulo_distribuido` | numeric(18,2) | 3.4.2 |
| `total_entradas` | numeric(18,2) | `recebido_direto + recebido_financiamento + credito_producao_recebido + previsto_direto + previsto_financiamento_elegivel + previsto_financiamento_pendente + credito_producao_previsto` |
| `total_saidas` | numeric(18,2) | `pago + a_pagar + a_pagar_vencido + custo_sem_titulo_distribuido` |
| `saldo_mes` | numeric(18,2) | `total_entradas - total_saidas` |
| `caixa_gerado_acumulado` | numeric(18,2) | soma corrida de `saldo_mes` |
| `necessidade_aporte_acumulada` | numeric(18,2) | `greatest(-caixa_gerado_acumulado, 0)` |
| `aporte_incremental_mes` | numeric(18,2) | `greatest(necessidade_aporte_acumulada - necessidade do mês anterior (0 no primeiro), 0)` |
| `caixa_gerado_acumulado_conservador` | numeric(18,2) | soma corrida de `saldo_mes - previsto_financiamento_pendente` |
| `necessidade_aporte_conservadora` | numeric(18,2) | `greatest(-caixa_gerado_acumulado_conservador, 0)` |

Colunas de valor sem movimento no mês valem 0. Meses passados só têm realizado; o vencido a pagar entra em `mes_ref`, porque ainda vai sair. `fluxo_caixa_mensal` mantém a regra antiga (vencido no mês do vencimento) por compatibilidade; os dois acumulados coincidem a partir de `mes_ref` quando não há crédito à produção, custo sem título distribuído nem FI com data prevista diferente do vencimento.

#### 3.4.4 `marts.resumo_projecao_obra`

Uma linha por obra.

| Coluna | Fórmula |
| --- | --- |
| `tenant_id`, `centro_custo_id`, `obra`, `data_referencia` | |
| `exposicao_maxima_projetada` | `max(necessidade_aporte_acumulada)` |
| `mes_exposicao_maxima` | primeiro mês em que o máximo acontece; nulo quando o máximo é 0 |
| `exposicao_maxima_conservadora` | `max(necessidade_aporte_conservadora)` |
| `custo_sem_titulo_total` | `posicao_financeira_obra.custo_a_incorrer` quando `orcamento_carregado`; nulo senão |
| `custo_sem_titulo_distribuido_total` | `sum(custo_sem_titulo_distribuido)` |
| `custo_sem_titulo_nao_distribuido` | `custo_sem_titulo_total - custo_sem_titulo_distribuido_total`; nulo sem orçamento |
| `premissa_distribuicao_id` | premissa vigente usada, ou nulo |
| `motivo_distribuicao` | `orcamento_ausente`, `sem_premissa_distribuicao`, `premissa_invalida` ou nulo |
| `exposicao_parcial` | `custo_sem_titulo_total is null or custo_sem_titulo_nao_distribuido > 0` |
| `vencido_a_receber`, `a_pagar_vencido`, `financiamento_pendente_total` | somas das colunas do fluxo |

#### 3.4.5 `marts.comparativo_projecao`

Uma linha por obra e mês presente na versão original ou no fluxo atual. Versão original da obra: a de menor `numero` entre as de `tipo = 'projecao'` com `date_trunc('month', data_referencia) = mes_ref`; sem nenhuma no mês, a de maior `numero` de meses anteriores.

Colunas: `tenant_id, centro_custo_id, competencia, versao_original_id, versao_original_numero, original_total_entradas, original_total_saidas, original_caixa_gerado_acumulado, atual_total_entradas, atual_total_saidas, atual_caixa_gerado_acumulado, realizado_entradas, realizado_saidas, diferenca_caixa_acumulado`. `realizado_*` só para `competencia <= mes_ref` (`recebido_* + credito_producao_recebido` e `pago`), nulo depois. `diferenca_caixa_acumulado = atual - original`. Colunas `original_*` nulas quando não há versão.

#### 3.4.6 `marts.explicacao_desvio`

Linhas só quando os dados sustentam, para meses `<= mes_ref`.

| causa_codigo | Quando | quantidade | valor |
| --- | --- | --- | --- |
| `vendas_abaixo_meta` / `vendas_acima_meta` | existe meta (última versão `meta`) com `unidades` no mês e as vendas diferem | vendas menos meta, em unidades | valor vendido menos `valor_contratado` da meta; nulo se a meta não tem valor |
| `parcelas_vencidas_sem_pagamento` | parcelas com vencimento no mês e situação `vencida` | parcelas | soma do saldo |
| `financiamento_nao_elegivel` | FI `financiamento_pendente` com vencimento no mês | contratos | soma do saldo |
| `liberacao_prevista_vencida` | liberações `prevista` com `data_prevista` no mês e antes de `ref` | liberações | soma do previsto |
| `gasto_acima_previsto` | existe versão original e `pago` do mês passou do total de saídas da versão para o mês | nulo | diferença positiva |

Colunas: `tenant_id, centro_custo_id, competencia, causa_codigo, causa_descricao, quantidade integer null, valor numeric(18,2) null, origem_dado text` (`origem`, `complemento_manual` ou `versao_planejamento`).

#### 3.4.7 `marts.visao_gerencial_mensal`

Uma linha por obra e mês do fluxo projetado.

| Coluna | Fórmula |
| --- | --- |
| `meta_unidades`, `meta_valor_contratado`, `meta_limite_aporte` | última versão `meta`; nulos sem meta |
| `vendas_unidades`, `vendas_valor` | contratos com `data_venda` no mês (situação atual qualquer) |
| `distratos_unidades` | contratos com `data_distrato` no mês |
| `entrada_direta_prevista_original` | `recebido_direto + previsto_direto` da versão original; nulo sem versão |
| `entrada_direta_recebida` | `recebido_direto` atual |
| `financiamento_previsto_original` | `recebido_financiamento + previsto_financiamento_elegivel + previsto_financiamento_pendente + credito_producao_recebido + credito_producao_previsto` da versão original |
| `financiamento_recebido` | `recebido_financiamento + credito_producao_recebido` atual |
| `gastos_previstos_original` | `total_saidas` da versão original |
| `gastos_realizados` | `pago` atual |
| `caixa_gerado_acumulado`, `necessidade_aporte_acumulada` | do fluxo atual |
| `caixa_gerado_acumulado_original` | da versão original |
| `diferenca_original_atual` | `caixa_gerado_acumulado - caixa_gerado_acumulado_original` |

#### 3.4.8 `marts.pendencias_pos_entrega`

Uma linha por obra com `data_entrega = max(staging.unidade.data_entrega) < ref`. Colunas: `tenant_id, centro_custo_id, obra, data_entrega, recebiveis_vencidos, recebiveis_a_vencer, parcelas_abertas integer, titulos_em_aberto, titulos_abertos integer, liberacoes_nao_recebidas (sum valor_previsto de prevista e pendente), credito_nao_liberado (sum de greatest(valor_contratado - liberado_recebido, 0) das operações ativas)`. Acompanhamento gerencial, não encerramento contábil.

## 4. Assinaturas das funções

| Função | Migration | Segurança | Grants |
| --- | --- | --- | --- |
| `app.data_referencia() returns date` | 0007 | invoker, stable, `search_path = ''` | execute a `authenticated`, `service_role` |
| `app.situacao_parcela(numeric, numeric, date, boolean, date) returns text` | 0007 | invoker, immutable | execute a `authenticated` |
| `app.situacao_carga() returns table (data_referencia date, ultima_carga_em timestamptz, horas_desde_carga numeric(9,1), desatualizada boolean)` | 0007 | definer, stable | execute a `authenticated` |
| `app.registrar_auditoria() returns trigger` | 0007 | definer | nenhum |
| `app.definir_autor() returns trigger` | 0007 | invoker | nenhum |
| `staging.recarregar(p_tenant uuid) returns void` | 0007 (substitui) | definer | nenhum (só o dono) |
| `marts.dre_periodo(date, date, uuid default null)` | 0011 | invoker, stable | `authenticated` |
| `marts.recebimento_periodo(date, date, uuid default null)` | 0011 | invoker, stable | `authenticated` |
| `marts.desembolso_periodo(date, date, uuid default null)` | 0011 | invoker, stable | `authenticated` |
| `marts.simular_fluxo(p_centro_custo_id uuid, p_premissas jsonb) returns table (...)` | 0013 | invoker, stable | `authenticated` |
| `app.registrar_versao_projecao(p_centro_custo_id uuid, p_descricao text) returns uuid` | 0013 | invoker, volatile | `authenticated` |
| `app.registrar_versao_meta(p_centro_custo_id uuid, p_descricao text, p_metas jsonb) returns uuid` | 0013 | invoker, volatile | `authenticated` |
| `app.registrar_premissa_distribuicao(p_centro_custo_id uuid, p_fonte text, p_observacao text, p_meses jsonb) returns uuid` | 0013 | invoker, volatile | `authenticated` |

Todas com `set search_path = ''` e `revoke execute ... from public, anon`. Erro de premissa ou de entrada: `raise exception 'premissa inválida: <campo>' using errcode = '22023'`. O painel troca o código por frase de `mensagens.ts` e nunca mostra a mensagem crua.

### 4.1 `marts.simular_fluxo`

Esquema de `p_premissas` (chaves ausentes assumem o padrão):

```json
{
  "novas_vendas": [{"competencia": "2026-10-01", "quantidade": 2}],
  "desconto_tabela": 0.05,
  "composicao": {"entrada": 0.10, "parcelas_mensais": 0.30, "quantidade_parcelas_mensais": 24, "financiamento": 0.60},
  "meses_ate_liberacao_financiamento": 4,
  "atraso_liberacao_bancaria_meses": 0,
  "deslocamento_cronograma_meses": 0,
  "fator_cronograma": 1.0,
  "cancelar_contratos": [5001],
  "custo_campanha": [{"competencia": "2026-11-01", "valor": 30000.00}]
}
```

| Chave | Padrão | Validação |
| --- | --- | --- |
| `novas_vendas` | `[]` | `competencia` no primeiro dia do mês e `>= mes_ref`; `quantidade` inteiro `>= 0` |
| `desconto_tabela` | 0 | `0 <= x < 1` |
| `composicao` | obrigatória se houver venda | frações `>= 0` somando exatamente 1; `quantidade_parcelas_mensais >= 1` quando `parcelas_mensais > 0` |
| `meses_ate_liberacao_financiamento` | obrigatório se `financiamento > 0` | inteiro `>= 0` |
| `atraso_liberacao_bancaria_meses` | 0 | inteiro `>= 0` |
| `deslocamento_cronograma_meses` | 0 | inteiro `>= 0` |
| `fator_cronograma` | 1 | `> 0` |
| `cancelar_contratos` | `[]` | inteiros |
| `custo_campanha` | `[]` | `competencia >= mes_ref`, `valor > 0`. Rotulado como hipótese |

Regras:

1. Base: as linhas de `fluxo_projetado_mensal` da obra. Com `p_premissas = '{}'`, o resultado tem o mesmo `caixa_gerado_acumulado` da view, mês a mês.
2. Obra fora de `app.obras_permitidas()` devolve zero linhas.
3. Estoque: unidades de `marts.mapa_unidades` da obra com situação `disponivel`, `reservada` ou `proposta` e `valor` não nulo (a mesma base de `estoque_a_vender`). `ticket = sum(valor) / count`. `mapa_unidades` ainda usa `current_date` para o preço; a troca por `ref` fica para o PT-06. Venda aplicada no mês é o mínimo entre o pedido e o estoque que resta, na ordem dos meses. Sem estoque, nenhuma venda.
4. Valor das vendas do mês `m`: `V = round(q × ticket × (1 - desconto_tabela), 2)`. Entrada `round(V × entrada, 2)` em `m`. Financiamento `round(V × financiamento, 2)` em `m + meses_ate_liberacao + atraso_liberacao`. Parcelas: `P = V - entrada - financiamento`, dividido em `n` meses a partir de `m + 1`, `round(P / n, 2)` nos `n - 1` primeiros e o resto no último.
5. `atraso_liberacao_bancaria_meses` desloca `previsto_financiamento_elegivel`, `previsto_financiamento_pendente` e `credito_producao_previsto`.
6. `deslocamento_cronograma_meses` e `fator_cronograma` valem só para `custo_sem_titulo_distribuido`: cada mês vai para `m + deslocamento` com valor `round(valor × fator, 2)`. Títulos lançados não mudam.
7. `cancelar_contratos` tira da projeção as parcelas em aberto desses contratos. Recebimentos passados ficam.
8. Nunca grava em tabela nenhuma.

Retorno (uma linha por mês):

`competencia date, recebido numeric(18,2), carteira_prevista numeric(18,2), novas_vendas_unidades integer, novas_vendas_valor numeric(18,2), entradas_novas_vendas_direta numeric(18,2), entradas_novas_vendas_financiamento numeric(18,2), pago numeric(18,2), a_pagar numeric(18,2), custo_sem_titulo numeric(18,2), custo_campanha numeric(18,2), total_entradas numeric(18,2), total_saidas numeric(18,2), saldo_mes numeric(18,2), caixa_gerado_acumulado numeric(18,2), necessidade_aporte_acumulada numeric(18,2), aporte_incremental_mes numeric(18,2), aviso text, premissas jsonb`.

`recebido = recebido_direto + recebido_financiamento + credito_producao_recebido`; `carteira_prevista` é a soma das quatro colunas de previsto depois do atraso e dos cancelamentos; `a_pagar = a_pagar + a_pagar_vencido`; `aviso = 'vendas_limitadas_ao_estoque'` no mês em que a venda aplicada ficou abaixo da pedida; `premissas` repete a entrada com os padrões preenchidos.

### 4.2 Funções de registro

- `app.registrar_versao_projecao(p_centro_custo_id uuid, p_descricao text) returns uuid`: numa transação, insere a versão `projecao` com `numero = coalesce(max, 0) + 1`, `data_referencia = app.data_referencia()`, `premissas = jsonb_build_object('premissa_distribuicao_id', ..., 'motivo_distribuicao', ...)`, e copia as linhas de `marts.fluxo_projetado_mensal` da obra para `app.projecao_mensal`. Quem não é diretor nem financeiro recebe erro 42501 do RLS.
- `app.registrar_versao_meta(p_centro_custo_id uuid, p_descricao text, p_metas jsonb) returns uuid`: `p_metas` é `[{"competencia": "2026-10-01", "unidades": 3, "valor_contratado": 900000.00, "fracao_financiada": 0.6, "recebimento_esperado": 120000.00, "limite_aporte_proprio": 500000.00}]`; campos numéricos opcionais, `competencia` obrigatória e única.
- `app.registrar_premissa_distribuicao(p_centro_custo_id uuid, p_fonte text, p_observacao text, p_meses jsonb) returns uuid`: `p_meses` é `[{"competencia": "2026-10-01", "fracao": 0.5}]`; soma diferente de 1 dá erro 22023.

## 5. Campos da origem a verificar

A documentação oficial ainda não foi raspada. Todo campo abaixo é lido pelo staging novo e não é lido hoje. "Sintético" quer dizer que os JSON de `dados/` já usam o nome; "hipótese" quer dizer que o nome foi proposto e entra no gerador sintético como hipótese.

### 5.1 Tabela

| Endpoint | Campo | Situação | Uso | Se não existir |
| --- | --- | --- | --- | --- |
| `income` | `receipts[]` (todos, não só o primeiro) | sintético | eventos de recebimento | sem lista, parcela sem recebimento |
| `income` | `receipts[].amount` | sintético | valor recebido | a origem pode chamar de `netAmount` (valor líquido) com `grossAmount`, `interestAmount`, `fineAmount`, `discountAmount`; nesse caso a nova migration lê `netAmount` como `valor` |
| `income` | `receipts[].paymentDate` | sintético | data do caixa | item sem data fica fora, com aviso |
| `income` | `receipts[].operationTypeName` ou `operationTypeId` | hipótese | separar recebimento de caixa de baixa sem caixa (renegociação, desconto, cancelamento) | toda baixa conta como caixa; se a origem registrar renegociação como baixa, o recebido fica maior que o real até a regra ser ajustada. Maior risco desta lista |
| `income` | recebimento negativo como estorno | hipótese | estorno | se a origem apagar o recebimento em vez de lançar o negativo, o estorno já vem refletido; se usar tipo de operação, cai no item anterior |
| `income` | renegociação como parcela original com saldo 0 e sem recebimento, mais parcelas novas no mesmo `billId` | hipótese | evitar contagem dupla | se a renegociação gerar outro `billId`, o VGV não muda mas a carteira do contrato novo não se liga ao original |
| `income` | `issueDate` | sintético | competência de receitas financeiras e pendências | pendência sem data; receitas financeiras sem mês |
| `income` | `installmentNumber` | sintético | rótulo `numero_parcela` | coluna nula |
| `income` | `receiptsCategories[].financialCategoryId` | hipótese | conta da parcela | parcela sem conta, aparece como pendência de classificação |
| `outcome` | `buildingsCosts[]` (todos) | sintético | rateio entre obras | título vai para "Despesas sem obra" |
| `outcome` | `buildingsCosts[].amount` | sintético | percentual da obra | a origem pode mandar percentual (`rate`); a regra 1 de 3.1.8 lê o que existir |
| `outcome` | `payments[]` (todos) e `payments[].amount`, `paymentDate` | sintético | eventos de pagamento | a origem pode chamar o valor de `netAmount`; mesma troca do `income` |
| `outcome` | `issueDate` | hipótese (não está no sintético) | competência do título no DRE | `data_competencia` nula; DRE mostra "sem data de competência" e o reconhecimento fica indisponível (`custo_sem_competencia`) |
| `outcome` | `paymentsCategories[].financialCategoryId` e `financialCategoryRate` | hipótese | conta do título e rateio por conta | título sem conta; tudo vira pendência de classificação; DRE só com `sem_categoria` |
| `outcome` | `companyId` | sintético | `empresa_id_origem` | coluna nula |
| `sales` | `paymentConditions[].conditionType`, `totalValue` | sintético | `valor_financiado` | coluna nula; financiamento só pelas parcelas FI |
| `sales` | `associativeCredit` | sintético | `credito_associativo` | coluna nula |
| `sales` | `units[]` (todos), `units[].main` | sintético | fração vendida por unidade | contrato com duas unidades conta uma só |
| `sales` | `financialInstitutionDate` | lido hoje como `data_repasse` | classificação `financiamento_elegivel` | significado precisa ser conferido: data de contratação do financiamento ou data do repasse (pergunta P9) |
| `units` | `deliveryDate` | lido hoje | pendências pós-entrega | obra fora da lista |

### 5.2 Códigos sintéticos de conta propostos para o gerador

O gerador usa estes códigos e o carregador da demo grava o mapeamento em `app.mapa_conta_origem` (pedido na seção 11). Um código fica de propósito sem mapeamento para exercitar a pendência.

| Código | Categoria | Uso no gerador |
| --- | --- | --- |
| `1.01.001` | venda_imoveis | parcelas de venda |
| `2.01.001` | materiais | títulos de materiais |
| `2.01.002` | mao_de_obra | mão de obra |
| `2.01.003` | empreiteiros | empreiteiros |
| `2.01.004` | projetos | projetos |
| `2.02.001` | tributos_receita | tributos |
| `2.03.001` | corretagem | corretagem |
| `2.04.001` | despesas_administrativas | títulos sem obra |
| `2.05.001` | despesas_financeiras | juros |
| `2.09.001` | devolucao_distrato | devolução ao comprador |
| `2.99.001` | sem mapeamento | 1% dos títulos |

## 6. Contrato das consultas do painel

Regras comuns: uma consulta por bloco da tela, sem N+1; nenhum cálculo de valor em TypeScript (no máximo junção por chave e ordenação, como `serie-fluxo.ts`); filtros sempre por coluna indexada; o RLS decide as obras, a consulta não repete o filtro de tenant. Tipos com campos iguais às colunas. `numeric` pode chegar como texto pelo PostgREST: converter com `Number()` na borda, sem arredondar. Data chega como `"aaaa-mm-dd"`.

Filtros comuns: obra (`.eq("centro_custo_id", id)`, id validado como UUID), período (`.gte("competencia", inicio).lte("competencia", fim)` com meses do primeiro dia), categoria (`.eq("categoria_codigo", c)` ou `.eq("grupo_dre", g)`), situação e origem da carteira. Lista de obras: `app.centro_custo` com `.eq("tipo", "obra")`.

### 6.1 Referência e carga (`painel/lib/consultas/referencia.ts`, dono `painel_demonstrativos`)

```ts
export type SituacaoCarga = {
  data_referencia: string;
  ultima_carga_em: string | null;
  horas_desde_carga: number | null;
  desatualizada: boolean;
};
// supabase.schema("app").rpc("situacao_carga").single()
```

Toda tela nova mostra a data de referência e a da carga a partir daqui. `mesCorrente()` do painel deve ser trocado por `data_referencia` nas telas novas, para o mês de referência ser o mesmo do banco.

### 6.2 Visão geral ampliada (`app/(painel)/page.tsx`)

Consome: `marts.posicao_financeira_obra` (como hoje), `marts.resumo_receitas_obra` (filtrar `tipo_centro = 'obra'`), `marts.custo_obra_resumo`, `marts.resumo_projecao_obra`, `marts.dre_periodo(inicio_do_ano, mes_ref, null)` só a linha `resultado_gerencial`, `marts.pendencia_classificacao` (quantidade de linhas), `app.situacao_carga()`. Cinco a sete consultas em paralelo com `Promise.all`.

O tipo `PosicaoObra` (arquivo do coordenador) ganha no fim: `custo_lancado: number; ajuste_baixa: number; orcamento_carregado: boolean;`.

### 6.3 DRE (`painel/lib/consultas/dre.ts`)

```ts
export type LinhaDreMensal = {
  tenant_id: string; centro_custo_id: string; tipo_centro: "obra" | "empresa";
  competencia: string | null; linha_codigo: CodigoLinhaDre; linha_ordem: number; linha_nome: string;
  valor_mes: number | null; valor_acumulado: number | null; disponivel: boolean; motivo: CodigoMotivo | null;
  valor_com_categoria: number; valor_total_lancado: number; cobertura: number | null;
};
export type LinhaDreConsolidado = Omit<LinhaDreMensal, "centro_custo_id" | "tipo_centro"> & { quantidade_centros: number };
export type LinhaDrePeriodo = {
  linha_codigo: CodigoLinhaDre; linha_ordem: number; linha_nome: string;
  valor_periodo: number | null; disponivel: boolean; motivo: CodigoMotivo | null; cobertura: number | null;
};
export type LinhaReconhecimentoObra = {
  tenant_id: string; centro_custo_id: string; competencia: string; metodo: "nao_definido" | "percentual_conclusao";
  disponivel: boolean; motivo: CodigoMotivo | null; custo_incorrido_acumulado: number; custo_total_estimado: number | null;
  poc: number | null; vgv_ativo_fim_mes: number; unidades_obra: number; unidades_vendidas_fim_mes: number;
  fracao_vendida: number | null; receita_reconhecida_acumulada: number | null; custo_reconhecido_acumulado: number | null;
  receita_reconhecida_mes: number | null; custo_reconhecido_mes: number | null;
};
export type LinhaPendenciaClassificacao = {
  tenant_id: string; tipo_origem: "titulo_pagar" | "parcela_receber" | "orcamento"; conta_origem: string | null;
  quantidade_lancamentos: number; valor_envolvido: number; participacao: number | null;
  primeira_competencia: string | null; ultima_competencia: string | null;
};
export type CriterioReconhecimento = {
  id: string; tenant_id: string; centro_custo_id: string | null; metodo: "nao_definido" | "percentual_conclusao";
  base_fracao_vendida: "unidades"; validado_por: string | null; validado_em: string | null; observacao: string | null;
};
export type CategoriaGerencial = { codigo: string; nome: string; grupo_dre: GrupoDre; natureza: "entrada" | "saida"; ordem: number };
export type CodigoLinhaDre = "receita_bruta" | "deducoes" | "receita_liquida" | "custo_imovel_vendido" | "resultado_bruto"
  | "despesas_comerciais" | "despesas_administrativas" | "resultado_financeiro" | "resultado_gerencial"
  | "custo_obra_incorrido" | "fora_do_resultado" | "sem_categoria" | "sem_data_competencia";
export type GrupoDre = "receita_bruta" | "deducao_receita" | "custo_imovel" | "despesa_comercial"
  | "despesa_administrativa" | "resultado_financeiro" | "fora_do_resultado";
```

Consultas: tabela do período por `rpc("dre_periodo", { p_inicio, p_fim, p_centro_custo_id })`; série mensal de uma obra em `dre_mensal` filtrada por `centro_custo_id` e período, ordenada por `competencia, linha_ordem`; série consolidada em `dre_mensal_consolidado`; POC em `reconhecimento_obra_mensal`; aviso de pendência em `pendencia_classificacao`. Filtros: obra ou consolidado, período (mês, trimestre, ano, últimos 12 meses, calculados em `painel/lib/periodo.ts` a partir de `data_referencia`). Escrita do mapeamento e do critério em Server Action que confere `getUser()` e deixa o RLS barrar perfil sem permissão.

### 6.4 Receitas (`painel/lib/consultas/receitas.ts`)

```ts
export type SituacaoParcela = "quitada" | "vencida" | "a_vencer" | "cancelada_distrato" | "baixada_sem_recebimento";
export type LinhaCarteiraRecebiveis = {
  tenant_id: string; centro_custo_id: string; contrato_id_origem: number; contrato_numero: string | null;
  unidade_id_origem: number | null; unidade: string | null; parcela_id_origem: number; numero_parcela: string | null;
  tipo_condicao: string | null; origem: "direta" | "financiamento"; vencimento: string; valor_original: number;
  valor_recebido: number; saldo: number; data_ultimo_recebimento: string | null; situacao: SituacaoParcela;
  parcial: boolean; dias_atraso: number | null; situacao_contrato: "ativo" | "distratado" | "outra" | null;
  inadimplente_origem: boolean | null;
};
export type ResumoReceitasObra = {
  tenant_id: string; centro_custo_id: string; obra: string; tipo_centro: "obra" | "empresa";
  vgv_contratado_ativo: number; contratos_ativos: number; contratos_distratados: number;
  recebido_direto: number; recebido_financiamento: number; vencido_direto: number; vencido_financiamento: number;
  a_vencer_direto: number; a_vencer_financiamento: number; previsto_proximo_mes_direto: number;
  previsto_proximo_mes_financiamento: number; saldo_distratado: number; data_referencia: string;
};
export type LinhaRecebimentoMensal = {
  tenant_id: string; centro_custo_id: string; competencia: string; origem: "direta" | "financiamento";
  recebido: number; previsto_contratual: number; saldo_em_aberto: number;
};
export type LinhaRecebimentoPeriodo = { origem: "direta" | "financiamento"; recebido: number; previsto_contratual: number };
```

Carteira paginada de 50 em 50 com `.range()`, ordem `vencimento, contrato_numero, parcela_id_origem`, filtros `centro_custo_id`, `situacao`, `origem` e faixa de vencimento. Nunca pedir `nome_cliente`.

### 6.5 Despesas (`painel/lib/consultas/despesas.ts`)

```ts
export type CustoObraResumo = {
  tenant_id: string; centro_custo_id: string; obra: string; tipo_centro: "obra" | "empresa";
  orcamento_vigente: number | null; orcamento_original: null; custo_lancado: number; desembolsado: number;
  em_aberto_vencido: number; em_aberto_a_vencer: number; ajuste_baixa: number;
  remanescente_sem_titulo: number | null; estimativa_conclusao: number | null; desvio: number | null;
  compromissos_nao_faturados: null; cobertura_classificacao: number | null; motivo: CodigoMotivo | null;
};
export type LinhaCustoObraCategoria = {
  tenant_id: string; centro_custo_id: string; tipo_centro: "obra" | "empresa";
  categoria_codigo: string | null; categoria_nome: string; grupo_dre: GrupoDre | null;
  orcamento_vigente: number | null; custo_lancado: number; desembolsado: number;
  em_aberto_vencido: number; em_aberto_a_vencer: number; ajuste_baixa: number;
};
export type LinhaDespesaMensal = {
  tenant_id: string; centro_custo_id: string; competencia: string; categoria_codigo: string | null;
  categoria_nome: string; grupo_dre: GrupoDre | null; lancado_competencia: number; pago: number; a_pagar: number; vencido: number;
};
export type LinhaDesembolsoPeriodo = {
  categoria_codigo: string | null; categoria_nome: string; grupo_dre: GrupoDre | null; lancado_competencia: number; pago: number;
};
```

"Despesas sem obra" aparece como grupo separado quando `tipo_centro = 'empresa'`.

### 6.6 Fluxo realizado e projetado (`painel/lib/consultas/fluxo.ts`, dono `painel_planejamento`)

Mantém `listarFluxoMensal` e `listarFluxoCenario`. Novos tipos:

```ts
export type LinhaFluxoProjetado = {
  tenant_id: string; centro_custo_id: string; competencia: string; eh_passado: boolean;
  recebido_direto: number; recebido_financiamento: number; credito_producao_recebido: number;
  previsto_direto: number; previsto_financiamento_elegivel: number; previsto_financiamento_pendente: number;
  credito_producao_previsto: number; vencido_a_receber: number; pago: number; a_pagar: number;
  a_pagar_vencido: number; custo_sem_titulo_distribuido: number; total_entradas: number; total_saidas: number;
  saldo_mes: number; caixa_gerado_acumulado: number; necessidade_aporte_acumulada: number;
  aporte_incremental_mes: number; caixa_gerado_acumulado_conservador: number; necessidade_aporte_conservadora: number;
};
export type ResumoProjecaoObra = {
  tenant_id: string; centro_custo_id: string; obra: string; data_referencia: string;
  exposicao_maxima_projetada: number; mes_exposicao_maxima: string | null; exposicao_maxima_conservadora: number;
  custo_sem_titulo_total: number | null; custo_sem_titulo_distribuido_total: number;
  custo_sem_titulo_nao_distribuido: number | null; premissa_distribuicao_id: string | null;
  motivo_distribuicao: CodigoMotivo | null; exposicao_parcial: boolean;
  vencido_a_receber: number; a_pagar_vencido: number; financiamento_pendente_total: number;
};
export type PremissasSimulacao = {
  novas_vendas?: { competencia: string; quantidade: number }[];
  desconto_tabela?: number;
  composicao?: { entrada: number; parcelas_mensais: number; quantidade_parcelas_mensais: number; financiamento: number };
  meses_ate_liberacao_financiamento?: number;
  atraso_liberacao_bancaria_meses?: number;
  deslocamento_cronograma_meses?: number;
  fator_cronograma?: number;
  cancelar_contratos?: number[];
  custo_campanha?: { competencia: string; valor: number }[];
};
export type LinhaSimulacao = {
  competencia: string; recebido: number; carteira_prevista: number; novas_vendas_unidades: number;
  novas_vendas_valor: number; entradas_novas_vendas_direta: number; entradas_novas_vendas_financiamento: number;
  pago: number; a_pagar: number; custo_sem_titulo: number; custo_campanha: number; total_entradas: number;
  total_saidas: number; saldo_mes: number; caixa_gerado_acumulado: number; necessidade_aporte_acumulada: number;
  aporte_incremental_mes: number; aviso: "vendas_limitadas_ao_estoque" | null; premissas: PremissasSimulacao;
};
```

Premissas montadas em `painel/lib/simulacao.ts` a partir do formulário, validadas antes (mesmas regras da seção 4.1) e mandadas como objeto; nunca texto concatenado.

### 6.7 Planejamento e visão gerencial (`painel/lib/consultas/planejamento.ts`)

```ts
export type VersaoPlanejamento = {
  id: string; tenant_id: string; centro_custo_id: string; tipo: "meta" | "projecao"; numero: number;
  descricao: string; data_referencia: string; premissas: Record<string, unknown>; autor: string; criada_em: string;
};
export type LinhaMetaMensal = {
  versao_id: string; tenant_id: string; centro_custo_id: string; competencia: string; unidades: number | null;
  valor_contratado: number | null; fracao_financiada: number | null; recebimento_esperado: number | null;
  limite_aporte_proprio: number | null;
};
export type LinhaComparativoProjecao = {
  tenant_id: string; centro_custo_id: string; competencia: string; versao_original_id: string | null;
  versao_original_numero: number | null; original_total_entradas: number | null; original_total_saidas: number | null;
  original_caixa_gerado_acumulado: number | null; atual_total_entradas: number; atual_total_saidas: number;
  atual_caixa_gerado_acumulado: number; realizado_entradas: number | null; realizado_saidas: number | null;
  diferenca_caixa_acumulado: number | null;
};
export type LinhaExplicacaoDesvio = {
  tenant_id: string; centro_custo_id: string; competencia: string;
  causa_codigo: "vendas_abaixo_meta" | "vendas_acima_meta" | "parcelas_vencidas_sem_pagamento"
    | "financiamento_nao_elegivel" | "liberacao_prevista_vencida" | "gasto_acima_previsto";
  causa_descricao: string; quantidade: number | null; valor: number | null;
  origem_dado: "origem" | "complemento_manual" | "versao_planejamento";
};
export type LinhaVisaoGerencial = {
  tenant_id: string; centro_custo_id: string; competencia: string; meta_unidades: number | null;
  meta_valor_contratado: number | null; meta_limite_aporte: number | null; vendas_unidades: number; vendas_valor: number;
  distratos_unidades: number; entrada_direta_prevista_original: number | null; entrada_direta_recebida: number;
  financiamento_previsto_original: number | null; financiamento_recebido: number; gastos_previstos_original: number | null;
  gastos_realizados: number; caixa_gerado_acumulado: number; necessidade_aporte_acumulada: number;
  caixa_gerado_acumulado_original: number | null; diferenca_original_atual: number | null;
};
export type LinhaPendenciaPosEntrega = {
  tenant_id: string; centro_custo_id: string; obra: string; data_entrega: string; recebiveis_vencidos: number;
  recebiveis_a_vencer: number; parcelas_abertas: number; titulos_em_aberto: number; titulos_abertos: number;
  liberacoes_nao_recebidas: number; credito_nao_liberado: number;
};
```

Registro de versão e meta por `rpc("registrar_versao_projecao", ...)` e `rpc("registrar_versao_meta", ...)` dentro de Server Action que confere `getUser()`.

### 6.8 Medições e liberações (`painel/lib/consultas/financiamento.ts`)

```ts
export type ClassificacaoFinanciamento = "financiamento_elegivel" | "financiamento_pendente";
export type FinanciamentoContrato = {
  tenant_id: string; centro_custo_id: string; contrato_id_origem: number; contrato_numero: string | null; unidade: string | null;
  valor_contrato: number; valor_financiado: number | null; instituicao_financeira: string | null;
  data_financiamento_origem: string | null; credito_associativo: boolean | null;
  etapa: "contratacao" | "aprovacao" | "elegivel" | "liberado" | null; pendencia: boolean | null;
  motivo_pendencia: string | null; data_etapa: string | null; data_prevista_liberacao: string | null;
  classificacao: ClassificacaoFinanciamento; saldo_financiamento_aberto: number; recebido_financiamento: number;
};
export type SaldoOperacaoCredito = {
  tenant_id: string; centro_custo_id: string; operacao_credito_id: string;
  modalidade: "credito_producao" | "plano_empresario" | "credito_associativo" | "outra"; instituicao: string;
  valor_contratado: number; percentual_retencao: number | null; retencao_prevista: number | null;
  limite_antes_retencao: number; liberado_recebido: number; previsto_aberto: number; saldo_liberavel: number;
  saldo_nao_programado: number; medido_elegivel: number; elegivel_nao_liberado: number; excede_limite: boolean;
};
export type LinhaLiberacao = {
  id: string; tenant_id: string; centro_custo_id: string; nivel: "contrato" | "empreendimento" | "lote";
  operacao_credito_id: string | null; contrato_id_origem: number | null; contrato_numero: string | null;
  medicao_id: string | null; descricao_lote: string | null; valor_previsto: number; data_prevista: string;
  situacao: "prevista" | "pendente" | "recebida" | "cancelada";
  situacao_efetiva: "prevista" | "pendente" | "recebida" | "cancelada" | "atrasada";
  motivo: string | null; valor_recebido: number | null; data_recebimento: string | null;
  vinculo_tipo: "recebimento" | "lancamento_manual" | null; vinculo_chave: string | null; fonte: string;
  referencia_documento: string | null; dias_atraso: number | null; origem_dado: "complemento_manual";
};
export type MedicaoBancaria = {
  id: string; tenant_id: string; centro_custo_id: string; operacao_credito_id: string; numero: number;
  data_vistoria: string; avanco_fisico_informado: number; data_apresentacao: string | null;
  situacao: "apresentada" | "aprovada" | "reprovada"; data_aprovacao: string | null; valor_medido: number | null;
  valor_elegivel: number | null; valor_retido: number | null; fonte: string; referencia_documento: string | null;
};
```

Não há tela de medições na lista de arquivos exclusivos; a sugestão é `painel/app/(painel)/planejamento/financiamento/` (dono `painel_planejamento`).

### 6.9 Perguntas prontas novas

Cada pergunta chama a mesma função de consulta da tela, então o número bate por construção. Ids finais:

| id | Pergunta | Fonte |
| --- | --- | --- |
| `resultado-gerencial-ano` | Qual o resultado gerencial deste ano, por obra? | `dre_periodo(inicio_do_ano, mes_ref, obra)` linha `resultado_gerencial` |
| `previsto-proximo-mes` | Quanto está previsto para entrar no próximo mês, por obra? | `resumo_receitas_obra.previsto_proximo_mes_direto` e `_financiamento` |
| `custo-por-categoria` | Quanto cada obra já gastou por categoria? | `custo_obra_categoria` |
| `aporte-necessario` | Quanto de aporte cada obra vai precisar e em que mês? | `resumo_projecao_obra` |
| `financiamentos-pendentes` | Quanto de financiamento ainda não está elegível? | `resumo_projecao_obra.financiamento_pendente_total` |
| `pendencias-classificacao` | Que contas ainda não têm categoria? | `pendencia_classificacao` |
| `simular-vendas` | O que acontece com o caixa se a obra vender N unidades por mês? | `simular_fluxo` com premissas mostradas na resposta |

Resposta: conclusão curta, valores consultados, data de referência, tabela, e a marcação de cada número como fato (realizado), previsão contratual ou simulação.

## 7. Regras de reconciliação

Cada regra vira teste pgTAP (dono indicado) e é conferida pelo revisor. Igualdade exata ao centavo.

| # | Regra | Dono do teste |
| --- | --- | --- |
| R1 | Por obra, `sum(staging.recebimento.valor)` de caixa = `resumo_receitas_obra.recebido_direto + recebido_financiamento` = `posicao_financeira_obra.recebido_direto + recebido_repasse` = soma de `entrada_direta_realizada + repasse_realizado` em `fluxo_caixa_mensal` | banco_eventos e banco_dre |
| R2 | Por obra e origem, `sum(carteira_recebiveis.saldo) filter (situacao = 'a_vencer')` = `resumo_receitas_obra.a_vencer_*` = `posicao_financeira_obra.a_receber_*`; idem `vencida` com `vencido_direto` e `repasse_atrasado` | banco_dre |
| R3 | `sum(carteira_recebiveis.valor_recebido)` por obra = `resumo_receitas_obra.recebido_direto + recebido_financiamento` | banco_dre |
| R4 | Soma de `recebimento_mensal.recebido` por obra = R1 | banco_dre |
| R5 | Por título, soma das apropriações: `valor_original` = `originalAmount`; `saldo` = `balanceAmount`; soma de `staging.pagamento.valor` = soma de `payments[]` | banco_eventos |
| R6 | Por obra, `custo_obra_resumo.custo_lancado = desembolsado + em_aberto_vencido + em_aberto_a_vencer + ajuste_baixa`; e soma das linhas de `custo_obra_categoria` = `custo_obra_resumo` em cada coluna | banco_dre |
| R7 | `custo_obra_resumo.desembolsado` = `posicao_financeira_obra.pago`; `em_aberto_vencido + em_aberto_a_vencer` = `a_pagar`; `custo_lancado` = `posicao.custo_lancado`; `remanescente_sem_titulo` = `posicao.custo_a_incorrer` quando há orçamento | banco_dre |
| R8 | Soma de `saida_realizada` de todos os centros do tenant (obras e empresa) = `sum(staging.pagamento.valor)` do tenant | banco_eventos |
| R9 | `estimativa_conclusao = custo_lancado + remanescente_sem_titulo` e `desvio = posicao.estouro_orcamento` | banco_dre |
| R10 | `dre_mensal_consolidado` = soma de `dre_mensal` dos centros visíveis, linha a linha, quando disponível | banco_dre |
| R11 | Num centro sem parcelas classificadas em `receitas_financeiras` ou `fora_do_resultado`, a soma de `valor_mes` das linhas 20, 60, 70, 80, 100, 110 e 120 em todos os meses, mais a linha 130, é igual a `-sum(valor_original)` das apropriações do centro com `data_competencia` até o mês de referência ou nula (o DRE termina no mês de referência; competência futura entra quando o mês chegar). Nenhum título fica fora nem conta duas vezes | banco_dre |
| R12 | `dre_periodo(p_inicio, p_fim, obra)` = soma de `dre_mensal.valor_mes` no intervalo | banco_dre |
| R13 | Por obra, `sum(previsto_direto)` do fluxo projetado = `resumo_receitas_obra.a_vencer_direto`; `sum(previsto_financiamento_elegivel + previsto_financiamento_pendente)` + parte FI de `vencido_a_receber` = `a_vencer_financiamento + vencido_financiamento` | banco_planejamento |
| R14 | `sum(pago)` do fluxo projetado = `posicao.pago`; `sum(a_pagar) + a_pagar_vencido` = `posicao.a_pagar` | banco_planejamento |
| R15 | `resumo_projecao_obra.custo_sem_titulo_total = custo_obra_resumo.remanescente_sem_titulo` e `distribuido_total + nao_distribuido = total` | banco_planejamento e revisor |
| R16 | `simular_fluxo(obra, '{}')` devolve, mês a mês, o mesmo `caixa_gerado_acumulado` de `fluxo_projetado_mensal` | banco_planejamento |
| R17 | Soma de `novas_vendas_valor` = soma de `entradas_novas_vendas_direta + entradas_novas_vendas_financiamento` quando o horizonte cobre todas as parcelas | banco_planejamento |
| R18 | Por operação, `liberado_recebido + previsto_aberto <= valor_contratado` sempre (gatilho) | banco_planejamento |
| R19 | `sum(recebivel_projetado.saldo)` por obra e origem = `sum(carteira_recebiveis.saldo) filter (situacao in ('vencida','a_vencer'))` | revisor (depende de 0011 e 0012) |
| R20 | Dashboard e assistente: cada pergunta pronta nova devolve o mesmo número que a tela correspondente, porque chama a mesma função de `painel/lib/consultas`. Teste Vitest confere que a pergunta referencia a função da tela | painel_planejamento |

## 8. Rótulos de interface e definições

Rótulo curto na tela e frase do botão de explicação. As frases dos indicadores já existentes em `painel/lib/explicacoes.ts` continuam; os ajustes pedidos estão marcados.

| Chave | Rótulo | Definição |
| --- | --- | --- |
| `caixa_atual` (ajuste) | Caixa realizado acumulado | Só o realizado: tudo que já entrou dos compradores e do banco menos tudo que já foi pago, desde o início da obra. Não é saldo bancário: não inclui aplicações, empréstimos nem dinheiro de outras obras. "Caixa gerado acumulado" fica reservado para a projeção (realizado mais previsto). A exposição máxima exibida vem de `resumo_projecao_obra`, para haver um número só de aporte. |
| `vgv_contratado_ativo` | VGV contratado | Soma do valor dos contratos de venda ativos. Contrato distratado não entra. É venda, não é dinheiro recebido nem receita do DRE. |
| `recebido_direto` | Recebido do comprador | Entradas diretas já pagas pelos compradores, pela data do pagamento. Estorno já descontado. |
| `recebido_financiamento` | Recebido de financiamento | Repasse do banco já recebido pelo financiamento dos compradores, pela data do recebimento. |
| `vencido_direto` | Vencido do comprador | Parcelas dos compradores com vencimento antes da data de referência e ainda em aberto. Não entram no caixa previsto. |
| `vencido_financiamento` | Financiamento atrasado | Parcelas de financiamento com vencimento passado e ainda não pagas pelo banco. Não entram no caixa previsto. |
| `a_vencer_direto` | A receber do comprador | Saldo das parcelas dos compradores que vencem da data de referência em diante. Contrato distratado não entra. |
| `a_vencer_financiamento` | A receber de financiamento | Saldo das parcelas de financiamento que vencem da data de referência em diante. |
| `previsto_proximo_mes_direto` | Entrada direta prevista no próximo mês | Parcelas dos compradores que vencem no mês seguinte ao da data de referência. Parcela já vencida não entra. |
| `previsto_proximo_mes_financiamento` | Financiamento previsto no próximo mês | Parcelas de financiamento que vencem no mês seguinte ao da data de referência. Parcela já vencida não entra. |
| `saldo_distratado` | Saldo de contratos distratados | O que ficou em aberto em contratos distratados. Fica fora da carteira; o que esses compradores pagaram antes continua no recebido. |
| `carteira_situacao` | Situação da parcela | Quitada, vencida, a vencer, cancelada por distrato ou baixada sem recebimento (renegociada ou cancelada na origem). |
| `receita_bruta` | Receita bruta reconhecida | Receita das vendas reconhecida no mês pelo percentual de conclusão da obra. Só aparece depois que o financeiro valida o critério. |
| `deducoes` | Deduções e tributos | Tributos sobre a receita lançados no mês de competência dos títulos. |
| `custo_imovel_vendido` | Custo reconhecido dos imóveis vendidos | Parte do custo da obra que corresponde às unidades vendidas, pelo mesmo critério da receita. O resto do custo fica em estoque. |
| `resultado_bruto` | Resultado bruto | Receita líquida menos o custo reconhecido dos imóveis vendidos. |
| `despesas_comerciais` | Despesas comerciais | Corretagem e marketing pela competência dos títulos. |
| `despesas_administrativas` | Despesas administrativas | Despesas da empresa pela competência dos títulos, inclusive as sem obra. |
| `resultado_financeiro` | Resultado financeiro | Receitas financeiras menos juros e encargos lançados. Rendimento de aplicação não entra: o extrato bancário não é carregado. |
| `resultado_gerencial` | Resultado gerencial do período | Resultado bruto menos despesas comerciais e administrativas, mais o resultado financeiro. Não é o lucro contábil: não inclui imposto de renda nem ajustes do contador. |
| `custo_obra_incorrido` | Custo de obra lançado no mês | Títulos de custo de obra pela competência. Vai para o estoque e não é despesa do mês. |
| `fora_do_resultado` | Fora do resultado | Aportes, empréstimos, crédito à produção, amortizações, transferências e devoluções de distrato. Mexem no caixa, não no resultado. |
| `sem_categoria` | Sem categoria | Lançamentos cuja conta de origem ainda não foi classificada. Não entram em nenhuma linha do resultado até alguém classificar. |
| `sem_data_competencia` | Sem data de competência | Títulos que a origem mandou sem data de emissão. Ficam fora dos meses até a origem informar a data. |
| `cobertura` | Classificado | Parte do valor lançado no período que já tem categoria. Abaixo de 100%, o resultado pode mudar quando as contas pendentes forem classificadas. |
| `poc` | Percentual de conclusão | Custo de obra lançado até o mês dividido pelo custo total estimado (o maior entre o orçamento e o custo já lançado). |
| `fracao_vendida` | Fração vendida | Unidades com contrato ativo dividido pelo total de unidades da obra. Premissa: todas as unidades pesam igual. |
| `orcamento_vigente` | Orçamento vigente | Soma dos itens do orçamento que está na origem hoje. A origem não guarda o orçamento original. |
| `custo_lancado` | Custo lançado | Títulos da obra, pagos ou não, pelo valor original. Parte de título rateado entre obras entra só pela fatia desta obra. |
| `desembolsado` | Desembolsado | Pagamentos da obra, pela data do pagamento. |
| `em_aberto_vencido` | A pagar vencido | Saldo de títulos com vencimento passado. Entra no caixa previsto do mês de referência. |
| `em_aberto_a_vencer` | A pagar a vencer | Saldo de títulos que vencem da data de referência em diante. |
| `ajuste_baixa` | Descontos e acréscimos | Diferença entre o custo lançado e o que foi pago ou está em aberto: descontos obtidos menos juros e multas pagos. |
| `remanescente_sem_titulo` | Orçamento sem título | Parte do orçamento vigente que ainda não virou título. Nunca negativo. Não soma com os títulos: é o que falta lançar. |
| `estimativa_conclusao` | Estimativa até a conclusão | Custo lançado mais o orçamento sem título. |
| `desvio` | Desvio sobre o orçamento | Quanto a estimativa até a conclusão passa do orçamento vigente. Zero quando está dentro. |
| `compromissos_nao_faturados` | Compromissos não faturados | Pedidos de compra e contratos de empreiteiro ainda sem título. Indisponível: a origem ainda não é lida para isso. |
| `previsto_financiamento_elegivel` | Financiamento elegível | Parcelas de financiamento de contratos já aprovados pelo banco ou com financiamento registrado na origem, pela data prevista. |
| `previsto_financiamento_pendente` | Financiamento pendente | Parcelas de financiamento de compradores sem aprovação do banco ou com pendência. Podem não entrar. |
| `credito_producao_previsto` | Crédito à produção previsto | Liberações do banco para a obra, cadastradas pelo financeiro e ainda não recebidas. |
| `custo_sem_titulo_distribuido` | Custo sem título distribuído | Orçamento sem título repartido nos meses pela premissa cadastrada, com fonte e autor. |
| `custo_sem_titulo_nao_distribuido` | Custo sem título não distribuído | Orçamento sem título sem premissa de meses. Fica num total separado e deixa a necessidade de aporte parcial. |
| `caixa_gerado_acumulado` | Caixa gerado acumulado | Soma, mês a mês, do que entrou e do que está previsto entrar menos o que saiu e vai sair. Entrada vencida fica fora; saída vencida entra. Não é saldo bancário. |
| `necessidade_aporte_acumulada` | Aporte necessário | Quanto dinheiro próprio a obra precisa ter colocado até o mês para o caixa gerado acumulado não ficar negativo. |
| `aporte_incremental_mes` | Aporte do mês | Quanto a necessidade de aporte cresce no mês. |
| `exposicao_maxima_projetada` | Maior aporte necessário | O pico da necessidade de aporte na projeção. Parcial quando há custo sem título não distribuído. |
| `saldo_liberavel` | Saldo liberável | Valor contratado com o banco menos a retenção e menos o que já foi liberado. |
| `medido_elegivel` | Medido e elegível | Valor aceito pelo banco nas medições aprovadas. Não é dinheiro recebido. |
| `simulacao` | Simulação | Cenário com premissas escolhidas por você. Não altera o realizado nem a projeção salva. |

Rótulos de origem: "Entrada direta" (comprador paga à construtora), "Financiamento" nas telas novas e "Repasse" nas telas que já usam a palavra. Nunca "saldo bancário" nem "lucro líquido".

## 9. Estados

| Estado | Como o banco sinaliza | Como a tela mostra |
| --- | --- | --- |
| Indisponível | `disponivel = false`, valor nulo, `motivo` com código | Traço no lugar do número e a frase do motivo; nunca zero |
| Cobertura parcial | `cobertura < 1` ou `exposicao_parcial = true` | Número com selo "parcial" e a fração ("78% classificado"); link para a pendência |
| Dado ausente | Coluna nula (ex. orçamento sem itens, data de competência nula, `dias_atraso` de parcela não vencida) | "Não informado" ou traço, com a explicação; nunca 0 |
| Zero conhecido | Coluna 0 | R$ 0,00 |
| Carga desatualizada | `app.situacao_carga().desatualizada = true` | Aviso no topo: "A carga de hoje não rodou. Os números são de dd/mm às hh:mm." |
| Sem permissão | RLS devolve zero linhas | Mesma mensagem de obra não encontrada; nunca revela que existe |

Códigos de motivo (`CodigoMotivo`) e frase:

| Código | Frase |
| --- | --- |
| `criterio_nao_validado` | Critério de reconhecimento não validado pelo financeiro. |
| `orcamento_ausente` | A obra não tem orçamento carregado. |
| `unidades_ausentes` | A obra não tem unidades cadastradas; a fração vendida não pode ser calculada. |
| `custo_sem_categoria` | Há custo da obra sem categoria. Classifique as contas pendentes para liberar o cálculo. |
| `custo_sem_competencia` | Há títulos da obra sem data de competência na origem. |
| `sem_fonte` | A origem não traz este dado. |
| `sem_premissa_distribuicao` | Não há premissa de meses para o custo sem título. |
| `premissa_invalida` | A premissa de meses não soma 100%. |
| `consolidado_parcial` | Alguma obra do consolidado está indisponível. |

## 10. Perguntas pendentes para João e o financeiro do piloto

| # | Pergunta | Impacto enquanto não responde |
| --- | --- | --- |
| P1 | Qual critério de reconhecimento de receita e custo o piloto usa: percentual de conclusão (POC) ou entrega das chaves? | DRE mostra receita, custo, resultado bruto e resultado gerencial como indisponíveis |
| P2 | A fração vendida do custo reconhecido é por unidades, por área privativa ou por valor de venda? | Implementado só por unidades; obra com unidades de tamanhos muito diferentes distorce o custo reconhecido |
| P3 | O terreno entra no custo incorrido do POC ou só no custo reconhecido? | Hoje entra nos dois, como todo `custo_imovel`; tirar muda o POC |
| P4 | Qual o plano de contas financeiro do piloto e como cada conta se liga às categorias gerenciais? | Sem mapeamento, todo título vai para "Sem categoria" e o POC fica indisponível |
| P5 | Como o financeiro trata a devolução de distrato e a multa retida no resultado? | Devolução fica fora do resultado; multa retida não é identificada |
| P6 | O piloto tem crédito à produção ou plano empresário? Com qual banco? Como a liberação aparece no ERP (contas a receber, movimento bancário, nada)? | Define se a liberação recebida liga a `recebimento` ou a `lancamento_manual` |
| P7 | Qual o percentual de retenção de cada contrato com o banco? | Sem ele, `retencao_prevista` fica nula e o saldo liberável considera o contrato inteiro |
| P8 | A condição FI é sempre financiamento do comprador? Existem outras condições pagas pelo banco (FGTS, subsídio, chaves financiadas)? | Parcela de outra condição paga pelo banco aparece como entrada direta |
| P9 | A data de instituição financeira do contrato de venda é a data da contratação do financiamento ou a data em que o banco pagou? | Hoje ela torna o financiamento "elegível"; se for a data do pagamento, a classificação fica atrasada |
| P10 | Financiamento pendente deve entrar no caixa previsto principal? | Entra no principal; a coluna conservadora exclui |
| P11 | Na premissa de meses do custo sem título, o que não aconteceu em mês passado vai para o mês corrente? | Implementado assim; alternativa é repartir nos meses seguintes |
| P12 | O VGV do POC deve ser corrigido pelo índice do contrato ou usar o valor nominal? | Usa o nominal |
| P13 | O orçamento do piloto é por etapa (fundação, estrutura) ou por insumo (material, mão de obra)? | Por etapa, o orçamento por categoria fica quase todo em "sem categoria" e a comparação por categoria perde sentido |
| P14 | Despesas comerciais e financeiras apropriadas à obra devem contar contra o orçamento da obra? | Hoje contam (todo título da obra entra no custo lançado) |
| P15 | A competência do título é a data de emissão, a data do documento ou a data de lançamento? | Usa emissão (hipótese `issueDate`) |
| P16 | Como a origem registra renegociação, desconto e estorno de recebimento? | Toda baixa é caixa; renegociação registrada como baixa inflaria o recebido |
| P17 | Os números 0011 a 0013 podem ser usados? O plano reservava 0011 em diante para o PT-09 | Colisão de numeração com o PT-09 |

## 11. Pedidos ao coordenador (arquivos fora dos agentes)

1. `painel/lib/consultas/unidades.ts`: `listarObras` e `buscarObra` precisam de `.eq("tipo", "obra")`, senão "Despesas sem obra" aparece na lista de obras e no mapa de unidades para diretor e financeiro.
2. `painel/lib/consultas/posicao.ts`: acrescentar `custo_lancado`, `ajuste_baixa` e `orcamento_carregado` ao tipo `PosicaoObra`.
3. `supabase/seed.sql` ou o carregador: gravar o mapeamento da seção 5.2 em `app.mapa_conta_origem` para o tenant da demo depois da 0011. `carregar_demo.py` é do `banco_eventos`, mas a tabela nasce na 0011; decidir quem grava.
4. `painel/lib/explicacoes.ts` (dono `painel_demonstrativos`): trocar o rótulo e a frase de `caixa_atual` pelo texto da seção 8.
5. `CONTEXTO.md` e `docs/plano_implementacao.md`: registrar a numeração 0011 a 0013 e o resultado das perguntas da seção 10.
