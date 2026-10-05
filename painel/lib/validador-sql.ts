import {
  parse,
  toSql,
  type DataTypeDef,
  type Expr,
  type From,
  type OrderByStatement,
  type SelectFromStatement,
  type SelectStatement,
  type Statement,
} from "pgsql-ast-parser";
import { catalogoDoPerfil } from "./catalogo-views";

export type ResultadoValidacao = { ok: true; sql: string } | { ok: false; motivo: string };

export const limiteLinhasConsulta = 500;

// As relações vêm do catálogo do perfil de quem pergunta (correção C4 do plano APO): o gerente não chega à DRE
// nem pelo SQL gerado. Sem perfil lido vale o catálogo sem as views restritas. app.centro_custo entra para a
// consulta trocar o id da obra pelo nome. Um conjunto por perfil, montado uma vez.
const relacoesPorPerfil = new Map<string | null, ReadonlySet<string>>();

function relacoesPermitidasDoPerfil(perfil: string | null): ReadonlySet<string> {
  const guardado = relacoesPorPerfil.get(perfil);
  if (guardado) return guardado;
  const relacoes = new Set([...catalogoDoPerfil(perfil).map((view) => view.nome), "app.centro_custo"]);
  relacoesPorPerfil.set(perfil, relacoes);
  return relacoes;
}

// As CTEs mudam a cada with; as relações do catálogo valem para a instrução inteira.
type Escopo = { relacoes: ReadonlySet<string>; ctes: ReadonlySet<string> };

// Lista fechada: função fora dela pode ler ou mudar estado da sessão (set_config troca os claims que o RLS lê,
// query_to_xml roda SQL em texto), então só entra o que agrega, calcula ou formata.
const funcoesPermitidas = new Set([
  "count", "sum", "avg", "min", "max", "stddev", "variance", "percentile_cont", "percentile_disc",
  "bool_and", "bool_or", "string_agg", "array_agg",
  "row_number", "rank", "dense_rank", "percent_rank", "cume_dist", "ntile", "lag", "lead", "first_value", "last_value",
  "coalesce", "nullif", "greatest", "least",
  "round", "trunc", "abs", "ceil", "ceiling", "floor", "sign", "mod", "div", "power", "sqrt",
  "date_trunc", "date_part", "make_date", "age", "now", "to_char", "to_date", "to_number",
  "lower", "upper", "initcap", "btrim", "ltrim", "rtrim", "length", "concat", "concat_ws", "substr",
  "left", "right", "replace", "lpad", "rpad", "split_part",
  "exists",
]);

const tiposPermitidos = new Set([
  "text", "varchar", "character varying", "char", "character",
  "numeric", "decimal", "int", "integer", "int2", "int4", "int8", "smallint", "bigint",
  "real", "float", "float4", "float8", "double precision",
  "date", "timestamp", "timestamptz", "timestamp with time zone", "timestamp without time zone", "interval",
  "boolean", "bool",
]);

const palavrasPermitidas = new Set(["current_date", "current_timestamp", "current_time", "localtimestamp", "localtime"]);

class ConsultaRecusada extends Error {}

function recusar(motivo: string): never {
  throw new ConsultaRecusada(motivo);
}

function verificarTipo(tipo: DataTypeDef): void {
  if (tipo.kind === "array") return verificarTipo(tipo.arrayOf);
  if (tipo.schema || !tiposPermitidos.has(tipo.name.toLowerCase())) recusar(`tipo nao permitido: ${tipo.name}`);
}

function verificarOrdenacao(ordens: OrderByStatement[] | null | undefined, escopo: Escopo): void {
  ordens?.forEach((ordem) => verificarExpressao(ordem.by, escopo));
}

