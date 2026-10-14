"""Gera o balancete mensal das SPEs da demo no formato do endpoint de balancete do ERP de origem.

Cada SPE tem um razão simulado em partida dobrada, mês a mês, desde o primeiro mês da obra. Os
valores seguem a escala dos dados já gerados: vendas de dados/sales.json, orçamento e avanço de
dados/building-cost-estimation-items.json, terreno, projetos e VGV do estudo de viabilidade. Do razão
saem as duas passagens do balancete, com e sem o zeramento mensal do resultado, de jan/2025 a out/2026.

Saída em dados/contabil: companies.json, trial-balance.json e mapa-contas.json. A semente é fixa:
rodar de novo gera os mesmos bytes.
"""

import json
import random
from collections import defaultdict
from datetime import date
from pathlib import Path

PASTA_DADOS = Path(__file__).resolve().parent.parent / "dados"
PASTA_SAIDA = PASTA_DADOS / "contabil"
PRIMEIRO_MES_SAIDA = date(2025, 1, 1)
ULTIMO_MES = date(2026, 10, 1)
# Os contratos de dados/sales.json vão até 22/09/2026; outubro repete a média dos meses anteriores.
MES_SEM_DADOS = date(2026, 10, 1)
SEMENTE = 2026

# Contas analíticas. Natureza D ou C é a do saldo normal; linha vazia quer dizer que a conta herda do
# prefixo sintético mapeado (ver PREFIXOS_MAPEADOS) ou que fica sem mapa de propósito.
CAIXA = "1.1.1.01.0001"
BANCO = "1.1.1.02.0001"
BANCO_VINCULADO = "1.1.1.02.0002"
APLICACAO = "1.1.1.03.0001"
CLIENTES = "1.1.2.01.0001"
PDD = "1.1.2.02.0001"
ESTOQUE = "1.1.3.01.0001"
ALMOXARIFADO = "1.1.3.02.0001"
ADIANTAMENTO_FORNECEDORES = "1.1.4.01.0001"
IMPOSTOS_RECUPERAR = "1.1.4.02.0001"
CAUCAO = "1.1.4.03.0001"
CORRETAGEM_APROPRIAR = "1.1.4.04.0001"
CORRETAGEM_APROPRIADA = "1.1.4.04.0002"
SEGURO_APROPRIAR = "1.1.4.05.0001"
ADIANTAMENTO_CONCILIAR = "1.1.4.09.0001"
ESTANDE = "1.2.1.01.0001"
DEPRECIACAO_ACUMULADA = "1.2.1.02.0001"
FORNECEDORES = "2.1.1.01.0001"
COMISSOES_PAGAR = "2.1.1.01.0002"
PESSOAL_PAGAR = "2.1.2.01.0001"
IMPOSTOS_PAGAR = "2.1.3.01.0001"
IRPJ_PAGAR = "2.1.3.02.0001"
TAC_PAGAR = "2.1.4.01.0001"
OBRIGACAO_TERRENO = "2.1.5.01.0001"
ADIANTAMENTO_CLIENTES = "2.1.6.01.0001"
PROVISAO_GARANTIA = "2.1.7.01.0001"
DIVIDENDOS_PAGAR = "2.1.8.01.0001"
DIVIDENDOS_PARTICIPANTES = "2.1.8.02.0001"
DIVIDENDOS_OSTENSIVOS = "2.1.8.03.0001"
EMPRESTIMO = "2.2.1.01.0001"
MUTUO = "2.2.2.01.0001"
SALDO_TERRENO = "2.2.3.01.0001"
CAPITAL = "2.3.1.01.0001"
AFAC = "2.3.1.02.0001"
LUCROS = "2.3.2.01.0001"
RESERVA = "2.3.2.02.0001"
AJUSTE_ANTERIOR = "2.3.2.03.0001"
RECEITA_VENDAS = "3.1.1.01.0001"
JUROS_VENDAS = "3.1.1.02.0001"
GANHO_DISTRATO = "3.1.2.01.0001"
RECEITA_SERVICOS = "3.1.2.02.0001"
OUTRAS_RECEITAS = "3.1.2.03.0001"
IMPOSTOS_VENDAS = "3.2.1.01.0001"
VENDAS_CANCELADAS = "3.2.1.02.0001"
PERDAS_CANCELADAS = "3.2.1.03.0001"
RECEITAS_FINANCEIRAS = "3.3.1.01.0001"
DESPESAS_FINANCEIRAS = "3.3.2.01.0001"
CMV = "4.1.1.01.0001"
CUSTO_GARANTIA = "4.1.1.02.0001"
OUTROS_CUSTOS = "4.1.1.03.0001"
JUROS_OBRA = "4.1.1.04.0001"
CORRETAGEM = "4.2.1.01.0001"
PUBLICIDADE = "4.2.1.02.0001"
DESPESAS_ADMINISTRATIVAS = "4.3.1.01.0001"
SEGUROS = "4.3.1.01.0002"
SENTENCAS = "4.3.1.02.0001"
SERVICOS_TERCEIROS_DESPESA = "4.3.1.03.0001"
DESPESAS_TRIBUTARIAS = "4.3.1.04.0001"
TAC_DESPESA = "4.3.1.05.0001"
DEPRECIACAO = "4.3.1.06.0001"
OUTRAS_DESPESAS = "4.3.1.07.0001"
DESPESA_PDD = "4.3.1.07.0002"
IRPJ_CSLL = "4.4.1.01.0001"
CUSTO_TERRENO = "5.1.1.01.0001"
CUSTO_PROJETOS = "5.1.2.01.0001"
CUSTO_LEGALIZACAO = "5.1.3.01.0001"
MATERIAIS = "5.2.1.01.0001"
SALARIOS = "5.2.1.02.0001"
ENCARGOS_SOCIAIS = "5.2.1.03.0001"
ENCARGOS_COMPLEMENTARES = "5.2.1.04.0001"
SERVICOS_TERCEIROS_OBRA = "5.2.1.05.0001"
GASTOS_GERAIS = "5.2.1.06.0001"
TRANSFERENCIA_ESTOQUE = "5.9.2.01.0001"
APURACAO = "6.1.1.01.0001"
SALDO_ABERTURA = "6.1.2.01.0001"

