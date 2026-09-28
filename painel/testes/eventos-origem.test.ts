import { describe, expect, it } from "vitest";
import {
  canonicalizar,
  contarIds,
  extrairIdsCrm,
  extrairIdsErp,
  lerCorpoLimitado,
  lerJsonObjeto,
  idsAceitaveis,
  lerTokenBearer,
  respostaEvento,
  sha256Hex,
  statusDoRegistro,
  tipoEventoCrm,
} from "../lib/eventos-origem";

function requisicao(corpo: string | ReadableStream<Uint8Array>, cabecalhos: Record<string, string> = {}) {
  return new Request("http://localhost/api/origem/erp", {
    method: "POST",
    body: corpo,
    headers: cabecalhos,
    // Exigido pelo Node quando o corpo é stream.
    ...(typeof corpo === "string" ? {} : { duplex: "half" }),
  } as RequestInit);
}

describe("extrairIdsErp", () => {
  it("pega só as chaves de ID conhecidas e descarta o resto do corpo", () => {
    const corpo = { receivableBillId: 100, installmentId: 5, accountNumber: "1234-5", status: "CONFIRMED" };
    expect(extrairIdsErp(corpo)).toEqual({ receivableBillId: 100, installmentId: 5 });
  });

  it("aceita lista de inteiros", () => {
    expect(extrairIdsErp({ receivableBillId: [1, 2], situation: "x" })).toEqual({ receivableBillId: [1, 2] });
  });

  it("recusa texto, decimal, negativo, objeto e lista com item inválido", () => {
    const corpo = { unitId: "7", billId: 1.5, customerId: -1, costCenterId: { id: 1 }, buildingId: [1, "2"] };
    expect(extrairIdsErp(corpo)).toEqual({});
  });

  it("não lê chave herdada do protótipo", () => {
    const corpo = Object.create({ unitId: 9 }) as Record<string, unknown>;
    expect(extrairIdsErp(corpo)).toEqual({});
  });

  it("recusa lista vazia ou maior que 100 itens", () => {
    const longa = Array.from({ length: 101 }, (_, indice) => indice);
    expect(extrairIdsErp({ billId: [], unitId: longa })).toEqual({});
  });
});

describe("extrairIdsCrm", () => {
  it("converte ID em texto só com dígitos para inteiro", () => {
    const corpo = { idreserva: "55", idempreendimento: 3, nome: "descartado", email: "descartado" };
    expect(extrairIdsCrm(corpo)).toEqual({ idreserva: 55, idempreendimento: 3 });
  });

  it("recusa texto que não é número", () => {
    expect(extrairIdsCrm({ idreserva: "55a", idlead: "" })).toEqual({});
  });
});

describe("tipoEventoCrm", () => {
  it("prefere a funcionalidade do corpo", () => {
    expect(tipoEventoCrm({ funcionalidade: "rs" }, new URLSearchParams("funcionalidade=RP"))).toBe("RS");
  });

  it("usa o parâmetro da URL quando o corpo não traz", () => {
    expect(tipoEventoCrm({}, new URLSearchParams("funcionalidade=RP"))).toBe("RP");
    expect(tipoEventoCrm({}, new URLSearchParams())).toBeNull();
  });
});

describe("lerCorpoLimitado", () => {
  it("devolve o corpo dentro do limite", async () => {
    expect(await lerCorpoLimitado(requisicao('{"unitId":1}'))).toBe('{"unitId":1}');
  });

  it("recusa corpo que declara tamanho acima do limite", async () => {
    const corpo = "x".repeat(20);
    expect(await lerCorpoLimitado(requisicao(corpo, { "content-length": "20" }), 10)).toBeNull();
  });

  it("recusa corpo que passa do limite mesmo sem content-length", async () => {
    const pedacos = [new Uint8Array(8), new Uint8Array(8)];
    const fluxo = new ReadableStream<Uint8Array>({
      start(controlador) {
        pedacos.forEach((pedaco) => controlador.enqueue(pedaco));
        controlador.close();
      },
    });
    expect(await lerCorpoLimitado(requisicao(fluxo), 10)).toBeNull();
  });

  it("aceita exatamente 16 KB e recusa um byte a mais no limite padrão", async () => {
    expect(await lerCorpoLimitado(requisicao("a".repeat(16 * 1024)))).toHaveLength(16 * 1024);
    expect(await lerCorpoLimitado(requisicao("a".repeat(16 * 1024 + 1)))).toBeNull();
  });
});

describe("lerJsonObjeto", () => {
  it("aceita só objeto", () => {
    expect(lerJsonObjeto('{"a":1}')).toEqual({ a: 1 });
    expect(lerJsonObjeto("[1]")).toBeNull();
    expect(lerJsonObjeto("não é json")).toBeNull();
  });
});

describe("canonicalizar", () => {
  it("gera o mesmo hash com os campos em outra ordem", () => {
    const primeiro = sha256Hex(canonicalizar({ idreserva: 1, dados: { b: 2, a: [1, { d: 1, c: 2 }] } }));
    const segundo = sha256Hex(canonicalizar({ dados: { a: [1, { c: 2, d: 1 }], b: 2 }, idreserva: 1 }));
    expect(primeiro).toBe(segundo);
    expect(primeiro).toMatch(/^[0-9a-f]{64}$/);
  });
});

describe("lerTokenBearer", () => {
  it("lê o token do cabeçalho Bearer", () => {
    expect(lerTokenBearer("Bearer abc.def")).toBe("abc.def");
    expect(lerTokenBearer("Basic abc")).toBeNull();
    expect(lerTokenBearer(null)).toBeNull();
  });
});

describe("limite de IDs e resposta do registro", () => {
  it("soma os itens das listas e conta escalar como um", () => {
    expect(contarIds({ receivableBillId: [1, 2, 3], installmentId: 4 })).toBe(4);
  });

  it("aceita até 100 IDs somados e recusa um a mais", () => {
    const cem = Array.from({ length: 100 }, (_, i) => i);
    expect(idsAceitaveis({ billId: cem })).toBe(true);
    expect(idsAceitaveis({ billId: cem, installmentId: 1 })).toBe(false);
    expect(idsAceitaveis({})).toBe(false);
  });

  it("limite vira 429 com Retry-After e token recusado continua 401", async () => {
    expect(statusDoRegistro("gravado")).toBe(200);
    expect(statusDoRegistro("negado")).toBe(401);
    expect(statusDoRegistro("limite")).toBe(429);
    const resposta = respostaEvento(429);
    expect(resposta.status).toBe(429);
    expect(resposta.headers.get("retry-after")).toBe("60");
    expect(await resposta.json()).toEqual({ ok: false });
  });
});
