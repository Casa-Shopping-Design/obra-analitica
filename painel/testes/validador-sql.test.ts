import { describe, expect, it } from "vitest";
import { catalogoViews } from "../lib/catalogo-views";
import { perguntasProntas } from "../lib/perguntas-prontas";
import { limiteLinhasConsulta, validarSql } from "../lib/validador-sql";

const legitima =
  "select c.nome as obra, f.competencia, f.saldo_acumulado from marts.fluxo_caixa_mensal f join app.centro_custo c on c.id = f.centro_custo_id where c.nome ilike '%aurora%' order by f.saldo_acumulado";

function sqlAceito(sql: string): string {
  const resultado = validarSql(sql);
  if (!resultado.ok) throw new Error(`recusada: ${resultado.motivo}`);
  return resultado.sql;
}

describe("validador de SQL: os dez casos do plano", () => {
  it("aceita a consulta legítima e devolve o texto reescrito pelo parser", () => {
    const sql = sqlAceito(legitima);
    expect(sql).not.toBe(legitima);
    expect(sql).toMatch(/LIMIT \(500\)$/);
  });

  it.each([
    ["tabela depois de vírgula fora do catálogo", "select * from marts.vso_mensal, staging.parcela_receber"],
    ["schema entre aspas fora do catálogo", 'select * from "staging"."parcela_receber"'],
    ["schema e tabela separados por espaços", "select * from staging . parcela_receber"],
    ["CTE sobre raw", "with bruto as (select payload from raw.registro) select * from bruto"],
    ["limit acima do teto", "select * from marts.vso_mensal limit 99999999"],
    ["duas instruções", "select 1 from marts.vso_mensal; select 1 from marts.estoque_atual"],
    ["função do schema app", "select app.tenant_atual()"],
    ["subconsulta no select sobre tabela fora do catálogo", "select (select count(*) from staging.parcela_receber) as total from marts.vso_mensal"],
  ])("recusa %s", (_caso, sql) => {
    expect(validarSql(sql).ok).toBe(false);
  });

  it("aceita consulta legítima com palavra proibida dentro de comentário e tira o comentário", () => {
    const sql = sqlAceito(`-- drop table app.tenant; delete from staging.parcela_receber\n${legitima} /* insert into raw.registro */`);
    expect(sql).not.toMatch(/drop|delete|insert|--|\/\*/i);
  });
});

describe("validador de SQL: consultas do catálogo e perguntas prontas", () => {
  const exemplos = catalogoViews.flatMap((view) => view.exemplos.map((exemplo) => [exemplo.pergunta, exemplo.sql] as const));
  const prontas = perguntasProntas.map((pergunta) => [pergunta.id, pergunta.sql] as const);

  // O diretor lê o catálogo inteiro; o que cada perfil não lê é testado no bloco de catálogo por perfil.
  it.each([...exemplos, ...prontas])("aceita %s", (_nome, sql) => {
    expect(validarSql(sql, "diretor")).toMatchObject({ ok: true });
  });

  it.each(["marts.estoque_obra", "marts.estoque_tipologia", "marts.posicao_carteira", "marts.alertas_obra"])(
    "aceita select na view %s da migration 0024",
    (view) => {
      expect(validarSql(`select * from ${view}`).ok).toBe(true);
    },
  );

  it.each([
    ["simulação no from", "select * from marts.simular_venda_estoque('00000000-0000-4000-8000-000000000000', 4, 0)"],
    ["resumo da simulação no select", "select marts.resumo_venda_estoque(centro_custo_id, 4, 0) from marts.estoque_obra"],
  ])("recusa a %s, que fica só na tela", (_caso, sql) => {
    expect(validarSql(sql).ok).toBe(false);
  });

  it("aceita agregação com filter (where ...), que o catálogo pode usar", () => {
    expect(validarSql("select count(*) filter (where vendas > 0) from marts.vso_mensal").ok).toBe(true);
  });
});

describe("validador de SQL: catálogo por perfil (correção C4)", () => {
  const lucro = "select obra, viabilidade, tendencia, desvio from marts.dre_viabilidade where linha = 'lucro_operacional'";
  const viewsResultado = [
    "marts.dre_viabilidade",
    "marts.dre_resumo_obra",
    "marts.dre_resumo_carteira",
    "marts.tendencia_resultado_mensal",
    "marts.imposto_obra",
  ];

  it.each(["diretor", "financeiro", "leitura"])("aceita a DRE para %s", (perfil) => {
    expect(validarSql(lucro, perfil)).toMatchObject({ ok: true });
  });

  it.each(["gerente_obra", "comercial"])("recusa a DRE para %s, como view fora do catálogo dele", (perfil) => {
    expect(validarSql(lucro, perfil)).toEqual({ ok: false, motivo: "relacao fora do catalogo: marts.dre_viabilidade" });
  });

  it("sem perfil lido vale o catálogo sem as views restritas", () => {
    expect(validarSql(lucro).ok).toBe(false);
    expect(validarSql(lucro, null).ok).toBe(false);
    expect(validarSql("select obra, exposicao_maxima from marts.posicao_financeira_obra").ok).toBe(true);
  });

  it.each(viewsResultado)("gerente não lê %s nem escondida em CTE, subconsulta ou join", (view) => {
    expect(validarSql(`select * from ${view}`, "gerente_obra").ok).toBe(false);
    expect(validarSql(`with d as (select * from ${view}) select * from d`, "gerente_obra").ok).toBe(false);
    expect(validarSql(`select (select count(*) from ${view}) as n from marts.vso_mensal`, "gerente_obra").ok).toBe(false);
    expect(
      validarSql(`select * from marts.vso_mensal v join ${view} d on d.centro_custo_id = v.centro_custo_id`, "gerente_obra").ok,
    ).toBe(false);
    expect(validarSql(`select * from ${view}`, "leitura").ok).toBe(true);
  });

  it("a soma da coluna inteira da DRE passa no validador: quem avisa que não se soma é a descrição do catálogo", () => {
    expect(validarSql("select sum(tendencia) from marts.dre_viabilidade", "diretor").ok).toBe(true);
    const descricao = catalogoViews.find((view) => view.nome === "marts.dre_viabilidade")!.descricao;
    expect(descricao).toContain("nunca some a coluna inteira");
  });

  it("a tabela do estudo fica fora do catálogo de todo perfil", () => {
    for (const perfil of ["diretor", "financeiro", "leitura", "gerente_obra", null]) {
      expect(validarSql("select * from app.estudo_viabilidade", perfil).ok).toBe(false);
      expect(validarSql("select * from app.posicao_dre_mensal", perfil).ok).toBe(false);
    }
  });
});

