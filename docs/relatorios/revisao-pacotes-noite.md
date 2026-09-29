# Revisão dos pacotes da noite de 27/09/2026

Cinco pacotes foram implementados em paralelo, cada um num worktree próprio, e passaram por um revisor independente que refez os testes do zero. Cada pacote está numa branch; nada foi para a `main` e nenhum pull request foi aberto. Os testes de banco rodaram em Postgres 16 local com pgTAP, não na imagem do Supabase, e o PT-10 só com o cliente da Anthropic simulado. Por isso cada branch pede `supabase test db` no Mac antes do `db push`.

Preparação, uma vez:

```bash
cd ~/documents/painel-sienge-demo
git fetch origin
git remote set-url origin https://github.com/Casa-Shopping-Design/obra-analitica.git
```

Para cada branch, ler o diff contra a base indicada, conferir os pontos da lista, rodar os testes e só então integrar na `main`. Linhas citadas são do arquivo na branch.

```bash
git diff BASE...origin/BRANCH --stat
git diff BASE...origin/BRANCH -- ARQUIVO
```

Ordem de integração: VGV, PT-05, PT-06, PT-07, PT-10, PT-08. PT-06 e PT-10 foram empilhados sobre a branch do pacote de que dependem; o PT-08 fica por último porque mexe no mesmo `package-lock.json` que PT-07 e PT-10.

## 1. `claude/dreamy-clarke-am2xge`: VGV

Base `origin/main`. 15 arquivos, commits `8b7e2e1` e `afdcb88`. Migration 0011 já aplicada no remoto.

- [ ] `supabase/migrations/0011_vgv.sql`: colunas novas no fim da view; fora de venda não entra no VGV.
- [ ] `painel/componentes/MapaUnidades.tsx`: grade à esquerda e totais à direita em tela larga.
- [ ] `docs/plano_implementacao.md`, seção 5.1: migrations reservadas renumeradas para 0012 a 0015.
- [ ] `supabase test db`: vgv.sql 4/4.
- [ ] Integrada na `main`.

## 2. `pt-05-eventos`: eventos financeiros

Base `origin/claude/dreamy-clarke-am2xge`. 5 arquivos, commit `33f2646`. A revisão não achou defeito.

- [ ] `0012_eventos_financeiros.sql` L32 a 40: `rateio_titulo` tem `fracao`, fora do plano, com check entre 0 e 1. Rateio negativo vindo do ERP pararia a carga do tenant; olhar de novo no PT-09.
- [ ] L59 a 80: política nova de `titulo_pagar` e `pagamento`. O gerente vê o valor total de um título dividido com outra obra; só a fração dele entra nos números. **Decisão 1, aceita.**
- [ ] L86 a 215: `staging.recarregar` mantém `search_path = ''` e o `revoke` da L215.
- [ ] L238 e L243: saída realizada e prevista multiplicadas pela fração.
- [ ] `scripts/gerar_dados_demo.py`: recebimento em duas vezes (40/60), rateio 60/40, `random.seed(2026)` mantido.
- [ ] `docs/decisoes/0002-eventos-financeiros.md` lido.
- [ ] `supabase test db`: fluxo_caixa 19, isolamento 12, vgv 4.
- [ ] Integrada na `main`, `supabase db push`, depois `gerar_dados_demo.py` e `carregar_demo.py`. Os números por obra mudam um pouco, porque 5% dos títulos passam a ser rateados.

Revisão de 27/09: pode integrar. Segurança, regra de negócio e eficiência conferidas contra a migration, o ADR e os 19 testes; a soma de `saida_realizada` de todas as obras bate com o pago antes da mudança. Decisão 1 aceita por João. Para o PT-09: com carga incremental, duas versões do mesmo título em `raw` dariam fração acima de 1 e parariam a carga (a 0002 já tinha o mesmo risco na chave de `titulo_pagar`); e o filtro `valor_recebido > 0` saiu, então estorno negativo vindo do ERP reduz a entrada do mês.

## 3. `pt-06-vso`: VSO com calendário

Base `origin/pt-05-eventos`. 4 arquivos, commits `97bbf96`, `bae4f9f` e `8929305`. A revisão incluiu índices por obra e tirou da contagem o contrato em situação desconhecida.

