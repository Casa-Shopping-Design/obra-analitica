-- Exclusão de cliente. As tabelas de staging nasceram com tenant_id sem chave estrangeira (0002, 0004,
-- 0012, 0018, 0019 e 0035), e app.estudo_viabilidade_linha também: apagar o tenant deixava o dado delas
-- órfão no banco e no backup. Lista conferida contra o catálogo do Supabase local em 28/10/2026, e a
-- conferência fica no fim desta migration para tabela nova não escapar.

-- O que já está órfão sai antes da chave entrar (tenants de teste apagados à mão no banco local).
do $$
declare
  relacao text;
begin
  foreach relacao in array array[
    'staging.unidade', 'staging.contrato_venda', 'staging.parcela_receber', 'staging.titulo_pagar',
    'staging.item_orcamento',
    'staging.indice_valor', 'staging.tabela_preco', 'staging.tabela_preco_unidade', 'staging.unidade_valor',
    'staging.recebimento', 'staging.pagamento', 'staging.rateio_titulo',
    'staging.reserva', 'staging.repasse', 'staging.lead_diario',
    'staging.mapa_imobiliario_mensal', 'staging.medicao_obra', 'staging.inadimplencia',
    'staging.saldo_contabil_mensal',
    'app.estudo_viabilidade_linha'
  ] loop
    execute format('delete from %s t where not exists (select 1 from app.tenant x where x.id = t.tenant_id)', relacao);
    execute format('alter table %s add constraint %I foreign key (tenant_id) references app.tenant(id) on delete cascade',
                   relacao, split_part(relacao, '.', 2) || '_tenant_fk');
  end loop;
end $$;

-- Toda tabela com tenant_id aponta para app.tenant em cascata. Falha aqui é tabela esquecida.
do $$
declare
  faltando text;
begin
  select string_agg(n.nspname || '.' || c.relname, ', ' order by n.nspname, c.relname) into faltando
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  join pg_attribute a on a.attrelid = c.oid and a.attname = 'tenant_id' and not a.attisdropped
  where c.relkind in ('r', 'p') and n.nspname in ('app', 'raw', 'staging', 'marts', 'public')
    and not exists (
      select 1 from pg_constraint f
      where f.conrelid = c.oid and f.contype = 'f' and f.confrelid = 'app.tenant'::regclass
        and f.confdeltype = 'c' and f.conkey = array[a.attnum]);
  if faltando is not null then
    raise exception 'tabela com tenant_id sem chave estrangeira em cascata para app.tenant: %', faltando;
  end if;
end $$;

-- Apaga um cliente inteiro: o tenant e, pela cascata, tudo que tem tenant_id em app, raw e staging. Só aceita
-- tenant com status 'inativo', para a exclusão ser sempre o segundo passo depois de parar a carga, e toma a
-- trava das recargas, para não correr junto com uma carga do mesmo tenant. Não mexe em auth.users: a conta de
-- login é da pessoa, pode estar vinculada a outro tenant, e sai pelo Dashboard ou pela API de admin. Devolve
-- o que apagou, por relação, e o que ficou de fora. Só o dono do banco (carregador e operador) executa.
-- O(r) consultas para r relações com tenant_id (cerca de 40), cada uma pelo índice que começa em tenant_id.
create function app.excluir_tenant(p_tenant uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_status text;
  v_relacao record;
  v_linhas bigint;
  v_apagadas jsonb := '{}'::jsonb;
  v_usuarios bigint;
begin
  select status into v_status from app.tenant where id = p_tenant;
  if v_status is null then
    raise exception 'tenant % não existe', p_tenant;
  end if;
  if v_status <> 'inativo' then
    raise exception 'tenant % está com status %; marque como inativo antes de excluir', p_tenant, v_status;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('recarga:' || p_tenant::text, 0));

  select count(*) into v_usuarios from app.usuario_tenant where tenant_id = p_tenant;

  for v_relacao in
    select n.nspname, c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    join pg_attribute a on a.attrelid = c.oid and a.attname = 'tenant_id' and not a.attisdropped
    where c.relkind in ('r', 'p') and n.nspname in ('app', 'raw', 'staging', 'marts', 'public')
    order by n.nspname, c.relname
  loop
    execute format('select count(*) from %I.%I where tenant_id = $1', v_relacao.nspname, v_relacao.relname)
      into v_linhas using p_tenant;
    if v_linhas > 0 then
      v_apagadas := v_apagadas || jsonb_build_object(v_relacao.nspname || '.' || v_relacao.relname, v_linhas);
    end if;
  end loop;

  delete from app.tenant where id = p_tenant;
  v_apagadas := v_apagadas || jsonb_build_object('app.tenant', 1);

  -- Conferência depois da cascata: tabela nova com tenant_id e sem chave desfaz a exclusão inteira.
  for v_relacao in
    select n.nspname, c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    join pg_attribute a on a.attrelid = c.oid and a.attname = 'tenant_id' and not a.attisdropped
    where c.relkind in ('r', 'p') and n.nspname in ('app', 'raw', 'staging', 'marts', 'public')
  loop
    execute format('select count(*) from %I.%I where tenant_id = $1', v_relacao.nspname, v_relacao.relname)
      into v_linhas using p_tenant;
    if v_linhas > 0 then
      raise exception 'exclusão desfeita: %.% ainda tem % linha(s) do tenant %',
        v_relacao.nspname, v_relacao.relname, v_linhas, p_tenant;
    end if;
  end loop;

  return jsonb_build_object(
    'tenant_id', p_tenant,
    'apagadas', v_apagadas,
    'fora_da_funcao', jsonb_build_object(
      'auth.users', v_usuarios,
      'observacao', 'as contas de login que estavam vinculadas continuam em auth.users, sem vínculo e sem '
                    'enxergar nada; apague pelo Dashboard ou pela API de admin as que não pertencem a outro tenant'));
end $$;

revoke execute on function app.excluir_tenant(uuid) from public, anon, authenticated;
