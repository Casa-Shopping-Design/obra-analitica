# PT-07, execução da noite de 23/09/2026

Branch `claude/pt-07`, a partir da `main` em `5b6db2e`. Nada foi aplicado em banco remoto e nenhuma credencial foi usada.

## O que foi feito

- `painel/lib/validador-sql.ts` reescrito sobre `pgsql-parser` 17.9.17 (parser do Postgres 17 em wasm). Aceita uma única instrução `select`, com CTE não recursiva, sobre as views do catálogo e `app.centro_custo`. Tudo funciona por lista de permissão: tipos de nó, funções, tipos de conversão, operadores e tabelas. Nome sem schema só vale se for CTE visível naquele ponto da consulta. Põe `limit 500` quando falta, recusa limite maior, negativo ou calculado, e devolve o SQL reescrito pela biblioteca depois de conferir que ele volta à mesma árvore.
- `painel/lib/assistente/executar.ts`: `executarConsultaValidada` valida, assina o SQL com HMAC-SHA256, chama `marts.executar_consulta` com o cliente do usuário, mede a duração e grava a auditoria. Recusa e erro viram mensagem sem SQL nem tabela. O log leva `id_requisicao` e o código do erro. Se a auditoria não grava, as linhas não saem.
- `painel/lib/assistente/limite.ts`: `verificarLimite` conta as perguntas do usuário na última hora (30 por hora) e bloqueia quando o banco não responde.
- `supabase/migrations/0009_assistente.sql`: `statement_timeout` de 8 s no papel `authenticated`; tabela `app.pergunta_assistente` com RLS ligado e forçado, uma política de insert e uma de select, sem update nem delete; `app.assinatura_consulta_valida` (security definer, `search_path` vazio, lê a chave no Vault); `marts.executar_consulta` (security invoker, exige usuário, tenant e assinatura, transação somente leitura, teto de 500 linhas).
- Testes: `painel/testes/validador-sql.test.ts` (91 casos), `executar.test.ts` (7) e `limite.test.ts` (5) com o cliente do banco simulado; `supabase/tests/assistente.sql` (28 asserções pgTAP).
- `docs/decisoes/0004-validador-parser.md` e a dependência travada em `painel/package.json` e `painel/package-lock.json`.

## O que foi verificado e como

- Em `painel/`: `npm ci`, `npm run lint`, `npm test` (110 testes), `npm run build` com URL e chave fictícias só na variável do comando, `npx tsc --noEmit` e `npm audit --audit-level=high` (0 vulnerabilidades), todos sem erro. O `tsc` antes do primeiro build acusa `LayoutProps` em dois layouts do PT-01, porque o tipo é gerado pelo build; depois do build passa. Não é deste pacote.
- Banco: num contêiner Docker descartável da imagem `supabase/postgres:17.6.1.166`, sem porta exposta, apliquei 0001 a 0006 e a 0009 e rodei `supabase/tests/assistente.sql` (28 de 28) e `isolamento_perfis.sql` (12 de 12). A imagem não traz `auth.jwt()` nem a versão atual de `auth.uid()`, que o Auth cria no projeto; criei as duas só no contêiner. O contêiner foi removido.
- Ponta a ponta no mesmo contêiner: os 10 exemplos do catálogo e uma consulta com janela, `filter` e intervalo passaram pelo validador, foram assinados e executados por `marts.executar_consulta` como diretor, sem erro. O HMAC do Node e o do `pgcrypto` deram o mesmo valor, com acento no texto.
- No contêiner, uma consulta só com `set_config` trocando os claims leu 777 reais de parcela de outro tenant. É o motivo da assinatura, explicado no ADR.
- Tentativa de quebrar o validador com consultas novas: duas passavam e viraram correção e teste (função chamada como coluna, `v.row_to_json`; e `limit -1`). As outras dez da lista de autorrevisão foram recusadas na primeira tentativa e estão no teste.
- Build de produção com uma rota temporária que importava o validador: sem `serverExternalPackages: ["libpg-query"]` o parse falha porque o Turbopack empacota o wasm; com a opção, a rota respondeu certo em `next start` e o `.nft.json` incluiu o `.wasm`. A rota e a mudança no `next.config.ts` foram desfeitas.
- Conferência contra o `CLAUDE.md`: nomes em português sem acento; nenhum nome do ERP; RLS `enable` e `force` na mesma migration; uma política por ação, nenhuma `using (true)`; a única função `security definer` tem `search_path` vazio e está revogada de `public` e `anon`; `service_role` não aparece; a chave de assinatura não tem prefixo `NEXT_PUBLIC_`; auditoria sem token e com `user_id`, não e-mail; nenhuma expressão regular decide o que o validador aceita.

