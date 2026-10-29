# Layout do painel comparado ao portal aipim.tech

17/10/2026. Pedido do Braga: aproximar o painel do layout do portal do cliente em https://portaldocliente.aipim.tech/home_logado. O João pediu, na mesma sessão, o levantamento das funcionalidades do portal que faltam aqui; está na seção de funcionalidades, só como proposta.

O portal foi lido no Chrome do João, com a sessão do Braga, só em leitura: navegação pelo menu e pelas abas, capturas de tela e leitura de estilo pelo navegador. Nada foi gravado, enviado ou alterado no portal. Este relatório descreve estrutura e estilo e não traz nenhum número de cliente que aparece lá.

O painel foi rodado neste worktree contra o Supabase local (migrations 0001 a 0039, seed e carga da demo), com um usuário diretor de teste criado só no banco local. Nada foi rodado contra o projeto hospedado nem contra obra-analitica.vercel.app.

## Como o portal é montado

Menu lateral escuro de 264 px, em degradê de azul-marinho para roxo, com grupos em caixa alta que abrem em acordeão (Operações, Agentes, Integrações, Governança, Conta). Módulos não contratados aparecem com cadeado. No pé do menu ficam avatar, e-mail e empresa. Acima do conteúdo há uma barra clara com o botão de recolher o menu, o nome da empresa e um sino de notificações.

Dentro do módulo de contabilidade, uma faixa em degradê com o nome do módulo e, logo abaixo, abas horizontais que rolam para o lado: visão geral, DRE de viabilidade, receita de vendas, carteira de recebíveis, custo do empreendimento, gestão de imposto, gestão de despesas, importação de dados e central de ajuda. Cada tela tem título grande com subtítulo ao lado, um seletor de empreendimento à direita e um seletor de mês com setas de anterior e próximo.

Os indicadores ficam em cartões cheios de cor, quatro por linha, cada um com um degradê diferente (azul, roxo, laranja, rosa, ciano, verde, grafite), ícone num círculo translúcido, rótulo de 11 px em caixa alta e valor de 27 px em peso 900. A fonte é Futura em toda a interface.

A DRE de viabilidade é uma tabela larga com rolagem lateral e campos editáveis amarelos dentro das células. O gráfico de tendências mensais alterna entre receita x custo e indicadores percentuais, e entre barras e área.

Enquanto carrega, cada tela mostra uma caixa com indicador giratório e o texto "Carregando dados da ...". Módulo não contratado aparece como caixa tracejada com "Produto não contratado.". Um botão flutuante "Agente", com foto, fica no canto inferior direito.

No celular (390 px) o menu some atrás do botão de três linhas, os cartões viram uma coluna e as abas rolam para o lado, sem estouro horizontal da página.

## O que o painel já faz melhor e fica como está

Cada item abaixo foi comparado com o portal e a troca pioraria pelo menos uma característica da ISO/IEC 25010:2023.

| Ponto | Portal | Painel | Característica que perderia |
| --- | --- | --- | --- |
| Cor dos cartões | Cada cartão tem uma cor sem significado: custo e imposto a produzir em vermelho, recebimento em ciano | Cartão branco; cor só com significado (verde é entrada, grafite é saída, vermelho é alerta) | Capacidade de interação: cor que não significa nada tira o peso do vermelho de alerta |
| Contraste | Branco sobre o início do degradê fica entre 3,05 e 3,75 em cinco cores, abaixo de 4,5 para o rótulo de 11 px | Texto escuro sobre branco; contrastes anotados na paleta em globals.css | Capacidade de interação (acessibilidade, WCAG 2.2 AA) |
| Número em português | Percentual com ponto (73.50%), eixo em 15.0M | Intl pt-BR: 55,9%, R$ 1,3 mi no eixo | Capacidade de interação (número formatado em real) |
| Rótulo do indicador | Caixa alta, 11 px, peso 900 | Frase normal, 14 px, com botão "?" que explica o indicador | Capacidade de interação: caixa alta pequena é mais lenta de ler e o portal não explica o que cada número é |
| Foco do teclado | Abas sem contorno de foco | Contorno de 3 px em todo elemento focado | Capacidade de interação (acessibilidade) |
| DRE de viabilidade | Campos editáveis dentro da tabela | Estudo editado em tela própria, com versão gravada e anterior guardada | Segurança (rastreabilidade) e adequação funcional: dá para saber qual estudo gerou cada margem |
| Tempo de tela | Visão geral levou 5,8 s na API, medido no navegador | Todas as telas medidas abaixo de 0,5 s no banco local (tabela de medições adiante) | Eficiência de desempenho (meta de 2 s) |
| Fonte | Futura, licença paga, sem arquivo próprio | IBM Plex servida pelo próprio painel, com CSP em font-src 'self' | Segurança e manutenibilidade: trocar exige licença e abrir a CSP para outro domínio |
| Módulo ausente | Caixa "Produto não contratado." e item com cadeado no menu | O menu esconde o que o perfil não abre e cada tela confere de novo | Capacidade de interação: o usuário não esbarra em tela que não pode usar |

