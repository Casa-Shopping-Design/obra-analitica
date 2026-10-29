-- Exclusão de cliente (migration 0042): toda tabela com tenant_id aponta para app.tenant em cascata,
-- app.excluir_tenant apaga um tenant inativo sem deixar linha em relação nenhuma e sem tocar no outro
-- tenant nem em auth.users, e só o dono do banco a executa. Cria os próprios dados.
begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

-- Relações com tenant_id, lidas do catálogo, para a conferência não depender de lista escrita à mão.
create function pg_temp.relacoes_com_tenant() returns table (nspname text, relname text) language sql as $$
  select n.nspname::text, c.relname::text
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  join pg_attribute a on a.attrelid = c.oid and a.attname = 'tenant_id' and not a.attisdropped
  where c.relkind in ('r', 'p') and n.nspname in ('app', 'raw', 'staging', 'marts', 'public')
$$;

create function pg_temp.linhas_do_tenant(p_tenant uuid) returns bigint language plpgsql as $$
declare
  relacao record;
  linhas bigint;
  total bigint := 0;
begin
  for relacao in select * from pg_temp.relacoes_com_tenant() loop
    execute format('select count(*) from %I.%I where tenant_id = $1', relacao.nspname, relacao.relname)
      into linhas using p_tenant;
    total := total + linhas;
  end loop;
  return total;
end $$;

create function pg_temp.relacoes_com_linhas(p_tenant uuid) returns bigint language plpgsql as $$
declare
  relacao record;
  linhas bigint;
  total bigint := 0;
begin
  for relacao in select * from pg_temp.relacoes_com_tenant() loop
    execute format('select count(*) from %I.%I where tenant_id = $1', relacao.nspname, relacao.relname)
      into linhas using p_tenant;
    if linhas > 0 then
      total := total + 1;
    end if;
  end loop;
  return total;
end $$;

create function pg_temp.travas_da_recarga(p_tenant uuid) returns bigint language sql as $$
  select count(*)
  from pg_locks l, hashtextextended('recarga:' || p_tenant::text, 0) as chave
  where l.locktype = 'advisory' and l.pid = pg_backend_pid() and l.objsubid = 1
    and l.classid::bigint = (chave >> 32) & 4294967295
    and l.objid::bigint = chave & 4294967295
$$;

-- Tenant A será apagado; tenant B fica e prova que a exclusão não vaza para o vizinho.
insert into app.tenant (id, razao_social) values
  ('0e000000-0000-4000-8000-0000000000d1', 'Construtora Exclusão A'),
  ('0e000000-0000-4000-8000-0000000000d2', 'Construtora Exclusão B');
insert into app.centro_custo (id, tenant_id, id_origem, nome) values
  ('0c000000-0000-4000-8000-0000000000d1', '0e000000-0000-4000-8000-0000000000d1', 701, 'Obra A'),
  ('0c000000-0000-4000-8000-0000000000d2', '0e000000-0000-4000-8000-0000000000d2', 701, 'Obra B');
insert into auth.users (id, email) values
  ('0a000000-0000-4000-8000-0000000000d1', 'diretor.exclusao.a@teste.invalid'),
  ('0a000000-0000-4000-8000-0000000000d2', 'diretor.exclusao.b@teste.invalid');
insert into app.usuario_tenant (user_id, tenant_id, perfil) values
  ('0a000000-0000-4000-8000-0000000000d1', '0e000000-0000-4000-8000-0000000000d1', 'diretor'),
  ('0a000000-0000-4000-8000-0000000000d2', '0e000000-0000-4000-8000-0000000000d2', 'diretor');

-- Uma linha em cada relação de carga e de staging, para os dois tenants.
insert into raw.registro (tenant_id, endpoint, payload, hash_registro, chave_origem)
select t, 'units', '{"id": 1}', 'h' || t::text, '1'
from unnest(array['0e000000-0000-4000-8000-0000000000d1', '0e000000-0000-4000-8000-0000000000d2']::uuid[]) as t;
insert into app.marca_carga (tenant_id, endpoint, ultima_referencia)
select t, 'units', current_date
from unnest(array['0e000000-0000-4000-8000-0000000000d1', '0e000000-0000-4000-8000-0000000000d2']::uuid[]) as t;
insert into app.carga_execucao (tenant_id, endpoint, terminado_em, situacao)
select t, 'staging', now(), 'ok'
from unnest(array['0e000000-0000-4000-8000-0000000000d1', '0e000000-0000-4000-8000-0000000000d2']::uuid[]) as t;

