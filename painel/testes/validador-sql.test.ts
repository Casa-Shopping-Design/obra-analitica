import { describe, expect, it } from "vitest";
import { catalogoViews } from "../lib/catalogo-views";
import { limiteLinhas, validarSql } from "../lib/validador-sql";

async function aceita(sql: string): Promise<string> {
  const resultado = await validarSql(sql);
  if (!resultado.ok) throw new Error(`recusou uma consulta legítima (${resultado.motivo}): ${sql}`);
  return resultado.sql;
}

async function motivoDaRecusa(sql: string): Promise<string> {
  const resultado = await validarSql(sql);
  if (resultado.ok) throw new Error(`aceitou uma consulta que devia recusar: ${sql}`);
  return resultado.motivo;
}

describe("validarSql aceita", () => {
  const exemplosDoCatalogo = catalogoViews.flatMap((view) => view.exemplos.map((exemplo) => [exemplo.pergunta, exemplo.sql]));

  it.each(exemplosDoCatalogo)("exemplo do catálogo: %s", async (_pergunta, sql) => {
    await aceita(sql);
  });

  it("consulta legítima e devolve o SQL reescrito com limite", async () => {
    const sql = await aceita("select obra, exposicao_maxima from marts.posicao_financeira_obra order by exposicao_maxima desc");
    expect(sql).toContain("marts.posicao_financeira_obra");
    expect(sql).toContain(`LIMIT ${limiteLinhas}`);
  });

  it("comentário com palavra proibida em consulta legítima, e o comentário some da saída", async () => {
    const sql = await aceita("select sum(disponiveis) from marts.estoque_atual -- drop table app.tenant; delete from raw.registro\n");
    expect(sql).not.toContain("drop");
    expect(sql).not.toContain("raw.registro");
  });

  it("comentário de bloco entre tabelas do catálogo", async () => {
    await aceita("select m.unidade from marts.mapa_unidades m /* staging.contrato_venda */ join app.centro_custo c on c.id = m.centro_custo_id");
  });

  it("limite igual ao teto", async () => {
    const sql = await aceita(`select * from marts.vso_mensal limit ${limiteLinhas}`);
    expect(sql).toContain(`LIMIT ${limiteLinhas}`);
  });

  it("limite menor e offset preservados", async () => {
    const sql = await aceita("select * from marts.vso_mensal order by competencia limit 10 offset 20");
    expect(sql).toContain("LIMIT 10");
    expect(sql).toContain("OFFSET 20");
  });

  it("CTE sobre view do catálogo", async () => {
    await aceita(
      "with ruins as (select obra, estouro_orcamento from marts.posicao_financeira_obra where estouro_orcamento > 0) select * from ruins order by estouro_orcamento desc",
    );
  });

  it("CTE que usa CTE anterior", async () => {
    await aceita("with a as (select centro_custo_id, sum(vendas) as v from marts.vso_mensal group by 1), b as (select * from a where v > 0) select * from b");
  });

  it("nome do catálogo entre aspas", async () => {
    await aceita('select * from "marts"."vso_mensal"');
  });

  it("união de duas views do catálogo", async () => {
    await aceita("select centro_custo_id from marts.vso_mensal union select centro_custo_id from marts.estoque_atual");
  });

  it("funções, janela, case, intervalo, distinct e filter", async () => {
    await aceita(`
      select distinct c.nome,
        round(sum(f.saldo_mes) over (partition by f.centro_custo_id order by f.competencia), 2) as saldo,
        case when f.saldo_acumulado < 0 then 'negativo' else 'positivo' end as sinal,
        count(*) filter (where f.saida_vencida > 0) over () as meses_com_atraso,
        to_char(f.competencia, 'MM/YYYY') as mes
      from marts.fluxo_caixa_mensal f
      join app.centro_custo c on c.id = f.centro_custo_id
      where f.competencia between date_trunc('month', current_date) and current_date + interval '12 months'
        and c.nome ilike '%aurora%'
        and coalesce(f.repasse_previsto, 0) >= 0
        and f.centro_custo_id in (select centro_custo_id from marts.posicao_financeira_obra where caixa_atual < 0)
    `);
  });

  it("subconsulta com exists sobre o catálogo", async () => {
    await aceita(
      "select obra from marts.posicao_financeira_obra p where exists (select 1 from marts.mapa_unidades m where m.centro_custo_id = p.centro_custo_id and m.situacao = 'disponivel')",
    );
  });
});

