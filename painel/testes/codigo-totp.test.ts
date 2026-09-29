import { describe, expect, it } from "vitest";
import { gerarCodigoTotp } from "./e2e/codigo-totp";

// Chave e instantes do apêndice B da RFC 6238 (SHA-1). A RFC mostra oito dígitos; os seis daqui são os últimos.
const segredoRfc = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";

describe("gerarCodigoTotp", () => {
  it.each([
    [59, "287082"],
    [1111111109, "081804"],
    [1111111111, "050471"],
    [1234567890, "005924"],
    [2000000000, "279037"],
  ])("no segundo %i gera %s", (segundo, esperado) => {
    expect(gerarCodigoTotp(segredoRfc, segundo * 1000)).toBe(esperado);
  });

  it("aceita a chave agrupada de quatro em quatro, como a tela mostra", () => {
    expect(gerarCodigoTotp("GEZD GNBV GY3T QOJQ GEZD GNBV GY3T QOJQ", 59_000)).toBe("287082");
  });

  it("recusa chave com caractere fora do base32", () => {
    expect(() => gerarCodigoTotp("GEZD1", 59_000)).toThrow();
  });

  it("muda de código quando a janela de 30 segundos vira", () => {
    expect(gerarCodigoTotp(segredoRfc, 59_999)).toBe("287082");
    expect(gerarCodigoTotp(segredoRfc, 60_000)).not.toBe("287082");
  });
});