# (conta, nome, natureza, linha direta)
CONTAS = [
    (CAIXA, "Caixa Fixo", "D", "caixa"),
    (BANCO, "Banco Principal - Conta Movimento", "D", None),
    (BANCO_VINCULADO, "Banco Financiador - Conta Vinculada da Obra", "D", None),
    (APLICACAO, "Aplicações Financeiras de Liquidez Imediata", "D", None),
    (CLIENTES, "Clientes - Unidades Vendidas", "D", "receber_incorporacao"),
    (PDD, "(-) Provisão para Devedores Duvidosos", "C", "receber_ajustes_pdd"),
    (ESTOQUE, "Imóveis em Construção - Incorporação", "D", "estoque_imoveis_construcao"),
    (ALMOXARIFADO, "Materiais no Almoxarifado da Obra", "D", "estoque_almoxarifado"),
    (ADIANTAMENTO_FORNECEDORES, "Adiantamentos a Fornecedores de Obra", "D", "adiantamentos_terceiros"),
    (IMPOSTOS_RECUPERAR, "Impostos Retidos a Recuperar", "D", "impostos_recuperar"),
    (CAUCAO, "Cauções e Depósitos Vinculados", "D", "depositos_judiciais"),
    (CORRETAGEM_APROPRIAR, "Despesas de Corretagem a Apropriar", "D", "corretagem_apropriar"),
    (CORRETAGEM_APROPRIADA, "(-) Despesas de Corretagem Apropriadas", "C", "corretagem_apropriada"),
    (SEGURO_APROPRIAR, "Prêmio de Seguro de Obra a Apropriar", "D", "seguro_apropriar"),
    (ADIANTAMENTO_CONCILIAR, "Adiantamentos Diversos a Conciliar", "D", None),
    (ESTANDE, "Estande de Vendas e Apartamento Decorado", "D", "imobilizado"),
    (DEPRECIACAO_ACUMULADA, "(-) Depreciação Acumulada do Estande", "C", "depreciacao_acumulada"),
    (FORNECEDORES, "Fornecedores de Materiais e Serviços", "C", "fornecedores"),
    (COMISSOES_PAGAR, "Comissões de Corretagem a Pagar", "C", None),
    (PESSOAL_PAGAR, "Salários e Encargos Trabalhistas a Pagar", "C", "salarios_pagar"),
    (IMPOSTOS_PAGAR, "Impostos sobre a Receita a Pagar", "C", None),
    (IRPJ_PAGAR, "IRPJ e CSLL a Pagar", "C", None),
    (TAC_PAGAR, "Taxa de Administração Central a Pagar", "C", "taxa_administracao_pagar"),
    (OBRIGACAO_TERRENO, "Obrigações por Aquisição de Terreno", "C", "obrigacoes_terreno"),
    (ADIANTAMENTO_CLIENTES, "Adiantamentos de Clientes", "C", "adiantamento_clientes"),
    (PROVISAO_GARANTIA, "Provisão para Garantia e Assistência Técnica", "C", "provisao_assistencia_tecnica"),
    (DIVIDENDOS_PAGAR, "Dividendos a Pagar", "C", "dividendos_pagar"),
    (DIVIDENDOS_PARTICIPANTES, "Dividendos a Pagar - Sócios Participantes", "C", "dividendos_pagar_participantes"),
    (DIVIDENDOS_OSTENSIVOS, "Dividendos a Pagar - Sócios Ostensivos", "C", "dividendos_pagar_ostensivos"),
    (EMPRESTIMO, "Financiamento à Produção", "C", "emprestimos_bancarios"),
    (MUTUO, "Mútuo com Sócios", "C", "mutuo_pagar"),
    (SALDO_TERRENO, "Saldo a Pagar de Terreno ao Proprietário", "C", "saldo_pagar_terreno"),
    (CAPITAL, "Capital Social Integralizado", "C", "aporte_capital"),
    (AFAC, "Adiantamento para Futuro Aumento de Capital", "C", "capital_especial"),
    (LUCROS, "Lucros Acumulados", "C", "lucros_acumulados"),
    (RESERVA, "Reserva Legal", "C", "reserva_legal"),
    (AJUSTE_ANTERIOR, "Ajustes de Exercícios Anteriores", "C", "lucros_acumulados"),
    (RECEITA_VENDAS, "Receita de Vendas de Unidades Imobiliárias", "C", "receita_vendas_incorporacao"),
    (JUROS_VENDAS, "Juros sobre Vendas a Prazo", "C", "juros_tabela_price"),
    (GANHO_DISTRATO, "Ganho com Distratos de Vendas", "C", "ganho_distrato"),
    (RECEITA_SERVICOS, "Receita de Serviços e Taxas de Contrato", "C", "receita_servicos"),
    (OUTRAS_RECEITAS, "Outras Receitas Operacionais", "C", "outras_receitas"),
    (IMPOSTOS_VENDAS, "(-) Impostos sobre Vendas", "D", "impostos_vendas"),
    (VENDAS_CANCELADAS, "(-) Vendas Canceladas e Abatimentos", "D", "vendas_canceladas_abatimentos"),
    (PERDAS_CANCELADAS, "(-) Perdas com Vendas Canceladas", "D", "perdas_vendas_canceladas"),
    (RECEITAS_FINANCEIRAS, "Rendimentos de Aplicações Financeiras", "C", "receitas_financeiras"),
    (DESPESAS_FINANCEIRAS, "(-) Tarifas Bancárias e IOF", "D", "despesas_financeiras"),
    (CMV, "Custo das Unidades Vendidas", "D", "custo_unidades_vendidas"),
    (CUSTO_GARANTIA, "Custo da Provisão de Garantia", "D", "custo_assistencia_tecnica"),
    (OUTROS_CUSTOS, "Outros Custos de Incorporação", "D", "outros_custos"),
    (JUROS_OBRA, "Juros sobre Financiamento da Obra", "D", "juros_financiamento_obra"),
    (CORRETAGEM, "Corretagem sobre Vendas", "D", "corretagem"),
    (PUBLICIDADE, "Publicidade e Propaganda", "D", "publicidade"),
    (DESPESAS_ADMINISTRATIVAS, "Despesas Administrativas Gerais", "D", None),
    (SEGUROS, "Seguros e Prêmios", "D", None),
    (SENTENCAS, "Sentenças Cíveis e Trabalhistas", "D", "sentencas"),
    (SERVICOS_TERCEIROS_DESPESA, "Serviços de Terceiros Administrativos", "D", "servicos_terceiros_despesa"),
    (DESPESAS_TRIBUTARIAS, "Taxas e Despesas Tributárias", "D", "despesas_tributarias"),
    (TAC_DESPESA, "Taxa de Administração Central", "D", "taxa_administracao_central"),
    (DEPRECIACAO, "Depreciação do Estande", "D", "depreciacao"),
    (OUTRAS_DESPESAS, "Outras Despesas Operacionais", "D", None),
    (DESPESA_PDD, "Despesa com Devedores Duvidosos", "D", None),
    (IRPJ_CSLL, "IRPJ e CSLL do Período", "D", "irpj_csll"),
    (CUSTO_TERRENO, "Custo de Aquisição do Terreno", "D", "custo_terreno"),
    (CUSTO_PROJETOS, "Custo de Projetos e Estudos", "D", "custo_projetos"),
    (CUSTO_LEGALIZACAO, "Custo de Legalização e Licenças", "D", "custo_legalizacao"),
    (MATERIAIS, "Materiais Aplicados nas Obras", "D", "materiais_aplicados"),
    (SALARIOS, "Salários e Proventos da Obra", "D", "salarios_proventos"),
    (ENCARGOS_SOCIAIS, "Encargos Sociais da Obra", "D", "encargos_sociais"),
    (ENCARGOS_COMPLEMENTARES, "Encargos Complementares da Obra", "D", "encargos_complementares"),
    (SERVICOS_TERCEIROS_OBRA, "Serviços de Terceiros da Obra", "D", "servicos_terceiros_obra"),
    (GASTOS_GERAIS, "Gastos Gerais de Obra", "D", "gastos_gerais_obra"),
    (TRANSFERENCIA_ESTOQUE, "(-) Transferência do Custo para Imóveis em Construção", "C", "transferencia_custo_estoque"),
    (APURACAO, "Apuração do Resultado do Mês", "C", "apuracao_resultado"),
    (SALDO_ABERTURA, "Saldo de Abertura", "C", "saldo_abertura"),
]