with par as (
  select * from (values
    ('0e000000-0000-4000-8000-0000000000d1'::uuid, '0c000000-0000-4000-8000-0000000000d1'::uuid),
    ('0e000000-0000-4000-8000-0000000000d2'::uuid, '0c000000-0000-4000-8000-0000000000d2'::uuid)) as v(tenant, obra)
),
i1 as (insert into staging.unidade (tenant_id, centro_custo_id, id_origem, nome) select tenant, obra, 1, 'Unidade 1' from par),
i2 as (insert into staging.contrato_venda (tenant_id, centro_custo_id, id_origem) select tenant, obra, 1 from par),
i3 as (insert into staging.parcela_receber (tenant_id, centro_custo_id, id_origem, contrato_id_origem, vencimento, valor_original)
       select tenant, obra, 1, 1, '2026-01-10', 1000 from par),
i4 as (insert into staging.titulo_pagar (tenant_id, centro_custo_id, id_origem, vencimento) select tenant, obra, 1, '2026-01-10' from par),
i5 as (insert into staging.item_orcamento (tenant_id, centro_custo_id, codigo) select tenant, obra, '01' from par),
i6 as (insert into staging.indice_valor (tenant_id, indexador_id_origem, referencia, valor) select tenant, 1, '2026-01-01', 1.5 from par),
i7 as (insert into staging.tabela_preco (tenant_id, centro_custo_id, id_origem, versao, vigencia_inicio) select tenant, obra, 1, 1, '2026-01-01' from par),
i8 as (insert into staging.tabela_preco_unidade (tenant_id, centro_custo_id, tabela_id_origem, versao, unidade_id_origem, quantidade_indexada)
       select tenant, obra, 1, 1, 1, 10 from par),
i9 as (insert into staging.unidade_valor (tenant_id, centro_custo_id, unidade_id_origem) select tenant, obra, 1 from par),
i10 as (insert into staging.recebimento (tenant_id, centro_custo_id, contrato_id_origem, parcela_id_origem, sequencia, data_recebimento, valor)
        select tenant, obra, 1, 1, 1, '2026-01-10', 100 from par),
i11 as (insert into staging.pagamento (tenant_id, centro_custo_id, titulo_id_origem, sequencia, data_pagamento, valor)
        select tenant, obra, 1, 1, '2026-01-10', 100 from par),
i12 as (insert into staging.rateio_titulo (tenant_id, titulo_id_origem, centro_custo_id, valor, fracao) select tenant, 1, obra, 100, 1 from par),
i13 as (insert into staging.reserva (tenant_id, centro_custo_id, id_origem) select tenant, obra, 1 from par),
i14 as (insert into staging.repasse (tenant_id, centro_custo_id, id_origem) select tenant, obra, 1 from par),
i15 as (insert into staging.lead_diario (tenant_id, centro_custo_id, dia, origem, midia, situacao, motivo_cancelamento, leads)
        select tenant, obra, '2026-01-10', 'site', 'busca', 'ativo', '', 3 from par),
i16 as (insert into staging.mapa_imobiliario_mensal (tenant_id, centro_custo_id, competencia) select tenant, obra, '2026-01-01' from par),
i17 as (insert into staging.medicao_obra (tenant_id, centro_custo_id, numero_medicao, unidade_construtiva_id, tarefa_id, data_medicao)
        select tenant, obra, 1, 1, 1, '2026-01-10' from par),
i18 as (insert into staging.inadimplencia (tenant_id, centro_custo_id, titulo_id_origem, data_posicao, dias_atraso, parcelas_atrasadas, valor_atrasado)
        select tenant, obra, 1, '2026-01-10', 30, 1, 500 from par),
i19 as (insert into staging.saldo_contabil_mensal (tenant_id, centro_custo_id, conta, competencia, saldo_final)
        select tenant, obra, '1.1', '2026-01-01', 10 from par)
select count(*) from par;

insert into app.estudo_viabilidade (id, tenant_id, centro_custo_id, versao, data_base, situacao) values
  ('0d000000-0000-4000-8000-0000000000d1', '0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1', 1, '2026-01-01', 'vigente'),
  ('0d000000-0000-4000-8000-0000000000d2', '0e000000-0000-4000-8000-0000000000d2', '0c000000-0000-4000-8000-0000000000d2', 1, '2026-01-01', 'vigente');
insert into app.estudo_viabilidade_linha (estudo_id, tenant_id, centro_custo_id, linha, valor) values
  ('0d000000-0000-4000-8000-0000000000d1', '0e000000-0000-4000-8000-0000000000d1', '0c000000-0000-4000-8000-0000000000d1', 'vgv_bruto', 100),
  ('0d000000-0000-4000-8000-0000000000d2', '0e000000-0000-4000-8000-0000000000d2', '0c000000-0000-4000-8000-0000000000d2', 'vgv_bruto', 100);

