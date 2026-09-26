# Revisão independente: eventos financeiros, DRE, receitas, despesas, financiamento e planejamento

Revisão das migrations 0007, 0011, 0012 e 0013 e das telas novas do painel, feita em 26/09/2026 sobre o banco local (Postgres 16 com o stub do Supabase). Casos próprios em `supabase/tests/revisao_independente.sql`, medição em `scripts/medir_volume_piloto.sql` com os dados de `scripts/gerar_volume_piloto.py`.

Resultado curto: nenhum achado bloqueante. Três importantes: uma consulta passa de 2 s no volume do piloto por causa das políticas antigas de RLS, a visão geral mostra dois números diferentes para o mesmo aporte, e o mapeamento de contas e o critério de reconhecimento não têm tela. Os 98 casos independentes passaram, assim como os 460 dos implementadores, em banco limpo e com a demo.

## Achados

### Importantes

#### I1. Políticas de RLS antigas avaliam `app.tenant_atual()` linha a linha e levam `marts.explicacao_desvio` a 2,4 s

- Onde: `supabase/migrations/0002_staging.sql:135-141`, `0004_precos.sql:98-110`, `0001_esquema.sql:88-90` (políticas escritas como `tenant_id = app.tenant_atual()`, sem `(select ...)`). O efeito aparece em `0012_financiamento_medicoes.sql:305` (`contrato as materialized` de `marts.recebivel_projetado`) usado por `0013_planejamento_projecoes.sql:563` (`recebivel` de `explicacao_desvio`).
- Evidência: no volume do piloto, como diretor, `select * from marts.explicacao_desvio where competencia = '2026-09-01'` leva 2.415 ms; filtrada por uma obra, 1.151 ms. O plano mostra `CTE Scan on contrato (rows=800 loops=197) Filter: (tenant_id = app.tenant_atual())` com `Rows Removed by Join Filter: 157403`, duas vezes (uma por ramo da view). O filtro de tenant da parcela é propagado pela junção para o CTE e a função `security definer` roda 157 mil vezes por ramo. Recriando, dentro de uma transação, as políticas das tabelas de 0002 e 0004 e de `app.centro_custo` com `(select app.tenant_atual())`, a mesma consulta cai de 2.455 ms para 127 ms; `resumo_receitas_obra`, `carteira_recebiveis` e `resumo_projecao_obra` ficam iguais (253/276, 443/482, 251/272 ms).
- Impacto: a pergunta pronta `meta-do-mes` do assistente passa da meta de 2 s (2,4 s só nessa consulta) e a tela de planejamento da obra fica em 1,5 s somadas as consultas, com uma de 1,15 s. Num servidor mais lento que o Postgres local, a tela de planejamento também chega perto da meta.
- Correção sugerida: migration nova (número a definir pelo coordenador, porque 0001 a 0006 não se editam) que faz `drop policy` e `create policy` nas tabelas `staging.unidade`, `contrato_venda`, `parcela_receber`, `titulo_pagar`, `item_orcamento`, `indice_valor`, `tabela_preco`, `tabela_preco_unidade`, `unidade_valor`, `app.centro_custo` e `app.tenant` com `(select app.tenant_atual())` e `(select app.obras_permitidas())`, que é o padrão já usado nas tabelas novas. Em segundo plano, trocar o `contrato as materialized` de `recebivel_projetado` por junção direta, para o planejador poder usar hash join.

#### I2. Visão geral mostra dois números diferentes para o aporte e dois conceitos com o mesmo rótulo "Caixa gerado acumulado"

- Onde: `painel/componentes/TabelaObras.tsx:28-29` (colunas `caixa_atual` e `exposicao_maxima` de `marts.posicao_financeira_obra`, que lê `fluxo_caixa_mensal` com a regra antiga) e `painel/app/(painel)/page.tsx:96` (cartão "Maior aporte na projeção" de `marts.resumo_projecao_obra`). No assistente, `exposicao-maxima` (`painel/lib/perguntas-prontas.ts:100-108`) responde pela posição e `aporte-necessario` pela projeção. O contrato de dados (seção 8) dá o rótulo "Caixa gerado acumulado" tanto a `caixa_atual` (só realizado) quanto a `caixa_gerado_acumulado` (realizado mais previsto).
- Evidência: na demo, com uma operação de crédito à produção e uma liberação recebida de R$ 3.000.000,00 por lançamento manual em 01/06/2026 na Parque das Aguas, a mesma tela mostra "Exposição máxima" 15.648.885,79 e "Maior aporte na projeção" 12.648.885,79; `caixa_atual` continua em -14.178.735,42. Sem complemento manual e sem custo sem título distribuído os dois coincidem, por isso a demo atual não mostra a diferença.
- Impacto: o diretor vê duas respostas para "quanto dinheiro próprio a obra precisa" na mesma página, e o assistente dá números diferentes conforme a pergunta escolhida. A diferença cresce com crédito à produção, premissa de custo sem título e financiamento com data prevista diferente do vencimento.
- Correção sugerida: decidir uma fonte. O mais simples é a coluna "Exposição máxima" e a pergunta `exposicao-maxima` passarem a ler `resumo_projecao_obra.exposicao_maxima_projetada`, e `caixa_atual` ganhar o rótulo "Caixa realizado acumulado" no contrato, em `explicacoes.ts` e em `TabelaObras.tsx`.

#### I3. Mapeamento de contas e critério de reconhecimento só se gravam por SQL

- Onde: contrato de dados, seção 6.3 ("Escrita do mapeamento e do critério em Server Action que confere `getUser()`"). Não há Server Action nem formulário: `grep -rl "mapa_conta_origem\|criterio_reconhecimento" painel/app painel/lib painel/componentes` não devolve nada.
- Evidência: a tela do DRE lista as pendências de classificação e o motivo "critério de reconhecimento não validado pelo financeiro", mas não oferece como resolver.
- Impacto: no piloto, receita reconhecida, resultado bruto e resultado gerencial ficam indisponíveis até alguém rodar SQL. Se isso for feito com a chave de serviço, `app.registrar_validacao_criterio` grava `validado_por` nulo (não há `auth.uid()`), e a rastreabilidade de quem validou o critério se perde.
- Correção sugerida: Server Actions em `/dre` (dono `painel_demonstrativos`) para inserir e alterar `app.mapa_conta_origem` e `app.criterio_reconhecimento` com o cliente do usuário, no mesmo padrão de `planejamento/gravacao.ts`.

