# Configuração por cliente

Cada construtora tem regras e preferências próprias. Este documento define onde elas ficam, quem altera, qual o padrão e qual view lê cada uma. É o contrato dos agentes que implementam a personalização; complementa `contrato_dados.md`.

## 1. Princípios

1. Todo padrão reproduz o comportamento atual. Instalar a personalização não muda nenhum número da demo.
2. Regra de negócio vem da configuração, nunca de constante em view ou em tela. Quando uma view precisa de uma regra, lê a configuração efetiva da obra.
3. Três níveis: padrão do produto (catálogo), valor do tenant e valor da obra. A obra vence o tenant, o tenant vence o padrão. Parâmetro marcado só para tenant não aceita valor por obra.
4. Toda alteração tem autor (do JWT), data, observação e fica no histórico (`app.auditoria_alteracao`). Nada é sobrescrito sem registro.
5. Só diretor e financeiro alteram. Os demais perfis veem os valores em vigor, sem formulário.
6. Parâmetro novo entra por uma linha no catálogo. A tela de configuração se monta a partir do catálogo, sem código novo para cada parâmetro. A view que consome o parâmetro precisa ler a coluna nova da configuração efetiva.
7. Nome de parâmetro e de valor em português, sem o nome do ERP de origem.

## 2. Objetos (migration 0007, dono `banco_config`, salvo onde indicado)

As migrations 0007 a 0014 ainda não foram aplicadas em nenhum banco remoto, então a personalização entra nelas mesmas. Nenhum número novo de migration.

### 2.1 `app.parametro` (catálogo global, só leitura para `authenticated`)

| Coluna | Tipo | Significado |
| --- | --- | --- |
| `codigo` | `text` pk | ex.: `reconhecimento.base_fracao_vendida` |
| `grupo` | `text` | `reconhecimento`, `dre`, `caixa`, `financiamento`, `comercial`, `simulacao`, `negocio`, `alerta`, `exibicao` |
| `nome` | `text` | rótulo da tela |
| `descricao` | `text` | o que muda no número quando o valor muda |
| `tipo` | `text` | `opcao`, `booleano`, `numero`, `inteiro`, `fracao`, `texto`, `data`, `fuso` |
| `opcoes` | `jsonb` | para `opcao`: lista de `{valor, rotulo, descricao}` |
| `minimo`, `maximo` | `numeric` | para número, inteiro e fração |
| `padrao` | `jsonb` | valor do produto |
| `escopo` | `text` | `tenant` ou `tenant_e_obra` |
| `ordem` | `integer` | ordem na tela |
| `exige_validacao_financeira` | `boolean` | a tela pede confirmação e observação (como o critério de reconhecimento) |

### 2.2 `app.parametro_valor` (por tenant e obra)

`id uuid pk`, `tenant_id`, `centro_custo_id uuid null` (nulo = valor do tenant), `codigo references app.parametro`, `valor jsonb not null`, `observacao text`, `autor uuid not null`, `atualizado_em timestamptz`. Único `(tenant_id, coalesce(centro_custo_id, uuid nulo), codigo)` (use `unique nulls not distinct`). Gatilho de validação (erro 23514 com mensagem clara): tipo, opção existente, faixa, fuso existente em `pg_timezone_names`, escopo (valor por obra só se `tenant_e_obra`; obra do mesmo tenant e `tipo = 'obra'`). Gatilhos `app.definir_autor` e `app.registrar_auditoria`. RLS: leitura por tenant e obra permitida (valor do tenant visível a todo o tenant); inserir, alterar e excluir só diretor e financeiro. Excluir um valor volta ao nível de cima.

### 2.3 `app.parametros_obra` (view, `security_invoker`)

Uma linha por centro de custo visível, com uma coluna tipada por parâmetro (nome da coluna = código com `.` trocado por `__`), já resolvida obra, tenant e padrão, mais `tenant_id` e `centro_custo_id`. E `app.parametros_tenant`: uma linha por tenant, só o nível tenant e padrão. Views e funções de marts juntam por `centro_custo_id` (ou `tenant_id`) com essas duas. Uma consulta, sem função por linha.

`app.configuracao_efetiva` (view para a tela): tenant, centro, código, valor em vigor, de onde veio (`padrao`, `tenant`, `obra`), autor e data do valor.

### 2.4 `app.mapa_codigo_origem` (códigos do ERP por tenant)

