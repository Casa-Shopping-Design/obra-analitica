import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const raizPainel = join(__dirname, "..");
const pastasLidas = ["app", "componentes", "lib"];
const nomeAntigo = /obra[ _-]?anal[ií]tica/i;

function arquivosDaPasta(pasta: string): string[] {
  return readdirSync(join(raizPainel, pasta), { recursive: true, withFileTypes: true })
    .filter((entrada) => entrada.isFile())
    .map((entrada) => join(entrada.parentPath, entrada.name));
}

describe("marca APO", () => {
  it("nenhum arquivo de app, componentes ou lib cita o nome antigo", () => {
    const arquivos = pastasLidas.flatMap(arquivosDaPasta);
    expect(arquivos.length).toBeGreaterThan(0);
    const comNomeAntigo = arquivos.filter((arquivo) => nomeAntigo.test(readFileSync(arquivo, "utf8")));
    expect(comNomeAntigo).toEqual([]);
  });
});
