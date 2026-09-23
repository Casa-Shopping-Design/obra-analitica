# Contexto do projeto

Atualizado em 23/09/2026. Este arquivo é o resumo para retomar o trabalho em outra sessão.

## O que é

Camada analítica em cima do ERP de origem para gestores de construtoras: consolidado por obra (centro de custo), fluxo de caixa separando receita direta de repasse bancário, estoque com VSO e ponto de equilíbrio, e assistente de IA que responde em português usando só o banco (texto para SQL sobre views aprovadas, executado com o JWT do usuário para o RLS valer).

## Pessoas e papéis

- João Cosme: tecnologia, desenvolvimento, 20 h por semana.
- João Braga: parceiro comercial em negociação, mais de 40 anos no mercado da construção, rede de contatos com construtoras. Ainda não viu a proposta.
- Lucas Almeida Pinto: sócio de João na startup de IA/RAG. Precisa concordar com a divisão desse projeto antes de fechar com Braga.

## Decisões tomadas

- Nomenclatura neutra: nada no sistema leva o nome do ERP (tabelas, colunas, schemas, arquivos, variáveis, env). Chave externa é `id_origem`, conta no ERP é `conta_origem`, URL da API vem de `ORIGEM_URL_BASE`. Nome de campo do payload bruto fica como a API devolve, só dentro de `raw` e das funções de staging.
- Stack: Supabase (Postgres, Auth, RLS, pgvector) e Next.js na Vercel. Carga noturna proposta no GitHub Actions (cota gratuita), no lugar do contêiner; falta João confirmar. E-mails de convite e senha pelo Resend (plano gratuito).
- ELT: Bulk Data e REST do ERP de origem gravados brutos em `raw`, transformados por SQL em `staging` e `marts`. Carga diária de madrugada. Painel e IA nunca chamam o ERP ao vivo.
- Multi-tenant por linha (pool com RLS), política única por tabela com `tenant_id` e `centro_custo_id in obras_permitidas()`. Nunca duas políticas permissivas separadas (elas se combinam com OR).
- Identidade via claims do JWT (`tenant_id`, `perfil`), não `current_setting`.
- Regra inicial: parcela com condição `FI` é repasse; o resto é receita direta. Ajustar com o controller do piloto.
- LGPD: CPF, renda, score e dados bancários não são carregados no MVP. Mascaramento no banco, não no front.
- Assistente: sem embeddings de tabela. Catálogo semântico de views no prompt, validador de SQL, execução com JWT do usuário, resposta só com números retornados.
- Demo: três obras fictícias (Residencial Aurora, Parque das Águas, Torre Comercial Sul), dados sintéticos no formato do ERP de origem, dois logins (diretor e gerente da Aurora). Prazo 16/10/2026.
- MVP: 16 semanas a 20 h por semana, a partir de 19/10/2026, em duas entregas. Entrega 1 até 18/12/2026: carga real, visão geral, fluxo de caixa, obras e login. Entrega 2 até 05/02/2027 (19/02 com recesso de duas semanas): estoque com preços, assistente e uso acompanhado. Braga ouviu "3 meses"; a entrega 1 cobre isso.
- Login: só por convite, perfis diretor, financeiro e gerente de obra, segundo fator por app autenticador para diretor e financeiro.
- Preço das unidades: tabela guarda quantidade indexada (INCC); valor = quantidade x índice do mês; vendida vale o contrato. View `marts.mapa_unidades`.
- Situação da unidade no ERP: D disponível, C reservada, P proposta, V/O/G vendida, R reserva técnica e demais fora de venda.
- Visual: paleta tijolo (menu vinho, fundo rosado), nada de creme ou azul de IA. Verde entra, grafite sai, vermelho vivo só em alerta.
- Entradas e saídas por obra (migration 0005): `marts.posicao_financeira_obra` separa direto do comprador e repasse do banco (recebido, a receber, vencido), estoque a preço de hoje, pago, a pagar, orçamento sem título, estouro, caixa atual, exposição máxima (dinheiro próprio no pior mês) e resultado. `marts.fluxo_caixa_mensal` foi recriada com realizado pela data do pagamento e saldo acumulado; o cenário desloca só o repasse pendente. Saldo projetado conservador: a receber vencido fica fora, a pagar vencido entra.
- Proposta do MVP para o Braga (23/09/2026, link abaixo): desembolso de R$ 7.260,50 a R$ 7.321,00 nos quatro meses (4 x R$ 1.800 de remuneração, mais R$ 60,50 a R$ 121,00 de infraestrutura, que é só a API de IA em dezembro e janeiro com 10% de reserva). Todo o resto fica no plano gratuito até o primeiro cliente. Com cliente em produção, cerca de R$ 418,58 por mês, com o gatilho de cada item na tabela da proposta. O aporte em horas aparece no documento: R$ 37.866,67 nos quatro meses, mais R$ 9.100 da demo.
- Indicadores por entrega (detalhe na proposta). Entrega 1, só Sienge: caixa realizado e previsto, maior aporte, direto x repasse, inadimplência por faixa, VGV/andamento/margem, cobertura do orçamento. Entrega 2: compromissos não pagos (contratos de empreiteiro e pedidos de compra), custo realizado x orçado, VSO, estoque por tipologia, distratos por motivo. Se o piloto usar o CVCRM: tempo de repasse por etapa, funil e desconto x tabela. O Bulk do Sienge e a base analítica do CVCRM (CVDW, contratada à parte) aceitam cerca de 20 chamadas por minuto. O inventário de campos saiu de cópias das especificações feitas por terceiros (`deco-cx/apps` no GitHub para o Sienge, `manzano/cvdw-cli` para o CVDW) e precisa ser conferido na documentação oficial.
- Padrão de qualidade do painel, escrito na proposta: número conferido contra o relatório do Sienge, todo total abre nas parcelas, data da carga visível e aviso de carga falha, menos de 2 s, leitura em 10 s, funciona no celular e imprime, definição de cada termo ao passar o mouse.
- Módulo para escritórios contábeis: etapa opcional, fora do MVP, só depois de conversar com o escritório do piloto. Estimativa preliminar de 60 a 100 horas. Antes dele, `app.tenant_atual()` precisa deixar de escolher um tenant com `limit 1`, porque um contador atende vários clientes.
- Medição de obra: fica depois do MVP. Três medições diferentes: avanço físico do cronograma (planejamento do Sienge), medição de empreiteiro (saída) e medição do banco (entrada no crédito associativo e no plano empresário; no repasse na chave, a medição muda a data do repasse e das parcelas de chaves). O cenário de atraso passa a sair do ritmo real da obra. Estimativa de 35 a 55 horas para o cronograma e as medições do Sienge.
- Medição do banco: não há API da Caixa nem dos bancos privados. O financeiro anexa o PDF do RAE, o sistema sugere percentual acumulado, data da vistoria e valor liberado, e o número só vale depois que uma pessoa confirma. O crédito no movimento bancário do Sienge é ligado ao RAE. Pelo menos 5% ficam retidos até o habite-se, então a liberação trava em 95%. No associativo da Caixa, a liberação dos financiamentos PF também depende das vendas contratadas com o banco. Open Finance talvez traga as datas de desembolso do plano empresário, sem percentual medido. Estimativa de 20 a 30 horas, mais 10 a 15 para a leitura automática do PDF. Falta um RAE real do piloto para modelar os campos.
- Parecer sobre os relatórios de validação de 22 e 23/09: achados 4.1 e 4.2 (realizado pela data do pagamento, cenário só no repasse) resolvidos na 0005; 4.4 (cobertura do orçamento) resolvido na 0006; 4.3 (VSO), 4.5 (listas do ERP lidas só no primeiro elemento) e 4.6 (validador com regex) continuam abertos, nos PT-06, PT-05 e PT-07. A entrega pequena que mais reduz incerteza é uma obra real conferida contra o relatório do ERP.
- Tela da obra (protótipo, 23/09/2026): estoque mostrado em valores, não só em quantidade. Vendidas pelo valor do contrato, em negociação (reservadas e propostas) e disponíveis a preço de hoje, fora de venda com o motivo (hoje só "reserva técnica", que é a situação R do Sienge; motivo detalhado depende do cadastro do piloto). Nova meta de vendas por mês para cobrir o custo até as chaves: falta vender = custo orçado menos VGV contratado, dividido pelos meses até as chaves, refeito todo mês (o que não vendeu passa para os meses seguintes), com o equivalente em unidades pelo ticket médio disponível a preço de hoje. Na implementação (PT-06), a meta precisa ser configurável por obra, fora da tela inicial: automática por padrão; o cliente pode trocar o horizonte (chaves, habite-se ou data própria), a base (custo orçado ou outra) ou digitar as metas mês a mês numa tabela própria por centro de custo e mês, com RLS.
- Premissas do repositório em `CLAUDE.md` (nomes em português, humanizer, PAA, ISO 25010, segurança Supabase/Vercel). Claude não faz commit.

