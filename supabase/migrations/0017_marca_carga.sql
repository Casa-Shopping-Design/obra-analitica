-- Carga incremental do ERP de origem (decisão 0005). Só o carregador lê e grava estas tabelas,
-- com a conexão do dono do banco; nenhum usuário do painel enxerga marca ou modo de carga.

-- Data de referência da última carga confirmada, por tenant e endpoint. Avança na mesma
-- transação que grava os registros do endpoint, então nunca fica à frente do que está em raw.
create table app.marca_carga (
  tenant_id uuid not null references app.tenant(id) on delete cascade,
  endpoint text not null,
  ultima_referencia date not null,
  atualizado_em timestamptz not null default now(),
  primary key (tenant_id, endpoint)
);

-- Pacote sem Bulk-Data responde 403 no bulk. O tenant fica marcado para o caminho só REST
-- e o carregador tenta o Bulk de novo depois de alguns dias, caso o cliente mude de pacote.
create table app.modo_carga (
  tenant_id uuid primary key references app.tenant(id) on delete cascade,
  so_rest boolean not null,
  verificado_em timestamptz not null default now()
);

-- Sem política: authenticated e anon não leem nem gravam. O carregador usa o dono do banco.
alter table app.marca_carga enable row level security;
alter table app.marca_carga force row level security;
alter table app.modo_carga enable row level security;
alter table app.modo_carga force row level security;
revoke all on app.marca_carga from public, anon, authenticated;
revoke all on app.modo_carga from public, anon, authenticated;

-- Identidade do registro na origem (por exemplo título e parcela). Na carga incremental a versão
-- nova de um registro substitui a antiga pela chave; sem isso o staging receberia duas linhas
-- da mesma parcela e quebraria a chave primária. Nula nos registros gravados pela carga da demo.
alter table raw.registro add column chave_origem text;
create index registro_chave_origem_idx on raw.registro (tenant_id, endpoint, chave_origem)
  where chave_origem is not null;