### Menores

#### M1. O sql de `simular-vendas` no catálogo perde meses da simulação

- Onde: `painel/lib/perguntas-prontas.ts:480`. O `full join` com `where f.centro_custo_id = $1` descarta as linhas que só existem na simulação.
- Evidência: na demo, Residencial Aurora com 5 vendas em out/2026 e financiamento 6 meses depois, `simular_fluxo` devolve 61 meses (até 2029-10) e o fluxo base 60 (até 2029-09); o sql do catálogo devolve 60. A tela e a função TypeScript mostram os 61, então hoje o número que o usuário vê está certo; o texto que vai virar contrato do PT-07 não está.
- Correção: `select s.competencia, f.caixa_gerado_acumulado as base, s.caixa_gerado_acumulado as simulado, ... from marts.simular_fluxo($1, $2) s left join marts.fluxo_projetado_mensal f on f.centro_custo_id = $1 and f.competencia = s.competencia order by s.competencia` (o calendário da simulação já cobre os meses da base).

#### M2. Rateio com `rate` em só parte dos itens descarta os itens sem percentual

- Onde: `supabase/migrations/0007_eventos_financeiros.sql:379`.
- Evidência: título de R$ 1.000,00 com `buildingsCosts` `[{obra 1, amount 500, rate 100}, {obra 2, amount 500}]` vira uma apropriação de 100% na obra 1; a obra 2 some sem aviso.
- Impacto: baixo enquanto `rate` for hipótese, mas o erro seria silencioso.
- Correção: usar `rate` só quando todos os itens do título o trazem (`bool_and`), senão `amount`; ou `raise notice` com a contagem.

#### M3. DRE omite, sem sinal, títulos com competência depois do mês de referência

- Onde: `0011_dre_gerencial.sql:714-719` (calendário até `mes_ref`) e a regra R11 do contrato (seção 7), que fala em "todos os meses".
- Evidência: na demo, 85 apropriações somando R$ 5.500.648,51 têm emissão depois de set/2026; no volume, 4.716 somando R$ 138.894.532,17. Elas entram em `despesa_mensal` mas em nenhuma linha do DRE, nem em "sem data de competência". Com a restrição `data_competencia < mes_ref + 1 mês`, R11 fecha nos 11 centros do volume; sem ela, falha nas 11.
- Correção: escrever a restrição em R11 no contrato e, se o financeiro quiser, mostrar no cabeçalho do DRE o total com competência futura.

#### M4. Nome do comprador continua legível por SQL no staging

- Onde: `staging.contrato_venda.nome_cliente`, com `grant select` a `authenticated` desde `0002_staging.sql:141` e `usage` no schema `staging`.
- Evidência: consulta a `information_schema.columns` lista `staging.contrato_venda.nome_cliente`; nenhuma view de `marts`, catálogo ou tela usa a coluna (caso 12 dos testes independentes confere que `marts` não tem coluna de nome, CPF ou cliente).
- Impacto: `staging` não está exposto na API, então hoje ninguém chega à coluna. Quando o PT-07 rodar SQL gerado com o JWT do usuário, o validador precisa barrar `staging` por parser, não por regex (o `lib/validador-sql.ts` atual usa regex, achado 4.6 já aberto).
- Correção: parar de gravar `nome_cliente` (nada o lê) ou trocar o grant por colunas, sem ela.

#### M5. Liberação `pendente` e liberação prevista atrasada ficam fora do fluxo sem coluna informativa

- Onde: `0013_planejamento_projecoes.sql:354-358` (só `prevista` com `data_prevista >= ref` entra em `credito_producao_previsto`) contra `0012_financiamento_medicoes.sql:337` (`previsto_aberto` soma `prevista` e `pendente`).
- Impacto: a tela de financiamento mostra como previsto um valor que o fluxo não projeta, e uma liberação que atrasou desaparece do caixa previsto sem ir para um campo parecido com `vencido_a_receber`. Segue o contrato; é pergunta para João e o financeiro, não defeito de código.

#### M6. Duas idas ao banco em sequência para a premissa vigente

- Onde: `painel/lib/consultas/planejamento.ts:275-291` (premissa e depois os meses dela).
- Correção: uma consulta com recurso embutido do PostgREST (`premissa_distribuicao_custo(..., premissa_distribuicao_custo_mes(competencia, fracao))`). Custo atual pequeno (menos de 1 ms cada no volume), só latência de rede.

#### M7. Páginas novas não conferem a identidade dentro delas

- Onde: `painel/app/(painel)/dre/page.tsx`, `receitas/page.tsx`, `despesas/page.tsx`, `fluxo/**`, `planejamento/page.tsx`, `assistente/page.tsx`. Só `layout.tsx` e `planejamento/financiamento/page.tsx` chamam `exigirIdentidade()`.
- Impacto: nenhum vazamento, porque sem sessão as consultas rodam como `anon`, que não tem `usage` em `app` nem `marts` (testes 92 a 95), e o proxy redireciona. Mas o CLAUDE.md pede a conferência em cada rota.
- Correção: chamar `exigirIdentidade()` no começo de cada página (com `cache` do React não custa outra ida ao Auth).

#### M8. Perfil conferido nas Server Actions pode não ser o do tenant do JWT

- Onde: `painel/lib/consultas/planejamento.ts:303-309` (`usuario_tenant` com `limit(1)`, sem ordem nem filtro de tenant).
- Impacto: só a mensagem; quem decide é o RLS. Para o futuro módulo de escritório contábil (usuário em vários tenants) precisa ler o perfil pelo mesmo tenant de `app.tenant_atual()`.

#### M9. Listas da simulação sem teto de tamanho no banco

