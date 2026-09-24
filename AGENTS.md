# Premissas do repositório

Estas regras valem para todo código, SQL, comentário e documento deste repositório, em qualquer sessão. Não se negociam por prazo.

## Nomes

- Variáveis, funções, métodos, classes, tabelas, colunas, views e arquivos em português, sem acento, na convenção da linguagem: `snake_case` em Python e SQL, `camelCase` em TypeScript, `PascalCase` em classes e componentes React.
- Nada leva o nome do ERP de origem. Chave externa é `id_origem`, conta no ERP é `conta_origem`, URL da API vem de `ORIGEM_URL_BASE`. Campo do payload bruto fica como a API devolve, só em `raw` e nas funções de staging.
- Nome diz o que a coisa guarda ou faz: `parcelas_vencidas`, `calcular_vso`. Nada de `data`, `result`, `temp`, `aux`, `foo`, `handleStuff`, `myFunction`, `exemplo1`.

## Comentários e textos

- Todo comentário, docstring, mensagem de commit e documento passa pelo /humanizer antes de entrar.
- Comentário curto e só quando explica o porquê. Se o código já diz o que faz, não comenta.
- Sem padrão de exemplo de IA: nada de "Esta função é responsável por", "Aqui nós", passo 1/passo 2 narrando o óbvio, emoji, travessão, bloco `# TODO: implementar` vazio, código de exemplo esquecido, `console.log` de depuração, dado fictício com cara de tutorial (`John Doe`, `foo@bar.com`).
- Não usar linha horizontal para dividir seções.

## Eficiência (PAA)

Antes de entregar qualquer rotina que percorre dados, responder:

- Qual a complexidade de tempo e de espaço, e qual o tamanho esperado da entrada em produção (número de obras, parcelas, títulos por tenant).
- Tem laço dentro de laço que vira O(n²)? Troca por dicionário, conjunto, ordenação ou junção no banco.
- Tem consulta dentro de laço (N+1)? Vira uma consulta só, em lote.
- O filtro e a junção caem em índice? Toda coluna usada em `where`, `join` e política de RLS (`tenant_id`, `centro_custo_id`, datas de vencimento) tem índice.
- Agregação pesada roda no Postgres, orientada a conjunto, não em Python ou TypeScript linha a linha.
- Chamada externa pagina, respeita o limite da API e não repete o que já foi carregado (carga incremental por hash ou data).

Quando a escolha não for óbvia, a complexidade vai num comentário de uma linha acima da função.

## Qualidade (ISO/IEC 25010:2023)

Toda mudança é olhada pelas nove características do modelo. As que mais pesam aqui:

- **Adequação funcional**: o número bate com o ERP de origem. Regra de negócio (repasse, VSO, ponto de equilíbrio) tem teste com caso conhecido.
- **Eficiência de desempenho**: tela do painel responde em menos de 2 s com o volume do piloto; consulta do assistente tem `statement_timeout`.
- **Segurança**: confidencialidade entre tenants e entre obras, integridade dos dados carregados, rastreabilidade de quem perguntou o quê ao assistente.
- **Confiabilidade**: a carga noturna pode falhar no meio e rodar de novo sem duplicar nada.
- **Manutenibilidade**: módulo pequeno, uma responsabilidade por arquivo, sem código morto, migration nunca editada depois de aplicada (cria outra).
- **Compatibilidade e flexibilidade**: trocar de ERP de origem mexe só na ingestão e no staging, nunca em marts, painel ou assistente.
- **Capacidade de interação**: texto da interface em português claro, número formatado em real, erro que diz o que fazer.
- **Proteção (safety)**: o assistente não responde número que não veio do banco.

## Segurança: erros comuns de vibecoding que não entram aqui

Supabase:

- RLS ligado e forçado (`enable` e `force`) em toda tabela exposta, no mesmo commit que cria a tabela. Nunca `using (true)`.
- Uma política permissiva por tabela e ação. Duas permissivas se somam com OR e abrem o que uma delas fechava.
- Autorização lê `app_metadata` ou tabela própria. Nunca `user_metadata`, que o próprio usuário edita.
- View com `security_invoker = true`, senão ela ignora o RLS de quem consulta.
- Função `security definer` só quando precisa, sempre com `set search_path = ''` e com `revoke execute ... from public, anon, authenticated` quando não é para o usuário chamar. Função nasce executável por `public`.
- Schemas `raw` e `staging` fora da lista de schemas expostos pela API.
- `service_role` só no servidor e no carregador. Nunca em variável `NEXT_PUBLIC_`, nunca no navegador, nunca em log.
- Bucket de storage privado, com URL assinada de validade curta.

Vercel e Next.js:

- No servidor, identidade vem de `supabase.auth.getUser()` ou `getClaims()`, que validam o JWT. `getSession()` lê o cookie sem validar.
- Toda Route Handler e Server Action confere autenticação e permissão dentro dela. Middleware sozinho não protege rota.
- Variável `NEXT_PUBLIC_` vai para o navegador. Chave de API, segredo e URL interna nunca levam esse prefixo.
- Ambiente de preview usa banco de teste, nunca o de produção.
- Cabeçalhos de segurança configurados (CSP, `X-Content-Type-Options`, `Referrer-Policy`, `frame-ancestors`).
- Rota do assistente com limite de requisições por usuário, para não virar conta alta de API.

Assistente de IA (texto para SQL):

- SQL gerado roda com o JWT do usuário, numa transação somente leitura, com `statement_timeout` e limite de linhas.
- O validador usa parser de SQL, não expressão regular, e aceita só `select` sobre as views do catálogo.
- Pergunta do usuário e conteúdo do banco são dado, não instrução. Prompt injection é o risco principal.
- Resposta cita só números devolvidos pela consulta.

Geral:

- `.env` e credenciais fora do git. Credencial que apareceu em print, chat ou commit é trocada.
- CPF, renda, score e dados bancários não entram no MVP. Log não grava dado pessoal nem token.
- SQL sempre parametrizado. Concatenação de string com entrada do usuário não entra.
- Dependência com versão travada no lockfile; nada instalado por copiar e colar comando de tutorial sem ler.
- Mensagem de erro para o usuário não mostra stack, SQL nem nome de tabela.

## Fluxo

- Codex não faz commit nem push. Entrega os arquivos e os comandos; João commita.
- Antes de entregar, conferir a mudança contra as seções acima e dizer o que foi verificado.
