-- As views de estoque, carteira e alertas da migration 0024 pelo caminho do assistente (executar_consulta):
-- rodam com o RLS de quem pergunta, o gerente vê só a obra dele e o diretor sem segundo fator não vê nada.
-- Cria os próprios dados; um título a pagar sem orçamento em cada obra dispara o alerta de estouro.
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

insert into app.tenant (id, razao_social) values
  ('0e000000-0000-4000-8000-0000000000a5', 'Construtora Assistente Estoque');

insert into app.centro_custo (id, tenant_id, id_origem, nome) values
  ('0c000000-0000-4000-8000-0000000000a5', '0e000000-0000-4000-8000-0000000000a5', 991, 'Obra Leste'),
  ('0c000000-0000-4000-8000-0000000000a6', '0e000000-0000-4000-8000-0000000000a5', 992, 'Obra Oeste');

insert into auth.users (id, email) values
  ('0a000000-0000-4000-8000-00000000d1a5', 'diretor.estoque@teste.invalid'),
  ('0a000000-0000-4000-8000-00000000c1a5', 'gerente.estoque@teste.invalid');

insert into app.usuario_tenant (user_id, tenant_id, perfil) values
  ('0a000000-0000-4000-8000-00000000d1a5', '0e000000-0000-4000-8000-0000000000a5', 'diretor'),
  ('0a000000-0000-4000-8000-00000000c1a5', '0e000000-0000-4000-8000-0000000000a5', 'gerente_obra');

insert into app.usuario_centro_custo (user_id, tenant_id, centro_custo_id) values
  ('0a000000-0000-4000-8000-00000000c1a5', '0e000000-0000-4000-8000-0000000000a5', '0c000000-0000-4000-8000-0000000000a5');

insert into staging.titulo_pagar (tenant_id, centro_custo_id, id_origem, vencimento, valor_original, saldo) values
  ('0e000000-0000-4000-8000-0000000000a5', '0c000000-0000-4000-8000-0000000000a5', 70, current_date + 40, 1000, 1000),
  ('0e000000-0000-4000-8000-0000000000a5', '0c000000-0000-4000-8000-0000000000a6', 71, current_date + 40, 500, 500);

insert into staging.rateio_titulo (tenant_id, titulo_id_origem, centro_custo_id, valor, fracao) values
  ('0e000000-0000-4000-8000-0000000000a5', 70, '0c000000-0000-4000-8000-0000000000a5', 1000, 1),
  ('0e000000-0000-4000-8000-0000000000a5', 71, '0c000000-0000-4000-8000-0000000000a6', 500, 1);

-- Chave só deste teste; a de produção é gravada por João e nunca entra no repositório.
delete from app.chave_assinatura_consulta;
insert into app.chave_assinatura_consulta (chave) values ('chave-local-do-teste-estoque-000000000');

-- Desde a 0025 cada execução grava na reserva pendente de quem pergunta e deixa a transação só de leitura.
-- O bloco desfaz as duas coisas, e a mesma reserva serve a todas as consultas de cada usuário.
with gerente as (
  insert into app.pergunta_assistente (user_id, tenant_id, id_requisicao, pergunta, resultado)
  values ('0a000000-0000-4000-8000-00000000c1a5', '0e000000-0000-4000-8000-0000000000a5', gen_random_uuid(), 'estoque', 'pendente')
  returning id
)
select set_config('teste.pergunta_gerente', id::text, true) from gerente;
with diretor as (
  insert into app.pergunta_assistente (user_id, tenant_id, id_requisicao, pergunta, resultado)
  values ('0a000000-0000-4000-8000-00000000d1a5', '0e000000-0000-4000-8000-0000000000a5', gen_random_uuid(), 'estoque', 'pendente')
  returning id
)
select set_config('teste.pergunta_diretor', id::text, true) from diretor;

create function pg_temp.consultar(p_sql text) returns jsonb language plpgsql as $$
declare
  linhas jsonb;
begin
  begin
    linhas := marts.executar_consulta(
      current_setting('teste.pergunta_atual')::bigint,
      p_sql,
      encode(extensions.hmac(p_sql, 'chave-local-do-teste-estoque-000000000', 'sha256'), 'hex'));
    raise exception using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  return linhas;
end;
$$;
grant execute on function pg_temp.consultar(text) to authenticated;

-- Estrutura: views que o catálogo do assistente passou a listar

