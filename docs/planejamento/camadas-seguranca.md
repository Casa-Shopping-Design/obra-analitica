# Camadas de segurança para Vercel e Supabase

28/10/2026. Pedido do João: um plano de segurança que funcione na arquitetura atual. Hoje o painel Next.js roda na Vercel; o banco, o Auth e a API de dados ficam no Supabase; e a carga roda no GitHub Actions. Cada camada abaixo diz o que já existe (conferido no repositório ou no GitHub em 28/10), o que falta, quem faz e como conferir.

Ficam de fora o nginx e o Cloudflare como proxy na frente da Vercel. O painel não tem servidor próprio, então o nginx pediria uma máquina só para repassar tráfego, que viraria ponto único de falha. Já o proxy do Cloudflare esconde o IP de quem acessa, o que enfraquece o firewall e a proteção contra robôs da Vercel; a própria Vercel desaconselha essa montagem ([guia da Vercel](https://vercel.com/kb/guide/can-i-use-a-proxy-on-top-of-my-vercel-deployment)). O Cloudflare entra onde soma: no DNS e no Turnstile.

## Camada 0. Repositório público (urgente)

O repositório `Casa-Shopping-Design/obra-analitica` é público desde 22/09/2026, sem proteção na main e com a varredura de segredos do GitHub desligada.

O que está exposto: o código inteiro, as migrations e o desenho de RLS, os documentos de negócio (o nome do cliente Verg aparece em 13 arquivos, e há pautas de reunião) e, em `docs/planejamento/pauta-braga-08-10.md`, e-mails pessoais de sócios.

O que não foi achado: nenhum segredo. Varri os 93 commits da main e os 27 branches publicados atrás de chave da Anthropic, chave secreta do Supabase, senha em URL de banco, senha do ERP, token do GitHub e JWT. A única URL de banco é o modelo com `SENHA` e `PROJETO`. A busca foi por padrão; o gitleaks da camada 1 confirma com mais regras.

Exposição medida: o GitHub registra 1 visita, de 1 pessoa, nos últimos 14 dias, e nenhum fork. É provável que tenha sido o próprio João, mas o GitHub só guarda 14 dias de tráfego.

| Ação | Quem | Como conferir |
| --- | --- | --- |
| Tornar o repositório privado (Settings, General, Danger Zone, Change visibility) | João | `gh api repos/Casa-Shopping-Design/obra-analitica --jq .visibility` devolve `private` |
| Antes de virar, conferir o plano da organização no GitHub (os minutos do Actions passam a contar) e se a Vercel continua publicando de repositório privado de organização | João | Carga noturna e CI rodam depois da troca; deploy da Vercel sai verde |
| Tirar os e-mails pessoais da pauta de 08/10 num commit novo. Reescrever o histórico não vale a pena com 1 visita registrada | Claude prepara, João commita | `git grep -i "proton.me\|@gmail" HEAD` vazio, fora a documentação pública de webhook das skills |

## Camada 1. Código e repositório

Hoje o CI roda lint, `tsc`, Vitest, auditoria de dependências do npm, pgTAP, carga da demo e Playwright. Não há `dependabot.yml`, nem `SECURITY.md`, nem varredura de segredo.

| O que falta | Por quê | Quem |
| --- | --- | --- |
| Proteção da main: PR obrigatório, CI verde obrigatório, sem force push e sem apagar o branch | Hoje qualquer push na main publica na Vercel | João, em Settings, Rules |
| gitleaks no CI, sobre o histórico inteiro e em cada PR | No repositório privado, a varredura nativa do GitHub é paga; o gitleaks é gratuito. Já existe preparado no worktree vibercoder (item 6 do inventário de 20/10), com placeholders a trocar | Claude |
| Dependabot para npm, pip e GitHub Actions | Os alertas do Dependabot são gratuitos também em repositório privado | Claude |
| Testes Python do carregador no CI e `pip-audit` | Hoje o CI não roda os 229 testes Python, que cobrem a idempotência da carga | Claude |
| Actions fixadas por SHA (o `carga_noturna.yml` já fixa o `setup-python`) e `permissions: contents: read` em todos os workflows | Uma action comprometida não pode escrever no repositório | Claude |

## Camada 2. Contas de administração

Quem toma a conta de administrador passa por cima de todas as outras camadas.

| Conta | O que fazer |
| --- | --- |
| GitHub, organização Casa-Shopping-Design | Exigir segundo fator de todos os membros (Settings, Authentication security) e manter só João como dono |
| Vercel, equipe casa-design | Segundo fator em todos os membros e só João como dono |
| Supabase, organização Casa Design | Segundo fator em todos os membros e papel de leitura para quem não aplica migration |
| Anthropic, console da empresa | Segundo fator, limite de gasto mensal e a chave da produção separada da chave da demo |
| Domínio | Registrador com segundo fator e bloqueio de transferência |

Tudo isso é do João, porque são configurações de conta.

## Camada 3. Borda, na Vercel

Já existe: HTTPS com HSTS e `preload`, CSP com nonce e `strict-dynamic`, `X-Frame-Options: DENY`, `nosniff`, `Referrer-Policy` e `Permissions-Policy` (`painel/next.config.ts`, `painel/lib/politica-conteudo.ts`), além de cabeçalho `X-Powered-By` desligado.

| O que falta | Detalhe |
| --- | --- |
| Regras de limite no Firewall da Vercel | `POST /entrar` (a Server Action de `app/entrar/acoes.ts`), `/api/assistente` e `/api/origem/*`, por IP. O assistente já tem cota no Postgres; a regra na borda corta antes de gastar função. Conferir quantas regras o plano da equipe permite |
| Proteção contra robôs da Vercel ligada | Só funciona sem proxy na frente, que é mais um motivo para não usar o Cloudflare como proxy |
| Projeto Vercel separado para a produção | `obra-analitica.vercel.app` é a demo dos sócios. O cliente real ganha projeto próprio, com variáveis só de produção e com o preview num banco de teste |
| Domínio próprio com DNS no Cloudflare em modo só DNS (nuvem cinza) e DNSSEC | O certificado é emitido pela Vercel e o Cloudflare não fica no caminho do tráfego |

## Camada 4. Login

Já existe: login por Server Action com `getUser` no servidor, segundo fator obrigatório para diretor e financeiro (0022), cadastro livre a desligar no projeto novo e mensagem de erro sem detalhe técnico.

| O que falta | Detalhe |
| --- | --- |
| Cloudflare Turnstile ligado no Supabase Auth | Ligar no Supabase, não só na tela: a chave pública permite chamar o Auth direto, sem passar pelo painel. Muda o `FormularioEntrar` e a Server Action (que passa a enviar o `captchaToken`) e a CSP (`script-src` e `frame-src` para `challenges.cloudflare.com`) ([CAPTCHA no Supabase](https://supabase.com/docs/guides/auth/auth-captcha)) |
| Proteção contra senha vazada e tamanho mínimo de senha | No Dashboard do Supabase, Authentication |
| Limites de tentativa do Auth revistos | No Dashboard do Supabase, Authentication, Rate Limits |
| Tempo de sessão | Encerrar a sessão por inatividade, para notebook esquecido aberto. Conferir se o plano Pro já oferece |

## Camada 5. Banco

Já existe: RLS ligado e forçado em todas as tabelas expostas, isolamento por cliente e por obra, schemas `raw` e `staging` fora da API, assistente em transação somente leitura e, com a 0041 e a 0042, trava de recarga e exclusão de cliente.

| O que falta | Detalhe |
| --- | --- |
| Papel próprio para a carga | Hoje a `DATABASE_URL` da carga usa o usuário dono do banco. Um papel `carregador`, com permissão só nos schemas e funções que a carga usa, limita o estrago se o segredo vazar. Pede migration e revisão com o Fable 5.1 |
| SSL obrigatório nas conexões diretas | Dashboard do Supabase, Database, SSL Configuration |
| Restrição de rede (só IPs autorizados conectam no Postgres) | O GitHub Actions muda de IP a cada execução. Para fechar o banco por IP, a carga precisa rodar num runner com IP fixo. A restrição não vale para Auth e API de dados, que continuam protegidos por RLS e limites ([Network Restrictions](https://supabase.com/docs/guides/platform/network-restrictions)). Decisão do João, pelo custo do runner |
| Backup com ensaio de restauração | O plano Pro tem backup diário; a recuperação em qualquer ponto é paga à parte. Fazer um ensaio de restauração por cliente antes do segundo cliente pagante |

## Camada 6. Aplicação e dado

São os itens da Parte 1 de `docs/relatorios/saas-e-interface-28-10.md` que ainda não foram feitos: onboarding por cliente (passo 4), carga em matriz por cliente com o `http_seguro.py` (passo 5), teste genérico entre clientes (passo 7), cliente ativo na sessão (passo 8), credencial do ERP cifrada por cliente (passo 9), auditoria administrativa (passo 10) e `app` e `marts` fora da API de dados (passo 11). Somam-se os baixos: o Sentry no `connect-src`, a conferência de Origin em `/sair` e a assinatura do corpo no webhook do CRM.

## Camada 7. Vigilância

| O que | Detalhe |
| --- | --- |
| Alerta de carga que falhou | Com a 0041, a carga real grava `app.carga_execucao`; o monitor de `/api/saude` (UptimeRobot com `MONITOR_TOKEN`) avisa quando a carga do dia não rodou |
| Alertas do Sentry | Erro novo em produção vai para o e-mail do João |
| Revisão mensal dos acessos | Quem tem conta no painel, em cada cliente, e quem tem papel de administrador nas plataformas |

## Ordem

1. Camada 0, já: repositório privado.
2. Camada 2: segundo fator nas contas de administração. Leva minutos e não depende de código.
3. Camada 1: proteção da main e gitleaks, antes do próximo merge.
4. Camadas 4 e 5 no projeto de produção, antes de criar o primeiro usuário real: Turnstile, senha vazada, SSL e papel da carga.
5. Camada 3, quando o projeto Vercel de produção for criado.
6. Camadas 6 e 7, nos passos 4 a 11 do relatório.