- Onde: `0013_planejamento_projecoes.sql:785-878`. `novas_vendas` e `custo_campanha` aceitam qualquer quantidade de itens; o painel limita no formulário, a API direta não.
- Correção: recusar com 22023 acima de, por exemplo, 120 itens. O `statement_timeout` do papel `authenticated` no Supabase já protege contra abuso grande.

#### M10. Nome do ERP e travessão fora de código novo

- `supabase/config.toml:5` tinha um `project_id` com o nome do ERP (arquivo do coordenador, gerado pela CLI). `painel/componentes/financeiro/ValorEstado.tsx:19` usa o caractere de travessão como traço de valor indisponível na tela; é texto de interface pedido pela seção 9 do contrato, não comentário, mas o CLAUDE.md proíbe o caractere em documentos. As demais menções ao ERP estão em `CONTEXTO.md`, `docs/plano_implementacao.md` e `docs/README.md`, que são contexto do negócio.

## Tempos no volume do piloto

Volume gerado por `scripts/gerar_volume_piloto.py` num tenant separado ("Volume sintético do piloto (revisão)") no mesmo banco da demo: 10 obras, 1.000 unidades, 800 contratos (5% distratados), 30.000 parcelas, 12.911 recebimentos, 20.000 títulos, 21.024 apropriações (5% rateadas), 15.724 pagamentos, 2.000 itens de orçamento. Postgres 16 local, cache quente, data de referência 26/09/2026.

Recarga do staging (duas rodadas, contagens idênticas nas 13 tabelas):

| Rodada | `staging.recarregar` | `staging.recarregar_precos` |
| --- | --- | --- |
| 1 | 1,57 s | 0,06 s |
| 2 | 1,88 s | 0,06 s |

Gravação dos 53.843 registros em `raw.registro`: 1,31 s.

Tempo por tela, em ms, menor de duas execuções (execução mais planejamento), somando as três consultas comuns (identidade, carga e centros, cerca de 3 ms). As telas disparam as consultas com `Promise.all`, então o tempo real fica entre a maior consulta e a soma.

| Tela | Recorte | Consultas | Diretor soma | Diretor maior | Gerente soma | Gerente maior |
| --- | --- | --- | --- | --- | --- | --- |
| Visão geral | consolidado | 6 | 923 | 257 | 258 | 71 |
| DRE | consolidado | 5 | 558 | 174 | 158 | 45 |
| DRE | obra | 5 | 491 | 154 | 157 | 46 |
| Receitas | consolidado | 6 | 1.489 | 444 | 225 | 56 |
| Receitas | obra | 6 | 225 | 62 | 199 | 55 |
| Despesas | consolidado | 2 | 185 | 102 | 52 | 27 |
| Despesas | obra | 3 | 72 | 29 | 66 | 24 |
| Fluxo | consolidado | 1 | 262 | 259 | 77 | 74 |
| Fluxo | obra (com cenário) | 3 | 209 | 87 | 173 | 66 |
| Simular | obra | 4 | 243 | 106 | 199 | 81 |
| Planejamento | consolidado | 1 | 206 | 204 | 45 | 43 |
| Planejamento | obra | 8 | 1.512 | 1.158 | 322 | 149 |
| Financiamento | obra | 5 | 17 | 13 | 17 | 13 |
| Obra (tela antiga) | obra | 3 | 175 | 115 | 116 | 53 |
| Mapa de unidades | obra | 2 | 50 | 36 | 52 | 38 |
| Assistente (5 consultas das perguntas mais pesadas) | consolidado | 5 | 3.326 | 2.420 | 293 | 79 |

Consultas mais lentas (diretor, ms): `explicacao_desvio` de um mês consolidado 2.415 e de uma obra 1.151 (achado I1); `carteira_recebiveis` página 1 consolidada 443 (a situação é calculada para as 30 mil parcelas antes de ordenar); `recebimento_mensal_consolidado` 320; `resumo_receitas_obra` 239 a 256; `resumo_projecao_obra` 249 a 252; `comparativo_projecao` da obra 220; `pendencias_pos_entrega` consolidada 201; `dre_periodo` e `dre_mensal_consolidado` 150 a 165.

Seq Scan com mais de 5 mil linhas lidas: `titulo_pagar_apropriacao` (21.575 linhas, todas as de todos os tenants) em `pendencia_classificacao` e `dre_mensal`, porque a view agrupa por tenant e conta inteira; `pagamento` e `recebimento` (16 mil e 15 mil) em `comparativo_projecao`, `visao_gerencial_mensal` e `fluxo_projetado_mensal` sem filtro de obra. Como o tenant do volume tem 97% das linhas do banco, o planejador prefere ler a tabela inteira; com muitos tenants o índice que começa por `tenant_id` passa a valer. Nenhuma coluna de `where`, `join` ou RLS das tabelas novas ficou sem índice.

N+1 no painel: nenhum laço com consulta. Há duas dependências em sequência de uma consulta cada (premissa e meses, achado M6; versões e metas no planejamento) e `incluirNomeObra` nas perguntas antigas faz uma consulta extra de nomes por pergunta.

## Casos independentes

Arquivo `supabase/tests/revisao_independente.sql`, 98 testes. Tenant R (`a1000000-...0001`) com obras A, B, C e D e tenant X (`a1000000-...0002`) com os mesmos `id_origem` de obra (9101), contrato (7001), parcela e título (8001), para pegar junção sem tenant. Data de referência 20/11/2026, com uma passagem por 15/12/2026. Contas feitas à mão:

- Obra A, contrato 7001 de R$ 500.000,00: entrada de 50.000 paga 20.000 em 10/03 e 30.000 em 02/04; PM de 50.000 vencida em 10/10 com 20.000 pagos (saldo 30.000, 41 dias de atraso); PM de 50.000 em 25/11 e em 10/12; FI de 300.000 em 15/02/2027 sem etapa. Contrato 7002 de 400.000 com entrada de 100.000 paga e FI de 300.000 em 20/12 com data de financiamento na origem. Contrato 7003 de 350.000 distratado em 15/09 com 35.000 pagos e 315.000 em aberto. VGV ativo 900.000; recebido 20.000 + 30.000 + 20.000 + 100.000 + 35.000 = 205.000; vencido 30.000; a vencer direto 100.000; a vencer financiamento 600.000; próximo mês (dezembro) 50.000 direto e 300.000 de financiamento; saldo distratado 315.000.
- Obra B, contrato 7004 de 250.000: 100.000 pagos, estornados e pagos de novo (fevereiro fica 0, março 100.000); parcela de 150.000 renegociada em duas de 75.000 (05/12 e 05/01/2027). Previsto contratual 100.000 + 75.000 + 75.000 = 250.000.
- Em 15/12/2026 o próximo mês é janeiro de 2027: na obra B só a parcela de 05/01 (75.000); na obra A nada, e o vencido direto vai a 30.000 + 50.000 + 50.000 = 130.000.
- Título 8001 de 1.000,00 em três obras com peso igual: 333,33 nas obras B e C e 333,34 na A (principal). Pagamentos de 500 + 500 repartidos pelo acumulado: na A 166,66 + 166,68; na B e na C 166,67 + 166,66.
- Obra A: lançado 333,34 + 10.000 + 3.000 + 5.000 = 18.333,34; pago 166,66 + 166,68 + 4.000 + 4.800 = 9.133,34; vencido 6.000; a vencer 3.000; desconto 200; orçamento 50.000; remanescente 31.666,66; estimativa 50.000 (o orçamento, sem somar títulos de novo); cobertura 15.333,34 / 18.333,34 = 0,836364. Obra B com orçamento zero: remanescente 0,00 e desvio 333,33. Obra C sem orçamento: tudo nulo com `orcamento_ausente`.
- Obra D com percentual de conclusão validado: orçamento 100.000, custo de 20.000 em agosto e 30.000 em setembro, quatro unidades, venda de 200.000 em agosto e de 300.000 em setembro distratada em 20/10. POC 0,2 e 0,5; receita acumulada 40.000, 250.000, 100.000; custo acumulado 5.000, 25.000, 12.500; no ano, resultado gerencial 100.000 - 12.500 = 87.500.
- Fluxo projetado da obra A: caixa gerado 195.866,66 em outubro, 239.866,66 em novembro (50.000 a receber menos 6.000 vencidos a pagar; os 30.000 vencidos a receber ficam fora), 586.866,66 em dezembro e 886.866,66 em fevereiro de 2027. Obra C: aporte de 333,33 em outubro.
- Premissa de meses 0,333333 (outubro, que já passou e vai para novembro), 0,333333 (dezembro) e 0,333334 (janeiro) sobre 31.666,66: 10.555,54, 10.555,54 e 10.555,58 (o centavo de resíduo vai para a maior fração).
- Operação de 1.000.000 com retenção de 5%: medição aprovada de 400.000 não muda o fluxo; liberação recebida de 300.000 por lançamento manual e prevista de 600.000; mais 150.000 passaria do contratado e é recusada; saldo liberável 650.000; não programado 50.000; medido e não liberado 100.000.
- Simulação na obra A com ticket (300.000 + 320.000) / 2 = 310.000 e 10% de desconto: venda de 279.000 em dezembro e outra em janeiro (pedidas 3, estoque 1); entrada 27.900, três parcelas de 27.900, financiamento de 167.400 dois meses depois. Direto: 27.900, 55.800, 55.800, 55.800, 27.900; financiamento 167.400 em fevereiro e em março.
- Versões: a versão 1 guarda 229.311,12 em novembro; depois da liberação de 300.000 a versão 2 guarda 529.311,12 e o comparativo mostra diferença de 300.000.

## Verificado e passou

- 98 de 98 testes independentes, em banco limpo e com a demo e o volume carregados. Suíte completa de `supabase/tests/`: 558 ok e 0 falha em cada banco (dre_gerencial 99, eventos_financeiros 66, financiamento_medicoes 69, isolamento_dre 53, isolamento_eventos 27, isolamento_perfis 12, isolamento_planejamento 51, planejamento_projecoes 83, revisao_independente 98). `medir_volume_piloto.sql` roda e termina em rollback nos dois bancos.
- Painel: `npx next typegen` ok, `npx tsc --noEmit` sem erro, `npm run lint` sem aviso, `npx vitest run` com 221 testes em 9 arquivos passando.
- Regras de reconciliação no volume, como diretor, nas 10 obras: R1, R2, R6, R7, R13, R14, R15, R16 (simulação com `{}` igual ao fluxo em todas as obras) e R19 sem divergência. R11 fecha com a restrição do achado M3.
- Recarga idempotente: dez tabelas do staging com a mesma assinatura (contagem e md5 das linhas) depois de duas recargas extras; o complemento manual (liberações e versões) sobrevive à recarga; recarregar um tenant não mexe no outro.
- Isolamento: gerente, leitura, diretor de outro tenant e anônimo conferidos em detalhe (carteira), totais (resumos), consolidados (DRE e custos), funções de período, simulação, fluxo, complementos e escrita. O `user_metadata` com perfil de diretor não muda nada.
- Segurança pelo catálogo (banco com as 10 migrations): toda tabela de `app` e `staging` com `enable` e `force row level security` (só `raw.registro` sem RLS, sem grant e sem `usage` para `authenticated`); nenhuma tabela com duas políticas permissivas na mesma ação; nenhuma política `ALL`, nenhuma `using (true)`, nenhuma leitura de `user_metadata`; todas as views de `app` e `marts` com `security_invoker=true`; as oito funções `security definer` com `search_path=""`, e as que o usuário não chama (`claims_jwt`, `registrar_auditoria`, `recarregar`, `recarregar_precos`) sem execute para `public`, `anon` e `authenticated`; nenhuma função de `app`, `staging` ou `marts` executável por `anon`; nenhuma função de gatilho executável por `authenticated`; `anon` sem `usage` em `app`, `staging`, `marts` e `raw`; `staging.titulo_pagar` (com o credor) sem select para `authenticated`; escrita só nas tabelas de complemento, com update apenas onde o contrato prevê e sem delete fora de `mapa_conta_origem`.
- Painel: nenhuma `service_role`, nenhum `console.log`, nenhuma mensagem de banco na tela (erro vira código e o código vira frase em `mensagens.ts` e `mensagens-planejamento.ts`); Server Actions de planejamento e financiamento conferem `getUser()`, perfil e obra antes de gravar e gravam com o cliente do usuário; ids de obra validados como UUID antes de ir ao banco; premissas da simulação mandadas como objeto.
- Dashboard e assistente: os 34 sql do catálogo em `lib/perguntas-prontas.ts` rodam na demo com as colunas que existem; as perguntas novas chamam as mesmas funções de `lib/consultas` que as telas (teste Vitest do R20). Divergência só no texto do sql de `simular-vendas` (M1).
- Telas antigas: visão geral, obras, mapa de unidades e assistente leem `posicao_financeira_obra`, `fluxo_caixa_mensal`, `fluxo_caixa_cenario`, `mapa_unidades`, `cobertura_orcamento_obra`, `vso_mensal` e `estoque_atual` com colunas que existem (rodadas na medição e no catálogo); `listarObras` e `buscarObra` filtram `tipo = 'obra'`.
- Texto: nenhum "lucro líquido" ou "saldo bancário" como rótulo (só em frases que negam), nenhum TODO, nenhum travessão em comentário ou documento novo, nenhum nome do ERP em código novo.