create temp table antes as
select pg_temp.linhas_do_tenant('0e000000-0000-4000-8000-0000000000d2') as linhas_b,
       pg_temp.relacoes_com_linhas('0e000000-0000-4000-8000-0000000000d1') as relacoes_a;

-- Catálogo
select is(
  (select count(*) from pg_temp.relacoes_com_tenant() r
   where not exists (
     select 1 from pg_constraint f
     join pg_attribute a on a.attrelid = f.conrelid and a.attname = 'tenant_id'
     where f.conrelid = (quote_ident(r.nspname) || '.' || quote_ident(r.relname))::regclass
       and f.contype = 'f' and f.confrelid = 'app.tenant'::regclass and f.confdeltype = 'c'
       and f.conkey = array[a.attnum])),
  0::bigint,
  'toda tabela com tenant_id em app, raw, staging, marts e public aponta para app.tenant com on delete cascade'
);
select cmp_ok((select relacoes_a from antes), '>=', 26::bigint,
  'o tenant de teste tem linha em pelo menos 26 relações (as 19 de staging, a linha do estudo e as de app e raw)');

-- Guardas
select throws_like(
  $$select app.excluir_tenant('0e000000-0000-4000-8000-0000000000d1')$$,
  '%marque como inativo antes de excluir%',
  'tenant ativo não é excluído: inativar primeiro é o segundo fator da operação'
);
select throws_like(
  $$select app.excluir_tenant('0e000000-0000-4000-8000-0000000000ff')$$,
  '%não existe%',
  'tenant inexistente dá erro em vez de devolver relatório vazio'
);
select is(pg_temp.linhas_do_tenant('0e000000-0000-4000-8000-0000000000d1'),
  (select linhas_b from antes), 'a tentativa recusada não apagou nada do tenant A');

-- Exclusão
update app.tenant set status = 'inativo' where id = '0e000000-0000-4000-8000-0000000000d1';
create temp table exclusao as select app.excluir_tenant('0e000000-0000-4000-8000-0000000000d1') as resultado;

select is((select resultado->'apagadas'->>'staging.unidade' from exclusao), '1',
  'o relatório conta a linha apagada de staging.unidade');
select is((select resultado->'apagadas'->>'app.estudo_viabilidade_linha' from exclusao), '1',
  'o relatório conta a linha do estudo de viabilidade');
select is((select count(*) from exclusao, jsonb_object_keys(resultado->'apagadas')),
  (select relacoes_a + 1 from antes),
  'o relatório lista toda relação que tinha linha do tenant, mais o próprio app.tenant');
select is((select resultado->'fora_da_funcao'->>'auth.users' from exclusao), '1',
  'o relatório diz quantas contas de login ficaram fora da função');
select is(pg_temp.linhas_do_tenant('0e000000-0000-4000-8000-0000000000d1'), 0::bigint,
  'nenhuma relação com tenant_id guarda linha do tenant apagado');
select is((select count(*) from app.tenant where id = '0e000000-0000-4000-8000-0000000000d1'), 0::bigint,
  'o tenant saiu de app.tenant');
select is(pg_temp.linhas_do_tenant('0e000000-0000-4000-8000-0000000000d2'), (select linhas_b from antes),
  'o tenant B continua com as mesmas linhas');
select is((select count(*) from auth.users where id = '0a000000-0000-4000-8000-0000000000d1'), 1::bigint,
  'a conta de login continua em auth.users, só sem vínculo');
select is(pg_temp.travas_da_recarga('0e000000-0000-4000-8000-0000000000d1'), 1::bigint,
  'a exclusão prende a mesma trava das recargas do tenant');

-- Privilégios
select ok(
  not has_function_privilege('anon', 'app.excluir_tenant(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'app.excluir_tenant(uuid)', 'execute')
    and not has_function_privilege('public', 'app.excluir_tenant(uuid)', 'execute'),
  'app.excluir_tenant está revogada de anon, authenticated e public'
);
set local role authenticated;
select throws_ok(
  $$select app.excluir_tenant('0e000000-0000-4000-8000-0000000000d2')$$,
  '42501', 'permission denied for function excluir_tenant',
  'authenticated não executa app.excluir_tenant'
);
reset role;
set local role anon;
select throws_ok(
  $$select app.excluir_tenant('0e000000-0000-4000-8000-0000000000d2')$$,
  '42501', 'permission denied for function excluir_tenant',
  'anon não executa app.excluir_tenant'
);
reset role;

select * from finish();
rollback;
