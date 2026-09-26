---
name: atualizar-docs-apis
description: Rebaixa a documentação das APIs do Sienge e do CV CRM, regrava a referência das skills api-sienge e api-cvcrm e diz o que mudou desde a última vez. Use quando João pedir para ver se a documentação mudou, atualizar o mapa das APIs, raspar de novo, ou quando um endpoint devolver campo ou erro que a referência não prevê.
---

# Atualizar a documentação das APIs

## Rodar

```bash
python scripts/atualizar_documentacao_apis.py                 # as duas fontes
python scripts/atualizar_documentacao_apis.py --fonte sienge  # uma só
python scripts/atualizar_documentacao_apis.py --navegador     # portal que só monta a página com JavaScript
```

O script procura sozinho as especificações OpenAPI (HTML, scripts, configuração do Swagger UI, páginas filhas) e o `llms.txt` do portal. Grava em `.claude/skills/api-<fonte>/referencia/` e guarda as especificações brutas em `dados/brutos/documentacao/`, que fica fora do git. Só usa a biblioteca padrão e o PyYAML; o modo `--navegador` pede `pip install playwright && playwright install chromium`.

Quando não acha nada, sai com código 1 e não mexe na referência anterior.

## Quando a rede barra

A sessão na nuvem só alcança os domínios liberados no ambiente. Se o script disser que o índice respondeu 0 ou 403:

1. Pedir a João para liberar `api.sienge.com.br` e `desenvolvedor.cvcrm.com.br` em Network access do ambiente e rodar de novo, ou
2. João roda o mesmo comando no Mac, que tem acesso, e commita a pasta `referencia/`, ou
3. Se o portal recusar robô até no Mac: João abre a documentação no navegador, salva os arquivos de especificação (o link do JSON ou YAML que aparece no topo do Swagger UI) e as páginas `.md` numa pasta e roda `python scripts/atualizar_documentacao_apis.py --fonte sienge --pasta-local <pasta>`.

Não tentar contornar o bloqueio por espelho, cache ou outro domínio.

## Depois de rodar

1. Ler a seção mais recente de `referencia/MUDANCAS.md` de cada fonte.
2. `git diff --stat .claude/skills/` para ver o tamanho da mudança.
3. Para cada item marcado "usado pelo projeto", procurar o campo ou caminho em `supabase/migrations/`, `scripts/` e `painel/` e dizer o que quebra ou precisa de migration nova.
4. Se mudou base, autenticação ou limite (aparece nos guias ou nos servidores), atualizar a seção de resumo do `SKILL.md` da fonte e o `CONTEXTO.md`.
5. Entregar a João o resumo e os comandos de commit. Claude não commita.

Na primeira raspagem, conferir também a lista `caminhos_usados` em `scripts/documentacao_apis/fontes.py` contra os caminhos reais do índice gerado.