# Prefixos sintéticos mapeados. A conta analítica com linha própria vence; senão vale o prefixo mais longo.
PREFIXOS_MAPEADOS = {
    "1.1.1.02": "bancos",
    "1.1.1.03": "aplicacoes_financeiras",
    "2.1.1.01": "fornecedores",
    "2.1.3": "impostos_pagar",
    "4.3.1": "outras_despesas",
    "4.3.1.01": "despesas_administrativas",
}

NOMES_SINTETICAS = {
    "1": "ATIVO", "1.1": "ATIVO CIRCULANTE", "1.1.1": "Disponibilidades", "1.1.1.01": "Caixa",
    "1.1.1.02": "Bancos Conta Movimento", "1.1.1.03": "Aplicações Financeiras", "1.1.2": "Contas a Receber",
    "1.1.2.01": "Clientes de Incorporação", "1.1.2.02": "Ajustes de Contas a Receber", "1.1.3": "Estoques",
    "1.1.3.01": "Imóveis em Construção", "1.1.3.02": "Materiais em Almoxarifado",
    "1.1.4": "Outros Ativos Circulantes", "1.1.4.01": "Adiantamentos", "1.1.4.02": "Impostos a Recuperar",
    "1.1.4.03": "Cauções e Depósitos", "1.1.4.04": "Despesas de Corretagem", "1.1.4.05": "Seguros a Apropriar",
    "1.1.4.09": "Valores a Classificar", "1.2": "ATIVO NÃO CIRCULANTE", "1.2.1": "Imobilizado",
    "1.2.1.01": "Estande de Vendas", "1.2.1.02": "Depreciação Acumulada",
    "2": "PASSIVO E PATRIMÔNIO LÍQUIDO", "2.1": "PASSIVO CIRCULANTE", "2.1.1": "Fornecedores",
    "2.1.1.01": "Fornecedores e Credores Diversos", "2.1.2": "Obrigações Trabalhistas",
    "2.1.2.01": "Salários e Encargos", "2.1.3": "Obrigações Tributárias",
    "2.1.3.01": "Impostos sobre a Receita", "2.1.3.02": "IRPJ e CSLL", "2.1.4": "Taxa de Administração Central",
    "2.1.4.01": "TAC a Pagar", "2.1.5": "Obrigações por Aquisição de Terreno",
    "2.1.5.01": "Terreno a Prazo", "2.1.6": "Obrigações com Clientes", "2.1.6.01": "Adiantamentos de Clientes",
    "2.1.7": "Provisões", "2.1.7.01": "Provisão para Garantia", "2.1.8": "Dividendos a Pagar",
    "2.1.8.01": "Dividendos Gerais", "2.1.8.02": "Dividendos de Participantes", "2.1.8.03": "Dividendos de Ostensivos",
    "2.2": "PASSIVO NÃO CIRCULANTE", "2.2.1": "Financiamentos", "2.2.1.01": "Financiamento à Produção",
    "2.2.2": "Partes Relacionadas", "2.2.2.01": "Mútuo com Sócios", "2.2.3": "Terreno a Pagar a Sócios",
    "2.2.3.01": "Saldo a Pagar de Terreno", "2.3": "PATRIMÔNIO LÍQUIDO", "2.3.1": "Capital",
    "2.3.1.01": "Capital Social", "2.3.1.02": "Adiantamento para Aumento de Capital",
    "2.3.2": "Lucros e Reservas", "2.3.2.01": "Lucros Acumulados", "2.3.2.02": "Reservas de Lucros",
    "2.3.2.03": "Ajustes de Exercícios Anteriores",
    "3": "RECEITAS", "3.1": "RECEITA BRUTA", "3.1.1": "Receita de Vendas", "3.1.1.01": "Vendas de Unidades",
    "3.1.1.02": "Juros sobre Vendas", "3.1.2": "Outras Receitas", "3.1.2.01": "Distratos",
    "3.1.2.02": "Serviços", "3.1.2.03": "Receitas Diversas", "3.2": "DEDUÇÕES", "3.2.1": "Deduções de Vendas",
    "3.2.1.01": "Impostos sobre Vendas", "3.2.1.02": "Vendas Canceladas", "3.2.1.03": "Perdas com Cancelamentos",
    "3.3": "EFEITOS FINANCEIROS", "3.3.1": "Receitas Financeiras", "3.3.1.01": "Rendimentos de Aplicações",
    "3.3.2": "Despesas Financeiras", "3.3.2.01": "Tarifas Bancárias",
    "4": "CUSTOS E DESPESAS", "4.1": "CUSTOS DAS VENDAS", "4.1.1": "Custos de Incorporação",
    "4.1.1.01": "Custo das Unidades", "4.1.1.02": "Garantia", "4.1.1.03": "Outros Custos",
    "4.1.1.04": "Juros da Obra", "4.2": "DESPESAS DE VENDAS", "4.2.1": "Despesas Comerciais",
    "4.2.1.01": "Corretagem", "4.2.1.02": "Publicidade", "4.3": "DESPESAS FIXAS",
    "4.3.1": "Despesas Operacionais", "4.3.1.01": "Despesas Administrativas", "4.3.1.02": "Sentenças",
    "4.3.1.03": "Serviços de Terceiros", "4.3.1.04": "Despesas Tributárias", "4.3.1.05": "Taxa de Administração Central",
    "4.3.1.06": "Depreciação", "4.3.1.07": "Outras Despesas", "4.4": "TRIBUTOS SOBRE O LUCRO",
    "4.4.1": "IRPJ e CSLL", "4.4.1.01": "IRPJ e CSLL do Período",
    "5": "CUSTO DE OBRA", "5.1": "CUSTOS PRELIMINARES", "5.1.1": "Terreno", "5.1.1.01": "Aquisição do Terreno",
    "5.1.2": "Projetos", "5.1.2.01": "Projetos e Estudos", "5.1.3": "Legalização", "5.1.3.01": "Licenças",
    "5.2": "CUSTO DE CONSTRUÇÃO", "5.2.1": "Custos Diretos", "5.2.1.01": "Materiais", "5.2.1.02": "Salários",
    "5.2.1.03": "Encargos Sociais", "5.2.1.04": "Encargos Complementares", "5.2.1.05": "Serviços de Terceiros",
    "5.2.1.06": "Gastos Gerais", "5.9": "TRANSFERÊNCIAS", "5.9.2": "Transferência para Estoque",
    "5.9.2.01": "Transferência do Custo",
    "6": "APURAÇÃO", "6.1": "CONTAS DE APURAÇÃO", "6.1.1": "Resultado do Mês", "6.1.1.01": "Apuração do Resultado",
    "6.1.2": "Abertura", "6.1.2.01": "Saldo de Abertura",
}
GRUPOS_ERP = {"1": "ASSETS", "2": "LIABILITIES", "3": "INCOME", "4": "EXPENSES", "5": "EXPENSES", "6": "TRANSITION"}
GRUPOS_RESULTADO = ("3", "4", "5")
NATUREZA_SINTETICA = {"1": "D", "2": "C", "3": "C", "4": "D", "5": "D", "6": "C"}

