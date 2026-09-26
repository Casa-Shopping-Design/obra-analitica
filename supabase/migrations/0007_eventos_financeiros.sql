-- Eventos financeiros por linha: cada recebimento, cada pagamento e cada parte do rateio de um título
-- vira uma linha no staging, e o que não tem obra vai para o centro "Despesas sem obra" do tenant.
-- Contrato: docs/financeiro/contrato_dados.md, seção 3.1. Decisão: docs/decisoes/0002-eventos-financeiros.md.

-- Centro de custo da empresa: recebe título e parcela sem obra cadastrada. Gerente não tem vínculo com ele,
-- então só diretor e financeiro o enxergam pela regra de app.obras_permitidas().
alter table app.centro_custo add column tipo text not null default 'obra' check (tipo in ('obra', 'empresa'));
alter table app.centro_custo alter column id_origem drop not null;
alter table app.centro_custo add constraint centro_custo_tipo_origem
  check ((tipo = 'obra' and id_origem is not null) or (tipo = 'empresa' and id_origem is null));
create unique index centro_custo_empresa_unico on app.centro_custo (tenant_id) where tipo = 'empresa';
create index centro_custo_tenant_tipo on app.centro_custo (tenant_id, tipo);

insert into app.centro_custo (tenant_id, id_origem, nome, tipo)
select id, null, 'Despesas sem obra', 'empresa' from app.tenant
on conflict (tenant_id) where tipo = 'empresa' do nothing;

-- Auditoria comum das tabelas de complemento manual (0011 e 0012 usam os mesmos gatilhos).
create table app.auditoria_alteracao (
  id bigserial primary key,
  tenant_id uuid not null,
  tabela text not null,
  registro_id text not null,
  operacao text not null check (operacao in ('insert', 'update', 'delete')),
  antes jsonb,
  depois jsonb,
  autor uuid,
  alterado_em timestamptz not null default now()
);
create index auditoria_alteracao_registro on app.auditoria_alteracao (tenant_id, tabela, registro_id, alterado_em desc);
-- Últimas alterações por tabela, lidas pela tela de configurações.
create index auditoria_alteracao_tabela_data on app.auditoria_alteracao (tenant_id, tabela, alterado_em desc);

alter table app.auditoria_alteracao enable row level security;
alter table app.auditoria_alteracao force row level security;
create policy leitura_diretor_financeiro on app.auditoria_alteracao
  for select to authenticated
  using (tenant_id = (select app.tenant_atual()) and (select app.perfil_atual()) in ('diretor', 'financeiro'));
grant select on app.auditoria_alteracao to authenticated;

-- security definer porque o usuário não tem insert na auditoria; TG_ARGV traz as colunas da chave.
create function app.registrar_auditoria() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  linha jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
begin
  insert into app.auditoria_alteracao (tenant_id, tabela, registro_id, operacao, antes, depois, autor)
  values (
    (linha ->> 'tenant_id')::uuid,
    tg_table_schema || '.' || tg_table_name,
    (select string_agg(linha ->> chave.coluna, '|' order by chave.posicao)
     from unnest(tg_argv) with ordinality as chave(coluna, posicao)),
    lower(tg_op),
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end,
    auth.uid()
  );
  return null;
end $$;
revoke execute on function app.registrar_auditoria() from public, anon, authenticated;

-- O autor mandado pelo usuário logado é sempre trocado pelo do JWT. Sem JWT (carregador ou dono
-- do banco) o valor informado fica, para a carga poder gravar mapeamentos iniciais.
create function app.definir_autor() returns trigger
language plpgsql security invoker set search_path = '' as $$
declare
  ajuste jsonb := '{}'::jsonb;
begin
  if auth.uid() is not null or current_user in ('authenticated', 'anon') then
    ajuste := jsonb_build_object('autor', auth.uid());
  end if;
  if to_jsonb(new) ? 'atualizado_em' then
    ajuste := ajuste || jsonb_build_object('atualizado_em', now());
  end if;
  new := jsonb_populate_record(new, ajuste);
  return new;
end $$;
revoke execute on function app.definir_autor() from public, anon, authenticated;

-- Configuração por cliente (docs/financeiro/configuracao.md). Três níveis: padrão do catálogo, valor do
-- tenant e valor da obra; a obra vence o tenant e o tenant vence o padrão. Todo padrão reproduz o
-- comportamento anterior à configuração, então instalar esta parte não muda nenhum número.

-- Catálogo global: uma linha por parâmetro, sem tenant e sem escrita pela API.
create table app.parametro (
  codigo text primary key check (codigo ~ '^[a-z_]+\.[a-z_]+$'),
  grupo text not null check (grupo in ('reconhecimento', 'dre', 'caixa', 'financiamento', 'comercial', 'simulacao',
                                       'negocio', 'alerta', 'exibicao')),
  nome text not null,
  descricao text not null,
  tipo text not null check (tipo in ('opcao', 'booleano', 'numero', 'inteiro', 'fracao', 'texto', 'data', 'fuso')),
  opcoes jsonb,
  minimo numeric,
  maximo numeric,
  padrao jsonb not null,
  aceita_nulo boolean not null default false,
  escopo text not null check (escopo in ('tenant', 'tenant_e_obra')),
  ordem integer not null unique,
  exige_validacao_financeira boolean not null default false,
  constraint parametro_opcoes check ((tipo = 'opcao' and jsonb_typeof(opcoes) = 'array') or (tipo <> 'opcao' and opcoes is null)),
  constraint parametro_nulo check (jsonb_typeof(padrao) <> 'null' or aceita_nulo)
);

alter table app.parametro enable row level security;
alter table app.parametro force row level security;
create policy leitura_autenticado on app.parametro
  for select to authenticated
  using ((select auth.uid()) is not null);
grant select on app.parametro to authenticated;