describe("validarSql recusa", () => {
  it("tabela depois de vírgula fora do catálogo", async () => {
    expect(await motivoDaRecusa("select * from marts.vso_mensal, staging.parcela_receber")).toContain("staging.parcela_receber");
  });

  it("tabela sem schema depois de vírgula, que cairia no pg_catalog", async () => {
    await motivoDaRecusa("select * from marts.vso_mensal v, pg_user");
  });

  it("vírgula escondida atrás de comentário de bloco", async () => {
    await motivoDaRecusa("select * from marts.vso_mensal /* só a view */ , raw.registro");
  });

  it("nome entre aspas com schema fora do catálogo", async () => {
    await motivoDaRecusa('select * from "staging"."parcela_receber"');
  });

  it("nome entre aspas com caixa diferente do catálogo", async () => {
    await motivoDaRecusa('select * from "Marts"."vso_mensal"');
  });

  it("identificador com escape unicode apontando para staging", async () => {
    await motivoDaRecusa('select * from U&"stag\\0069ng".parcela_receber');
  });

  it("schema e tabela separados por espaços", async () => {
    await motivoDaRecusa("select * from staging . parcela_receber");
  });

  it("nome com banco na frente", async () => {
    await motivoDaRecusa("select * from postgres.marts.vso_mensal");
  });

  it("CTE sobre raw", async () => {
    await motivoDaRecusa("with bruto as (select payload from raw.registro) select * from bruto");
  });

  it("CTE que referencia outra definida depois dela", async () => {
    await motivoDaRecusa("with a as (select * from b), b as (select 1 as n) select * from a");
  });

  it("nome de CTE usado fora do escopo onde foi definido", async () => {
    await motivoDaRecusa("select * from (with pg_user as (select 1 as n) select * from pg_user) s, pg_user");
  });

  it("CTE recursiva", async () => {
    await motivoDaRecusa("with recursive n(i) as (select 1 union all select i + 1 from n) select * from n");
  });

  it("CTE que grava", async () => {
    await motivoDaRecusa("with apagado as (delete from app.tenant returning id) select * from apagado");
  });

  it("subconsulta no select sobre tabela fora do catálogo", async () => {
    await motivoDaRecusa("select (select count(*) from staging.parcela_receber) as total from marts.vso_mensal");
  });

  it("subconsulta no where sobre tabela fora do catálogo", async () => {
    await motivoDaRecusa("select * from marts.vso_mensal where exists (select 1 from app.usuario_tenant)");
  });

  it("subconsulta no from sobre tabela fora do catálogo", async () => {
    await motivoDaRecusa("select * from (select * from app.tenant) t");
  });

  it("join lateral com tabela fora do catálogo", async () => {
    await motivoDaRecusa("select * from marts.vso_mensal v join lateral (select * from app.usuario_tenant) u on true");
  });

  it("join comum com tabela fora do catálogo", async () => {
    await motivoDaRecusa("select * from marts.vso_mensal v left join app.tenant t on true");
  });

  it("limit acima do teto", async () => {
    expect(await motivoDaRecusa("select * from marts.vso_mensal limit 99999999")).toContain("limite");
  });

  it("limit all", async () => {
    await motivoDaRecusa("select * from marts.vso_mensal limit all");
  });

  it("limit com expressão", async () => {
    await motivoDaRecusa("select * from marts.vso_mensal limit (select 1000)");
  });

  it("fetch first acima do teto", async () => {
    await motivoDaRecusa("select * from marts.vso_mensal fetch first 1000 rows only");
  });

  it("duas instruções", async () => {
    expect(await motivoDaRecusa("select 1; select 2")).toContain("única instrução");
  });

  it("select seguido de drop", async () => {
    await motivoDaRecusa("select * from marts.vso_mensal; drop table app.tenant");
  });

  it.each([
    ["insert", "insert into app.tenant (razao_social) values ('x')"],
    ["update", "update app.tenant set razao_social = 'x'"],
    ["delete", "delete from app.tenant"],
    ["drop", "drop table app.tenant"],
    ["create", "create table app.copia as select * from app.tenant"],
    ["grant", "grant all on app.tenant to anon"],
    ["truncate", "truncate app.tenant"],
    ["copy", "copy app.tenant to stdout"],
    ["set", "set role postgres"],
    ["explain", "explain select * from marts.vso_mensal"],
    ["call", "call app.qualquer()"],
    ["do", "do $$ begin perform 1; end $$"],
  ])("comando %s", async (_nome, sql) => {
    await motivoDaRecusa(sql);
  });

  it("select into, que cria tabela", async () => {
    await motivoDaRecusa("select * into app.copia from marts.vso_mensal");
  });

  it("select for update", async () => {
    await motivoDaRecusa("select * from marts.vso_mensal for update");
  });

  it("função do schema app", async () => {
    await motivoDaRecusa("select app.tenant_atual()");
  });

  it.each([
    ["pg_sleep", "select pg_sleep(30)"],
    ["pg_read_file", "select pg_catalog.pg_read_file('/etc/passwd')"],
    ["set_config", "select set_config('request.jwt.claims', '{}', true) from marts.vso_mensal"],
    ["current_setting", "select current_setting('request.jwt.claims')"],
    ["função do schema auth", "select auth.uid()"],
    ["dblink", "select dblink('host=exemplo', 'select 1')"],
    ["função entre aspas", 'select "pg_sleep"(1)'],
    ["row_to_json", "select row_to_json(v) from marts.vso_mensal v"],
    ["query_to_xml", "select query_to_xml('select * from app.tenant', true, true, '')"],
  ])("função perigosa: %s", async (_nome, sql) => {
    await motivoDaRecusa(sql);
  });

  it("função no from", async () => {
    await motivoDaRecusa("select * from generate_series(1, 1000000000)");
  });

  it("tablesample", async () => {
    await motivoDaRecusa("select * from marts.vso_mensal tablesample system (10)");
  });

  it("conversão para regclass", async () => {
    await motivoDaRecusa("select 'app.tenant'::regclass");
  });

  it("operador com schema", async () => {
    await motivoDaRecusa("select * from marts.vso_mensal where 1 operator(public.=) 1");
  });

  it("current_user", async () => {
    await motivoDaRecusa("select current_user");
  });

  it("table como atalho de select", async () => {
    await motivoDaRecusa("table staging.parcela_receber");
  });

  it("SQL que não faz parse", async () => {
    expect(await motivoDaRecusa("selec * form marts.vso_mensal")).toBe("SQL inválido");
  });

  it("texto longo demais", async () => {
    await motivoDaRecusa(`select * from marts.vso_mensal where centro_custo_id is not null ${"and 1 = 1 ".repeat(2000)}`);
  });
});