function verificarExpressao(expressao: Expr | null | undefined, escopo: Escopo): void {
  if (!expressao) return;
  switch (expressao.type) {
    case "ref":
    case "integer":
    case "numeric":
    case "string":
    case "boolean":
    case "null":
      return;
    case "keyword":
      if (!palavrasPermitidas.has(expressao.keyword)) recusar(`palavra nao permitida: ${expressao.keyword}`);
      return;
    case "constant":
      return verificarTipo(expressao.dataType);
    case "cast":
      verificarTipo(expressao.to);
      return verificarExpressao(expressao.operand, escopo);
    case "binary":
      if (expressao.opSchema) recusar("operador qualificado por schema");
      verificarExpressao(expressao.left, escopo);
      return verificarExpressao(expressao.right, escopo);
    case "unary":
      if (expressao.opSchema) recusar("operador qualificado por schema");
      return verificarExpressao(expressao.operand, escopo);
    case "ternary":
      [expressao.value, expressao.lo, expressao.hi].forEach((parte) => verificarExpressao(parte, escopo));
      return;
    case "member":
      return verificarExpressao(expressao.operand, escopo);
    case "arrayIndex":
      verificarExpressao(expressao.array, escopo);
      return verificarExpressao(expressao.index, escopo);
    case "list":
    case "array":
      expressao.expressions.forEach((item) => verificarExpressao(item, escopo));
      return;
    case "extract":
      return verificarExpressao(expressao.from, escopo);
    case "substring":
      [expressao.value, expressao.from, expressao.for].forEach((parte) => verificarExpressao(parte, escopo));
      return;
    case "overlay":
      [expressao.value, expressao.placing, expressao.from, expressao.for].forEach((parte) => verificarExpressao(parte, escopo));
      return;
    case "case":
      verificarExpressao(expressao.value, escopo);
      expressao.whens.forEach(({ when, value }) => {
        verificarExpressao(when, escopo);
        verificarExpressao(value, escopo);
      });
      return verificarExpressao(expressao.else, escopo);
    case "call": {
      const { function: funcao } = expressao;
      if (funcao.schema || !funcoesPermitidas.has(funcao.name.toLowerCase())) recusar(`funcao nao permitida: ${funcao.name}`);
      expressao.args.forEach((argumento) => verificarExpressao(argumento, escopo));
      verificarExpressao(expressao.filter, escopo);
      verificarOrdenacao(expressao.orderBy, escopo);
      if (expressao.withinGroup) verificarExpressao(expressao.withinGroup.by, escopo);
      expressao.over?.partitionBy?.forEach((parte) => verificarExpressao(parte, escopo));
      return verificarOrdenacao(expressao.over?.orderBy, escopo);
    }
    case "array select":
      return verificarInstrucao(expressao.select, escopo);
    case "select":
    case "union":
    case "union all":
    case "values":
    case "with":
      return verificarInstrucao(expressao, escopo);
    default:
      recusar(`construcao nao permitida: ${expressao.type}`);
  }
}

function verificarOrigem(origem: From, escopo: Escopo): void {
  if (origem.type === "table") {
    const { schema, name } = origem.name;
    if (schema ? !escopo.relacoes.has(`${schema}.${name}`) : !escopo.ctes.has(name)) {
      recusar(`relacao fora do catalogo: ${schema ? `${schema}.` : ""}${name}`);
    }
  } else if (origem.type === "statement") {
    verificarInstrucao(origem.statement, escopo);
  } else {
    recusar("funcao no from");
  }
  verificarExpressao(origem.join?.on, escopo);
}

function verificarSelect(select: SelectFromStatement, escopo: Escopo): void {
  if (select.for || select.skip) recusar("select com trava de linha");
  select.columns?.forEach((coluna) => verificarExpressao(coluna.expr, escopo));
  select.from?.forEach((origem) => verificarOrigem(origem, escopo));
  verificarExpressao(select.where, escopo);
  select.groupBy?.forEach((grupo) => verificarExpressao(grupo, escopo));
  verificarExpressao(select.having, escopo);
  verificarOrdenacao(select.orderBy, escopo);
  if (Array.isArray(select.distinct)) select.distinct.forEach((item) => verificarExpressao(item, escopo));
  verificarExpressao(select.limit?.limit, escopo);
  verificarExpressao(select.limit?.offset, escopo);
}