## ERP de origem: o que foi verificado

- Base URL REST: `https://{tenant}.sienge.com.br/sienge-api/public/api/v1/` ou via gateway `https://api.sienge.com.br/{tenant}/public/api/v1/`. Bulk: `.../bulk-data/v1/`.
- Endpoints usados: REST `companies`, `cost-centers`, `enterprises`, `units`, `customers`; Bulk `income`, `outcome`, `sales`, `defaulters-receivable-bills`, `bank-movement`, `building-cost-estimation-items`, `customer-extract-history`.
- Bulk aceita `_async=true`, chunks e webhook de conclusão. Exige permissão "Massive" no usuário de API.
- Limite relatado por terceiros: 200 requisições por minuto por conta, compartilhado com outras integrações (CV CRM incluído). 429 ao estourar. REST pagina em 200 registros.
- Campos que resolvem a separação direta x repasse: `paymentConditions[].conditionType` no `sales` e `paymentTerm` no `income`; `financialInstitutionNumber` e `financialInstitutionDate` marcam repasse.
- Documentação oficial: https://api.sienge.com.br/docs/ (bloqueia leitura automática; abrir no navegador).

## Negociação

- Cliente disse que R$ 10 mil por mês está fora da realidade.
- Proposta atual: sociedade em torno do produto. Participação de 30% a 40% para o lado técnico, mensalidade mínima de R$ 3.000 mais infra repassada sem margem (US$ 90 a 165 por mês no piloto), metas comerciais para Braga e vesting para os dois.
- Com Lucas: sugestão de dividir a participação (por exemplo 27% João, 8% sociedade) e a mensalidade ir para João como remuneração das horas. Ainda não conversado.
- A parceria é com a empresa de João Cosme, não com ele como pessoa física (razão social ainda não definida no documento).
- Hora de desenvolvimento de João: R$ 130 (era R$ 180 até 22/09/2026). Remuneração que ele cobra: R$ 1.800 por mês (era R$ 1.700); o restante das horas é aporte (R$ 9.466,67 por mês). A planilha ainda está com os valores antigos; para bater, alterar as duas células da aba Premissas.
- Relatório orçamentário atualizado com os valores novos, quatro meses (out/2026 a jan/2027) e cronograma de custos que só entram com cliente em produção: `docs/plano_implementacao.md`, seção 7.
- Planilha `negocio/investimento_mvp_obra_analitica.xlsx` (fora do git), conferida centavo a centavo com os valores antigos: custo mensal com uma construtora R$ 2.118,58 (infra R$ 418,58 + remuneração R$ 1.700); investimento até o fim do MVP R$ 70.271,10 (aporte em horas R$ 61.600, remuneração R$ 6.800, infra R$ 1.871,10). Dólar efetivo R$ 5,50 (PTAX 5,11 + spread 4% estimado + IOF 3,5%).
- Fase mobile fora do total: já existe um Mac (Xcode só roda em macOS); Apple US$ 99 por ano, Google Play US$ 25 uma vez; Apple exige D-U-N-S para conta de empresa.