// Consultas montadas na autorrevisão para tentar quebrar o validador. As duas primeiras passavam
// na primeira versão e viraram correção: chamada de função disfarçada de coluna e limite negativo.
describe("validarSql recusa tentativas da autorrevisão", () => {
  it.each([
    ["função chamada como coluna (v.row_to_json vira row_to_json(v))", "select v.row_to_json from marts.vso_mensal v"],
    ["limite negativo", "select * from marts.vso_mensal limit -1"],
    ["table dentro de in", "select * from marts.vso_mensal where centro_custo_id in (table app.tenant)"],
    ["natural join com tabela de controle", "select * from marts.vso_mensal v natural join app.usuario_tenant"],
    ["array de subconsulta", "select array(select razao_social from app.tenant)"],
    ["offset com subconsulta", "select * from marts.vso_mensal limit 500 offset (select count(*) from app.tenant)"],
    ["lateral sobre visão do sistema sem schema", "select * from marts.vso_mensal cross join lateral (select * from pg_stat_activity) s"],
    ["nome de função com escape unicode", 'select U&"pg\\005fsleep"(5)'],
    ["CTE com nome de view do catálogo escondendo staging", "with vso_mensal as (select * from staging.contrato_venda) select * from vso_mensal"],
    ["expressão regular catastrófica", "select * from marts.vso_mensal where competencia::text ~ '(a+)+$'"],
    ["parâmetro posicional", "select c.nome from app.centro_custo c where c.nome = $1"],
    ["indireção sobre linha inteira", "select (v).competencia from marts.vso_mensal v"],
  ])("%s", async (_nome, sql) => {
    await motivoDaRecusa(sql);
  });

  it("união sem limite recebe o teto na consulta inteira", async () => {
    const sql = await aceita("select centro_custo_id from marts.vso_mensal union all select centro_custo_id from marts.vso_mensal");
    expect(sql.trimEnd().endsWith(`LIMIT ${limiteLinhas}`)).toBe(true);
  });

  it("coluna qualificada com apelido de subconsulta continua aceita", async () => {
    await aceita("select x.total from (select count(*) as total from marts.vso_mensal) x");
  });
});
