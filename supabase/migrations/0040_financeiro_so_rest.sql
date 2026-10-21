-- A pagar, pago, a receber, recebido e orçamento pelo caminho só REST, para a construtora sem Bulk (pacote abaixo
-- do Ultimate). Os endpoints REST que a carga já gravava em raw (bills, bills/installments, bills/buildings-cost,
-- accounts-statements) e os dois novos (parcelas a receber por título e itens de orçamento por planilha) entram nas
-- mesmas tabelas de staging que o Bulk preenche, então marts, painel e assistente não mudam.
--
-- A regra contra somar os dois caminhos é a da 0039: o REST só entra na obra que não recebeu nada pelo Bulk naquele
-- assunto. O carregador chama esta função logo depois de staging.recarregar, na mesma transação; quem chama só a
-- staging.recarregar (a carga da demo) fica sem o REST, que a demo não tem.
--
-- O formato de parcelas, rateio, extrato e parcela a receber vem da documentação: a sondagem de 11/10/2026 recebeu
-- 403 no extrato e não pediu os outros. Falta conferir com amostra real (docs/decisoes/0021).

-- Tudo orientado a conjunto, O(n log n) nas linhas de raw do tenant; nenhuma consulta por linha. As junções com raw
-- usam o índice (tenant_id, endpoint) da 0001.
create or replace function staging.recarregar_financeiro_rest(p_tenant uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  obras_bulk_pagar uuid[];
  obras_bulk_receber uuid[];
  obras_bulk_orcamento uuid[];
  tem_bulk_pagar boolean;
  titulos_rest integer[];
  titulos_sem_vencimento integer;
begin
  -- Fotografia do que o Bulk já trouxe, antes de qualquer inserção deste caminho.
  select coalesce(array_agg(distinct centro_custo_id), '{}') into obras_bulk_pagar
  from staging.rateio_titulo where tenant_id = p_tenant;
  select coalesce(array_agg(distinct centro_custo_id), '{}') into obras_bulk_receber
  from staging.parcela_receber where tenant_id = p_tenant;
  select coalesce(array_agg(distinct centro_custo_id), '{}') into obras_bulk_orcamento
  from staging.item_orcamento where tenant_id = p_tenant;
  select exists (select 1 from raw.registro where tenant_id = p_tenant and endpoint = 'outcome') into tem_bulk_pagar;

  -- Título do REST entra quando não veio pelo Bulk e nenhuma obra do rateio dele tem título do Bulk. Título sem
  -- rateio (despesa da empresa) só entra quando o tenant não tem Bulk de a pagar nenhum.
  with titulo as (
    select distinct (r.payload->>'id')::int as id
    from raw.registro r
    where r.tenant_id = p_tenant and r.endpoint = 'bills' and r.payload->>'id' ~ '^\d{1,9}$'
  ), apropriacao as (
    select (r.payload->>'billId')::int as titulo_id_origem,
           case when r.payload->>'buildingId' ~ '^\d{1,9}$' then (r.payload->>'buildingId')::int end as obra_id_origem
    from raw.registro r
    where r.tenant_id = p_tenant and r.endpoint = 'bills/buildings-cost' and r.payload->>'billId' ~ '^\d{1,9}$'
      and r.payload->>'buildingId' is not null
  ), bloqueado as (
    select distinct a.titulo_id_origem
    from apropriacao a
    join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = a.obra_id_origem
    where cc.id = any(obras_bulk_pagar)
  )
  select coalesce(array_agg(t.id), '{}') into titulos_rest
  from titulo t
  where not exists (select 1 from staging.titulo_pagar tp where tp.tenant_id = p_tenant and tp.id_origem = t.id)
    and not exists (select 1 from bloqueado b where b.titulo_id_origem = t.id)
    and (not tem_bulk_pagar or exists (select 1 from apropriacao a where a.titulo_id_origem = t.id));

  -- O rateio do REST vem em percentual do título, então a fração é o percentual sobre 100. A soma só passa a ser o
  -- divisor quando excede 100. Obra fora de app.centro_custo, parte de departamento e linha sem percentual ficam
  -- com a parte delas, e nenhuma obra recebe a de outra. Percentual ausente vale 100 só quando o título tem uma
  -- obra; com várias, a linha sem percentual fica de fora.
  insert into staging.rateio_titulo (tenant_id, titulo_id_origem, centro_custo_id, valor, fracao)
  with apropriacao as (
    select (r.payload->>'billId')::int as titulo_id_origem,
           case when r.payload->>'buildingId' ~ '^\d{1,9}$' then (r.payload->>'buildingId')::int end as obra_id_origem,
           coalesce(staging.numero_origem(r.payload->>'percentage'),
                    case when count(*) over (partition by r.payload->>'billId') = 1 then 100 end) as percentual
    from raw.registro r
    join unnest(titulos_rest) as tr(id) on tr.id::text = r.payload->>'billId'
    where r.tenant_id = p_tenant and r.endpoint = 'bills/buildings-cost' and r.payload->>'buildingId' is not null
  ), valida as (
    select a.*, greatest(sum(a.percentual) over (partition by a.titulo_id_origem), 100) as total_apropriado
    from apropriacao a
    where a.percentual > 0
  ), valor_titulo as (
    select (r.payload->>'id')::int as titulo_id_origem, staging.numero_origem(r.payload->>'totalInvoiceAmount') as valor
    from raw.registro r
    join unnest(titulos_rest) as tr(id) on tr.id::text = r.payload->>'id'
    where r.tenant_id = p_tenant and r.endpoint = 'bills'
  )
  select p_tenant, v.titulo_id_origem, cc.id,
         coalesce(max(vt.valor), 0) * sum(v.percentual) / max(v.total_apropriado),
         sum(v.percentual) / max(v.total_apropriado)
  from valida v
  join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = v.obra_id_origem
  left join valor_titulo vt on vt.titulo_id_origem = v.titulo_id_origem
  group by v.titulo_id_origem, cc.id
  on conflict do nothing;

  -- staging.titulo_pagar tem uma linha por título. A parcela do REST não traz valor pago, só a situação; o que foi
  -- pago vem do extrato (type Expense, ou origem CP quando o tipo falta) pelo título e número da parcela. Saldo da
  -- parcela: zero se totalmente paga, o valor se não paga, e o valor menos o pago no extrato nos demais casos;
  -- sem valor, o saldo fica nulo, para a parcela não parecer quitada.
  -- O vencimento do título é o da primeira parcela em aberto; quitado, o da última.
  insert into staging.titulo_pagar
    (tenant_id, centro_custo_id, id_origem, credor, vencimento, valor_original, saldo, data_pagamento)
  with movimento as (
    select (r.payload->>'billId')::int as titulo_id_origem,
           case when r.payload->>'installmentNumber' ~ '^\d{1,9}$' then (r.payload->>'installmentNumber')::int end as parcela,
           staging.data_origem(r.payload->>'date') as data_pagamento,
           abs(staging.numero_origem(r.payload->>'value')) as valor
    from raw.registro r
    join unnest(titulos_rest) as tr(id) on tr.id::text = r.payload->>'billId'
    where r.tenant_id = p_tenant and r.endpoint = 'accounts-statements'
      and coalesce(lower(r.payload->>'type') in ('expense', 'saida', 'saída'), upper(r.payload->>'statementOrigin') = 'CP')
  ), pago_parcela as (
    select titulo_id_origem, parcela, sum(valor) as valor from movimento group by 1, 2
  ), pago_titulo as (
    select titulo_id_origem, sum(valor) as valor, max(data_pagamento) as ultimo_pagamento from movimento group by 1
  ), parcela as (
    select (r.payload->>'billId')::int as titulo_id_origem,
           staging.data_origem(r.payload->>'dueDate') as vencimento,
           staging.numero_origem(r.payload->>'amount') as valor,
           case translate(lower(btrim(r.payload->>'situation')), 'ãáâàéêíóôõúç', 'aaaaeeiooouc')
             when 'totalmente paga' then 0
             when 'nao paga' then staging.numero_origem(r.payload->>'amount')
             -- greatest ignora nulo e daria zero; com least o valor ausente continua nulo
             else staging.numero_origem(r.payload->>'amount')
                  - least(coalesce(pp.valor, 0), staging.numero_origem(r.payload->>'amount'))
           end as saldo
    from raw.registro r
    join unnest(titulos_rest) as tr(id) on tr.id::text = r.payload->>'billId'
    left join pago_parcela pp on pp.titulo_id_origem = (r.payload->>'billId')::int
     and pp.parcela = case when r.payload->>'installmentNumber' ~ '^\d{1,9}$' then (r.payload->>'installmentNumber')::int end
    where r.tenant_id = p_tenant and r.endpoint = 'bills/installments' and r.payload ? 'installmentNumber'
  ), resumo_parcela as (
    select titulo_id_origem, sum(valor) as valor, sum(saldo) as saldo,
           min(vencimento) filter (where saldo > 0) as proximo_vencimento, max(vencimento) as ultimo_vencimento
    from parcela group by 1
  ), obra_unica as (
    select titulo_id_origem, (array_agg(centro_custo_id))[1] as centro_custo_id
    from staging.rateio_titulo
    where tenant_id = p_tenant and titulo_id_origem = any(titulos_rest)
    group by titulo_id_origem
    having count(*) = 1
  ), titulo as (
    select (r.payload->>'id')::int as id_origem,
           coalesce(staging.numero_origem(r.payload->>'totalInvoiceAmount'), rp.valor) as valor_original,
           case when rp.titulo_id_origem is not null then rp.saldo
                else staging.numero_origem(r.payload->>'totalInvoiceAmount')
                     - least(coalesce(pt.valor, 0), staging.numero_origem(r.payload->>'totalInvoiceAmount'))
           end as saldo,
           coalesce(rp.proximo_vencimento, rp.ultimo_vencimento, staging.data_origem(r.payload->>'issueDate'),
                    pt.ultimo_pagamento) as vencimento,
           pt.ultimo_pagamento
    from raw.registro r
    join unnest(titulos_rest) as tr(id) on tr.id::text = r.payload->>'id'
    left join resumo_parcela rp on rp.titulo_id_origem = (r.payload->>'id')::int
    left join pago_titulo pt on pt.titulo_id_origem = (r.payload->>'id')::int
    where r.tenant_id = p_tenant and r.endpoint = 'bills'
  )
  select p_tenant, ou.centro_custo_id, t.id_origem, null, t.vencimento, t.valor_original, t.saldo, t.ultimo_pagamento
  from titulo t
  left join obra_unica ou on ou.titulo_id_origem = t.id_origem
  where t.vencimento is not null
  on conflict do nothing;

  select count(*) into titulos_sem_vencimento
  from unnest(titulos_rest) tr(id)
  where not exists (select 1 from staging.titulo_pagar t where t.tenant_id = p_tenant and t.id_origem = tr.id);
  raise notice '% títulos do REST sem data nenhuma ficaram fora do a pagar', titulos_sem_vencimento;

  insert into staging.pagamento (tenant_id, centro_custo_id, titulo_id_origem, sequencia, data_pagamento, valor)
  select p_tenant, t.centro_custo_id, t.id_origem,
         row_number() over (partition by t.id_origem
                            order by staging.data_origem(r.payload->>'date'), r.payload->>'id', r.id),
         staging.data_origem(r.payload->>'date'), abs(staging.numero_origem(r.payload->>'value'))
  from raw.registro r
  join unnest(titulos_rest) as tr(id) on tr.id::text = r.payload->>'billId'
  join staging.titulo_pagar t on t.tenant_id = p_tenant and t.id_origem = tr.id
  where r.tenant_id = p_tenant and r.endpoint = 'accounts-statements'
    and coalesce(lower(r.payload->>'type') in ('expense', 'saida', 'saída'), upper(r.payload->>'statementOrigin') = 'CP')
    and staging.data_origem(r.payload->>'date') is not null and staging.numero_origem(r.payload->>'value') is not null
  on conflict do nothing;

  -- A receber: o título a receber liga ao contrato pelo receivableBillId do sales-contracts, e a parcela do staging
  -- fica com o código do contrato, que é o que contrato_venda guarda. balanceDue é o saldo devedor sem correção.
  -- Parcela quitada que a API não devolve ainda aparece no extrato (type Income, ou origem CR); ela entra com o
  -- recebido, saldo zero e a data do último recebimento no lugar do vencimento, para o recebido não se perder.
  insert into staging.parcela_receber
    (tenant_id, centro_custo_id, id_origem, contrato_id_origem, vencimento, valor_original, saldo,
     saldo_corrigido, tipo_condicao, inadimplente, data_recebimento, valor_recebido)
  with contrato as (
    select distinct on ((r.payload->>'receivableBillId')::int)
           (r.payload->>'receivableBillId')::int as titulo_id_origem, (r.payload->>'id')::int as contrato_id_origem,
           cc.id as centro_custo_id
    from raw.registro r
    join app.centro_custo cc on cc.tenant_id = p_tenant
     and cc.id_origem = case when r.payload->>'enterpriseId' ~ '^\d{1,9}$' then (r.payload->>'enterpriseId')::int end
    where r.tenant_id = p_tenant and r.endpoint = 'sales-contracts'
      and r.payload->>'receivableBillId' ~ '^\d{1,9}$' and r.payload->>'id' ~ '^\d{1,9}$'
      and not cc.id = any(obras_bulk_receber)
    order by (r.payload->>'receivableBillId')::int, (r.payload->>'id')::int
  ), recebido as (
    select (r.payload->>'billId')::int as titulo_id_origem, (r.payload->>'installmentNumber')::int as parcela,
           max(staging.data_origem(r.payload->>'date')) as ultimo_recebimento,
           sum(abs(staging.numero_origem(r.payload->>'value'))) as valor
    from raw.registro r
    where r.tenant_id = p_tenant and r.endpoint = 'accounts-statements'
      and r.payload->>'billId' ~ '^\d{1,9}$' and r.payload->>'installmentNumber' ~ '^\d{1,9}$'
      and coalesce(lower(r.payload->>'type') in ('income', 'entrada'), upper(r.payload->>'statementOrigin') = 'CR')
      and staging.data_origem(r.payload->>'date') is not null and staging.numero_origem(r.payload->>'value') is not null
    group by 1, 2
  ), aberta as (
    select (r.payload->>'receivableBillId')::int as titulo_id_origem, (r.payload->>'installmentId')::int as parcela,
           staging.data_origem(r.payload->>'dueDate') as vencimento,
           staging.numero_origem(r.payload->>'balanceDue') as saldo,
           nullif(btrim(r.payload->>'conditionTypeId'), '') as tipo_condicao
    from raw.registro r
    where r.tenant_id = p_tenant and r.endpoint = 'receivable-bills/installments'
      and r.payload->>'receivableBillId' ~ '^\d{1,9}$' and r.payload->>'installmentId' ~ '^\d{1,9}$'
  ), parcela as (
    select coalesce(a.titulo_id_origem, rc.titulo_id_origem) as titulo_id_origem,
           coalesce(a.parcela, rc.parcela) as parcela,
           coalesce(a.vencimento, rc.ultimo_recebimento) as vencimento,
           coalesce(a.saldo, 0) as saldo, a.tipo_condicao, rc.ultimo_recebimento, rc.valor as recebido
    from aberta a
    full join recebido rc on rc.titulo_id_origem = a.titulo_id_origem and rc.parcela = a.parcela
  )
  select p_tenant, c.centro_custo_id, p.parcela, c.contrato_id_origem, p.vencimento,
         p.saldo + coalesce(p.recebido, 0), p.saldo, null, p.tipo_condicao,
         p.saldo > 0 and p.vencimento < current_date, p.ultimo_recebimento, p.recebido
  from parcela p
  join contrato c on c.titulo_id_origem = p.titulo_id_origem
  where p.vencimento is not null
  on conflict do nothing;

  insert into staging.recebimento
    (tenant_id, centro_custo_id, contrato_id_origem, parcela_id_origem, sequencia, data_recebimento, valor)
  select p.tenant_id, p.centro_custo_id, p.contrato_id_origem, p.id_origem,
         row_number() over (partition by p.contrato_id_origem, p.id_origem
                            order by staging.data_origem(r.payload->>'date'), r.payload->>'id', r.id),
         staging.data_origem(r.payload->>'date'), abs(staging.numero_origem(r.payload->>'value'))
  from raw.registro r
  join raw.registro sc on sc.tenant_id = p_tenant and sc.endpoint = 'sales-contracts'
   and sc.payload->>'receivableBillId' = r.payload->>'billId'
  join staging.parcela_receber p on p.tenant_id = p_tenant
   and p.contrato_id_origem = case when sc.payload->>'id' ~ '^\d{1,9}$' then (sc.payload->>'id')::int end
   and p.id_origem = case when r.payload->>'installmentNumber' ~ '^\d{1,9}$' then (r.payload->>'installmentNumber')::int end
  where r.tenant_id = p_tenant and r.endpoint = 'accounts-statements'
    and coalesce(lower(r.payload->>'type') in ('income', 'entrada'), upper(r.payload->>'statementOrigin') = 'CR')
    and not p.centro_custo_id = any(obras_bulk_receber)
    and staging.data_origem(r.payload->>'date') is not null and staging.numero_origem(r.payload->>'value') is not null
  on conflict do nothing;

  -- Orçamento por planilha (uma por unidade construtiva). Só o item folha entra: a etapa que agrupa outros itens
  -- repetiria o valor deles na soma do custo orçado. Na ordem do código, o item é etapa quando o seguinte começa por
  -- ele e um ponto; isso é O(n log n), sem comparar cada item com todos. O mesmo código em planilhas diferentes vira
  -- uma linha com a soma, porque a chave de staging.item_orcamento é obra e código.
  insert into staging.item_orcamento (tenant_id, centro_custo_id, codigo, descricao, valor_total, pct_concluido)
  with item as (
    select cc.id as centro_custo_id, btrim(r.payload->>'wbsCode') as codigo,
           nullif(btrim(r.payload->>'description'), '') as descricao,
           staging.numero_origem(r.payload->>'totalPrice') as valor_total,
           lead(btrim(r.payload->>'wbsCode')) over (
             partition by cc.id, r.payload->>'buildingUnitId' order by btrim(r.payload->>'wbsCode') collate "C") as seguinte
    from raw.registro r
    join app.centro_custo cc on cc.tenant_id = p_tenant
     and cc.id_origem = case when r.payload->>'buildingId' ~ '^\d{1,9}$' then (r.payload->>'buildingId')::int end
    where r.tenant_id = p_tenant and r.endpoint = 'building-cost-estimations/items'
      and nullif(btrim(r.payload->>'wbsCode'), '') is not null
      and not cc.id = any(obras_bulk_orcamento)
  )
  select p_tenant, centro_custo_id, codigo, min(descricao), sum(valor_total), null
  from item
  where seguinte is null or left(seguinte, length(codigo) + 1) <> codigo || '.'
  group by centro_custo_id, codigo
  on conflict do nothing;
end $$;

revoke execute on function staging.recarregar_financeiro_rest(uuid) from public, anon, authenticated;
