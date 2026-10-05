import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { cores } from "../lib/cores-grafico";

const textoCss = readFileSync(join(__dirname, "..", "app", "globals.css"), "utf8");

function lerTokens(css: string): Record<string, string> {
  const tokens: Record<string, string> = {};
  for (const [, nome, valor] of css.matchAll(/--color-([a-z-]+):\s*(#[0-9a-f]{6})\s*;/gi)) {
    tokens[nome] = valor.toLowerCase();
  }
  return tokens;
}

function luminancia(hex: string): number {
  const [r, g, b] = [1, 3, 5].map((inicio) => {
    const canal = parseInt(hex.slice(inicio, inicio + 2), 16) / 255;
    return canal <= 0.03928 ? canal / 12.92 : ((canal + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function contraste(primeira: string, segunda: string): number {
  const [clara, escura] = [luminancia(primeira), luminancia(segunda)].sort((a, b) => b - a);
  return (clara + 0.05) / (escura + 0.05);
}

function arredondar(valor: number): number {
  return Number(valor.toFixed(2));
}

const tokens = lerTokens(textoCss);

describe("paleta APO", () => {
  it("cores-grafico.ts repete os valores de globals.css", () => {
    const chaves = Object.keys(cores) as (keyof typeof cores)[];
    expect(chaves).toHaveLength(10);
    for (const chave of chaves) {
      expect(tokens[chave], chave).toBe(cores[chave].toLowerCase());
    }
  });

  it("os pares de texto e fundo do anexo E dão o contraste calculado à mão", () => {
    const pares: [string, string, number][] = [
      [tokens.texto, tokens.fundo, 15.06],
      [tokens.suave, tokens.superficie, 6.59],
      [tokens.suave, tokens.fundo, 6.01],
      [tokens.entrada, tokens.superficie, 5.08],
      [tokens.entrada, tokens.fundo, 4.63],
      [tokens["menu-texto"], tokens.menu, 9.65],
      [tokens["menu-suave"], tokens.menu, 6.66],
      [tokens.superficie, tokens["menu-ativo"], 7.73],
      [tokens.alerta, tokens.fundo, 5.96],
      [tokens.atencao, tokens.fundo, 5.4],
    ];
    for (const [texto, fundo, esperado] of pares) {
      const calculado = contraste(texto, fundo);
      expect(arredondar(calculado), `${texto} sobre ${fundo}`).toBe(esperado);
      expect(calculado).toBeGreaterThanOrEqual(4.5);
    }
  });

  it("o verde do repasse não tem contraste para texto", () => {
    const calculado = contraste(tokens.repasse, tokens.superficie);
    expect(arredondar(calculado)).toBe(2.41);
    expect(calculado).toBeLessThan(4.5);
  });

  it("o cinza de referência serve para linha de gráfico e não para texto", () => {
    const sobreSuperficie = contraste(tokens.referencia, tokens.superficie);
    const sobreFundo = contraste(tokens.referencia, tokens.fundo);
    expect(arredondar(sobreSuperficie)).toBe(3.82);
    expect(arredondar(sobreFundo)).toBe(3.48);
    expect(Math.min(sobreSuperficie, sobreFundo)).toBeGreaterThanOrEqual(3);
    expect(sobreSuperficie).toBeLessThan(4.5);
  });
});
