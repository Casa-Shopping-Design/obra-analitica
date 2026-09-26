-- Políticas de RLS das migrations 0001 a 0006 reescritas com (select app.tenant_atual()).
-- Sem o select, a função security definer roda uma vez por linha lida; com ele o Postgres a avalia
-- uma vez por consulta (initPlan). No volume do piloto, marts.explicacao_desvio caiu de 2,4 s para
-- 0,13 s (docs/financeiro/revisao.md, achado I1). A regra de acesso não muda: mesmo tenant e mesmas obras.

alter policy leitura_tenant on app.centro_custo
  using (tenant_id = (select app.tenant_atual()) and id in (select app.obras_permitidas()));

alter policy leitura_proprio_tenant on app.tenant
  using (id = (select app.tenant_atual()));

alter policy leitura_tenant on staging.indice_valor
  using (tenant_id = (select app.tenant_atual()));

alter policy leitura_por_obra on staging.unidade
  using (tenant_id = (select app.tenant_atual()) and centro_custo_id in (select app.obras_permitidas()));

alter policy leitura_por_obra on staging.contrato_venda
  using (tenant_id = (select app.tenant_atual()) and centro_custo_id in (select app.obras_permitidas()));

alter policy leitura_por_obra on staging.parcela_receber
  using (tenant_id = (select app.tenant_atual()) and centro_custo_id in (select app.obras_permitidas()));

alter policy leitura_por_obra on staging.titulo_pagar
  using (tenant_id = (select app.tenant_atual()) and centro_custo_id in (select app.obras_permitidas()));

alter policy leitura_por_obra on staging.item_orcamento
  using (tenant_id = (select app.tenant_atual()) and centro_custo_id in (select app.obras_permitidas()));

alter policy leitura_por_obra on staging.tabela_preco
  using (tenant_id = (select app.tenant_atual()) and centro_custo_id in (select app.obras_permitidas()));

alter policy leitura_por_obra on staging.tabela_preco_unidade
  using (tenant_id = (select app.tenant_atual()) and centro_custo_id in (select app.obras_permitidas()));

alter policy leitura_por_obra on staging.unidade_valor
  using (tenant_id = (select app.tenant_atual()) and centro_custo_id in (select app.obras_permitidas()));