select is(
  (select count(*)::integer from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'marts'
      and c.relname in ('estoque_obra', 'estoque_tipologia', 'posicao_carteira', 'alertas_obra')
      and c.reloptions @> array['security_invoker=true']),
  4,
  'as quatro views rodam como quem consulta'
);
select ok(
  has_table_privilege('authenticated', 'marts.estoque_obra', 'select')
  and has_table_privilege('authenticated', 'marts.estoque_tipologia', 'select')
  and has_table_privilege('authenticated', 'marts.posicao_carteira', 'select')
  and has_table_privilege('authenticated', 'marts.alertas_obra', 'select'),
  'usuário logado lê as quatro views'
);
select ok(
  not has_table_privilege('anon', 'marts.estoque_obra', 'select')
  and not has_table_privilege('anon', 'marts.estoque_tipologia', 'select')
  and not has_table_privilege('anon', 'marts.posicao_carteira', 'select')
  and not has_table_privilege('anon', 'marts.alertas_obra', 'select'),
  'anônimo não lê nenhuma delas'
);

-- Gerente da Obra Leste

select set_config('request.jwt.claims', '{"sub": "0a000000-0000-4000-8000-00000000c1a5", "role": "authenticated"}', true);
select set_config('teste.pergunta_atual', current_setting('teste.pergunta_gerente'), true);
set local role authenticated;

select is(
  pg_temp.consultar('select obra from marts.estoque_obra order by obra'),
  '[{"obra": "Obra Leste"}]'::jsonb,
  'gerente vê o estoque só da obra dele'
);
select is(
  pg_temp.consultar('select obras from marts.posicao_carteira'),
  '[{"obras": 1}]'::jsonb,
  'gerente vê a carteira do tamanho da obra dele'
);
select is(
  pg_temp.consultar('select obra, tipo, valor from marts.alertas_obra where tipo = ''estouro_orcamento'''),
  '[{"obra": "Obra Leste", "tipo": "estouro_orcamento", "valor": 1000.00}]'::jsonb,
  'gerente vê só o alerta da obra dele'
);
select is(
  pg_temp.consultar(
    'select count(*) as linhas from marts.estoque_tipologia e join app.centro_custo c on c.id = e.centro_custo_id where c.nome = ''Obra Oeste'''),
  '[{"linhas": 0}]'::jsonb,
  'gerente não vê o estoque por tipologia de outra obra'
);

-- Diretor com segundo fator

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000d1a5", "role": "authenticated", "aal": "aal2"}', true);
select set_config('teste.pergunta_atual', current_setting('teste.pergunta_diretor'), true);
set local role authenticated;

select is(
  pg_temp.consultar('select obras, exposicao_maxima from marts.posicao_carteira'),
  '[{"obras": 2, "exposicao_maxima": 1500.00}]'::jsonb,
  'diretor vê a carteira com as duas obras'
);
select is(
  pg_temp.consultar('select obra, valor from marts.alertas_obra where tipo = ''estouro_orcamento'' order by obra'),
  '[{"obra": "Obra Leste", "valor": 1000.00}, {"obra": "Obra Oeste", "valor": 500.00}]'::jsonb,
  'diretor vê o alerta de estouro das duas obras'
);
select is(
  pg_temp.consultar('select obra, unidades_estoque, meses_para_vender_estoque from marts.estoque_obra order by obra'),
  '[{"obra": "Obra Leste", "unidades_estoque": 0, "meses_para_vender_estoque": 0},
    {"obra": "Obra Oeste", "unidades_estoque": 0, "meses_para_vender_estoque": 0}]'::jsonb,
  'obra sem estoque aparece com zero unidades e zero meses'
);

-- Diretor só com senha

reset role;
select set_config('request.jwt.claims',
  '{"sub": "0a000000-0000-4000-8000-00000000d1a5", "role": "authenticated", "aal": "aal1"}', true);
set local role authenticated;

select throws_ok(
  $$select pg_temp.consultar('select obras from marts.posicao_carteira')$$,
  '42501',
  'pergunta exige o segundo fator',
  'diretor sem segundo fator não recebe a carteira pelo assistente'
);
select throws_ok(
  $$select pg_temp.consultar('select obra from marts.alertas_obra')$$,
  '42501',
  'pergunta exige o segundo fator',
  'diretor sem segundo fator não recebe alertas pelo assistente'
);

select * from finish();
rollback;