## O que falta com banco real (aceites ficam com João)

1. Gerar a chave e guardar nos dois lados, com o mesmo valor: `select vault.create_secret('<openssl rand -hex 32>', 'assistente_chave_assinatura');` no SQL Editor de cada projeto e `ASSISTENTE_CHAVE_ASSINATURA` na Vercel (produção e preview, cada uma com a chave do seu banco) e no `.env.local`. Sem ela, toda pergunta falha com a mensagem genérica.
2. `supabase db push` da 0009. A 0007 e a 0008 ainda não existem; se a CLI reclamar da ordem, usar `--include-all` ou esperar os PT-05 e PT-06.
3. `supabase test db` com `assistente.sql` e `isolamento_perfis.sql`.
4. Adicionar `serverExternalPackages: ["libpg-query"]` ao `next.config.ts` quando o PT-10 criar a rota. O arquivo é do PT-01 e não mexi nele.
5. Aceite do plano: rodar uma pergunta pronta do PT-03 por este caminho e comparar com o resultado anterior.
6. Incluir `ASSISTENTE_CHAVE_ASSINATURA` no `.env.example` (arquivo fora deste pacote).

## Desvios do plano

- Parser: `pgsql-parser` (libpg-query) no lugar de `pgsql-ast-parser`, pelo motivo do ADR.
- Assinatura HMAC e o parâmetro `p_assinatura` em `marts.executar_consulta`, mais a função `app.assinatura_consulta_valida`. O plano previa só `p_sql`, o que deixava a função aberta a SQL livre pela API.
- Funções por lista de permissão, não por proibição de `pg_`, `auth` e `app`. CTE recursiva e `limit` negativo são recusados. `offset` só constante.
- Política de select da auditoria também exige o tenant do usuário (o plano deixava o diretor ver qualquer tenant).
- `user_id`, `tenant_id` e `criado_em` vêm de valor padrão e ficam fora do grant de insert. Não há FK de `user_id` para `auth.users`, para a auditoria sobreviver à exclusão do usuário. Coluna `situacao` (executada, recusada, falhou) acrescentada.
- Assinaturas: `verificarLimite(cliente, usuarioId)` e `executarConsultaValidada({ cliente, idRequisicao, pergunta, sql, registrar })`. O cliente e o registrador entram como parâmetro para teste e porque `lib/log.ts` é do PT-08. A função valida por conta própria, então não existe caminho que assine SQL sem validar.
- As mensagens ao usuário ficaram em `mensagensExecucao`, dentro de `executar.ts`, porque `lib/mensagens.ts` não é deste pacote. Vale mover na integração.
- Testes de `executar.ts` e `limite.ts` em `painel/testes/executar.test.ts` e `limite.test.ts`, arquivos que o plano não listava.

## Dúvidas e limites conhecidos

- Tokens e custo da segunda chamada ao modelo (PT-10) só são conhecidos depois da execução, e a auditoria não tem update. O PT-10 precisa escolher entre gravar tudo no fim, uma tabela de consumo à parte ou um grant de update só nessas colunas.
- O limite por hora conta e depois grava; duas requisições simultâneas podem passar juntas na borda. Serve para conter custo.
- O usuário consegue inserir linhas de auditoria em nome próprio direto pela API. Não consegue forjar outro usuário, data, tenant, nem apagar ou alterar.
- Junção cartesiana entre views do catálogo passa no validador; quem para é o `statement_timeout` de 8 s.
- `alter role authenticated set statement_timeout` vale para todo o painel, não só para o assistente, como o plano pede.
- A lista de funções é enxuta (agregações, arredondamento, datas, `to_char`, janelas). Se o PT-10 precisar de outra, entra com teste.

## Eficiência (PAA)

- Validador: O(t) no tamanho do texto, com um parse, duas caminhadas na árvore, uma reescrita e um parse de conferência. Texto limitado a 10.000 caracteres e aninhamento a 200 níveis. Sem laço aninhado sobre dados.
- `verificarLimite`: uma contagem `head` que usa o índice `(user_id, criado_em desc)`; no máximo 30 linhas por usuário na janela.
- Execução: uma chamada ao banco e um insert por pergunta; nada de N+1. Agregação fica no Postgres; o resultado tem teto de 500 linhas no validador e na função.
- Índices: `(user_id, criado_em desc)` para o limite e `(tenant_id, criado_em desc)` para a política de select e a leitura do diretor.
- Sem chamada externa neste pacote.
