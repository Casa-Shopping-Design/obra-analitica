# Roteiro da demo de 16/10/2026

Quinze minutos, em https://obra-analitica.vercel.app. Os números abaixo saíram do Supabase local deste worktree em 06/10/2026, depois de `supabase db reset` (0001 a 0035) e da carga da demo, consultados com as mesmas views que as telas leem. O gerador tem semente fixa, então o hospedado mostra os mesmos valores, salvo o que depende da data do dia (vencidos e inadimplência), depois que a 0035 for aplicada e a Carga noturna rodar. Antes disso a margem na tendência aparece com 2,1% na Parque das Águas, e não 1,6%, e com 15,0% na Aurora, e não 14,8%. A diferença vem do terreno, dos projetos e das despesas, que só ganham realizado contábil com a 0035.

Quem conduz entra com dois logins, em duas janelas. O sócio usa o perfil leitura, sem segundo fator, e só consulta. O diretor passa pelo aplicativo autenticador e é o único que grava o estudo e a alíquota. Os dois veem as três obras: o diretor porque o perfil libera todas, o sócio porque as três estão vinculadas a ele.

## Sequência

| Minuto | Tela | Quem | O que mostrar |
| --- | --- | --- | --- |
| 0 a 1 | Entrada | Sócio | Login por convite, sem cadastro aberto. O rodapé traz a data da carga e o aviso de dados fictícios. |
| 1 a 3 | Visão geral (`/`) | Sócio | Faixa de resultado e faixa da carteira. |
| 3 a 6 | DRE de viabilidade (`/dre`) | Sócio | As três obras, margem no estudo, na tendência e o desvio, com a miniatura mês a mês. |
| 6 a 8 | DRE da Parque das Águas (`/obras/<id>/dre`) | Sócio | Linha a linha, onde a margem foi parar, e o gráfico da tendência. |
| 8 a 9 | Gestão de imposto da Aurora (`/obras/<id>/imposto`) | Sócio | Imposto já gerado e o que ainda vai gerar. |
| 9 a 11 | Assistente (`/assistente`) | Sócio | Três perguntas prontas. |
| 11 a 13 | Estudo da obra (`/obras/<id>/dre/estudo`) e Conferência com o ERP | Diretor | Gravação de uma versão nova do estudo e conferência dos números contra o ERP. |
| 13 a 15 | Perguntas | Todos | Respostas para o que está fora do escopo, na seção final. |

## O que dizer em cada tela

### Visão geral

Na faixa de resultado, a carteira das três obras soma R$ 73.763.733,23 de VGV bruto na tendência, com 55,9% vendido e POC de 87,6%. A margem operacional do estudo era 13,6% e a tendência está em 9,6%, 4,0 pontos abaixo. Em dinheiro, o lucro operacional cai de R$ 9.499.120,00 no estudo para R$ 6.812.814,86 na tendência. Custo apropriado de R$ 32.135.649,13 e recebimentos acumulados de R$ 15.476.562,68.

Na faixa da carteira: caixa atual de R$ -29.511.535,40, exposição máxima da carteira de R$ 32.785.238,34 em janeiro de 2027, resultado projetado de R$ 23.113.143,94 e R$ 758.426,94 vencidos dos compradores.

Frase de apoio: o cartão mostra o número, e o ícone ao lado explica de onde ele vem. Nada é digitado no painel; tudo sai da carga noturna do ERP.

### DRE de viabilidade

| Obra | Margem no estudo | Margem na tendência | Desvio |
| --- | --- | --- | --- |
| Residencial Aurora | 14,0% | 14,8% | 0,8 ponto acima |
| Torre Comercial Sul | 10,5% | 7,5% | 3,0 pontos abaixo |
| Parque das Águas | 14,0% | 1,6% | 12,3 pontos abaixo |

O ponto da tela é a Parque das Águas: a obra perdeu quase toda a margem do estudo e a miniatura mostra a queda mês a mês. Clicar no nome abre a DRE completa.

### DRE da Parque das Águas

O lucro operacional do estudo era R$ 3.350.000,00 e a tendência está em R$ 381.247,94, R$ 2.968.752,06 abaixo. As três linhas que mais pesam contra o estudo:

| Linha | Estudo | Tendência | Desvio |
| --- | --- | --- | --- |
| Construção | R$ 17.500.000,00 | R$ 19.578.085,64 | R$ 2.078.085,64 acima |
| VGV bruto | R$ 25.000.000,00 | R$ 24.175.347,49 | R$ 824.652,51 abaixo |
| Projetos | R$ 300.000,00 | R$ 375.000,00 | R$ 75.000,00 acima |