`tenant_id`, `dominio`, `codigo_origem`, `valor`, `rotulo`, `observacao`, `autor`, `atualizado_em`. Chave `(tenant_id, dominio, codigo_origem)`. Domínios e valores aceitos (gatilho 23514):

| Domínio | Valores | Padrão semeado para todo tenant (comportamento atual) |
| --- | --- | --- |
| `condicao_pagamento` | `entrada_direta`, `financiamento_comprador` | `FI` = financiamento; `AT`, `PM`, `BA`, `CH` = entrada direta |
| `situacao_unidade` | `disponivel`, `reservada`, `proposta`, `vendida`, `fora_de_venda` | `D` disponível, `C` reservada, `P` proposta, `V`, `O`, `G` vendida, `R` fora de venda (rótulo "reserva técnica") |
| `situacao_contrato` | `ativo`, `distratado`, `outro` | `1` ativo, `3` distratado |

Código que aparece no staging e não está no mapa: comportamento atual (condição vira entrada direta, situação de unidade vira fora de venda, contrato fica fora das contas de ativo) e aparece em `marts.pendencia_codigo_origem` com a quantidade de registros e o valor envolvido. Nunca silencioso. Novo tenant recebe os padrões por gatilho em `app.tenant` e pela migration para os existentes.

`staging.parcela_receber.origem` deixa de ser coluna gerada (`alter column origem drop expression`) e passa a ser gravada por `staging.recarregar` a partir do mapa (`financiamento_comprador` grava `repasse`, para manter o valor atual da coluna; o resto grava `direta`). `staging.contrato_venda` ganha `situacao_normalizada`. `marts.mapa_unidades` e `marts.estoque_atual` são recriadas na 0007 lendo o mapa, com as mesmas colunas e os mesmos valores de `situacao`.

### 2.5 `app.categoria_tenant` (subcategorias próprias, migration 0011, dono `banco_regras`)

Fica na 0011 porque referencia `app.categoria_gerencial`, criada lá. RLS, autor e auditoria como em 2.2.

`id`, `tenant_id`, `categoria_codigo references app.categoria_gerencial` (a categoria global à qual ela soma), `codigo`, `nome`, `ativa`. `app.mapa_conta_origem` (0011) ganha `subcategoria_id null`, que precisa ser da mesma categoria global. O DRE continua somando pela categoria global; as telas de despesa podem abrir por subcategoria.

### 2.6 `app.rotulo_personalizado`

`tenant_id`, `contexto` (`linha_dre`, `categoria`, `indicador`), `chave`, `rotulo`. Troca só o texto exibido. A definição do indicador continua a do produto.

## 3. Catálogo inicial

Padrão = comportamento atual. A coluna "Quem lê" é o dono da mudança.

