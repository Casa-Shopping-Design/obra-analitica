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
