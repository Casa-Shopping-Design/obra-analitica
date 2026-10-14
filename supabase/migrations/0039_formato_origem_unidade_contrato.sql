-- Unidade e contrato no formato real da API (sondagem de 11/10/2026 em group/v2). Na unidade, o valor sugerido
-- vem em evaluation, a tabela de preço em specialValues[].tablePricesId e a data de entrega muitas vezes só na
-- prevista; cada cliente preenche o cadastro do seu jeito, então nenhum campo além do código e da obra é
-- obrigatório. O contrato passa a vir também do REST sales-contracts quando o Bulk de vendas não responde.
-- As duas funções são as da 0012 e da 0004 com só esses trechos trocados.

create or replace function staging.recarregar(p_tenant uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  titulos_sem_obra integer;
begin
  -- Cadastro de unidade muda de cliente para cliente e quase nenhum campo é obrigatório no ERP: número e data
  -- passam por conversão tolerante, unidade sem nome ganha o código, e a entrega usa a data prevista
  -- (scheduledDeliveryDate) quando a efetiva não foi preenchida.
  delete from staging.unidade where tenant_id = p_tenant;
  insert into staging.unidade
  select p_tenant, cc.id, (r.payload->>'id')::int,
         coalesce(nullif(btrim(r.payload->>'name'), ''), 'Unidade ' || (r.payload->>'id')),
         nullif(btrim(r.payload->>'propertyType'), ''),
         staging.numero_origem(r.payload->>'privateArea'),
         nullif(btrim(r.payload->>'commercialStock'), ''),
         coalesce(staging.data_origem(r.payload->>'deliveryDate'), staging.data_origem(r.payload->>'scheduledDeliveryDate'))
  from raw.registro r
  join app.centro_custo cc on cc.tenant_id = p_tenant
   and cc.id_origem = case when r.payload->>'enterpriseId' ~ '^\d{1,9}$' then (r.payload->>'enterpriseId')::int end
  where r.tenant_id = p_tenant and r.endpoint = 'units' and r.payload->>'id' ~ '^\d{1,9}$';

  delete from staging.contrato_venda where tenant_id = p_tenant;
  insert into staging.contrato_venda
  select p_tenant, cc.id, (r.payload->>'id')::int, r.payload->>'number', (r.payload->>'contractDate')::date,
         (r.payload->>'value')::numeric, r.payload->>'situation', (r.payload->>'cancellationDate')::date,
         r.payload->>'financialInstitutionNumber', (r.payload->>'financialInstitutionDate')::date,
         r.payload->'customers'->0->>'name', (r.payload->'units'->0->>'id')::int
  from raw.registro r
  join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = (r.payload->>'enterpriseId')::int
  where r.tenant_id = p_tenant and r.endpoint = 'sales';

  -- Sem Bulk (pacote sem carga em massa ou rota indisponível) o contrato vem do REST sales-contracts. Só entra
  -- a obra que não recebeu contrato nenhum pelo Bulk, para os dois caminhos não se somarem. A API devolve a
  -- situação por extenso (Emitido, Cancelado), embora a documentação fale em código de 0 a 3; vale qualquer
  -- um. Só o emitido conta como venda ('1', como no Bulk); cancelado é distrato ('3'); solicitado e
  -- autorizado ainda não são venda ('0'). O nome do cliente não é carregado neste caminho.
  insert into staging.contrato_venda
  select p_tenant, cc.id, (r.payload->>'id')::int, nullif(btrim(r.payload->>'number'), ''),
         staging.data_origem(coalesce(r.payload->>'contractDate', r.payload->>'issueDate')),
         staging.numero_origem(coalesce(r.payload->>'value', r.payload->>'totalSellingValue')),
         case lower(btrim(r.payload->>'situation'))
           when 'emitido' then '1' when '2' then '1'
           when 'cancelado' then '3' when '3' then '3'
           else '0'
         end,
         staging.data_origem(r.payload->>'cancellationDate'),
         nullif(btrim(r.payload->>'financialInstitutionNumber'), ''),
         staging.data_origem(r.payload->>'financialInstitutionDate'),
         null,
         (select (u->>'id')::int
          from jsonb_array_elements(case when jsonb_typeof(r.payload->'salesContractUnits') = 'array'
                                         then r.payload->'salesContractUnits' else '[]'::jsonb end)
            with ordinality as x(u, ordem)
          where u->>'id' ~ '^\d{1,9}$'
          -- main ausente conta como falso; sem o coalesce o nulo viria antes da unidade principal
          order by coalesce(lower(u->>'main') = 'true', false) desc, ordem
          limit 1)
  from raw.registro r
  join app.centro_custo cc on cc.tenant_id = p_tenant
   and cc.id_origem = case when r.payload->>'enterpriseId' ~ '^\d{1,9}$' then (r.payload->>'enterpriseId')::int end
  where r.tenant_id = p_tenant and r.endpoint = 'sales-contracts' and r.payload->>'id' ~ '^\d{1,9}$'
    and not exists (
      select 1 from staging.contrato_venda c where c.tenant_id = p_tenant and c.centro_custo_id = cc.id
    )
  on conflict (tenant_id, id_origem) do nothing;

  -- data_recebimento e valor_recebido da parcela viram o último recebimento e a soma de todos;
  -- o valor de cada evento fica em staging.recebimento.
  delete from staging.parcela_receber where tenant_id = p_tenant;
  insert into staging.parcela_receber
    (tenant_id, centro_custo_id, id_origem, contrato_id_origem, vencimento, valor_original, saldo,
     saldo_corrigido, tipo_condicao, inadimplente, data_recebimento, valor_recebido)
  select p_tenant, cc.id, (r.payload->>'installmentId')::int, (r.payload->>'billId')::int,
         (r.payload->>'dueDate')::date, (r.payload->>'originalAmount')::numeric, (r.payload->>'balanceAmount')::numeric,
         (r.payload->>'correctedBalanceAmount')::numeric, r.payload->'paymentTerm'->>'id',
         r.payload->>'defaulterSituation' = 'S',
         rc.ultimo_recebimento, rc.total_recebido
  from raw.registro r
  join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = (r.payload->>'projectId')::int
  cross join lateral (
    select max((e->>'paymentDate')::date) as ultimo_recebimento, sum((e->>'amount')::numeric) as total_recebido
    from jsonb_array_elements(case when jsonb_typeof(r.payload->'receipts') = 'array'
                                   then r.payload->'receipts' else '[]'::jsonb end) e
  ) rc
  where r.tenant_id = p_tenant and r.endpoint = 'income';

  delete from staging.recebimento where tenant_id = p_tenant;
  insert into staging.recebimento
    (tenant_id, centro_custo_id, contrato_id_origem, parcela_id_origem, sequencia, data_recebimento, valor)
  select p_tenant, cc.id, (r.payload->>'billId')::int, (r.payload->>'installmentId')::int, rc.sequencia,
         (rc.evento->>'paymentDate')::date, (rc.evento->>'amount')::numeric
  from raw.registro r
  join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = (r.payload->>'projectId')::int
  cross join lateral jsonb_array_elements(case when jsonb_typeof(r.payload->'receipts') = 'array'
                                               then r.payload->'receipts' else '[]'::jsonb end)
    with ordinality as rc(evento, sequencia)
  where r.tenant_id = p_tenant and r.endpoint = 'income'
    and rc.evento->>'paymentDate' is not null and rc.evento->>'amount' is not null;

  delete from staging.pagamento where tenant_id = p_tenant;
  delete from staging.rateio_titulo where tenant_id = p_tenant;
  delete from staging.titulo_pagar where tenant_id = p_tenant;

  -- A fração divide pelo total apropriado no título, inclusive a parte de obra que não está em
  -- app.centro_custo; assim uma obra nunca recebe a parte de outra. Mesma obra repetida no payload é somada.
  insert into staging.rateio_titulo (tenant_id, titulo_id_origem, centro_custo_id, valor, fracao)
  with apropriacao as (
    select (r.payload->>'billId')::int as titulo_id_origem, (bc->>'buildingId')::int as obra_id_origem,
           (bc->>'amount')::numeric as valor,
           sum((bc->>'amount')::numeric) over (partition by r.id) as total_apropriado
    from raw.registro r
    cross join lateral jsonb_array_elements(case when jsonb_typeof(r.payload->'buildingsCosts') = 'array'
                                                 then r.payload->'buildingsCosts' else '[]'::jsonb end) bc
    where r.tenant_id = p_tenant and r.endpoint = 'outcome'
  )
  select p_tenant, a.titulo_id_origem, cc.id, sum(a.valor), sum(a.valor) / max(a.total_apropriado)
  from apropriacao a
  join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = a.obra_id_origem
  group by a.titulo_id_origem, cc.id
  having max(a.total_apropriado) > 0;

  -- data_pagamento do título vira a do último pagamento; o valor de cada um fica em staging.pagamento.
  insert into staging.titulo_pagar
    (tenant_id, centro_custo_id, id_origem, credor, vencimento, valor_original, saldo, data_pagamento)
  with obra_unica as (
    select titulo_id_origem, (array_agg(centro_custo_id))[1] as centro_custo_id
    from staging.rateio_titulo
    where tenant_id = p_tenant
    group by titulo_id_origem
    having count(*) = 1
  )
  select p_tenant, ou.centro_custo_id, (r.payload->>'billId')::int, r.payload->>'creditorName',
         (r.payload->>'dueDate')::date, (r.payload->>'originalAmount')::numeric,
         (r.payload->>'balanceAmount')::numeric, pg.ultimo_pagamento
  from raw.registro r
  left join obra_unica ou on ou.titulo_id_origem = (r.payload->>'billId')::int
  cross join lateral (
    select max((e->>'paymentDate')::date) as ultimo_pagamento
    from jsonb_array_elements(case when jsonb_typeof(r.payload->'payments') = 'array'
                                   then r.payload->'payments' else '[]'::jsonb end) e
  ) pg
  where r.tenant_id = p_tenant and r.endpoint = 'outcome';

  insert into staging.pagamento (tenant_id, centro_custo_id, titulo_id_origem, sequencia, data_pagamento, valor)
  select p_tenant, t.centro_custo_id, t.id_origem, pg.sequencia,
         (pg.evento->>'paymentDate')::date, (pg.evento->>'amount')::numeric
  from raw.registro r
  join staging.titulo_pagar t on t.tenant_id = p_tenant and t.id_origem = (r.payload->>'billId')::int
  cross join lateral jsonb_array_elements(case when jsonb_typeof(r.payload->'payments') = 'array'
                                               then r.payload->'payments' else '[]'::jsonb end)
    with ordinality as pg(evento, sequencia)
  where r.tenant_id = p_tenant and r.endpoint = 'outcome'
    and pg.evento->>'paymentDate' is not null and pg.evento->>'amount' is not null;

  select count(*) into titulos_sem_obra
  from staging.titulo_pagar t
  where t.tenant_id = p_tenant
    and not exists (
      select 1 from staging.rateio_titulo rt
      where rt.tenant_id = t.tenant_id and rt.titulo_id_origem = t.id_origem
    );
  raise notice '% títulos a pagar sem obra ficaram fora das views por obra', titulos_sem_obra;

  delete from staging.item_orcamento where tenant_id = p_tenant;
  insert into staging.item_orcamento
  select p_tenant, cc.id, r.payload->>'wbsCode', r.payload->>'description',
         (r.payload->>'totalPrice')::numeric, (r.payload->>'percentComplete')::numeric
  from raw.registro r
  join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = (r.payload->>'buildingId')::int
  where r.tenant_id = p_tenant and r.endpoint = 'building-cost-estimation-items';
end $$;

revoke execute on function staging.recarregar(uuid) from public, anon, authenticated;

create or replace function staging.recarregar_precos(p_tenant uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  insert into staging.indice_valor (tenant_id, indexador_id_origem, nome, referencia, valor, percentual)
  select p_tenant, (r.payload->>'id')::int, r.payload->>'name', (r.payload->'lastValue'->>'date')::date,
         (r.payload->'lastValue'->>'value')::numeric, (r.payload->'lastValue'->>'percentage')::numeric
  from raw.registro r
  where r.tenant_id = p_tenant and r.endpoint = 'indexers' and r.payload->'lastValue'->>'date' is not null
  on conflict (tenant_id, indexador_id_origem, referencia)
    do update set valor = excluded.valor, percentual = excluded.percentual, nome = excluded.nome;

  delete from staging.tabela_preco_unidade where tenant_id = p_tenant;
  delete from staging.tabela_preco where tenant_id = p_tenant;
  insert into staging.tabela_preco
  select p_tenant, cc.id, (r.payload->>'id')::int, (r.payload->>'version')::int, r.payload->>'tableName',
         r.payload->>'tableVersionName', (r.payload->>'startOfTerm')::date, (r.payload->>'endOfTerm')::date,
         (r.payload->'paymentConditions'->0->'indexer'->>'id')::int, (r.payload->'paymentConditions'->0->>'baseDate')::date
  from raw.registro r
  join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = (r.payload->>'enterpriseId')::int
  where r.tenant_id = p_tenant and r.endpoint = 'price-tables'
  on conflict do nothing;

  insert into staging.tabela_preco_unidade
  select p_tenant, cc.id, (r.payload->>'id')::int, (r.payload->>'version')::int,
         (item->>'id')::int, (item->>'indexedQuantity')::numeric
  from raw.registro r
  join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = (r.payload->>'enterpriseId')::int
  cross join lateral jsonb_array_elements(r.payload->'units') as item
  where r.tenant_id = p_tenant and r.endpoint = 'price-tables' and item->>'indexedQuantity' is not null
  on conflict do nothing;

  delete from staging.unidade_valor where tenant_id = p_tenant;
  -- Na API o valor sugerido fica em evaluation e a tabela em specialValues[].tablePricesId; o formato antigo, no
  -- nível da unidade e com tablePricesID, segue aceito. Indexador 0 quer dizer sem indexador.
  insert into staging.unidade_valor
  select p_tenant, cc.id, (r.payload->>'id')::int,
         staging.numero_origem(coalesce(r.payload->'evaluation'->>'saleValuePrice', r.payload->>'saleValuePrice')),
         staging.data_origem(coalesce(r.payload->'evaluation'->>'saleValueDate', r.payload->>'saleValueDate')),
         nullif(case when r.payload->>'indexerId' ~ '^\d{1,9}$' then (r.payload->>'indexerId')::int end, 0),
         case when t.tabela ~ '^\d{1,9}$' then t.tabela::int end
  from raw.registro r
  join app.centro_custo cc on cc.tenant_id = p_tenant
   and cc.id_origem = case when r.payload->>'enterpriseId' ~ '^\d{1,9}$' then (r.payload->>'enterpriseId')::int end
  cross join lateral (
    select coalesce(
      (select e->>'tablePricesId'
       from jsonb_array_elements(case when jsonb_typeof(r.payload->'specialValues') = 'array'
                                      then r.payload->'specialValues' else '[]'::jsonb end) with ordinality as v(e, ordem)
       where e->>'tablePricesId' is not null order by ordem limit 1),
      r.payload->>'tablePricesId', r.payload->>'tablePricesID') as tabela
  ) t
  where r.tenant_id = p_tenant and r.endpoint = 'units' and r.payload->>'id' ~ '^\d{1,9}$';
end $$;
revoke execute on function staging.recarregar_precos(uuid) from public, anon, authenticated;