PERFIS = {
    11: {
        "obra": 101, "chaves": date(2027, 6, 1), "capital_inicial": 6_000_000, "piso_caixa": 250_000,
        "conta_aporte": CAPITAL, "adm_base": 17_000, "publicidade_base": 8_000, "tributarias_base": 2_000,
        "outras_base": 2_000, "taxa_tac": 0.010, "tac_base": 1_500, "taxa_comissao": 0.03, "limite_financiamento": 0.38, "juros_mensal": 0.0095,
        "terreno": ((BANCO, 0.30), (OBRIGACAO_TERRENO, 0.70)), "prazo_terreno": 24, "taxa_recebimento": 0.014,
        "imposto_vendas": 0.04, "irpj": 0.0, "estande": 0.012, "seguro": 0.0025, "outras_receitas": True,
        "mutuo": {date(2025, 3, 1): 1_200_000, date(2026, 8, 1): -600_000},
        "dividendos": {date(2025, 12, 1): (0.25, (DIVIDENDOS_PARTICIPANTES, DIVIDENDOS_OSTENSIVOS))},
        "reserva_legal": (date(2025, 12, 1),),
    },
    12: {
        "obra": 102, "chaves": date(2027, 2, 1), "capital_inicial": 3_500_000, "piso_caixa": 150_000,
        "conta_aporte": AFAC, "adm_base": 11_000, "publicidade_base": 4_000, "tributarias_base": 1_400,
        "outras_base": 1_200, "taxa_tac": 0.008, "tac_base": 1_000, "taxa_comissao": 0.03, "limite_financiamento": 0.30, "juros_mensal": 0.0095,
        "terreno": ((BANCO, 0.40), (OBRIGACAO_TERRENO, 0.35), (SALDO_TERRENO, 0.25)), "prazo_terreno": 18,
        "taxa_recebimento": 0.012, "imposto_vendas": 0.04, "irpj": 0.0, "estande": 0.010, "seguro": 0.003, "outras_receitas": False,
        "mutuo": {}, "dividendos": {}, "reserva_legal": (),
        "conciliar": {date(2026, 7, 1): 18_450, date(2026, 9, 1): 6_320},
    },
    13: {
        "obra": 103, "chaves": date(2026, 5, 1), "capital_inicial": 1_800_000, "piso_caixa": 80_000,
        "conta_aporte": CAPITAL, "adm_base": 4_000, "publicidade_base": 800, "tributarias_base": 700,
        "outras_base": 600, "taxa_tac": 0.005, "tac_base": 500, "taxa_comissao": 0.015, "limite_financiamento": 0.28, "juros_mensal": 0.0095,
        "terreno": ((BANCO, 0.60), (OBRIGACAO_TERRENO, 0.40)), "prazo_terreno": 12, "taxa_recebimento": 0.020,
        "imposto_vendas": 0.0365, "irpj": 0.0267, "estande": 0.004, "seguro": 0.0015, "outras_receitas": True,
        "mutuo": {}, "dividendos": {date(2026, 6, 1): (0.20, (DIVIDENDOS_PAGAR,))}, "reserva_legal": (),
        "ajuste_anterior": {date(2026, 3, 1): 36_750}, "sentenca": {date(2026, 8, 1): 18_500},
    },
}
PASSO_APORTE = 5_000_000
TAXA_APLICACAO = 0.0095
IR_APLICACAO = 0.15
FRACAO_VINCULADA = 0.05
TAXA_JUROS_VENDAS = 0.003
TAXA_PDD = 0.01
TAXA_GARANTIA = 0.006
PESOS_PROJETOS = (30, 25, 18, 12, 9, 6)
PESOS_LEGALIZACAO = (1, 2, 3, 3, 2, 1, 1, 1)
PARTES_OBRA = (
    (MATERIAIS, 0.340), (SALARIOS, 0.150), (ENCARGOS_SOCIAIS, 0.078),
    (ENCARGOS_COMPLEMENTARES, 0.0315), (SERVICOS_TERCEIROS_OBRA, 0.340), (GASTOS_GERAIS, 0.0605),
)


def reais(valor):
    return round(valor * 100)


def primeiro_dia(d):
    return date(d.year, d.month, 1)


