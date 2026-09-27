# Contexto do projeto

Atualizado em 27/09/2026. Este arquivo é o resumo para retomar o trabalho em outra sessão.

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
- DRE gerencial, receitas, despesas, financiamento e planejamento (26/09/2026, implementado por multiagentes, sem commit): migrations 0007 (eventos financeiros: recebimentos e pagamentos um por linha, rateio entre obras com resíduo de centavo, centro "Despesas sem obra", data de referência no fuso de São Paulo), 0011 (categorias gerenciais, mapeamento de contas por tenant com auditoria, critério de reconhecimento, DRE, receitas, despesas), 0012 (financiamento por contrato, crédito à produção, medições e liberações como complemento manual auditado), 0013 (fluxo projetado, aporte, versões imutáveis de meta e projeção, simulação determinística, visão gerencial, pendências pós-entrega) e 0014 (políticas antigas com `(select app.tenant_atual())`). Contrato em `docs/financeiro/contrato_dados.md`. Receita e custo reconhecidos ficam indisponíveis até o financeiro validar o critério (padrão `nao_definido`; POC implementado e desligado). "Caixa gerado acumulado" é a projeção e "caixa realizado acumulado" só o realizado; nenhum dos dois é saldo bancário.
- Configuração por cliente (26/09/2026): regras e preferências em catálogo (`app.parametro`) com valor por construtora e por obra (obra vence construtora, que vence o padrão), códigos do ERP por cliente (`app.mapa_codigo_origem`: condição de pagamento, situação de unidade e de contrato), subcategorias e rótulos próprios, tela `/configuracoes`. Todo padrão reproduz o comportamento anterior. Contrato em `docs/financeiro/configuracao.md`. As perguntas financeiras em aberto viraram opções configuráveis; o piloto escolhe.
- O pedido de 26/09 ampliou o escopo: crédito associativo e medição do banco entram, como complemento manual, porque não há API de banco.
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

- Decisões financeiras do DRE e do planejamento (lista completa em `docs/financeiro/contrato_dados.md`, seção 10): critério de reconhecimento e base da fração vendida; plano de contas do piloto; terreno no POC; tratamento de distrato; retenção; se o caixa consolidado soma obras; números 0011 a 0014 (o plano reservava 0011 em diante para o PT-09, que passa a começar na 0015).
- Conversa com Braga no sábado 26/09 sobre porcentagens; antes disso enviar o documento e a planilha (compartilhar o documento, que é privado).
- Conferir o spread do cartão na fatura e ajustar na aba Premissas.
- Conversa com Lucas sobre a divisão.
- Construtora piloto com o ERP em nuvem e usuário de API.
- As 20 perguntas do assistente (vêm do Braga e do piloto).
- Conflito de interesse com o CVCRM: ler o contrato de trabalho antes de assinar sociedade.
- CNPJ: a sociedade com Lucas ainda não tem; definir quem assina.

- Rodar `scripts/sondar_origem.py` no terminal do Mac (a rede das sessões do Claude bloqueia a API do ERP) e depois `sanitizar_amostras.py`.
- Trocar o validador de SQL por parser (hoje é regex e deixa passar tabela depois de vírgula).
- Gerador: custo realizado está à frente da execução física nas três obras; decidir se ajusta.
- Exposição máxima só enxerga títulos já lançados; no ERP real o custo futuro sem título fica só no total (`custo_a_incorrer`). Decidir como distribuir por mês.
- Staging lê só `buildingsCosts[0]` do título a pagar: rateio entre obras vai inteiro para a primeira e título sem obra (despesa da empresa, devolução de distrato) some. Conferir com as amostras reais.
- Tirar `marts.consolidado_centro_custo` do catálogo do assistente (sobrepõe a posição financeira e ainda soma saldo de distrato).
- Gerador: orçamento sai com resíduo de ponto flutuante (17500000.000000001); arredondar.

## Links

- Telas da demo (canvas): https://claude.ai/artifact/SBVWLWvyW4FLDfg5kFZXqz (visão geral, obra, mapa de disponibilidade, assistente, login, paletas)
- Documento para o Braga: https://claude.ai/code/artifact/db85bf45-161e-434c-a663-a25b04b7b3bd
- Repositório: https://github.com/Casa-Shopping-Design/obra-analitica (transferido de joaocss/obra-analitica em 27/09/2026; o endereço antigo redireciona)