## Não verificado

- Tempos no Supabase remoto (sa-east-1, plano gratuito), com PostgREST, rede e concorrência entre as consultas do `Promise.all`; os números acima são do Postgres local com cache quente.
- Comportamento real das telas no navegador (não subi o `next dev` com sessão); a revisão das páginas foi por leitura de código, tipos e testes.
- Campos da origem marcados como hipótese no contrato (seção 5): o volume usa os mesmos nomes sintéticos, então não confirma nada sobre a API real.
- `mapa_unidades` ainda usa `current_date` (fora do escopo, PT-06); a simulação com `app.data_referencia` fixada em outro dia usa o preço de hoje.
- Os arquivos de `painel_planejamento` passaram em tsc, lint e vitest no fim da revisão; se mudarem depois, a conferência de M1, M6 e M9 precisa ser refeita.

## Situação depois da rodada de correções (26/09/2026)

| Achado | Situação |
| --- | --- |
| I1 | Corrigido. Migration 0014 reescreve as políticas antigas com `(select app.tenant_atual())`, e `marts.recebivel_projetado` (0012) perdeu o CTE materializado. `explicacao_desvio` consolidado no volume: de 2.369 ms para 45 ms |
| I2 | Corrigido. Visão geral, tabela de obras, tela da obra e a pergunta `exposicao-maxima` leem o aporte de `marts.resumo_projecao_obra`. `caixa_atual` passou a "Caixa realizado acumulado" |
| I3 | Corrigido. `/dre` tem Server Actions para classificar conta e registrar o critério, só para diretor e financeiro |
| M1 | Corrigido. O sql de `simular-vendas` parte da simulação |
| M2 | Corrigido na 0007: `rate` só vale quando todos os itens do título o trazem. Teste novo em `eventos_financeiros.sql` |
| M3 | Registrado no contrato (R11 com competência até o mês de referência) |
| M4 | Mantido: o plano (4.1, item 17) permite o nome só no staging, que não é exposto. Revisar no PT-07 |
| M5 | Pergunta para João e o financeiro (contrato, seção 10) |
| M6 | Corrigido: premissa e meses numa consulta |
| M7 | Corrigido: `exigirIdentidade()` em todas as páginas novas, com `cache` do React |
| M8 | Corrigido: perfil lido por `app.perfil_atual()` |
| M9 | Corrigido: simulação recusa listas acima de 120 itens (22023) |
| M10 | Corrigido: `project_id` renomeado e marca de indisponível sem travessão |

Depois das correções: 562 testes pgTAP passando em banco limpo e com a demo; 233 testes vitest; tsc, lint e build limpos. No volume do piloto, a tela mais pesada (receitas consolidado, diretor) soma 1,45 s em sequência, com a maior consulta em 426 ms.

## Rodada 2: configuração por cliente

Revisão das partes de configuração nas migrations 0007, 0011, 0012 e 0013, do contrato `docs/financeiro/configuracao.md` e da tela `/configuracoes`, feita em 26/09/2026 no banco local. Os casos novos estão no fim de `supabase/tests/revisao_independente.sql`, num tenant próprio (C, `a1000000-...0003`) com as obras E (9201) e F (9202). O arquivo passou de `no_plan()` para `plan(217)`: 98 casos da rodada 1 e 119 novos.

Resultado curto: um achado importante (a data de referência quebra na segunda transação de uma sessão sem JWT) e quatro menores. Com tudo no padrão, as 33 views que já existiam e as funções de período e de simulação devolvem os mesmos números do commit c4d2b66, na demo e no volume do piloto. Os 914 testes pgTAP passam em banco limpo, com a demo e com demo mais volume. Nenhuma tela passa de 2 s.

### Achados

#### R2-I1 (importante). `app.data_referencia()` falha a partir da segunda transação de uma sessão sem JWT

