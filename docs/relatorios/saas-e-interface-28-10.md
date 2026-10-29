# Estrutura de SaaS e interface do painel

28/10/2026. Pedido do João: análise completa da estrutura de SaaS antes de montar a base de um segundo cliente com o usuário de API novo, com segurança e confiabilidade em primeiro lugar, e troca do visual do painel, que estava com cara de feito por IA, sem perder ergonomia nem os critérios da ISO/IEC 25010:2023.

A revisão de estrutura e segurança foi feita só em leitura por um subagente com o Fable 5.1, como combinado em 20/10 para análise que pede julgamento. A mudança de interface foi feita nesta sessão, no Opus 5.5, e conferida no navegador contra o Supabase local (demo com três obras). Nada foi rodado contra o xwqw nem contra obra-analitica.vercel.app.

## Parte 1. Estrutura de SaaS, segurança e confiabilidade

### Veredito

O isolamento entre clientes está bem feito. O que ainda não deixa a base do cliente novo começar com segurança é a operação: a carga real não registra a própria execução, o cliente, as obras e os usuários são criados à mão com ids da demo, a credencial do ERP e a configuração ficam em variáveis de ambiente de um processo só, e ainda não há exclusão de cliente, auditoria de administração nem teste genérico de vazamento entre clientes.

As afirmações marcadas como verificadas foram conferidas no código com arquivo e linha. Nesta sessão conferi de novo cinco delas: o carregador real não grava `app.carga_execucao`, o hook usa `limit 1`, a carga noturna roda só a demo, o CI não roda os testes Python e não há chave estrangeira nem trava em `staging.recarregar`.

### O que já está sólido (verificado)

- RLS `enable` e `force` em 41 tabelas, nenhuma `using (true)`, uma política permissiva por tabela e ação. Só `raw.registro` fica sem RLS, e o schema `raw` não tem grant nem está exposto na API.
- 46 de 46 views com `security_invoker`. Toda função `security definer` viva tem `search_path = ''`; as que o usuário pode chamar conferem tenant e perfil dentro do corpo, e as internas estão revogadas.
- Isolamento por obra pela função `app.obras_permitidas()`, inclusive no título rateado entre obras. Toda coluna de filtro tem índice começando por `tenant_id`.
- Carregador com `--tenant` obrigatório e `tenant_id` explícito em toda escrita; não foi achado caminho para a carga de um cliente escrever em outro. A carga é idempotente: hash único por registro, `on conflict do nothing`, marca incremental avançando na mesma transação e staging regravado numa transação por cliente.
- Painel sem nenhum `getSession`; identidade por `getUser` e `getClaims`, perfil por `app_metadata` ou tabela própria. Rotas e Server Actions conferem usuário, segundo fator e perfil dentro delas. `NEXT_PUBLIC_` só leva URL, chave pública, DSN do Sentry e SHA. CSP com nonce, HSTS, nosniff, Referrer-Policy e X-Frame-Options.
- Assistente com `pgsql-ast-parser`, uma instrução só, apenas `select` sobre o catálogo do perfil, lista fechada de funções, LIMIT 500, execução `security invoker` em transação somente leitura, SQL assinado e registrado antes de rodar, cota de 30 perguntas por hora por usuário e teto diário por cliente.
- Testes: 584 no Vitest, 694 asserções pgTAP em 29 arquivos, 7 no Playwright e 229 em Python.

### Achados, do mais grave ao menos