| Código | Tipo e valores | Padrão | Escopo | Quem lê |
| --- | --- | --- | --- | --- |
| `negocio.fuso_horario` | fuso | `America/Sao_Paulo` | tenant | `app.data_referencia()` usa o fuso do tenant do JWT; sem JWT, o padrão (banco_config) |
| `alerta.carga_desatualizada_horas` | inteiro 1 a 168 | 26 | tenant | `app.situacao_carga()` (banco_config) |
| `reconhecimento.base_fracao_vendida` | `unidades`, `area_privativa`, `valor_tabela` | `unidades` | tenant_e_obra | `marts.reconhecimento_obra_mensal` (banco_regras) |
| `reconhecimento.incluir_terreno` | booleano | verdadeiro | tenant_e_obra | POC: custo incorrido e custo total com ou sem a categoria terreno (banco_regras) |
| `reconhecimento.cobertura_minima` | fração 0,5 a 1 | 1 | tenant_e_obra | POC fica disponível quando a fração classificada do custo acumulado é pelo menos esse valor; o motivo `custo_sem_categoria` só aparece abaixo dele, e a cobertura real sempre é exibida (banco_regras) |
| `reconhecimento.exigir_validacao_usuario` | booleano | verdadeiro | tenant | método `percentual_conclusao` só vale com `validado_por` preenchido; gravado pela carga sem usuário fica como `nao_definido` com motivo `criterio_sem_validador` (banco_regras) |
| `dre.competencia_titulo` | `emissao`, `emissao_ou_vencimento`, `vencimento` | `emissao` | tenant | competência das apropriações no DRE e em `despesa_mensal` (banco_regras) |
| `caixa.receber_vencido` | `excluir`, `mes_referencia` | `excluir` | tenant_e_obra | fluxo projetado: vencido a receber fica fora ou entra no mês de referência multiplicado por `caixa.fracao_recuperacao_vencido` (banco_regras) |
| `caixa.fracao_recuperacao_vencido` | fração 0 a 1 | 1 | tenant_e_obra | idem |
| `caixa.pagar_vencido` | `mes_referencia`, `excluir` | `mes_referencia` | tenant_e_obra | fluxo projetado (banco_regras) |
| `caixa.financiamento_pendente` | `incluir`, `excluir` | `incluir` | tenant_e_obra | financiamento pendente no caixa principal; a variante conservadora continua sem ele (banco_regras) |
| `caixa.liberacao_pendente` | `excluir`, `incluir` | `excluir` | tenant_e_obra | liberação `pendente` de crédito à produção no previsto (banco_regras) |
| `caixa.liberacao_atrasada` | `excluir`, `mes_referencia` | `excluir` | tenant_e_obra | liberação prevista vencida sem recebimento (banco_regras) |
| `caixa.custo_sem_titulo_passado` | `mes_referencia`, `ignorar` | `mes_referencia` | tenant_e_obra | fração da premissa de meses passados (banco_regras) |
| `caixa.consolidado_compensa_obras` | booleano | falso | tenant | com verdadeiro, `/fluxo` mostra primeiro a série consolidada de `marts.fluxo_projetado_consolidado` (que sempre existe) e o aporte consolidado; com falso, a lista por obra (painel_config) |
| `financiamento.data_origem_significa` | `contratacao`, `repasse` | `contratacao` | tenant | com `repasse`, a data do banco no contrato marca o financiamento como liberado, não só elegível (banco_regras) |
| `financiamento.retencao_padrao` | fração 0 a 0,5, ou nulo | nulo | tenant_e_obra | retenção usada quando a operação não informa a própria (banco_regras) |
| `comercial.meta_metodo` | `manual`, `automatica` | `manual` | tenant_e_obra | `marts.meta_automatica_mensal` e a visão gerencial (banco_regras) |
| `comercial.meta_horizonte` | `chaves`, `data_propria` | `chaves` | tenant_e_obra | fim do período da meta automática; `chaves` usa a maior data de entrega das unidades (banco_regras) |
| `comercial.meta_data_horizonte` | data | nulo | tenant_e_obra | usada com `data_propria` (banco_regras) |
| `comercial.meta_base` | `custo_orcado`, `estimativa_conclusao` | `custo_orcado` | tenant_e_obra | meta automática: falta vender = base menos VGV contratado, dividido pelos meses até o horizonte, refeito todo mês; unidades pelo ticket médio disponível a preço de hoje (CONTEXTO, tela da obra de 23/09) (banco_regras) |
| `simulacao.desconto` | fração 0 a 0,5 | 0 | tenant_e_obra | padrão do formulário e de `simular_fluxo` quando a premissa não informa (banco_regras e painel_config) |
| `simulacao.fracao_entrada` | fração | valor atual do padrão de `simular_fluxo` | tenant_e_obra | idem |
| `simulacao.fracao_parcelas` | fração | idem | tenant_e_obra | idem |
| `simulacao.fracao_financiamento` | fração | idem | tenant_e_obra | idem; as três somam 1 (conferido no nível em que forem gravadas e na resolução) |
| `simulacao.quantidade_parcelas` | inteiro 1 a 600 | idem | tenant_e_obra | idem |
| `simulacao.meses_ate_liberacao` | inteiro 0 a 600 | idem | tenant_e_obra | idem |
| `exibicao.periodo_padrao` | `mes`, `trimestre`, `ano_ate_mes`, `ultimos_12` | `ano_ate_mes` | tenant | filtro inicial das telas de demonstrativos (painel_config) |
| `exibicao.meses_grafico` | inteiro 12 a 120 | 36 | tenant | horizonte dos gráficos de fluxo (painel_config) |

O agente `banco_regras` confere os padrões de simulação atuais em `marts.simular_fluxo` (0013) e grava exatamente esses números no catálogo.

## 4. Tela `/configuracoes` (dono `painel_config`)

