import { describe, expect, it } from "vitest";
import {
  formularioPadrao,
  juntarBaseESimulacao,
  lerDecimal,
  lerFormularioSimulacao,
  piorMes,
  validarPremissas,
  type FormularioSimulacao,
} from "../lib/simulacao";

const referencia = "2026-09-26";
const contexto = { dataReferencia: referencia, estoque: 40 };

function formulario(mudancas: Partial<FormularioSimulacao> = {}): FormularioSimulacao {
  return { ...formularioPadrao(referencia), ...mudancas };
}

describe("lerDecimal", () => {
  it("aceita vírgula e ponto como no Brasil", () => {
    expect(lerDecimal("1.234,56")).toBe(1234.56);
    expect(lerDecimal("12,5")).toBe(12.5);
    expect(lerDecimal("1234.56")).toBe(1234.56);
    expect(lerDecimal("R$ 30.000,00")).toBe(30000);
  });

  it("recusa texto, negativo e vazio", () => {
    expect(lerDecimal("")).toBeNull();
    expect(lerDecimal("-5")).toBeNull();
    expect(lerDecimal("5e3")).toBeNull();
    expect(lerDecimal("dez")).toBeNull();
    expect(lerDecimal("1,2,3")).toBeNull();
  });
});

describe("lerFormularioSimulacao", () => {
  it("usa o padrão para campo ausente e guarda o que veio", () => {
    const lido = lerFormularioSimulacao({ vendas_por_mes: "3", desconto: ["7", "9"] }, referencia);
    expect(lido.vendas_por_mes).toBe("3");
    expect(lido.desconto).toBe("7");
    expect(lido.mes_inicio_vendas).toBe("2026-10");
  });

  it("corta texto longo", () => {
    expect(lerFormularioSimulacao({ custo_campanha: "9".repeat(500) }, referencia).custo_campanha).toHaveLength(40);
  });
});