| Severidade | Achado | Evidência | O que acontece | Correção |
| --- | --- | --- | --- | --- |
| Crítico | A carga real não registra execução. Só a carga da demo grava `app.carga_execucao` | `scripts/carregar_origem.py` (nenhuma ocorrência); `0021_carga_execucao.sql:31-66`; `painel/lib/consultas/carga.ts:17` | O cliente carregado toda noite aparece "sem carga" no carimbo, `/api/saude` responde 503 e uma falha de `staging.recarregar` só vai para o log do job | Abrir e fechar `carga_execucao` por tarefa e na etapa de staging, com erro resumido em classe e SQLSTATE |
| Alto | Cliente, obras e usuários nascem à mão, com ids da demo | `supabase/seed.sql:4-13`; `scripts/vincular_usuarios_demo.py:16-41`; joins com `app.centro_custo` em `0039` | Obra que existe no ERP e não foi digitada some do staging sem aviso | `app.origem_configuracao` por cliente, função que sincroniza centros de custo a partir do `raw`, script de onboarding com argumentos |
| Alto | Não há agendamento da carga real; segredos `ORIGEM_*` e `DATABASE_URL` são únicos no repositório e a concorrência é global | `.github/workflows/carga_noturna.yml:15,45` | Uma credencial para N clientes; a carga de um trava a do outro | Workflow em matriz por cliente, com environment e segredos próprios |
| Alto (ao ter consultor) | O hook `app.claims_jwt` pega só o primeiro tenant do usuário, e o fallback `app.tenant_atual()` faz `limit 1` sem ordem | `0006_ajustes_demo.sql:10, 98-102` | Quem tem acesso a dois clientes (o Braga, por exemplo) fica preso ao de menor UUID. Não vaza dado, mas não troca | Cliente ativo na sessão, conferido contra `app.usuario_tenant` a cada requisição |
| Médio | 19 de 21 tabelas de staging têm `tenant_id` sem chave estrangeira | `0002`, `0004`, `0012`, `0018`, `0019`, `0035` | Apagar o cliente deixa dado órfão no banco e no backup, o que impede cumprir a eliminação prevista na LGPD | Migration com `references app.tenant(id) on delete cascade` e função `app.excluir_tenant` revogada dos papéis da aplicação |
| Médio | `staging.recarregar` e `recarregar_precos` sem `pg_advisory_xact_lock`, ao contrário de 0019, 0035 e 0036 | `0002`, `0012`, `0039` | Carga manual rodando junto com a noturna do mesmo cliente pode violar chave primária ou misturar staging | Trava por cliente nas duas funções |
| Médio | Os testes Python, que cobrem o carregador e a idempotência, não rodam no CI, e nenhum usa dois clientes | `.github/workflows/ci.yml` | Regressão de isolamento no carregador passa despercebida | Job com Supabase local rodando `scripts/testes`, mais caso com dois tenants |
| Médio | O teste entre clientes cobre duas relações | `supabase/tests/isolamento_perfis.sql:52-53` | Política nova errada expõe todos os clientes sem quebrar teste | pgTAP guiado pelo catálogo: para toda relação com `tenant_id`, usuário de B lê zero linhas de A |
| Médio | `urllib` segue redirecionamento copiando `Authorization` | `scripts/cliente_origem.py:186` | Um 3xx do gateway entrega a credencial do ERP a outro host | Incorporar o `http_seguro.py` que já está no worktree apis-liberadas |
| Médio | Webhook do CRM conta tentativa só depois do token bater e não confere HMAC do corpo; token vai na URL | `0016:144-149`; `app/api/origem/*` | Muitas chamadas inválidas viram RPC com sha256 cada uma | Limite antes da RPC e assinatura do corpo quando o CRM oferecer |
| Médio | Preview e produção sem separação de banco no repositório | Sem `VERCEL_ENV` nem `vercel.json`; `plano_implementacao.md:120` | Com o banco do cliente novo, preview pode apontar para produção | Variáveis por ambiente na Vercel, preview sempre em banco de teste |
| Baixo | `app.parametro_assistente` tem um teto diário único para todos os clientes | `0020_assistente.sql:87-93`; `0023:34` | Não dá para vender planos com cotas diferentes | Teto por cliente ou por plano |
| Baixo | `statement_timeout` do assistente vale pelo papel `authenticated`, não dentro da função | `0020:7`; `0025:62-63` | Se o painel passar a usar conexão direta com `set role`, o limite some | `set local statement_timeout` explícito |
| Baixo | `raw.registro` sem RLS, `/sair` sem conferência de Origin, `connect-src` sem o Sentry, `lib/supabase/navegador.ts` sem uso | `0001:40-49` e outros | Defesa em profundidade e limpeza | Itens pequenos num PR só |

