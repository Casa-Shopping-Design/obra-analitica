import { describe, expect, it } from "vitest";
import { catalogoDoPerfil, catalogoViews } from "../lib/catalogo-views";
import { tiposAlerta } from "../lib/alertas";
import { rotuloLinha } from "../lib/dre";
import {
  buscarPerguntaPronta,
  perguntasProntas,
  perguntasProntasDoPerfil,
  rotulosAlerta,
  type PerguntaPronta,
} from "../lib/perguntas-prontas";
import { validarSql } from "../lib/validador-sql";

const colunasPorView = new Map(catalogoViews.map((view) => [view.nome, new Set(view.colunas)]));
const viewsDoSql = (sql: string) =>
  [...sql.matchAll(/\b(?:from|join)\s+([a-z_]+\.[a-z_]+)/gi)].map((referencia) => referencia[1].toLowerCase());
const primeiroPerfil = (pergunta: PerguntaPronta) => pergunta.perfis?.[0] ?? null;

const perguntasDre = [
  "tendencia-lucro-obras",
  "linha-mais-desvia-parque",
  "margem-perdida-obras",
  "receita-a-apropriar-obras",
  "imposto-a-gerar-obras",
];

describe("perguntas prontas", () => {
  it("tem ids únicos", () => {
    const ids = perguntasProntas.map((pergunta) => pergunta.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it("tem o texto de cada pergunta único", () => {
    const textos = perguntasProntas.map((pergunta) => pergunta.pergunta);
    expect(new Set(textos).size).toBe(textos.length);
  });

  it.each(perguntasProntas.map((pergunta) => [pergunta.id, pergunta] as const))(
    "%s passa no validador de SQL com o primeiro perfil dela e só lê views do catálogo desse perfil",
    (_id, pergunta) => {
      expect(validarSql(pergunta.sql, primeiroPerfil(pergunta)).ok).toBe(true);
      const views = viewsDoSql(pergunta.sql).filter((nome) => nome !== "app.centro_custo");
      expect(views.length).toBeGreaterThan(0);
      views.forEach((nome) => expect(colunasPorView.has(nome)).toBe(true));
      const doPerfil = new Set(catalogoDoPerfil(primeiroPerfil(pergunta)).map((view) => view.nome));
      views.forEach((nome) => expect(doPerfil).toContain(nome));
    },
  );

  it.each(perguntasProntas.map((pergunta) => [pergunta.id, pergunta] as const))(
    "%s mostra só colunas que existem nas views que consulta",
    (_id, pergunta) => {
      const disponiveis = new Set(["obra"]);
      viewsDoSql(pergunta.sql).forEach((nome) => colunasPorView.get(nome)?.forEach((coluna) => disponiveis.add(coluna)));
      pergunta.colunas.forEach((coluna) => expect(disponiveis).toContain(coluna.chave));
    },
  );

  it("não usa as views retiradas do assistente", () => {
    perguntasProntas.forEach((pergunta) => {
      expect(pergunta.sql).not.toMatch(/consolidado_centro_custo|break_even_obra/);
    });
  });

  it("nunca pede nome de comprador", () => {
    perguntasProntas.forEach((pergunta) => {
      expect(pergunta.sql).not.toMatch(/nome_cliente|cpf/i);
    });
  });

  it("leva ao assistente as views de estoque, carteira e alertas da migration 0024", () => {
    const views = new Set(perguntasProntas.flatMap((pergunta) => viewsDoSql(pergunta.sql)));
    ["marts.estoque_obra", "marts.estoque_tipologia", "marts.posicao_carteira", "marts.alertas_obra"].forEach((nome) =>
      expect(views).toContain(nome),
    );
  });

  it("não chama as funções de simulação", () => {
    perguntasProntas.forEach((pergunta) => {
      expect(pergunta.sql).not.toMatch(/simular_venda_estoque|resumo_venda_estoque/);
    });
  });

  it("dá rótulo a todo tipo de alerta, igual ao case do sql da pergunta de atenção", () => {
    const sql = buscarPerguntaPronta("obras-pedem-atencao", null)!.sql;
    const casos = [...sql.matchAll(/when '([a-z_]+)' then '([^']+)'/g)].map(([, tipo, rotulo]) => [tipo, rotulo]);
    expect(Object.fromEntries(casos)).toEqual(rotulosAlerta);
    expect(Object.keys(rotulosAlerta).sort()).toEqual([...tiposAlerta].sort());
  });

  it("busca pelo id e ignora id fora da lista", () => {
    expect(buscarPerguntaPronta("exposicao-maxima", null)?.pergunta).toBe(
      "Quanto dinheiro próprio cada obra precisa no pior momento?",
    );
    expect(buscarPerguntaPronta("'; drop table app.tenant; --", "diretor")).toBeUndefined();
    expect(buscarPerguntaPronta(undefined, "diretor")).toBeUndefined();
  });
});

describe("perguntas prontas sobre viabilidade, tendência e imposto", () => {
  it("as cinco perguntas leem as views de DRE e de imposto", () => {
    const views = new Set(perguntasDre.flatMap((id) => viewsDoSql(buscarPerguntaPronta(id, "diretor")!.sql)));
    expect(views).toEqual(new Set(["marts.dre_viabilidade", "marts.dre_resumo_obra", "marts.imposto_obra"]));
  });

  it.each(["diretor", "financeiro", "leitura"])("aparecem para %s", (perfil) => {
    const ids = perguntasProntasDoPerfil(perfil).map((pergunta) => pergunta.id);
    expect(ids).toEqual(expect.arrayContaining(perguntasDre));
    expect(ids).toHaveLength(perguntasProntas.length);
  });

  it.each(["gerente_obra", "comercial", null])("não aparecem para %s, nem por id", (perfil) => {
    const ids = perguntasProntasDoPerfil(perfil).map((pergunta) => pergunta.id);
    perguntasDre.forEach((id) => {
      expect(ids).not.toContain(id);
      expect(buscarPerguntaPronta(id, perfil)).toBeUndefined();
    });
    expect(ids).toHaveLength(perguntasProntas.length - perguntasDre.length);
    expect(ids).toContain("exposicao-maxima");
  });

  it("o validador recusa o SQL delas para o gerente, mesmo que o id chegasse à consulta", () => {
    perguntasDre.forEach((id) => {
      expect(validarSql(buscarPerguntaPronta(id, "diretor")!.sql, "gerente_obra").ok).toBe(false);
    });
  });

  it("dá à linha da DRE o mesmo rótulo da tela, igual ao case do sql da pergunta da Parque", () => {
    const sql = buscarPerguntaPronta("linha-mais-desvia-parque", "diretor")!.sql;
    const casos = [...sql.matchAll(/when '([a-z_]+)' then '([^']+)'/g)].map(([, linha, rotulo]) => [linha, rotulo]);
    expect(casos).toHaveLength(11);
    casos.forEach(([linha, rotulo]) => expect(rotuloLinha(linha)).toBe(rotulo));
  });

  it("formata fração como percentual, nunca como real", () => {
    const colunas = perguntasDre.flatMap((id) => [...buscarPerguntaPronta(id, "diretor")!.colunas]);
    const fracoes = colunas.filter((coluna) => /pct|margem|aliquota/.test(coluna.chave));
    expect(fracoes.length).toBeGreaterThan(0);
    fracoes.forEach((coluna) => expect(coluna.formato).toBe("percentual"));
  });
});
