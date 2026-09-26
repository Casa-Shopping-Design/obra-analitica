import { describe, expect, it } from "vitest";
import {
  validarAtualizacaoLiberacao,
  validarEtapa,
  validarLiberacao,
  validarMedicao,
  validarOperacao,
} from "../componentes/planejamento/regras-financiamento";
import {
  compararMetas,
  juntarPorMes,
  leitorDeObjeto,
  limitesDaJanela,
  milionesimosDePercentual,
  validarDescricaoVersao,
  validarMetas,
  validarPremissaDistribuicao,
} from "../componentes/planejamento/regras-planejamento";
import { montarSerieProjetada } from "../componentes/planejamento/serie-projetada";

const referencia = "2026-09-26";
const operacao = "11111111-2222-4333-8444-555555555555";
const medicao = "66666666-7777-4888-9999-000000000000";
const liberacao = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee";

describe("versões de metas", () => {
  it("lê as linhas preenchidas, ignora as vazias e ordena por mês", () => {
    const resultado = validarMetas(
      leitorDeObjeto({
        descricao: "Revisão depois do lançamento",
        mes_0: "2026-11",
        unidades_0: "3",
        valor_0: "900.000,00",
        fracao_0: "60",
        mes_2: "2026-10",
        unidades_2: "2",
        limite_2: "500000",
      }),
      referencia,
    );
    expect(resultado).toEqual({
      ok: true,
      descricao: "Revisão depois do lançamento",
      metas: [
        {
          competencia: "2026-10-01",
          unidades: 2,
          valor_contratado: null,
          fracao_financiada: null,
          recebimento_esperado: null,
          limite_aporte_proprio: 500000,
        },
        {
          competencia: "2026-11-01",
          unidades: 3,
          valor_contratado: 900000,
          fracao_financiada: 0.6,
          recebimento_esperado: null,
          limite_aporte_proprio: null,
        },
      ],
    });
  });

  it("recusa mês repetido, valor inválido, linha sem valor e versão sem descrição", () => {
    const resultado = validarMetas(
      leitorDeObjeto({
        mes_0: "2026-10",
        unidades_0: "2",
        mes_1: "2026-10",
        unidades_1: "3",
        mes_2: "2026-12",
        valor_2: "abc",
        fracao_2: "120",
        mes_3: "2026-11",
      }),
      referencia,
    );
    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(Object.keys(resultado.erros).sort()).toEqual(["descricao", "fracao_2", "mes_1", "unidades_3", "valor_2"]);
  });

  it("exige pelo menos um mês e recusa mês fora da faixa", () => {
    const vazio = validarMetas(leitorDeObjeto({ descricao: "x" }), referencia);
    expect(vazio.ok || vazio.erros.mes_0).toBeTruthy();
    const longe = validarMetas(leitorDeObjeto({ descricao: "x", mes_0: "2040-01", unidades_0: "1" }), referencia);
    expect(longe.ok).toBe(false);
  });

  it("descrição da versão da projeção é obrigatória e curta", () => {
    expect(validarDescricaoVersao(leitorDeObjeto({ descricao: "Fechamento de setembro" })).ok).toBe(true);
    expect(validarDescricaoVersao(leitorDeObjeto({ descricao: "" })).ok).toBe(false);
    expect(validarDescricaoVersao(leitorDeObjeto({ descricao: "a".repeat(201) })).ok).toBe(false);
  });
});

describe("premissa de distribuição do custo sem título", () => {
  it("aceita percentuais que somam exatamente 100%", () => {
    const resultado = validarPremissaDistribuicao(
      leitorDeObjeto({
        fonte: "Cronograma físico-financeiro de setembro",
        mes_0: "2026-10",
        percentual_0: "33,3333",
        mes_1: "2026-11",
        percentual_1: "33,3333",
        mes_2: "2026-12",
        percentual_2: "33,3334",
      }),
      referencia,
    );
    expect(resultado.ok && resultado.meses).toEqual([
      { competencia: "2026-10-01", fracao: 0.333333 },
      { competencia: "2026-11-01", fracao: 0.333333 },
      { competencia: "2026-12-01", fracao: 0.333334 },
    ]);
  });

  it("recusa soma diferente de 100% sem arredondar", () => {
    const resultado = validarPremissaDistribuicao(
      leitorDeObjeto({ fonte: "Planilha", mes_0: "2026-10", percentual_0: "33,3333", mes_1: "2026-11", percentual_1: "66,6666" }),
      referencia,
    );
    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.erros.soma).toMatch(/99,9999%/);
  });

  it("exige fonte e recusa percentual zero ou com mais de quatro casas", () => {
    const resultado = validarPremissaDistribuicao(
      leitorDeObjeto({ mes_0: "2026-10", percentual_0: "0", mes_1: "2026-11", percentual_1: "10,12345" }),
      referencia,
    );
    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(Object.keys(resultado.erros).sort()).toEqual(["fonte", "percentual_0", "percentual_1"]);
  });

  it("percentual vira milionésimos inteiros", () => {
    expect(milionesimosDePercentual("12,5")).toBe(125000);
    expect(milionesimosDePercentual("100")).toBe(1_000_000);
    expect(milionesimosDePercentual("100,01")).toBeNull();
  });
});

