// Catalogo semantico das views e funcoes de marts que o assistente pode consultar.
// E o unico lugar de onde a LLM aprende nomes de tabela e coluna. Funcao entra como "funcao" porque
// aparece no from de um select (security invoker, so leitura).

export type ViewCatalogo = {
  nome: string;
  tipo?: "view" | "funcao";
  descricao: string;
  colunas: string[];
  exemplos: { pergunta: string; sql: string }[];
};

export const catalogoViews: ViewCatalogo[] = [
  {
    nome: "marts.fluxo_caixa_mensal",
    descricao: "Entradas e saidas de cada obra por mes. Realizado cai no mes em que o dinheiro entrou ou saiu; previsto e vencido caem no mes do vencimento. Entrada direta e o que o comprador paga a construtora; repasse e o que o banco paga pelo financiamento. saldo_acumulado soma realizado, previsto e saidas vencidas; entrada vencida fica fora.",
    colunas: ["centro_custo_id", "competencia", "entrada_direta_realizada", "repasse_realizado", "entrada_direta_prevista", "repasse_previsto", "entrada_direta_vencida", "repasse_vencido", "saida_realizada", "saida_prevista", "saida_vencida", "saldo_mes", "saldo_acumulado"],
    exemplos: [
      { pergunta: "Quanto entra de repasse na Parque das Aguas nos proximos 6 meses?", sql: "select sum(f.repasse_previsto) from marts.fluxo_caixa_mensal f join app.centro_custo c on c.id = f.centro_custo_id where c.nome ilike '%parque%' and f.competencia between date_trunc('month', current_date) and current_date + interval '6 months'" },
      { pergunta: "Em que mes o caixa da Aurora fica mais negativo?", sql: "select f.competencia, f.saldo_acumulado from marts.fluxo_caixa_mensal f join app.centro_custo c on c.id = f.centro_custo_id where c.nome ilike '%aurora%' order by f.saldo_acumulado limit 1" },
    ],
  },
  {
    nome: "marts.posicao_financeira_obra",
    descricao: "Uma linha por obra com tudo que entrou e vai entrar (direto do comprador, repasse do banco, vencido e estoque a preco de hoje), tudo que saiu e vai sair (pago, a pagar, orcamento ainda sem titulo, estouro), caixa atual (caixa realizado acumulado: so o realizado, nao e saldo bancario), exposicao maxima pela regra antiga (para o aporte use marts.resumo_projecao_obra) e resultado contratado e projetado.",
    colunas: ["centro_custo_id", "obra", "recebido_direto", "recebido_repasse", "a_receber_direto", "a_receber_repasse", "vencido_direto", "repasse_atrasado", "estoque_a_vender", "pago", "a_pagar", "custo_orcado", "custo_a_incorrer", "estouro_orcamento", "caixa_atual", "exposicao_maxima", "resultado_contratado", "resultado_projetado", "custo_lancado", "ajuste_baixa", "orcamento_carregado"],
    exemplos: [
      { pergunta: "Quanto a Aurora ainda vai receber do banco e quanto dos compradores?", sql: "select obra, a_receber_repasse + repasse_atrasado as do_banco, a_receber_direto + vencido_direto as dos_compradores from marts.posicao_financeira_obra where obra ilike '%aurora%'" },
      { pergunta: "Alguma obra estourou o orcamento?", sql: "select obra, custo_orcado, custo_lancado, estouro_orcamento from marts.posicao_financeira_obra where estouro_orcamento > 0" },
    ],
  },
  {
    nome: "marts.vso_mensal",
    descricao: "Vendas, distratos e VGV vendido por obra e mes.",
    colunas: ["centro_custo_id", "competencia", "vendas", "distratos", "vgv_vendido"],
    exemplos: [
      { pergunta: "Quantos distratos houve em 2026?", sql: "select sum(distratos) from marts.vso_mensal where competencia >= '2026-01-01'" },
    ],
  },
  {
    nome: "marts.estoque_atual",
    descricao: "Contagem de unidades por obra e tipologia: disponiveis, reservadas, em proposta, vendidas e fora de venda.",
    colunas: ["centro_custo_id", "tipologia", "disponiveis", "reservadas", "propostas", "vendidas", "indisponiveis", "total"],
    exemplos: [
      { pergunta: "Quantas unidades disponiveis existem hoje no total?", sql: "select sum(disponiveis) from marts.estoque_atual" },
    ],
  },
  {
    nome: "marts.mapa_unidades",
    descricao: "Uma linha por unidade com situacao e valor de hoje. Vendida vale o contrato; em estoque vale quantidade da tabela vigente vezes o indice do mes.",
    colunas: ["centro_custo_id", "unidade_id", "unidade", "tipologia", "area_privativa", "situacao", "valor", "origem_valor", "valor_m2", "tabela", "tabela_versao", "quantidade_indexada", "indice", "indice_referencia", "indice_valor", "data_venda"],
    exemplos: [
      { pergunta: "Quanto custa hoje a unidade 3Q-0202 da Parque das Aguas?", sql: "select m.unidade, m.valor, m.valor_m2, m.indice_referencia from marts.mapa_unidades m join app.centro_custo c on c.id = m.centro_custo_id where c.nome ilike '%parque%' and m.unidade = '3Q-0202'" },
      { pergunta: "Quanto vale o estoque disponivel da Aurora a preco de hoje?", sql: "select sum(m.valor) from marts.mapa_unidades m join app.centro_custo c on c.id = m.centro_custo_id where c.nome ilike '%aurora%' and m.situacao = 'disponivel'" },
    ],
  },
  {
    nome: "marts.cobertura_orcamento_obra",
    descricao: "Cobertura do orcamento pelo VGV contratado, por obra. Compara o valor dos contratos ativos com o custo orcado; nao e caixa nem ponto de equilibrio, porque ignora quando o dinheiro entra e sai. pct_cobertura e fracao (1,0 = VGV igual ao orcamento). unidades_para_cobrir e quantas vendas ao ticket medio faltam para o VGV alcancar o orcamento.",
    colunas: ["centro_custo_id", "obra", "custo_orcado", "vgv_contratado", "pct_cobertura", "ticket_medio", "unidades_para_cobrir"],
    exemplos: [
      { pergunta: "Quantas vendas faltam para o VGV da Parque das Aguas cobrir o orcamento?", sql: "select obra, custo_orcado, vgv_contratado, pct_cobertura, unidades_para_cobrir from marts.cobertura_orcamento_obra where obra ilike '%parque%'" },
    ],
  },
  {
    nome: "marts.resumo_receitas_obra",
    descricao: "Uma linha por obra: VGV dos contratos ativos (venda, nao receita nem caixa), recebido direto e de financiamento, vencido e a vencer por origem e o previsto do proximo mes (so parcela a vencer; vencida nunca entra). data_referencia e a data usada.",
    colunas: ["centro_custo_id", "obra", "tipo_centro", "vgv_contratado_ativo", "contratos_ativos", "contratos_distratados", "recebido_direto", "recebido_financiamento", "vencido_direto", "vencido_financiamento", "a_vencer_direto", "a_vencer_financiamento", "previsto_proximo_mes_direto", "previsto_proximo_mes_financiamento", "saldo_distratado", "data_referencia"],
    exemplos: [
      { pergunta: "Quanto esta previsto para entrar no proximo mes?", sql: "select obra, previsto_proximo_mes_direto, previsto_proximo_mes_financiamento from marts.resumo_receitas_obra where tipo_centro = 'obra' order by obra" },
    ],
  },
  {
    nome: "marts.carteira_recebiveis",
    descricao: "Uma linha por parcela, sem nome de comprador: contrato, unidade, origem (direta ou financiamento), vencimento, valor original, recebido, saldo e situacao (quitada, vencida, a_vencer, cancelada_distrato, baixada_sem_recebimento).",
    colunas: ["centro_custo_id", "contrato_id_origem", "contrato_numero", "unidade", "parcela_id_origem", "numero_parcela", "tipo_condicao", "origem", "vencimento", "valor_original", "valor_recebido", "saldo", "data_ultimo_recebimento", "situacao", "parcial", "dias_atraso", "situacao_contrato"],
    exemplos: [
      { pergunta: "Quais parcelas estao vencidas ha mais de 90 dias?", sql: "select contrato_numero, unidade, vencimento, saldo, dias_atraso from marts.carteira_recebiveis where situacao = 'vencida' and dias_atraso > 90 order by dias_atraso desc" },
    ],
  },
  {
    nome: "marts.recebimento_mensal",
    descricao: "Por obra, mes e origem: recebido pelo mes do caixa, previsto contratual e saldo em aberto pelo mes do vencimento.",
    colunas: ["centro_custo_id", "competencia", "origem", "recebido", "previsto_contratual", "saldo_em_aberto"],
    exemplos: [],
  },
  {
    nome: "marts.custo_obra_categoria",
    descricao: "Por obra e categoria gerencial: orcamento vigente, custo lancado (titulos), desembolsado (pagamentos), em aberto vencido e a vencer, ajuste de baixa. categoria_codigo nulo e Sem categoria.",
    colunas: ["centro_custo_id", "tipo_centro", "categoria_codigo", "categoria_nome", "grupo_dre", "orcamento_vigente", "custo_lancado", "desembolsado", "em_aberto_vencido", "em_aberto_a_vencer", "ajuste_baixa"],
    exemplos: [
      { pergunta: "Quanto a obra ja gastou por categoria?", sql: "select categoria_nome, custo_lancado, desembolsado from marts.custo_obra_categoria where centro_custo_id = $1 order by custo_lancado desc" },
    ],
  },
  {
    nome: "marts.custo_obra_resumo",
    descricao: "Uma linha por centro: orcamento vigente, custo lancado, desembolsado, em aberto, orcamento sem titulo, estimativa ate a conclusao e desvio sobre o orcamento.",
    colunas: ["centro_custo_id", "obra", "tipo_centro", "orcamento_vigente", "orcamento_original", "custo_lancado", "desembolsado", "em_aberto_vencido", "em_aberto_a_vencer", "ajuste_baixa", "remanescente_sem_titulo", "estimativa_conclusao", "desvio", "compromissos_nao_faturados", "cobertura_classificacao", "motivo"],
    exemplos: [],
  },
  {
    nome: "marts.despesa_mensal",
    descricao: "Por obra, mes e categoria: lancado pela competencia (emissao), pago pela data do pagamento, a pagar e vencido pelo vencimento.",
    colunas: ["centro_custo_id", "competencia", "categoria_codigo", "categoria_nome", "grupo_dre", "lancado_competencia", "pago", "a_pagar", "vencido"],
    exemplos: [],
  },
  {
    nome: "marts.pendencia_classificacao",
    descricao: "Contas da origem sem categoria gerencial, com quantidade de lancamentos, valor envolvido e participacao no total do mesmo tipo de lancamento.",
    colunas: ["tipo_origem", "conta_origem", "quantidade_lancamentos", "valor_envolvido", "participacao", "primeira_competencia", "ultima_competencia"],
    exemplos: [
      { pergunta: "Que contas ainda nao tem categoria?", sql: "select tipo_origem, conta_origem, quantidade_lancamentos, valor_envolvido, participacao from marts.pendencia_classificacao order by valor_envolvido desc limit 20" },
    ],
  },
  {
    nome: "marts.dre_mensal",
    descricao: "DRE gerencial em formato longo por obra, mes e linha. Linhas indisponiveis vem com disponivel = false, valor nulo e motivo. Resultado gerencial do periodo nao e lucro contabil.",
    colunas: ["centro_custo_id", "tipo_centro", "competencia", "linha_codigo", "linha_ordem", "linha_nome", "valor_mes", "valor_acumulado", "disponivel", "motivo", "valor_com_categoria", "valor_total_lancado", "cobertura"],
    exemplos: [],
  },
  {
    nome: "marts.dre_periodo",
    tipo: "funcao",
    descricao: "Funcao dre_periodo(inicio, fim, obra ou null): soma o DRE gerencial no periodo. Obra nula e o consolidado do que o usuario enxerga.",
    colunas: ["linha_codigo", "linha_ordem", "linha_nome", "valor_periodo", "disponivel", "motivo", "cobertura"],
    exemplos: [
      { pergunta: "Qual o resultado gerencial deste ano?", sql: "select linha_nome, valor_periodo, disponivel, motivo from marts.dre_periodo($1, $2, null) where linha_codigo = 'resultado_gerencial'" },
    ],
  },
  {
    nome: "marts.fluxo_projetado_mensal",
    descricao: "Fluxo de caixa por obra e mes separando realizado (recebido, pago), carteira contratada (direta, financiamento elegivel, financiamento pendente, credito a producao), a pagar e custo sem titulo distribuido. caixa_gerado_acumulado nao e saldo bancario. necessidade_aporte_acumulada e o dinheiro proprio que a obra precisa ate o mes.",
    colunas: ["centro_custo_id", "competencia", "eh_passado", "recebido_direto", "recebido_financiamento", "credito_producao_recebido", "previsto_direto", "previsto_financiamento_elegivel", "previsto_financiamento_pendente", "credito_producao_previsto", "vencido_a_receber", "pago", "a_pagar", "a_pagar_vencido", "custo_sem_titulo_distribuido", "total_entradas", "total_saidas", "saldo_mes", "caixa_gerado_acumulado", "necessidade_aporte_acumulada", "aporte_incremental_mes", "caixa_gerado_acumulado_conservador", "necessidade_aporte_conservadora"],
    exemplos: [
      { pergunta: "Quanto de aporte cada obra precisa neste mes?", sql: "select centro_custo_id, aporte_incremental_mes, necessidade_aporte_acumulada from marts.fluxo_projetado_mensal where competencia = $1" },
    ],
  },
  {
    nome: "marts.resumo_projecao_obra",
    descricao: "Uma linha por obra: maior aporte necessario na projecao e o mes, versao conservadora sem financiamento pendente, custo sem titulo distribuido e nao distribuido (exposicao_parcial quando falta premissa), vencidos e financiamento pendente.",
    colunas: ["centro_custo_id", "obra", "data_referencia", "exposicao_maxima_projetada", "mes_exposicao_maxima", "exposicao_maxima_conservadora", "custo_sem_titulo_total", "custo_sem_titulo_distribuido_total", "custo_sem_titulo_nao_distribuido", "premissa_distribuicao_id", "motivo_distribuicao", "exposicao_parcial", "vencido_a_receber", "a_pagar_vencido", "financiamento_pendente_total"],
    exemplos: [
      { pergunta: "Quanto de aporte cada obra vai precisar e em que mes?", sql: "select obra, exposicao_maxima_projetada, mes_exposicao_maxima, exposicao_parcial from marts.resumo_projecao_obra order by obra" },
    ],
  },
  {
    nome: "marts.simular_fluxo",
    tipo: "funcao",
    descricao: "Funcao simular_fluxo(obra, premissas jsonb): cenario deterministico com novas vendas, desconto, composicao, atraso de liberacao e cronograma de gastos. Nunca grava. Com premissas vazias devolve o mesmo caixa do fluxo projetado.",
    colunas: ["competencia", "recebido", "carteira_prevista", "novas_vendas_unidades", "novas_vendas_valor", "entradas_novas_vendas_direta", "entradas_novas_vendas_financiamento", "pago", "a_pagar", "custo_sem_titulo", "custo_campanha", "total_entradas", "total_saidas", "saldo_mes", "caixa_gerado_acumulado", "necessidade_aporte_acumulada", "aporte_incremental_mes", "aviso", "premissas"],
    exemplos: [],
  },
  {
    nome: "marts.comparativo_projecao",
    descricao: "Por obra e mes: versao original da projecao (primeira do mes), fluxo atual e realizado, com a diferenca do caixa gerado acumulado.",
    colunas: ["centro_custo_id", "competencia", "versao_original_id", "versao_original_numero", "original_total_entradas", "original_total_saidas", "original_caixa_gerado_acumulado", "atual_total_entradas", "atual_total_saidas", "atual_caixa_gerado_acumulado", "realizado_entradas", "realizado_saidas", "diferenca_caixa_acumulado"],
    exemplos: [],
  },
  {
    nome: "marts.explicacao_desvio",
    descricao: "Causas de desvio sustentadas pelos dados, por obra e mes ate o mes de referencia: vendas abaixo ou acima da meta, parcelas vencidas, financiamento nao elegivel, liberacao vencida, gasto acima do previsto.",
    colunas: ["centro_custo_id", "competencia", "causa_codigo", "causa_descricao", "quantidade", "valor", "origem_dado"],
    exemplos: [],
  },
  {
    nome: "marts.visao_gerencial_mensal",
    descricao: "Por obra e mes: meta e realizado comercial, entradas e financiamento previstos na versao original e recebidos, gastos previstos e realizados, caixa gerado acumulado, aporte e diferenca para o original.",
    colunas: ["centro_custo_id", "competencia", "meta_unidades", "meta_valor_contratado", "meta_limite_aporte", "vendas_unidades", "vendas_valor", "distratos_unidades", "entrada_direta_prevista_original", "entrada_direta_recebida", "financiamento_previsto_original", "financiamento_recebido", "gastos_previstos_original", "gastos_realizados", "caixa_gerado_acumulado", "necessidade_aporte_acumulada", "caixa_gerado_acumulado_original", "diferenca_original_atual"],
    exemplos: [],
  },
  {
    nome: "marts.pendencias_pos_entrega",
    descricao: "Obras com entrega passada e o que continua aberto: recebiveis, titulos, liberacoes e credito nao liberado. Acompanhamento gerencial, nao encerramento contabil.",
    colunas: ["centro_custo_id", "obra", "data_entrega", "recebiveis_vencidos", "recebiveis_a_vencer", "parcelas_abertas", "titulos_em_aberto", "titulos_abertos", "liberacoes_nao_recebidas", "credito_nao_liberado"],
    exemplos: [],
  },
  {
    nome: "marts.financiamento_contrato",
    descricao: "Contratos com financiamento do comprador: etapa no banco (complemento manual), classificacao elegivel ou pendente, saldo de financiamento em aberto e recebido.",
    colunas: ["centro_custo_id", "contrato_id_origem", "contrato_numero", "unidade", "valor_contrato", "valor_financiado", "instituicao_financeira", "data_financiamento_origem", "credito_associativo", "etapa", "pendencia", "motivo_pendencia", "data_etapa", "data_prevista_liberacao", "classificacao", "saldo_financiamento_aberto", "recebido_financiamento"],
    exemplos: [],
  },
  {
    nome: "marts.saldo_operacao_credito",
    descricao: "Por operacao de credito a producao: valor contratado, retencao, liberado recebido, previsto em aberto, saldo liberavel, medido elegivel e elegivel nao liberado.",
    colunas: ["centro_custo_id", "operacao_credito_id", "modalidade", "instituicao", "valor_contratado", "percentual_retencao", "retencao_prevista", "limite_antes_retencao", "liberado_recebido", "previsto_aberto", "saldo_liberavel", "saldo_nao_programado", "medido_elegivel", "elegivel_nao_liberado", "excede_limite"],
    exemplos: [],
  },
  {
    nome: "marts.liberacao_status",
    descricao: "Uma linha por liberacao cadastrada (complemento manual), com situacao efetiva (atrasada quando prevista e vencida) e dias de atraso.",
    colunas: ["id", "centro_custo_id", "nivel", "operacao_credito_id", "contrato_id_origem", "contrato_numero", "medicao_id", "descricao_lote", "valor_previsto", "data_prevista", "situacao", "situacao_efetiva", "motivo", "valor_recebido", "data_recebimento", "vinculo_tipo", "vinculo_chave", "fonte", "referencia_documento", "dias_atraso", "origem_dado"],
    exemplos: [],
  },
];
