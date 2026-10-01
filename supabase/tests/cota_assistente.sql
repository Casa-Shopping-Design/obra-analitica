-- Cota do assistente: diretor e financeiro em aal1 não reservam nem concluem pergunta, gerente segue em aal1,
-- o custo gravado para no teto por pergunta e só quem reservou fecha a própria reserva, uma vez.
begin;
create extension if not exists pgtap with schema extensions;
select plan(24);

insert into app.tenant (id, razao_social) values
  ('0e000000-0000-4000-8000-0000000003c1', 'Construtora Cota');

insert into auth.users (id, email) values
  ('0a000000-0000-4000-8000-0000000d03c1', 'diretor.cota@teste.invalid'),
  ('0a000000-0000-4000-8000-0000000f03c1', 'financeiro.cota@teste.invalid'),
  ('0a000000-0000-4000-8000-0000000c03c1', 'gerente.cota@teste.invalid');

insert into app.usuario_tenant (user_id, tenant_id, perfil) values
  ('0a000000-0000-4000-8000-0000000d03c1', '0e000000-0000-4000-8000-0000000003c1', 'diretor'),
  ('0a000000-0000-4000-8000-0000000f03c1', '0e000000-0000-4000-8000-0000000003c1', 'financeiro'),
  ('0a000000-0000-4000-8000-0000000c03c1', '0e000000-0000-4000-8000-0000000003c1', 'gerente_obra');

-- Estrutura e permissões
select has_column('app', 'parametro_assistente', 'teto_por_pergunta_usd', 'parâmetro tem o teto por pergunta');
select is(
  (select teto_por_pergunta_usd from app.parametro_assistente),
  0.25::numeric,
  'teto por pergunta nasce em US$ 0,25'
);
select ok(
  (select bool_and(prosecdef and proconfig @> array['search_path=""']) from pg_proc
   where oid in ('app.reservar_pergunta(uuid, text)'::regprocedure,
                 'app.concluir_pergunta(bigint, text, text, text, integer, integer, integer, integer, numeric)'::regprocedure)),
  'reservar e concluir seguem security definer com search_path vazio'
);
select ok(
  not has_function_privilege('anon', 'app.reservar_pergunta(uuid, text)', 'execute')
  and not has_function_privilege('public', 'app.reservar_pergunta(uuid, text)', 'execute')
  and not has_function_privilege('anon', 'app.concluir_pergunta(bigint, text, text, text, integer, integer, integer, integer, numeric)', 'execute')
  and not has_function_privilege('public', 'app.concluir_pergunta(bigint, text, text, text, integer, integer, integer, integer, numeric)', 'execute'),
  'anônimo e public não reservam nem concluem'
);
select ok(
  has_function_privilege('authenticated', 'app.reservar_pergunta(uuid, text)', 'execute')
  and has_function_privilege('authenticated', 'app.concluir_pergunta(bigint, text, text, text, integer, integer, integer, integer, numeric)', 'execute'),
  'usuário logado reserva e conclui'
);

-- Gerente em aal1 reserva e conclui normalmente
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-0000000c03c1", "role": "authenticated"}', true);
set local role authenticated;
select lives_ok(
  $$select set_config('teste.gerente_1',
    app.reservar_pergunta('00000000-0000-4000-8000-0000000003c1', 'Quanto falta receber?')::text, true)$$,
  'gerente em aal1 reserva'
);
select lives_ok(
  format($$select app.concluir_pergunta(%s, null, null, 'erro', 1, 12, 100, 20, 0.01)$$,
    current_setting('teste.gerente_1')),
  'gerente em aal1 conclui'
);
select is(
  (select resultado from app.pergunta_assistente where id = current_setting('teste.gerente_1')::bigint),
  'erro',
  'conclusão da gerente grava o resultado'
);
select throws_ok(
  format($$select app.concluir_pergunta(%s, null, null, 'erro', null, null, null, null, 0.01)$$,
    current_setting('teste.gerente_1')),
  '42501',
  null,
  'reserva já concluída não é fechada de novo'
);

-- Custo acima do teto é gravado no teto; custo negativo é recusado
select set_config('teste.gerente_2',
  app.reservar_pergunta('00000000-0000-4000-8000-0000000003c2', 'Qual obra atrasou?')::text, true);
