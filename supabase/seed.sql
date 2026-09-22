-- Tenant da demo e os dois usuarios. Crie os usuarios antes no Supabase Auth
-- (diretor@demo.com e gerente.aurora@demo.com) e cole os UUIDs abaixo.

insert into app.tenant (id, razao_social, cnpj, conta_origem)
values ('11111111-1111-1111-1111-111111111111', 'Construtora Demo Ltda', '12.345.678/0001-90', 'demo')
on conflict do nothing;

insert into app.centro_custo (tenant_id, id_origem, nome, empresa_id) values
  ('11111111-1111-1111-1111-111111111111', 101, 'Residencial Aurora', 1),
  ('11111111-1111-1111-1111-111111111111', 102, 'Parque das Aguas', 1),
  ('11111111-1111-1111-1111-111111111111', 103, 'Torre Comercial Sul', 1)
on conflict do nothing;

-- Substituir pelos ids reais de auth.users
-- insert into app.usuario_tenant values ('<uuid diretor>', '11111111-1111-1111-1111-111111111111', 'diretor');
-- insert into app.usuario_tenant values ('<uuid gerente>', '11111111-1111-1111-1111-111111111111', 'gerente_obra');
-- insert into app.usuario_centro_custo
--   select '<uuid gerente>', tenant_id, id from app.centro_custo where id_origem = 101;
