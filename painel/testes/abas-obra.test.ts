import { describe, expect, it } from "vitest";
import { abaAtiva, abasObra } from "../lib/abas-obra";

const id = "8e588cdd-3847-4cbb-a2a9-a21be7dffa20";
const raiz = `/obras/${id}`;
const rotulos = (acesso: { verDre: boolean; verConferencia: boolean }) => abasObra(id, acesso).map((aba) => aba.rotulo);

describe("abasObra", () => {
  it("abre pelo resumo e leva DRE, imposto e conferência para o diretor", () => {
    expect(rotulos({ verDre: true, verConferencia: true })).toEqual([
      "Resumo",
      "DRE de viabilidade",
      "Imposto",
      "Unidades",
      "Estoque",
      "Simulação",
      "Vendas e repasse",
      "Execução física",
      "Inadimplência",
      "Conferência",
      "Relatório",
    ]);
  });

  it("esconde DRE, imposto e conferência de quem não tem o perfil", () => {
    const abas = rotulos({ verDre: false, verConferencia: false });
    expect(abas).not.toContain("DRE de viabilidade");
    expect(abas).not.toContain("Imposto");
    expect(abas).not.toContain("Conferência");
    expect(abas).toHaveLength(8);
  });

  it("monta o destino de cada aba dentro da obra", () => {
    const destinos = abasObra(id, { verDre: true, verConferencia: false }).map((aba) => aba.destino);
    expect(destinos[0]).toBe(raiz);
    expect(destinos[1]).toBe(`${raiz}/dre`);
  });
});

describe("abaAtiva", () => {
  it("marca o resumo só na tela da obra", () => {
    expect(abaAtiva(raiz, raiz, raiz)).toBe(true);
    expect(abaAtiva(`${raiz}/dre`, raiz, raiz)).toBe(false);
  });

  it("mantém a DRE ativa no estudo de viabilidade", () => {
    expect(abaAtiva(`${raiz}/dre/estudo`, `${raiz}/dre`, raiz)).toBe(true);
  });

  it("não confunde telas com começo parecido", () => {
    expect(abaAtiva(`${raiz}/estoque-antigo`, `${raiz}/estoque`, raiz)).toBe(false);
  });
});