Sobre migrations: a 0030 teve dois commits em 05/10. Não dá para afirmar daqui se ela já estava aplicada no xwqw entre os dois; vale conferir com `supabase migration list` e, se estava, registrar a exceção.

### O que falta para vender como SaaS

Não existem no código: tabela de plano, cobrança ou consumo; função de exclusão de cliente; trilha de auditoria administrativa; credencial do ERP guardada por cliente; saúde e concorrência por cliente. Pela documentação, o projeto está em us-east-2, sem contrato de tratamento de dados, sem SLA e sem ensaio de restauração por cliente. As linhas devolvidas pelo assistente (nome de obra, valores) vão para a Anthropic, que precisa entrar no contrato como suboperadora. As sete decisões da seção 5 da proposta de 17/10 (`docs/planejamento/saas-e-portabilidade.md`, no worktree nostalgic-newton, sem commit) seguem abertas.

### Ordem proposta

Cada passo cabe numa migration ou num PR. O risco ao lado é o de começar a carga do cliente novo sem ele.

| Passo | O que é | Risco de começar sem ele |
| --- | --- | --- |
| 1 | Projeto Supabase de produção separado da demo, região decidida, senha nova, cadastro livre desligado, hook e schemas configurados | Dado real no banco da demo, cujos segredos já apareceram em print |
| 2 | Carregador gravando `carga_execucao`; trava por cliente em `staging.recarregar` e `recarregar_precos` | Carga falha sem ninguém ver; recarga dupla corrompe o staging |
| 3 | Chave estrangeira com cascade nas 19 tabelas de staging e `app.excluir_tenant` | Não dá para cumprir a eliminação prevista em contrato |
| 4 | Configuração de origem por cliente, sincronização de centros de custo e script de onboarding | Obra digitada à mão; obra nova no ERP some sem aviso |
| 5 | Workflow por cliente com segredos próprios e `http_seguro.py` | Redirecionamento vaza credencial; um cliente trava o outro |
| 6 | CI rodando os testes Python, com caso de dois clientes | Regressão de isolamento no carregador |
| 7 | Teste pgTAP genérico entre clientes | Política nova errada expõe todos |
| 8 | Cliente ativo na sessão no lugar do `limit 1` | Consultor preso a um cliente |
| 9 | Credencial do ERP cifrada por cliente, com tela de cadastro e sondagem de permissões | Credenciais de vários clientes num segredo só |
| 10 | Auditoria só de inserção, saúde e consumo por cliente, teto do assistente por plano | Sem trilha administrativa e sem base para cobrar |
| 11 | `app` e `marts` fora da API de dados, atrás de uma camada no servidor | Toda função `security definer` nova fica chamável pelo token do usuário |

Os passos 1 a 3 vêm antes da primeira carga do cliente novo. Os passos 4 a 6 vêm antes de a carga virar rotina noturna, e os passos 7 a 11 antes do segundo cliente pagante. Pela regra de 01/10, os passos 2, 3, 7, 8 e 11, que mexem em RLS, em `security definer` ou em escrita, rodam com o Fable 5.1 ou passam por revisão de segurança nele antes do commit.

## Parte 2. Interface

### Por que parecia feito por IA

O painel seguia o molde que os geradores de código entregam por padrão para qualquer dashboard. Nenhum dos sinais abaixo é problema sozinho. Juntos, são o que faz alguém olhar a tela e reconhecer o modelo.

| Sinal | Onde estava |
| --- | --- |
| Tudo dentro de cartão branco com canto bem arredondado (12 px) e borda cinza, flutuando sobre fundo cinza | 46 ocorrências de `rounded-xl border border-borda bg-superficie`, em 35 arquivos |
| Menu lateral escuro com o item ativo numa pílula arredondada | `MenuLateral.tsx` |
| Fileira de quatro cartões iguais de indicador | Visão geral, tela da obra, simulação, repasse |
| Um "?" dentro de círculo ao lado de cada rótulo | `ExplicacaoIndicador.tsx`, usado em 19 lugares |
| Botão redondo de chat flutuando no canto inferior direito, com conversa em balões e cantos cortados | `ChatAssistente.tsx` |
| Tela de entrar dividida ao meio, com faixa colorida e frase de efeito ("Cada obra, o caixa e o estoque numa tela só.") | `app/entrar/page.tsx` e `app/seguranca/layout.tsx` |
| Selos de situação em pílula | Empresas e conferência |

