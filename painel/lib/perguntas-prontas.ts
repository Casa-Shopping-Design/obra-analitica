// Perguntas prontas do assistente. O campo sql é o texto revisado por João e vira o contrato do PT-07;
// até lá quem executa é a função de mesmo id em lib/consultas/perguntas-prontas.ts, que precisa
// devolver exatamente o que este sql devolveria. Mudou um, muda o outro.

import type { TipoAlerta } from "./alertas";
import { perfisDre } from "./dre";

export type FormatoColuna = "texto" | "real" | "inteiro" | "percentual" | "mes" | "data" | "area";

export type ColunaResposta = { chave: string; rotulo: string; formato: FormatoColuna };

export type PerguntaPronta = {
  id: string;
  pergunta: string;
  sql: string;
  colunas: readonly ColunaResposta[];
  semResultado: string;
  // Sem perfis, qualquer perfil vê a pergunta; com perfis, só eles. Mesmo critério do catálogo das views.
  perfis?: readonly string[];
};

const semObraDre = "Nenhuma obra com estudo de viabilidade liberada para o seu perfil.";

export const perguntasProntas = [
  {
    id: "repasse-parque-6-meses",
    pergunta: "Quanto entra de repasse na Parque das Águas nos próximos 6 meses?",
    sql: "select c.nome as obra, f.competencia, f.repasse_previsto from marts.fluxo_caixa_mensal f join app.centro_custo c on c.id = f.centro_custo_id where c.nome ilike '%parque%' and f.competencia between date_trunc('month', current_date) and current_date + interval '6 months' order by f.competencia",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "competencia", rotulo: "Mês", formato: "mes" },
      { chave: "repasse_previsto", rotulo: "Repasse previsto", formato: "real" },
    ],
    semResultado: "Nenhum repasse previsto para a Parque das Águas nos próximos 6 meses, ou a obra não está liberada para o seu perfil.",
  },
  {
    id: "mes-mais-negativo-aurora",
    pergunta: "Em que mês o caixa da Aurora fica mais negativo?",
    sql: "select c.nome as obra, f.competencia, f.saldo_acumulado from marts.fluxo_caixa_mensal f join app.centro_custo c on c.id = f.centro_custo_id where c.nome ilike '%aurora%' order by f.saldo_acumulado limit 1",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "competencia", rotulo: "Mês", formato: "mes" },
      { chave: "saldo_acumulado", rotulo: "Saldo acumulado", formato: "real" },
    ],
    semResultado: "A Residencial Aurora não tem fluxo de caixa carregado ou não está liberada para o seu perfil.",
  },
  {
    id: "a-receber-aurora",
    pergunta: "Quanto a Aurora ainda vai receber do banco e quanto dos compradores?",
    sql: "select obra, a_receber_repasse, repasse_atrasado, a_receber_direto, vencido_direto from marts.posicao_financeira_obra where obra ilike '%aurora%'",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "a_receber_repasse", rotulo: "Repasse a receber", formato: "real" },
      { chave: "repasse_atrasado", rotulo: "Repasse atrasado", formato: "real" },
      { chave: "a_receber_direto", rotulo: "A receber do comprador", formato: "real" },
      { chave: "vencido_direto", rotulo: "Vencido do comprador", formato: "real" },
    ],
    semResultado: "A Residencial Aurora não está liberada para o seu perfil.",
  },
  {
    id: "exposicao-maxima",
    pergunta: "Quanto dinheiro próprio cada obra precisa no pior momento?",
    sql: "select obra, exposicao_maxima from marts.posicao_financeira_obra order by exposicao_maxima desc",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "exposicao_maxima", rotulo: "Exposição máxima", formato: "real" },
    ],
    semResultado: "Nenhuma obra liberada para o seu perfil.",
  },
  {
    id: "estouro-orcamento",
    pergunta: "Alguma obra estourou o orçamento?",
    sql: "select obra, custo_orcado, pago, a_pagar, estouro_orcamento from marts.posicao_financeira_obra where estouro_orcamento > 0 order by estouro_orcamento desc",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "custo_orcado", rotulo: "Custo orçado", formato: "real" },
      { chave: "pago", rotulo: "Pago", formato: "real" },
      { chave: "a_pagar", rotulo: "A pagar", formato: "real" },
      { chave: "estouro_orcamento", rotulo: "Estouro", formato: "real" },
    ],
    semResultado: "Nenhuma das obras liberadas para o seu perfil passou do orçamento.",
  },
  {
    id: "distratos-ano",
    pergunta: "Quantos distratos houve neste ano?",
    sql: "select c.nome as obra, v.competencia, v.distratos from marts.vso_mensal v join app.centro_custo c on c.id = v.centro_custo_id where v.competencia >= date_trunc('year', current_date) and v.distratos > 0 order by v.competencia, c.nome",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "competencia", rotulo: "Mês", formato: "mes" },
      { chave: "distratos", rotulo: "Distratos", formato: "inteiro" },
    ],
    semResultado: "Nenhum distrato neste ano nas obras liberadas para o seu perfil.",
  },
  {
    id: "unidades-disponiveis",
    pergunta: "Quantas unidades disponíveis cada obra tem hoje, por tipologia?",
    sql: "select c.nome as obra, e.tipologia, e.disponiveis, e.total from marts.estoque_atual e join app.centro_custo c on c.id = e.centro_custo_id order by c.nome, e.tipologia",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "tipologia", rotulo: "Tipologia", formato: "texto" },
      { chave: "disponiveis", rotulo: "Disponíveis", formato: "inteiro" },
      { chave: "total", rotulo: "Total de unidades", formato: "inteiro" },
    ],
    semResultado: "Nenhuma unidade cadastrada nas obras liberadas para o seu perfil.",
  },
  {
    id: "preco-unidade-3q-0202-parque",
    pergunta: "Quanto custa hoje a unidade 3Q-0202 da Parque das Águas?",
    sql: "select c.nome as obra, m.unidade, m.valor, m.valor_m2, m.indice_referencia from marts.mapa_unidades m join app.centro_custo c on c.id = m.centro_custo_id where c.nome ilike '%parque%' and m.unidade = '3Q-0202'",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "unidade", rotulo: "Unidade", formato: "texto" },
      { chave: "valor", rotulo: "Valor hoje", formato: "real" },
      { chave: "valor_m2", rotulo: "Valor por m²", formato: "real" },
      { chave: "indice_referencia", rotulo: "Índice de", formato: "data" },
    ],
    semResultado: "A unidade 3Q-0202 não foi encontrada ou a Parque das Águas não está liberada para o seu perfil.",
  },
  {
    id: "disponiveis-aurora",
    pergunta: "Quais unidades da Aurora estão disponíveis e quanto vale cada uma hoje?",
    sql: "select c.nome as obra, m.unidade, m.tipologia, m.area_privativa, m.valor from marts.mapa_unidades m join app.centro_custo c on c.id = m.centro_custo_id where c.nome ilike '%aurora%' and m.situacao = 'disponivel' order by m.tipologia, m.unidade",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "unidade", rotulo: "Unidade", formato: "texto" },
      { chave: "tipologia", rotulo: "Tipologia", formato: "texto" },
      { chave: "area_privativa", rotulo: "Área privativa", formato: "area" },
      { chave: "valor", rotulo: "Valor hoje", formato: "real" },
    ],
    semResultado: "Nenhuma unidade disponível na Residencial Aurora, ou a obra não está liberada para o seu perfil.",
  },
  {
    id: "cobertura-parque",
    pergunta: "Quantas vendas faltam para o VGV da Parque das Águas cobrir o orçamento?",
    sql: "select obra, custo_orcado, vgv_contratado, unidades_para_cobrir from marts.cobertura_orcamento_obra where obra ilike '%parque%'",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "custo_orcado", rotulo: "Custo orçado", formato: "real" },
      { chave: "vgv_contratado", rotulo: "VGV contratado", formato: "real" },
      { chave: "unidades_para_cobrir", rotulo: "Vendas que faltam", formato: "inteiro" },
    ],
    semResultado: "A Parque das Águas não está liberada para o seu perfil.",
  },
  {
    id: "a-receber-banco",
    pergunta: "Quanto cada obra ainda vai receber do banco?",
    sql: "select obra, a_receber_repasse, repasse_atrasado from marts.posicao_financeira_obra order by a_receber_repasse desc",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "a_receber_repasse", rotulo: "Repasse a receber", formato: "real" },
      { chave: "repasse_atrasado", rotulo: "Repasse atrasado", formato: "real" },
    ],
    semResultado: "Nenhuma obra liberada para o seu perfil.",
  },
  {
    id: "mais-vencido",
    pergunta: "Qual obra tem mais dinheiro vencido a receber dos compradores?",
    sql: "select obra, vencido_direto, repasse_atrasado from marts.posicao_financeira_obra order by vencido_direto desc",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "vencido_direto", rotulo: "Vencido do comprador", formato: "real" },
      { chave: "repasse_atrasado", rotulo: "Repasse atrasado", formato: "real" },
    ],
    semResultado: "Nenhuma obra liberada para o seu perfil.",
  },
  {
    id: "estoque-preco-hoje",
    pergunta: "Quanto vale o estoque de cada obra a preço de hoje?",
    sql: "select obra, estoque_a_vender from marts.posicao_financeira_obra order by estoque_a_vender desc",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "estoque_a_vender", rotulo: "Estoque a preço de hoje", formato: "real" },
    ],
    semResultado: "Nenhuma obra liberada para o seu perfil.",
  },
  {
    id: "tempo-vender-estoque",
    pergunta: "Quanto tempo leva para vender o estoque de cada obra?",
    sql: "select obra, unidades_estoque, meses_para_vender_estoque, data_entrega, meses_ate_entrega from marts.estoque_obra order by meses_para_vender_estoque desc nulls first",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "unidades_estoque", rotulo: "Unidades em estoque", formato: "inteiro" },
      { chave: "meses_para_vender_estoque", rotulo: "Meses para vender no ritmo recente", formato: "inteiro" },
      { chave: "data_entrega", rotulo: "Entrega", formato: "data" },
      { chave: "meses_ate_entrega", rotulo: "Meses até a entrega", formato: "inteiro" },
    ],
    semResultado: "Nenhuma obra liberada para o seu perfil.",
  },
  {
    id: "exposicao-carteira",
    pergunta: "Quanto dinheiro próprio a carteira exige no pior mês?",
    sql: "select obras, exposicao_maxima, mes_exposicao_maxima, soma_exposicao_obras from marts.posicao_carteira",
    colunas: [
      { chave: "obras", rotulo: "Obras na carteira", formato: "inteiro" },
      { chave: "exposicao_maxima", rotulo: "Exposição da carteira", formato: "real" },
      { chave: "mes_exposicao_maxima", rotulo: "Pior mês", formato: "mes" },
      { chave: "soma_exposicao_obras", rotulo: "Soma das exposições de cada obra", formato: "real" },
    ],
    semResultado: "Nenhuma obra liberada para o seu perfil.",
  },
  {
    id: "obras-pedem-atencao",
    pergunta: "Quais obras pedem atenção agora?",
    sql: "select a.obra, case a.tipo when 'repasse_atrasado' then 'Repasse do banco atrasado' when 'estoque_apos_entrega' then 'Estoque não acaba até a entrega' when 'estouro_orcamento' then 'Custo acima do orçamento' when 'inadimplencia_alta' then 'Inadimplência alta' when 'pago_a_frente_do_fisico' then 'Pago à frente do físico' end as tipo from marts.alertas_obra a order by a.obra, a.tipo",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "tipo", rotulo: "Alerta", formato: "texto" },
    ],
    semResultado: "Nenhum alerta nas obras liberadas para o seu perfil.",
  },
  {
    id: "estoque-tipologia-preco-hoje",
    pergunta: "Quanto vale o estoque de cada tipologia a preço de hoje?",
    sql: "select c.nome as obra, e.tipologia, e.disponiveis, e.reservadas, e.propostas, e.valor_estoque, e.preco_m2_estoque from marts.estoque_tipologia e join app.centro_custo c on c.id = e.centro_custo_id order by c.nome, e.tipologia",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "tipologia", rotulo: "Tipologia", formato: "texto" },
      { chave: "disponiveis", rotulo: "Disponíveis", formato: "inteiro" },
      { chave: "reservadas", rotulo: "Reservadas", formato: "inteiro" },
      { chave: "propostas", rotulo: "Em proposta", formato: "inteiro" },
      { chave: "valor_estoque", rotulo: "Estoque a preço de hoje", formato: "real" },
      { chave: "preco_m2_estoque", rotulo: "Preço por m²", formato: "real" },
    ],
    semResultado: "Nenhuma unidade cadastrada nas obras liberadas para o seu perfil.",
  },
  {
    id: "tendencia-lucro-obras",
    pergunta: "Qual a tendência do lucro de cada obra contra o estudo?",
    sql: "select obra, viabilidade, tendencia, desvio, desvio_pct from marts.dre_viabilidade where linha = 'lucro_operacional' order by desvio",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "viabilidade", rotulo: "Lucro no estudo", formato: "real" },
      { chave: "tendencia", rotulo: "Lucro na tendência", formato: "real" },
      { chave: "desvio", rotulo: "Desvio", formato: "real" },
      { chave: "desvio_pct", rotulo: "Desvio %", formato: "percentual" },
    ],
    semResultado: semObraDre,
    perfis: perfisDre,
  },
  {
    id: "linha-mais-desvia-parque",
    pergunta: "Em que linha a Parque das Águas mais desvia do estudo?",
    sql: "select obra, case linha when 'vgv_bruto' then 'VGV bruto' when 'impostos' then 'Impostos' when 'custo_terreno' then 'Custo do terreno' when 'custo_projetos' then 'Projetos' when 'custo_licenciamento' then 'Licenciamento' when 'custo_construcao' then 'Construção' when 'assistencia_tecnica' then 'Assistência técnica' when 'juros_financiamento' then 'Juros do financiamento' when 'estoque' then 'Estoque' when 'despesas_comerciais' then 'Despesas comerciais' when 'despesas_administrativas' then 'Despesas administrativas' end as linha, viabilidade, tendencia, desvio from marts.dre_viabilidade where obra ilike '%parque%' and linha_de_total = false and desvio_favoravel = false order by abs(desvio) desc limit 3",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "linha", rotulo: "Linha da DRE", formato: "texto" },
      { chave: "viabilidade", rotulo: "Estudo", formato: "real" },
      { chave: "tendencia", rotulo: "Tendência", formato: "real" },
      { chave: "desvio", rotulo: "Desvio", formato: "real" },
    ],
    semResultado: "A Parque das Águas não tem linha desfavorável ao estudo, ou não está liberada para o seu perfil.",
    perfis: perfisDre,
  },
  {
    id: "margem-perdida-obras",
    pergunta: "Qual obra perdeu mais margem contra o estudo?",
    sql: "select obra, margem_operacional_viabilidade, margem_operacional_tendencia, desvio_margem_operacional from marts.dre_resumo_obra order by desvio_margem_operacional",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "margem_operacional_viabilidade", rotulo: "Margem no estudo", formato: "percentual" },
      { chave: "margem_operacional_tendencia", rotulo: "Margem na tendência", formato: "percentual" },
      { chave: "desvio_margem_operacional", rotulo: "Desvio da margem", formato: "percentual" },
    ],
    semResultado: semObraDre,
    perfis: perfisDre,
  },
  {
    id: "receita-a-apropriar-obras",
    pergunta: "Quanto falta apropriar de receita em cada obra?",
    sql: "select obra, apropriado, a_apropriar, a_contratar from marts.dre_viabilidade where linha = 'vgv_bruto' order by obra",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "apropriado", rotulo: "Receita apropriada", formato: "real" },
      { chave: "a_apropriar", rotulo: "Vendido a apropriar", formato: "real" },
      { chave: "a_contratar", rotulo: "Estoque a vender", formato: "real" },
    ],
    semResultado: semObraDre,
    perfis: perfisDre,
  },
  {
    id: "imposto-a-gerar-obras",
    pergunta: "Quanto de imposto cada obra ainda vai gerar?",
    sql: "select obra, aliquota, imposto_receita_a_apropriar, imposto_vgv_estoque, imposto_a_realizar from marts.imposto_obra order by imposto_a_realizar desc",
    colunas: [
      { chave: "obra", rotulo: "Obra", formato: "texto" },
      { chave: "aliquota", rotulo: "Alíquota informada", formato: "percentual" },
      { chave: "imposto_receita_a_apropriar", rotulo: "Sobre o vendido a apropriar", formato: "real" },
      { chave: "imposto_vgv_estoque", rotulo: "Sobre o estoque", formato: "real" },
      { chave: "imposto_a_realizar", rotulo: "Imposto a realizar", formato: "real" },
    ],
    semResultado: "Nenhuma obra com alíquota de imposto informada liberada para o seu perfil.",
    perfis: perfisDre,
  },
] as const satisfies readonly PerguntaPronta[];

