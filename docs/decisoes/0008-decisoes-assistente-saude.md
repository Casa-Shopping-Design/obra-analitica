# 0008 Decisões 3 a 6 da revisão de 28/09: assistente e rota de saúde

**Contexto.** A integração das branches pt-07, pt-10 e pt-08 deixou quatro decisões abertas (docs/relatorios/revisao-pacotes-noite.md), fechadas por João em 28/09/2026 com os padrões recomendados. As migrations 0013 e 0014 das branches viraram 0020 e 0021, porque 0016 a 0019 já estavam na main; nenhuma das duas tinha sido aplicada em projeto hospedado.

**Decisão 3.** O `statement_timeout` de 8 s no papel `authenticated` fica como teto de proteção de todas as telas, e `marts.executar_consulta` repete o limite com `set local` e guarda os claims e o papel antes de abrir o cursor, recusando com 42501 se mudaram durante a consulta. A execução assinada por HMAC permanece.

**Decisão 4.** O limite de 30 perguntas por hora e o teto diário de US$ 5 por construtora (tabela `app.parametro_assistente`, linha única) são conferidos e reservados numa função só, `app.reservar_pergunta`, sob bloqueio consultivo por usuário; a rota reserva antes de chamar o modelo e fecha com `app.concluir_pergunta`. O usuário não insere nem lê a tabela por inteiro: o grant é por coluna, e `sql_gerado` e `sql_executado` saem só por `app.sql_das_perguntas`, que devolve vazio a quem não é diretor.

**Decisão 5.** A rota de saúde lê `public.ultima_carga()`, executável por `anon`; a 0021 não concede `usage` em `app` ao anônimo. O `usage` que a 0016 já dá por causa do webhook continua, e os testes `carga_execucao.sql` e `eventos_origem.sql` exigem que o anônimo execute só `app.registrar_evento_origem` nesse schema. Sem o segredo `MONITOR_TOKEN` no cabeçalho `x-monitor-token`, `/api/saude` responde só `ok` e `idade_horas`.

**Decisão 6.** O aviso "Dados da demo" volta em `CarimboCarga`, ligado por `NEXT_PUBLIC_MOSTRAR_AVISO_DEMO=1` só no projeto da demo, com o texto em `mensagens.ts`.
