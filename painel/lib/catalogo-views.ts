// Catalogo semantico das views que o assistente pode consultar.
// E o unico lugar de onde a LLM aprende nomes de tabela e coluna.

export type ViewCatalogo = {
  nome: string;
  descricao: string;
  colunas: string[];
  exemplos: { pergunta: string; sql: string }[];
  // Sem perfis, qualquer perfil consulta; com perfis, a view so entra no catalogo desses perfis.
  perfis?: string[];
};

export const catalogoViews: ViewCatalogo[] = [
  {
    nome: "marts.fluxo_caixa_mensal",
    descricao: "Entradas e saidas de cada obra por mes. Realizado cai no mes de cada recebimento ou pagamento (parcela ou titulo pago em duas vezes aparece nos dois meses); previsto e vencido caem no mes do vencimento. Titulo rateado entre obras entra em cada obra pela fracao do rateio; despesa sem obra nao entra em obra nenhuma. Entrada direta e o que o comprador paga a construtora; repasse e o que o banco paga pelo financiamento. saldo_acumulado soma realizado, previsto e saidas vencidas; entrada vencida fica fora.",
    colunas: ["centro_custo_id", "competencia", "entrada_direta_realizada", "repasse_realizado", "entrada_direta_prevista", "repasse_previsto", "entrada_direta_vencida", "repasse_vencido", "saida_realizada", "saida_prevista", "saida_vencida", "saldo_mes", "saldo_acumulado"],
    exemplos: [
      { pergunta: "Quanto entra de repasse na Parque das Aguas nos proximos 6 meses?", sql: "select sum(f.repasse_previsto) from marts.fluxo_caixa_mensal f join app.centro_custo c on c.id = f.centro_custo_id where c.nome ilike '%parque%' and f.competencia between date_trunc('month', current_date) and current_date + interval '6 months'" },
      { pergunta: "Em que mes o caixa da Aurora fica mais negativo?", sql: "select f.competencia, f.saldo_acumulado from marts.fluxo_caixa_mensal f join app.centro_custo c on c.id = f.centro_custo_id where c.nome ilike '%aurora%' order by f.saldo_acumulado limit 1" },
    ],
  },
  {
    nome: "marts.posicao_financeira_obra",
    descricao: "Uma linha por obra com tudo que entrou e vai entrar (direto do comprador, repasse do banco, vencido e estoque a preco de hoje), tudo que saiu e vai sair (pago, a pagar, orcamento ainda sem titulo, estouro), caixa atual, exposicao maxima (dinheiro proprio que a obra exige no pior mes), resultado contratado e projetado e VGV. vgv_total e vgv_vendido (contratos ativos) mais estoque_a_vender; unidade fora de venda nao entra. pct_vgv_vendido e fracao (0,5 = metade do VGV vendido).",
    colunas: ["centro_custo_id", "obra", "recebido_direto", "recebido_repasse", "a_receber_direto", "a_receber_repasse", "vencido_direto", "repasse_atrasado", "estoque_a_vender", "pago", "a_pagar", "custo_orcado", "custo_a_incorrer", "estouro_orcamento", "caixa_atual", "exposicao_maxima", "resultado_contratado", "resultado_projetado", "vgv_vendido", "vgv_total", "pct_vgv_vendido"],
    exemplos: [
      { pergunta: "Quanto a Aurora ainda vai receber do banco e quanto dos compradores?", sql: "select obra, a_receber_repasse + repasse_atrasado as do_banco, a_receber_direto + vencido_direto as dos_compradores from marts.posicao_financeira_obra where obra ilike '%aurora%'" },
      { pergunta: "Quanto dinheiro proprio cada obra precisa no pior momento?", sql: "select obra, exposicao_maxima from marts.posicao_financeira_obra order by exposicao_maxima desc" },
      { pergunta: "Qual o VGV de cada obra e quanto dele ja foi vendido?", sql: "select obra, vgv_total, vgv_vendido, pct_vgv_vendido from marts.posicao_financeira_obra order by vgv_total desc" },
      { pergunta: "Alguma obra estourou o orcamento?", sql: "select obra, custo_orcado, pago + a_pagar as custo_lancado, estouro_orcamento from marts.posicao_financeira_obra where estouro_orcamento > 0" },
    ],
  },
  {
    nome: "marts.posicao_carteira",
    descricao: "Uma linha so, com a carteira somada: as obras que quem pergunta enxerga (o gerente ve a carteira do tamanho das obras dele). Nao tem centro_custo_id nem obra; para ver obra a obra, use marts.posicao_financeira_obra, de onde saem as somas. obras e quantas obras entraram. vgv_total, vgv_vendido, estoque_a_vender, caixa_atual, resultado_projetado, vencido_direto, repasse_atrasado, a_receber_direto, a_receber_repasse, a_pagar e estouro_orcamento sao a soma das obras, com o mesmo significado de la. pct_vgv_vendido e fracao, vgv_vendido sobre vgv_total. exposicao_maxima e o dinheiro proprio que a carteira exige no pior mes, tirado do saldo acumulado das obras juntas mes a mes em marts.fluxo_caixa_mensal; nao e a soma das exposicoes, porque o pior mes de cada obra cai em momentos diferentes. mes_exposicao_maxima e o mes desse pior saldo, nulo quando o saldo nunca fica negativo. soma_exposicao_obras e a soma das exposicoes obra a obra, so para comparar. Ao responder exposicao da carteira, usar exposicao_maxima.",
    colunas: ["obras", "vgv_total", "vgv_vendido", "pct_vgv_vendido", "estoque_a_vender", "caixa_atual", "resultado_projetado", "vencido_direto", "repasse_atrasado", "a_receber_direto", "a_receber_repasse", "a_pagar", "estouro_orcamento", "exposicao_maxima", "mes_exposicao_maxima", "soma_exposicao_obras"],
    exemplos: [
      { pergunta: "Quanto dinheiro proprio a carteira exige no pior mes?", sql: "select obras, exposicao_maxima, mes_exposicao_maxima, soma_exposicao_obras from marts.posicao_carteira" },
      { pergunta: "Quanto do VGV da carteira ja foi vendido e quanto falta vender?", sql: "select obras, vgv_total, vgv_vendido, pct_vgv_vendido, estoque_a_vender from marts.posicao_carteira" },
    ],
  },
  {
    nome: "marts.vso_mensal",
    descricao: "VSO (vendas sobre oferta) por obra e mes, em calendario continuo do primeiro contrato ate o mes atual; mes sem venda aparece com zero. vendas conta os contratos assinados no mes, inclusive os distratados depois; distratos conta os cancelamentos no mes do cancelamento; vendas_liquidas e vendas menos distratos. vgv_vendido soma o valor dos contratos assinados no mes. estoque_inicio_mes e o denominador: unidades em oferta (fora de venda nao conta) sem contrato ativo no primeiro dia do mes. vso_pct e fracao, vendas_liquidas dividido por estoque_inicio_mes (0,05 = 5% do estoque vendido no mes); fica nulo sem estoque e pode ser negativo quando o distrato supera a venda. Ao responder taxa, mostrar tambem vendas_liquidas e estoque_inicio_mes.",
    colunas: ["centro_custo_id", "competencia", "vendas", "distratos", "vgv_vendido", "vendas_liquidas", "estoque_inicio_mes", "vso_pct"],
    exemplos: [
      { pergunta: "Qual a VSO da Aurora nos ultimos 6 meses?", sql: "select v.competencia, v.vendas_liquidas, v.estoque_inicio_mes, v.vso_pct from marts.vso_mensal v join app.centro_custo c on c.id = v.centro_custo_id where c.nome ilike '%aurora%' and v.competencia >= date_trunc('month', current_date) - interval '5 months' order by v.competencia" },
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
    colunas: ["centro_custo_id", "unidade", "tipologia", "area_privativa", "situacao", "valor", "origem_valor", "valor_m2", "tabela", "tabela_versao", "quantidade_indexada", "indice", "indice_referencia", "indice_valor", "data_venda"],
    exemplos: [
      { pergunta: "Quanto custa hoje a unidade 3Q-0202 da Parque das Aguas?", sql: "select m.unidade, m.valor, m.valor_m2, m.indice_referencia from marts.mapa_unidades m join app.centro_custo c on c.id = m.centro_custo_id where c.nome ilike '%parque%' and m.unidade = '3Q-0202'" },
      { pergunta: "Quanto vale o estoque disponivel da Aurora a preco de hoje?", sql: "select sum(m.valor) from marts.mapa_unidades m join app.centro_custo c on c.id = m.centro_custo_id where c.nome ilike '%aurora%' and m.situacao = 'disponivel'" },
    ],
  },
  {
    nome: "marts.cobertura_orcamento_obra",
    descricao: "Cobertura do orcamento pelo VGV contratado, por obra. Compara o valor dos contratos ativos com o custo orcado; nao e caixa nem ponto de equilibrio, porque ignora quando o dinheiro entra e sai. pct_cobertura e fracao (1,0 = VGV igual ao orcamento). unidades_para_cobrir e quantas vendas ao ticket medio faltam para o VGV alcancar o orcamento. vendas_media_6m e a media de vendas liquidas por mes nos seis meses do calendario ate o mes atual (ou desde o primeiro contrato, se a obra tem menos historia), contando mes sem venda como zero. meses_para_cobrir e unidades_para_cobrir dividido por vendas_media_6m; e projecao no ritmo recente, nao prazo garantido, e fica nulo quando nao houve venda liquida no periodo.",
    colunas: ["centro_custo_id", "obra", "custo_orcado", "vgv_contratado", "pct_cobertura", "ticket_medio", "unidades_para_cobrir", "vendas_media_6m", "meses_para_cobrir"],
    exemplos: [
      { pergunta: "Quantas vendas faltam para o VGV da Parque das Aguas cobrir o orcamento?", sql: "select obra, custo_orcado, vgv_contratado, pct_cobertura, unidades_para_cobrir from marts.cobertura_orcamento_obra where obra ilike '%parque%'" },
      { pergunta: "No ritmo atual, em quantos meses as vendas cobrem o orcamento de cada obra?", sql: "select obra, unidades_para_cobrir, vendas_media_6m, meses_para_cobrir from marts.cobertura_orcamento_obra order by meses_para_cobrir desc nulls first" },
    ],
  },
  {
    nome: "marts.estoque_obra",
    descricao: "Uma linha por obra com o estoque e o tempo para vende-lo. Estoque e unidade disponivel, reservada ou em proposta; vendida e fora de venda nao entram. unidades_estoque conta essas unidades e valor_estoque soma o valor delas a preco de hoje, pela regra de marts.mapa_unidades (unidade sem preco conta na quantidade e nao no valor). preco_medio_estoque e valor_estoque dividido por unidades_estoque. unidades_vendidas conta as vendidas. vendas_media_6m e o ritmo de vendas liquidas por mes, o mesmo de marts.cobertura_orcamento_obra. meses_para_vender_estoque e unidades_estoque dividido por vendas_media_6m: projecao no ritmo recente, nao prazo garantido; e zero sem estoque e nulo quando nao houve venda liquida no periodo (estoque parado). data_entrega e a maior data de entrega das unidades da obra. meses_ate_entrega conta os meses do mes atual ate o mes da entrega, zero se a obra ja foi entregue e nulo sem data. Estoque que nao acaba ate a entrega aparece em marts.alertas_obra.",
    colunas: ["centro_custo_id", "obra", "unidades_estoque", "valor_estoque", "unidades_vendidas", "preco_medio_estoque", "vendas_media_6m", "meses_para_vender_estoque", "data_entrega", "meses_ate_entrega"],
    exemplos: [
      { pergunta: "Quanto tempo leva para vender o estoque de cada obra?", sql: "select obra, unidades_estoque, vendas_media_6m, meses_para_vender_estoque, meses_ate_entrega from marts.estoque_obra order by meses_para_vender_estoque desc nulls first" },
      { pergunta: "O estoque da Aurora acaba antes da entrega?", sql: "select obra, unidades_estoque, valor_estoque, meses_para_vender_estoque, data_entrega, meses_ate_entrega from marts.estoque_obra where obra ilike '%aurora%'" },
    ],
  },
  {
    nome: "marts.estoque_tipologia",
    descricao: "Unidades e valor do estoque por obra e tipologia; unidade sem tipologia cai em 'Sem tipologia'. disponiveis, reservadas, propostas, vendidas e fora_de_venda contam as unidades em cada situacao e total conta todas. Estoque e disponivel, reservada e proposta, como em marts.estoque_obra. valor_estoque soma o valor dessas unidades a preco de hoje, pela regra de marts.mapa_unidades; preco_medio_estoque e a media delas; preco_m2_estoque e o valor dividido pela area privativa, so com unidade que tem area e preco. Nao tem o nome da obra: faca join de app.centro_custo.",
    colunas: ["centro_custo_id", "tipologia", "disponiveis", "reservadas", "propostas", "vendidas", "fora_de_venda", "total", "valor_estoque", "preco_medio_estoque", "preco_m2_estoque"],
    exemplos: [
      { pergunta: "Quanto vale o estoque de cada tipologia a preco de hoje?", sql: "select c.nome as obra, e.tipologia, e.disponiveis + e.reservadas + e.propostas as unidades_estoque, e.valor_estoque, e.preco_m2_estoque from marts.estoque_tipologia e join app.centro_custo c on c.id = e.centro_custo_id order by c.nome, e.tipologia" },
      { pergunta: "Qual o preco medio por m2 do estoque de 3 quartos da Parque das Aguas?", sql: "select e.tipologia, e.preco_medio_estoque, e.preco_m2_estoque from marts.estoque_tipologia e join app.centro_custo c on c.id = e.centro_custo_id where c.nome ilike '%parque%' and e.tipologia ilike '3q%'" },
    ],
  },
  {
    nome: "marts.repasse_obra",
    descricao: "Repasse do financiamento bancario por obra, cruzando o CRM de vendas com o ERP. So aparece obra que tem repasse no CRM. A etapa vem das datas do CRM: em analise (sem contrato assinado no banco), assinado (contrato assinado, recurso ainda nao liberado) e liberado (banco liberou o recurso). repasses_atrasados e valor_atrasado nao sao etapa: sao os repasses sem recurso liberado cuja parcela de financiamento ja venceu e esta em aberto no ERP, e tambem estao contados em analise ou assinado. Valores de etapa sao o valor financiado no CRM. contratos_financiados_origem sao os contratos ativos do ERP com parcela de financiamento; contratos_sem_repasse sao os que nao tem repasse no CRM. dias_medios_assinatura_liberacao e a media de dias entre a assinatura e a liberacao, nula sem repasse liberado. a_receber_repasse_origem e repasse_atrasado_origem vem do ERP pela mesma regra do fluxo de caixa. liberado_sem_baixa_origem e o valor que o CRM ja da como liberado e o ERP ainda nao baixou: recebimento proximo.",
    colunas: ["centro_custo_id", "obra", "contratos_financiados_origem", "contratos_com_repasse", "contratos_sem_repasse", "repasses_em_analise", "valor_em_analise", "repasses_assinados", "valor_assinado", "repasses_liberados", "valor_liberado", "repasses_atrasados", "valor_atrasado", "dias_medios_assinatura_liberacao", "a_receber_repasse_origem", "repasse_atrasado_origem", "liberado_sem_baixa_origem"],
    exemplos: [
      { pergunta: "Quantos repasses da Aurora estao em analise no banco e quanto valem?", sql: "select obra, repasses_em_analise, valor_em_analise from marts.repasse_obra where obra ilike '%aurora%'" },
      { pergunta: "Quanto o banco ja liberou e ainda nao entrou no ERP?", sql: "select obra, repasses_liberados, liberado_sem_baixa_origem from marts.repasse_obra order by liberado_sem_baixa_origem desc" },
      { pergunta: "Quanto tempo o banco leva da assinatura a liberacao em cada obra?", sql: "select obra, repasses_liberados, dias_medios_assinatura_liberacao from marts.repasse_obra order by dias_medios_assinatura_liberacao desc nulls last" },
    ],
  },
  {
    nome: "marts.repasse_banco",
    descricao: "Repasse do financiamento por obra e banco, com a mesma regra de marts.repasse_obra: somando os bancos de uma obra, contagens e valores de etapa e de atraso fecham com a linha da obra la. banco e o nome que o CRM grava; vazio vira 'Nao informado'. contratos_com_repasse, repasses_em_analise, valor_em_analise, repasses_assinados, valor_assinado, repasses_liberados, valor_liberado, repasses_atrasados e valor_atrasado tem o mesmo significado de marts.repasse_obra. dias_medios_assinatura_liberacao e a media de dias entre a assinatura e a liberacao naquele banco, nula quando o banco ainda nao liberou nenhum; para a media de varios bancos, ponderar por repasses_liberados, nunca tirar media simples. repasses_parados_analise e valor_parado_analise contam os repasses em analise (sem assinatura) cuja situacao no CRM nao muda ha mais de 60 dias; repasse sem data de mudanca de situacao nao entra nessa conta.",
    colunas: ["centro_custo_id", "obra", "banco", "contratos_com_repasse", "repasses_em_analise", "valor_em_analise", "repasses_assinados", "valor_assinado", "repasses_liberados", "valor_liberado", "repasses_atrasados", "valor_atrasado", "dias_medios_assinatura_liberacao", "repasses_parados_analise", "valor_parado_analise"],
    exemplos: [
      { pergunta: "Qual banco demora mais para liberar o repasse na Torre Comercial Sul?", sql: "select banco, repasses_liberados, dias_medios_assinatura_liberacao from marts.repasse_banco where obra ilike '%torre%' and dias_medios_assinatura_liberacao is not null order by dias_medios_assinatura_liberacao desc" },
      { pergunta: "Quanto esta parado em analise ha mais de 60 dias em cada banco?", sql: "select banco, sum(repasses_parados_analise) as repasses, sum(valor_parado_analise) as valor from marts.repasse_banco group by banco order by valor desc" },
    ],
  },
  {
    nome: "marts.funil_vendas_mensal",
    descricao: "Funil de vendas por obra e mes, em calendario continuo; so aparece obra com dado do CRM de vendas. leads e reservas vem do CRM (reserva pela data de cadastro, reservas_canceladas pela data do cancelamento). vendas e distratos vem do ERP pela mesma regra de marts.vso_mensal. conversao_lead_reserva e reservas dividido por leads do mesmo mes, e conversao_reserva_venda e vendas dividido por reservas do mesmo mes; sao fracoes (0,1 = 10%), nulas quando o denominador e zero, e nao sao coorte: a reserva de marco pode vir de lead de janeiro. Para conversao de um periodo, somar as contagens antes de dividir, nunca tirar media das conversoes mensais.",
    colunas: ["centro_custo_id", "competencia", "leads", "reservas", "reservas_canceladas", "vendas", "distratos", "conversao_lead_reserva", "conversao_reserva_venda"],
    exemplos: [
      { pergunta: "Quantos leads e reservas a Parque das Aguas teve nos ultimos 3 meses?", sql: "select f.competencia, f.leads, f.reservas, f.vendas from marts.funil_vendas_mensal f join app.centro_custo c on c.id = f.centro_custo_id where c.nome ilike '%parque%' and f.competencia >= date_trunc('month', current_date) - interval '2 months' order by f.competencia" },
      { pergunta: "Qual a conversao de reserva em venda da Aurora em 2026?", sql: "select sum(f.reservas) as reservas, sum(f.vendas) as vendas, round(sum(f.vendas)::numeric / nullif(sum(f.reservas), 0), 4) as conversao from marts.funil_vendas_mensal f join app.centro_custo c on c.id = f.centro_custo_id where c.nome ilike '%aurora%' and f.competencia >= '2026-01-01'" },
    ],
  },
  {
    nome: "marts.leads_origem",
    descricao: "Leads do CRM de vendas por obra, origem e midia nos ultimos 12 meses (o mes atual e os 11 anteriores). leads conta os leads cadastrados no periodo; leads_descartados conta os que tem motivo de cancelamento ou situacao de descarte, cancelamento ou perda. pct_descartados e fracao, leads_descartados sobre leads (0,4 = 40%). motivo_principal_descarte e o motivo mais frequente entre os descartados com motivo, nulo quando nenhum descartado tem motivo; leads_motivo_principal e quantos leads tiveram esse motivo. O lead nao se liga a reserva nem a venda, entao esta view nao responde conversao por origem; para conversao use marts.funil_vendas_mensal, que e da obra inteira. Para o total por origem, somar leads e leads_descartados das midias; o motivo principal nao soma.",
    colunas: ["centro_custo_id", "obra", "origem", "midia", "leads", "leads_descartados", "pct_descartados", "motivo_principal_descarte", "leads_motivo_principal"],
    exemplos: [
      { pergunta: "De onde vem a maior parte dos leads da Aurora?", sql: "select origem, sum(leads) as leads, sum(leads_descartados) as descartados from marts.leads_origem where obra ilike '%aurora%' group by origem order by leads desc" },
      { pergunta: "Qual origem de lead tem mais descarte na Parque das Aguas?", sql: "select origem, midia, leads, leads_descartados, pct_descartados, motivo_principal_descarte from marts.leads_origem where obra ilike '%parque%' order by pct_descartados desc nulls last" },
    ],
  },
  {
    nome: "marts.execucao_fisica_obra",
    descricao: "Execucao fisica contra financeira por obra e mes, do primeiro mes com medicao ate o mes atual. pct_fisico e o valor medido sobre o valor planejado das tarefas, so com medicao aprovada no ERP; tarefa sem medicao no mes segue com o acumulado anterior. pct_financeiro e o pago acumulado ate o mes sobre o custo orcado; pct_financeiro_origem e o custo incorrido sobre o orcado segundo o mapa imobiliario do ERP, nulo no mes que o ERP nao fechou. diferenca_financeiro_fisico e pct_financeiro menos pct_fisico: positivo quer dizer pago na frente da obra. Todas sao fracoes (0,5 = 50%). valor_medido, valor_planejado, custo_orcado e pago_acumulado estao em reais.",
    colunas: ["centro_custo_id", "competencia", "valor_medido", "valor_planejado", "pct_fisico", "custo_orcado", "pago_acumulado", "pct_financeiro", "pct_financeiro_origem", "diferenca_financeiro_fisico"],
    exemplos: [
      { pergunta: "Qual o percentual fisico da Aurora hoje contra o financeiro?", sql: "select e.competencia, e.pct_fisico, e.pct_financeiro, e.diferenca_financeiro_fisico from marts.execucao_fisica_obra e join app.centro_custo c on c.id = e.centro_custo_id where c.nome ilike '%aurora%' and e.pct_fisico is not null order by e.competencia desc limit 1" },
      { pergunta: "Em que obras o pago esta mais de 10 pontos na frente do fisico neste mes?", sql: "select c.nome, e.pct_fisico, e.pct_financeiro from marts.execucao_fisica_obra e join app.centro_custo c on c.id = e.centro_custo_id where e.competencia = date_trunc('month', current_date) and e.diferenca_financeiro_fisico > 0.1" },
    ],
  },
  {
    nome: "marts.inadimplencia_faixa",
    descricao: "Inadimplencia dos compradores por obra e faixa de dias de atraso (1-30, 31-90, 91-180, >180), na ultima posicao que o ERP entregou (data_posicao). Cada obra com posicao carregada tem sempre as quatro faixas, com zero quando a faixa esta vazia. Cada titulo entra na faixa da sua parcela mais atrasada. titulos conta os titulos, parcelas soma as parcelas atrasadas, valor_atrasado e o valor das parcelas atrasadas corrigido sem acrescimos e valor_atualizado soma juros, multa e pro rata. ordem vai de 1 (menor atraso) a 4. Nao identifica comprador.",
    colunas: ["centro_custo_id", "obra", "data_posicao", "ordem", "faixa", "titulos", "parcelas", "valor_atrasado", "valor_atualizado"],
    exemplos: [
      { pergunta: "Quanto esta atrasado ha mais de 90 dias em cada obra?", sql: "select obra, sum(valor_atualizado) from marts.inadimplencia_faixa where ordem >= 3 group by obra order by 2 desc" },
      { pergunta: "Como se distribui a inadimplencia da Parque das Aguas por faixa?", sql: "select faixa, titulos, parcelas, valor_atrasado, valor_atualizado, data_posicao from marts.inadimplencia_faixa where obra ilike '%parque%' order by ordem" },
    ],
  },
  {
    nome: "marts.alertas_obra",
    descricao: "Alertas por obra, uma linha por alerta que disparou; obra sem alerta nao aparece. valor e referencia mudam de unidade conforme o tipo, entao nunca some valor de tipos diferentes. Tipos: estouro_orcamento dispara quando o custo lancado (pago mais a pagar) passa o orcamento; valor e o estouro em reais e referencia e o custo orcado em reais (zero quando a obra nao tem orcamento). repasse_atrasado dispara com repasse do banco vencido e nao pago; valor e esse repasse em reais e referencia e nula. inadimplencia_alta dispara quando o vencido do comprador passa de 5% da carteira direta (recebido, a receber e vencido direto); valor e o vencido em reais e referencia e a fracao (0,06 = 6%). pago_a_frente_do_fisico dispara quando, no mes mais recente de marts.execucao_fisica_obra, o pago passa o fisico em mais de 10 pontos; valor e a diferenca em fracao (0,23 = 23 pontos) e referencia e nula. estoque_apos_entrega dispara quando ha estoque e, no ritmo dos ultimos 6 meses, ele nao acaba ate a entrega; valor e meses_para_vender_estoque de marts.estoque_obra (nulo quando nao houve venda liquida, estoque parado) e referencia e meses_ate_entrega (zero = obra ja entregue).",
    colunas: ["centro_custo_id", "obra", "tipo", "valor", "referencia"],
    exemplos: [
      { pergunta: "Quais obras pedem atencao agora?", sql: "select obra, tipo, valor, referencia from marts.alertas_obra order by obra, tipo" },
      { pergunta: "Em que obras a inadimplencia passou do limite?", sql: "select obra, valor as vencido_comprador, referencia as fracao_vencida from marts.alertas_obra where tipo = 'inadimplencia_alta' order by valor desc" },
    ],
  },
  {
    nome: "marts.comparativo_obras",
    descricao: "Uma linha por obra com os indicadores de comparacao entre obras, tirados dos outros marts sem regra nova. vgv_total, vgv_vendido, pct_vgv_vendido, resultado_projetado, exposicao_maxima, caixa_atual, vencido_direto e repasse_atrasado sao os de marts.posicao_financeira_obra. vendas_liquidas_12m soma as vendas menos distratos dos ultimos 12 meses de marts.vso_mensal, estoque_inicio_12m e o estoque no inicio do primeiro desses meses e vso_12m e a divisao dos dois (fracao, 0,5 = metade do estoque vendido no ano; nula sem estoque). unidades_estoque, valor_estoque e meses_para_vender_estoque sao os de marts.estoque_obra. margem_projetada e resultado_projetado sobre vgv_total (fracao). pct_inadimplencia e vencido_direto sobre recebido, a receber e vencido direto, a mesma fracao do alerta inadimplencia_alta. pct_fisico, pct_financeiro e diferenca_financeiro_fisico sao os do mes atual (competencia_execucao) em marts.execucao_fisica_obra, nulos sem medicao. alertas conta as linhas da obra em marts.alertas_obra, zero sem alerta. Exposicao maxima da carteira nao e a soma desta coluna: use marts.posicao_carteira.",
    colunas: ["centro_custo_id", "obra", "vgv_total", "vgv_vendido", "pct_vgv_vendido", "vendas_liquidas_12m", "estoque_inicio_12m", "vso_12m", "unidades_estoque", "valor_estoque", "meses_para_vender_estoque", "resultado_projetado", "margem_projetada", "exposicao_maxima", "caixa_atual", "vencido_direto", "pct_inadimplencia", "repasse_atrasado", "competencia_execucao", "pct_fisico", "pct_financeiro", "diferenca_financeiro_fisico", "alertas"],
    exemplos: [
      { pergunta: "Qual obra tem a maior exposicao?", sql: "select obra, exposicao_maxima from marts.comparativo_obras order by exposicao_maxima desc limit 1" },
      { pergunta: "Compare a margem e a VSO das obras", sql: "select obra, resultado_projetado, margem_projetada, vendas_liquidas_12m, estoque_inicio_12m, vso_12m from marts.comparativo_obras order by margem_projetada" },
      { pergunta: "Qual obra tem mais inadimplencia e mais alertas?", sql: "select obra, vencido_direto, pct_inadimplencia, alertas from marts.comparativo_obras order by pct_inadimplencia desc nulls last" },
    ],
  },
  {
    nome: "marts.conferencia_origem",
    descricao: "Conferencia do painel contra o mapa imobiliario do ERP, por obra, no ultimo mes que o ERP fechou (competencia_origem). Cada indicador vem com o valor do painel, o do ERP, a diferenca em reais (painel menos ERP) e, quando ha, a diferenca em fracao sobre o ERP: VGV (o do painel e o de hoje), custo orcado, custo incorrido (painel soma o pago ate o mes e os titulos em aberto que vencem ate o mes; o ERP apropria pela competencia do titulo, entao titulo com vencimento futuro vira diferenca) e recebido ate o fim do mes. Diferenca de ate 1% e arredondamento; acima de 5% pede conferencia do lancamento. So diretor e financeiro consultam.",
    colunas: ["centro_custo_id", "obra", "competencia_origem", "vgv_painel", "vgv_origem", "diferenca_vgv", "diferenca_vgv_pct", "custo_orcado_painel", "custo_orcado_origem", "diferenca_custo_orcado", "custo_incorrido_painel", "custo_incorrido_origem", "diferenca_custo_incorrido", "diferenca_custo_incorrido_pct", "recebido_painel", "recebido_origem", "diferenca_recebido", "diferenca_recebido_pct"],
    exemplos: [
      { pergunta: "O VGV do painel bate com o do ERP?", sql: "select obra, competencia_origem, vgv_painel, vgv_origem, diferenca_vgv, diferenca_vgv_pct from marts.conferencia_origem order by abs(diferenca_vgv) desc" },
      { pergunta: "Em que obras o custo incorrido diverge mais de 5% do ERP?", sql: "select obra, custo_incorrido_painel, custo_incorrido_origem, diferenca_custo_incorrido_pct from marts.conferencia_origem where abs(diferenca_custo_incorrido_pct) > 0.05" },
    ],
    perfis: ["diretor", "financeiro"],
  },
  {
    nome: "marts.dre_viabilidade",
    descricao: "DRE de viabilidade por obra. Uma linha por obra e por linha do resultado (campo linha: vgv_bruto, impostos, vgv_liquido, custo_vendas, custo_empreendimento, custo_terreno, custo_projetos, custo_licenciamento, custo_construcao, assistencia_tecnica, juros_financiamento, estoque, resultado_bruto, despesas, despesas_comerciais, despesas_administrativas, lucro_operacional). viabilidade e o valor do estudo. apropriado e o realizado contabil ate a competencia. a_apropriar e o que ja esta vendido ou lancado e ainda nao foi apropriado. a_contratar e o que falta vender (no VGV) ou contratar (no custo). tendencia e apropriado mais a_apropriar mais a_contratar: o valor da linha no fim da obra se nada mudar. desvio e tendencia menos viabilidade; desvio_favoravel diz se o desvio ajuda o resultado. Linhas com linha_de_total verdadeiro ja somam as outras: nunca some a coluna inteira, sempre filtre por linha. pct_ sao fracoes sobre o VGV liquido. So diretor e financeiro consultam.",
    colunas: ["centro_custo_id", "obra", "competencia", "estudo_versao", "estudo_data_base", "linha", "ordem", "nivel", "natureza", "linha_de_total", "fonte_realizado", "viabilidade", "pct_viabilidade", "apropriado", "a_apropriar", "a_contratar", "a_realizar", "tendencia", "pct_tendencia", "desvio", "desvio_pct", "desvio_favoravel"],
    exemplos: [
      { pergunta: "Qual a tendencia do lucro de cada obra contra o estudo?", sql: "select obra, viabilidade, tendencia, desvio, desvio_pct from marts.dre_viabilidade where linha = 'lucro_operacional' order by desvio" },
      { pergunta: "Em que linha a Parque das Aguas mais desvia do estudo?", sql: "select linha, viabilidade, tendencia, desvio from marts.dre_viabilidade where obra ilike '%parque%' and linha_de_total = false and desvio_favoravel = false order by desvio desc limit 3" },
      { pergunta: "Quanto falta apropriar de receita em cada obra?", sql: "select obra, a_apropriar, a_contratar from marts.dre_viabilidade where linha = 'vgv_bruto' order by obra" },
    ],
    perfis: ["diretor", "financeiro"],
  },
  {
    nome: "marts.dre_resumo_obra",
    descricao: "Uma linha por obra com estudo de viabilidade vigente, resumo de marts.dre_viabilidade. vgv_bruto_viabilidade e o VGV do estudo e vgv_bruto_tendencia e o VGV de hoje (vendido mais estoque). pct_vendido e vgv_vendido sobre vgv_bruto_tendencia. receita_apropriada e a receita contabil ate a competencia e poc e receita_apropriada sobre vgv_vendido. custo_apropriado e o custo de vendas ja apropriado. recebido_acumulado e o caixa recebido do comprador e do banco, que nao e receita apropriada. resultado_bruto e lucro_operacional vem nas versoes viabilidade e tendencia. margem_operacional_viabilidade e margem_operacional_tendencia sao o lucro operacional sobre o VGV liquido de cada coluna e desvio_margem_operacional e a diferenca entre elas; sao fracoes (0,1 = 10%). So diretor e financeiro consultam.",
    colunas: ["centro_custo_id", "obra", "competencia", "estudo_versao", "vgv_bruto_viabilidade", "vgv_bruto_tendencia", "vgv_vendido", "pct_vendido", "receita_apropriada", "poc", "custo_apropriado", "recebido_acumulado", "resultado_bruto_viabilidade", "resultado_bruto_tendencia", "lucro_operacional_viabilidade", "lucro_operacional_tendencia", "margem_operacional_viabilidade", "margem_operacional_tendencia", "desvio_margem_operacional"],
    exemplos: [
      { pergunta: "Qual a margem operacional de cada obra, no estudo e na tendencia?", sql: "select obra, margem_operacional_viabilidade, margem_operacional_tendencia, desvio_margem_operacional from marts.dre_resumo_obra order by desvio_margem_operacional" },
      { pergunta: "Quanto de receita ja foi apropriado em cada obra e qual o POC?", sql: "select obra, competencia, vgv_vendido, receita_apropriada, poc from marts.dre_resumo_obra order by poc desc" },
      { pergunta: "Qual obra tem o lucro operacional mais abaixo do estudo?", sql: "select obra, lucro_operacional_viabilidade, lucro_operacional_tendencia, lucro_operacional_tendencia - lucro_operacional_viabilidade as desvio from marts.dre_resumo_obra order by desvio limit 1" },
    ],
    perfis: ["diretor", "financeiro"],
  },
  {
    nome: "marts.dre_resumo_carteira",
    descricao: "Uma linha por tenant com a soma de marts.dre_resumo_obra nas obras com estudo de viabilidade vigente que quem pergunta ve. obras e quantas obras entraram na soma. vgv_bruto_tendencia e o VGV de hoje e pct_vendido e vgv_vendido sobre ele. poc e receita_apropriada sobre vgv_vendido. custo_apropriado e o custo de vendas ja apropriado e recebido_acumulado e o caixa recebido do comprador e do banco. margem_operacional_viabilidade e margem_operacional_tendencia sao o lucro operacional somado sobre o VGV liquido somado, nao a media das margens das obras; desvio_margem_operacional e a diferenca entre elas. Fracoes (0,1 = 10%). So diretor e financeiro consultam.",
    colunas: ["obras", "vgv_bruto_tendencia", "vgv_vendido", "pct_vendido", "receita_apropriada", "poc", "custo_apropriado", "recebido_acumulado", "lucro_operacional_viabilidade", "lucro_operacional_tendencia", "margem_operacional_viabilidade", "margem_operacional_tendencia", "desvio_margem_operacional"],
    exemplos: [
      { pergunta: "Qual a margem operacional da carteira no estudo e na tendencia?", sql: "select obras, margem_operacional_viabilidade, margem_operacional_tendencia, desvio_margem_operacional from marts.dre_resumo_carteira" },
      { pergunta: "Qual o POC e o percentual vendido somando todas as obras?", sql: "select obras, vgv_bruto_tendencia, pct_vendido, poc from marts.dre_resumo_carteira" },
    ],
    perfis: ["diretor", "financeiro"],
  },
];

// Catalogo que vai para o prompt e para o validador de quem pergunta. perfil e o valor cru de app.perfil_atual.
export function catalogoDoPerfil(perfil: string | null): ViewCatalogo[] {
  return catalogoViews.filter((view) => !view.perfis || (perfil !== null && view.perfis.includes(perfil)));
}
