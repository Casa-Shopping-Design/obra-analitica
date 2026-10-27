# Revisão de segurança e confiabilidade de 27/10/2026

Revisão feita sobre a `main` em d03a009 (PR 11). Três agentes leram o código em paralelo: um cuidou de RLS, autenticação e assistente; outro, de carga, staging e funcionalidades; o terceiro, de dependências e segredos. Depois disso o projeto rodou do zero numa sessão na nuvem, e os achados principais foram reproduzidos contra o Supabase local. Nada foi aplicado no projeto hospedado e nada foi commitado.

Cada achado diz como foi verificado. Provado quer dizer reproduzido contra o banco ou o código rodando; confirmado, lido no código depois do agente; relatado, só o agente leu.

## O que rodou localmente

| Verificação | Resultado |
|---|---|
| Supabase local com as migrations 0001 a 0039 e o seed | ok |
| pgTAP (`supabase test db`) | 29 arquivos, 694 asserções, todas passando |
| Lint, `next typegen`, `tsc` e Vitest do painel | ok; 578 testes, 580 depois desta revisão |
| `scripts/auditar-dependencias.mjs` | reprovava; passa depois da troca do Next |
| `npm run build` | ok |
| Playwright contra o banco local com a carga da demo | 7 de 7 |
| Testes Python de `scripts/testes` | 229, todos ok (o CI não roda esses testes) |

Para repetir: `dockerd &` e `SUPABASE_INTERNAL_IMAGE_REGISTRY=docker.io supabase start`, porque o proxy da sessão barra o `public.ecr.aws`. As portas foram trocadas numa cópia do repositório para o APO subir junto com outro projeto; no Mac não precisa.

## Corrigido no worktree, sem commit

O Next.js 16.3.8 tinha três alertas que o próprio auditor do repositório barra: execução remota sem login pela Image Optimization com SVG (GHSA-2464-fhr4-w9xw), execução remota em `use cache` com typed arrays (GHSA-673q-mjm6-r5xr) e negação de serviço em Server Actions (GHSA-p3m5-59mp-jv5r). O painel não usa `next/image` nem `use cache`, mas o endpoint `/_next/image` existe por padrão. A troca foi para `next` e `eslint-config-next` 16.4.3 e `vitest` 5.0.5; no lockfile, `zod` foi para 4.6.7. Todo o quadro acima passou depois da troca.

A trava que impede o assistente de citar número fora do banco só reconhecia algarismos de 0 a 9. "Dois milhões e meio", "quarenta por cento" e algarismos de largura cheia (１２３) passavam, e foi provado com a função real. Em `painel/lib/assistente/responder.ts`, a expressão passou a pegar qualquer algarismo Unicode e número por extenso; "um" e "uma" ficaram de fora porque também são artigo. Dois testes novos estão em `painel/testes/assistente.test.ts`.

## Achados abertos

### Número errado na carga real

Estes pesam mais que qualquer item de segurança, porque o diretor lê o número sem saber que ele está errado.

| Achado | Onde | Verificação | Correção mínima |
|---|---|---|---|
| Título a pagar com duas parcelas derruba o staging inteiro. O raw guarda `outcome` por `billId` e `installmentId`, mas `staging.titulo_pagar` e `staging.rateio_titulo` usam chave só por título; a fração do rateio passa de 1 e viola o check | 0002:60, 0012:37, 0039:105-148 | provado: com a segunda parcela de um título da demo, `staging.recarregar` falha em `rateio_titulo_fracao_check` (fração 2,0) e desfaz tudo | chave por parcela em `titulo_pagar` e `pagamento`, fração por parcela; teste pgTAP com título de várias parcelas |
| Staging financeiro escrito contra o JSON sintético. A referência da API traz `grossAmount`/`netAmount` em recebimentos e pagamentos e `rate` no rateio por obra, e o staging lê `amount`, que não existe | 0039:87, 96, 115-122, 152 | relatado, conferido contra a referência em `.claude/skills/erp-origem-api` | depois da amostra real, mapear o campo que o controller usa; caso pgTAP com payload no formato real |
| Chave da obra nunca conferida: `income` usa `projectId`, `outcome` usa `buildingId`, unidades e vendas usam `enterpriseId`, todos comparados com `centro_custo.id_origem` | 0039:85, 114 | relatado | sondar e guardar o de-para por endpoint em `app.centro_custo` |
| Ninguém cria tenant, obras e usuários a partir do ERP; a carga lê obras de `app.centro_custo`, que só o seed preenche | `scripts/carregar_origem.py:497` | relatado | `provisionar_tenant.py` |
| A carga real não grava `app.carga_execucao`, não chama `registrar_posicao_dre`, `recarregar_saldo_contabil` nem `recarregar_crm`, e não tem workflow; o noturno roda só a demo | `carregar_origem.py`, `carga_noturna.yml:45` | relatado | etapa de staging registrada, as três chamadas, `carga_origem.yml` com timeout maior |
| Parcela apagada ou renegociada no ERP fica como fantasma em "a receber" e "a pagar"; a janela inicial de 400 dias corta o histórico de caixa | `carregar_origem.py:125`, ADR 0005 | relatado | recarga completa semanal de `income` e `outcome` com conferência de contagem; janela desde o início da obra |
| Título sem obra (despesa da empresa, devolução de distrato) some de todas as telas, sem indicador | 0039:161 | relatado | view de não alocados e cartão na conferência |