- Onde: `supabase/migrations/0007_eventos_financeiros.sql`, função `app.data_referencia()` (a memória do fuso em `app.fuso_claims` e `app.fuso_valor`).
- Evidência: numa sessão `psql` como dono do banco, sem data fixada, `select count(*) from marts.resumo_receitas_obra;` funciona e a mesma consulta logo em seguida dá `ERROR: time zone "" not recognized`. A primeira chamada grava as duas variáveis com `set_config(..., true)`. No fim da transação o Postgres não as apaga: elas voltam como texto vazio. Na transação seguinte `v_claims` também é vazio (não há JWT), a função acha que a memória vale e chama `now() at time zone ''`.
- Quem é afetado: toda conexão direta ao banco que faça mais de uma transação sem `request.jwt.claims`: o carregador noturno se consultar `marts` depois de gravar, o editor de SQL, `psql`, tarefas agendadas. O painel não é afetado, porque o PostgREST sempre preenche os claims (ao menos `{"role": ...}`); com claims preenchidos o erro não aparece (conferido com `{"role":"service_role"}` em duas transações).
- Por que os testes não pegam: cada arquivo pgTAP roda numa transação só.
- Correção sugerida: tratar valor vazio como memória ausente, por exemplo `if coalesce(current_setting('app.fuso_valor', true), '') = '' or current_setting('app.fuso_claims', true) is distinct from v_claims then`. Um teste possível: dentro da transação, `select set_config('app.fuso_claims', '', true), set_config('app.fuso_valor', '', true);` sem claims e depois `app.data_referencia()` sem erro.

#### R2-M1 (menor). Simulação com `cancelar_contratos` mantém o vencido recuperado do contrato cancelado

- Onde: `0013_planejamento_projecoes.sql`, `marts.simular_fluxo`, ramo que soma `b.vencido_recuperacao_prevista` da base sem olhar `v_cancelar`.
- Evidência: tenant C, obra F com `caixa.receber_vencido = mes_referencia`. Só o contrato 7201 tem parcela vencida (40 mil). `simular_fluxo(obra F, '{"cancelar_contratos":[7201]}')` tira a parcela de dezembro (carteira prevista de 40 mil para 0) mas mantém os 40 mil de novembro.
- Correção: calcular o vencido recuperado a partir de `marts.recebivel_projetado` com o mesmo filtro de contratos cancelados, ou descontar o vencido dos cancelados.

#### R2-M2 (menor). Subcategoria sem uso

- `app.categoria_tenant` e `app.mapa_conta_origem.subcategoria_id` existem, mas nenhuma view de `marts` lê a subcategoria e o painel não liga conta a subcategoria (`grep -rn subcategoria_id painel/app painel/lib painel/componentes` não devolve nada). A tela cria subcategorias que não aparecem em lugar nenhum. O contrato (2.5) diz que as telas de despesa podem abrir por subcategoria; hoje não abrem. Os totais não mudam (conferido).

#### R2-M3 (menor). Validador do critério aceita qualquer UUID quando não há JWT

- Onde: `0011_dre_gerencial.sql`, `app.registrar_validacao_criterio`. Sem `auth.uid()` e fora dos papéis `authenticated` e `anon` (dono do banco ou `service_role`), fica o `validado_por` informado.
- Evidência: `scripts/gerar_volume_piloto.py` grava `validado_por = 00000000-0000-0000-0000-000000000000` e o percentual de conclusão passa a valer. É o que o contrato permite (seção 6, "carga sem JWT pode informar o validador"), mas a rastreabilidade depende de quem roda a carga. Sugestão: exigir que o validador seja um usuário do tenant com perfil diretor ou financeiro.

#### R2-M4 (menor). `marts.mapa_unidades` passou a usar a data de referência no lugar de `current_date`

- A troca corrige o que a rodada 1 deixou em "não verificado", mas não está na lista da seção 6 do contrato. Com a data fixada no passado, a tabela de preço e o índice vigentes mudam. Em 30/06/2025, as 240 unidades da demo e as 1.000 do volume perdem tabela e índice (valor passa a vir do cadastro), e isso muda `posicao_financeira_obra.estoque_a_vender` do volume e o ticket das vendas simuladas. Em produção muda só perto da meia-noite, quando o dia em São Paulo difere do dia UTC do servidor. Registrar no contrato.

#### Observação de processo

`supabase/tests/revisao_independente.sql` e `scripts/gerar_volume_piloto.py` são arquivos do revisor e foram alterados por outro agente nesta rodada, para preencher `validado_por` (regra nova de critério sem validador). As mudanças estão certas e foram mantidas.

### Regra de ouro: comparação com o commit c4d2b66

Dois bancos com os mesmos dados: `rev2_antes` com as migrations do c4d2b66 (tiradas por `git archive`, sem checkout) e `rev2_depois` com as atuais, ambos com a demo e com o volume do piloto (mesmo gerador, mesma semente). Um script lê, como diretor de cada tenant, todas as views de `app` e `marts` que existem nos dois bancos (33), só as colunas comuns, e as funções `dre_periodo`, `recebimento_periodo` e `desembolso_periodo` (ano até o mês, consolidado e por obra), `fluxo_caixa_cenario(3)` e `simular_fluxo` com `{}`, com atraso de 3 meses e com duas vendas e composição completa. Os UUIDs de centro de custo são trocados pelo `id_origem` antes de comparar.

| Data fixada | Tenant | Views iguais | Chamadas de função iguais |
| --- | --- | --- | --- |
| 26/09/2026 | demo | 33 de 33 | 22 de 22 |
| 26/09/2026 | volume | 33 de 33 | 64 de 64 |
| 15/12/2026 | demo | 33 de 33 | 22 de 22 (3 simulações com venda em novembro dão o mesmo erro 22023 nos dois) |
| 15/12/2026 | volume | 33 de 33 | 64 de 64 (10 com o mesmo erro nos dois) |
| 30/06/2025 | demo | 32 de 33 | 22 de 22 |
| 30/06/2025 | volume | 31 de 33 | 54 de 64 |

As diferenças de 30/06/2025 vêm todas de R2-M4: `mapa_unidades` (demo e volume), `posicao_financeira_obra` do volume (estoque a vender) e as dez simulações com venda do volume (ticket). Nenhuma diferença vem de parâmetro. Uma diferença prevista pelo contrato e não observada aqui porque os dois bancos carregam o volume com o validador preenchido: critério gravado pela carga sem `validado_por` passa a `nao_definido` com motivo `criterio_sem_validador` (caso coberto nos testes novos).

### Casos independentes da rodada 2