// Cada CTE enxerga as anteriores; nome de CTE só vale sem schema, então "staging.x" nunca vira CTE.
function verificarInstrucao(instrucao: Statement, escopo: Escopo): void {
  switch (instrucao.type) {
    case "select":
      return verificarSelect(instrucao, escopo);
    case "union":
    case "union all":
      verificarInstrucao(instrucao.left, escopo);
      return verificarInstrucao(instrucao.right, escopo);
    case "values":
      instrucao.values.forEach((linha) => linha.forEach((valor) => verificarExpressao(valor, escopo)));
      return;
    case "with": {
      const visiveis = new Set(escopo.ctes);
      const interno: Escopo = { relacoes: escopo.relacoes, ctes: visiveis };
      instrucao.bind.forEach(({ alias, statement }) => {
        verificarInstrucao(statement, interno);
        visiveis.add(alias.name);
      });
      return verificarInstrucao(instrucao.in, interno);
    }
    default:
      recusar(`instrucao nao permitida: ${instrucao.type}`);
  }
}

function limiteLiteral(expressao: Expr | null | undefined, nome: string): number | undefined {
  if (!expressao) return undefined;
  if (expressao.type !== "integer") recusar(`${nome} precisa ser um numero inteiro`);
  return expressao.value;
}

// Limite vale para a consulta de fora; union e values ficam dentro de um select para receber o limite.
function aplicarLimite(instrucao: SelectStatement): SelectStatement {
  if (instrucao.type === "with") return { ...instrucao, in: aplicarLimite(instrucao.in as SelectStatement) };
  if (instrucao.type !== "select") {
    return {
      type: "select",
      columns: [{ expr: { type: "ref", name: "*" } }],
      from: [{ type: "statement", statement: instrucao, alias: "consulta" }],
      limit: { limit: { type: "integer", value: limiteLinhasConsulta } },
    };
  }
  const limite = limiteLiteral(instrucao.limit?.limit, "limit");
  limiteLiteral(instrucao.limit?.offset, "offset");
  if (limite !== undefined && limite > limiteLinhasConsulta) recusar(`limit acima de ${limiteLinhasConsulta}`);
  if (limite !== undefined) return instrucao;
  return { ...instrucao, limit: { ...instrucao.limit, limit: { type: "integer", value: limiteLinhasConsulta } } };
}

function analisar(sql: string): Statement {
  let instrucoes: Statement[];
  try {
    instrucoes = parse(sql);
  } catch {
    recusar("sql que o parser nao reconhece");
  }
  if (instrucoes.length !== 1) recusar("precisa ser exatamente uma instrucao");
  return instrucoes[0];
}

function serializar(sql: string, relacoes: ReadonlySet<string>): string {
  const instrucao = analisar(sql);
  verificarInstrucao(instrucao, { relacoes, ctes: new Set() });
  return toSql.statement(aplicarLimite(instrucao as SelectStatement));
}

// O(t) no tamanho do texto: um parse e uma caminhada na árvore, repetidos uma vez sobre o texto gerado.
// A segunda volta prova que o SQL reescrito é lido do mesmo jeito; o banco executa só esse texto.
// perfil é o valor cru de app.perfil_atual (ou do claim), nunca o nome de exibição.
export function validarSql(sql: string, perfil: string | null = null): ResultadoValidacao {
  try {
    const relacoes = relacoesPermitidasDoPerfil(perfil);
    const reescrito = serializar(sql, relacoes);
    if (serializar(reescrito, relacoes) !== reescrito) recusar("sql reescrito nao e estavel");
    return { ok: true, sql: reescrito };
  } catch (erro) {
    if (erro instanceof ConsultaRecusada) return { ok: false, motivo: erro.message };
    return { ok: false, motivo: "falha inesperada ao validar" };
  }
}