## Mudanças aplicadas

Todas estão no painel/ deste worktree, sem commit.

| Mudança | Arquivos | Característica | Conferido |
| --- | --- | --- | --- |
| Abas nas telas da obra, como as do portal: faixa com Resumo, DRE de viabilidade, Imposto, Unidades, Estoque, Simulação, Vendas e repasse, Execução física, Inadimplência, Conferência e Relatório. A aba ativa tem traço e negrito, não só cor, e `aria-current="page"`. No celular a faixa rola para o lado; em tela média que não comporta tudo, quebra em duas linhas em vez de esconder abas. Aparece na tela da obra e em todas as telas filhas, inclusive no estudo da DRE (com a aba DRE ativa). Substitui a lista de links sublinhados, que ocupava cinco linhas no celular | `componentes/AbasObra.tsx`, `componentes/ListaAbasObra.tsx`, `lib/abas-obra.ts`, `componentes/CabecalhoTelaObra.tsx`, `app/(painel)/obras/[id]/page.tsx`; sai `componentes/LinksObra.tsx` | Capacidade de interação, manutenibilidade (regra pura com teste) | Navegador a 1440 px e a 375 px; 6 casos em `testes/abas-obra.test.ts` |
| Perfil lido uma vez por requisição. A tela e as abas pedem o perfil; com `React.cache` a segunda chamada não vai ao banco | `lib/consultas/perfil.ts` | Eficiência de desempenho | Build de produção e telas da obra no navegador |
| Menu recolhível no celular. Abaixo de 768 px o menu vira uma barra com a marca e o botão "Menu" (`aria-expanded`); fecha ao escolher um item. A partir de 768 px fica igual ao de antes. A faixa do menu caiu de 342 px para 68 px na tela de 375 px, e o conteúdo começa na primeira dobra | `componentes/MenuLateral.tsx` | Capacidade de interação | Navegador a 375 px: abre, fecha ao navegar, sem rolagem lateral da página |
| Estado de carregamento em todas as telas do painel: esqueleto no formato de título, cartões e bloco, com texto para leitor de tela ("Carregando os números da tela."). A animação respeita a preferência de movimento reduzido. O mapa de unidades mantém o esqueleto próprio | `app/(painel)/loading.tsx` | Capacidade de interação, eficiência percebida | O HTML de produção de /obras traz o esqueleto antes do conteúdo |
| Botão e janela do assistente na paleta do painel. Estava em azul padrão (`bg-blue-600`), com emoji no botão e classes `cinza-*` e `vermelho-*` que não existem no tema, então metade da janela saía sem estilo. Agora usa petróleo do menu, ícone desenhado, contorno de foco visível (o campo tinha `focus:outline-none`), rótulo no campo, `aria-live` nas respostas e Esc para fechar. Erro de rede mostrava a mensagem crua do navegador ("Failed to fetch"); agora diz "Não foi possível falar com o assistente. Confira a conexão e tente de novo." Também corrigido: o foco não voltava ao campo depois da resposta, porque o campo ainda estava desativado nesse instante | `componentes/ChatAssistente.tsx` | Capacidade de interação (acessibilidade, erro que diz o que fazer) | Navegador: pergunta enviada ao assistente local (sem chave, devolve 503), mensagem de erro clara, foco no campo, Esc fecha |

