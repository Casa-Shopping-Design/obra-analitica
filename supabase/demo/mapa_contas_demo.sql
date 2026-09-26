-- Mapeamento das contas sintéticas da demo para as categorias gerenciais (contrato de dados, seção 5.2).
-- A conta 2.99.001 fica sem mapeamento de propósito, para a demo mostrar a pendência de classificação.
-- Roda depois da migration 0011 e da carga; rodar de novo não duplica e não desfaz reclassificação manual.
-- Sem usuário logado, o autor fica com o uuid nulo, que marca a carga inicial no histórico.
insert into app.mapa_conta_origem (tenant_id, tipo_origem, conta_origem, categoria_codigo, observacao, autor)
select '11111111-1111-1111-1111-111111111111', m.tipo_origem, m.conta_origem, m.categoria_codigo,
       'carga inicial da demo', '00000000-0000-0000-0000-000000000000'
from (values
  ('parcela_receber', '1.01.001', 'venda_imoveis'),
  ('titulo_pagar', '2.01.001', 'materiais'),
  ('titulo_pagar', '2.01.002', 'mao_de_obra'),
  ('titulo_pagar', '2.01.003', 'empreiteiros'),
  ('titulo_pagar', '2.01.004', 'projetos'),
  ('titulo_pagar', '2.02.001', 'tributos_receita'),
  ('titulo_pagar', '2.03.001', 'corretagem'),
  ('titulo_pagar', '2.04.001', 'despesas_administrativas'),
  ('titulo_pagar', '2.05.001', 'despesas_financeiras'),
  ('titulo_pagar', '2.09.001', 'devolucao_distrato')
) as m(tipo_origem, conta_origem, categoria_codigo)
on conflict (tenant_id, tipo_origem, conta_origem) do nothing;
