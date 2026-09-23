# obra-analitica

Ponto de partida do painel financeiro com assistente de IA para construtoras, alimentado pelo ERP de origem. Este repositório guarda a demo que será apresentada a João Braga em outubro de 2026 e serve de base para o MVP.

Leia `CONTEXTO.md` antes de qualquer coisa. Ele resume o que foi decidido, o que está aberto e onde estão os documentos completos.

## Estrutura

```
dados/            JSON sintéticos no formato dos endpoints do ERP de origem (gerados, não versionar os grandes)
scripts/          gerador de dados e carregador para o Supabase
supabase/         migrations (esquema, RLS, marts) e seed de usuários
lib/              catálogo de views e validador de SQL do assistente
docs/             referências aos documentos de escopo, apresentação e plano
painel/           (a criar no PT-01) Next.js com App Router
```

## Como começar

Ambiente Python e dados sintéticos:

```bash
python -m venv .venv && source .venv/bin/activate
pip install psycopg[binary] python-dotenv
python scripts/gerar_dados_demo.py          # escreve dados/*.json
cp .env.example .env                        # preencher DATABASE_URL (pooler em modo sessão) e TENANT_DEMO_ID
```

Banco no Supabase, com a CLI logada:

```bash
supabase link --project-ref <ref do projeto>
supabase db push                            # aplica supabase/migrations na ordem
supabase db push --include-seed             # grava o tenant e os três centros de custo
python scripts/carregar_demo.py             # grava em raw e recarrega o staging
```

No Dashboard do projeto:

1. Authentication, Users, Add user: criar `diretor@demo.com` e `gerente.aurora@demo.com` com "Auto Confirm User" marcado.
2. Authentication, Sign In / Providers, Email: desligar "Allow new users to sign up".
3. Configurações da Data API: acrescentar `app` e `marts` aos schemas expostos. `raw` e `staging` ficam de fora.

Vínculo dos usuários ao tenant (os UUIDs estão em Authentication, Users, e não vão para arquivo versionado):

```bash
python scripts/vincular_usuarios_demo.py --diretor <uuid do diretor> --gerente <uuid da gerente>
```

O diretor vê as três obras; a gerente vê só o Residencial Aurora.

## Documentos

| Documento | Uso |
| --- | --- |
| Escopo do MVP (Claude Doc) | arquitetura completa: ingestão, RLS, LGPD, RAG, cronograma de 16 semanas |
| Apresentação para João Braga (Claude Doc) | o que mostrar na reunião e o que pedir a ele |
| Plano de construção da demo (Claude Doc) | as 3 semanas de trabalho, telas, dados e roteiro |

Os links estão em `docs/README.md`. Os três podem ser exportados em PDF ou DOCX pelo próprio documento.