### O que mudou

A referência agora é o demonstrativo financeiro impresso, que é o que o controller e o sócio já leem: fundo branco, um traço no alto de cada bloco com o título logo abaixo, números alinhados em coluna e moldura só onde ela tem função.

| Mudança | Arquivos | Característica da ISO 25010 |
| --- | --- | --- |
| Três classes no tema substituem o cartão repetido: `secao` (traço de 2 px no alto, sem caixa, sombra nem fundo), `quadro` (moldura fina só em tabela larga, que precisa do limite visível para a rolagem lateral) e `figura` (fio vertical à esquerda de um número solto). A troca foi mecânica nos 35 arquivos | `app/globals.css` e as telas e componentes que usavam o cartão | Manutenibilidade: o estilo do bloco mora num lugar só. Capacidade de interação: a leitura segue de cima para baixo, sem caixas competindo |
| Canto de botão e campo cai de 8 px para 3 px pelo token `--radius-lg`, sem mexer nos 54 usos | `app/globals.css` | Manutenibilidade |
| Fundo da página branco; menu lateral em cinza claro, com o item ativo marcado por fio petróleo à esquerda, fundo branco e negrito. Passar o mouse sublinha | `componentes/MenuLateral.tsx`, `app/globals.css` | Capacidade de interação: o ativo não depende só de cor (WCAG 1.4.1) |
| Algarismos de largura fixa em todo o painel, para os reais alinharem de uma linha para outra | `app/globals.css` | Capacidade de interação |
| Título da tela de 34 para 28 px e título de bloco de 24 para 20 px; espaço entre blocos de 28 para 40 px | Telas do grupo (painel) | Capacidade de interação: o número pesa mais que o título |
| O "?" virou chamada de nota em petróleo, sublinhada em pontilhado e sem círculo. A área de toque continua com 24 × 24 px, e o texto abre igual por toque, teclado e mouse | `componentes/ExplicacaoIndicador.tsx` | Capacidade de interação (WCAG 2.5.8) |
| O botão flutuante saiu. A pergunta rápida fica no pé do menu, junto com perfil e Sair, e abre um painel na altura toda da borda direita. A conversa vira registro: "Você" e "Assistente" em cima, o texto embaixo, sem balão. O painel vai para o `body` por portal, porque o menu é sticky e prenderia o painel abaixo das tabelas. Fechar com Esc ou com o botão devolve o foco ao gatilho | `componentes/ChatAssistente.tsx`, `app/(painel)/layout.tsx` | Capacidade de interação (foco previsível, WCAG 2.4.3); o botão flutuante cobria o canto das tabelas largas |
| Entrar e segundo fator numa moldura só: marca no topo, formulário, uma linha dizendo o que acontece. Sem faixa colorida nem frase de efeito | `componentes/MolduraAcesso.tsx` (novo), `app/entrar/page.tsx`, `app/seguranca/layout.tsx`, `componentes/MarcaApo.tsx` | Capacidade de interação, manutenibilidade (duas telas iguais viram um componente) |
| Selos de situação e barras de execução com canto reto | `app/(painel)/empresas/page.tsx`, `componentes/ConferenciaEmpresa.tsx`, `componentes/TabelaExecucao.tsx` | Coerência visual |

Não mudaram: a paleta com significado (verde entra, grafite sai, vermelho só em alerta), a marca APO, a fonte IBM Plex servida pelo próprio painel (a CSP segue em `font-src 'self'`), o contorno de foco de 3 px, os textos e as explicações. Nenhuma consulta, regra de negócio ou rota mudou.

