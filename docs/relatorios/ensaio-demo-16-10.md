# Ensaio da demo de 16/10/2026

Este relatório separa o que foi medido no Supabase local deste worktree, em 06/10/2026, do que ainda falta medir no projeto hospedado (`xwqwjawlbzvqpkxtqfld`) e em https://obra-analitica.vercel.app. Nada aqui foi rodado contra o hospedado. As medições do hospedado ficam com o João, depois do `supabase db push` da 0035 e da Carga noturna.

## Ambiente local da medição

MacBook do João, Docker com o Supabase local do worktree `project-scope-31c6ef` (porta 54322), migrations 0001 a 0035 e o seed, carga da demo pelo bloco C do plano. Banco local e Postgres sem rede no caminho, então os tempos daqui são o piso do que o hospedado vai mostrar.

## Medições

| Medição | Alvo | Local, 06/10 | Hospedado | Situação |
| --- | --- | --- | --- | --- |
| `marts.dre_viabilidade` filtrada por obra, `explain analyze`, como diretor com RLS | menos de 300 ms | 27 a 29 ms de execução e 2,5 a 4,4 ms de planejamento, em três rodadas | falta | local dentro do alvo |
| A mesma consulta como dono do banco, sem RLS | só referência | 3,9 ms | não se aplica | |
| Carga completa da demo, banco vazio depois do reset (geradores e `carregar_demo.py`) | menos de 5 min | cerca de 1 s | falta (tempo do job da Carga noturna no GitHub Actions) | local dentro do alvo |
| Carga completa da demo, segunda rodada sobre a mesma base | menos de 5 min | 0,71 s (geradores 0,13 s e carga 0,58 s) | falta | local dentro do alvo |
| Visão geral (`/`) no navegador | menos de 2 s | não medido | falta | |
| `/dre` no navegador | menos de 2 s | não medido | falta | |
| DRE da obra (`/obras/<id>/dre`) no navegador | menos de 2 s | não medido | falta | |
| Gestão de imposto (`/obras/<id>/imposto`) no navegador | menos de 2 s | não medido | falta | |
| Pergunta ao assistente sobre tendência | menos de 8 s | não medido | falta | |

A consulta medida foi `select * from marts.dre_viabilidade where centro_custo_id = '<Parque das Águas>'`, dentro de uma transação com `role authenticated` e claims de diretor com `aal2`. Devolve as 17 linhas da obra. O tempo inclui tudo o que a view faz por baixo, inclusive o saldo contábil da 0035.

## Como medir no hospedado

As telas: abrir cada endereço no Chrome logado como sócio (perfil leitura), com o DevTools na aba Network e o cache desligado, recarregar três vezes e anotar o maior tempo do documento principal (coluna Time da primeira linha). Anotar na coluna Hospedado acima, com a data.

O `explain analyze` no hospedado: no SQL Editor do Supabase, a mesma consulta, trocando o id pelo da Parque das Águas no projeto. O SQL Editor roda como dono, então o número sai sem o custo do RLS; para o valor com RLS, use a mesma transação do teste local:

```sql
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"<id de um diretor em auth.users>","role":"authenticated","aal":"aal2","app_metadata":{"tenant_id":"11111111-1111-1111-1111-111111111111","perfil":"diretor"}}';
explain analyze select * from marts.dre_viabilidade where centro_custo_id = '<id da Parque das Águas>';
rollback;
```

A carga: em Actions, Carga noturna, o tempo do passo "Carga" no job disparado por `workflow_dispatch`.

O assistente: em `/assistente`, a pergunta pronta "Qual a tendência do lucro de cada obra contra o estudo?", cronometrada do clique até a tabela aparecer. Repetir com uma pergunta livre só se a `ASSISTENTE_CHAVE_ASSINATURA` estiver confirmada nas duas pontas.

## Testes que rodaram no ensaio local

Bloco A: `supabase db reset` aplicou 0001 a 0035 e o seed; `supabase test db` deu 25 arquivos e 541 testes, todos passando.

Bloco B: lint sem erro, `next typegen` e `tsc --noEmit` sem erro, Vitest com 25 arquivos e 461 testes passando, `npm run build` concluído.

Bloco C: carga da demo duas vezes sem duplicar (9.349 registros em `raw`, 504 em `staging.saldo_contabil_mensal`, 396 em `app.posicao_dre_mensal`, 51 linhas em `marts.dre_viabilidade`). Nenhuma linha da DRE fora do estoque ficou com `fonte_realizado = 'sem_fonte'`. O arquivo de inadimplência foi restaurado com `git checkout` depois de cada carga.

Bloco E: 156 testes Python de `scripts/testes`, todos passando com o banco local.

Playwright: os 7 casos de `painel/testes/e2e/login.spec.ts` passaram contra o build local e o Supabase local, com usuários de teste criados na hora como faz o CI, entre eles o caso novo da DRE (diretor vê as três obras, gerente vê o aviso de tela restrita).

## Defeitos achados

Nenhum defeito de tela ou de número no ensaio local.

Os testes Python deixam 5 linhas em `staging.parcela_receber` de três tenants de teste depois de rodar (4.142 linhas no total contra 4.137 do tenant da demo). A carga da demo não apaga nem lê essas linhas e as telas filtram por tenant, mas o banco local fica sujo para quem conta linhas sem filtrar. Não foi corrigido nesta etapa.

## O que ficou de fora

O roteiro ainda não foi seguido do começo ao fim no hospedado, que é parte do critério de pronto da etapa. A resposta 200 de `/api/saude` no hospedado também falta conferir. A etapa 12 (Onde agir agora) espera a pergunta P13 ao Braga e não entra na demo.