-- Padrões de simulação: os valores iniciais do formulário de simulação do painel (painel/lib/simulacao.ts),
-- porque marts.simular_fluxo exige composição quando há novas vendas e não tem padrão próprio para ela.
insert into app.parametro (codigo, grupo, nome, descricao, tipo, opcoes, minimo, maximo, padrao, aceita_nulo, escopo, ordem,
                           exige_validacao_financeira) values
  ('negocio.fuso_horario', 'negocio', 'Fuso horário',
   'Decide o dia de referência das telas: o que já venceu, o mês corrente e o próximo mês mudam à meia-noite deste fuso.',
   'fuso', null, null, null, '"America/Sao_Paulo"', false, 'tenant', 10, false),
  ('alerta.carga_desatualizada_horas', 'alerta', 'Horas até a carga ficar atrasada',
   'Passado esse tempo desde a última carga, as telas avisam que os números podem estar desatualizados.',
   'inteiro', null, 1, 168, '26', false, 'tenant', 20, false),
  ('reconhecimento.base_fracao_vendida', 'reconhecimento', 'Base da fração vendida',
   'Como se mede a parte vendida da obra no custo reconhecido.',
   'opcao', '[{"valor": "unidades", "rotulo": "Unidades", "descricao": "Unidades vendidas sobre o total de unidades da obra."},
              {"valor": "area_privativa", "rotulo": "Área privativa", "descricao": "Área privativa vendida sobre a área privativa total."},
              {"valor": "valor_tabela", "rotulo": "Valor de tabela", "descricao": "Valor de tabela das unidades vendidas sobre o de todas as unidades."}]',
   null, null, '"unidades"', false, 'tenant_e_obra', 30, true),
  ('reconhecimento.incluir_terreno', 'reconhecimento', 'Terreno no percentual de conclusão',
   'Com sim, o custo do terreno entra no custo incorrido e no custo total do percentual de conclusão.',
   'booleano', null, null, null, 'true', false, 'tenant_e_obra', 40, true),
  ('reconhecimento.cobertura_minima', 'reconhecimento', 'Cobertura mínima do custo classificado',
   'O percentual de conclusão só é calculado quando ao menos esta fração do custo acumulado tem categoria. A cobertura real aparece sempre.',
   'fracao', null, 0.5, 1, '1', false, 'tenant_e_obra', 50, true),
  ('reconhecimento.exigir_validacao_usuario', 'reconhecimento', 'Critério validado por um usuário',
   'Com sim, o percentual de conclusão só vale depois que alguém do financeiro valida o critério; o que a carga grava fica como não definido.',
   'booleano', null, null, null, 'true', false, 'tenant', 60, true),
  ('dre.competencia_titulo', 'dre', 'Competência dos títulos a pagar',
   'Data que decide em que mês a despesa entra no DRE e na despesa mensal.',
   'opcao', '[{"valor": "emissao", "rotulo": "Emissão", "descricao": "Título sem data de emissão fica sem competência."},
              {"valor": "emissao_ou_vencimento", "rotulo": "Emissão ou vencimento", "descricao": "Usa a emissão e, sem ela, o vencimento."},
              {"valor": "vencimento", "rotulo": "Vencimento", "descricao": "Usa sempre o vencimento."}]',
   null, null, '"emissao"', false, 'tenant', 70, true),
  ('caixa.receber_vencido', 'caixa', 'Parcelas vencidas no fluxo projetado',
   'Define se o que o comprador deve e não pagou entra no caixa projetado.',
   'opcao', '[{"valor": "excluir", "rotulo": "Deixar fora", "descricao": "O vencido aparece à parte e não soma no caixa."},
              {"valor": "mes_referencia", "rotulo": "Somar no mês atual", "descricao": "O vencido entra no mês de referência, multiplicado pela fração de recuperação."}]',
   null, null, '"excluir"', false, 'tenant_e_obra', 80, false),
  ('caixa.fracao_recuperacao_vencido', 'caixa', 'Fração do vencido que se espera receber',
   'Vale quando as parcelas vencidas entram no mês atual: 1 soma o vencido inteiro, 0,5 soma metade.',
   'fracao', null, 0, 1, '1', false, 'tenant_e_obra', 90, false),
  ('caixa.pagar_vencido', 'caixa', 'Contas vencidas no fluxo projetado',
   'Define se o título a pagar vencido e não pago sai do caixa projetado.',
   'opcao', '[{"valor": "mes_referencia", "rotulo": "Considerar no mês atual", "descricao": "O vencido sai do caixa no mês de referência."},
              {"valor": "excluir", "rotulo": "Deixar fora", "descricao": "O vencido aparece à parte e não sai do caixa projetado."}]',
   null, null, '"mes_referencia"', false, 'tenant_e_obra', 100, false),
  ('caixa.financiamento_pendente', 'caixa', 'Financiamento pendente no caixa principal',
   'Parcelas de financiamento sem contratação ou com etapa pendente. A variante conservadora do fluxo nunca as inclui.',
   'opcao', '[{"valor": "incluir", "rotulo": "Incluir", "descricao": "Entram no caixa principal no mês previsto."},
              {"valor": "excluir", "rotulo": "Deixar fora", "descricao": "Só aparecem à parte."}]',
   null, null, '"incluir"', false, 'tenant_e_obra', 110, false),
  ('caixa.liberacao_pendente', 'caixa', 'Liberação pendente de crédito à produção',
   'Define se a liberação marcada como pendente entra no previsto.',
   'opcao', '[{"valor": "excluir", "rotulo": "Deixar fora", "descricao": "Só a liberação prevista entra no previsto."},
              {"valor": "incluir", "rotulo": "Incluir", "descricao": "A pendente também entra, na data prevista."}]',
   null, null, '"excluir"', false, 'tenant_e_obra', 120, false),
  ('caixa.liberacao_atrasada', 'caixa', 'Liberação prevista já vencida',
   'Liberação com data prevista no passado e sem recebimento.',
   'opcao', '[{"valor": "excluir", "rotulo": "Deixar fora", "descricao": "Aparece como atrasada e não entra no caixa."},
              {"valor": "mes_referencia", "rotulo": "Somar no mês atual", "descricao": "Entra no mês de referência."}]',
   null, null, '"excluir"', false, 'tenant_e_obra', 130, false),
  ('caixa.custo_sem_titulo_passado', 'caixa', 'Custo sem título de meses encerrados',
   'Parte da premissa de distribuição do custo que caía em meses já encerrados.',
   'opcao', '[{"valor": "mes_referencia", "rotulo": "Somar no mês atual", "descricao": "Entra como saída do mês de referência."},
              {"valor": "ignorar", "rotulo": "Ignorar", "descricao": "Não entra no fluxo projetado."}]',
   null, null, '"mes_referencia"', false, 'tenant_e_obra', 140, false),
  ('caixa.consolidado_compensa_obras', 'caixa', 'Abrir o fluxo pelo consolidado',
   'Com sim, a tela de fluxo abre na série consolidada, em que a sobra de uma obra cobre a falta de outra, e no aporte consolidado. Com não, abre na lista por obra.',
   'booleano', null, null, null, 'false', false, 'tenant', 150, false),
  ('financiamento.data_origem_significa', 'financiamento', 'Data do banco no contrato',
   'O que a data de financiamento informada no contrato de venda indica.',
   'opcao', '[{"valor": "contratacao", "rotulo": "Contratação", "descricao": "O financiamento fica elegível, ainda não liberado."},
              {"valor": "repasse", "rotulo": "Repasse", "descricao": "O financiamento conta como liberado."}]',
   null, null, '"contratacao"', false, 'tenant', 160, true),
  ('financiamento.retencao_padrao', 'financiamento', 'Retenção padrão do banco',
   'Retenção usada quando a operação de crédito não informa a própria. Em branco, nenhuma retenção é presumida.',
   'fracao', null, 0, 0.5, 'null', true, 'tenant_e_obra', 170, false),
  ('comercial.meta_metodo', 'comercial', 'Meta de vendas',
   'Meta digitada no planejamento ou calculada todo mês a partir do que falta vender.',
   'opcao', '[{"valor": "manual", "rotulo": "Manual", "descricao": "Vale a meta gravada no planejamento."},
              {"valor": "automatica", "rotulo": "Automática", "descricao": "O que falta vender dividido pelos meses até o prazo, refeito todo mês."}]',
   null, null, '"manual"', false, 'tenant_e_obra', 180, false),
  ('comercial.meta_horizonte', 'comercial', 'Prazo da meta automática',
   'Até quando a meta automática distribui o que falta vender.',
   'opcao', '[{"valor": "chaves", "rotulo": "Entrega das chaves", "descricao": "Usa a maior data de entrega das unidades."},
              {"valor": "data_propria", "rotulo": "Data informada", "descricao": "Usa a data final da meta automática."}]',
   null, null, '"chaves"', false, 'tenant_e_obra', 190, false),
  ('comercial.meta_data_horizonte', 'comercial', 'Data final da meta automática',
   'Usada quando o prazo da meta automática é uma data informada.',
   'data', null, null, null, 'null', true, 'tenant_e_obra', 200, false),
  ('comercial.meta_base', 'comercial', 'Base da meta automática',
   'Valor que as vendas precisam alcançar na meta automática.',
   'opcao', '[{"valor": "custo_orcado", "rotulo": "Custo orçado", "descricao": "Orçamento vigente da obra."},
              {"valor": "estimativa_conclusao", "rotulo": "Estimativa até a conclusão", "descricao": "Custo lançado mais o custo que ainda não virou título."}]',
   null, null, '"custo_orcado"', false, 'tenant_e_obra', 210, false),
  ('simulacao.desconto', 'simulacao', 'Desconto sobre a tabela',
   'Desconto inicial do formulário de simulação e da simulação que não informa desconto.',
   'fracao', null, 0, 0.5, '0', false, 'tenant_e_obra', 220, false),
  ('simulacao.fracao_entrada', 'simulacao', 'Entrada',
   'Parte do preço paga na entrada. Entrada, parcelas mensais e financiamento somam 100%.',
   'fracao', null, 0, 1, '0.10', false, 'tenant_e_obra', 230, false),
  ('simulacao.fracao_parcelas', 'simulacao', 'Parcelas mensais',
   'Parte do preço paga em parcelas mensais. Entrada, parcelas mensais e financiamento somam 100%.',
   'fracao', null, 0, 1, '0.30', false, 'tenant_e_obra', 240, false),
  ('simulacao.fracao_financiamento', 'simulacao', 'Financiamento',
   'Parte do preço paga pelo banco. Entrada, parcelas mensais e financiamento somam 100%.',
   'fracao', null, 0, 1, '0.60', false, 'tenant_e_obra', 250, false),
  ('simulacao.quantidade_parcelas', 'simulacao', 'Quantidade de parcelas mensais',
   'Número de parcelas mensais das vendas simuladas.',
   'inteiro', null, 1, 600, '24', false, 'tenant_e_obra', 260, false),
  ('simulacao.meses_ate_liberacao', 'simulacao', 'Meses até a liberação do financiamento',
   'Meses entre a venda simulada e a entrada do dinheiro do banco.',
   'inteiro', null, 0, 600, '4', false, 'tenant_e_obra', 270, false),
  ('exibicao.periodo_padrao', 'exibicao', 'Período inicial dos demonstrativos',
   'Período que as telas de DRE, receitas e despesas mostram ao abrir.',
   'opcao', '[{"valor": "mes", "rotulo": "Mês", "descricao": "O mês de referência."},
              {"valor": "trimestre", "rotulo": "Trimestre", "descricao": "O trimestre do mês de referência."},
              {"valor": "ano_ate_mes", "rotulo": "Ano até o mês", "descricao": "De janeiro até o mês de referência."},
              {"valor": "ultimos_12", "rotulo": "Últimos 12 meses", "descricao": "Os 12 meses até o mês de referência."}]',
   null, null, '"ano_ate_mes"', false, 'tenant', 280, false),
  ('exibicao.meses_grafico', 'exibicao', 'Meses nos gráficos de fluxo',
   'Quantos meses os gráficos de fluxo mostram.',
   'inteiro', null, 12, 120, '36', false, 'tenant', 290, false);

-- Devolve a mensagem de erro, ou nulo quando o valor serve. Serve ao gatilho e confere os padrões do catálogo.
create function app.erro_valor_parametro(p_codigo text, p_valor jsonb) returns text
language plpgsql stable security invoker set search_path = '' as $$
declare
  p app.parametro%rowtype;
  v_tipo text := jsonb_typeof(p_valor);
  v_numero numeric;
  v_texto text;
begin
  select * into p from app.parametro where codigo = p_codigo;
  if not found then
    return format('o parâmetro %s não existe', p_codigo);
  end if;
  if p_valor is null or v_tipo = 'null' then
    return case when p.aceita_nulo then null else format('%s precisa de um valor', p.nome) end;
  end if;

  if p.tipo in ('numero', 'inteiro', 'fracao') then
    if v_tipo <> 'number' then
      return format('%s precisa ser um número', p.nome);
    end if;
    v_numero := p_valor::numeric;
    if p.tipo = 'inteiro' and v_numero <> trunc(v_numero) then
      return format('%s precisa ser um número inteiro', p.nome);
    end if;
    if p.tipo = 'fracao' and v_numero <> round(v_numero, 6) then
      return format('%s aceita no máximo seis casas decimais', p.nome);
    end if;
    if v_numero < coalesce(p.minimo, v_numero) or v_numero > coalesce(p.maximo, v_numero) then
      return format('%s precisa ficar entre %s e %s', p.nome, p.minimo, p.maximo);
    end if;
    return null;
  end if;

  if p.tipo = 'booleano' then
    return case when v_tipo = 'boolean' then null else format('%s precisa ser sim ou não', p.nome) end;
  end if;

  if v_tipo <> 'string' then
    return format('%s precisa ser um texto', p.nome);
  end if;
  v_texto := p_valor #>> '{}';

  if p.tipo = 'opcao' and not exists (select 1 from jsonb_array_elements(p.opcoes) o where o ->> 'valor' = v_texto) then
    return format('%s não aceita a opção %s', p.nome, v_texto);
  elsif p.tipo = 'fuso' and not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = v_texto) then
    return format('%s não reconhece o fuso %s', p.nome, v_texto);
  elsif p.tipo = 'texto' and length(v_texto) > 500 then
    return format('%s aceita até 500 caracteres', p.nome);
  elsif p.tipo = 'data' then
    if v_texto !~ '^\d{4}-\d{2}-\d{2}$' then
      return format('%s precisa ser uma data no formato AAAA-MM-DD', p.nome);
    end if;
    begin
      perform v_texto::date;
    exception when others then
      return format('%s precisa ser uma data válida', p.nome);
    end;
  end if;
  return null;
end $$;
revoke execute on function app.erro_valor_parametro(text, jsonb) from public, anon;
grant execute on function app.erro_valor_parametro(text, jsonb) to authenticated;

do $$
declare v_erro text;
begin
  select string_agg(p.codigo || ': ' || app.erro_valor_parametro(p.codigo, p.padrao), '; ') into v_erro
  from app.parametro p
  where app.erro_valor_parametro(p.codigo, p.padrao) is not null;
  if v_erro is not null then
    raise exception 'padrão inválido no catálogo: %', v_erro;
  end if;
end $$;

-- Valor por tenant (centro nulo) ou por obra. Excluir a linha volta ao nível de cima.
create table app.parametro_valor (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenant(id) on delete cascade,
  centro_custo_id uuid references app.centro_custo(id) on delete cascade,
  codigo text not null references app.parametro(codigo),
  valor jsonb not null,
  observacao text,
  autor uuid not null,
  atualizado_em timestamptz not null default now(),
  constraint parametro_valor_unico unique nulls not distinct (tenant_id, centro_custo_id, codigo)
);
create index parametro_valor_obra on app.parametro_valor (centro_custo_id) where centro_custo_id is not null;
create index parametro_valor_codigo on app.parametro_valor (codigo);

create function app.validar_parametro_valor() returns trigger
language plpgsql security invoker set search_path = '' as $$
declare
  v_erro text := app.erro_valor_parametro(new.codigo, new.valor);
  v_escopo text;
  v_exige_observacao boolean;