### Contraste

O teste da paleta (`testes/paleta.test.ts`) passou a conferir o fundo branco e o cinza do menu. Todos os pares de texto ficam acima de 4,5:

| Texto | Fundo | Contraste |
| --- | --- | --- |
| Texto | Página branca | 16,52 |
| Texto | Menu cinza | 14,83 |
| Texto suave | Menu cinza | 5,92 |
| Petróleo (chamada de nota, item ativo) | Branco | 10,74 |
| Alerta | Branco | 6,54 |
| Atenção | Branco | 5,92 |

O cinza de referência dos gráficos fica em 3,82 sobre branco e 3,43 sobre o menu: serve para linha, não para texto, como antes.

### Base do trabalho

As mudanças de layout de 17/10 e 22/10 (abas da obra, menu recolhível no celular, esqueleto de carregamento, valor que não quebra no cartão), que estavam sem commit no worktree `stoic-chatterjee-e92648`, foram trazidas para este worktree como base, sem alterar aquele. O Braga já tinha visto esse layout nos prints de 22/10, e redesenhar por cima da versão antiga geraria conflito nos mesmos arquivos. O relatório de 17/10 veio junto (`docs/relatorios/layout-portal-aipim-17-10.md`). Se este trabalho for aceito, o worktree stoic-chatterjee pode ser arquivado.

### Conferido

- `tsc --noEmit` e `eslint` sem erro; Vitest com 584 testes passando (31 arquivos); `next build` de produção concluído.
- Navegador a 1440 px: visão geral, tela da obra (resumo, DRE, vendas e repasse), DRE consolidada, empresas, assistente e entrar. A 375 px: tela da obra, menu aberto e fechado, entrar; a página não rola para o lado.
- Pergunta rápida: abre por cima das tabelas, Esc fecha e o foco volta ao gatilho. Sem chave da Anthropic no ambiente local, o erro aparece em texto claro.
- Entrada com um usuário de leitura criado só no banco local (senha gerada e guardada fora do repositório).

Não conferido: os testes e2e do Playwright (pedem as credenciais do CI), a impressão do relatório da obra em A4 e a tela de cadastro do segundo fator, que exige o aplicativo autenticador.

### Páginas de erro e manutenção

Até aqui, qualquer erro caía na página padrão do Next, em inglês. Agora:

| Situação | O que aparece | Arquivos |
| --- | --- | --- |
| Endereço que não existe | "Página não encontrada", com link para a visão geral e status 404 | `app/not-found.tsx` |
| Erro numa tela do painel | Aviso com o menu ainda na tela, botão "Tentar de novo" e o código do erro para o suporte. A mensagem interna nunca aparece | `app/(painel)/error.tsx`, `componentes/AvisoErro.tsx` |
| Erro nas telas de entrar e segundo fator, ou no próprio layout raiz | O mesmo aviso, na moldura das telas de acesso | `app/error.tsx`, `app/global-error.tsx` |
| Manutenção, com `MODO_MANUTENCAO=1` | Telas com status 503, `Retry-After: 300` e o aviso; API com 503 em JSON; `/api/saude` segue no ar | `proxy.ts`, `lib/manutencao.ts`, `app/manutencao/page.tsx` |

A manutenção é decidida no proxy antes de renovar a sessão, então nada chama o Auth nem o banco enquanto ela estiver ligada. Só o valor `1` liga, para que um erro de digitação na variável não derrube a produção. Erro do servidor segue para o Sentry pelo `onRequestError`; o aviso registra só o erro que nasce no navegador. A função `forbidden()` do Next continua experimental nesta versão e não foi usada, e as telas mantêm os avisos de permissão que já tinham.

Conferido: 589 testes do Vitest (5 novos), o build de produção, a página não encontrada com 404, o erro dentro do painel com uma rota temporária que falhava de propósito com um CPF falso na mensagem (o CPF não apareceu na tela), e a manutenção num build de produção, com o status de cada caminho conferido por curl e a CSP com nonce funcionando na reescrita. A tela de erro global não foi provocada.