describe("validador de SQL: tentativas de fuga", () => {
  it.each([
    ["set_config que troca os claims lidos pelo RLS", "select set_config('request.jwt.claims', '{}', true) from marts.vso_mensal"],
    ["current_setting", "select current_setting('request.jwt.claims')"],
    ["função que roda SQL em texto", "select query_to_xml('select * from raw.registro', true, true, '')"],
    ["função pg_", "select pg_sleep(10)"],
    ["função qualificada por pg_catalog", "select pg_catalog.sum(vendas) from marts.vso_mensal"],
    ["função do schema auth", "select auth.uid()"],
    ["função no from", "select * from generate_series(1, 1000000000)"],
    ["CTE que apaga dados", "with apagado as (delete from app.tenant returning id) select * from apagado"],
    ["with recursive", "with recursive r(n) as (select 1 union all select n + 1 from r) select n from r"],
    ["select for update", "select * from marts.vso_mensal for update"],
    ["insert", "insert into app.tenant (razao_social) values ('x')"],
    ["update", "update app.centro_custo set nome = 'x'"],
    ["parâmetro posicional", "select * from marts.vso_mensal limit $1"],
    ["limit por expressão", "select * from marts.vso_mensal limit 400 + 400"],
    ["limit all", "select * from marts.vso_mensal limit all"],
    ["current_user", "select current_user"],
    ["tabela sem schema que não é CTE", "select * from parcela_receber"],
    ["schema com maiúsculas entre aspas", 'select * from "MARTS"."VSO_MENSAL"'],
    ["cast para regclass", "select 'raw.registro'::regclass"],
    ["operador qualificado por schema", "select 1 from marts.vso_mensal where vendas operator(public.+) 1 = 2"],
    ["tabela de fora na subconsulta do where", "select * from marts.vso_mensal where exists (select 1 from raw.registro)"],
    ["tabela de fora no join", "select * from marts.vso_mensal v join staging.contrato_venda c on c.centro_custo_id = v.centro_custo_id"],
    ["tabela de fora no union", "select vendas from marts.vso_mensal union select 1 from app.usuario_tenant"],
    ["texto vazio", ""],
    ["só comentário", "-- select 1"],
    ["sintaxe inválida", "selec * from marts.vso_mensal"],
  ])("recusa %s", (_caso, sql) => {
    expect(validarSql(sql).ok).toBe(false);
  });

  it("CTE com nome que imita schema continua apontando para a CTE", () => {
    const sql = sqlAceito('with "staging.parcela_receber" as (select 1 as n) select n from "staging.parcela_receber"');
    expect(sql).toContain('FROM "staging.parcela_receber"');
  });

  it("CTE não fica visível para quem vem antes dela", () => {
    expect(validarSql("with a as (select * from b), b as (select 1) select * from a").ok).toBe(false);
  });
});

describe("validador de SQL: limite de linhas", () => {
  it("mantém limit dentro do teto", () => {
    expect(sqlAceito("select vendas from marts.vso_mensal limit 10")).toMatch(/LIMIT \(10\)$/);
  });

  it("aceita limit igual ao teto", () => {
    expect(validarSql(`select vendas from marts.vso_mensal limit ${limiteLinhasConsulta}`).ok).toBe(true);
  });

  it("acrescenta o teto quando falta limit e preserva offset", () => {
    expect(sqlAceito("select vendas from marts.vso_mensal offset 5")).toMatch(/OFFSET \(5\)\s*LIMIT \(500\)$/);
  });

  it("põe o teto na consulta de fora do with", () => {
    expect(sqlAceito("with v as (select vendas from marts.vso_mensal) select * from v")).toMatch(/FROM v\s+LIMIT \(500\)$/);
  });

  it("embrulha union num select com o teto", () => {
    const sql = sqlAceito("select vendas from marts.vso_mensal union all select distratos from marts.vso_mensal");
    expect(sql).toMatch(/^SELECT \*\s+FROM \(/);
    expect(sql).toMatch(/LIMIT \(500\)$/);
  });

  it("reescrita é estável: validar o texto reescrito devolve o mesmo texto", () => {
    const sql = sqlAceito(legitima);
    expect(sqlAceito(sql)).toBe(sql);
  });
});