describe("validarPremissas", () => {
  it("monta as premissas do contrato a partir do padrão", () => {
    const resultado = validarPremissas(formulario(), contexto);
    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.premissas).toEqual({
      novas_vendas: [
        { competencia: "2026-10-01", quantidade: 2 },
        { competencia: "2026-11-01", quantidade: 2 },
        { competencia: "2026-12-01", quantidade: 2 },
        { competencia: "2027-01-01", quantidade: 2 },
        { competencia: "2027-02-01", quantidade: 2 },
        { competencia: "2027-03-01", quantidade: 2 },
      ],
      desconto_tabela: 0,
      composicao: { entrada: 0.1, parcelas_mensais: 0.3, quantidade_parcelas_mensais: 24, financiamento: 0.6 },
      meses_ate_liberacao_financiamento: 4,
      atraso_liberacao_bancaria_meses: 0,
      deslocamento_cronograma_meses: 0,
      fator_cronograma: 1,
      custo_campanha: [],
    });
    expect(resultado.resumo.map((item) => item.rotulo)).toContain("Composição");
  });

  it("converte percentuais em fração com seis casas", () => {
    const resultado = validarPremissas(
      formulario({ desconto: "2,5", entrada: "12,5", parcelas: "27,5", financiamento: "60", fator_gastos: "110" }),
      contexto,
    );
    expect(resultado.ok && resultado.premissas.desconto_tabela).toBe(0.025);
    expect(resultado.ok && resultado.premissas.composicao?.entrada).toBe(0.125);
    expect(resultado.ok && resultado.premissas.fator_cronograma).toBe(1.1);
  });

  it("exige composição somando exatamente 100%", () => {
    const resultado = validarPremissas(formulario({ entrada: "10", parcelas: "30", financiamento: "59,99" }), contexto);
    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.erros.financiamento).toMatch(/somam 99,99%/);
  });

  it("não aceita mais vendas que o estoque", () => {
    const resultado = validarPremissas(formulario({ vendas_por_mes: "10", meses_vendas: "5" }), { ...contexto, estoque: 40 });
    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.erros.vendas_por_mes).toMatch(/50 vendas.*40 unidades/);
  });

  it("aceita exatamente o estoque e deixa o banco limitar quando a contagem falhou", () => {
    expect(validarPremissas(formulario({ vendas_por_mes: "8", meses_vendas: "5" }), contexto).ok).toBe(true);
    expect(validarPremissas(formulario({ vendas_por_mes: "100", meses_vendas: "2" }), { ...contexto, estoque: null }).ok).toBe(true);
  });

  it("obra sem estoque só simula com zero vendas", () => {
    expect(validarPremissas(formulario(), { ...contexto, estoque: 0 }).ok).toBe(false);
    const semVendas = validarPremissas(formulario({ vendas_por_mes: "0", entrada: "", parcelas: "", financiamento: "" }), {
      ...contexto,
      estoque: 0,
    });
    expect(semVendas.ok).toBe(false);
    const zero = validarPremissas(formulario({ vendas_por_mes: "0" }), { ...contexto, estoque: 0 });
    expect(zero.ok).toBe(true);
    if (!zero.ok) return;
    expect(zero.premissas.novas_vendas).toEqual([]);
    expect(zero.premissas.composicao).toBeUndefined();
    expect(zero.premissas.meses_ate_liberacao_financiamento).toBeUndefined();
  });

  it("recusa tipo errado e limites", () => {
    const resultado = validarPremissas(
      formulario({
        vendas_por_mes: "2,5",
        meses_vendas: "0",
        desconto: "100",
        quantidade_parcelas: "0",
        meses_liberacao: "61",
        atraso_liberacao: "-1",
        deslocamento_gastos: "25",
        fator_gastos: "0",
      }),
      contexto,
    );
    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(Object.keys(resultado.erros).sort()).toEqual(
      ["atraso_liberacao", "desconto", "deslocamento_gastos", "fator_gastos", "meses_vendas", "vendas_por_mes"].sort(),
    );
  });

  it("confere parcelas e liberação só quando há venda com essa parte", () => {
    const resultado = validarPremissas(formulario({ quantidade_parcelas: "0", meses_liberacao: "99" }), contexto);
    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.erros.quantidade_parcelas).toBeDefined();
    expect(resultado.erros.meses_liberacao).toBeDefined();
    const aVista = validarPremissas(
      formulario({ entrada: "100", parcelas: "0", financiamento: "0", quantidade_parcelas: "", meses_liberacao: "" }),
      contexto,
    );
    expect(aVista.ok).toBe(true);
    expect(aVista.ok && aVista.premissas.composicao?.quantidade_parcelas_mensais).toBe(1);
    expect(aVista.ok && aVista.premissas.meses_ate_liberacao_financiamento).toBeUndefined();
  });

  it("recusa mês de venda antes da referência ou longe demais", () => {
    expect(validarPremissas(formulario({ mes_inicio_vendas: "2026-08" }), contexto).ok).toBe(false);
    expect(validarPremissas(formulario({ mes_inicio_vendas: "2031-10" }), contexto).ok).toBe(false);
    expect(validarPremissas(formulario({ mes_inicio_vendas: "2026-9" }), contexto).ok).toBe(false);
    expect(validarPremissas(formulario({ mes_inicio_vendas: "2026-09" }), contexto).ok).toBe(true);
  });

  it("campanha exige mês e valor positivo com centavos", () => {
    expect(validarPremissas(formulario({ mes_campanha: "2026-11" }), contexto).ok).toBe(false);
    expect(validarPremissas(formulario({ mes_campanha: "2026-11", custo_campanha: "0" }), contexto).ok).toBe(false);
    expect(validarPremissas(formulario({ mes_campanha: "2026-11", custo_campanha: "10,005" }), contexto).ok).toBe(false);
    const campanha = validarPremissas(formulario({ mes_campanha: "2026-11", custo_campanha: "30.000,00" }), contexto);
    expect(campanha.ok && campanha.premissas.custo_campanha).toEqual([{ competencia: "2026-11-01", valor: 30000 }]);
    expect(campanha.ok && campanha.resumo.find((item) => item.rotulo.startsWith("Campanha"))?.valor).toMatch(/novembro de 2026/);
  });

  it("dezembro vira janeiro na sequência de meses", () => {
    const resultado = validarPremissas(formulario({ mes_inicio_vendas: "2026-12", meses_vendas: "2" }), contexto);
    expect(resultado.ok && resultado.premissas.novas_vendas?.map((venda) => venda.competencia)).toEqual([
      "2026-12-01",
      "2027-01-01",
    ]);
  });
});

describe("piorMes e juntarBaseESimulacao", () => {
  it("escolhe o mês de maior aporte e devolve nulo sem aporte", () => {
    const linhas = [
      { competencia: "2026-10-01", necessidade_aporte_acumulada: 10 },
      { competencia: "2026-11-01", necessidade_aporte_acumulada: 30 },
      { competencia: "2026-12-01", necessidade_aporte_acumulada: 30 },
    ];
    expect(piorMes(linhas)?.competencia).toBe("2026-11-01");
    expect(piorMes([{ competencia: "2026-10-01", necessidade_aporte_acumulada: 0 }])).toBeNull();
  });

  it("junta por mês sem somar e mantém o mês que só existe na simulação", () => {
    const pontos = juntarBaseESimulacao(
      [{ competencia: "2026-10-01", caixa_gerado_acumulado: -100 }],
      [
        { competencia: "2026-11-01", caixa_gerado_acumulado: -50 },
        { competencia: "2026-10-01", caixa_gerado_acumulado: -80 },
      ],
    );
    expect(pontos).toEqual([
      { competencia: "2026-10-01", base: -100, simulado: -80 },
      { competencia: "2026-11-01", base: null, simulado: -50 },
    ]);
  });
});
