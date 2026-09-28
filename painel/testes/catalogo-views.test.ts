import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { catalogoDoPerfil, catalogoViews } from "../lib/catalogo-views";
import { validarSql } from "../lib/validador-sql";

const migrations = join(__dirname, "..", "..", "supabase", "migrations");
const viewsNovas: Record<string, string> = {
  "marts.repasse_obra": "0018_crm.sql",
  "marts.funil_vendas_mensal": "0018_crm.sql",
  "marts.execucao_fisica_obra": "0019_complementos_origem.sql",
  "marts.inadimplencia_faixa": "0019_complementos_origem.sql",
  "marts.conferencia_origem": "0019_complementos_origem.sql",
};

// Trecho da migration entre o create view e o grant da mesma view.
function definicaoView(arquivo: string, nome: string): string {
  const sql = readFileSync(join(migrations, arquivo), "utf8");
  const inicio = sql.indexOf(`create or replace view ${nome} `);
  const fim = sql.indexOf(`grant select on ${nome} `, inicio);
  expect(inicio).toBeGreaterThanOrEqual(0);
  expect(fim).toBeGreaterThan(inicio);
  return sql.slice(inicio, fim);
}

describe("catálogo das views novas", () => {
  it("tem as cinco views das migrations 0018 e 0019", () => {
    const nomes = catalogoViews.map((view) => view.nome);
    for (const nome of Object.keys(viewsNovas)) expect(nomes).toContain(nome);
  });

  it("só descreve colunas que existem na view", () => {
    for (const [nome, arquivo] of Object.entries(viewsNovas)) {
      const definicao = definicaoView(arquivo, nome);
      const view = catalogoViews.find((item) => item.nome === nome)!;
      for (const coluna of view.colunas) {
        expect(definicao, `${nome}.${coluna}`).toMatch(new RegExp(`\\b${coluna}\\b`));
      }
    }
  });

  it("todo exemplo passa pelo validador", () => {
    for (const view of catalogoViews) {
      for (const exemplo of view.exemplos) {
        expect(validarSql(exemplo.sql), exemplo.pergunta).toMatchObject({ ok: true });
      }
    }
  });
});

describe("catalogoDoPerfil", () => {
  it("deixa a conferência com o ERP só para diretor e financeiro", () => {
    const nomesDe = (perfil: string | null) => catalogoDoPerfil(perfil).map((view) => view.nome);
    expect(nomesDe("diretor")).toContain("marts.conferencia_origem");
    expect(nomesDe("financeiro")).toContain("marts.conferencia_origem");
    expect(nomesDe("gerente_obra")).not.toContain("marts.conferencia_origem");
    expect(nomesDe("comercial")).not.toContain("marts.conferencia_origem");
    expect(nomesDe(null)).not.toContain("marts.conferencia_origem");
  });

  it("mantém as views sem restrição para qualquer perfil", () => {
    expect(catalogoDoPerfil("leitura").map((view) => view.nome)).toContain("marts.repasse_obra");
    expect(catalogoDoPerfil(null)).toHaveLength(catalogoViews.length - 1);
  });
});