### Segurança

| Achado | Onde | Verificação | Correção mínima |
|---|---|---|---|
| O claim do JWT vence a tabela de vínculo: usuário removido ou rebaixado continua vendo todas as obras por até 1 hora | 0006:6-20 (`coalesce(claim, tabela)`), `jwt_expiry = 3600` | provado: usuário sem vínculo com token de diretor viu as 2 obras de um tenant de teste | `tenant_atual` e `perfil_atual` lendo `usuario_tenant`; políticas antigas com `(select ...)` |
| Perfil leitura entra só com senha e lê DRE, saldos e Fontes e Usos; a senha local mínima é 6 sem exigência; diretor ou financeiro que ainda não cadastrou o fator pode ter o fator cadastrado por quem roubou a senha | `config.toml:182`, decisão 0032 | relatado | senha de 12 com proteção contra vazada no Dashboard; cadastro do fator no primeiro acesso, acompanhado; alerta de fator novo |
| `public.ultima_carga()` entrega ao anônimo a data e a situação da carga que `/api/saude` esconde sem o token | 0021:43-69 | provado: `set role anon` devolve `concluida_em` e `situacao` | devolver só a idade em horas sem token |
| O validador aceita `lpad` e `rpad` sem teto; `select lpad('a', 1000000000)` passa e pede cerca de 1 GB ao banco, que o `statement_timeout` não corta | `validador-sql.ts:44` | relatado | tirar as duas funções ou exigir comprimento literal pequeno |
| A assinatura do SQL não amarra pergunta, usuário nem perfil, e a comparação usa `=` | 0020:32 | relatado; impacto baixo, o RLS segura | assinar `consulta:<id>:<perfil>:<sql>` |
| `reservar_pergunta` aceita pergunta de vários MB pela RPC | 0023:28 | relatado | teto de 500 caracteres na função |
| Cookies do Supabase sem `HttpOnly` | `lib/supabase/servidor.ts:10`, `sessao.ts:70` | relatado; a CSP com nonce reduz o risco | `cookieOptions` com `httpOnly` |
| `raw.registro` sem RLS; hoje protegida só porque o schema não é exposto | 0001:40 | relatado | `enable` e `force` |

Seguem valendo os conhecidos: cadastro livre ligado, senha do banco a trocar, `ASSISTENTE_CHAVE_ASSINATURA` a confirmar nas duas pontas e o token do webhook do CRM na URL.

### Operação

O workflow Resumo semanal falhou em 26/10, o esperado sem conta no Resend e sem os segredos. Os testes Python não rodam no CI. Não há arquivo de dependências Python com versão travada; `openpyxl` nem aparece nos workflows. O `.gitignore` da raiz cobre `.env` e `.env*.local`, mas um `.env.production` na raiz entraria no git.

O que está certo e não precisa de mexida: RLS ligado e forçado em `app` e `staging`, uma política permissiva por tabela e ação, views com `security_invoker`, funções definer com `search_path = ''` e revoke, barreira do segundo fator no banco, validador com parser recusando uns 60 casos de ataque, execução com o JWT do usuário em transação somente leitura, CSP com nonce e `strict-dynamic`, e nenhum segredo no histórico.

## Como avançar até 18/12

Faltam umas sete semanas e meia, perto de 150 horas. O primeiro passo não depende de código e trava os outros.

1. Liberar os 403 e a rota do Bulk com o cliente, rodar `sondar_origem.py` e `sanitizar_amostras.py` e escrever o formato real de `income`, `outcome` e `sales`. Sem isso, nenhum número da entrega 1 pode ser validado.
2. Migration 0040 com o staging financeiro no formato real: chave por parcela, campos de valor certos, chave da obra por endpoint e pgTAP com payload real.
3. `provisionar_tenant.py`, convites, cadastro livre desligado e environment "piloto" no GitHub com segredos próprios.
4. Fechar o ciclo da carga real: `carga_execucao`, as três chamadas de recálculo, `carga_origem.yml` e limitador em 120 por minuto.
5. Recarga completa semanal e janela desde o início da obra.
6. Claim do JWT lido da tabela (migration nova), `ultima_carga` sem situação para o anônimo, `lpad`/`rpad` fora do validador e teto na `reservar_pergunta`.
7. Conciliação de uma obra com o controller do piloto, mês a mês. É o critério de aceite da entrega.
8. Testes Python e lint Python no CI.
9. Teste de volume com dez vezes o piloto, medindo as telas contra os 2 segundos.

A troca do Next e a trava do assistente estão no worktree. Para entrar: `cd painel && npm ci && npm run lint && npx next typegen && npx tsc --noEmit && npx vitest run && node scripts/auditar-dependencias.mjs`, e depois o commit.
