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
app/              (a criar) Next.js 15 com App Router
```

## Como começar

```bash
python -m venv .venv && source .venv/bin/activate
pip install psycopg[binary] python-dotenv
python scripts/gerar_dados_demo.py          # escreve dados/*.json
cp .env.example .env                        # preencher DATABASE_URL do Supabase
# aplicar supabase/migrations/*.sql e supabase/seed.sql no SQL editor, na ordem
python scripts/carregar_demo.py             # grava em raw e roda staging/marts
npx create-next-app@latest app --ts --tailwind --app --src-dir=false
```

## Documentos

| Documento | Uso |
| --- | --- |
| Escopo do MVP (Claude Doc) | arquitetura completa: ingestão, RLS, LGPD, RAG, cronograma de 16 semanas |
| Apresentação para João Braga (Claude Doc) | o que mostrar na reunião e o que pedir a ele |
| Plano de construção da demo (Claude Doc) | as 3 semanas de trabalho, telas, dados e roteiro |

Os links estão em `docs/README.md`. Os três podem ser exportados em PDF ou DOCX pelo próprio documento.