def somar_meses(d, n):
    mes = d.month - 1 + n
    return date(d.year + mes // 12, mes % 12 + 1, 1)


def indice_mes(inicio, mes):
    return (mes.year - inicio.year) * 12 + mes.month - inicio.month


def distribuir(total, pesos):
    """Reparte o total em centavos pelos pesos; a última parte absorve o arredondamento."""
    soma = sum(pesos)
    partes, acumulado = [], 0
    for posicao, peso in enumerate(pesos):
        parte = total - acumulado if posicao == len(pesos) - 1 else round(total * peso / soma)
        partes.append(parte)
        acumulado += parte
    return partes


def prefixos(conta):
    partes = conta.split(".")
    return [".".join(partes[:n]) for n in range(1, len(partes))]


def resolver_linha(conta, diretas, por_prefixo):
    if diretas.get(conta):
        return diretas[conta]
    for prefixo in reversed(prefixos(conta)):
        if prefixo in por_prefixo:
            return por_prefixo[prefixo]
    return None


class Razao:
    """Lançamentos mensais agregados. movimento[(mes, conta)] = [débito, crédito, débito de zeramento, crédito de zeramento]."""

    def __init__(self):
        self.movimento = {}
        self.saldo = defaultdict(int)

    def lancar(self, mes, debito, credito, valor, zeramento=False):
        if valor == 0:
            return
        if valor < 0:
            debito, credito, valor = credito, debito, -valor
        base = 2 if zeramento else 0
        self.movimento.setdefault((mes, debito), [0, 0, 0, 0])[base] += valor
        self.movimento.setdefault((mes, credito), [0, 0, 0, 0])[base + 1] += valor
        self.saldo[debito] += valor
        self.saldo[credito] -= valor

    def credor(self, conta):
        return -self.saldo[conta]


def ler_json(caminho):
    return json.loads(caminho.read_text(encoding="utf-8"))


# O(contratos + itens de orçamento + estudos), lidos uma vez por obra.
def escala_da_obra(id_obra):
    """Vendas e cancelamentos por mês (centavos), avanço físico, orçamento e dados do estudo da obra."""
    brutas, canceladas = defaultdict(int), defaultdict(int)
    for contrato in ler_json(PASTA_DADOS / "sales.json")["data"]:
        if contrato["enterpriseId"] != id_obra:
            continue
        brutas[primeiro_dia(date.fromisoformat(contrato["contractDate"]))] += reais(contrato["value"])
        if contrato["situation"] == "3" and contrato.get("cancellationDate"):
            canceladas[primeiro_dia(date.fromisoformat(contrato["cancellationDate"]))] += reais(contrato["value"])
    orcamento = medido = 0.0
    for item in ler_json(PASTA_DADOS / "building-cost-estimation-items.json")["data"]:
        if item["buildingId"] == id_obra:
            orcamento += item["totalPrice"]
            medido += item["totalPrice"] * item["percentComplete"] / 100
    estudo = next(e for e in ler_json(PASTA_DADOS / "viabilidade" / "estudos.json") if e["id_origem"] == id_obra)
    linhas = estudo["linhas"]
    return {
        "vendas": brutas, "cancelamentos": canceladas, "orcamento_obra": reais(orcamento),
        "avanco": medido / orcamento, "terreno": reais(linhas["custo_terreno"]),
        "projetos": reais(linhas["custo_projetos"]), "legalizacao": reais(linhas["custo_licenciamento"]),
        "vgv": reais(linhas["vgv_bruto"]), "primeira_venda": min(brutas),
    }


class Simulador:
    """Um razão de SPE: custo de obra, vendas pelo POC, recebimentos, financiamento, tesouraria e zeramento."""

    def __init__(self, id_empresa, perfil, escala):
        self.id_empresa = id_empresa
        self.perfil = perfil
        self.escala = escala
        self.sorteio = random.Random(SEMENTE * 100 + id_empresa)
        self.razao = Razao()
        self.inicio = escala["primeira_venda"]
        self.meses = [somar_meses(self.inicio, n) for n in range(indice_mes(self.inicio, ULTIMO_MES) + 1)]
        self.indice_chaves = indice_mes(self.inicio, perfil["chaves"])
        self.orcamento_total = (escala["terreno"] + escala["projetos"] + escala["legalizacao"]
                                + escala["orcamento_obra"])
        self.cronograma = self.montar_cronograma()
        self.vendas = self.projetar(escala["vendas"])
        self.cancelamentos = [escala["cancelamentos"].get(mes, 0) for mes in self.meses]
        self.parcelas_terreno = self.montar_parcelas_terreno()
        self.base = self.receita_acumulada = self.custo_acumulado = self.cmv_acumulado = 0
        self.recebido_acumulado = self.financiamento_liberado = self.lucro_ano = 0
        self.premio_seguro = self.parcela_seguro = self.parcela_estande = 0
        self.abertura = {}
        self.recebimento_mes = 0

    def projetar(self, por_mes):
        """Vendas do mês; o mês sem dado repete a média móvel dos últimos doze, com variação fixa."""
        serie = [por_mes.get(mes, 0) for mes in self.meses]
        for posicao, mes in enumerate(self.meses):
            if mes >= MES_SEM_DADOS:
                media = sum(serie[max(0, posicao - 12):posicao]) / min(12, posicao)
                serie[posicao] = round(media * self.sorteio.uniform(0.9, 1.1))
        return serie

    def montar_cronograma(self):
        """Custo de terreno, projetos, legalização e obra por mês; a obra chega ao avanço medido em out/2026."""
        n = len(self.meses)
        escala = self.escala
        projetos = [0] * n
        legalizacao = [0] * n
        for posicao, parte in enumerate(distribuir(escala["projetos"], PESOS_PROJETOS)):
            projetos[posicao] = parte
        for posicao, parte in enumerate(distribuir(escala["legalizacao"], PESOS_LEGALIZACAO)):
            legalizacao[1 + posicao] = parte
        inicio_obra = 4
        fim_obra = min(n - 1, self.indice_chaves - 1)
        self.fim_obra = fim_obra
        self.obra_concluida = escala["avanco"] >= 0.999
        pesos = []
        for posicao in range(inicio_obra, fim_obra + 1):
            rampa = min(1.0, 0.25 + 0.15 * (posicao - inicio_obra))
            cauda = min(1.0, (fim_obra - posicao + 1) / 4) if escala["avanco"] >= 0.8 else 1.0
            pesos.append(rampa * cauda * self.sorteio.uniform(0.88, 1.12))
        total_obra = round(escala["orcamento_obra"] * escala["avanco"])
        obra = [0] * n
        for posicao, valor in zip(range(inicio_obra, fim_obra + 1), distribuir(total_obra, pesos)):
            obra[posicao] = valor
        itens = []
        for posicao in range(n):
            partes = {conta: 0 for conta, _ in PARTES_OBRA}
            if obra[posicao]:
                ruido = [peso * (self.sorteio.uniform(0.9, 1.1) if conta in (MATERIAIS, SALARIOS) else 1.0)
                         for conta, peso in PARTES_OBRA]
                partes = dict(zip((conta for conta, _ in PARTES_OBRA), distribuir(obra[posicao], ruido)))
            itens.append({
                CUSTO_TERRENO: escala["terreno"] if posicao == 0 else 0,
                CUSTO_PROJETOS: projetos[posicao], CUSTO_LEGALIZACAO: legalizacao[posicao], **partes,
            })
        return itens

    def montar_parcelas_terreno(self):
        parcelas = {OBRIGACAO_TERRENO: {}, SALDO_TERRENO: {}}
        for conta, fracao in self.perfil["terreno"]:
            if conta == OBRIGACAO_TERRENO:
                valor = round(self.escala["terreno"] * fracao)
                for posicao, parte in enumerate(distribuir(valor, [1] * self.perfil["prazo_terreno"])):
                    parcelas[conta][1 + posicao] = parte
            elif conta == SALDO_TERRENO:
                valor = round(self.escala["terreno"] * fracao)
                for posicao, parte in enumerate(distribuir(valor, [1] * 12)):
                    parcelas[conta][13 + posicao] = parte
        return parcelas

    # O(meses x contas movimentadas por mês): cerca de 25 meses e 70 contas por SPE.
    def executar(self):
        for posicao, mes in enumerate(self.meses):
            razao = self.razao
            self.abertura = {conta: max(razao.credor(conta), 0) for conta in (
                FORNECEDORES, COMISSOES_PAGAR, PESSOAL_PAGAR, IMPOSTOS_PAGAR, IRPJ_PAGAR, TAC_PAGAR,
                EMPRESTIMO)}
            self.abertura[APLICACAO] = razao.saldo[APLICACAO]
            if posicao == 0:
                self.constituir(mes)
            custo_mes, obra_mes = self.lancar_custos(posicao, mes)
            self.lancar_vendas(posicao, mes, custo_mes)
            self.lancar_despesas(posicao, mes, obra_mes)
            self.lancar_financiamento(posicao, mes, obra_mes)
            self.lancar_pagamentos(posicao, mes)
            self.lancar_eventos(posicao, mes)
            self.lancar_tesouraria(mes)
            self.fechar_mes(posicao, mes)
        return self.razao

    def constituir(self, mes):
        razao = self.razao
        razao.lancar(mes, BANCO, CAPITAL, self.perfil["capital_inicial"] * 100 - 300_000)
        razao.lancar(mes, CAIXA, CAPITAL, 300_000)

    def lancar_custos(self, posicao, mes):
        razao, itens = self.razao, self.cronograma[posicao]
        terreno = itens[CUSTO_TERRENO]
        if terreno:
            restante = terreno
            for conta, fracao in self.perfil["terreno"][:-1]:
                parte = round(terreno * fracao)
                razao.lancar(mes, CUSTO_TERRENO, conta, parte)
                restante -= parte
            razao.lancar(mes, CUSTO_TERRENO, self.perfil["terreno"][-1][0], restante)
        razao.lancar(mes, CUSTO_PROJETOS, FORNECEDORES, itens[CUSTO_PROJETOS])
        razao.lancar(mes, CUSTO_LEGALIZACAO, FORNECEDORES, itens[CUSTO_LEGALIZACAO])
        materiais = itens[MATERIAIS]
        estoque_alvo = 0 if self.obra_concluida and posicao >= self.fim_obra else round(0.3 * materiais)
        compras = materiais + estoque_alvo - razao.saldo[ALMOXARIFADO]
        razao.lancar(mes, ALMOXARIFADO, FORNECEDORES, compras)
        razao.lancar(mes, MATERIAIS, ALMOXARIFADO, materiais)
        for conta in (SERVICOS_TERCEIROS_OBRA, GASTOS_GERAIS):
            razao.lancar(mes, conta, FORNECEDORES, itens[conta])
        for conta in (SALARIOS, ENCARGOS_SOCIAIS, ENCARGOS_COMPLEMENTARES):
            razao.lancar(mes, conta, PESSOAL_PAGAR, itens[conta])
        obra_mes = sum(itens[conta] for conta, _ in PARTES_OBRA)
        custo_mes = obra_mes + terreno + itens[CUSTO_PROJETOS] + itens[CUSTO_LEGALIZACAO]
        razao.lancar(mes, ESTOQUE, TRANSFERENCIA_ESTOQUE, custo_mes)
        adiantamento_alvo = round(0.25 * (materiais + itens[SERVICOS_TERCEIROS_OBRA]))
        diferenca = adiantamento_alvo - razao.saldo[ADIANTAMENTO_FORNECEDORES]
        if diferenca > 0:
            razao.lancar(mes, ADIANTAMENTO_FORNECEDORES, BANCO, diferenca)
        else:
            razao.lancar(mes, FORNECEDORES, ADIANTAMENTO_FORNECEDORES, -diferenca)
        return custo_mes, obra_mes

    def lancar_vendas(self, posicao, mes, custo_mes):
        razao, perfil = self.razao, self.perfil
        novas, canceladas = self.vendas[posicao], self.cancelamentos[posicao]
        base_anterior = self.base
        self.base = base_anterior + novas - canceladas
        self.custo_acumulado += custo_mes
        poc = min(1.0, self.custo_acumulado / self.orcamento_total)
        acumulada = round(poc * self.base)
        variacao = acumulada - self.receita_acumulada
        self.receita_acumulada = acumulada
        estorno = round(poc * canceladas)
        razao.lancar(mes, CLIENTES, RECEITA_VENDAS, variacao + estorno)
        razao.lancar(mes, VENDAS_CANCELADAS, CLIENTES, estorno)
        razao.lancar(mes, IMPOSTOS_VENDAS, IMPOSTOS_PAGAR, round(perfil["imposto_vendas"] * variacao))
        razao.lancar(mes, IRPJ_CSLL, IRPJ_PAGAR, round(perfil["irpj"] * variacao))
        cmv_acumulado = round(min(1.0, self.base / self.escala["vgv"]) * self.custo_acumulado)
        razao.lancar(mes, CMV, ESTOQUE, cmv_acumulado - self.cmv_acumulado)
        razao.lancar(mes, OUTROS_CUSTOS, FORNECEDORES, round(0.004 * (cmv_acumulado - self.cmv_acumulado)))
        self.cmv_acumulado = cmv_acumulado
        razao.lancar(mes, CORRETAGEM_APROPRIAR, COMISSOES_PAGAR, round(perfil["taxa_comissao"] * (novas - canceladas)))
        razao.lancar(mes, CORRETAGEM, CORRETAGEM_APROPRIADA, round(perfil["taxa_comissao"] * variacao))
        razao.lancar(mes, CUSTO_GARANTIA, PROVISAO_GARANTIA, round(TAXA_GARANTIA * variacao))
        razao.lancar(mes, BANCO, RECEITA_SERVICOS, round(0.0015 * novas))
        razao.lancar(mes, BANCO, GANHO_DISTRATO, round(0.12 * canceladas))
        razao.lancar(mes, PERDAS_CANCELADAS, BANCO, round(0.05 * canceladas))
        if posicao % 3 == 1 and perfil["outras_receitas"]:
            razao.lancar(mes, BANCO, OUTRAS_RECEITAS, self.sorteio.randrange(120_000, 480_000, 100))
        self.recebimento_mes = self.recebimento(posicao, base_anterior, novas)
        razao.lancar(mes, BANCO, CLIENTES, self.recebimento_mes)
        self.recebido_acumulado += self.recebimento_mes
        razao.lancar(mes, CLIENTES, JUROS_VENDAS, round(TAXA_JUROS_VENDAS * max(razao.saldo[CLIENTES], 0)))
        posicao_liquida = razao.saldo[CLIENTES] + razao.saldo[ADIANTAMENTO_CLIENTES]
        razao.lancar(mes, CLIENTES, ADIANTAMENTO_CLIENTES, max(posicao_liquida, 0) - razao.saldo[CLIENTES])
        razao.lancar(mes, DESPESA_PDD, PDD, round(TAXA_PDD * max(razao.saldo[CLIENTES], 0)) - razao.credor(PDD))

    def recebimento(self, posicao, base_anterior, novas):
        if posicao == self.indice_chaves:
            taxa = 0.5
        elif posicao > self.indice_chaves:
            taxa = 0.07
        else:
            taxa = self.perfil["taxa_recebimento"]
        a_receber = max(base_anterior - self.recebido_acumulado, 0)
        limite = max(self.base - self.recebido_acumulado, 0)
        return min(limite, round(taxa * a_receber + 0.12 * novas))

    def lancar_despesas(self, posicao, mes, obra_mes):
        razao, perfil = self.razao, self.perfil
        fator = (1 + 0.04 * posicao / 12) * (0.6 if posicao > self.indice_chaves else 1.0)
        administrativas = round(reais(perfil["adm_base"]) * fator * self.sorteio.uniform(0.92, 1.08))
        razao.lancar(mes, DESPESAS_ADMINISTRATIVAS, FORNECEDORES, administrativas)
        razao.lancar(mes, SERVICOS_TERCEIROS_DESPESA, FORNECEDORES, round(0.35 * administrativas))
        razao.lancar(mes, DESPESAS_TRIBUTARIAS, FORNECEDORES,
                     round(reais(perfil["tributarias_base"]) * self.sorteio.uniform(0.8, 1.2)))
        razao.lancar(mes, OUTRAS_DESPESAS, FORNECEDORES,
                     round(reais(perfil["outras_base"]) * self.sorteio.uniform(0.5, 1.5)))
        razao.lancar(mes, TAC_DESPESA, TAC_PAGAR, round(perfil["taxa_tac"] * obra_mes) + reais(perfil["tac_base"]))
        ritmo = 1.0 if posicao < 18 else 0.4
        razao.lancar(mes, PUBLICIDADE, FORNECEDORES,
                     round(reais(perfil["publicidade_base"]) * ritmo * self.sorteio.uniform(0.85, 1.15)
                           + 0.007 * self.vendas[posicao]))
        if posicao == 1:
            capex = round(perfil["estande"] * self.escala["orcamento_obra"])
            razao.lancar(mes, ESTANDE, FORNECEDORES, capex)
            self.parcela_estande = round(capex / 36)
        if posicao >= 2:
            depreciacao = min(self.parcela_estande, razao.saldo[ESTANDE] + razao.saldo[DEPRECIACAO_ACUMULADA])
            razao.lancar(mes, DEPRECIACAO, DEPRECIACAO_ACUMULADA, depreciacao)
        if posicao == 2:
            razao.lancar(mes, CAUCAO, BANCO, round(0.002 * self.escala["vgv"]))
        if posicao % 12 == 2:
            self.premio_seguro = round(perfil["seguro"] * self.escala["orcamento_obra"])
            self.parcela_seguro = round(self.premio_seguro / 12)
            razao.lancar(mes, SEGURO_APROPRIAR, BANCO, self.premio_seguro)
        if self.parcela_seguro:
            razao.lancar(mes, SEGUROS, SEGURO_APROPRIAR, min(self.parcela_seguro, razao.saldo[SEGURO_APROPRIAR]))

    def lancar_financiamento(self, posicao, mes, obra_mes):
        razao, perfil = self.razao, self.perfil
        razao.lancar(mes, JUROS_OBRA, BANCO, round(perfil["juros_mensal"] * self.abertura[EMPRESTIMO]))
        if posicao >= 7 and obra_mes:
            limite = round(perfil["limite_financiamento"] * self.escala["orcamento_obra"])
            liberacao = min(round(0.38 * obra_mes), limite - self.financiamento_liberado)
            razao.lancar(mes, BANCO, EMPRESTIMO, liberacao)
            self.financiamento_liberado += liberacao
        if posicao >= self.indice_chaves:
            razao.lancar(mes, EMPRESTIMO, BANCO, min(razao.credor(EMPRESTIMO), round(0.6 * self.recebimento_mes)))
        alvo = round(FRACAO_VINCULADA * razao.credor(EMPRESTIMO))
        razao.lancar(mes, BANCO_VINCULADO, BANCO, alvo - razao.saldo[BANCO_VINCULADO])
        razao.lancar(mes, DESPESAS_FINANCEIRAS, BANCO, reais(280) + round(0.0004 * max(razao.credor(EMPRESTIMO), 0)))
        rendimento = round(TAXA_APLICACAO * self.abertura[APLICACAO])
        imposto = round(IR_APLICACAO * rendimento)
        razao.lancar(mes, APLICACAO, RECEITAS_FINANCEIRAS, rendimento - imposto)
        razao.lancar(mes, IMPOSTOS_RECUPERAR, RECEITAS_FINANCEIRAS, imposto)
        valor_mutuo = perfil["mutuo"].get(mes, 0) * 100
        razao.lancar(mes, BANCO, MUTUO, valor_mutuo)

    def lancar_pagamentos(self, posicao, mes):
        razao = self.razao
        for conta in (FORNECEDORES, COMISSOES_PAGAR, PESSOAL_PAGAR, IMPOSTOS_PAGAR, IRPJ_PAGAR, TAC_PAGAR):
            razao.lancar(mes, conta, BANCO, self.abertura[conta])
        for conta, parcelas in self.parcelas_terreno.items():
            razao.lancar(mes, conta, BANCO, parcelas.get(posicao, 0))
        if posicao > self.indice_chaves:
            razao.lancar(mes, PROVISAO_GARANTIA, BANCO, min(reais(14_000), razao.credor(PROVISAO_GARANTIA)))

    def lancar_eventos(self, posicao, mes):
        razao, perfil = self.razao, self.perfil
        razao.lancar(mes, ADIANTAMENTO_CONCILIAR, BANCO, perfil.get("conciliar", {}).get(mes, 0) * 100)
        razao.lancar(mes, FORNECEDORES, AJUSTE_ANTERIOR, perfil.get("ajuste_anterior", {}).get(mes, 0) * 100)
        razao.lancar(mes, SENTENCAS, BANCO, perfil.get("sentenca", {}).get(mes, 0) * 100)

    def lancar_tesouraria(self, mes):
        razao, piso = self.razao, reais(self.perfil["piso_caixa"])
        saldo = razao.saldo[BANCO]
        if saldo < piso:
            falta = piso - saldo
            resgate = min(razao.saldo[APLICACAO], falta)
            razao.lancar(mes, BANCO, APLICACAO, resgate)
            falta -= resgate
            if falta > 0:
                razao.lancar(mes, BANCO, self.perfil["conta_aporte"], -(-falta // PASSO_APORTE) * PASSO_APORTE)
        elif saldo > 3 * piso:
            razao.lancar(mes, APLICACAO, BANCO, saldo - 2 * piso)

    def lucro_do_mes(self):
        return -sum(saldo for conta, saldo in self.razao.saldo.items() if conta[0] in GRUPOS_RESULTADO)

    def fechar_mes(self, posicao, mes):
        razao, perfil = self.razao, self.perfil
        self.lucro_ano = (self.lucro_ano if mes.month != 1 else 0) + self.lucro_do_mes()
        if mes in perfil["dividendos"]:
            fracao, contas = perfil["dividendos"][mes]
            declarado = round(fracao * self.lucro_ano) if self.lucro_ano > 0 else 0
            pesos = (60, 40) if len(contas) == 2 else (1,)
            for conta, parte in zip(contas, distribuir(declarado, pesos)):
                razao.lancar(mes, LUCROS, conta, parte)
        if mes in perfil["reserva_legal"] and self.lucro_ano > 0:
            razao.lancar(mes, LUCROS, RESERVA, round(0.05 * self.lucro_ano))
        for conta in sorted(c for c, saldo in razao.saldo.items() if c[0] in GRUPOS_RESULTADO and saldo):
            razao.lancar(mes, APURACAO, conta, razao.saldo[conta], zeramento=True)
        razao.lancar(mes, LUCROS, APURACAO, razao.saldo[APURACAO], zeramento=True)


def plano_da_empresa(razao):
    usadas = {conta for _, conta in razao.movimento} | {SALDO_ABERTURA}
    return [linha for linha in CONTAS if linha[0] in usadas]


def valor_com_tipo(saldo, natureza):
    tipo = ("D" if saldo > 0 else "C") if saldo else natureza
    return {"value": abs(saldo) / 100, "type": tipo}


# O(contas x meses x níveis do código) por empresa; o resultado inteiro cabe em memória.
def balancete_da_empresa(id_empresa, razao, plano, meses, codigos_reduzidos):
    analiticas = {conta: (nome, natureza) for conta, nome, natureza, _ in plano}
    sinteticas = sorted({p for conta in analiticas for p in prefixos(conta)})
    saldo_com = defaultdict(int)
    saldo_sem = defaultdict(int)
    registros = []
    for mes in meses:
        numeros = {False: {}, True: {}}
        for conta in analiticas:
            deb, cred, deb_zeramento, cred_zeramento = razao.movimento.get((mes, conta), (0, 0, 0, 0))
            for sem_zeramento, debito, credito, saldos in (
                    (False, deb + deb_zeramento, cred + cred_zeramento, saldo_com), (True, deb, cred, saldo_sem)):
                anterior = saldos[conta]
                saldos[conta] = anterior + debito - credito
                numeros[sem_zeramento][conta] = (debito, credito, anterior, saldos[conta])
        for sem_zeramento in (False, True):
            por_conta = numeros[sem_zeramento]
            totais = {prefixo: [0, 0, 0, 0] for prefixo in sinteticas}
            for conta in analiticas:
                for prefixo in prefixos(conta):
                    for coluna, valor in enumerate(por_conta[conta]):
                        totais[prefixo][coluna] += valor
            por_conta.update({prefixo: tuple(soma) for prefixo, soma in totais.items()})
        if mes < PRIMEIRO_MES_SAIDA:
            continue
        for sem_zeramento in (False, True):
            for conta in sorted(numeros[sem_zeramento]):
                debito, credito, anterior, atual = numeros[sem_zeramento][conta]
                eh_analitica = conta in analiticas
                nome, natureza = analiticas[conta] if eh_analitica else (
                    NOMES_SINTETICAS[conta], NATUREZA_SINTETICA[conta[0]])
                registros.append({
                    "companyId": id_empresa, "reducedCode": codigos_reduzidos[conta],
                    "accountGroup": GRUPOS_ERP[conta[0]], "account": conta, "accountName": nome,
                    "accountType": "ANALYTICAL" if eh_analitica else "SYNTHETIC",
                    "debit": debito / 100, "credit": credito / 100,
                    "operatingBalance": valor_com_tipo(debito - credito, natureza),
                    "balances": {"previous": valor_com_tipo(anterior, natureza),
                                 "current": valor_com_tipo(atual, natureza)},
                    "initialPeriod": mes.isoformat(), "desconsiderClosingBalance": sem_zeramento,
                })
    return registros


def mapa_de_contas():
    itens = [{"conta": prefixo, "linha": linha} for prefixo, linha in sorted(PREFIXOS_MAPEADOS.items())]
    itens += [{"conta": conta, "linha": linha} for conta, _, _, linha in CONTAS if linha]
    return sorted(itens, key=lambda item: item["conta"])


def escrever(nome, conteudo, compacto=False):
    PASTA_SAIDA.mkdir(parents=True, exist_ok=True)
    caminho = PASTA_SAIDA / nome
    if compacto:
        texto = json.dumps(conteudo, ensure_ascii=False, separators=(",", ":"))
    else:
        texto = json.dumps(conteudo, ensure_ascii=False, indent=1)
    caminho.write_text(texto + "\n", encoding="utf-8")
    print(f"{nome}: {caminho.stat().st_size / 1024:.0f} KB")


def main():
    cadastro = ler_json(PASTA_DADOS / "companies.json")["data"]
    obra_da_empresa = {c["idCompany"]: c["id"] for c in ler_json(PASTA_DADOS / "cost-centers.json")["data"]}
    linhas_diretas = {conta: linha for conta, _, _, linha in CONTAS}
    codigos_reduzidos = {}
    for posicao, conta in enumerate(sorted({c for c, *_ in CONTAS} | set(NOMES_SINTETICAS))):
        codigos_reduzidos[conta] = 1001 + posicao
    registros = []
    for id_empresa, perfil in PERFIS.items():
        assert obra_da_empresa[id_empresa] == perfil["obra"], id_empresa
        simulador = Simulador(id_empresa, perfil, escala_da_obra(perfil["obra"]))
        razao = simulador.executar()
        plano = plano_da_empresa(razao)
        for conta, *_ in plano:
            assert all(p in NOMES_SINTETICAS for p in prefixos(conta)), conta
            # A única conta analítica sem linha é a do Parque, deixada assim para a conferência ter o que mostrar.
            assert resolver_linha(conta, linhas_diretas, PREFIXOS_MAPEADOS) or conta == ADIANTAMENTO_CONCILIAR, conta
        registros += balancete_da_empresa(id_empresa, razao, plano, simulador.meses, codigos_reduzidos)
        print(f"empresa {id_empresa}: {len(plano)} contas analíticas")
    escrever("companies.json", {"data": cadastro})
    escrever("trial-balance.json", {"results": registros}, compacto=True)
    escrever("mapa-contas.json", mapa_de_contas())


if __name__ == "__main__":
    main()