describe("comparação de versões", () => {
  it("junta duas séries pelo mês sem somar", () => {
    const linhas = juntarPorMes(
      [
        { competencia: "2026-11-01", valor: 2 },
        { competencia: "2026-10-01", valor: 1 },
      ],
      [{ competencia: "2026-12-01", outro: 3 }],
    );
    expect(linhas.map((linha) => [linha.competencia, linha.a?.valor ?? null, linha.b?.outro ?? null])).toEqual([
      ["2026-10-01", 1, null],
      ["2026-11-01", 2, null],
      ["2026-12-01", null, 3],
    ]);
  });

  it("separa as metas da versão vigente e da comparada", () => {
    const metas = [
      { versao_id: "v2", competencia: "2026-10-01", unidades: 3 },
      { versao_id: "v1", competencia: "2026-10-01", unidades: 5 },
      { versao_id: "v1", competencia: "2026-11-01", unidades: 4 },
    ];
    const linhas = compararMetas(metas, "v2", "v1");
    expect(linhas).toEqual([
      { competencia: "2026-10-01", a: metas[0], b: metas[1] },
      { competencia: "2026-11-01", a: null, b: metas[2] },
    ]);
    expect(compararMetas(metas, "v2", null)).toEqual([{ competencia: "2026-10-01", a: metas[0], b: null }]);
  });

  it("janela de meses parte do mês de referência", () => {
    expect(limitesDaJanela("curta", referencia)).toEqual({ inicio: "2026-03-01", fim: "2027-09-01" });
    expect(limitesDaJanela("tudo", referencia)).toEqual({ inicio: null, fim: null });
  });

  it("série do gráfico só escolhe a coluna pelo mês passado ou futuro", () => {
    const [passado, atual] = montarSerieProjetada([
      { competencia: "2026-08-01", eh_passado: true, total_entradas: 10, total_saidas: 20, caixa_gerado_acumulado: -10, caixa_gerado_acumulado_conservador: -10 },
      { competencia: "2026-09-01", eh_passado: false, total_entradas: 30, total_saidas: 5, caixa_gerado_acumulado: 15, caixa_gerado_acumulado_conservador: 12 },
    ]);
    expect(passado).toMatchObject({ entradasRealizadas: 10, entradasPrevistas: null, saidasRealizadas: 20, caixa: -10 });
    expect(atual).toMatchObject({ entradasRealizadas: null, entradasPrevistas: 30, saidasPrevistas: 5, caixaConservador: 12 });
  });
});