## Em aberto

- Conversa com Braga no sábado 26/09 sobre porcentagens e sobre quem arca com o desembolso do MVP. Antes disso, enviar a proposta do MVP, a planilha e o documento técnico. A proposta é privada: compartilhar pelo menu Share antes de mandar o link, e o protótipo das telas também.
- As quatro parcelas de R$ 1.800 vão de outubro a janeiro, mas a entrega 2 é em 19/02: as semanas de fevereiro ficam sem remuneração. Combinar com o Braga.
- Perguntar ao piloto: usa CVCRM e tem a base analítica (CVDW)? Qual modalidade de financiamento cada obra usa? O cronograma é mantido no Sienge com avanço lançado todo mês? Pedir um RAE recente e o contrato com o banco.
- Conferir o spread do cartão na fatura e ajustar na aba Premissas.
- Conversa com Lucas sobre a divisão.
- Construtora piloto com o ERP em nuvem e usuário de API.
- As 20 perguntas do assistente (vêm do Braga e do piloto).
- Conflito de interesse com o CVCRM: ler o contrato de trabalho antes de assinar sociedade. Vale também para usar a API do CVCRM no produto.
- CNPJ: a sociedade com Lucas ainda não tem; definir quem assina.

- Rodar `scripts/sondar_origem.py` no terminal do Mac (a rede das sessões do Claude bloqueia a API do ERP) e depois `sanitizar_amostras.py`.
- Trocar o validador de SQL por parser (hoje é regex e deixa passar tabela depois de vírgula).
- Gerador: custo realizado está à frente da execução física nas três obras; decidir se ajusta.
- Exposição máxima só enxerga títulos já lançados; no ERP real o custo futuro sem título fica só no total (`custo_a_incorrer`). Decidir como distribuir por mês.
- Staging lê só `buildingsCosts[0]` do título a pagar: rateio entre obras vai inteiro para a primeira e título sem obra (despesa da empresa, devolução de distrato) some. Conferir com as amostras reais.

