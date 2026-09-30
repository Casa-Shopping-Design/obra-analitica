import { describe, expect, it } from "vitest";
import { catalogoViews } from "../lib/catalogo-views";
import { tiposAlerta } from "../lib/alertas";
import { buscarPerguntaPronta, perguntasProntas, rotulosAlerta } from "../lib/perguntas-prontas";
import { validarSql } from "../lib/validador-sql";

const colunasPorView = new Map(catalogoViews.map((view) => [view.nome, new Set(view.colunas)]));
const viewsDoSql = (sql: string) =>
  [...sql.matchAll(/\b(?:from|join)\s+([a-z_]+\.[a-z_]+)/gi)].map((referencia) => referencia[1].toLowerCase());

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
    "%s passa no validador de SQL e só lê views do catálogo",
    (_id, pergunta) => {
      expect(validarSql(pergunta.sql).ok).toBe(true);
      const views = viewsDoSql(pergunta.sql).filter((nome) => nome !== "app.centro_custo");
      expect(views.length).toBeGreaterThan(0);
      views.forEach((nome) => expect(colunasPorView.has(nome)).toBe(true));
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
    const sql = buscarPerguntaPronta("obras-pedem-atencao")!.sql;
    const casos = [...sql.matchAll(/when '([a-z_]+)' then '([^']+)'/g)].map(([, tipo, rotulo]) => [tipo, rotulo]);
    expect(Object.fromEntries(casos)).toEqual(rotulosAlerta);
    expect(Object.keys(rotulosAlerta).sort()).toEqual([...tiposAlerta].sort());
  });

  it("busca pelo id e ignora id fora da lista", () => {
    expect(buscarPerguntaPronta("exposicao-maxima")?.pergunta).toBe(
      "Quanto dinheiro próprio cada obra precisa no pior momento?",
    );
    expect(buscarPerguntaPronta("'; drop table app.tenant; --")).toBeUndefined();
    expect(buscarPerguntaPronta(undefined)).toBeUndefined();
  });
});