begin
  if v_erro is not null then
    raise exception '%', v_erro using errcode = '23514';
  end if;
  select p.escopo, p.exige_validacao_financeira into v_escopo, v_exige_observacao
  from app.parametro p where p.codigo = new.codigo;
  if new.centro_custo_id is not null then
    if v_escopo <> 'tenant_e_obra' then
      raise exception 'o parâmetro % vale para a construtora inteira e não aceita valor por obra', new.codigo
        using errcode = '23514';
    end if;
    if not exists (select 1 from app.centro_custo cc
                   where cc.id = new.centro_custo_id and cc.tenant_id = new.tenant_id and cc.tipo = 'obra') then
      raise exception 'valor por obra só vale para uma obra da mesma construtora' using errcode = '23514';
    end if;
  end if;
  if v_exige_observacao and coalesce(btrim(new.observacao), '') = '' then
    raise exception 'o parâmetro % muda números do financeiro; informe a observação', new.codigo using errcode = '23514';
  end if;
  return new;
end $$;
revoke execute on function app.validar_parametro_valor() from public, anon, authenticated;

-- Entrada, parcelas e financiamento da simulação somam 1 em todo nível que tiver valor gravado. Confere
-- depois da instrução, para a tela gravar as três frações de uma vez; é adiável para quem grava em várias.
create function app.conferir_composicao_simulacao() returns trigger
language plpgsql security invoker set search_path = '' as $$
declare
  v_linha app.parametro_valor%rowtype;
  v_soma numeric;
begin
  v_linha := case when tg_op = 'DELETE' then old else new end;
  if v_linha.codigo not in ('simulacao.fracao_entrada', 'simulacao.fracao_parcelas', 'simulacao.fracao_financiamento') then
    return null;
  end if;
  select soma into v_soma
  from (
    select pt.simulacao__fracao_entrada + pt.simulacao__fracao_parcelas + pt.simulacao__fracao_financiamento as soma
    from app.parametros_tenant pt
    where pt.tenant_id = v_linha.tenant_id
    union all
    select po.simulacao__fracao_entrada + po.simulacao__fracao_parcelas + po.simulacao__fracao_financiamento
    from app.parametros_obra po
    where po.tenant_id = v_linha.tenant_id
      and (v_linha.centro_custo_id is null or po.centro_custo_id = v_linha.centro_custo_id)
  ) niveis
  where soma <> 1
  limit 1;
  if v_soma is not null then
    raise exception 'entrada, parcelas mensais e financiamento da simulação somam %, e precisam somar 1 (100%%)', v_soma
      using errcode = '23514';
  end if;
  return null;
end $$;
revoke execute on function app.conferir_composicao_simulacao() from public, anon, authenticated;

create trigger definir_autor before insert or update on app.parametro_valor
  for each row execute function app.definir_autor();
create trigger validar_valor before insert or update on app.parametro_valor
  for each row execute function app.validar_parametro_valor();
create trigger registrar_auditoria after insert or update or delete on app.parametro_valor
  for each row execute function app.registrar_auditoria('id');
create constraint trigger conferir_composicao_simulacao after insert or update or delete on app.parametro_valor
  deferrable initially immediate
  for each row execute function app.conferir_composicao_simulacao();

alter table app.parametro_valor enable row level security;
alter table app.parametro_valor force row level security;
create policy leitura_por_obra on app.parametro_valor
  for select to authenticated
  using (tenant_id = (select app.tenant_atual())
         and (centro_custo_id is null or centro_custo_id in (select app.obras_permitidas())));
create policy inclusao_diretor_financeiro on app.parametro_valor
  for insert to authenticated
  with check (tenant_id = (select app.tenant_atual())
              and (centro_custo_id is null or centro_custo_id in (select app.obras_permitidas()))
              and (select app.perfil_atual()) in ('diretor', 'financeiro'));
create policy alteracao_diretor_financeiro on app.parametro_valor
  for update to authenticated
  using (tenant_id = (select app.tenant_atual())
         and (centro_custo_id is null or centro_custo_id in (select app.obras_permitidas()))
         and (select app.perfil_atual()) in ('diretor', 'financeiro'))
  with check (tenant_id = (select app.tenant_atual())
              and (centro_custo_id is null or centro_custo_id in (select app.obras_permitidas()))
              and (select app.perfil_atual()) in ('diretor', 'financeiro'));
create policy exclusao_diretor_financeiro on app.parametro_valor
  for delete to authenticated
  using (tenant_id = (select app.tenant_atual())
         and (centro_custo_id is null or centro_custo_id in (select app.obras_permitidas()))
         and (select app.perfil_atual()) in ('diretor', 'financeiro'));
grant select, insert, update, delete on app.parametro_valor to authenticated;

-- Gera app.parametros_obra e app.parametros_tenant a partir do catálogo: uma coluna tipada por parâmetro,
-- com o código trocando "." por "__". Parâmetro novo entra por uma linha no catálogo e uma chamada desta
-- função numa migration; as colunas que já existem mantêm a posição, porque create or replace view só
-- aceita coluna nova no fim. O offset 0 impede o planejador de copiar a mescla dos três níveis para cada
-- coluna; sem ele, cada coluna repetiria as três subconsultas em cada linha.
create function app.gerar_views_parametros() returns void
language plpgsql security invoker set search_path = '' as $$
declare
  v_colunas text;
begin
  select string_agg(
           format('(e.valores -> %L #>> ''{}'')::%s as %I', p.codigo,
                  case p.tipo when 'booleano' then 'boolean' when 'numero' then 'numeric' when 'inteiro' then 'integer'
                              when 'fracao' then 'numeric(9,6)' when 'data' then 'date' else 'text' end,
                  replace(p.codigo, '.', '__')),
           ', ' order by coalesce(a.attnum, 32767), p.ordem)
  into v_colunas
  from app.parametro p
  left join pg_catalog.pg_attribute a
    on a.attrelid = pg_catalog.to_regclass('app.parametros_obra') and a.attname = replace(p.codigo, '.', '__')
   and not a.attisdropped;

  execute format($v$
    create or replace view app.parametros_obra with (security_invoker = true) as
    select cc.tenant_id, cc.id as centro_custo_id, %s
    from app.centro_custo cc
    cross join lateral (
      select (select jsonb_object_agg(p.codigo, p.padrao) from app.parametro p)
          || coalesce((select jsonb_object_agg(v.codigo, v.valor) from app.parametro_valor v
                       where v.tenant_id = cc.tenant_id and v.centro_custo_id is null), '{}')
          || coalesce((select jsonb_object_agg(v.codigo, v.valor) from app.parametro_valor v
                       where v.tenant_id = cc.tenant_id and v.centro_custo_id = cc.id), '{}') as valores
      offset 0
    ) e$v$, v_colunas);

  execute format($v$
    create or replace view app.parametros_tenant with (security_invoker = true) as
    select t.id as tenant_id, %s
    from app.tenant t
    cross join lateral (
      select (select jsonb_object_agg(p.codigo, p.padrao) from app.parametro p)
          || coalesce((select jsonb_object_agg(v.codigo, v.valor) from app.parametro_valor v
                       where v.tenant_id = t.id and v.centro_custo_id is null), '{}') as valores
      offset 0
    ) e$v$, v_colunas);
end $$;
revoke execute on function app.gerar_views_parametros() from public, anon, authenticated;

select app.gerar_views_parametros();
grant select on app.parametros_obra, app.parametros_tenant to authenticated;

-- Para a tela: o valor em vigor de cada parâmetro no nível do tenant e, nos de obra, em cada obra visível.
create view app.configuracao_efetiva with (security_invoker = true) as
select t.id as tenant_id, null::uuid as centro_custo_id, p.codigo,
       coalesce(vt.valor, p.padrao) as valor,
       case when vt.id is not null then 'tenant' else 'padrao' end as origem,
       vt.autor, vt.atualizado_em, vt.observacao
from app.tenant t
cross join app.parametro p
left join app.parametro_valor vt on vt.tenant_id = t.id and vt.centro_custo_id is null and vt.codigo = p.codigo
union all
select cc.tenant_id, cc.id, p.codigo,
       coalesce(vo.valor, vt.valor, p.padrao),
       case when vo.id is not null then 'obra' when vt.id is not null then 'tenant' else 'padrao' end,
       coalesce(vo.autor, vt.autor), coalesce(vo.atualizado_em, vt.atualizado_em),
       case when vo.id is not null then vo.observacao else vt.observacao end
from app.centro_custo cc
cross join app.parametro p
left join app.parametro_valor vt on vt.tenant_id = cc.tenant_id and vt.centro_custo_id is null and vt.codigo = p.codigo
left join app.parametro_valor vo on vo.tenant_id = cc.tenant_id and vo.centro_custo_id = cc.id and vo.codigo = p.codigo
where cc.tipo = 'obra' and p.escopo = 'tenant_e_obra';
grant select on app.configuracao_efetiva to authenticated;

-- Fuso do tenant de quem chama; sem JWT, o padrão do catálogo. security definer para a data de referência
-- não depender de privilégio de quem chama (service_role não lê o catálogo); devolve só o fuso do próprio tenant.
-- plpgsql, e não sql, porque as views chamam a data de referência uma vez por linha: função sql aninhada é
-- replanejada a cada chamada (130 µs), plpgsql guarda o plano na sessão (poucos µs).
create function app.fuso_horario_atual() returns text
language plpgsql stable security definer set search_path = '' as $$
declare
  v_tenant uuid := app.tenant_atual();
  v_fuso text;
begin
  if v_tenant is not null then
    select v.valor #>> '{}' into v_fuso
    from app.parametro_valor v
    where v.tenant_id = v_tenant and v.centro_custo_id is null and v.codigo = 'negocio.fuso_horario';
  end if;
  if v_fuso is null then
    select p.padrao #>> '{}' into v_fuso from app.parametro p where p.codigo = 'negocio.fuso_horario';
  end if;
  return v_fuso;
end $$;
revoke execute on function app.fuso_horario_atual() from public, anon;
grant execute on function app.fuso_horario_atual() to authenticated, service_role;

-- Valores aceitos por domínio de código da origem. valor_sem_mapa é o que vale para código ainda não mapeado.
create table app.valor_codigo_origem (
  dominio text not null check (dominio in ('condicao_pagamento', 'situacao_unidade', 'situacao_contrato')),
  valor text not null,
  rotulo text not null,
  ordem integer not null,
  valor_sem_mapa boolean not null default false,
  primary key (dominio, valor)
);
create unique index valor_codigo_origem_sem_mapa on app.valor_codigo_origem (dominio) where valor_sem_mapa;

insert into app.valor_codigo_origem (dominio, valor, rotulo, ordem, valor_sem_mapa) values
  ('condicao_pagamento', 'entrada_direta', 'Pago direto à construtora', 10, true),
  ('condicao_pagamento', 'financiamento_comprador', 'Financiamento do comprador', 20, false),
  ('situacao_unidade', 'disponivel', 'Disponível', 10, false),
  ('situacao_unidade', 'reservada', 'Reservada', 20, false),
  ('situacao_unidade', 'proposta', 'Em proposta', 30, false),
  ('situacao_unidade', 'vendida', 'Vendida', 40, false),
  ('situacao_unidade', 'fora_de_venda', 'Fora de venda', 50, true),
  ('situacao_contrato', 'ativo', 'Ativo', 10, false),
  ('situacao_contrato', 'distratado', 'Distratado', 20, false),
  ('situacao_contrato', 'outro', 'Fora das contas de contrato ativo', 30, true);

