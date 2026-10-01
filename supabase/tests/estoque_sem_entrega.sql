-- Obra sem data de entrega fica com prazo nulo e sem o alerta de estoque depois da entrega (migration 0029).
begin;
create extension if not exists pgtap with schema extensions;
select plan(3);

create temporary table obra_teste on commit drop as
select tenant_id, centro_custo_id from marts.estoque_obra where unidades_estoque > 0 limit 1;

update staging.unidade u set data_entrega = null
from obra_teste o where u.tenant_id = o.tenant_id and u.centro_custo_id = o.centro_custo_id;

select is(
  (select e.meses_ate_entrega from marts.estoque_obra e join obra_teste o using (tenant_id, centro_custo_id)),
  null::integer,
  'sem data de entrega, meses_ate_entrega é nulo'
);

select is(
  (select count(*)::integer from marts.alertas_obra a join obra_teste o using (tenant_id, centro_custo_id)
   where a.tipo = 'estoque_apos_entrega'),
  0,
  'sem data de entrega, o alerta de estoque depois da entrega não dispara'
);

update staging.unidade u set data_entrega = current_date - 40
from obra_teste o where u.tenant_id = o.tenant_id and u.centro_custo_id = o.centro_custo_id;

select is(
  (select e.meses_ate_entrega from marts.estoque_obra e join obra_teste o using (tenant_id, centro_custo_id)),
  0,
  'entrega já passada continua contando zero meses'
);

select * from finish();
rollback;
