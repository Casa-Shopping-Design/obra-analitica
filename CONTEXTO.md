# Contexto do projeto

Atualizado em 03/10/2026. Este arquivo é o resumo para retomar o trabalho em outra sessão.

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
- CRM de vendas como segunda origem (28/09/2026): sem conflito de interesse. O projeto usa a API contratada pelo cliente para entregar análise que o CRM não oferece.
- O mapa das telas do ERP foi levantado numa base de produto com login e não entra no repositório. Fica na skill pessoal `erp-origem-interface`, em `~/.claude/skills`.
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

- Conversa com Braga no sábado 26/09 sobre porcentagens; antes disso enviar o documento e a planilha (compartilhar o documento, que é privado).
- Conferir o spread do cartão na fatura e ajustar na aba Premissas.
- Conversa com Lucas sobre a divisão.
- Construtora piloto com o ERP em nuvem e usuário de API.
- As 20 perguntas do assistente (vêm do Braga e do piloto).
- CNPJ: a sociedade com Lucas ainda não tem; definir quem assina.

- Rodar `scripts/sondar_origem.py` no terminal do Mac (a rede das sessões do Claude bloqueia a API do ERP) e depois `sanitizar_amostras.py`.
- Gerador: desde 30/09 só a Parque das Águas paga à frente da medição (18 pontos), para a demo ter um alerta de execução. Na Aurora a medição segue a curva do custo, e `staging.item_orcamento.pct_concluido` dela ficou em 55% contra 78% medido; nenhuma tela lê essa coluna.
- Exposição máxima só enxerga títulos já lançados; no ERP real o custo futuro sem título fica só no total (`custo_a_incorrer`). Decidir como distribuir por mês.
- Staging lê só `buildingsCosts[0]` do título a pagar: rateio entre obras vai inteiro para a primeira e título sem obra (despesa da empresa, devolução de distrato) some. Conferir com as amostras reais.

- Migrations 0025 a 0029 (01/10/2026), sem aplicar em projeto hospedado: 0025 grava no banco o SQL executado pelo assistente e exige assinatura no SQL gerado (ADR 0014; publicar junto com o painel novo, senão o assistente para); 0026 repasse por banco e leads por origem; 0027 comparativo entre obras em `/obras`; 0028 não existe (o resumo semanal não precisou); 0029 corrige o alerta de estoque para obra sem data de entrega.
- Resumo semanal por e-mail (`scripts/enviar_resumo_semanal.py`, workflow `resumo_semanal.yml`): falta conta no Resend, domínio com SPF, DKIM e DMARC, e os segredos no GitHub. Decidir com os sócios se o e-mail de diretor e financeiro leva valores em real, já que sai da barreira do segundo fator.

## Links

- Telas da demo (canvas): https://claude.ai/artifact/SBVWLWvyW4FLDfg5kFZXqz (visão geral, obra, mapa de disponibilidade, assistente, login, paletas)
- Documento para o Braga: https://claude.ai/code/artifact/db85bf45-161e-434c-a663-a25b04b7b3bd
- Repositório: https://github.com/Casa-Shopping-Design/obra-analitica

## Plano de implementação

`docs/plano_implementacao.md` (22/09/2026) é o plano em pacotes de trabalho PT-00 a PT-11 para execução por vários agentes, com números de migration reservados (0006 a 0010), premissas de segurança, observabilidade, engenharia, PAA, usabilidade e ISO 25010, cronograma até 19/02/2027, orçamento e conceitos a estudar. Foi escrito para um modelo executor menos capaz: qualquer agente lê `CLAUDE.md`, este arquivo e o plano antes de mexer em código.

## Aplicativo nas lojas

`docs/plano_aplicativo_loja.md` (02/10/2026): primeira versão para App Store e Google Play em Expo, com agentes A0 a A10 e migrations 0030 e 0031 reservadas. Antes de começar, João fecha a tecnologia (D1) e o tipo de conta de desenvolvedor (D2). A recomendação é pedir já o D-U-N-S e abrir as contas de empresa, e deixar o código para depois da entrega 2.

## Próxima sessão

Plano de 28/09/2026 para carga real do ERP, fila de webhooks e CRM como segunda origem: `docs/plano_origens.md` (grafo N1 a N8, migrations 0016 a 0019). As skills `erp-origem-api` e `crm-vendas-api` ficam em `.claude/skills/`.


Situação em 03/10/2026. A `main` está no merge do PR 5 (01/10), com as migrations 0001 a 0029 (não existe 0028). O PT-07 entrou pelo PR 2.

O projeto Supabase oficial é o `xwqwjawlbzvqpkxtqfld`, na organização Casa Design. Em 01/10 ele tinha as migrations 0001 a 0024 e o seed, sem carga e sem usuários. Os projetos `rxbhxtbjxqlisbrfcbtt` e `obraanalitic` (`ndgwcunpnxhkzapmmvsq`, conta prof.joaosena) não são o oficial: nada se aplica neles.

Falta, na ordem de `docs/operacao/publicar-demo.md`:
- Dashboard do projeto oficial: senha nova do banco, schemas expostos (`public`, `app`, `marts`), TOTP, hook `app.claims_jwt` e cadastro livre desligado.
- Migrations 0025 a 0029 e painel novo publicados no mesmo dia, senão o assistente para.
- Carga da demo, chave de assinatura do assistente e variáveis na Vercel (`casa-design/obra-analitica`); depois, Site URL e Redirect URLs no Supabase.
- Usuários criados e vinculados. Entrar com `gerente.aurora@demo.com` e ver uma obra só.
- Trocar a senha do banco do projeto antigo, que apareceu em print.
- Demo em 16/10/2026.