- [ ] `0015_vso.sql` L64: `vso_pct = vendas_liquidas / estoque_inicio_mes`. O plano pedia `/ (estoque + vendas)`, que conta duas vezes a unidade vendida no mês. **Decisão 2**, justificativa no ADR 0003.
- [ ] L18: só contratos em situação `'1'` ou `'3'`. Confirmar que esses são os códigos de ativo e distratado na origem.
- [ ] L6 e L7: índices novos em `staging`.
- [ ] L104: `meses_para_cobrir`; Parque das Aguas dá 228 meses com os dados da demo.
- [ ] `painel/lib/catalogo-views.ts`: descrição de `vso_mensal` mostra o denominador.
- [ ] `supabase test db`: vso 24.
- [ ] Integrada na `main` depois do PT-05, `supabase db push`.

Revisão de 27/09: pode integrar depois do PT-05. Recomendação para a decisão 2: aceitar. Vendas sobre estoque inicial é a definição de mercado e equivale a vendas sobre vendas mais estoque final; a fórmula do plano soma duas vezes a unidade vendida no mês. Pontos de atenção, sem bloqueio: `vgv_vendido` em `vso_mensal` passou a incluir contratos distratados depois, enquanto em `posicao_financeira_obra` a mesma coluna é só contrato ativo, o que pode confundir o assistente (renomear numa migration futura com `alter view ... rename column`); obra com menos de seis meses de contrato tem `vendas_media_6m` sobre os meses que existem, não sobre seis; unidade hoje fora de venda sai da oferta de todos os meses, porque o staging não guarda histórico de situação.

## 4. `pt-07-validador`: validador, execução e auditoria

Base `origin/claude/dreamy-clarke-am2xge`. 9 arquivos, commits `18260ab`, `332f0db` e `52b7116`. A revisão passou a ler o tenant do JWT validado e garantiu o pgcrypto na migration. Pacote de maior risco de segurança.

- [ ] `0013_assistente.sql` L5: `statement_timeout` de 8 s no papel `authenticated` vale para todas as telas, não só o assistente. **Decisão 3.**
- [ ] L11 a 35: tabela da chave sem grant; `assinatura_consulta_valida` exposta a quem está logado, devolve só verdadeiro ou falso.
- [ ] L39 a 63: `executar_consulta` com `security invoker`, exigência de usuário, assinatura, `transaction_read_only` e cursor, que impede segundo comando no texto. Recebe `p_assinatura`, fora do plano. **Decisão 3**, ADR 0004.
- [ ] L66 a 101: `pergunta_assistente` com uma política por ação. A L94 deixa o não diretor ler o próprio `sql_executado` pela API. **Decisão 4.**
- [ ] `painel/lib/validador-sql.ts`: L114 lista de funções, L135 a 146 tabela fora do catálogo recusada e CTE como nome local, L194 a 208 teto de 500 linhas, L230 entrada pública.
- [ ] `painel/lib/assistente/limite.ts` L11 a 22: conta e depois grava; perguntas simultâneas passam do limite. **Decisão 4.**
- [ ] `painel/testes/validador-sql.test.ts`: os dez casos do plano presentes.
- [ ] `painel/package.json`: `pgsql-ast-parser` 12.0.2 exata.
- [ ] `npm ci && npx vitest run`: 126. `supabase test db`: assistente 25.
- [ ] Chave gerada com `openssl rand -hex 32`, gravada em `app.chave_assinatura_consulta` pelo SQL Editor e em `ASSISTENTE_CHAVE_ASSINATURA` na Vercel, sem `NEXT_PUBLIC_`.
- [ ] Integrada na `main`, `supabase db push`.

## 5. `pt-10-assistente`: assistente com texto livre

Base `origin/pt-07-validador`. 15 arquivos, commits `3f3c88d`, `b9fe1e7`, `a405241` e `f7fa866`. A revisão barrou usuário sem tenant e rota sem chave antes de chamar o modelo, e corrigiu id duplicado na tela.

- [ ] `painel/app/api/assistente/route.ts`: L75 `getUser` (401), L81 a 95 tenant (403), L105 limite (429), L116 chave antes do modelo (503), L128 geração com uma segunda tentativa, L148 execução. Nenhum erro devolve SQL.
- [ ] `painel/lib/assistente/prompt.ts`: L6 modelo `claude-sonnet-5`; L60 e L73 pergunta e linhas tratadas como dado; L77 tira `<` e `>`.
- [ ] `painel/lib/assistente/responder.ts` L80 a 99: número só por referência `{{linha.coluna}}`; algarismo solto descarta o texto. Conferir com um exemplo.
- [ ] Arquivos de outros pacotes alterados: `executar.ts`, `RespostaPergunta.tsx`, `mensagens.ts`.
- [ ] `painel/package.json`: `@anthropic-ai/sdk` 0.128.0.
- [ ] `npx vitest run`: 143.
- [ ] Integrada na `main` depois do PT-07.
- [ ] Com `ANTHROPIC_API_KEY` na Vercel: as 16 perguntas prontas em texto livre, números iguais aos da consulta direta, custo médio abaixo de US$ 0,03 em `pergunta_assistente`.

