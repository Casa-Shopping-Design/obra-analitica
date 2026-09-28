import { describe, expect, it } from "vitest";
import {
  classificarDiferenca,
  execucaoMaisRecente,
  financeiroAdiantado,
  numeroOuNulo,
  perfilVeConferencia,
  rotuloFaixa,
  totalizarFunil,
  totalizarInadimplencia,
  type LinhaExecucao,
  type LinhaFunil,
} from "../lib/consultas/resumo-origem";

function mesFunil(competencia: string, leads: number, reservas: number, vendas: number): LinhaFunil {
  return {
    competencia,
    leads,
    reservas,
    reservas_canceladas: 0,
    vendas,
    distratos: 0,
    conversao_lead_reserva: leads > 0 ? reservas / leads : null,
    conversao_reserva_venda: reservas > 0 ? vendas / reservas : null,
  };
}

describe("perfilVeConferencia", () => {
  it("libera só diretor e financeiro", () => {
    expect(perfilVeConferencia("diretor")).toBe(true);
    expect(perfilVeConferencia("financeiro")).toBe(true);
    expect(perfilVeConferencia("gerente_obra")).toBe(false);
    expect(perfilVeConferencia("comercial")).toBe(false);
    expect(perfilVeConferencia("leitura")).toBe(false);
  });

  it("nega perfil ausente ou com caixa diferente", () => {
    expect(perfilVeConferencia(null)).toBe(false);
    expect(perfilVeConferencia(undefined)).toBe(false);
    expect(perfilVeConferencia("Diretor")).toBe(false);
  });
});

describe("numeroOuNulo", () => {
  it("lê numeric que o PostgREST devolve como texto", () => {
    expect(numeroOuNulo("27.1")).toBe(27.1);
    expect(numeroOuNulo(0)).toBe(0);
  });

  it("mantém nulo e descarta texto que não é número", () => {
    expect(numeroOuNulo(null)).toBeNull();
    expect(numeroOuNulo("")).toBeNull();
    expect(numeroOuNulo("abc")).toBeNull();
  });
});

describe("totalizarFunil", () => {
  it("soma as contagens antes de dividir, sem média das conversões mensais", () => {
    // Janeiro converte 50% (1 de 2) e fevereiro 10% (10 de 100); a média daria 30%, o período dá 11/102.
    const total = totalizarFunil([mesFunil("2026-01-01", 2, 1, 1), mesFunil("2026-02-01", 100, 10, 4)]);
    expect(total.leads).toBe(102);
    expect(total.reservas).toBe(11);
    expect(total.vendas).toBe(5);
    expect(total.conversaoLeadReserva).toBeCloseTo(11 / 102, 10);
    expect(total.conversaoReservaVenda).toBeCloseTo(5 / 11, 10);
  });

  it("deixa a conversão nula quando não houve lead nem reserva", () => {
    const total = totalizarFunil([mesFunil("2026-03-01", 0, 0, 2)]);
    expect(total.conversaoLeadReserva).toBeNull();
    expect(total.conversaoReservaVenda).toBeNull();
    expect(total.vendas).toBe(2);
  });
});

describe("classificarDiferenca", () => {
  it("separa confere, atenção e diverge pelos limites de 1% e 5%", () => {
    expect(classificarDiferenca(0)).toBe("confere");
    expect(classificarDiferenca(-0.01)).toBe("confere");
    expect(classificarDiferenca(0.0101)).toBe("atencao");
    // Caso do pgTAP da 0019: custo incorrido 190.000 contra 200.000 do ERP.
    expect(classificarDiferenca(-0.05)).toBe("atencao");
    expect(classificarDiferenca(0.0501)).toBe("diverge");
  });

  it("marca sem base quando o ERP mostra zero", () => {
    expect(classificarDiferenca(null)).toBe("sem_base");
  });
});

describe("execução física", () => {
  const linha = (competencia: string, pctFisico: number | null, diferenca: number | null): LinhaExecucao => ({
    competencia,
    pct_fisico: pctFisico,
    pct_financeiro: null,
    pct_financeiro_origem: null,
    diferenca_financeiro_fisico: diferenca,
  });

  it("pega o último mês com físico medido", () => {
    const linhas = [linha("2026-07-01", 0.25, 0.05), linha("2026-08-01", 0.5, -0.2), linha("2026-09-01", null, null)];
    expect(execucaoMaisRecente(linhas)?.competencia).toBe("2026-08-01");
    expect(execucaoMaisRecente([])).toBeNull();
  });

  it("avisa só quando o pago passa o físico em mais de 10 pontos", () => {
    expect(financeiroAdiantado(0.1)).toBe(false);
    expect(financeiroAdiantado(0.1001)).toBe(true);
    expect(financeiroAdiantado(-0.3)).toBe(false);
    expect(financeiroAdiantado(null)).toBe(false);
  });
});

describe("inadimplência", () => {
  it("soma as quatro faixas e dá rótulo legível", () => {
    const faixas = [
      { data_posicao: "2026-09-27", ordem: 1, faixa: "1-30", titulos: 1, parcelas: 1, valor_atrasado: 1000, valor_atualizado: 1010 },
      { data_posicao: "2026-09-27", ordem: 2, faixa: "31-90", titulos: 0, parcelas: 0, valor_atrasado: 0, valor_atualizado: 0 },
      { data_posicao: "2026-09-27", ordem: 3, faixa: "91-180", titulos: 1, parcelas: 2, valor_atrasado: 5000, valor_atualizado: 5300 },
      { data_posicao: "2026-09-27", ordem: 4, faixa: ">180", titulos: 1, parcelas: 7, valor_atrasado: 1234.56, valor_atualizado: 1500 },
    ];
    const total = totalizarInadimplencia(faixas);
    expect(total).toMatchObject({ titulos: 3, parcelas: 10, valorAtualizado: 7810 });
    expect(total.valorAtrasado).toBeCloseTo(7234.56, 2);
    expect(rotuloFaixa(">180")).toBe("Mais de 180 dias");
    expect(rotuloFaixa("31-90")).toBe("31 a 90 dias");
  });
});