alter table app.valor_codigo_origem enable row level security;
alter table app.valor_codigo_origem force row level security;
create policy leitura_autenticado on app.valor_codigo_origem
  for select to authenticated
  using ((select auth.uid()) is not null);
grant select on app.valor_codigo_origem to authenticated;

-- Código do ERP de origem para o valor do produto, por tenant. O que não está aqui usa o valor_sem_mapa
-- e aparece em marts.pendencia_codigo_origem. autor nulo marca o padrão semeado pelo produto.
create table app.mapa_codigo_origem (
  tenant_id uuid not null references app.tenant(id) on delete cascade,
  dominio text not null check (dominio in ('condicao_pagamento', 'situacao_unidade', 'situacao_contrato')),
  codigo_origem text not null check (length(codigo_origem) between 1 and 40),
  valor text not null,
  rotulo text,
  observacao text,
  autor uuid,
  atualizado_em timestamptz not null default now(),
  primary key (tenant_id, dominio, codigo_origem),
  foreign key (dominio, valor) references app.valor_codigo_origem (dominio, valor)
);
create index mapa_codigo_origem_valor on app.mapa_codigo_origem (dominio, valor);

-- A chave estrangeira já barra o valor fora do domínio; o gatilho troca a mensagem por uma que diz o que usar.
create function app.validar_mapa_codigo_origem() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  if not exists (select 1 from app.valor_codigo_origem v where v.dominio = new.dominio and v.valor = new.valor) then
    raise exception 'o domínio % não aceita o valor %; use um destes: %', new.dominio, new.valor,
      coalesce((select string_agg(v.valor, ', ' order by v.ordem) from app.valor_codigo_origem v where v.dominio = new.dominio),
               'nenhum, o domínio não existe')
      using errcode = '23514';
  end if;
  return new;
end $$;
revoke execute on function app.validar_mapa_codigo_origem() from public, anon, authenticated;

create trigger definir_autor before insert or update on app.mapa_codigo_origem
  for each row execute function app.definir_autor();
create trigger validar_valor before insert or update on app.mapa_codigo_origem
  for each row execute function app.validar_mapa_codigo_origem();
-- A semeadura de tenant novo roda dentro do gatilho de app.tenant e não entra no histórico: é o estado
-- inicial, não uma alteração.
create trigger registrar_auditoria after insert or update or delete on app.mapa_codigo_origem
  for each row when (pg_trigger_depth() = 0)
  execute function app.registrar_auditoria('tenant_id', 'dominio', 'codigo_origem');

alter table app.mapa_codigo_origem enable row level security;
alter table app.mapa_codigo_origem force row level security;
create policy leitura_tenant on app.mapa_codigo_origem
  for select to authenticated
  using (tenant_id = (select app.tenant_atual()));
create policy inclusao_diretor_financeiro on app.mapa_codigo_origem
  for insert to authenticated
  with check (tenant_id = (select app.tenant_atual()) and (select app.perfil_atual()) in ('diretor', 'financeiro'));
create policy alteracao_diretor_financeiro on app.mapa_codigo_origem
  for update to authenticated
  using (tenant_id = (select app.tenant_atual()) and (select app.perfil_atual()) in ('diretor', 'financeiro'))
  with check (tenant_id = (select app.tenant_atual()) and (select app.perfil_atual()) in ('diretor', 'financeiro'));
create policy exclusao_diretor_financeiro on app.mapa_codigo_origem
  for delete to authenticated
  using (tenant_id = (select app.tenant_atual()) and (select app.perfil_atual()) in ('diretor', 'financeiro'));
grant select, insert, update, delete on app.mapa_codigo_origem to authenticated;

-- Padrão do produto: a regra que as views usavam antes do mapa.
create function app.semear_mapa_codigo_origem(p_tenant uuid) returns void
language sql security definer set search_path = '' as $$
  insert into app.mapa_codigo_origem (tenant_id, dominio, codigo_origem, valor, rotulo)
  select p_tenant, m.dominio, m.codigo_origem, m.valor, m.rotulo
  from (values
    ('condicao_pagamento', 'FI', 'financiamento_comprador', 'Financiamento'),
    ('condicao_pagamento', 'AT', 'entrada_direta', 'Sinal'),
    ('condicao_pagamento', 'PM', 'entrada_direta', 'Parcela mensal'),
    ('condicao_pagamento', 'BA', 'entrada_direta', 'Balão'),
    ('condicao_pagamento', 'CH', 'entrada_direta', 'Chaves'),
    ('situacao_unidade', 'D', 'disponivel', 'Disponível'),
    ('situacao_unidade', 'C', 'reservada', 'Reservada'),
    ('situacao_unidade', 'P', 'proposta', 'Proposta'),
    ('situacao_unidade', 'V', 'vendida', 'Vendida'),
    ('situacao_unidade', 'O', 'vendida', null),
    ('situacao_unidade', 'G', 'vendida', null),
    ('situacao_unidade', 'R', 'fora_de_venda', 'Reserva técnica'),
    ('situacao_contrato', '1', 'ativo', 'Ativo'),
    ('situacao_contrato', '3', 'distratado', 'Distratado')
  ) as m(dominio, codigo_origem, valor, rotulo)
  on conflict (tenant_id, dominio, codigo_origem) do nothing
$$;
revoke execute on function app.semear_mapa_codigo_origem(uuid) from public, anon, authenticated;

create function app.semear_tenant_novo() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform app.semear_mapa_codigo_origem(new.id);
  return null;
end $$;
revoke execute on function app.semear_tenant_novo() from public, anon, authenticated;

create trigger semear_mapa_codigo_origem after insert on app.tenant
  for each row execute function app.semear_tenant_novo();

select app.semear_mapa_codigo_origem(t.id) from app.tenant t;

-- Rótulo próprio do tenant para uma linha do DRE, uma categoria ou um indicador. Troca só o texto exibido;
-- a chave é a do produto (código da linha, da categoria ou do indicador) e a definição não muda.
create table app.rotulo_personalizado (
  tenant_id uuid not null references app.tenant(id) on delete cascade,
  contexto text not null check (contexto in ('linha_dre', 'categoria', 'indicador')),
  chave text not null check (chave ~ '^[a-z0-9_.]{1,80}$'),
  rotulo text not null check (length(btrim(rotulo)) between 1 and 80),
  autor uuid not null,
  atualizado_em timestamptz not null default now(),
  primary key (tenant_id, contexto, chave)
);

create trigger definir_autor before insert or update on app.rotulo_personalizado
  for each row execute function app.definir_autor();
create trigger registrar_auditoria after insert or update or delete on app.rotulo_personalizado
  for each row execute function app.registrar_auditoria('tenant_id', 'contexto', 'chave');

alter table app.rotulo_personalizado enable row level security;
alter table app.rotulo_personalizado force row level security;
create policy leitura_tenant on app.rotulo_personalizado
  for select to authenticated
  using (tenant_id = (select app.tenant_atual()));
create policy inclusao_diretor_financeiro on app.rotulo_personalizado
  for insert to authenticated
  with check (tenant_id = (select app.tenant_atual()) and (select app.perfil_atual()) in ('diretor', 'financeiro'));
create policy alteracao_diretor_financeiro on app.rotulo_personalizado
  for update to authenticated
  using (tenant_id = (select app.tenant_atual()) and (select app.perfil_atual()) in ('diretor', 'financeiro'))
  with check (tenant_id = (select app.tenant_atual()) and (select app.perfil_atual()) in ('diretor', 'financeiro'));
create policy exclusao_diretor_financeiro on app.rotulo_personalizado
  for delete to authenticated
  using (tenant_id = (select app.tenant_atual()) and (select app.perfil_atual()) in ('diretor', 'financeiro'));
grant select, insert, update, delete on app.rotulo_personalizado to authenticated;

-- Data de referência das views. Testes e reprocessamento fixam o dia por set_config; o usuário da API
-- não alcança set_config porque pg_catalog não é exposto. Sem data fixada, o dia no fuso do tenant.
-- Views das migrations seguintes chamam esta função uma vez por linha; o fuso fica guardado na transação
-- junto com os claims que o resolveram, e a consulta não refaz a busca a cada linha (3 µs por chamada, e não 15).
create function app.data_referencia() returns date
language plpgsql stable security invoker set search_path = '' as $$
declare
  v_fixada text := current_setting('app.data_referencia', true);
  v_claims text;
  v_fuso text;
begin
  if coalesce(v_fixada, '') <> '' then
    return v_fixada::date;
  end if;
  v_claims := coalesce(nullif(current_setting('request.jwt.claim', true), ''), current_setting('request.jwt.claims', true), '');
  -- set_config local volta como texto vazio (não nulo) ao fim da transação: vazio é cache ausente
  v_fuso := nullif(current_setting('app.fuso_valor', true), '');
  if v_fuso is null or current_setting('app.fuso_claims', true) is distinct from v_claims then
    v_fuso := app.fuso_horario_atual();
    perform set_config('app.fuso_claims', v_claims, true), set_config('app.fuso_valor', v_fuso, true);
  end if;
  return (now() at time zone v_fuso)::date;
end $$;
revoke execute on function app.data_referencia() from public, anon;
grant execute on function app.data_referencia() to authenticated, service_role;

-- Única implementação da situação da parcela; 0011 e 0012 chamam esta função.
create function app.situacao_parcela(p_saldo numeric, p_valor_recebido numeric, p_vencimento date,
                                     p_contrato_distratado boolean, p_referencia date) returns text
language sql immutable security invoker set search_path = '' as $$
  select case
    when coalesce(p_saldo, 0) > 0 and p_contrato_distratado then 'cancelada_distrato'
    when coalesce(p_saldo, 0) > 0 and p_vencimento < p_referencia then 'vencida'
    when coalesce(p_saldo, 0) > 0 then 'a_vencer'
    when coalesce(p_valor_recebido, 0) > 0 then 'quitada'
    else 'baixada_sem_recebimento'
  end
$$;
revoke execute on function app.situacao_parcela(numeric, numeric, date, boolean, date) from public, anon;
grant execute on function app.situacao_parcela(numeric, numeric, date, boolean, date) to authenticated, service_role;

create index registro_tenant_carregado on raw.registro (tenant_id, carregado_em desc);