## 6. `pt-08-observabilidade`: observabilidade, CI e carga agendada

Base `origin/claude/dreamy-clarke-am2xge`. 23 arquivos, commits `4153fca` e `07c5130`. A revisão tirou da 0014 um `alter default privileges` que não revogava nada e deixaria toda função nova em `app` aberta ao anônimo.

- [ ] `0014_carga_execucao.sql` L41 a 60: `grant usage on schema app to anon` para a rota de saúde responder sem login. A alternativa é a rota ler pelo servidor e o anônimo continuar fora do schema. **Decisão 5**, antes do `db push`.
- [ ] `painel/app/api/saude/route.ts` L9 a 37: devolve só `ok`, commit e datas.
- [ ] `scripts/carregar_demo.py`, `registrar_falha`: grava só a classe do erro e o SQLSTATE, sem a mensagem do banco.
- [ ] `painel/componentes/CarimboCarga.tsx`: aviso "Dados da demo" removido. **Decisão 6.** Textos de alerta fixos no componente, contra a regra do `mensagens.ts`.
- [ ] `painel/lib/filtro-sentry.ts`: apaga e-mail, IP, cookies e cabeçalhos sensíveis.
- [ ] `.github/workflows/carga_noturna.yml`: 05:17 UTC, com secrets; regera a demo toda noite.
- [ ] `.github/workflows/ci.yml` L77: chave `service_role` do Supabase local, padrão e pública.
- [ ] `painel/package-lock.json`: as 1.826 linhas são campo `libc` e marcação `dev` reescritos pelo npm; nenhuma versão mudou e nenhum pacote saiu.
- [ ] `npx vitest run`: 64. `supabase test db`: carga_execucao 11.
- [ ] Integrada na `main` por último, conflito do lockfile resolvido com `npm install`, `supabase db push`.
- [ ] Sentry com DSN na Vercel e domínio de ingest na CSP; secrets `DATABASE_URL` e `TENANT_DEMO_ID` no GitHub; carga rodada uma vez por `workflow_dispatch`; monitor no UptimeRobot.

## Decisões pendentes

| # | Branch | Decisão | Escolha |
| --- | --- | --- | --- |
| 1 | pt-05 | Gerente vê o valor total de um título rateado com outra obra | Aceita em 27/09 |
| 2 | pt-06 | Denominador da VSO diferente do plano | Recomendado aceitar; aguarda João |
| 3 | pt-07 | `executar_consulta` com assinatura; `statement_timeout` de 8 s para todas as telas | Aceita em 28/09: teto no papel fica, função repete o limite e confere os claims (ADR 0008) |
| 4 | pt-07 | Corrida no limite de 30 por hora e leitura do próprio SQL pela API no MVP | Aceita em 28/09: reserva atômica no banco e SQL só para o diretor (ADR 0008) |
| 5 | pt-08 | Anônimo no schema `app` ou rota de saúde pelo servidor | Aceita em 28/09: função `public.ultima_carga()` para `anon`, sem `usage` novo em `app` (ADR 0008) |
| 6 | pt-08 | Aviso "Dados da demo" volta ou não | Aceita em 28/09: volta, ligado por `NEXT_PUBLIC_MOSTRAR_AVISO_DEMO=1` (ADR 0008) |

Na integração de 28/09 as migrations 0013 e 0014 das branches viraram 0020 e 0021; as referências acima a `0013_assistente.sql` e `0014_carga_execucao.sql` são dos arquivos como estavam nas branches.

## Ficou para depois

Textos novos em `painel/lib/mensagens.ts` e variáveis no `.env.example` (Sentry e E2E). `registrar()` do log nas rotas que já existem e no `proxy.ts`. Retirar `marts.consolidado_centro_custo`, que ignora títulos rateados. `requirements.txt` para os scripts Python. `test-results/` e `playwright-report/` no `painel/.gitignore`. Alerta de custo do assistente no job de carga, que depende do PT-07 na `main`.