Data de referência 20/11/2026. Obra E: quatro unidades (40, 80, 80 e 100 m²; 100, 300, 200 e 500 mil), duas vendidas pelos contratos 7101 (100 mil) e 7102 (300 mil, FI de 240 mil em 15/01/2027, data do banco 01/10/2026). Custos: terreno 40 mil em março (pago), materiais 60 mil emitido em setembro e vencido em 05/10 sem pagamento, 20 mil numa conta sem mapeamento emitido em outubro. Orçamento: 40 mil de terreno e 160 mil de materiais. Obra F: contrato 7201 de 200 mil (entrada paga, PM de 40 mil vencida em 15/10, PM de 40 mil em 15/12, 40 mil com o código novo SF em 10/02/2027, FI de 60 mil sem data do banco), contrato 7202 de 150 mil com situação 9, unidade com situação Z, títulos de 10 mil sem emissão (vence 05/12) e de 300 mil emitido em 02/11 (vence 15/01/2027), orçamento de 250 mil.

- Padrão do produto: pendências SF (40 mil, entrada direta), 9 (150 mil, outro) e Z (180 mil, fora de venda); estoque da F com uma indisponível; VGV da F 200 mil; critério da carga sem validador vale `nao_definido`. Fluxo E: 60 mil em novembro, 40 mil em dezembro, 280 mil em janeiro. Fluxo F: 20 mil em novembro, -250 mil em janeiro, -150 mil em março (conservador -210 mil). Consolidado: -40 mil em março de 2026 (aporte 40 mil), -20 mil em maio, 80 mil em novembro, 30 mil em janeiro e 130 mil em março de 2027, carregando os 280 mil da E depois do último mês dela.
- Reconhecimento, obra E, novembro: cobertura 100/120 = 0,833333. Com mínimo 1 (padrão) e 0,9 (tenant) bloqueia; com 0,8 na obra libera: POC 100/200 mil = 0,5, receita 400 mil x 0,5 = 200 mil, custo 100 mil x 2/4 = 50 mil, DRE do ano com resultado gerencial de 150 mil. Sem terreno: POC 60/160 = 0,375, receita 150 mil, custo reconhecido continua 50 mil. Área privativa: 120/300 = 0,4, custo 40 mil. Valor de tabela: 400 mil / 1,1 milhão = 0,363636, custo 36.363,64. Obra com valor próprio e obra sem valor lendo o do tenant.
- DRE: pela emissão o título de 10 mil fica sem competência (linha própria de -10 mil); emissão ou vencimento põe em 05/12 e zera a linha; vencimento leva os 300 mil para janeiro de 2027 na despesa mensal.
- Caixa, obra F, novembro: vencido no mês de referência com fração 1 soma 40 mil (caixa 60 mil); fração 0,25 na obra, 10 mil (30 mil); obra com `excluir` vence o tenant (20 mil). Obra E com pagar vencido excluído: 120 mil em novembro e 340 mil em janeiro. Obra F com financiamento pendente excluído: -210 mil em março, igual ao conservador. Liberações de 100 mil prevista (janeiro), 50 mil pendente (fevereiro), 30 mil prevista atrasada e 20 mil pendente atrasada: padrão só janeiro; pendente incluída soma fevereiro; atrasada no mês de referência põe 50 mil em novembro (30 mil sem as pendentes). Custo sem título da E (80 mil) com premissa de 25% em outubro e 75% em dezembro: 20 mil em novembro e 60 mil em dezembro; com `ignorar`, só os 60 mil, e 20 mil ficam não distribuídos. A simulação vazia acompanha os parâmetros de caixa nas duas obras.
- Financiamento: com `repasse`, o 7102 fica `liberado` e os 240 mil saem de janeiro e entram em novembro (caixa de novembro 280 mil, já com a premissa). Retenção padrão de 10% no tenant dá 50 mil sobre 500 mil (`origem_retencao = padrao`); 20% na obra dá 100 mil e saldo liberável de 400 mil.
- Meta automática, obra F: falta vender 250 - 200 = 50 mil em cinco meses até as chaves (março), 10 mil e uma unidade por mês (ticket 250 mil); outubro, já passado, 50 mil / 6 = 8.333,33; maio 250 mil / 11 = 22.727,27. Estimativa até a conclusão usa os 310 mil lançados: 110 mil / 5 = 22 mil. Prazo próprio em janeiro: 16.666,67, 16.666,67 e 16.666,66. Prazo em setembro encerra outubro e novembro. Tenant automático com obra E manual; explicação de desvio de novembro na F com -1 unidade e -10 mil.
- Simulação, obra E, uma venda em dezembro: padrão do produto dá 350 mil (ticket das duas disponíveis), entrada de 35 mil, 24 parcelas de 4.375 e 210 mil do banco em abril. Com os padrões da obra (desconto 20% contra 10% do tenant, entrada 20%, parcelas 20% em 4 vezes, banco 2 meses depois): 280 mil, 56 mil em dezembro, 14 mil de janeiro a abril e 168 mil em fevereiro. Frações que não somam 1, na obra ou na resolução com o produto, são recusadas.
- Mapa de códigos: Z como reservada muda o estoque e o mapa de unidades na hora; 9 como ativo, SF como financiamento e FI como entrada direta só mudam na recarga: VGV da F vai a 350 mil, a F fica com 100 mil diretos e 40 mil de financiamento a vencer, a E com 240 mil diretos, e o FI do tenant R continua financiamento.
- Subcategoria (aço, em materiais) ligada à conta 2.01.001 e rótulo próprio de linha do DRE não mudam nenhuma linha do DRE nem o custo por categoria.
- Fuso: Kiritimati no tenant C e Pago Pago no tenant R. Sem data fixada, cada usuário recebe o dia do próprio fuso, inclusive trocando de usuário na mesma transação, e o dia do C fica sempre um ou dois à frente do R. Carga de 30 horas atrás fica atrasada com o limite padrão de 26 e em dia com 48.
- Segurança: seis tabelas novas com RLS ligado e forçado; uma política permissiva por tabela e ação, nenhuma `ALL`; nenhuma `using (true)` em `app`, `staging` e `marts`; toda escrita nas tabelas novas passa por `perfil_atual()` com diretor e financeiro; nenhuma política com `user_metadata`; catálogo e valores aceitos sem escrita para `authenticated`; toda função `security definer` com `search_path` vazio; `gerar_views_parametros`, `semear_mapa_codigo_origem`, `semear_tenant_novo` e os gatilhos sem execute para `authenticated` e `anon`; `fuso_horario_atual` só para logado; todas as views de `app` e `marts` com `security_invoker`. Gerente da obra E não vê o valor da F (nem em `parametros_obra`, nem em `configuracao_efetiva`), vê o consolidado só com a E e não grava; leitura não exclui nem cria; financeiro não grava em outro tenant nem em obra de outro tenant; outro tenant não vê nada; o histórico registra o financeiro como autor.
- Injeção: código fora do formato `^[a-z_]+\.[a-z_]+$` é recusado até para o dono do banco; um parâmetro novo com nome e padrão contendo `'); drop table app.tenant; --` gera a coluna pelo `format` com `%I` e `%L` e o texto volta como literal; valor jsonb com SQL vira só uma opção inexistente (23514).

