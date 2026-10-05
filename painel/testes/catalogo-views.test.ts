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
  "marts.estoque_tipologia": "0024_estoque_carteira_simulacao.sql",
  "marts.estoque_obra": "0024_estoque_carteira_simulacao.sql",
  "marts.posicao_carteira": "0024_estoque_carteira_simulacao.sql",
  "marts.alertas_obra": "0024_estoque_carteira_simulacao.sql",
  "marts.repasse_banco": "0026_repasse_banco_leads_origem.sql",
  "marts.leads_origem": "0026_repasse_banco_leads_origem.sql",
  "marts.comparativo_obras": "0027_comparativo_obras.sql",
  "marts.dre_viabilidade": "0030_dre_viabilidade.sql",
  "marts.dre_resumo_obra": "0030_dre_viabilidade.sql",
};

// Trecho da migration entre o create view e o próximo create ou grant no começo de linha.
function definicaoView(arquivo: string, nome: string): string {
  const sql = readFileSync(join(migrations, arquivo), "utf8");
  const inicio = Math.max(sql.indexOf(`create or replace view ${nome} `), sql.indexOf(`create view ${nome} `));
  expect(inicio).toBeGreaterThanOrEqual(0);
  const proximo = sql.slice(inicio + 1).search(/\n(create|grant) /);
  expect(proximo).toBeGreaterThan(0);
  return sql.slice(inicio, inicio + 1 + proximo);
}

describe("catálogo das views novas", () => {
  it("tem as views das migrations 0018, 0019, 0024, 0026, 0027 e 0030", () => {
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

  it("responde qual obra tem a maior exposição pelo comparativo, para qualquer perfil", () => {
    const sql = "select obra, exposicao_maxima from marts.comparativo_obras order by exposicao_maxima desc limit 1";
    expect(validarSql(sql)).toMatchObject({ ok: true });
    expect(catalogoDoPerfil("gerente_obra").map((view) => view.nome)).toContain("marts.comparativo_obras");
  });

  it("deixa as funções de simulação fora do catálogo", () => {
    const nomes = catalogoViews.map((view) => view.nome);
    expect(nomes).not.toContain("marts.simular_venda_estoque");
    expect(nomes).not.toContain("marts.resumo_venda_estoque");
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

  it("deixa a DRE de viabilidade e o resumo dela só para diretor e financeiro", () => {
    const nomesDe = (perfil: string | null) => catalogoDoPerfil(perfil).map((view) => view.nome);
    for (const nome of ["marts.dre_viabilidade", "marts.dre_resumo_obra"]) {
      expect(nomesDe("diretor")).toContain(nome);
      expect(nomesDe("financeiro")).toContain(nome);
      expect(nomesDe("gerente_obra")).not.toContain(nome);
      expect(nomesDe(null)).not.toContain(nome);
    }
  });

  it("mantém as views sem restrição para qualquer perfil", () => {
    expect(catalogoDoPerfil("leitura").map((view) => view.nome)).toContain("marts.repasse_obra");
    expect(catalogoDoPerfil("gerente_obra").map((view) => view.nome)).toEqual(
      expect.arrayContaining(["marts.repasse_banco", "marts.leads_origem"]),
    );
    // Três views restritas: conferência com o ERP, DRE de viabilidade e resumo da DRE.
    expect(catalogoDoPerfil(null)).toHaveLength(catalogoViews.length - 3);
  });
});
