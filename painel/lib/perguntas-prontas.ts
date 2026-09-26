// Perguntas prontas do assistente. O campo sql de cada seção é o texto revisado por João e vira o
// contrato do PT-07; até lá quem executa é a função de mesmo id em lib/consultas/perguntas-prontas.ts,
// que precisa devolver exatamente o que este sql devolveria. Mudou um, muda o outro.
// $1, $2... são os parâmetros que a função passa (listados em parametros), nunca texto do usuário.
import type { NaturezaNumero } from "./mensagens-planejamento";

export type FormatoColuna = "texto" | "real" | "inteiro" | "mes" | "data" | "area" | "percentual" | "motivo" | "simnao";

export type ColunaResposta = { chave: string; rotulo: string; formato: FormatoColuna };

export type SecaoPergunta = {
  chave: string;
  titulo: string;
  natureza: NaturezaNumero;
  sql: string;
  parametros?: readonly string[];
  colunas: readonly ColunaResposta[];
};

// Tela que mostra os mesmos números e as funções de lib/consultas que a pergunta chama.
export type TelaDaPergunta = {
  caminho: string;
  consultas: readonly {
    modulo: "fluxo" | "planejamento" | "financiamento" | "receitas" | "despesas" | "dre";
    funcao: string;
    arquivo: string;
  }[];
};

export type PerguntaPronta = {
  id: string;
  pergunta: string;
  semResultado: string;
  secoes: readonly SecaoPergunta[];
  obra?: "obrigatoria" | "opcional";
  tela?: TelaDaPergunta;
};

const obra: ColunaResposta = { chave: "obra", rotulo: "Obra", formato: "texto" };
const mes: ColunaResposta = { chave: "competencia", rotulo: "Mês", formato: "mes" };