-- security definer porque raw não é legível pelo usuário; devolve só o carimbo do tenant de quem chama.
-- O limite de horas vem de alerta.carga_desatualizada_horas do tenant, ou do padrão do catálogo.
create function app.situacao_carga()
returns table (data_referencia date, ultima_carga_em timestamptz, horas_desde_carga numeric(9,1), desatualizada boolean)
language sql stable security definer set search_path = '' as $$
  select app.data_referencia(),
         u.ultima,
         round(extract(epoch from now() - u.ultima) / 3600, 1)::numeric(9,1),
         u.ultima is null or now() - u.ultima > make_interval(hours => l.horas)
  from (select max(r.carregado_em) as ultima from raw.registro r where r.tenant_id = app.tenant_atual()) u
  cross join (
    select coalesce(
      (select (v.valor #>> '{}')::integer from app.parametro_valor v
        where v.tenant_id = app.tenant_atual() and v.centro_custo_id is null and v.codigo = 'alerta.carga_desatualizada_horas'),
      (select (p.padrao #>> '{}')::integer from app.parametro p where p.codigo = 'alerta.carga_desatualizada_horas')) as horas
  ) l
$$;
revoke execute on function app.situacao_carga() from public, anon;
grant execute on function app.situacao_carga() to authenticated;

-- Contrato de venda: financiamento e crédito associativo; todas as unidades do contrato em tabela própria.
alter table staging.contrato_venda
  add column valor_financiado numeric(18,2),
  add column credito_associativo boolean,
  add column situacao_normalizada text not null check (situacao_normalizada in ('ativo', 'distratado', 'outro'));
create index contrato_venda_obra_data on staging.contrato_venda (tenant_id, centro_custo_id, data_venda);
create index contrato_venda_unidade_ativa on staging.contrato_venda (tenant_id, unidade_id_origem, data_venda desc)
  where situacao_normalizada = 'ativo';

create table staging.contrato_unidade (
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  contrato_id_origem integer not null,
  sequencia integer not null,
  unidade_id_origem integer not null,
  principal boolean not null,
  primary key (tenant_id, contrato_id_origem, sequencia)
);
create index contrato_unidade_obra on staging.contrato_unidade (tenant_id, centro_custo_id);
create index contrato_unidade_unidade on staging.contrato_unidade (tenant_id, unidade_id_origem);

-- Parcela: valor_recebido passa a ser a soma dos recebimentos; parcela de obra não cadastrada vai para a empresa.
-- origem é gravada pela recarga a partir do mapa de códigos do tenant, não calculada pela condição FI.
alter table staging.parcela_receber alter column origem drop expression;
alter table staging.parcela_receber
  alter column origem set not null,
  add constraint parcela_receber_origem check (origem in ('direta', 'repasse'));
alter table staging.parcela_receber
  add column data_emissao date,
  add column numero_parcela text,
  add column conta_origem text,
  add column id_origem_obra integer,
  add column motivo_sem_obra text,
  add column valor_baixado_sem_caixa numeric(18,2) not null default 0;

create table staging.recebimento (
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  contrato_id_origem integer not null,
  parcela_id_origem integer not null,
  sequencia integer not null,
  data_recebimento date not null,
  valor numeric(18,2) not null,
  origem text not null,
  tipo_condicao text,
  tipo_operacao_origem text,
  tipo_baixa text not null check (tipo_baixa in ('recebimento', 'estorno', 'baixa_sem_caixa')),
  primary key (tenant_id, contrato_id_origem, parcela_id_origem, sequencia)
);
create index recebimento_obra_data on staging.recebimento (tenant_id, centro_custo_id, data_recebimento);

-- Título: o cabeçalho deixa de ser lido pelo usuário; obra, valor e pagamento vêm das apropriações.
alter table staging.titulo_pagar alter column centro_custo_id drop not null;
alter table staging.titulo_pagar
  add column empresa_id_origem integer,
  add column data_emissao date,
  add column valor_pago numeric(18,2) not null default 0,
  add column ajuste_baixa numeric(18,2) not null default 0,
  add column quantidade_apropriacoes integer not null default 1;
alter table staging.titulo_pagar alter column quantidade_apropriacoes drop default;
revoke select on staging.titulo_pagar from authenticated;

create table staging.titulo_pagar_apropriacao (
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  titulo_id_origem integer not null,
  sequencia_obra integer not null,
  sequencia_conta integer not null,
  id_origem_obra integer,
  motivo_sem_obra text check (motivo_sem_obra in ('sem_rateio_na_origem', 'rateio_sem_valor', 'obra_nao_cadastrada')),
  conta_origem text,
  percentual numeric(9,6) not null,
  principal boolean not null,
  valor_original numeric(18,2) not null,
  valor_pago numeric(18,2) not null,
  ajuste_baixa numeric(18,2) not null,
  saldo numeric(18,2) not null,
  vencimento date not null,
  data_competencia date,
  data_ultimo_pagamento date,
  primary key (tenant_id, titulo_id_origem, sequencia_obra, sequencia_conta)
);
create index apropriacao_obra_vencimento on staging.titulo_pagar_apropriacao (tenant_id, centro_custo_id, vencimento);
create index apropriacao_obra_competencia on staging.titulo_pagar_apropriacao (tenant_id, centro_custo_id, data_competencia);
create index apropriacao_conta on staging.titulo_pagar_apropriacao (tenant_id, conta_origem);

create table staging.pagamento (
  tenant_id uuid not null,
  centro_custo_id uuid not null,
  titulo_id_origem integer not null,
  sequencia_pagamento integer not null,
  sequencia_obra integer not null,
  sequencia_conta integer not null,
  data_pagamento date not null,
  valor numeric(18,2) not null,
  conta_origem text,
  primary key (tenant_id, titulo_id_origem, sequencia_pagamento, sequencia_obra, sequencia_conta)
);
create index pagamento_obra_data on staging.pagamento (tenant_id, centro_custo_id, data_pagamento);

do $$
declare t text;
begin
  foreach t in array array['contrato_unidade', 'recebimento', 'titulo_pagar_apropriacao', 'pagamento'] loop
    execute format('alter table staging.%I enable row level security', t);
    execute format('alter table staging.%I force row level security', t);
    execute format($p$create policy leitura_por_obra on staging.%I for select to authenticated
      using (tenant_id = (select app.tenant_atual()) and centro_custo_id in (select app.obras_permitidas()))$p$, t);
    execute format('grant select on staging.%I to authenticated', t);
  end loop;
end $$;

-- A recarga grava origem e situação normalizada numa instrução só. Estes gatilhos cobrem quem grava direto
-- no staging (testes e reprocessamento manual) sem informar a coluna, com a mesma regra do mapa.
create function staging.normalizar_parcela_receber() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  if (tg_op = 'INSERT' and new.origem is null)
     or (tg_op = 'UPDATE' and new.tipo_condicao is distinct from old.tipo_condicao and new.origem is not distinct from old.origem) then
    new.origem := case when exists (
                    select 1 from app.mapa_codigo_origem m
                    where m.tenant_id = new.tenant_id and m.dominio = 'condicao_pagamento'
                      and m.codigo_origem = new.tipo_condicao and m.valor = 'financiamento_comprador')
                  then 'repasse' else 'direta' end;
  end if;
  return new;
end $$;
revoke execute on function staging.normalizar_parcela_receber() from public, anon, authenticated;
create trigger normalizar_codigos before insert or update on staging.parcela_receber
  for each row execute function staging.normalizar_parcela_receber();

create function staging.normalizar_contrato_venda() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  if (tg_op = 'INSERT' and new.situacao_normalizada is null)
     or (tg_op = 'UPDATE' and new.situacao is distinct from old.situacao
         and new.situacao_normalizada is not distinct from old.situacao_normalizada) then
    new.situacao_normalizada := coalesce(
      (select m.valor from app.mapa_codigo_origem m
       where m.tenant_id = new.tenant_id and m.dominio = 'situacao_contrato' and m.codigo_origem = new.situacao),
      'outro');
  end if;
  return new;
end $$;
revoke execute on function staging.normalizar_contrato_venda() from public, anon, authenticated;
create trigger normalizar_codigos before insert or update on staging.contrato_venda
  for each row execute function staging.normalizar_contrato_venda();

-- Recarga do staging a partir do raw, por tenant, apagando e regravando. Uma instrução por grupo de
-- tabelas, sem laço por linha: O(n log n) em registros da origem, pela ordenação das janelas do rateio.
-- Condição de pagamento e situação do contrato passam pelo mapa de códigos do tenant; código sem mapa
-- fica com o valor_sem_mapa (entrada direta, outro) e aparece em marts.pendencia_codigo_origem.
-- jit desligado: o planejador estima 100 itens por lista jsonb, o custo passa do limite do JIT e a
-- compilação levava 2 s numa recarga que executa em menos de 150 ms.
create or replace function staging.recarregar(p_tenant uuid) returns void
language plpgsql security definer set search_path = '' set jit = off as $$
declare
  v_empresa uuid;
  v_recebimentos_sem_data bigint;
  v_pagamentos_sem_data bigint;
  v_titulos_sem_obra bigint;
  v_condicoes_financiamento text[];
begin
  insert into app.centro_custo (tenant_id, id_origem, nome, tipo)
  values (p_tenant, null, 'Despesas sem obra', 'empresa')
  on conflict (tenant_id) where tipo = 'empresa' do nothing;
  select cc.id into v_empresa from app.centro_custo cc where cc.tenant_id = p_tenant and cc.tipo = 'empresa';
  select coalesce(array_agg(m.codigo_origem), '{}') into v_condicoes_financiamento
  from app.mapa_codigo_origem m
  where m.tenant_id = p_tenant and m.dominio = 'condicao_pagamento' and m.valor = 'financiamento_comprador';

  delete from staging.unidade where tenant_id = p_tenant;
  delete from staging.contrato_unidade where tenant_id = p_tenant;
  delete from staging.contrato_venda where tenant_id = p_tenant;
  delete from staging.recebimento where tenant_id = p_tenant;
  delete from staging.parcela_receber where tenant_id = p_tenant;
  delete from staging.pagamento where tenant_id = p_tenant;
  delete from staging.titulo_pagar_apropriacao where tenant_id = p_tenant;
  delete from staging.titulo_pagar where tenant_id = p_tenant;
  delete from staging.item_orcamento where tenant_id = p_tenant;

  insert into staging.unidade
  select p_tenant, cc.id, (r.payload->>'id')::int, r.payload->>'name', r.payload->>'propertyType',
         (r.payload->>'privateArea')::numeric, r.payload->>'commercialStock', (r.payload->>'deliveryDate')::date
  from raw.registro r
  join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = (r.payload->>'enterpriseId')::int
  where r.tenant_id = p_tenant and r.endpoint = 'units';

  -- Unidade principal: a marcada como main; sem marcação, a primeira da lista.
  with contrato as (
    select cc.id as centro_custo_id, r.payload as pl, (r.payload->>'id')::int as contrato_id
    from raw.registro r
    join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = (r.payload->>'enterpriseId')::int
    where r.tenant_id = p_tenant and r.endpoint = 'sales'
  ), unidade_contrato as (
    select c.centro_custo_id, c.contrato_id, u.posicao::int as sequencia, (u.item->>'id')::int as unidade_id,
           row_number() over (partition by c.contrato_id
                              order by coalesce(u.item->>'main' = 'true', false) desc, u.posicao) = 1 as principal
    from contrato c
    cross join lateral jsonb_array_elements(
      case when jsonb_typeof(c.pl->'units') = 'array' then c.pl->'units' else '[]'::jsonb end
    ) with ordinality as u(item, posicao)
    where u.item->>'id' is not null
  ), grava_unidades as (
    insert into staging.contrato_unidade (tenant_id, centro_custo_id, contrato_id_origem, sequencia, unidade_id_origem, principal)
    select p_tenant, uc.centro_custo_id, uc.contrato_id, uc.sequencia, uc.unidade_id, uc.principal
    from unidade_contrato uc
  )
  insert into staging.contrato_venda
    (tenant_id, centro_custo_id, id_origem, numero, data_venda, valor, situacao, data_distrato, banco_repasse,
     data_repasse, nome_cliente, unidade_id_origem, valor_financiado, credito_associativo, situacao_normalizada)
  select p_tenant, c.centro_custo_id, c.contrato_id, c.pl->>'number', (c.pl->>'contractDate')::date,
         (c.pl->>'value')::numeric, c.pl->>'situation', (c.pl->>'cancellationDate')::date,
         c.pl->>'financialInstitutionNumber', (c.pl->>'financialInstitutionDate')::date,
         c.pl->'customers'->0->>'name',
         uc.unidade_id,
         case when jsonb_typeof(c.pl->'paymentConditions') = 'array' then
           coalesce((select sum((pc->>'totalValue')::numeric)
                     from jsonb_array_elements(c.pl->'paymentConditions') pc
                     where pc->>'conditionType' = any(v_condicoes_financiamento)), 0)
         end,
         case c.pl->>'associativeCredit' when 'S' then true when 'N' then false end,
         coalesce(ms.valor, 'outro')
  from contrato c
  left join unidade_contrato uc on uc.contrato_id = c.contrato_id and uc.principal
  left join app.mapa_codigo_origem ms
    on ms.tenant_id = p_tenant and ms.dominio = 'situacao_contrato' and ms.codigo_origem = c.pl->>'situation';

  -- Recebimentos e parcelas numa instrução: a parcela já nasce com a soma dos seus recebimentos.
  with parcela as (
    select r.payload as pl,
           (r.payload->>'billId')::int as contrato_id,
           (r.payload->>'installmentId')::int as parcela_id,
           (r.payload->>'projectId')::int as id_origem_obra,
           coalesce(cc.id, v_empresa) as centro_custo_id,
           case when cc.id is null then 'obra_nao_cadastrada' end as motivo_sem_obra,
           r.payload->'paymentTerm'->>'id' as tipo_condicao,
           case when r.payload->'paymentTerm'->>'id' = any(v_condicoes_financiamento) then 'repasse' else 'direta' end as origem
    from raw.registro r
    left join app.centro_custo cc
      on cc.tenant_id = p_tenant and cc.tipo = 'obra' and cc.id_origem = (r.payload->>'projectId')::int
    where r.tenant_id = p_tenant and r.endpoint = 'income'
  ), recebimento_bruto as (
    select p.contrato_id, p.parcela_id, p.centro_custo_id, p.tipo_condicao, p.origem, x.posicao::int as sequencia,
           (x.item->>'paymentDate')::date as data_recebimento,
           coalesce(x.item->>'netAmount', x.item->>'amount')::numeric as valor,
           x.item->>'operationTypeName' as tipo_operacao_origem
    from parcela p
    cross join lateral jsonb_array_elements(
      case when jsonb_typeof(p.pl->'receipts') = 'array' then p.pl->'receipts' else '[]'::jsonb end
    ) with ordinality as x(item, posicao)
  ), recebimento as (
    select rb.*,
           case when rb.valor < 0 then 'estorno' else 'recebimento' end as tipo_baixa
    from recebimento_bruto rb
    where rb.data_recebimento is not null and rb.valor is not null
  ), grava_recebimentos as (
    insert into staging.recebimento
      (tenant_id, centro_custo_id, contrato_id_origem, parcela_id_origem, sequencia, data_recebimento, valor,
       origem, tipo_condicao, tipo_operacao_origem, tipo_baixa)
    select p_tenant, rc.centro_custo_id, rc.contrato_id, rc.parcela_id, rc.sequencia, rc.data_recebimento, rc.valor,
           rc.origem, rc.tipo_condicao, rc.tipo_operacao_origem, rc.tipo_baixa
    from recebimento rc
  ), total_recebido as (
    select rc.contrato_id, rc.parcela_id,
           sum(rc.valor) filter (where rc.tipo_baixa in ('recebimento', 'estorno')) as valor_recebido,
           max(rc.data_recebimento) filter (where rc.tipo_baixa in ('recebimento', 'estorno')) as data_recebimento,
           sum(rc.valor) filter (where rc.tipo_baixa = 'baixa_sem_caixa') as valor_baixado_sem_caixa
    from recebimento rc
    group by rc.contrato_id, rc.parcela_id
  ), grava_parcelas as (
    insert into staging.parcela_receber
      (tenant_id, centro_custo_id, id_origem, contrato_id_origem, vencimento, valor_original, saldo, saldo_corrigido,
       tipo_condicao, origem, inadimplente, data_recebimento, valor_recebido, data_emissao, numero_parcela, conta_origem,
       id_origem_obra, motivo_sem_obra, valor_baixado_sem_caixa)
    select p_tenant, p.centro_custo_id, p.parcela_id, p.contrato_id, (p.pl->>'dueDate')::date,
           (p.pl->>'originalAmount')::numeric, (p.pl->>'balanceAmount')::numeric,
           (p.pl->>'correctedBalanceAmount')::numeric, p.tipo_condicao, p.origem, p.pl->>'defaulterSituation' = 'S',
           tr.data_recebimento, coalesce(tr.valor_recebido, 0),
           (p.pl->>'issueDate')::date, p.pl->>'installmentNumber',
           case when jsonb_typeof(p.pl->'receiptsCategories') = 'array'
                 and jsonb_array_length(p.pl->'receiptsCategories') = 1
                then p.pl->'receiptsCategories'->0->>'financialCategoryId' end,
           p.id_origem_obra, p.motivo_sem_obra, coalesce(tr.valor_baixado_sem_caixa, 0)
    from parcela p
    left join total_recebido tr on tr.contrato_id = p.contrato_id and tr.parcela_id = p.parcela_id
  )
  select count(*) filter (where rb.data_recebimento is null or rb.valor is null) into v_recebimentos_sem_data
  from recebimento_bruto rb;

  -- Rateio do título por obra e por conta. Cada valor V do título é repartido com round(V * p, 2) e a
  -- apropriação principal fica com o resto, então a soma das partes é sempre V. Pagamentos são
  -- repartidos pelo acumulado, para o título quitado fechar centavo a centavo em cada obra.
  with titulo as (
    select r.payload as pl,
           (r.payload->>'billId')::int as titulo_id,
           (r.payload->>'originalAmount')::numeric as valor_original,
           (r.payload->>'balanceAmount')::numeric as saldo_origem,
           (r.payload->>'dueDate')::date as vencimento,
           (r.payload->>'issueDate')::date as data_emissao,
           case when jsonb_typeof(r.payload->'buildingsCosts') = 'array'
                then jsonb_array_length(r.payload->'buildingsCosts') else 0 end as itens_rateio
    from raw.registro r
    where r.tenant_id = p_tenant and r.endpoint = 'outcome'
  ), obra_bruta as (
    select t.titulo_id, o.posicao::int as sequencia_obra, (o.item->>'buildingId')::int as id_origem_obra,
           (o.item->>'rate')::numeric as taxa, (o.item->>'amount')::numeric as valor
    from titulo t
    cross join lateral jsonb_array_elements(
      case when t.itens_rateio > 0 then t.pl->'buildingsCosts' else '[]'::jsonb end
    ) with ordinality as o(item, posicao)
  ), obra_peso as (
    -- percentual da origem só vale quando todos os itens o trazem; senão um item sem percentual sumiria do rateio
    select ob.titulo_id, ob.sequencia_obra, ob.id_origem_obra,
           case when bool_and(ob.taxa is not null) over (partition by ob.titulo_id) then ob.taxa else ob.valor end as peso
    from obra_bruta ob
  ), obra as (
    select op.titulo_id, op.sequencia_obra, op.id_origem_obra,
           op.peso / sum(op.peso) over (partition by op.titulo_id) as p_obra,
           null::text as motivo_sem_obra
    from obra_peso op
    where op.peso > 0
    union all
    select t.titulo_id, 1, null, 1::numeric,
           case when t.itens_rateio > 0 then 'rateio_sem_valor' else 'sem_rateio_na_origem' end
    from titulo t
    where not exists (select 1 from obra_peso op where op.titulo_id = t.titulo_id and op.peso > 0)
  ), obra_centro as (
    select o.titulo_id, o.sequencia_obra, o.id_origem_obra, o.p_obra,
           coalesce(cc.id, v_empresa) as centro_custo_id,
           coalesce(o.motivo_sem_obra, case when cc.id is null then 'obra_nao_cadastrada' end) as motivo_sem_obra
    from obra o
    left join app.centro_custo cc
      on cc.tenant_id = p_tenant and cc.tipo = 'obra' and cc.id_origem = o.id_origem_obra
  ), conta_bruta as (
    select t.titulo_id, c.posicao::int as sequencia_conta, c.item->>'financialCategoryId' as conta_origem,
           (c.item->>'financialCategoryRate')::numeric as peso
    from titulo t
    cross join lateral jsonb_array_elements(
      case when jsonb_typeof(t.pl->'paymentsCategories') = 'array' then t.pl->'paymentsCategories' else '[]'::jsonb end
    ) with ordinality as c(item, posicao)
  ), conta as (
    select cb.titulo_id, cb.sequencia_conta, cb.conta_origem,
           cb.peso / sum(cb.peso) over (partition by cb.titulo_id) as p_conta
    from conta_bruta cb
    where cb.peso > 0
    union all
    select t.titulo_id, 1, null, 1::numeric
    from titulo t
    where not exists (select 1 from conta_bruta cb where cb.titulo_id = t.titulo_id and cb.peso > 0)
  ), apropriacao as (
    select oc.titulo_id, oc.sequencia_obra, c.sequencia_conta, oc.centro_custo_id, oc.id_origem_obra,
           oc.motivo_sem_obra, c.conta_origem, oc.p_obra * c.p_conta as p,
           row_number() over (partition by oc.titulo_id
                              order by oc.p_obra * c.p_conta desc, oc.sequencia_obra, c.sequencia_conta) = 1 as principal,
           count(*) over (partition by oc.titulo_id) as quantidade
    from obra_centro oc
    join conta c on c.titulo_id = oc.titulo_id
  ), pagamento_bruto as (
    select t.titulo_id, pg.posicao::int as sequencia_pagamento,
           (pg.item->>'paymentDate')::date as data_pagamento,
           coalesce(pg.item->>'netAmount', pg.item->>'amount')::numeric as valor
    from titulo t
    cross join lateral jsonb_array_elements(
      case when jsonb_typeof(t.pl->'payments') = 'array' then t.pl->'payments' else '[]'::jsonb end
    ) with ordinality as pg(item, posicao)
  ), pagamento_valido as (
    select pb.*,
           sum(pb.valor) over (partition by pb.titulo_id order by pb.sequencia_pagamento) as acumulado
    from pagamento_bruto pb
    where pb.data_pagamento is not null and pb.valor is not null
  ), total_pago as (
    select pv.titulo_id, sum(pv.valor) as valor_pago, max(pv.data_pagamento) as data_ultimo_pagamento
    from pagamento_valido pv
    group by pv.titulo_id
  ), titulo_total as (
    select t.titulo_id, t.valor_original, t.vencimento, t.data_emissao, t.pl,
           coalesce(tp.valor_pago, 0) as valor_pago, tp.data_ultimo_pagamento,
           -- sem saldo na origem não há como separar desconto de saldo: o ajuste fica zero
           coalesce(t.valor_original - coalesce(tp.valor_pago, 0) - t.saldo_origem, 0) as ajuste_baixa
    from titulo t
    left join total_pago tp on tp.titulo_id = t.titulo_id
  ), apropriacao_arredondada as (
    select a.*, tt.vencimento, tt.data_emissao, tt.data_ultimo_pagamento, tt.valor_original as original_titulo,
           tt.valor_pago as pago_titulo, tt.ajuste_baixa as ajuste_titulo,
           round(tt.valor_original * a.p, 2) as original_arred,
           round(tt.valor_pago * a.p, 2) as pago_arred,
           round(tt.ajuste_baixa * a.p, 2) as ajuste_arred
    from apropriacao a
    join titulo_total tt on tt.titulo_id = a.titulo_id
  ), apropriacao_valor as (
    select aa.*,
           case when aa.principal then aa.original_titulo - (sum(aa.original_arred) over w - aa.original_arred)
                else aa.original_arred end as valor_original,
           case when aa.principal then aa.pago_titulo - (sum(aa.pago_arred) over w - aa.pago_arred)
                else aa.pago_arred end as valor_pago,
           case when aa.principal then aa.ajuste_titulo - (sum(aa.ajuste_arred) over w - aa.ajuste_arred)
                else aa.ajuste_arred end as ajuste_baixa
    from apropriacao_arredondada aa
    window w as (partition by aa.titulo_id)
  ), grava_apropriacoes as (
    insert into staging.titulo_pagar_apropriacao
      (tenant_id, centro_custo_id, titulo_id_origem, sequencia_obra, sequencia_conta, id_origem_obra, motivo_sem_obra,
       conta_origem, percentual, principal, valor_original, valor_pago, ajuste_baixa, saldo, vencimento,
       data_competencia, data_ultimo_pagamento)
    select p_tenant, av.centro_custo_id, av.titulo_id, av.sequencia_obra, av.sequencia_conta, av.id_origem_obra,
           av.motivo_sem_obra, av.conta_origem, round(av.p, 6), av.principal, av.valor_original, av.valor_pago,
           av.ajuste_baixa, av.valor_original - av.valor_pago - av.ajuste_baixa, av.vencimento, av.data_emissao,
           av.data_ultimo_pagamento
    from apropriacao_valor av
  ), pagamento_arredondado as (
    select pv.titulo_id, pv.sequencia_pagamento, pv.data_pagamento, pv.acumulado, pv.acumulado - pv.valor as anterior,
           a.sequencia_obra, a.sequencia_conta, a.centro_custo_id, a.conta_origem, a.principal,
           round(pv.acumulado * a.p, 2) as acumulado_arred,
           round((pv.acumulado - pv.valor) * a.p, 2) as anterior_arred
    from pagamento_valido pv
    join apropriacao a on a.titulo_id = pv.titulo_id
  ), grava_pagamentos as (
    insert into staging.pagamento
      (tenant_id, centro_custo_id, titulo_id_origem, sequencia_pagamento, sequencia_obra, sequencia_conta,
       data_pagamento, valor, conta_origem)
    select p_tenant, pa.centro_custo_id, pa.titulo_id, pa.sequencia_pagamento, pa.sequencia_obra, pa.sequencia_conta,
           pa.data_pagamento,
           case when pa.principal then pa.acumulado - (sum(pa.acumulado_arred) over w - pa.acumulado_arred)
                else pa.acumulado_arred end
           - case when pa.principal then pa.anterior - (sum(pa.anterior_arred) over w - pa.anterior_arred)
                  else pa.anterior_arred end,
           pa.conta_origem
    from pagamento_arredondado pa
    window w as (partition by pa.titulo_id, pa.sequencia_pagamento)
  ), grava_titulos as (
    insert into staging.titulo_pagar
      (tenant_id, centro_custo_id, id_origem, credor, vencimento, valor_original, saldo, data_pagamento,
       empresa_id_origem, data_emissao, valor_pago, ajuste_baixa, quantidade_apropriacoes)
    select p_tenant, a.centro_custo_id, tt.titulo_id, tt.pl->>'creditorName', tt.vencimento, tt.valor_original,
           (tt.pl->>'balanceAmount')::numeric, tt.data_ultimo_pagamento, (tt.pl->>'companyId')::int, tt.data_emissao,
           tt.valor_pago, tt.ajuste_baixa, a.quantidade
    from titulo_total tt
    join apropriacao a on a.titulo_id = tt.titulo_id and a.principal
    returning centro_custo_id
  )
  select (select count(*) from pagamento_bruto pb where pb.data_pagamento is null or pb.valor is null),
         (select count(*) from grava_titulos gt where gt.centro_custo_id = v_empresa)
  into v_pagamentos_sem_data, v_titulos_sem_obra;

  insert into staging.item_orcamento
  select p_tenant, cc.id, r.payload->>'wbsCode', r.payload->>'description',
         (r.payload->>'totalPrice')::numeric, (r.payload->>'percentComplete')::numeric
  from raw.registro r
  join app.centro_custo cc on cc.tenant_id = p_tenant and cc.id_origem = (r.payload->>'buildingId')::int
  where r.tenant_id = p_tenant and r.endpoint = 'building-cost-estimation-items';

  if v_recebimentos_sem_data > 0 or v_pagamentos_sem_data > 0 then
    raise notice 'recebimentos sem data ou valor ignorados: %, pagamentos sem data ou valor ignorados: %',
      v_recebimentos_sem_data, v_pagamentos_sem_data;
  end if;
  if v_titulos_sem_obra > 0 then
    raise notice 'títulos com a parte principal em Despesas sem obra: %', v_titulos_sem_obra;
  end if;
end $$;
revoke execute on function staging.recarregar(uuid) from public, anon, authenticated;

-- Views de caixa passam a ler os eventos. Nomes, colunas e ordem ficam os da 0005; drop porque o tipo
-- das colunas muda de numeric para a soma de numeric(18,2).
drop view marts.posicao_financeira_obra;
drop view marts.fluxo_caixa_mensal;
drop view marts.consolidado_centro_custo;

-- Receber vencido fica fora do saldo (atraso do comprador ou do banco); pagar vencido entra no mês em que venceu.
create view marts.fluxo_caixa_mensal with (security_invoker = true) as
with referencia as (
  select app.data_referencia() as ref
), movimento as (
  select r.tenant_id, r.centro_custo_id, date_trunc('month', r.data_recebimento)::date as competencia,
         r.origem, 'entrada_realizada' as tipo, r.valor
  from staging.recebimento r
  where r.tipo_baixa in ('recebimento', 'estorno')
  union all
  select p.tenant_id, p.centro_custo_id, date_trunc('month', p.vencimento)::date, p.origem,
         case when p.vencimento < ref.ref then 'entrada_vencida' else 'entrada_prevista' end,
         coalesce(p.saldo_corrigido, p.saldo)
  from staging.parcela_receber p
  cross join referencia ref
  left join staging.contrato_venda c on c.tenant_id = p.tenant_id and c.id_origem = p.contrato_id_origem
  where coalesce(p.saldo_corrigido, p.saldo) > 0 and c.situacao_normalizada is distinct from 'distratado'
  union all
  select pg.tenant_id, pg.centro_custo_id, date_trunc('month', pg.data_pagamento)::date, null,
         'saida_realizada', pg.valor
  from staging.pagamento pg
  union all
  select a.tenant_id, a.centro_custo_id, date_trunc('month', a.vencimento)::date, null,
         case when a.vencimento < ref.ref then 'saida_vencida' else 'saida_prevista' end, a.saldo
  from staging.titulo_pagar_apropriacao a
  cross join referencia ref
  where a.saldo > 0
), mensal as (
  select tenant_id, centro_custo_id, competencia,
    coalesce(sum(valor) filter (where tipo = 'entrada_realizada' and origem = 'direta'), 0) as entrada_direta_realizada,
    coalesce(sum(valor) filter (where tipo = 'entrada_realizada' and origem = 'repasse'), 0) as repasse_realizado,
    coalesce(sum(valor) filter (where tipo = 'entrada_prevista' and origem = 'direta'), 0) as entrada_direta_prevista,
    coalesce(sum(valor) filter (where tipo = 'entrada_prevista' and origem = 'repasse'), 0) as repasse_previsto,
    coalesce(sum(valor) filter (where tipo = 'entrada_vencida' and origem = 'direta'), 0) as entrada_direta_vencida,
    coalesce(sum(valor) filter (where tipo = 'entrada_vencida' and origem = 'repasse'), 0) as repasse_vencido,
    coalesce(sum(valor) filter (where tipo = 'saida_realizada'), 0) as saida_realizada,
    coalesce(sum(valor) filter (where tipo = 'saida_prevista'), 0) as saida_prevista,
    coalesce(sum(valor) filter (where tipo = 'saida_vencida'), 0) as saida_vencida
  from movimento
  group by 1, 2, 3
)
select m.*,
  m.entrada_direta_realizada + m.repasse_realizado + m.entrada_direta_prevista + m.repasse_previsto
    - m.saida_realizada - m.saida_prevista - m.saida_vencida as saldo_mes,
  sum(m.entrada_direta_realizada + m.repasse_realizado + m.entrada_direta_prevista + m.repasse_previsto
      - m.saida_realizada - m.saida_prevista - m.saida_vencida)
    over (partition by m.tenant_id, m.centro_custo_id order by m.competencia) as saldo_acumulado
from mensal m;

-- Custo a incorrer e estouro usam o custo lançado, que só difere de pago mais a pagar quando há
-- desconto ou juros na baixa. Só obras: "Despesas sem obra" fica fora da posição por obra.
create view marts.posicao_financeira_obra with (security_invoker = true) as
with fluxo as (
  select tenant_id, centro_custo_id,
    sum(entrada_direta_realizada) as recebido_direto,
    sum(repasse_realizado) as recebido_repasse,
    sum(entrada_direta_prevista) as a_receber_direto,
    sum(repasse_previsto) as a_receber_repasse,
    sum(entrada_direta_vencida) as vencido_direto,
    sum(repasse_vencido) as repasse_atrasado,
    sum(saida_realizada) as pago,
    sum(saida_prevista + saida_vencida) as a_pagar,
    min(saldo_acumulado) as menor_saldo_acumulado
  from marts.fluxo_caixa_mensal
  group by 1, 2
), lancado as (
  select tenant_id, centro_custo_id, sum(valor_original) as custo_lancado
  from staging.titulo_pagar_apropriacao
  group by 1, 2
), orcamento as (
  select tenant_id, centro_custo_id, sum(valor_total) as custo_orcado
  from staging.item_orcamento
  group by 1, 2
), estoque as (
  select tenant_id, centro_custo_id, sum(valor) as estoque_a_vender
  from marts.mapa_unidades
  where situacao in ('disponivel', 'reservada', 'proposta')
  group by 1, 2
), base as (
  select cc.tenant_id, cc.id as centro_custo_id, cc.nome as obra,
    coalesce(f.recebido_direto, 0) as recebido_direto,
    coalesce(f.recebido_repasse, 0) as recebido_repasse,
    coalesce(f.a_receber_direto, 0) as a_receber_direto,
    coalesce(f.a_receber_repasse, 0) as a_receber_repasse,
    coalesce(f.vencido_direto, 0) as vencido_direto,
    coalesce(f.repasse_atrasado, 0) as repasse_atrasado,
    coalesce(e.estoque_a_vender, 0) as estoque_a_vender,
    coalesce(f.pago, 0) as pago,
    coalesce(f.a_pagar, 0) as a_pagar,
    coalesce(o.custo_orcado, 0) as custo_orcado,
    coalesce(l.custo_lancado, 0) as custo_lancado,
    o.centro_custo_id is not null as orcamento_carregado,
    least(coalesce(f.menor_saldo_acumulado, 0), 0) as menor_saldo_acumulado
  from app.centro_custo cc
  left join fluxo f on f.tenant_id = cc.tenant_id and f.centro_custo_id = cc.id
  left join lancado l on l.tenant_id = cc.tenant_id and l.centro_custo_id = cc.id
  left join orcamento o on o.tenant_id = cc.tenant_id and o.centro_custo_id = cc.id
  left join estoque e on e.tenant_id = cc.tenant_id and e.centro_custo_id = cc.id
  where cc.tipo = 'obra'
)
select b.tenant_id, b.centro_custo_id, b.obra,
  b.recebido_direto, b.recebido_repasse, b.a_receber_direto, b.a_receber_repasse, b.vencido_direto, b.repasse_atrasado,
  b.estoque_a_vender,
  b.pago, b.a_pagar, b.custo_orcado,
  greatest(b.custo_orcado - b.custo_lancado, 0) as custo_a_incorrer,
  greatest(b.custo_lancado - b.custo_orcado, 0) as estouro_orcamento,
  b.recebido_direto + b.recebido_repasse - b.pago as caixa_atual,
  -b.menor_saldo_acumulado as exposicao_maxima,
  b.recebido_direto + b.recebido_repasse + b.a_receber_direto + b.a_receber_repasse + b.vencido_direto
    + b.repasse_atrasado
    - greatest(b.custo_orcado, b.custo_lancado) as resultado_contratado,
  b.recebido_direto + b.recebido_repasse + b.a_receber_direto + b.a_receber_repasse + b.vencido_direto
    + b.repasse_atrasado
    + b.estoque_a_vender - greatest(b.custo_orcado, b.custo_lancado) as resultado_projetado,
  b.custo_lancado,
  b.custo_lancado - b.pago - b.a_pagar as ajuste_baixa,
  b.orcamento_carregado
from base b;

create or replace view marts.cobertura_orcamento_obra with (security_invoker = true) as
with orcamento as (
  select tenant_id, centro_custo_id, sum(valor_total) as custo_orcado
  from staging.item_orcamento
  group by 1, 2
), vendas as (
  select tenant_id, centro_custo_id, sum(valor) as vgv_contratado, avg(valor) as ticket_medio
  from staging.contrato_venda
  where situacao_normalizada = 'ativo'
  group by 1, 2
)
select cc.tenant_id, cc.id as centro_custo_id, cc.nome as obra,
  coalesce(o.custo_orcado, 0) as custo_orcado,
  coalesce(v.vgv_contratado, 0) as vgv_contratado,
  case when o.custo_orcado > 0 then round(coalesce(v.vgv_contratado, 0) / o.custo_orcado, 4) end as pct_cobertura,
  round(v.ticket_medio, 2) as ticket_medio,
  case when v.ticket_medio > 0
       then greatest(0, ceil((coalesce(o.custo_orcado, 0) - v.vgv_contratado) / v.ticket_medio))::integer end as unidades_para_cobrir
from app.centro_custo cc
left join orcamento o on o.tenant_id = cc.tenant_id and o.centro_custo_id = cc.id
left join vendas v on v.tenant_id = cc.tenant_id and v.centro_custo_id = cc.id
where cc.tipo = 'obra';

grant select on marts.fluxo_caixa_mensal, marts.posicao_financeira_obra, marts.cobertura_orcamento_obra to authenticated;

-- Mapa e estoque de unidades recriados lendo o mapa de códigos, com as mesmas colunas e os mesmos valores
-- de situacao: fora_de_venda e código sem mapa saem como indisponivel. O dia do índice e da tabela
-- vigente é a data de referência.
create or replace view marts.mapa_unidades with (security_invoker = true) as
with dia as (
  select app.data_referencia() as ref
), indice_atual as (
  select distinct on (i.tenant_id, i.indexador_id_origem) i.tenant_id, i.indexador_id_origem, i.nome, i.referencia, i.valor
  from staging.indice_valor i
  cross join dia d
  where i.referencia <= d.ref
  order by i.tenant_id, i.indexador_id_origem, i.referencia desc
), tabela_vigente as (
  select distinct on (t.tenant_id, t.centro_custo_id) t.*
  from staging.tabela_preco t
  cross join dia d
  where t.vigencia_inicio <= d.ref and (t.vigencia_fim is null or t.vigencia_fim >= d.ref)
  order by t.tenant_id, t.centro_custo_id, t.vigencia_inicio desc, t.versao desc
), contrato_ativo as (
  select distinct on (tenant_id, unidade_id_origem) tenant_id, unidade_id_origem, valor, data_venda
  from staging.contrato_venda
  where situacao_normalizada = 'ativo'
  order by tenant_id, unidade_id_origem, data_venda desc
), base as (
  select
    u.tenant_id, u.centro_custo_id, u.id_origem as unidade_id, u.nome as unidade, u.tipologia, u.area_privativa,
    u.situacao as situacao_origem,
    case when ms.valor is null or ms.valor = 'fora_de_venda' then 'indisponivel' else ms.valor end as situacao,
    tv.nome as tabela, tv.nome_versao as tabela_versao,
    tpu.quantidade_indexada, ia.nome as indice, ia.referencia as indice_referencia, ia.valor as indice_valor,
    ca.valor as valor_contrato, ca.data_venda,
    round(tpu.quantidade_indexada * ia.valor, 2) as valor_tabela,
    uv.valor_sugerido, uv.data_valor_sugerido
  from staging.unidade u
  left join app.mapa_codigo_origem ms
    on ms.tenant_id = u.tenant_id and ms.dominio = 'situacao_unidade' and ms.codigo_origem = u.situacao
  left join contrato_ativo ca on ca.tenant_id = u.tenant_id and ca.unidade_id_origem = u.id_origem
  left join tabela_vigente tv on tv.tenant_id = u.tenant_id and tv.centro_custo_id = u.centro_custo_id
  left join staging.tabela_preco_unidade tpu
    on tpu.tenant_id = tv.tenant_id and tpu.tabela_id_origem = tv.id_origem and tpu.versao = tv.versao
   and tpu.unidade_id_origem = u.id_origem
  left join indice_atual ia on ia.tenant_id = tv.tenant_id and ia.indexador_id_origem = tv.indexador_id_origem
  left join staging.unidade_valor uv on uv.tenant_id = u.tenant_id and uv.unidade_id_origem = u.id_origem
)
select
  b.*,
  coalesce(case when b.situacao = 'vendida' then b.valor_contrato end, b.valor_tabela, b.valor_sugerido) as valor,
  case
    when b.situacao = 'vendida' and b.valor_contrato is not null then 'contrato'
    when b.valor_tabela is not null then 'tabela'
    when b.valor_sugerido is not null then 'cadastro'
  end as origem_valor,
  round(coalesce(case when b.situacao = 'vendida' then b.valor_contrato end, b.valor_tabela, b.valor_sugerido)
        / nullif(b.area_privativa, 0), 2) as valor_m2
from base b;

-- Unidade sem situação na origem conta como indisponível, igual ao mapa de unidades.
create or replace view marts.estoque_atual with (security_invoker = true) as
select u.tenant_id, u.centro_custo_id, u.tipologia,
       count(*) filter (where m.valor = 'disponivel') as disponiveis,
       count(*) filter (where m.valor = 'reservada') as reservadas,
       count(*) filter (where m.valor = 'proposta') as propostas,
       count(*) filter (where m.valor = 'vendida') as vendidas,
       count(*) filter (where m.valor is null or m.valor = 'fora_de_venda') as indisponiveis,
       count(*) as total
from staging.unidade u
left join app.mapa_codigo_origem m
  on m.tenant_id = u.tenant_id and m.dominio = 'situacao_unidade' and m.codigo_origem = u.situacao
group by 1, 2, 3;

-- Código visto no staging sem linha no mapa do tenant, com o que ele movimenta e o valor que está valendo
-- no lugar. Código nulo também aparece, porque não há como mapeá-lo e ele cai no valor sem mapa.
create view marts.pendencia_codigo_origem with (security_invoker = true) as
with pendencia as (
  select p.tenant_id, p.centro_custo_id, 'condicao_pagamento'::text as dominio, p.tipo_condicao as codigo_origem,
         count(*) as quantidade_registros, sum(p.valor_original) as valor_envolvido
  from staging.parcela_receber p
  where not exists (select 1 from app.mapa_codigo_origem m
                    where m.tenant_id = p.tenant_id and m.dominio = 'condicao_pagamento' and m.codigo_origem = p.tipo_condicao)
  group by p.tenant_id, p.centro_custo_id, p.tipo_condicao
  union all
  select mu.tenant_id, mu.centro_custo_id, 'situacao_unidade', mu.situacao_origem, count(*), sum(mu.valor)
  from marts.mapa_unidades mu
  where not exists (select 1 from app.mapa_codigo_origem m
                    where m.tenant_id = mu.tenant_id and m.dominio = 'situacao_unidade' and m.codigo_origem = mu.situacao_origem)
  group by mu.tenant_id, mu.centro_custo_id, mu.situacao_origem
  union all
  select c.tenant_id, c.centro_custo_id, 'situacao_contrato', c.situacao, count(*), sum(c.valor)
  from staging.contrato_venda c
  where not exists (select 1 from app.mapa_codigo_origem m
                    where m.tenant_id = c.tenant_id and m.dominio = 'situacao_contrato' and m.codigo_origem = c.situacao)
  group by c.tenant_id, c.centro_custo_id, c.situacao
)
select pe.tenant_id, pe.centro_custo_id, pe.dominio, pe.codigo_origem, pe.quantidade_registros, pe.valor_envolvido,
       v.valor as valor_aplicado
from pendencia pe
join app.valor_codigo_origem v on v.dominio = pe.dominio and v.valor_sem_mapa;

grant select on marts.mapa_unidades, marts.estoque_atual, marts.pendencia_codigo_origem to authenticated;
