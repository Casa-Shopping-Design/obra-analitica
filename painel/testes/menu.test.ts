import { describe, expect, it } from "vitest";
import { itemAtivo, itensMenu } from "../lib/menu";

const destinos = (perfil: string | null) => itensMenu(perfil).map((item) => item.destino);

describe("itensMenu", () => {
  it.each(["diretor", "financeiro", "leitura"])("mostra Empresas para %s, antes do assistente", (perfil) => {
    expect(destinos(perfil)).toEqual(["/", "/dre", "/obras", "/unidades", "/empresas", "/assistente"]);
  });

  it.each(["gerente_obra", "comercial", null])("esconde Empresas de %s e mantém o resto", (perfil) => {
    expect(destinos(perfil)).toEqual(["/", "/dre", "/obras", "/unidades", "/assistente"]);
  });

  it("dá o rótulo Empresas ao item novo", () => {
    expect(itensMenu("leitura").find((item) => item.destino === "/empresas")?.rotulo).toBe("Empresas");
  });
});

describe("itemAtivo", () => {
  it("marca Empresas também na tela de uma empresa e no mapa de contas", () => {
    expect(itemAtivo("/empresas", "/empresas")).toBe(true);
    expect(itemAtivo("/empresas/7a1c3e5f-2b4d-4c6e-8f0a-1b2c3d4e5f60", "/empresas")).toBe(true);
    expect(itemAtivo("/empresas/mapa-contas", "/empresas")).toBe(true);
    expect(itemAtivo("/empresas-antigas", "/empresas")).toBe(false);
  });

  it("marca a visão geral só na raiz", () => {
    expect(itemAtivo("/", "/")).toBe(true);
    expect(itemAtivo("/obras", "/")).toBe(false);
  });
});