- Um bloco por grupo, montado do catálogo: nome, descrição, valor em vigor, de onde veio (produto, construtora, obra), autor e data, e o controle certo para o tipo.
- Seletor de escopo: construtora ou uma obra (só para parâmetros `tenant_e_obra`). "Voltar ao padrão" exclui o valor do nível escolhido.
- Parâmetro com `exige_validacao_financeira` pede confirmação e observação.
- Códigos da origem: tabela por domínio com os códigos vistos no staging, o valor mapeado e as pendências, com edição.
- Subcategorias e rótulos personalizados: listas editáveis.
- Critério de reconhecimento e mapeamento de contas continuam em `/dre`; a página de configurações leva até lá.
- Histórico: últimas alterações de configuração lidas de `app.auditoria_alteracao`.
- Server Actions no padrão de `painel/app/(painel)/planejamento/gravacao.ts`. Validação no servidor a partir do catálogo, gravação com o cliente do usuário, RLS decide.
- Consumo das preferências de exibição e dos padrões de simulação nas telas existentes (filtro inicial, horizonte do gráfico, formulário de simulação pré-preenchido, rótulos personalizados no DRE).

## 5. Testes obrigatórios

- Sem nenhum valor gravado, todos os testes atuais passam e os números da demo não mudam (regressão contra os resultados de antes).
- Para cada parâmetro com "Quem lê": um caso com números conhecidos para cada valor, mostrando o efeito, e um caso de obra sobrepondo o tenant.
- Mapa de códigos: código novo em pendência; remapear `FI` muda a origem na próxima recarga; situação de unidade remapeada muda o estoque.
- Validação: tipo errado, opção inexistente, fora da faixa, fuso inválido, valor por obra em parâmetro só de tenant, obra de outro tenant, frações de simulação que não somam 1.
- Isolamento: gerente e leitura não gravam; valor da obra A não aparece para quem só vê a obra B; outro tenant invisível; histórico registra autor.
- Desempenho: as telas continuam abaixo de 2 s no volume do piloto (`scripts/gerar_volume_piloto.py` e `scripts/medir_volume_piloto.sql`).

## 6. O que a implementação acrescentou

- `app.parametro.aceita_nulo`: parâmetros com padrão nulo (`financiamento.retencao_padrao`, `comercial.meta_data_horizonte`).
- `app.erro_valor_parametro(codigo, valor)`: mensagem de erro em português ou nulo; usada pelo gatilho e disponível para a tela.
- `app.gerar_views_parametros()`: recria `app.parametros_obra` e `app.parametros_tenant` a partir do catálogo. Parâmetro novo: inserir a linha no catálogo e chamar a função numa migration.
- `app.valor_codigo_origem`: valores aceitos por domínio do mapa de códigos, com rótulo.
- A soma das frações de simulação é conferida por gatilho de restrição em cada nível; a tela grava as três numa instrução só.
- Padrões de simulação semeados: entrada 0,10, parcelas 0,30, financiamento 0,60, 24 parcelas, 4 meses até a liberação, desconto 0. Venda simulada sem composição ou sem prazo usa esses padrões da obra (antes era erro 22023). Sem venda, `simular_fluxo(obra, '{}')` devolve o mesmo que antes.
- Colunas novas: `marts.reconhecimento_obra_mensal.base_fracao_vendida` e `cobertura_custo`; `marts.financiamento_contrato.etapa_efetiva`; `marts.saldo_operacao_credito.origem_retencao` (`operacao`, `padrao` ou nulo); `marts.fluxo_projetado_mensal.vencido_recuperacao_prevista` (também em `app.projecao_mensal`).
- Views novas: `app.criterio_reconhecimento_efetivo`, `marts.meta_automatica_mensal`, `marts.fluxo_projetado_consolidado` (acumulado sobre a soma mensal das obras visíveis) e `marts.pendencia_codigo_origem`.
- Motivos novos de indisponível: `criterio_sem_validador`, `area_privativa_ausente`, `valor_tabela_ausente`, `horizonte_ausente`, `horizonte_encerrado`, `sem_estoque_disponivel`.
- Com `reconhecimento.exigir_validacao_usuario` verdadeiro (padrão), critério gravado sem `validado_por` não vale. Carga sem JWT pode informar o validador.
- Terreno fora do POC: sai do percentual e da receita; o custo reconhecido continua levando o terreno das unidades vendidas.
- `estoque_atual`: unidade com situação nula passa a contar como indisponível (antes entrava só no total).
- `marts.mapa_unidades` e `marts.estoque_atual` passaram a usar `app.data_referencia()` no lugar de `current_date` para a tabela de preço e o índice vigentes. Com a data de referência de hoje o resultado é o mesmo; com data fixada no passado, o preço segue aquela data.
- Subcategorias: existem, são validadas e aceitam mapeamento de conta, mas nenhuma tela abre por subcategoria ainda.