O terreno, os projetos, o licenciamento, a assistência técnica, os juros e as despesas mostram o realizado pelo saldo contábil por obra; a construção vem do orçamento e da medição do ERP. A coluna de fonte diz de onde veio cada linha.

No gráfico, a margem da tendência sai de 9,2% em novembro de 2025 e chega a 1,6% em setembro de 2026, contra a linha tracejada do estudo. A queda acelera a partir de maio. A visão geral já marcava esse alerta: a Parque pagou 18,3 pontos à frente do físico e estourou o orçamento da construção em R$ 2.078.085,64.

### Gestão de imposto

| Obra | Alíquota informada | Imposto a realizar |
| --- | --- | --- |
| Residencial Aurora | 4,00% | R$ 752.015,96 |
| Parque das Águas | 4,00% | R$ 714.167,70 |
| Torre Comercial Sul | 6,32% | R$ 60.117,31 |

Na Aurora, R$ 197.931,58 vêm do que já foi vendido e falta apropriar e R$ 554.084,38 do estoque ainda à venda. A alíquota é a informada pela construtora; o regime tributário de cada obra ainda não está no sistema (pergunta P8 ao Braga).

### Assistente

As três perguntas estão em `painel/lib/perguntas-prontas.ts` e aparecem para diretor, financeiro e leitura. Respostas no banco local:

1. "Qual obra perdeu mais margem contra o estudo?" Parque das Águas, de 14,0% para 1,6%; depois a Torre, de 10,5% para 7,5%; a Aurora ganhou 0,8 ponto.
2. "Em que linha a Parque das Águas mais desvia do estudo?" Construção (R$ 2.078.085,64 acima), VGV bruto (R$ 824.652,51 abaixo) e Projetos (R$ 75.000,00 acima). Bate com a tabela da DRE, e isso vale ser dito em voz alta.
3. "Qual a tendência do lucro de cada obra contra o estudo?" Parque R$ 381.247,94 contra R$ 3.350.000,00; Torre R$ 606.794,09 contra R$ 829.120,00; Aurora R$ 5.824.772,83 contra R$ 5.320.000,00.

A pergunta pronta roda uma consulta fixa e não depende do modelo de linguagem. A pergunta livre depende da `ASSISTENTE_CHAVE_ASSINATURA` na Vercel e no banco; se ela não estiver confirmada até a véspera, a demo fica só nas prontas.

### Diretor: estudo e conferência

Com o diretor, abrir o estudo da Torre Comercial Sul e mostrar que cada gravação cria uma versão nova, com quem gravou e quando. Não gravar valor diferente durante a demo sem rodar a carga depois, porque a série mensal da DRE só se refaz na carga. Em seguida, a Conferência com o ERP da mesma obra, que só diretor e financeiro abrem. Na janela do sócio, mostrar que o link do estudo não aparece e a conferência também não.

## Perguntas fora do escopo

**Onde agir agora.** A matriz por área (Comercial, Engenharia, Financeiro, Suprimentos, Tributos, Recebíveis) depende de a construtora definir o que vai em Orçado, Realizado e Projetado e a regra do status (pergunta P13). Com a resposta, são cerca de três horas de trabalho. Resposta curta: "Está desenhada; falta a regra de vocês para cada bolinha."

**Gestão de despesas.** Hoje o painel mostra tudo por obra. Título sem obra, como a despesa da sede, fica fora por desenho, para não distorcer a margem de nenhuma obra. Para entrar, precisamos saber se o que interessa é a despesa da obra, a da sede ou as duas, e se há rateio da sede (pergunta P14). Estimativa de 6 a 9 horas depois da resposta.

**Importação de dados.** A carga do ERP é automática, toda noite. O estudo de viabilidade é digitado na tela pelo diretor, uma versão por gravação, e isso cobre a demo. Importar planilha do estudo ou balancete depende de saber o que o usuário quer importar (pergunta P15). Estimativa de 6 horas.

Pergunta que pode aparecer sobre o realizado das linhas fora do orçamento: na demo ele vem de um saldo contábil sintético por obra. No piloto ele vem do balancete por centro de custo do ERP, que depende do pacote contratado e do plano de contas do cliente (pergunta P3).