## Para decidir: João ou Braga

Nenhum destes foi aplicado.

| Proposta | O que ganha | O que pesa contra | Recomendação |
| --- | --- | --- | --- |
| Data da carga no topo da tela, ao lado do título, como o "Atualizado em" do portal (hoje está no rodapé) | Adequação funcional: quem lê o número vê de quando ele é sem rolar até o fim | Nenhum risco técnico; o teste e2e procura o texto, não a posição | Aplicar |
| Seletor de obra no topo das telas da obra, para trocar de obra sem voltar à lista | Capacidade de interação | Uma consulta a mais por tela (lista de obras, pequena) | Aplicar depois de confirmar com o Braga |
| Seletor de mês com setas nas telas de DRE, imposto e carteira | Adequação funcional: ver a posição de um mês passado | Precisa das views por competência; hoje a posição da DRE é do mês corrente e o histórico tem o degrau ainda em aberto | Esperar a decisão sobre o histórico |
| Cartões cheios de cor | Aparência mais próxima do portal | Contraste abaixo de 4,5 e cor sem significado (ver tabela anterior) | Não aplicar. Se o Braga quiser mais cor, um traço fino colorido no topo do cartão, só onde a cor diz algo (entrada, saída, alerta) |
| Valores em reais sem centavos nos cartões, com centavos só nas tabelas | Leitura mais rápida dos cartões, como no portal | O controller confere com o ERP pelo centavo; arredondar na tela gera pergunta | Decisão do João com o controller do piloto |
| Barra superior com nome da construtora e botão de recolher o menu no computador | Mais área útil em tela pequena de notebook | O nome da construtora já está no pé do menu; o sino do portal não tem equivalente (os alertas estão em "Pede atenção") | Não aplicar agora |
| Menu em grupos com acordeão e módulos com cadeado | Prepara o painel para módulos vendidos à parte | O painel tem seis itens; agrupar esconde o que hoje está a um clique | Só quando houver módulo vendido à parte |
| Gráfico de tendência com alternância barras e área na visão geral | Paridade com o portal | A tendência já está na DRE de cada obra; repetir na visão geral soma consultas à tela mais acessada | Decisão do Braga |
| Paleta roxa e azul do portal e fonte Futura | Paridade visual | Conflita com a marca APO, com o padrão dos documentos do João e com a CSP | Não aplicar |

## Funcionalidades: o que o portal tem e o painel não

Pedido do João na mesma sessão: ver o que está implementado no portal e falta aqui, e o que lá é mais avançado e vale trazer. Nada desta seção foi implementado; fica como proposta.

Para isso foram lidas, também só em leitura, as abas receita de vendas, custo do empreendimento, gestão de despesas, importação de dados e central de ajuda, além das telas de agentes, integrações, usuários, auditoria e notificações. A central de ajuda conta como o portal funciona por dentro. Todo o módulo de contabilidade sai do relatório Mapa Imobiliário do ERP, que o cliente envia em planilha ou que o portal busca pela API. Os percentuais da visão consolidada são média simples entre os empreendimentos.

O mesmo Mapa Imobiliário existe no ERP como recurso REST (`GET /real-estate-map`, versão 1, sem Bulk), e o APO já o carrega em `staging.mapa_imobiliario_mensal` desde a 0019. Boa parte do que o portal mostra, o painel já tem o dado para mostrar.

Esforço: baixo é até dois dias, médio de três a sete, alto passa de uma semana. Regra aplicada: nada pode depender do Bulk Data, que é contratado à parte. Onde o caminho atual usa Bulk, a coluna de dado diz qual é o caminho só REST.

### Grupo 1: o portal tem e o painel não tem