## Links

- Telas da demo (canvas): https://claude.ai/artifact/SBVWLWvyW4FLDfg5kFZXqz (visão geral, obra, mapa de disponibilidade, assistente, login, paletas)
- Documento para o Braga (versão anterior): https://claude.ai/code/artifact/db85bf45-161e-434c-a663-a25b04b7b3bd
- Proposta do MVP (23/09/2026): https://claude.ai/code/artifact/71ab7d32-152a-4a4b-b10a-dc2d193fa16e
- Repositório: https://github.com/joaocss/obra-analitica

## Plano de implementação

`docs/plano_implementacao.md` (22/09/2026) é o plano em pacotes de trabalho PT-00 a PT-11 para execução por vários agentes, com números de migration reservados (0006 a 0010), premissas de segurança, observabilidade, engenharia, PAA, usabilidade e ISO 25010, cronograma até 19/02/2027, orçamento e conceitos a estudar. Foi escrito para um modelo executor menos capaz: qualquer agente lê `CLAUDE.md`, este arquivo e o plano antes de mexer em código.

## Próxima sessão

Projeto Supabase `obraanalitic` (ref `ndgwcunpnxhkzapmmvsq`, sa-east-1, Postgres 17) criado em 22/09/2026; CLI logado e linkado; `supabase/config.toml` com `app` e `marts` expostos (só local); `.venv` com psycopg. No repositório já estão `scripts/vincular_usuarios_demo.py` e o PT-04 (migration 0006, teste `supabase/tests/isolamento_perfis.sql`, catálogo limpo, orçamento arredondado, ADR 0001). Falta João confirmar no remoto: senha no `.env`, dois usuários no Dashboard, cadastro livre desligado, `app` e `marts` expostos, `carregar_demo.py`, vínculo dos usuários, `supabase db push` da 0006 e o hook `app.claims_jwt` ligado. Depois, PT-01 (painel em `painel/`), com a demo em 16/10.