## Plano de implementação

`docs/plano_implementacao.md` (22/09/2026) é o plano em pacotes de trabalho PT-00 a PT-11 para execução por vários agentes, com números de migration reservados (0006 a 0010), premissas de segurança, observabilidade, engenharia, PAA, usabilidade e ISO 25010, cronograma até 19/02/2027, orçamento e conceitos a estudar. Foi escrito para um modelo executor menos capaz: qualquer agente lê `CLAUDE.md`, este arquivo e o plano antes de mexer em código.

## Infraestrutura (27/09/2026)

- GitHub: organização `Casa-Shopping-Design`, com o app do Claude instalado em todos os repositórios. Repositórios `obra-analitica` e `site-rag` (site, projeto à parte). Falta convidar os sócios, exigir 2FA e criar a regra da `main` (pull request obrigatório, sem force push).
- E-mail da empresa: `admcasadesign@proton.me`, só para cobrança e contato das contas. Cada sócio entra nos serviços com a própria conta. Senhas, códigos de 2FA e frases de recuperação no cofre "Casa Design – Infra" do Proton Pass, compartilhado com os sócios.
- Supabase: falta criar a organização Casa Shopping Design, transferir o projeto `obraanalitic` para ela e trocar a senha do banco.
- Vercel: só antes da demo de 16/10 (Team provavelmente exige plano pago; conferir o preço na hora).
- Sentry: `@sentry/nextjs` 11.0.0 no painel (commit ded705f), sem gravação de sessão e sem dado pessoal. O DSN vai em `painel/.env.local` e na Vercel (`NEXT_PUBLIC_SENTRY_DSN`), nunca no código. Conferir se o projeto do Sentry é da organização Casa Shopping Design e não da do Episteme.
- No Mac, o projeto fica em `~/Projetos/casa-shopping-design/obra-analitica`. O trabalho segue no Claude Code local, que não tem o bloqueio de rede das sessões na nuvem (dá para rodar `scripts/atualizar_documentacao_apis.py` e `scripts/sondar_origem.py`).

## Próxima sessão

Estado em 27/09/2026: todo o trabalho está na branch `claude/vibrant-cerf-dor0x6` (DRE, receitas, despesas, fluxo, planejamento, financiamento, configuração por cliente e Sentry), com 915 testes pgTAP e 278 vitest passando. Nenhuma migration da 0007 em diante foi aplicada no Supabase remoto. Próximos passos, nesta ordem: CI no GitHub Actions (lint, tsc, vitest, `supabase test db`); modelo de pull request e ajuste no `CLAUDE.md` permitindo que o Claude commite em branches `claude/*` e abra PR, com merge só por João; PR da `claude/vibrant-cerf-dor0x6` para a `main`, depois da `claude/pt-07` (validador do assistente, migration 0009; conferir se aceita as views e funções novas do catálogo); trazer à mão as mudanças de `CONTEXTO.md` da `claude/sharp-knuth-96f5h3`; raspar a documentação das APIs pelo Mac. Decisões pendentes em `docs/financeiro/contrato_dados.md`, seção 10, e a confirmação dos números 0011 a 0014 contra a reserva do PT-09.

Histórico do ambiente do Supabase (22/09/2026): Projeto Supabase `obraanalitic` (ref `ndgwcunpnxhkzapmmvsq`, sa-east-1, Postgres 17) criado em 22/09/2026; CLI logado e linkado; migrations 0001 a 0005 e o seed aplicados; `supabase/config.toml` criado com `app` e `marts` expostos (só local); `.env` com a string do pooler e a senha ainda como `SENHA_DO_BANCO`; `.venv` com psycopg. Falta o PT-00 do plano: senha no `.env`, dois usuários no Dashboard, cadastro livre desligado, schemas `app` e `marts` expostos no Dashboard, `carregar_demo.py` e o script de vínculo dos usuários. Depois, PT-01 (painel em `painel/`) e PT-04 (migration 0006) em paralelo.
