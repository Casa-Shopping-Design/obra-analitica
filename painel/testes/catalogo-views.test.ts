import { readdirSync, readFileSync } from "node:fs";
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
  "marts.dre_resumo_carteira": "0031_dre_resumo_carteira.sql",
  "marts.tendencia_resultado_mensal": "0033_posicao_dre_mensal.sql",
  "marts.imposto_obra": "0034_imposto_obra.sql",
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
  it("tem as views das migrations 0018, 0019, 0024, 0026, 0027, 0030, 0031, 0033 e 0034", () => {
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

  it("todo exemplo passa pelo validador com um perfil que lê a view", () => {
    for (const view of catalogoViews) {
      for (const exemplo of view.exemplos) {
        expect(validarSql(exemplo.sql, view.perfis?.[0] ?? null), exemplo.pergunta).toMatchObject({ ok: true });
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

  it("deixa a DRE de viabilidade, os resumos dela, a tendência mensal e o imposto para diretor, financeiro e leitura", () => {
    const nomesDe = (perfil: string | null) => catalogoDoPerfil(perfil).map((view) => view.nome);
    for (const nome of [
      "marts.dre_viabilidade", "marts.dre_resumo_obra", "marts.dre_resumo_carteira", "marts.tendencia_resultado_mensal",
      "marts.imposto_obra",
    ]) {
      expect(nomesDe("diretor")).toContain(nome);
      expect(nomesDe("financeiro")).toContain(nome);
      expect(nomesDe("leitura")).toContain(nome);
      expect(nomesDe("gerente_obra")).not.toContain(nome);
      expect(nomesDe("comercial")).not.toContain(nome);
      expect(nomesDe(null)).not.toContain(nome);
    }
  });

  it("deixa o gerente de obra sem nenhuma view de resultado e o perfil leitura com todas", () => {
    const viewsResultado = [
      "marts.dre_viabilidade", "marts.dre_resumo_obra", "marts.dre_resumo_carteira", "marts.tendencia_resultado_mensal",
      "marts.imposto_obra",
    ];
    const gerente = catalogoDoPerfil("gerente_obra").map((view) => view.nome);
    const leitura = catalogoDoPerfil("leitura").map((view) => view.nome);
    expect(gerente).not.toEqual(expect.arrayContaining(viewsResultado));
    viewsResultado.forEach((nome) => expect(gerente).not.toContain(nome));
    expect(leitura).toEqual(expect.arrayContaining(viewsResultado));
  });

  it("mantém as views sem restrição para qualquer perfil", () => {
    expect(catalogoDoPerfil("leitura").map((view) => view.nome)).toContain("marts.repasse_obra");
    expect(catalogoDoPerfil("gerente_obra").map((view) => view.nome)).toEqual(
      expect.arrayContaining(["marts.repasse_banco", "marts.leads_origem"]),
    );
    // Onze views restritas: conferência com o ERP, DRE de viabilidade, os resumos dela por obra e da carteira,
    // a tendência mensal, a gestão de imposto e as cinco da visão por empresa.
    expect(catalogoDoPerfil(null)).toHaveLength(catalogoViews.length - 11);
  });
});

const viewsEmpresa = [
  "marts.fontes_usos_mensal",
  "marts.dre_societaria_mensal",
  "marts.custo_incorrido_mensal",
  "marts.empresa_resumo",
];
const colunasMensais = ["empresa_id", "empresa", "competencia", "linha", "rotulo", "ordem", "tipo", "nivel", "valor_mes", "valor_acumulado"];

// As views da visão por empresa saem das migrations 0036 a 0038, escritas em paralelo; enquanto não existem,
// o teste de colunas contra o SQL fica pulado e o contrato abaixo segura os nomes.
function migrationDaView(nome: string): string | null {
  const arquivos = readdirSync(migrations).filter((arquivo) => /^003[6-9]_.*\.sql$/.test(arquivo));
  return arquivos.find((arquivo) => readFileSync(join(migrations, arquivo), "utf8").includes(`view ${nome} `)) ?? null;
}

describe("catálogo da visão por empresa", () => {
  const nomesDe = (perfil: string | null) => catalogoDoPerfil(perfil).map((view) => view.nome);

  it("deixa as views mensais e o resumo para diretor, financeiro e leitura, nunca para o gerente", () => {
    for (const nome of viewsEmpresa) {
      expect(nomesDe("diretor")).toContain(nome);
      expect(nomesDe("financeiro")).toContain(nome);
      expect(nomesDe("leitura")).toContain(nome);
      expect(nomesDe("gerente_obra")).not.toContain(nome);
      expect(nomesDe("comercial")).not.toContain(nome);
      expect(nomesDe(null)).not.toContain(nome);
    }
  });

  it("deixa o controle das Fontes e Usos só para diretor e financeiro", () => {
    expect(nomesDe("diretor")).toContain("marts.controle_fontes_usos");
    expect(nomesDe("financeiro")).toContain("marts.controle_fontes_usos");
    expect(nomesDe("leitura")).not.toContain("marts.controle_fontes_usos");
    expect(nomesDe("gerente_obra")).not.toContain("marts.controle_fontes_usos");
    expect(validarSql("select * from marts.controle_fontes_usos", "leitura").ok).toBe(false);
    expect(validarSql("select * from marts.controle_fontes_usos", "financeiro").ok).toBe(true);
  });

  it("descreve as três views mensais com as colunas do contrato", () => {
    for (const nome of viewsEmpresa.slice(0, 3)) {
      expect(catalogoViews.find((view) => view.nome === nome)!.colunas).toEqual(colunasMensais);
    }
  });

  it("avisa nas views mensais para filtrar por linha e não somar total com linha, e diz o sinal", () => {
    for (const nome of viewsEmpresa.slice(0, 3)) {
      const descricao = catalogoViews.find((view) => view.nome === nome)!.descricao;
      expect(descricao).toContain("filtre sempre por linha");
      expect(descricao).toContain("nunca some a coluna inteira");
      expect(descricao).toMatch(/Sinal:/);
    }
    expect(catalogoViews.find((view) => view.nome === "marts.fontes_usos_mensal")!.descricao).toContain(
      "valor positivo e fonte",
    );
  });

  it("não cita o ERP de origem pelo nome", () => {
    const textos = catalogoViews.filter((view) => [...viewsEmpresa, "marts.controle_fontes_usos"].includes(view.nome));
    for (const view of textos) expect(JSON.stringify(view)).not.toMatch(/sienge/i);
  });

  it.each([...viewsEmpresa, "marts.controle_fontes_usos"])("%s só descreve colunas que existem na migration, quando ela já existe", (nome) => {
    const arquivo = migrationDaView(nome);
    if (arquivo === null) return;
    const definicao = definicaoView(arquivo, nome);
    for (const coluna of catalogoViews.find((view) => view.nome === nome)!.colunas) {
      expect(definicao, `${nome}.${coluna}`).toMatch(new RegExp(`\\b${coluna}\\b`));
    }
  });
});
