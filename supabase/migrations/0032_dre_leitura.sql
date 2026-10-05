-- Os sócios entram com o perfil leitura e sem segundo fator; a DRE de viabilidade passa a abrir para eles.
-- Gravar estudo e alíquota continua com diretor e financeiro em aal2, nas funções da 0030. A restritiva
-- segundo_fator fica como está: ela só cobra o segundo fator de diretor e financeiro.
do $$
declare t text;
begin
  foreach t in array array['estudo_viabilidade', 'estudo_viabilidade_linha', 'aliquota_imposto_obra'] loop
    execute format('drop policy leitura_diretoria on app.%I', t);
    execute format($p$create policy leitura_dre on app.%I for select to authenticated
      using (tenant_id = (select app.tenant_atual())
             and centro_custo_id in (select app.obras_permitidas())
             and (select app.perfil_atual()) in ('diretor', 'financeiro', 'leitura'))$p$, t);
  end loop;
end $$;
