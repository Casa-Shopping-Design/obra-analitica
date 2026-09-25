import { describe, expect, it } from "vitest";
import {
  lerNomeUnidade,
  montarGrade,
  normalizarSituacao,
  rotuloAndar,
  type SituacaoUnidade,
  type UnidadeMapa,
} from "../lib/grade-unidades";

let proximoId = 1;
function unidade(nome: string, situacao: SituacaoUnidade = "disponivel"): UnidadeMapa {
  return {
    unidade_id: proximoId++,
    unidade: nome,
    tipologia: null,
    area_privativa: 58,
    situacao,
    valor: 290000,
    origem_valor: "tabela",
    valor_m2: 5000,
    tabela: null,
    indice: null,
    indice_referencia: null,
    indice_valor: null,
  };
}

describe("lerNomeUnidade", () => {
  it("separa tipologia, andar e posição do padrão TIPO-AAPP", () => {
    expect(lerNomeUnidade("3Q-0202")).toEqual({ tipologia: "3Q", andar: 2, posicao: 2 });
    expect(lerNomeUnidade("SALA-1004")).toEqual({ tipologia: "SALA", andar: 10, posicao: 4 });
  });

  it("aceita tipologia com hífen, usando só os quatro últimos dígitos", () => {
    expect(lerNomeUnidade("BLOCO-A-0301")).toEqual({ tipologia: "BLOCO-A", andar: 3, posicao: 1 });
  });

  it("devolve nulo para nome fora do padrão", () => {
    expect(lerNomeUnidade("Loja 1")).toBeNull();
    expect(lerNomeUnidade("2Q-101")).toBeNull();
    expect(lerNomeUnidade("-0101")).toBeNull();
  });
});

describe("normalizarSituacao", () => {
  it("mantém as situações conhecidas e manda o resto para fora de venda", () => {
    expect(normalizarSituacao("vendida")).toBe("vendida");
    expect(normalizarSituacao("R")).toBe("indisponivel");
    expect(normalizarSituacao(null)).toBe("indisponivel");
  });
});

describe("rotuloAndar", () => {
  it("chama o andar zero de térreo", () => {
    expect(rotuloAndar(0)).toBe("Térreo");
    expect(rotuloAndar(12)).toBe("12º andar");
  });
});

describe("montarGrade", () => {
  it("agrupa por tipologia, põe o andar mais alto em cima e ordena as posições", () => {
    const grade = montarGrade([
      unidade("3Q-0102"),
      unidade("2Q-0101"),
      unidade("2Q-0202", "vendida"),
      unidade("2Q-0102", "reservada"),
      unidade("2Q-0201", "proposta"),
    ]);

    expect(grade.blocos.map((bloco) => bloco.tipologia)).toEqual(["2Q", "3Q"]);
    const [blocoDoisQuartos] = grade.blocos;
    expect(blocoDoisQuartos.posicoes).toEqual([1, 2]);
    expect(blocoDoisQuartos.andares.map((linha) => linha.andar)).toEqual([2, 1]);
    expect(blocoDoisQuartos.andares[0].celulas.map((celula) => celula?.unidade)).toEqual(["2Q-0201", "2Q-0202"]);
    expect(blocoDoisQuartos.andares[1].celulas.map((celula) => celula?.unidade)).toEqual(["2Q-0101", "2Q-0102"]);
  });

  it("deixa célula vazia onde falta unidade, sem deslocar as outras", () => {
    const grade = montarGrade([unidade("2Q-0101"), unidade("2Q-0104"), unidade("2Q-0202")]);
    const [bloco] = grade.blocos;
    expect(bloco.posicoes).toEqual([1, 2, 4]);
    expect(bloco.andares[0].celulas.map((celula) => celula?.unidade ?? null)).toEqual([null, "2Q-0202", null]);
    expect(bloco.andares[1].celulas.map((celula) => celula?.unidade ?? null)).toEqual(["2Q-0101", null, "2Q-0104"]);
  });

  it("separa nome fora do padrão e nome repetido, sem perder unidade", () => {
    const grade = montarGrade([unidade("2Q-0101"), unidade("2Q-0101", "vendida"), unidade("Loja 1")]);
    expect(grade.foraDoPadrao.map((celula) => celula.unidade)).toEqual(["2Q-0101", "Loja 1"]);
    expect(grade.blocos[0].andares[0].celulas).toHaveLength(1);
  });

  it("conta todas as unidades por situação, inclusive as fora da grade", () => {
    const grade = montarGrade([
      unidade("2Q-0101"),
      unidade("2Q-0102", "vendida"),
      unidade("2Q-0103", "vendida"),
      unidade("Loja 1", "indisponivel"),
    ]);
    expect(grade.totais).toEqual({ disponivel: 1, reservada: 0, proposta: 0, vendida: 2, indisponivel: 1 });
  });

  it("devolve grade vazia para obra sem unidades", () => {
    const grade = montarGrade([]);
    expect(grade.blocos).toEqual([]);
    expect(grade.foraDoPadrao).toEqual([]);
  });
});