| Funcionalidade no portal | Faz sentido para o APO | Dado de que depende | Esforço | ISO 25010 que melhora |
| --- | --- | --- | --- | --- |
| Importar o relatório Mapa Imobiliário por planilha XLSX, com etapas de validação e histórico (registros novos, atualizados, arquivo repetido) | Não agora: a alimentação é pela API. Pesam contra: dado duplicado; arquivo de outra obra, de outro mês ou de outra empresa; planilha editada à mão; duas fontes disputando o mesmo número; e o upload como superfície de ataque. Se um dia entrar, entra como exceção controlada: grava no mesmo staging da API, com uma fonte vencedora por obra e período, valida o modelo antes de gravar, mostra uma prévia que alguém aprova, permite desfazer o lote inteiro e registra quem subiu | Relatório Mapa Imobiliário exportado da tela do ERP. Sem Bulk | Alto: leitura do XLSX, validação do modelo, bucket privado com URL assinada, prévia, aprovação e desfazer por lote | Melhoraria a compatibilidade e flexibilidade (não depender da permissão de API), mas ameaça a integridade do dado (segurança) e a adequação funcional, que exige que o número bata com o ERP |
| Importar sob demanda: o usuário escolhe empreendimentos e período, vê quais já estão no painel e quais estão pendentes | Em parte. A carga noturna fica. Vale uma tela para o diretor escolher quais obras entram no primeiro acesso e um botão "carregar agora" com limite por dia | `cost-centers` e `enterprises` (REST; os dois responderam para a Verg) | Médio | Capacidade de interação (cliente novo entra sem suporte), eficiência (respeita a cota diária da API se o botão tiver limite) |
| Seletor de mês com setas de anterior e próximo em todas as telas | Sim, para DRE, imposto, carteira e custo | `real-estate-map` por mês (REST, já carregado). A DRE mensal depende do histórico, que ainda tem o degrau da decisão 1 do lote 3 | Médio | Adequação funcional (consultar um mês fechado) |
| Tela de custo do empreendimento: orçado, incorrido acumulado, a incorrer, custo das vendas apropriado, estoque e a evolução mês a mês | Sim. Hoje o custo aparece espalhado na DRE, na execução física e nos alertas | `real-estate-map` (REST, já carregado: `budgetedCost`, `accumulatedIncurredCost`, `costToIncur`, `appropriateCost`, `stock`) | Baixo a médio: view nova sobre o staging e uma tela | Adequação funcional, capacidade de interação |
| Tela de receita de vendas: VGV tendência, contratado, em estoque, receita apropriada, a apropriar e a realizar, com evolução mensal | Sim, como aba da obra ou como bloco da DRE. Os números já existem espalhados | `real-estate-map` e `sales-contracts` (REST, já carregados) | Baixo | Adequação funcional |
| Central de ajuda com passo a passo por tela, problemas comuns e glossário | Sim. O "?" de cada indicador fica; a central junta tudo numa página e pode ser gerada do mesmo `lib/explicacoes.ts`, para não ter dois textos | Nenhum dado do ERP | Baixo | Capacidade de interação (aprendizagem), manutenibilidade (uma fonte de texto) |
| Auditoria das alterações de configuração: quem mudou, quando e com qual justificativa | Sim. O banco já guarda `criado_por` e `criado_em` no estudo de viabilidade e na alíquota; falta a tela e o campo de justificativa | Tabelas do próprio APO | Baixo a médio | Segurança (responsabilização e rastreabilidade) |
| Tela de usuários: lista com perfil e situação, cadastro só para administrador | Sim, mas é parte da estrutura SaaS, que está em outra sessão | Tabelas do próprio APO e o Auth | Médio | Segurança, capacidade de interação |
| Notificações no sino, com marcar como lida | Opcional. O painel já tem "Pede atenção" e o resumo semanal por e-mail. Um contador de alertas novos desde a última visita resolve o mesmo problema | Alertas que o APO já calcula | Médio | Capacidade de interação |
| Catálogo de agentes (cobrança, pós-venda, pré-venda) e de integrações (WhatsApp, Asana, outros CRMs e ERPs) | Não agora. São produtos da própria Aipim, fora do escopo do APO | | | |

### Grupo 2: os dois têm, o portal faz de forma mais avançada

