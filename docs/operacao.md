# Operação do painel e da carga

Guia para quando algo quebra ou parece estranho. Cada sinal tem um lugar só: log na Vercel e no GitHub Actions, erro e desempenho no Sentry, disponibilidade no UptimeRobot, histórico da carga em `app.carga_execucao`.

## Como achar uma requisição: `id_requisicao`

O proxy do painel sorteia um UUID por requisição e devolve no cabeçalho `x-id-requisicao`. O mesmo valor vai para o log JSON (campo `id_requisicao`) e para o Sentry (etiqueta `id_requisicao`). Quando um usuário relatar um erro, peça a hora aproximada e a tela; com o id em mãos, os três lugares mostram a mesma requisição.

## Logs na Vercel

1. Projeto na Vercel, aba Logs.
2. Filtre pelo período e cole o `id_requisicao` na busca. Cada linha é um JSON com `nivel`, `rota`, `resultado`, `duracao_ms`, `user_id` e `tenant_id`.
3. O log nunca tem e-mail, token nem SQL. Para saber quem é o usuário, procure o `user_id` em Authentication, Users, no Dashboard do Supabase.

A Vercel guarda log por 1 hora no plano Hobby e 1 dia no Pro. O que precisa durar mais fica no banco.

## Erros no Sentry

1. Issues, busca `id_requisicao:<uuid>`.
2. O campo `release` é o SHA do commit; compare com o `commit` que `/api/saude` devolve para saber se o erro é da versão no ar.
3. O `beforeSend` apaga e-mail, nome, IP e cookie do usuário. Se aparecer dado pessoal num evento, trate como incidente: apague o evento e corrija o filtro em `painel/lib/filtro-sentry.ts`.

Sem `SENTRY_DSN` e `NEXT_PUBLIC_SENTRY_DSN` o SDK fica desligado, que é o normal em desenvolvimento e no CI.

## Rota de saúde

`GET /api/saude` responde `{ ok, idade_horas }`, sem login; com o segredo `MONITOR_TOKEN` no cabeçalho `x-monitor-token` acrescenta `commit`, `ultima_carga_em` e `situacao_carga`. A data vem de `public.ultima_carga()`, a única função que o anônimo chama fora do webhook. Responde 503 quando o banco não responde ou quando algum tenant ativo está há mais de 26 horas sem carga concluída. O UptimeRobot chama a cada 5 minutos e manda e-mail na falha.

Com 503, olhe `idade_horas`: nulo com `ultima_carga_em` nulo quer dizer banco fora do ar ou nenhuma carga concluída; número acima de 26 quer dizer que a carga noturna não rodou ou falhou.

## Carga noturna

O job `.github/workflows/carga_noturna.yml` roda às 02:17 de Brasília. Cada endpoint e a recarga do staging gravam uma linha em `app.carga_execucao` com início, fim, registros lidos, registros novos, situação e duração. A data "Dados carregados em" das telas sai só da etapa `staging` concluída com `ok`.

Para ver as últimas execuções, no SQL Editor do Supabase:

```sql
select endpoint, situacao, iniciado_em, terminado_em, registros_lidos, registros_novos, erro_resumo, duracao_ms
from app.carga_execucao
order by id desc
limit 20;
```

### Quando a carga falha

1. O GitHub manda e-mail de falha para quem editou por último a linha do `cron` no workflow. Confira em Settings, Notifications, Actions, que o e-mail está ligado.
2. Abra a execução em Actions, Carga noturna, e leia o passo "Carga". O script para no primeiro endpoint com erro e não recarrega o staging, então as telas continuam mostrando a carga anterior, com a data dela.
3. Em `app.carga_execucao`, a linha com `situacao = 'falha'` diz o endpoint e o `erro_resumo` (classe do erro e código SQLSTATE, sem valores de registro).
4. Linha parada em `executando` há mais de 30 minutos quer dizer que o job foi interrompido no meio (tempo limite ou cancelamento). Não precisa limpar: a próxima execução abre linhas novas.
5. Corrigida a causa, rode de novo à mão. A carga pode rodar quantas vezes precisar no mesmo dia sem duplicar nada.

Causas prováveis: senha do banco trocada sem atualizar o secret `DATABASE_URL`; `DATABASE_URL` apontando para a conexão direta, que só tem IPv6, em vez do Session pooler; projeto do Supabase pausado por inatividade no plano Free.

### Rodar a carga à mão

Actions, Carga noturna, Run workflow, branch `main`. Pela linha de comando:

```bash
gh workflow run carga_noturna.yml --ref main
gh run watch
```

### Agendamento que para sozinho

A documentação do GitHub diz que, em repositório público, o agendamento é desativado depois de 60 dias sem atividade no repositório. Para repositório privado a documentação não cita a regra. Por isso, uma vez por mês, confira em Actions que a Carga noturna rodou nos últimos dias; se o workflow aparecer desativado, reative no botão "Enable workflow". A rota de saúde também acusa: com a carga parada, ela vira 503 depois de 26 horas.

## Secrets e variáveis

| Onde | Nome | Para quê |
| --- | --- | --- |
| GitHub, secrets do repositório | `DATABASE_URL` | Session pooler do projeto da demo, com a senha codificada |
| GitHub, secrets do repositório | `TENANT_DEMO_ID` | Tenant que a carga grava |
| Vercel | `SENTRY_DSN` | Sentry no servidor |
| Vercel | `NEXT_PUBLIC_SENTRY_DSN` | Sentry no navegador; o DSN só permite enviar eventos |

Quando existir o banco do piloto, ele ganha secrets próprios, num environment do GitHub separado. O secret da demo nunca aponta para o piloto.

O CI (`.github/workflows/ci.yml`) não usa secret nenhum: sobe um Supabase local, cria dois usuários de teste com senha sorteada e apaga tudo no fim.