### Tempos no volume do piloto

Mesmos dados e mesma data (26/09/2026) nos dois bancos, `scripts/medir_volume_piloto.sql` sem alteração, menor de duas execuções, em ms. Soma é a soma sequencial das consultas da tela mais as comuns; maior é a consulta mais lenta.

| Tela | Recorte | Diretor soma c4d2b66 | Diretor soma atual | Diretor maior atual | Gerente soma c4d2b66 | Gerente soma atual |
| --- | --- | --- | --- | --- | --- | --- |
| Visão geral | consolidado | 922 | 864 | 275 | 230 | 243 |
| DRE | consolidado | 573 | 674 | 222 | 172 | 191 |
| DRE | obra | 504 | 564 | 194 | 159 | 190 |
| Receitas | consolidado | 1.402 | 939 | 264 | 208 | 158 |
| Receitas | obra | 182 | 133 | 33 | 191 | 136 |
| Despesas | consolidado | 172 | 132 | 73 | 46 | 43 |
| Despesas | obra | 60 | 54 | 23 | 59 | 54 |
| Fluxo | consolidado | 255 | 260 | 258 | 69 | 77 |
| Fluxo | obra | 156 | 177 | 70 | 166 | 182 |
| Simular | obra | 173 | 195 | 79 | 169 | 199 |
| Planejamento | consolidado | 21 | 20 | 17 | 13 | 13 |
| Planejamento | obra | 357 | 404 | 242 | 179 | 229 |
| Financiamento | obra | 20 | 17 | 14 | 14 | 16 |
| Obra (tela antiga) | obra | 169 | 176 | 118 | 105 | 110 |
| Mapa de unidades | obra | 46 | 54 | 39 | 45 | 47 |
| Assistente (5 consultas) | consolidado | 996 | 1.070 | 262 | 269 | 334 |

A receita consolidada ficou mais rápida (a carteira paginada caiu de 430 para 263 ms com a data de referência materializada). O maior aumento é no DRE, de 20 a 32 ms por consulta, pela junção com `app.parametros_tenant` em `apropriacao_classificada`. Consultas novas, diretor: página `/configuracoes` com 10 consultas somando 31 ms (a maior é `pendencia_codigo_origem`, 26 ms) e 7 ms no escopo de obra; `fluxo_projetado_consolidado` 247 ms (a tela `/fluxo` com o consolidado ligado soma 501 ms); `meta_automatica_mensal` 30 ms por obra e 63 ms consolidada; `criterio_reconhecimento_efetivo` 5 ms; `estoque_atual` 3 ms. Nada perto de 2 s.

### Verificado e passou

- pgTAP, arquivo por arquivo, em banco limpo, com a demo e com demo e volume: configuracao 88, dre_gerencial 99, eventos_financeiros 67, financiamento_medicoes 69, isolamento_configuracao 44, isolamento_dre 53, isolamento_eventos 27, isolamento_perfis 12, isolamento_planejamento 51, planejamento_projecoes 86, regras_configuraveis 101, revisao_independente 217. Total 914 ok e 0 falha em cada banco.
- Painel: `npx next typegen` ok, `npx tsc --noEmit` sem erro, `npm run lint` sem aviso, `npx vitest run` com 273 testes em 10 arquivos.
- Server Actions de `/configuracoes` (`acoes.ts` e `gravacao.ts`): cada uma passa por `executarConfiguracao`, que chama `getUser()`, lê tenant e perfil por `app.tenant_atual()` e `app.perfil_atual()`, recusa quem não é diretor ou financeiro, valida a entrada pelo catálogo no servidor e grava com o cliente do usuário; erro do banco vira frase, sem SQL nem nome de tabela. A página chama `exigirIdentidade()`.
- Nenhum `console.log`, `service_role`, `NEXT_PUBLIC_`, `getSession`, travessão, TODO ou nome do ERP nos arquivos novos e nas linhas alteradas.

### Não verificado

- Tempos no Supabase remoto, com PostgREST e rede.
- As telas no navegador; a leitura foi por código, tipos e testes.
- O comportamento de R2-I1 atrás do Supavisor em modo transação com clientes que não enviam claims.

### Situação dos achados da rodada 2 depois das correções

| Achado | Situação |
| --- | --- |
| R2-I1 | Corrigido na 0007: `app.data_referencia()` trata o cache vazio do fuso como ausente. Teste em `configuracao.sql` simula o início de uma nova transação; duas transações seguidas no `psql` conferidas à mão |
| R2-M1 | Corrigido na 0013: a simulação refaz o vencido recuperado sem os contratos cancelados. Teste em `revisao_independente.sql` |
| R2-M2 | Mantido como limitação: subcategoria existe e é validada, mas nenhuma tela abre por ela ainda |
| R2-M3 | Mantido: carga sem JWT pode informar o validador; a tela sempre grava o usuário logado |
| R2-M4 | Documentado em `configuracao.md`, seção 6 |

Depois das correções: 915 testes pgTAP passando em banco limpo e com a demo e o volume do piloto; 273 testes vitest; tsc, lint e build limpos.