export const perguntasProntas = [
  {
    id: "repasse-parque-6-meses",
    pergunta: "Quanto entra de repasse na Parque das Águas nos próximos 6 meses?",
    semResultado: "Nenhum repasse previsto para a Parque das Águas nos próximos 6 meses, ou a obra não está liberada para o seu perfil.",
    secoes: [
      {
        chave: "resposta",
        titulo: "Resposta",
        natureza: "previsao",
        sql: "select c.nome as obra, f.competencia, f.repasse_previsto from marts.fluxo_caixa_mensal f join app.centro_custo c on c.id = f.centro_custo_id where c.nome ilike '%parque%' and f.competencia between date_trunc('month', current_date) and current_date + interval '6 months' order by f.competencia",
        colunas: [
          { chave: "obra", rotulo: "Obra", formato: "texto" },
          { chave: "competencia", rotulo: "Mês", formato: "mes" },
          { chave: "repasse_previsto", rotulo: "Repasse previsto", formato: "real" },
        ],
      },
    ],
  },
  {
    id: "mes-mais-negativo-aurora",
    pergunta: "Em que mês o caixa da Aurora fica mais negativo?",
    semResultado: "A Residencial Aurora não tem fluxo de caixa carregado ou não está liberada para o seu perfil.",
    secoes: [
      {
        chave: "resposta",
        titulo: "Resposta",
        natureza: "previsao",
        sql: "select c.nome as obra, f.competencia, f.saldo_acumulado from marts.fluxo_caixa_mensal f join app.centro_custo c on c.id = f.centro_custo_id where c.nome ilike '%aurora%' order by f.saldo_acumulado limit 1",
        colunas: [
          { chave: "obra", rotulo: "Obra", formato: "texto" },
          { chave: "competencia", rotulo: "Mês", formato: "mes" },
          { chave: "saldo_acumulado", rotulo: "Saldo acumulado", formato: "real" },
        ],
      },
    ],
  },
  {
    id: "a-receber-aurora",
    pergunta: "Quanto a Aurora ainda vai receber do banco e quanto dos compradores?",
    semResultado: "A Residencial Aurora não está liberada para o seu perfil.",
    secoes: [
      {
        chave: "resposta",
        titulo: "Resposta",
        natureza: "previsao",
        sql: "select obra, a_receber_repasse, repasse_atrasado, a_receber_direto, vencido_direto from marts.posicao_financeira_obra where obra ilike '%aurora%'",
        colunas: [
          { chave: "obra", rotulo: "Obra", formato: "texto" },
          { chave: "a_receber_repasse", rotulo: "Repasse a receber", formato: "real" },
          { chave: "repasse_atrasado", rotulo: "Repasse atrasado", formato: "real" },
          { chave: "a_receber_direto", rotulo: "A receber do comprador", formato: "real" },
          { chave: "vencido_direto", rotulo: "Vencido do comprador", formato: "real" },
        ],
      },
    ],
  },
  {
    id: "exposicao-maxima",
    pergunta: "Quanto dinheiro próprio cada obra precisa no pior momento?",
    semResultado: "Nenhuma obra liberada para o seu perfil.",
    tela: {
      caminho: "/fluxo",
      consultas: [{ modulo: "fluxo", funcao: "listarResumoProjecao", arquivo: "app/(painel)/fluxo/page.tsx" }],
    },
    secoes: [
      {
        chave: "resposta",
        titulo: "Maior aporte na projeção",
        natureza: "previsao",
        sql: "select centro_custo_id, obra, data_referencia, mes_exposicao_maxima, premissa_distribuicao_id, motivo_distribuicao, exposicao_parcial, exposicao_maxima_projetada, exposicao_maxima_conservadora, custo_sem_titulo_distribuido_total, vencido_a_receber, a_pagar_vencido, financiamento_pendente_total, custo_sem_titulo_total, custo_sem_titulo_nao_distribuido from marts.resumo_projecao_obra order by obra",
        colunas: [
          { chave: "obra", rotulo: "Obra", formato: "texto" },
          { chave: "exposicao_maxima_projetada", rotulo: "Maior aporte necessário", formato: "real" },
          { chave: "mes_exposicao_maxima", rotulo: "Mês do pior caixa", formato: "mes" },
          { chave: "exposicao_parcial", rotulo: "Número parcial", formato: "simnao" },
        ],
      },
    ],
  },
  {
    id: "estouro-orcamento",
    pergunta: "Alguma obra estourou o orçamento?",
    semResultado: "Nenhuma das obras liberadas para o seu perfil passou do orçamento.",
    secoes: [
      {
        chave: "resposta",
        titulo: "Resposta",
        natureza: "fato",
        sql: "select obra, custo_orcado, pago, a_pagar, estouro_orcamento from marts.posicao_financeira_obra where estouro_orcamento > 0 order by estouro_orcamento desc",
        colunas: [
          { chave: "obra", rotulo: "Obra", formato: "texto" },
          { chave: "custo_orcado", rotulo: "Custo orçado", formato: "real" },
          { chave: "pago", rotulo: "Pago", formato: "real" },
          { chave: "a_pagar", rotulo: "A pagar", formato: "real" },
          { chave: "estouro_orcamento", rotulo: "Estouro", formato: "real" },
        ],
      },
    ],
  },
  {
    id: "distratos-ano",
    pergunta: "Quantos distratos houve neste ano?",
    semResultado: "Nenhum distrato neste ano nas obras liberadas para o seu perfil.",
    secoes: [
      {
        chave: "resposta",
        titulo: "Resposta",
        natureza: "fato",
        sql: "select c.nome as obra, v.competencia, v.distratos from marts.vso_mensal v join app.centro_custo c on c.id = v.centro_custo_id where v.competencia >= date_trunc('year', current_date) and v.distratos > 0 order by v.competencia, c.nome",
        colunas: [
          { chave: "obra", rotulo: "Obra", formato: "texto" },
          { chave: "competencia", rotulo: "Mês", formato: "mes" },
          { chave: "distratos", rotulo: "Distratos", formato: "inteiro" },
        ],
      },
    ],
  },
  {
    id: "unidades-disponiveis",
    pergunta: "Quantas unidades disponíveis cada obra tem hoje, por tipologia?",
    semResultado: "Nenhuma unidade cadastrada nas obras liberadas para o seu perfil.",
    secoes: [
      {
        chave: "resposta",
        titulo: "Resposta",
        natureza: "fato",
        sql: "select c.nome as obra, e.tipologia, e.disponiveis, e.total from marts.estoque_atual e join app.centro_custo c on c.id = e.centro_custo_id order by c.nome, e.tipologia",
        colunas: [
          { chave: "obra", rotulo: "Obra", formato: "texto" },
          { chave: "tipologia", rotulo: "Tipologia", formato: "texto" },
          { chave: "disponiveis", rotulo: "Disponíveis", formato: "inteiro" },
          { chave: "total", rotulo: "Total de unidades", formato: "inteiro" },
        ],
      },
    ],
  },
  {
    id: "preco-unidade-3q-0202-parque",
    pergunta: "Quanto custa hoje a unidade 3Q-0202 da Parque das Águas?",
    semResultado: "A unidade 3Q-0202 não foi encontrada ou a Parque das Águas não está liberada para o seu perfil.",
    secoes: [
      {
        chave: "resposta",
        titulo: "Resposta",
        natureza: "fato",
        sql: "select c.nome as obra, m.unidade, m.valor, m.valor_m2, m.indice_referencia from marts.mapa_unidades m join app.centro_custo c on c.id = m.centro_custo_id where c.nome ilike '%parque%' and m.unidade = '3Q-0202'",
        colunas: [
          { chave: "obra", rotulo: "Obra", formato: "texto" },
          { chave: "unidade", rotulo: "Unidade", formato: "texto" },
          { chave: "valor", rotulo: "Valor hoje", formato: "real" },
          { chave: "valor_m2", rotulo: "Valor por m²", formato: "real" },
          { chave: "indice_referencia", rotulo: "Índice de", formato: "data" },
        ],
      },
    ],
  },
  {
    id: "disponiveis-aurora",
    pergunta: "Quais unidades da Aurora estão disponíveis e quanto vale cada uma hoje?",
    semResultado: "Nenhuma unidade disponível na Residencial Aurora, ou a obra não está liberada para o seu perfil.",
    secoes: [
      {
        chave: "resposta",
        titulo: "Resposta",
        natureza: "fato",
        sql: "select c.nome as obra, m.unidade, m.tipologia, m.area_privativa, m.valor from marts.mapa_unidades m join app.centro_custo c on c.id = m.centro_custo_id where c.nome ilike '%aurora%' and m.situacao = 'disponivel' order by m.tipologia, m.unidade",
        colunas: [
          { chave: "obra", rotulo: "Obra", formato: "texto" },
          { chave: "unidade", rotulo: "Unidade", formato: "texto" },
          { chave: "tipologia", rotulo: "Tipologia", formato: "texto" },
          { chave: "area_privativa", rotulo: "Área privativa", formato: "area" },
          { chave: "valor", rotulo: "Valor hoje", formato: "real" },
        ],
      },
    ],
  },
  {
    id: "cobertura-parque",
    pergunta: "Quantas vendas faltam para o VGV da Parque das Águas cobrir o orçamento?",
    semResultado: "A Parque das Águas não está liberada para o seu perfil.",
    secoes: [
      {
        chave: "resposta",
        titulo: "Resposta",
        natureza: "fato",
        sql: "select obra, custo_orcado, vgv_contratado, unidades_para_cobrir from marts.cobertura_orcamento_obra where obra ilike '%parque%'",
        colunas: [
          { chave: "obra", rotulo: "Obra", formato: "texto" },
          { chave: "custo_orcado", rotulo: "Custo orçado", formato: "real" },
          { chave: "vgv_contratado", rotulo: "VGV contratado", formato: "real" },
          { chave: "unidades_para_cobrir", rotulo: "Vendas que faltam", formato: "inteiro" },
        ],
      },
    ],
  },
  {
    id: "a-receber-banco",
    pergunta: "Quanto cada obra ainda vai receber do banco?",
    semResultado: "Nenhuma obra liberada para o seu perfil.",
    secoes: [
      {
        chave: "resposta",
        titulo: "Resposta",
        natureza: "previsao",
        sql: "select obra, a_receber_repasse, repasse_atrasado from marts.posicao_financeira_obra order by a_receber_repasse desc",
        colunas: [
          { chave: "obra", rotulo: "Obra", formato: "texto" },
          { chave: "a_receber_repasse", rotulo: "Repasse a receber", formato: "real" },
          { chave: "repasse_atrasado", rotulo: "Repasse atrasado", formato: "real" },
        ],
      },
    ],
  },
  {
    id: "mais-vencido",
    pergunta: "Qual obra tem mais dinheiro vencido a receber dos compradores?",
    semResultado: "Nenhuma obra liberada para o seu perfil.",
    secoes: [
      {
        chave: "resposta",
        titulo: "Resposta",
        natureza: "fato",
        sql: "select obra, vencido_direto, repasse_atrasado from marts.posicao_financeira_obra order by vencido_direto desc",
        colunas: [
          { chave: "obra", rotulo: "Obra", formato: "texto" },
          { chave: "vencido_direto", rotulo: "Vencido do comprador", formato: "real" },
          { chave: "repasse_atrasado", rotulo: "Repasse atrasado", formato: "real" },
        ],
      },
    ],
  },
  {
    id: "estoque-preco-hoje",
    pergunta: "Quanto vale o estoque de cada obra a preço de hoje?",
    semResultado: "Nenhuma obra liberada para o seu perfil.",
    secoes: [
      {
        chave: "resposta",
        titulo: "Resposta",
        natureza: "fato",
        sql: "select obra, estoque_a_vender from marts.posicao_financeira_obra order by estoque_a_vender desc",
        colunas: [
          { chave: "obra", rotulo: "Obra", formato: "texto" },
          { chave: "estoque_a_vender", rotulo: "Estoque a preço de hoje", formato: "real" },
        ],
      },
    ],
  },
  {
    id: "resultado-gerencial-ano",
    pergunta: "Qual o resultado gerencial deste ano?",
    semResultado: "Nenhum lançamento com competência neste ano nas obras liberadas para o seu perfil.",
    obra: "opcional",
    tela: { caminho: "/dre", consultas: [{ modulo: "dre", funcao: "listarDrePeriodo", arquivo: "app/(painel)/dre/page.tsx" }] },
    secoes: [
      {
        chave: "consolidado",
        titulo: "Consolidado das obras liberadas",
        natureza: "fato",
        sql: "select linha_codigo, linha_ordem, linha_nome, valor_periodo, disponivel, motivo, cobertura from marts.dre_periodo($1, $2, null) where linha_ordem < 100 order by linha_ordem",
        parametros: ["primeiro mês do ano da data de referência", "mês da data de referência"],
        colunas: [
          { chave: "linha_nome", rotulo: "Linha", formato: "texto" },
          { chave: "valor_periodo", rotulo: "No ano", formato: "real" },
          { chave: "motivo", rotulo: "Situação", formato: "motivo" },
        ],
      },
      {
        chave: "obra",
        titulo: "Obra escolhida",
        natureza: "fato",
        sql: "select linha_codigo, linha_ordem, linha_nome, valor_periodo, disponivel, motivo, cobertura from marts.dre_periodo($1, $2, $3) where linha_ordem < 100 order by linha_ordem",
        parametros: ["primeiro mês do ano da data de referência", "mês da data de referência", "obra escolhida"],
        colunas: [
          { chave: "linha_nome", rotulo: "Linha", formato: "texto" },
          { chave: "valor_periodo", rotulo: "No ano", formato: "real" },
          { chave: "motivo", rotulo: "Situação", formato: "motivo" },
        ],
      },
    ],
  },
  {
    id: "previsto-proximo-mes",
    pergunta: "Quanto está previsto para entrar no próximo mês e de onde vem?",
    semResultado: "Nenhuma entrada prevista para o próximo mês nas obras liberadas para o seu perfil.",
    tela: {
      caminho: "/fluxo",
      consultas: [
        { modulo: "receitas", funcao: "listarResumoReceitas", arquivo: "app/(painel)/receitas/page.tsx" },
        { modulo: "fluxo", funcao: "listarFluxoProjetado", arquivo: "app/(painel)/fluxo/[id]/page.tsx" },
      ],
    },
    secoes: [
      {
        chave: "parcelas",
        titulo: "Parcelas que vencem no próximo mês",
        natureza: "previsao",
        sql: "select centro_custo_id, obra, previsto_proximo_mes_direto, previsto_proximo_mes_financiamento from marts.resumo_receitas_obra where tipo_centro = 'obra' order by obra",
        colunas: [
          obra,
          { chave: "previsto_proximo_mes_direto", rotulo: "Entrada direta", formato: "real" },
          { chave: "previsto_proximo_mes_financiamento", rotulo: "Financiamento", formato: "real" },
        ],
      },
      {
        chave: "fontes",
        titulo: "Fontes no fluxo projetado do próximo mês",
        natureza: "previsao",
        sql: "select f.centro_custo_id, c.nome as obra, f.competencia, f.previsto_direto, f.previsto_financiamento_elegivel, f.previsto_financiamento_pendente, f.credito_producao_previsto, f.total_entradas from marts.fluxo_projetado_mensal f join app.centro_custo c on c.id = f.centro_custo_id where f.competencia between $1 and $1 order by f.centro_custo_id, f.competencia",
        parametros: ["mês seguinte ao da data de referência"],
        colunas: [
          obra,
          { chave: "previsto_direto", rotulo: "Entrada direta", formato: "real" },
          { chave: "previsto_financiamento_elegivel", rotulo: "Financiamento elegível", formato: "real" },
          { chave: "previsto_financiamento_pendente", rotulo: "Financiamento pendente", formato: "real" },
          { chave: "credito_producao_previsto", rotulo: "Crédito à produção", formato: "real" },
          { chave: "total_entradas", rotulo: "Total de entradas", formato: "real" },
        ],
      },
    ],
  },
  {
    id: "custo-por-categoria",
    pergunta: "Quanto a obra já gastou por categoria?",
    semResultado: "Nenhum título lançado nesta obra, ou ela não está liberada para o seu perfil.",
    obra: "obrigatoria",
    tela: {
      caminho: "/despesas",
      consultas: [{ modulo: "despesas", funcao: "listarCustoPorCategoria", arquivo: "app/(painel)/despesas/page.tsx" }],
    },
    secoes: [
      {
        chave: "categorias",
        titulo: "Custo por categoria",
        natureza: "fato",
        sql: "select categoria_codigo, categoria_nome, grupo_dre, orcamento_vigente, custo_lancado, desembolsado, em_aberto_vencido, em_aberto_a_vencer, ajuste_baixa from marts.custo_obra_categoria where centro_custo_id = $1 order by custo_lancado desc",
        parametros: ["obra escolhida"],
        colunas: [
          { chave: "categoria_nome", rotulo: "Categoria", formato: "texto" },
          { chave: "custo_lancado", rotulo: "Custo lançado", formato: "real" },
          { chave: "desembolsado", rotulo: "Pago", formato: "real" },
          { chave: "em_aberto_vencido", rotulo: "A pagar vencido", formato: "real" },
          { chave: "em_aberto_a_vencer", rotulo: "A pagar a vencer", formato: "real" },
          { chave: "orcamento_vigente", rotulo: "Orçamento", formato: "real" },
        ],
      },
    ],
  },
  {
    id: "aporte-necessario",
    pergunta: "Quanto de aporte cada obra vai precisar e em que mês?",
    semResultado: "Nenhuma obra liberada para o seu perfil.",
    tela: { caminho: "/fluxo", consultas: [{ modulo: "fluxo", funcao: "listarResumoProjecao", arquivo: "app/(painel)/fluxo/page.tsx" }] },
    secoes: [
      {
        chave: "aporte",
        titulo: "Maior aporte na projeção",
        natureza: "previsao",
        sql: "select centro_custo_id, obra, data_referencia, mes_exposicao_maxima, premissa_distribuicao_id, motivo_distribuicao, exposicao_parcial, exposicao_maxima_projetada, exposicao_maxima_conservadora, custo_sem_titulo_distribuido_total, vencido_a_receber, a_pagar_vencido, financiamento_pendente_total, custo_sem_titulo_total, custo_sem_titulo_nao_distribuido from marts.resumo_projecao_obra order by obra",
        colunas: [
          obra,
          { chave: "exposicao_maxima_projetada", rotulo: "Maior aporte", formato: "real" },
          { chave: "mes_exposicao_maxima", rotulo: "Mês do pico", formato: "mes" },
          { chave: "exposicao_maxima_conservadora", rotulo: "Sem financiamento pendente", formato: "real" },
          { chave: "custo_sem_titulo_nao_distribuido", rotulo: "Custo sem título fora dos meses", formato: "real" },
          { chave: "exposicao_parcial", rotulo: "Número parcial", formato: "simnao" },
        ],
      },
    ],
  },
  {
    id: "financiamentos-pendentes",
    pergunta: "Quanto do previsto depende de aprovação do banco ou de medição?",
    semResultado: "Nenhuma obra liberada para o seu perfil.",
    tela: {
      caminho: "/planejamento/financiamento",
      consultas: [
        { modulo: "fluxo", funcao: "listarResumoProjecao", arquivo: "app/(painel)/fluxo/page.tsx" },
        { modulo: "financiamento", funcao: "listarSaldoOperacoes", arquivo: "app/(painel)/planejamento/financiamento/page.tsx" },
      ],
    },
    secoes: [
      {
        chave: "aprovacao",
        titulo: "Financiamento dos compradores ainda sem aprovação",
        natureza: "previsao",
        sql: "select centro_custo_id, obra, data_referencia, mes_exposicao_maxima, premissa_distribuicao_id, motivo_distribuicao, exposicao_parcial, exposicao_maxima_projetada, exposicao_maxima_conservadora, custo_sem_titulo_distribuido_total, vencido_a_receber, a_pagar_vencido, financiamento_pendente_total, custo_sem_titulo_total, custo_sem_titulo_nao_distribuido from marts.resumo_projecao_obra order by obra",
        colunas: [obra, { chave: "financiamento_pendente_total", rotulo: "Financiamento pendente", formato: "real" }],
      },
      {
        chave: "medicao",
        titulo: "Crédito à produção que depende de medição e liberação",
        natureza: "previsao",
        sql: "select s.centro_custo_id, c.nome as obra, s.operacao_credito_id, s.modalidade, s.instituicao, s.percentual_retencao, s.retencao_prevista, s.excede_limite, s.valor_contratado, s.limite_antes_retencao, s.liberado_recebido, s.previsto_aberto, s.saldo_liberavel, s.saldo_nao_programado, s.medido_elegivel, s.elegivel_nao_liberado from marts.saldo_operacao_credito s join app.centro_custo c on c.id = s.centro_custo_id order by s.centro_custo_id, s.instituicao",
        colunas: [
          obra,
          { chave: "instituicao", rotulo: "Banco", formato: "texto" },
          { chave: "previsto_aberto", rotulo: "Liberação prevista em aberto", formato: "real" },
          { chave: "elegivel_nao_liberado", rotulo: "Medido e ainda não liberado", formato: "real" },
          { chave: "saldo_nao_programado", rotulo: "Saldo sem liberação programada", formato: "real" },
        ],
      },
    ],
  },
  {
    id: "pendencias-classificacao",
    pergunta: "Que contas ainda não têm categoria?",
    semResultado: "Todas as contas vistas na origem já têm categoria.",
    tela: { caminho: "/dre", consultas: [{ modulo: "dre", funcao: "listarPendenciasClassificacao", arquivo: "app/(painel)/dre/page.tsx" }] },
    secoes: [
      {
        chave: "pendencias",
        titulo: "Contas sem categoria",
        natureza: "fato",
        sql: "select tipo_origem, conta_origem, quantidade_lancamentos, valor_envolvido, participacao, primeira_competencia, ultima_competencia from marts.pendencia_classificacao order by valor_envolvido desc limit 20",
        colunas: [
          { chave: "tipo_origem", rotulo: "Tipo", formato: "texto" },
          { chave: "conta_origem", rotulo: "Conta na origem", formato: "texto" },
          { chave: "quantidade_lancamentos", rotulo: "Lançamentos", formato: "inteiro" },
          { chave: "valor_envolvido", rotulo: "Valor envolvido", formato: "real" },
          { chave: "participacao", rotulo: "Parte do tipo", formato: "percentual" },
        ],
      },
    ],
  },
  {
    id: "simular-vendas",
    pergunta: "O que acontece com o caixa se a obra vender mais cinco unidades no próximo mês?",
    semResultado: "A obra não tem meses projetados ou não está liberada para o seu perfil.",
    obra: "obrigatoria",
    tela: {
      caminho: "/fluxo/[id]/simular",
      consultas: [
        { modulo: "fluxo", funcao: "listarFluxoProjetado", arquivo: "app/(painel)/fluxo/[id]/page.tsx" },
        { modulo: "fluxo", funcao: "simularFluxo", arquivo: "app/(painel)/fluxo/[id]/simular/page.tsx" },
        { modulo: "fluxo", funcao: "contarEstoqueSimulacao", arquivo: "app/(painel)/fluxo/[id]/simular/page.tsx" },
      ],
    },
    secoes: [
      {
        chave: "comparacao",
        titulo: "Caixa gerado acumulado: projeção de hoje e simulação",
        natureza: "simulacao",
        sql: "select s.competencia, f.caixa_gerado_acumulado as base, s.caixa_gerado_acumulado as simulado, s.necessidade_aporte_acumulada, s.novas_vendas_valor from marts.simular_fluxo($1, $2) s left join marts.fluxo_projetado_mensal f on f.centro_custo_id = $1 and f.competencia = s.competencia order by s.competencia",
        parametros: ["obra escolhida", "premissas mostradas na resposta"],
        colunas: [
          mes,
          { chave: "base", rotulo: "Projeção de hoje (previsão)", formato: "real" },
          { chave: "simulado", rotulo: "Com as novas vendas (simulação)", formato: "real" },
          { chave: "necessidade_aporte_acumulada", rotulo: "Aporte necessário na simulação", formato: "real" },
          { chave: "novas_vendas_valor", rotulo: "Valor das novas vendas", formato: "real" },
        ],
      },
    ],
  },
  {
    id: "quando-falta-caixa",
    pergunta: "Sem novas vendas, em que mês cada obra passa a precisar de aporte?",
    semResultado: "Nenhuma obra liberada para o seu perfil tem meses projetados.",
    tela: {
      caminho: "/fluxo",
      consultas: [
        { modulo: "fluxo", funcao: "listarFluxoProjetado", arquivo: "app/(painel)/fluxo/[id]/page.tsx" },
        { modulo: "fluxo", funcao: "listarResumoProjecao", arquivo: "app/(painel)/fluxo/page.tsx" },
      ],
    },
    secoes: [
      {
        chave: "falta",
        titulo: "Primeiro mês com aporte, da data de referência em diante",
        natureza: "previsao",
        sql: "select f.centro_custo_id, c.nome as obra, f.competencia, f.necessidade_aporte_acumulada, f.caixa_gerado_acumulado from marts.fluxo_projetado_mensal f join app.centro_custo c on c.id = f.centro_custo_id where f.competencia >= $1 order by f.centro_custo_id, f.competencia",
        parametros: ["mês da data de referência"],
        colunas: [
          obra,
          { chave: "competencia", rotulo: "Primeiro mês com aporte", formato: "mes" },
          { chave: "necessidade_aporte_acumulada", rotulo: "Aporte necessário nesse mês", formato: "real" },
        ],
      },
      {
        chave: "pico",
        titulo: "Pior mês da projeção",
        natureza: "previsao",
        sql: "select centro_custo_id, obra, mes_exposicao_maxima, exposicao_maxima_projetada, exposicao_parcial from marts.resumo_projecao_obra order by obra",
        colunas: [
          obra,
          { chave: "mes_exposicao_maxima", rotulo: "Pior mês", formato: "mes" },
          { chave: "exposicao_maxima_projetada", rotulo: "Maior aporte", formato: "real" },
          { chave: "exposicao_parcial", rotulo: "Número parcial", formato: "simnao" },
        ],
      },
    ],
  },
  {
    id: "meta-do-mes",
    pergunta: "A meta de vendas deste mês foi batida e o que isso fez no caixa?",
    semResultado: "Nenhuma obra liberada para o seu perfil tem este mês no planejamento.",
    tela: {
      caminho: "/planejamento",
      consultas: [
        { modulo: "planejamento", funcao: "listarVisaoGerencial", arquivo: "app/(painel)/planejamento/page.tsx" },
        { modulo: "planejamento", funcao: "listarExplicacaoDesvio", arquivo: "app/(painel)/planejamento/page.tsx" },
      ],
    },
    secoes: [
      {
        chave: "vendas",
        titulo: "Meta e vendas do mês",
        natureza: "fato",
        sql: "select v.centro_custo_id, c.nome as obra, v.competencia, v.meta_unidades, v.vendas_unidades, v.meta_valor_contratado, v.vendas_valor, v.distratos_unidades from marts.visao_gerencial_mensal v join app.centro_custo c on c.id = v.centro_custo_id where v.competencia between $1 and $1 order by v.centro_custo_id, v.competencia",
        parametros: ["mês da data de referência"],
        colunas: [
          obra,
          { chave: "meta_unidades", rotulo: "Meta (unidades)", formato: "inteiro" },
          { chave: "vendas_unidades", rotulo: "Vendidas", formato: "inteiro" },
          { chave: "meta_valor_contratado", rotulo: "Meta (valor)", formato: "real" },
          { chave: "vendas_valor", rotulo: "Valor vendido", formato: "real" },
          { chave: "distratos_unidades", rotulo: "Distratos", formato: "inteiro" },
        ],
      },
      {
        chave: "caixa",
        titulo: "Caixa gerado acumulado no mês",
        natureza: "previsao",
        sql: "select v.centro_custo_id, c.nome as obra, v.caixa_gerado_acumulado, v.caixa_gerado_acumulado_original, v.diferenca_original_atual from marts.visao_gerencial_mensal v join app.centro_custo c on c.id = v.centro_custo_id where v.competencia between $1 and $1 order by v.centro_custo_id",
        parametros: ["mês da data de referência"],
        colunas: [
          obra,
          { chave: "caixa_gerado_acumulado", rotulo: "Atual", formato: "real" },
          { chave: "caixa_gerado_acumulado_original", rotulo: "Planejamento original", formato: "real" },
          { chave: "diferenca_original_atual", rotulo: "Diferença", formato: "real" },
        ],
      },
      {
        chave: "desvios",
        titulo: "Causas que os dados sustentam",
        natureza: "fato",
        sql: "select d.centro_custo_id, c.nome as obra, d.competencia, d.causa_codigo, d.causa_descricao, d.quantidade, d.valor, d.origem_dado from marts.explicacao_desvio d join app.centro_custo c on c.id = d.centro_custo_id where d.competencia between $1 and $1 order by d.competencia desc, d.causa_codigo",
        parametros: ["mês da data de referência"],
        colunas: [
          obra,
          { chave: "causa_descricao", rotulo: "Causa", formato: "texto" },
          { chave: "quantidade", rotulo: "Quantidade", formato: "inteiro" },
          { chave: "valor", rotulo: "Valor", formato: "real" },
        ],
      },
    ],
  },
  {
    id: "aporte-deste-mes",
    pergunta: "Quanto de aporte cada obra precisa neste mês?",
    semResultado: "Nenhuma obra liberada para o seu perfil tem este mês projetado.",
    tela: {
      caminho: "/fluxo",
      consultas: [
        { modulo: "fluxo", funcao: "listarFluxoProjetado", arquivo: "app/(painel)/fluxo/[id]/page.tsx" },
        { modulo: "fluxo", funcao: "listarResumoProjecao", arquivo: "app/(painel)/fluxo/page.tsx" },
      ],
    },
    secoes: [
      {
        chave: "aporte",
        titulo: "Aporte no mês de referência",
        natureza: "previsao",
        sql: "select f.centro_custo_id, c.nome as obra, f.competencia, f.aporte_incremental_mes, f.necessidade_aporte_acumulada, f.caixa_gerado_acumulado, r.exposicao_parcial from marts.fluxo_projetado_mensal f join app.centro_custo c on c.id = f.centro_custo_id join marts.resumo_projecao_obra r on r.centro_custo_id = f.centro_custo_id where f.competencia between $1 and $1 order by f.centro_custo_id",
        parametros: ["mês da data de referência"],
        colunas: [
          obra,
          { chave: "aporte_incremental_mes", rotulo: "Aporte do mês", formato: "real" },
          { chave: "necessidade_aporte_acumulada", rotulo: "Aporte acumulado", formato: "real" },
          { chave: "caixa_gerado_acumulado", rotulo: "Caixa gerado acumulado", formato: "real" },
          { chave: "exposicao_parcial", rotulo: "Número parcial", formato: "simnao" },
        ],
      },
    ],
  },
  {
    id: "mudou-desde-projecao",
    pergunta: "O que mudou no caixa desde a projeção registrada?",
    semResultado: "A obra não tem meses projetados ou não está liberada para o seu perfil.",
    obra: "obrigatoria",
    tela: {
      caminho: "/planejamento",
      consultas: [
        { modulo: "planejamento", funcao: "listarComparativo", arquivo: "app/(painel)/planejamento/page.tsx" },
        { modulo: "planejamento", funcao: "listarExplicacaoDesvio", arquivo: "app/(painel)/planejamento/page.tsx" },
      ],
    },
    secoes: [
      {
        chave: "comparativo",
        titulo: "Projeção original e atual, mês a mês",
        natureza: "previsao",
        sql: "select centro_custo_id, competencia, versao_original_id, versao_original_numero, original_total_entradas, original_total_saidas, original_caixa_gerado_acumulado, atual_total_entradas, atual_total_saidas, atual_caixa_gerado_acumulado, realizado_entradas, realizado_saidas, diferenca_caixa_acumulado from marts.comparativo_projecao where centro_custo_id = $1 and competencia between $2 and $3 order by centro_custo_id, competencia",
        parametros: ["obra escolhida", "mês anterior ao da data de referência", "12 meses depois da data de referência"],
        colunas: [
          mes,
          { chave: "original_caixa_gerado_acumulado", rotulo: "Caixa na projeção original", formato: "real" },
          { chave: "atual_caixa_gerado_acumulado", rotulo: "Caixa na projeção atual", formato: "real" },
          { chave: "diferenca_caixa_acumulado", rotulo: "Diferença", formato: "real" },
          { chave: "realizado_entradas", rotulo: "Entradas realizadas", formato: "real" },
          { chave: "realizado_saidas", rotulo: "Saídas realizadas", formato: "real" },
        ],
      },
      {
        chave: "desvios",
        titulo: "Causas que os dados sustentam",
        natureza: "fato",
        sql: "select centro_custo_id, competencia, causa_codigo, causa_descricao, quantidade, valor, origem_dado from marts.explicacao_desvio where centro_custo_id = $1 and competencia between $2 and $3 order by competencia desc, causa_codigo",
        parametros: ["obra escolhida", "mês anterior ao da data de referência", "mês da data de referência"],
        colunas: [
          mes,
          { chave: "causa_descricao", rotulo: "Causa", formato: "texto" },
          { chave: "quantidade", rotulo: "Quantidade", formato: "inteiro" },
          { chave: "valor", rotulo: "Valor", formato: "real" },
        ],
      },
    ],
  },
  {
    id: "liberado-e-pendente",
    pergunta: "Quanto o banco já liberou e quanto está pendente?",
    semResultado: "Nenhuma operação de crédito nem liberação cadastrada nas obras liberadas para o seu perfil.",
    tela: {
      caminho: "/planejamento/financiamento",
      consultas: [
        { modulo: "financiamento", funcao: "listarSaldoOperacoes", arquivo: "app/(painel)/planejamento/financiamento/page.tsx" },
        { modulo: "financiamento", funcao: "listarLiberacoes", arquivo: "app/(painel)/planejamento/financiamento/page.tsx" },
      ],
    },
    secoes: [
      {
        chave: "operacoes",
        titulo: "Operações de crédito",
        natureza: "fato",
        sql: "select s.centro_custo_id, c.nome as obra, s.operacao_credito_id, s.modalidade, s.instituicao, s.percentual_retencao, s.retencao_prevista, s.excede_limite, s.valor_contratado, s.limite_antes_retencao, s.liberado_recebido, s.previsto_aberto, s.saldo_liberavel, s.saldo_nao_programado, s.medido_elegivel, s.elegivel_nao_liberado from marts.saldo_operacao_credito s join app.centro_custo c on c.id = s.centro_custo_id order by s.centro_custo_id, s.instituicao",
        colunas: [
          obra,
          { chave: "instituicao", rotulo: "Banco", formato: "texto" },
          { chave: "valor_contratado", rotulo: "Contratado", formato: "real" },
          { chave: "liberado_recebido", rotulo: "Liberado e recebido", formato: "real" },
          { chave: "previsto_aberto", rotulo: "Previsto em aberto", formato: "real" },
          { chave: "saldo_liberavel", rotulo: "Saldo liberável", formato: "real" },
        ],
      },
      {
        chave: "pendentes",
        titulo: "Liberações pendentes ou atrasadas",
        natureza: "previsao",
        sql: "select l.id, l.centro_custo_id, c.nome as obra, l.nivel, l.contrato_numero, l.descricao_lote, l.valor_previsto, l.data_prevista, l.situacao_efetiva, l.motivo, l.dias_atraso, l.fonte from marts.liberacao_status l join app.centro_custo c on c.id = l.centro_custo_id where l.situacao_efetiva in ('pendente', 'atrasada') order by l.data_prevista",
        colunas: [
          obra,
          { chave: "data_prevista", rotulo: "Prevista para", formato: "data" },
          { chave: "valor_previsto", rotulo: "Valor previsto", formato: "real" },
          { chave: "situacao_efetiva", rotulo: "Situação", formato: "texto" },
          { chave: "motivo", rotulo: "Motivo", formato: "texto" },
          { chave: "dias_atraso", rotulo: "Dias de atraso", formato: "inteiro" },
        ],
      },
    ],
  },
  {
    id: "pos-entrega",
    pergunta: "Que recebimentos e obrigações continuam abertos nas obras já entregues?",
    semResultado: "Nenhuma obra entregue com recebível, título ou liberação em aberto.",
    tela: {
      caminho: "/planejamento",
      consultas: [{ modulo: "planejamento", funcao: "listarPendenciasPosEntrega", arquivo: "app/(painel)/planejamento/page.tsx" }],
    },
    secoes: [
      {
        chave: "pendencias",
        titulo: "Em aberto depois da entrega (acompanhamento gerencial)",
        natureza: "previsao",
        sql: "select centro_custo_id, obra, data_entrega, recebiveis_vencidos, recebiveis_a_vencer, parcelas_abertas, titulos_em_aberto, titulos_abertos, liberacoes_nao_recebidas, credito_nao_liberado from marts.pendencias_pos_entrega order by data_entrega",
        colunas: [
          obra,
          { chave: "data_entrega", rotulo: "Entrega", formato: "data" },
          { chave: "recebiveis_vencidos", rotulo: "A receber vencido", formato: "real" },
          { chave: "recebiveis_a_vencer", rotulo: "A receber a vencer", formato: "real" },
          { chave: "titulos_em_aberto", rotulo: "Títulos em aberto", formato: "real" },
          { chave: "liberacoes_nao_recebidas", rotulo: "Liberações não recebidas", formato: "real" },
          { chave: "credito_nao_liberado", rotulo: "Crédito não liberado", formato: "real" },
        ],
      },
    ],
  },
] as const satisfies readonly PerguntaPronta[];

type PerguntaDoCatalogo = (typeof perguntasProntas)[number];
export type IdPerguntaPronta = PerguntaDoCatalogo["id"];
export type PerguntaComTela = Extract<PerguntaDoCatalogo, { tela: TelaDaPergunta }>;
export type IdPerguntaNova = PerguntaComTela["id"];

export function buscarPerguntaPronta(id: string | undefined): PerguntaDoCatalogo | undefined {
  return perguntasProntas.find((pergunta) => pergunta.id === id);
}

export const perguntasNovas: readonly PerguntaComTela[] = perguntasProntas.filter(
  (pergunta): pergunta is PerguntaComTela => "tela" in pergunta,
);