| Funcionalidade | Portal | Painel hoje | Faz sentido para o APO | Dado de que depende | Esforço | ISO 25010 que melhora |
| --- | --- | --- | --- | --- | --- | --- |
| Simulações da DRE de viabilidade | Várias simulações por mês-base, com nome, descrição e histórico para escolher qual usar | Uma versão vigente por obra; a anterior fica guardada, mas não dá para escolher qual vale nem comparar | Sim. Dar nome à versão e permitir comparar duas lado a lado. A edição continua na tela própria, com segundo fator | Tabelas do próprio APO | Médio | Adequação funcional |
| Despesas e resultado | Tela própria com corretagem, publicidade, administração central, despesa tributária, receita e despesa financeira, resultado financeiro, lucro líquido e margem líquida | Despesas comerciais e administrativas em duas linhas; a margem mostrada é a operacional, até o lucro líquido ter definição | Sim, depois que o Braga definir o lucro líquido. Abrir as despesas comerciais em corretagem e publicidade é o primeiro passo | `real-estate-map` (`commission`, REST, já carregado), `GET /commissions` (REST) e `trial-balance` (REST, hoje com 403 nas duas credenciais testadas) | Médio | Adequação funcional |
| Gestão de imposto | Regime tributário com alíquotas prontas (lucro presumido, RET, lucro real) ou personalizadas, e a alíquota efetiva calculada | Uma alíquota por obra, com vigência | Sim. Menos erro de digitação e o sócio vê de onde saiu a alíquota | Nenhum dado do ERP; as alíquotas de cada regime ficam no APO | Baixo a médio | Adequação funcional, capacidade de interação |
| Gráficos de evolução mensal | Carteira, receita e custo, cada um com troca entre barras e área e entre valores e percentuais | Fluxo de caixa mensal, tendência da margem e VSO | Sim, para carteira e custo, junto com as telas do grupo 1 | `real-estate-map` (REST, já carregado) | Baixo por gráfico | Adequação funcional |
| Carteira de recebíveis | Separa contas a receber financeiro de contas a receber contábil, e mostra o recebimento do mês | Caixa, exposição, vencido e repasse atrasado | Sim. O controller usa essa diferença para conciliar | Contábil: `real-estate-map` (`customerBalance`, REST). Financeiro: `income` é Bulk; o caminho só REST é o das parcelas a receber da 0040, ainda sem aplicar | Médio | Adequação funcional |
| Assistente | Usa a aba, a empresa e o período abertos como contexto da pergunta | O assistente não sabe em que tela o usuário está | Sim. A tela manda só o id da obra e o nome da tela; a pergunta continua passando pelo validador e pelo RLS. O texto da tela é dado, não instrução | Nenhum dado novo | Baixo a médio | Adequação funcional, proteção (resposta presa à obra aberta) |

### Grupo 3: o painel já faz melhor e deve ficar

| O que o painel tem | Como o portal faz | Por que fica |
| --- | --- | --- |
| Carga noturna automática e incremental, que pode cair no meio e rodar de novo sem duplicar | Importação disparada pelo usuário, por planilha ou pela API | Confiabilidade, e o número está pronto de manhã sem ninguém lembrar de importar |
| Consolidação feita no banco, somando valores e ponderando percentuais pelo peso de cada obra | Percentual consolidado é média simples entre os empreendimentos | Adequação funcional: a média simples dá o mesmo peso a uma obra de 40 milhões e a uma de 8, e o POC da carteira sai errado |
| Conferência com o ERP, diferença por indicador entre painel e origem | Não tem | Adequação funcional: o controller sabe se o número bate antes de levar à diretoria |
| Fluxo de caixa com cenário de atraso do repasse e exposição máxima | Não tem | Adequação funcional; é a pergunta do sócio sobre quanto dinheiro próprio a obra precisa |
| Alertas "Pede atenção" com a regra escrita (estoque que não acaba antes da entrega, custo acima do orçado, inadimplência alta, pago à frente do físico) | Só cartões; nada aponta o que exige ação | Capacidade de interação |
| Mapa de unidades, estoque por tipologia, VSO, simulação de vendas | Só o percentual vendido e o VGV em estoque | Adequação funcional |
| Vendas e repasse por banco, funil e leads por origem, vindos do CRM ligado ao contrato do ERP | Integração com CRM aparece só no catálogo | Adequação funcional, compatibilidade |
| Execução física comparada com o custo | Não tem | Adequação funcional |
| Inadimplência por faixa de atraso | Só citada na ajuda, "quando disponível no dado importado" | Adequação funcional. Ponto de atenção: a faixa de atraso vem hoje do Bulk (`defaulters-receivable-bills/by-aging`); sem Bulk, a 0040 (outro worktree, sem aplicar) traz as parcelas a receber pelo REST, de onde sai o vencido, mas a tela ainda não usa esse caminho |
| Visão por empresa: fontes e usos, DRE societária e mapa de contas | Não tem | Adequação funcional |
| Relatório da obra para imprimir ou salvar em PDF | Não tem | Capacidade de interação |
| Resumo semanal por e-mail com as obras de cada perfil | Sino de notificações, vazio | Capacidade de interação |
| Segurança: RLS por tenant e por obra, segundo fator para diretor e financeiro, gerente que só vê a própria obra, assistente com SQL validado por parser, somente leitura, com tempo limite, cota e registro de quem perguntou o quê | Perfis de usuário e trilha de auditoria de configuração, ainda vazia | Segurança e proteção |
| Telas abaixo de 0,5 s no banco local | Visão geral com 5,8 s só de API | Eficiência de desempenho |