describe("complemento manual de financiamento", () => {
  it("operação: valida modalidade, valor e retenção como fração", () => {
    const resultado = validarOperacao(
      leitorDeObjeto({ modalidade: "credito_producao", instituicao: "Banco da obra", valor_contratado: "5.000.000,00", percentual_retencao: "5", fonte: "Contrato com o banco" }),
    );
    expect(resultado.ok && resultado.dados).toMatchObject({ valor_contratado: 5_000_000, percentual_retencao: 0.05, numero_contrato: null });
    const errado = validarOperacao(leitorDeObjeto({ modalidade: "consorcio", valor_contratado: "0" }));
    expect(errado.ok).toBe(false);
    if (errado.ok) return;
    expect(Object.keys(errado.erros).sort()).toEqual(["fonte", "instituicao", "modalidade", "valor_contratado"]);
  });

  it("etapa: contrato precisa ser da obra e pendência exige motivo", () => {
    const contratos = new Set([5001]);
    expect(validarEtapa(leitorDeObjeto({ contrato_id_origem: "5001", etapa: "elegivel", data_etapa: "2026-09-10", fonte: "Banco" }), contratos).ok).toBe(true);
    const fora = validarEtapa(leitorDeObjeto({ contrato_id_origem: "9999", etapa: "elegivel", data_etapa: "2026-09-10", fonte: "Banco" }), contratos);
    expect(fora.ok || fora.erros.contrato_id_origem).toBeTruthy();
    const pendente = validarEtapa(
      leitorDeObjeto({ contrato_id_origem: "5001", etapa: "aprovacao", pendencia: "sim", data_etapa: "2026-09-10", fonte: "Banco" }),
      contratos,
    );
    expect(pendente.ok).toBe(false);
    if (pendente.ok) return;
    expect(pendente.erros.motivo_pendencia).toBeDefined();
  });

  it("medição: aprovada exige data de aprovação e avanço vira fração", () => {
    const operacoes = new Set([operacao]);
    const base = { operacao_credito_id: operacao, numero: "3", data_vistoria: "2026-09-05", avanco_fisico_informado: "42,5", fonte: "RAE 123" };
    const semData = validarMedicao(leitorDeObjeto({ ...base, situacao: "aprovada" }), operacoes);
    expect(semData.ok || semData.erros.data_aprovacao).toBeTruthy();
    const certa = validarMedicao(leitorDeObjeto({ ...base, situacao: "aprovada", data_aprovacao: "2026-09-12", valor_elegivel: "120000" }), operacoes);
    expect(certa.ok && certa.dados).toMatchObject({ avanco_fisico_informado: 0.425, valor_elegivel: 120000, valor_medido: null });
  });

  it("liberação: nível decide o que é obrigatório e não rateia por unidade", () => {
    const permitidos = { operacoes: new Set([operacao]), contratos: new Set([5001]), medicoes: new Set([medicao]) };
    const obra = validarLiberacao(
      leitorDeObjeto({ nivel: "empreendimento", operacao_credito_id: operacao, valor_previsto: "250000", data_prevista: "2026-11-15", situacao: "prevista", fonte: "Cronograma do banco" }),
      permitidos,
    );
    expect(obra.ok && obra.dados).toMatchObject({ contrato_id_origem: null, descricao_lote: null, operacao_credito_id: operacao });
    const obraComContrato = validarLiberacao(
      leitorDeObjeto({ nivel: "empreendimento", operacao_credito_id: operacao, contrato_id_origem: "5001", valor_previsto: "1", data_prevista: "2026-11-15", situacao: "prevista", fonte: "x" }),
      permitidos,
    );
    expect(obraComContrato.ok).toBe(false);
    const lote = validarLiberacao(
      leitorDeObjeto({ nivel: "lote", operacao_credito_id: operacao, valor_previsto: "1", data_prevista: "2026-11-15", situacao: "pendente", fonte: "x" }),
      permitidos,
    );
    expect(lote.ok).toBe(false);
    if (lote.ok) return;
    expect(Object.keys(lote.erros).sort()).toEqual(["descricao_lote", "motivo"]);
  });

  it("recebimento exige valor, data até a referência e vínculo no formato certo", () => {
    const liberacoes = new Set([liberacao]);
    const base = { id: liberacao, situacao: "recebida", fonte: "Extrato de setembro" };
    const errado = validarAtualizacaoLiberacao(
      leitorDeObjeto({ ...base, valor_recebido: "100", data_recebimento: "2026-10-01", vinculo_tipo: "recebimento", vinculo_chave: "5001-12-1" }),
      liberacoes,
      referencia,
    );
    expect(errado.ok).toBe(false);
    if (errado.ok) return;
    expect(Object.keys(errado.erros).sort()).toEqual(["data_recebimento", "vinculo_chave"]);
    const certo = validarAtualizacaoLiberacao(
      leitorDeObjeto({ ...base, valor_recebido: "100.000,00", data_recebimento: "2026-09-20", vinculo_tipo: "lancamento_manual", vinculo_chave: "EXT-0915-01" }),
      liberacoes,
      referencia,
    );
    expect(certo.ok && certo.dados).toMatchObject({ valor_recebido: 100000, vinculo_tipo: "lancamento_manual", motivo: null });
    const cancelada = validarAtualizacaoLiberacao(leitorDeObjeto({ id: liberacao, situacao: "cancelada", fonte: "x" }), liberacoes, referencia);
    expect(cancelada.ok || cancelada.erros.motivo).toBeTruthy();
  });
});
