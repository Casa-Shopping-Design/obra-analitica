# 0014 Trilha do assistente com o SQL que rodou

**Contexto.** A decisão 0012 deixou um ponto aberto. `app.concluir_pergunta` recebia `p_sql_gerado` e `p_sql_executado` de quem chamava e é executável por `authenticated`, então um usuário logado podia reservar uma pergunta, chamar a função direto pela API e gravar na trilha um SQL que nunca rodou. A rastreabilidade de quem perguntou o quê dependia de a rota do painel ser a única a chamar a função.

**Decisão.** A migration 0025 tira os dois textos da escolha do cliente.

O `sql_executado` passa a ser gravado pelo banco. `marts.executar_consulta` ganhou o parâmetro `p_id_pergunta` e, depois de conferir a assinatura HMAC, chama `app.registrar_sql_executado`, que grava o texto na reserva pendente do próprio usuário (`auth.uid()`), uma vez só, e só então a transação vira somente leitura. A função nova é `security definer` com `search_path` vazio e confere de novo a assinatura e o segundo fator, porque precisa ser executável por `authenticated` (executar_consulta roda como o usuário). Chamada direta só grava SQL que o servidor assinou. A versão antiga de `executar_consulta`, sem id, foi removida.

O `sql_gerado` é a saída do modelo e só existe no servidor. A rota assina `sql_gerado:<id da pergunta>:<texto>` com a mesma chave das consultas e manda a assinatura no lugar do antigo `p_sql_executado`. `concluir_pergunta` recusa com 42501 texto sem assinatura válida. O prefixo impede que essa assinatura sirva em `executar_consulta`, e o id impede reaproveitá-la em outra pergunta. Texto vazio dispensa assinatura e fica nulo na trilha.

A conclusão também confere o resultado contra a execução: `ok` exige `sql_executado` gravado, e `recusada` exige que nada tenha rodado. Pergunta recusada pelo validador nunca executa, então fica com o `sql_gerado` assinado e sem `sql_executado`. A assinatura antiga de `concluir_pergunta` foi removida para não ficarem duas.

**Consequência.** Um usuário que chama as funções direto não consegue pôr na trilha SQL que o servidor não produziu, nem marcar como `ok` uma pergunta que não rodou. O teste `supabase/tests/auditoria_assistente.sql` cobre essas tentativas.

Ficam limites. Quando a consulta falha no banco (tempo esgotado, erro de execução), o PostgREST desfaz a transação inteira e a gravação do `sql_executado` vai junto; a pergunta fecha como `erro` só com o `sql_gerado`, e quem audita refaz o texto executado passando o gerado pelo validador. `linhas_devolvidas`, `duracao_ms`, tokens e custo continuam vindo de quem chama (o custo com o teto da 0012), porque a transação já está somente leitura quando o banco conhece o número de linhas. O usuário ainda pode fechar a própria reserva como `erro` sem SQL antes da rota, mas aí perde a resposta e a pergunta continua registrada. Tudo depende da chave de assinatura ficar só no servidor: com ela vazada, o cliente volta a escrever o que quiser.

Como `executar_consulta` grava na reserva, cada execução precisa de uma pergunta pendente do próprio usuário, e uma transação comporta uma execução só. A rota já faz uma por requisição. Os testes pgTAP que executam várias consultas na mesma transação passam por um bloco que desfaz a gravação e o modo somente leitura a cada chamada.
