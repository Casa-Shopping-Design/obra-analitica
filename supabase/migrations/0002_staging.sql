-- Staging: tabelas tipadas preenchidas a partir de raw.registro.
-- Todas carregam tenant_id e centro_custo_id (uuid de app.centro_custo).

create table staging.unidade (
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  id_origem integer not null,
  nome text,
  tipologia text,
  area_privativa numeric,
  situacao text,          -- D disponivel, C reservada, P proposta, V vendida, R reserva tecnica (lista completa em marts.mapa_unidades)
  data_entrega date,
  primary key (tenant_id, id_origem)
);

create table staging.contrato_venda (
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  id_origem integer not null,
  numero text,
  data_venda date,
  valor numeric,
  situacao text,          -- 1 ativo, 3 distratado
  data_distrato date,
  banco_repasse text,
  data_repasse date,
  nome_cliente text,
  unidade_id_origem integer,
  primary key (tenant_id, id_origem)
);

create table staging.parcela_receber (
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  id_origem integer not null,
  contrato_id_origem integer,
  vencimento date not null,
  valor_original numeric,
  saldo numeric,
  saldo_corrigido numeric,
  tipo_condicao text,     -- AT, PM, BA, CH, FI
  origem text generated always as (case when tipo_condicao = 'FI' then 'repasse' else 'direta' end) stored,
  inadimplente boolean,
  data_recebimento date,
  valor_recebido numeric,
  -- installmentId repete entre titulos (1, 2, 3...), a chave precisa do titulo junto
  primary key (tenant_id, contrato_id_origem, id_origem)
);
create index on staging.parcela_receber (tenant_id, centro_custo_id, vencimento);

create table staging.titulo_pagar (
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  id_origem integer not null,
  credor text,
  vencimento date not null,
  valor_original numeric,
  saldo numeric,
  data_pagamento date,
  primary key (tenant_id, id_origem)
);
create index on staging.titulo_pagar (tenant_id, centro_custo_id, vencimento);

create table staging.item_orcamento (
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  codigo text not null,
  descricao text,
  valor_total numeric,
  pct_concluido numeric,
  primary key (tenant_id, centro_custo_id, codigo)
);

-- Recarrega o staging inteiro a partir do raw. Chamada pelo carregador apos gravar os JSON.
-- So o carregador (dono do banco) chama. Sem o revoke abaixo, qualquer usuario logado
-- poderia recarregar o tenant de outro, porque funcao nasce executavel por public.
create or replace function staging.recarregar(p_tenant uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from staging.unidade where tenant_id = p_tenant;
  insert into staging.unidade
  select p_tenant, cc.id, (r.payload->>'id')::int, r.payload->>'name', r.payload->>'propertyType',
         (r.payload->>'privateArea')::numeric, r.payload->>'commercialStock', (r.payload->>'deliveryDate')::date
  from raw.registro r
  join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = (r.payload->>'enterpriseId')::int
  where r.tenant_id = p_tenant and r.endpoint = 'units';

  delete from staging.contrato_venda where tenant_id = p_tenant;
  insert into staging.contrato_venda
  select p_tenant, cc.id, (r.payload->>'id')::int, r.payload->>'number', (r.payload->>'contractDate')::date,
         (r.payload->>'value')::numeric, r.payload->>'situation', (r.payload->>'cancellationDate')::date,
         r.payload->>'financialInstitutionNumber', (r.payload->>'financialInstitutionDate')::date,
         r.payload->'customers'->0->>'name', (r.payload->'units'->0->>'id')::int
  from raw.registro r
  join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = (r.payload->>'enterpriseId')::int
  where r.tenant_id = p_tenant and r.endpoint = 'sales';

  delete from staging.parcela_receber where tenant_id = p_tenant;
  insert into staging.parcela_receber
    (tenant_id, centro_custo_id, id_origem, contrato_id_origem, vencimento, valor_original, saldo,
     saldo_corrigido, tipo_condicao, inadimplente, data_recebimento, valor_recebido)
  select p_tenant, cc.id, (r.payload->>'installmentId')::int, (r.payload->>'billId')::int,
         (r.payload->>'dueDate')::date, (r.payload->>'originalAmount')::numeric, (r.payload->>'balanceAmount')::numeric,
         (r.payload->>'correctedBalanceAmount')::numeric, r.payload->'paymentTerm'->>'id',
         r.payload->>'defaulterSituation' = 'S',
         (r.payload->'receipts'->0->>'paymentDate')::date, (r.payload->'receipts'->0->>'amount')::numeric
  from raw.registro r
  join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = (r.payload->>'projectId')::int
  where r.tenant_id = p_tenant and r.endpoint = 'income';

  delete from staging.titulo_pagar where tenant_id = p_tenant;
  insert into staging.titulo_pagar
  select p_tenant, cc.id, (r.payload->>'billId')::int, r.payload->>'creditorName', (r.payload->>'dueDate')::date,
         (r.payload->>'originalAmount')::numeric, (r.payload->>'balanceAmount')::numeric,
         (r.payload->'payments'->0->>'paymentDate')::date
  from raw.registro r
  join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = (r.payload->'buildingsCosts'->0->>'buildingId')::int
  where r.tenant_id = p_tenant and r.endpoint = 'outcome';

  delete from staging.item_orcamento where tenant_id = p_tenant;
  insert into staging.item_orcamento
  select p_tenant, cc.id, r.payload->>'wbsCode', r.payload->>'description',
         (r.payload->>'totalPrice')::numeric, (r.payload->>'percentComplete')::numeric
  from raw.registro r
  join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = (r.payload->>'buildingId')::int
  where r.tenant_id = p_tenant and r.endpoint = 'building-cost-estimation-items';
end $$;

revoke execute on function staging.recarregar(uuid) from public, anon, authenticated;

-- RLS: politica unica por tabela (tenant AND obra). Nunca duas politicas permissivas separadas.
do $$
declare t text;
begin
  foreach t in array array['unidade','contrato_venda','parcela_receber','titulo_pagar','item_orcamento'] loop
    execute format('alter table staging.%I enable row level security', t);
    execute format('alter table staging.%I force row level security', t);
    execute format($p$create policy leitura_por_obra on staging.%I for select to authenticated
      using (tenant_id = app.tenant_atual() and centro_custo_id in (select app.obras_permitidas()))$p$, t);
    execute format('grant select on staging.%I to authenticated', t);
  end loop;
end $$;
