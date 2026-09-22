# Contexto do projeto

Atualizado em 22/09/2026. Este arquivo é o resumo para retomar o trabalho em outra sessão.

## O que é

Camada analítica em cima do ERP de origem para gestores de construtoras: consolidado por obra (centro de custo), fluxo de caixa separando receita direta de repasse bancário, estoque com VSO e ponto de equilíbrio, e assistente de IA que responde em português usando só o banco (texto para SQL sobre views aprovadas, executado com o JWT do usuário para o RLS valer).

## Pessoas e papéis

- João Cosme: tecnologia, desenvolvimento, 20 h por semana.
- João Braga: parceiro comercial em negociação, mais de 40 anos no mercado da construção, rede de contatos com construtoras. Ainda não viu a proposta.
- Lucas Almeida Pinto: sócio de João na startup de IA/RAG. Precisa concordar com a divisão desse projeto antes de fechar com Braga.

## Decisões tomadas

- Nomenclatura neutra: nada no sistema leva o nome do ERP (tabelas, colunas, schemas, arquivos, variáveis, env). Chave externa é `id_origem`, conta no ERP é `conta_origem`, URL da API vem de `ORIGEM_URL_BASE`. Nome de campo do payload bruto fica como a API devolve, só dentro de `raw` e das funções de staging.
- Stack: Supabase (Postgres, Auth, RLS, pgvector) e Next.js na Vercel. Worker de carga em contêiner só no MVP; na demo é script manual.
- ELT: Bulk Data e REST do ERP de origem gravados brutos em `raw`, transformados por SQL em `staging` e `marts`. Carga diária de madrugada. Painel e IA nunca chamam o ERP ao vivo.
- Multi-tenant por linha (pool com RLS), política única por tabela com `tenant_id` e `centro_custo_id in obras_permitidas()`. Nunca duas políticas permissivas separadas (elas se combinam com OR).
- Identidade via claims do JWT (`tenant_id`, `perfil`), não `current_setting`.
- Regra inicial: parcela com condição `FI` é repasse; o resto é receita direta. Ajustar com o controller do piloto.
- LGPD: CPF, renda, score e dados bancários não são carregados no MVP. Mascaramento no banco, não no front.
- Assistente: sem embeddings de tabela. Catálogo semântico de views no prompt, validador de SQL, execução com JWT do usuário, resposta só com números retornados.
- Demo: três obras fictícias (Residencial Aurora, Parque das Águas, Torre Comercial Sul), dados sintéticos no formato do ERP de origem, dois logins (diretor e gerente da Aurora). Prazo 16/10/2026.
- MVP: 16 semanas a 20 h por semana. O prazo de 6 semanas de outro documento foi descartado.

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
- Hora de referência de João: R$ 80 a 90.

## Em aberto

- Reunião com Braga (semana de 28/09) e reação dele ao modelo.
- Conversa com Lucas sobre a divisão.
- Construtora piloto com o ERP em nuvem e usuário de API.
- As 20 perguntas do assistente (vêm do Braga e do piloto).
- Conflito de interesse com o CVCRM: ler o contrato de trabalho antes de assinar sociedade.
- CNPJ: a sociedade com Lucas ainda não tem; definir quem assina.

## Próxima sessão

Começar pela semana 1 do plano da demo: rodar `gerar_dados_demo.py`, conferir totais, criar o projeto Supabase e aplicar as migrations.