select throws_ok(
  format($$select app.concluir_pergunta(%s, null, null, 'erro', null, null, null, null, -5)$$,
    current_setting('teste.gerente_2')),
  '22023',
  'custo inválido',
  'custo negativo é recusado'
);
select lives_ok(
  format($$select app.concluir_pergunta(%s, null, null, 'erro', null, null, 100, 20, 1000)$$,
    current_setting('teste.gerente_2')),
  'custo acima do teto não impede a conclusão'
);
reset role;
select is(
  (select custo_estimado from app.pergunta_assistente where id = current_setting('teste.gerente_2')::bigint),
  0.25::numeric,
  'custo de US$ 1.000 é gravado no teto de US$ 0,25'
);
select is(
  (select sum(custo_estimado) from app.pergunta_assistente where tenant_id = '0e000000-0000-4000-8000-0000000003c1'),
  0.26::numeric,
  'gasto do dia soma o custo limitado, e não o informado'
);

-- Diretor em aal2 reserva; em aal1 não reserva nem conclui a própria reserva
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-0000000d03c1", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;
select lives_ok(
  $$select set_config('teste.diretor_1',
    app.reservar_pergunta('00000000-0000-4000-8000-0000000003c3', 'Qual a exposição máxima?')::text, true)$$,
  'diretor em aal2 reserva'
);
select throws_ok(
  format($$select app.concluir_pergunta(%s, null, null, 'erro', null, null, null, null, null)$$,
    current_setting('teste.gerente_2')),
  '42501',
  null,
  'diretor não conclui reserva de outro usuário'
);

reset role;
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-0000000d03c1", "role": "authenticated", "aal": "aal1"}', true);
set local role authenticated;
select throws_ok(
  $$select app.reservar_pergunta('00000000-0000-4000-8000-0000000003c4', 'Quanto entra no mês?')$$,
  '42501',
  'pergunta exige o segundo fator',
  'diretor em aal1 não reserva'
);
select throws_ok(
  format($$select app.concluir_pergunta(%s, null, null, 'erro', null, null, null, null, 0.25)$$,
    current_setting('teste.diretor_1')),
  '42501',
  'pergunta exige o segundo fator',
  'diretor em aal1 não conclui nem a própria reserva'
);

reset role;
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-0000000d03c1", "role": "authenticated"}', true);
set local role authenticated;
select throws_ok(
  $$select app.reservar_pergunta('00000000-0000-4000-8000-0000000003c5', 'Quanto entra no mês?')$$,
  '42501',
  'pergunta exige o segundo fator',
  'diretor sem o claim aal conta como aal1 e não reserva'
);

reset role;
select is(
  (select resultado from app.pergunta_assistente where id = current_setting('teste.diretor_1')::bigint),
  'pendente',
  'reserva do diretor segue aberta depois da tentativa em aal1'
);
select is(
  (select count(*) from app.pergunta_assistente where user_id = '0a000000-0000-4000-8000-0000000d03c1'),
  1::bigint,
  'tentativas do diretor em aal1 não gravam reserva'
);

select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-0000000d03c1", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;
select lives_ok(
  format($$select app.concluir_pergunta(%s, null, null, 'erro', 1, 9, 100, 20, 0.02)$$,
    current_setting('teste.diretor_1')),
  'diretor em aal2 conclui a própria reserva'
);

-- Financeiro segue a mesma regra do diretor
reset role;
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-0000000f03c1", "role": "authenticated", "aal": "aal1"}', true);
set local role authenticated;
select throws_ok(
  $$select app.reservar_pergunta('00000000-0000-4000-8000-0000000003c6', 'Qual o saldo do caixa?')$$,
  '42501',
  'pergunta exige o segundo fator',
  'financeiro em aal1 não reserva'
);

reset role;
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-0000000f03c1", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;
select lives_ok(
  $$select app.reservar_pergunta('00000000-0000-4000-8000-0000000003c7', 'Qual o saldo do caixa?')$$,
  'financeiro em aal2 reserva'
);

-- O teto é lido do parâmetro a cada conclusão
reset role;
update app.parametro_assistente set teto_por_pergunta_usd = 0.1;
select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-0000000c03c1", "role": "authenticated"}', true);
set local role authenticated;
select set_config('teste.gerente_3',
  app.reservar_pergunta('00000000-0000-4000-8000-0000000003c8', 'Quantas unidades vendidas?')::text, true);
select app.concluir_pergunta(current_setting('teste.gerente_3')::bigint, null, null, 'erro', null, null, null, null, 0.2);
reset role;
select is(
  (select custo_estimado from app.pergunta_assistente where id = current_setting('teste.gerente_3')::bigint),
  0.1::numeric,
  'teto alterado no parâmetro vale na conclusão seguinte'
);

select * from finish();
rollback;
