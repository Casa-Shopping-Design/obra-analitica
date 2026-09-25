# PT-03: mapa de unidades e assistente com perguntas prontas

Branch `claude/pt-03`, a partir da `main` em `5b6db2e`. Execução noturna sem banco e sem login.

## O que foi feito

Mapa de unidades em `/obras/[id]/unidades`. Uma tabela por tipologia, andar mais alto em cima, uma célula por unidade. A célula mostra andar e posição, ícone de forma própria e a situação escrita (Disp., Res., Prop., Vend., Fora); o fundo muda de cor, mas a cor nunca aparece sozinha. Fora de venda tem hachura. Ao passar o mouse ou chegar pela tecla Tab aparecem valor de hoje, valor por m², área, origem do valor (contrato, tabela corrigida pelo índice ou cadastro), índice, referência e tabela. Abaixo da grade ficam os totais por situação e o estoque a preço de hoje, que vem pronto de `posicao_financeira_obra.estoque_a_vender` (disponível, reservada e proposta), a mesma regra do aceite 2.

A grade sai de `montarGrade` em `painel/lib/grade-unidades.ts`, função pura: lê `TIPO-AAPP`, agrupa por dicionário e ordena. Nome fora do padrão ou repetido vai para "Outras unidades", então nenhuma unidade some.

Assistente em `/assistente` com 13 perguntas prontas: as 10 do catálogo atual (nenhuma usa `consolidado_centro_custo` nem `break_even_obra`) e as 3 que o plano pede. Cada pergunta tem `{ id, pergunta, sql, colunas, semResultado }` em `painel/lib/perguntas-prontas.ts` e uma função de consulta com o mesmo id em `painel/lib/consultas/perguntas-prontas.ts`, escrita só com `from`, `select`, `eq`, `in`, `ilike`, `gt`, `gte`, `lte`, `order` e `limit`. O tipo `Record<IdPerguntaPronta, ...>` faz o `tsc` falhar se faltar função para alguma pergunta. A URL leva apenas o id, e id fora da lista é ignorado antes de qualquer consulta. A resposta mostra a tabela devolvida (cartões em tela estreita) e a frase "Resposta calculada a partir de N linhas, dados de dd/mm/aaaa". O campo livre aparece desabilitado com "Disponível na entrega 2".

Testes Vitest em `painel/testes/grade-unidades.test.ts` (nome, andar, posição, célula vazia, nome repetido, totais) e `painel/testes/perguntas-prontas.test.ts` (ids únicos, SQL passa no `validarSql`, só lê views do catálogo, colunas existem na view, nada de `nome_cliente`, id desconhecido é recusado).

## O que foi verificado e como

Rodei em `painel/`: `npm ci` (só com o aviso do item 5 das dúvidas), e sem erro nem aviso `npm run lint`, `npx tsc --noEmit` (depois de `npx next typegen`, ver dúvidas), `npm test` (3 arquivos, 48 testes) e `npm run build` com URL e chave fictícias só na linha de comando.

Renderizei `MapaUnidades` e `RespostaPergunta` com dados inventados e o CSS do build, fora do repositório, e olhei no navegador em cerca de 340 px e em 1280 px. Não há rolagem horizontal, o detalhe abre com Tab e a resposta vira cartão no celular. A CSP de produção bloqueia `style` inline, então tudo é classe do Tailwind; confirmei no CSS gerado que as classes arbitrárias (fundos e hachura) foram compiladas.

Conferência contra o `CLAUDE.md`: nomes em português sem acento, nenhum nome do ERP de origem, sem `console.log`, sem travessão; mensagens de erro em `lib/mensagens.ts`, sem nome de tabela nem código; nenhum SQL em texto executado, nenhum texto do usuário vira filtro; consultas com o cliente do servidor e o JWT do usuário; nome de comprador não é lido.

PAA: o mapa faz 3 consultas em paralelo por tela, sem N+1; a grade é O(u log u) com u na casa de centenas. As perguntas fazem de 1 a 3 consultas cada, com teto de 500 linhas. O nome da obra entra por dicionário, O(n). Nenhuma soma em TypeScript; a única conta é a contagem de células por situação no mapa, sobre a própria lista exibida.

## O que não deu para verificar sem banco ou login

Os três aceites do plano ficam para João: 120 unidades na Aurora e 40 na Torre, estoque igual ao `select sum(valor)` por obra, e cada pergunta em menos de 2 s, devolvendo só a Aurora quando quem pergunta é a gerente. Também não vi a tela com dados reais, não medi o tempo e não sei se o PostgREST devolve `numeric` como número (o código converte com `Number` onde formata). As cores dos ícones passaram pelo validador de paleta da skill de visualização (aviso de separação entre vendida e proposta para daltonismo, compensado pelo ícone e pelo texto); contraste de texto não foi medido com axe.

## Desvios do plano

1. Arquivos fora da lista exclusiva: `painel/lib/mensagens.ts` (dois blocos novos, `unidades` e `assistente`, no fim do objeto; pode dar conflito simples com o PT-02), `painel/app/(painel)/unidades/page.tsx` (o menu aponta para `/unidades`, que não existia; lista as obras e, com uma obra só, vai direto ao mapa), `painel/app/(painel)/obras/[id]/unidades/loading.tsx` (esqueleto), `painel/lib/grade-unidades.ts` e os dois testes.
2. O PostgREST do Supabase não agrega por padrão, então três perguntas mudaram para devolver números que existem prontos no banco. "Quantas unidades disponíveis existem hoje no total?" virou "por obra e tipologia". "Quanto vale o estoque disponível da Aurora?" virou a lista das disponíveis com o valor de cada uma. "Quanto a Aurora vai receber do banco e dos compradores?" mostra as quatro colunas em vez das duas somas.
3. "Qual obra tem mais parcelas vencidas?" virou "mais dinheiro vencido a receber dos compradores", porque as views de `marts` guardam o valor vencido, não a quantidade de parcelas.
4. "Quantos distratos houve em 2026?" virou "neste ano", filtrando do 1º de janeiro no fuso de Brasília.
5. "Dados de dd/mm/aaaa" mostra a data da consulta. Quando o PT-08 criar `app.carga_execucao`, trocar pela data da carga.

## Dúvidas e pendências

1. O SQL de cada pergunta precisa da revisão de João antes de valer (passo 3 do plano). Os testes garantem só que ele passa no validador e usa colunas do catálogo.
2. `staging.unidade` não tem índice em `(tenant_id, centro_custo_id)`, coluna usada pela política de RLS e pelo filtro do mapa. Com mil unidades por tenant a varredura custa pouco, mas o `CLAUDE.md` pede o índice. Fica para uma migration de João.
3. Limite de perguntas por usuário e registro de quem perguntou o quê ficaram para o PT-07, que cria `app.pergunta_assistente`. Sem modelo de linguagem, hoje não há custo de API.
4. Na `main`, `npx tsc --noEmit` num checkout limpo falha em `LayoutProps` até rodar `npx next typegen` ou `next build`. Isso já existia antes do PT-03; o CI do PT-08 precisa gerar os tipos antes.
5. `npm ci` mostra o aviso do npm sobre scripts de instalação não aprovados (`fsevents`, `unrs-resolver`), também anterior a este pacote.
6. O item "Obras" do menu aponta para `/obras`, que não existe e não é do PT-03.