### Ordem sugerida

Se o João quiser trazer parte disso, a ordem que mais rende com menos risco: primeiro as telas de custo e de receita sobre o Mapa Imobiliário, que já está carregado; depois o regime tributário e a central de ajuda; por último as simulações nomeadas e as despesas detalhadas, que esperam a definição do lucro líquido com o Braga.

A importação por planilha fica fora da sequência. Para a Verg, o caminho é cobrar a liberação das permissões da API, a começar por `real-estate-map`, que alimenta as telas de custo e de receita.

## Medições

Build de produção (`next build` e `next start`) contra o Supabase local, usuário diretor com segundo fator, tempo do documento inteiro pelo navegador. É o piso: no hospedado entra a rede até o Supabase em us-east-2.

| Tela | Tempo local |
| --- | --- |
| Visão geral (`/`) | 376 ms |
| Comparativo (`/obras`) | 431 ms |
| DRE de viabilidade (`/dre`) | 116 ms |
| Empresas (`/empresas`) | 61 ms |
| Mapa de unidades (`/unidades`) | 35 ms |
| Obra | 181 ms |
| DRE da obra | 60 ms |
| Imposto da obra | 73 ms |
| Estoque da obra | 38 ms |
| Vendas e repasse da obra | 79 ms |
| Unidades da obra | 65 ms |

Para comparar, a visão geral do portal levou 5,8 s só na chamada da API.

## O que foi verificado

Vitest com 584 testes passando, 6 deles novos (`testes/abas-obra.test.ts`). `tsc --noEmit` sem erro. ESLint sem aviso nos arquivos mexidos. Build de produção sem erro. No navegador: visão geral, comparativo, DRE, obra, imposto, estudo da DRE, vendas e repasse, a 1440 px e a 375 px; abas certas em cada tela; menu do celular abrindo e fechando; assistente com erro claro, foco e Esc.

Conferido contra o CLAUDE.md: nomes em português sem acento, comentário só onde explica o porquê, sem emoji, sem travessão, sem `console.log`, componente morto removido (`LinksObra.tsx`), nenhuma consulta nova em laço, nenhuma mudança em RLS, rota ou permissão (as abas só escondem o que cada tela já recusa).

As funcionalidades da seção de funcionalidades vieram da leitura das telas e da central de ajuda do portal, e a origem de cada dado foi conferida na referência da API do ERP (`.claude/skills/erp-origem-api`) e no `carregar_origem.py`. Nenhuma delas foi implementada nem testada.

Não verificado: o Playwright (o diretor de teste já tinha cadastrado o segundo fator, e o primeiro teste espera um diretor sem cadastro), o perfil gerente de obra no navegador (coberto pelo teste das abas), e qualquer tempo no hospedado.

## Ambiente que ficou montado

O Docker ficou aberto com o Supabase local deste worktree. O banco local foi recriado com `supabase db reset`, porque o volume antigo tinha as migrations até a 0039 sem a 0035, e a carga da demo falhava na função `staging.recarregar_saldo_contabil`. Só dados de teste foram apagados. `painel/.env.local` deste worktree aponta para o Supabase local e está fora do git. Os arquivos gerados pela carga em `dados/complementos` foram devolvidos ao estado do git.
