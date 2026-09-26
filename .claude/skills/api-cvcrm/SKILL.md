---
name: api-cvcrm
description: Mapa das APIs do CV CRM (CVCRM) com cada endpoint, parâmetro e campo de resposta, gerado da documentação oficial em desenvolvedor.cvcrm.com.br. Use sempre que precisar saber se o CV tem um dado ou endpoint (leads, reservas, unidades, empreendimentos, clientes, corretores, comissões, contratos, atendimentos, CVDW), como autenticar, qual o limite de requisições, ou quando for planejar trazer dados do CV para o painel. Consulte antes de afirmar que um endpoint existe.
---

# APIs do CV CRM

Referência gerada a partir de https://desenvolvedor.cvcrm.com.br/ por `scripts/atualizar_documentacao_apis.py`. Para atualizar, use a skill `atualizar-docs-apis`.

## Como consultar

1. `referencia/INDICE.md` lista as APIs e os guias encontrados.
2. `referencia/apis/<nome>.md` traz, por operação, os parâmetros, o corpo aceito e os campos da resposta achatados em caminhos como `dados[].unidade.situacao`.
3. `referencia/guias/` guarda as páginas do portal em Markdown (autenticação, permissões, integração com ERP). O portal é ReadMe e publica essas páginas pelo `llms.txt`.
4. Para achar um campo: `grep -rn "idreserva" .claude/skills/api-cvcrm/referencia/`.
5. `referencia/MUDANCAS.md` diz o que mudou em cada raspagem.

Se `referencia/apis/` estiver vazia, a raspagem ainda não rodou. Nesse caso vale só o resumo abaixo, e qualquer endpoint precisa ser conferido na documentação antes de entrar em código.

## Resumo conhecido

Vem da experiência de integração, não da raspagem. A referência gerada prevalece quando divergir.

- Base: `https://{dominio_do_cliente}.cvcrm.com.br/api/`. Os caminhos antigos `/api/cvio/...` estão sendo substituídos por `/api/v1/{modulo}/{recurso}`, por exemplo `/api/cvio/reserva` virou `/api/v1/comercial/reservas`. Código novo usa o padrão v1.
- Autenticação por cabeçalhos `email` e `token`, ou `Authorization: Bearer` nas rotas mais novas. O token é gerado no Painel do Gestor, em Usuários Administrativos, e pode ter validade. "Permissão de acesso desabilitada" quer dizer que o perfil do usuário não libera aquele endpoint.
- Limite: 200 requisições por minuto nas APIs REST e 20 por minuto no CVDW. Estouro devolve 429 e bloqueia por um minuto. Chamada em laço leva pausa e não roda em paralelo.
- CVDW é a API analítica (leads, reservas, comissões, simulações, atendimentos, assistências, pré-cadastros), contratada à parte.
- Módulos: Prospectar (leads, agendamentos), Vender (reservas, unidades, mapa de disponibilidade, empreendimentos e blocos), Gerenciar (clientes, corretores, contratos, extrato financeiro, boletos) e Relacionar (atendimentos, comunicador, pós-venda).
- O CVIO (`https://{dominio}.cvcrm.com.br/cvio`) registra as requisições de entrada e saída por 30 dias.

## Regras do repositório ao usar esta referência

- O CV seria uma segunda origem. Ele entraria pela mesma ingestão em `raw` e `staging`, com nomes neutros, sem tocar em marts, painel ou assistente.
- O limite do Sienge é compartilhado com a integração CV da construtora. Carga que chama os dois precisa somar o consumo.
- CPF, renda, score e dados bancários ficam fora do MVP mesmo quando o endpoint os devolve.