// Rótulo de cada tipo de marts.alertas_obra na pergunta "obras-pedem-atencao". Tem de ser igual ao case do sql dela.
export const rotulosAlerta: Record<TipoAlerta, string> = {
  repasse_atrasado: "Repasse do banco atrasado",
  estoque_apos_entrega: "Estoque não acaba até a entrega",
  estouro_orcamento: "Custo acima do orçamento",
  inadimplencia_alta: "Inadimplência alta",
  pago_a_frente_do_fisico: "Pago à frente do físico",
};

type PerguntaDoCatalogo = (typeof perguntasProntas)[number];
export type IdPerguntaPronta = PerguntaDoCatalogo["id"];

// perfil é o valor cru de app.perfil_atual; sem perfil lido ficam só as perguntas sem restrição.
export function perguntasProntasDoPerfil(perfil: string | null): readonly PerguntaDoCatalogo[] {
  return perguntasProntas.filter(
    (pergunta) => !("perfis" in pergunta) || (perfil !== null && pergunta.perfis.some((permitido) => permitido === perfil)),
  );
}

export function buscarPerguntaPronta(id: string | undefined, perfil: string | null): PerguntaDoCatalogo | undefined {
  return perguntasProntasDoPerfil(perfil).find((pergunta) => pergunta.id === id);
}
