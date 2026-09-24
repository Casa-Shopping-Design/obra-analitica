import { deparse, parse } from "pgsql-parser";
import { catalogoViews } from "./catalogo-views";

// Valida pela árvore sintática do próprio Postgres (libpg-query) e devolve o SQL reescrito a partir
// da árvore aprovada, nunca o texto recebido. Tudo que não está nas listas abaixo é recusado.

export const limiteLinhas = 500;
const tamanhoMaximoSql = 10_000;
const profundidadeMaxima = 200;

export type ResultadoValidacao = { ok: true; sql: string } | { ok: false; motivo: string };

const tabelasPermitidas = new Set([...catalogoViews.map((view) => view.nome), "app.centro_custo"]);

const nosPermitidos = new Set([
  "SelectStmt",
  "ResTarget",
  "ColumnRef",
  "String",
  "Integer",
  "Float",
  "Boolean",
  "A_Star",
  "A_Const",
  "A_Expr",
  "A_ArrayExpr",
  "BoolExpr",
  "FuncCall",
  "RangeVar",
  "RangeSubselect",
  "JoinExpr",
  "SubLink",
  "CommonTableExpr",
  "SortBy",
  "TypeCast",
  "CaseExpr",
  "CaseWhen",
  "NullTest",
  "BooleanTest",
  "CoalesceExpr",
  "MinMaxExpr",
  "SQLValueFunction",
  "GroupingSet",
  "WindowDef",
  "List",
]);

// Campos que guardam uma estrutura sem o invólucro { Tipo: ... } na árvore do libpg-query.
const estruturasInternas = new Set([
  "alias",
  "join_using_alias",
  "typeName",
  "over",
  "withClause",
  "ival",
  "fval",
  "sval",
  "boolval",
  "bsval",
]);

const camposSelect = new Set([
  "distinctClause",
  "targetList",
  "fromClause",
  "whereClause",
  "groupClause",
  "groupDistinct",
  "havingClause",
  "windowClause",
  "valuesLists",
  "sortClause",
  "limitOffset",
  "limitCount",
  "limitOption",
  "withClause",
  "op",
  "all",
  "larg",
  "rarg",
]);

const funcoesPermitidas = new Set([
  "count",
  "sum",
  "avg",
  "min",
  "max",
  "bool_and",
  "bool_or",
  "string_agg",
  "percentile_cont",
  "round",
  "trunc",
  "abs",
  "ceil",
  "ceiling",
  "floor",
  "sign",
  "mod",
  "date_trunc",
  "date_part",
  "extract",
  "make_date",
  "age",
  "now",
  "to_char",
  "lower",
  "upper",
  "row_number",
  "rank",
  "dense_rank",
  "lag",
  "lead",
  "first_value",
  "last_value",
]);

const tiposPermitidos = new Set([
  "numeric",
  "int2",
  "int4",
  "int8",
  "float4",
  "float8",
  "text",
  "varchar",
  "date",
  "timestamp",
  "timestamptz",
  "interval",
  "bool",
]);

const operadoresPermitidos = new Set(["=", "<>", "!=", "<", ">", "<=", ">=", "+", "-", "*", "/", "%", "||", "~~", "!~~", "~~*", "!~~*"]);

const tiposExpressaoComOperador = new Set([
  "AEXPR_OP",
  "AEXPR_OP_ANY",
  "AEXPR_OP_ALL",
  "AEXPR_DISTINCT",
  "AEXPR_NOT_DISTINCT",
  "AEXPR_NULLIF",
  "AEXPR_IN",
  "AEXPR_LIKE",
  "AEXPR_ILIKE",
]);
const tiposExpressaoIntervalo = new Set(["AEXPR_BETWEEN", "AEXPR_NOT_BETWEEN", "AEXPR_BETWEEN_SYM", "AEXPR_NOT_BETWEEN_SYM"]);

const funcoesDeValorPermitidas = new Set([
  "SVFOP_CURRENT_DATE",
  "SVFOP_CURRENT_TIMESTAMP",
  "SVFOP_CURRENT_TIMESTAMP_N",
  "SVFOP_LOCALTIMESTAMP",
  "SVFOP_LOCALTIMESTAMP_N",
]);

type Objeto = Record<string, unknown>;

class ConsultaRecusada extends Error {}

function recusar(motivo: string): never {
  throw new ConsultaRecusada(motivo);
}

function ehObjeto(valor: unknown): valor is Objeto {
  return typeof valor === "object" && valor !== null && !Array.isArray(valor);
}

// Nó da árvore vem embrulhado como { NomeDoTipo: { ...campos } }.
function lerNo(valor: unknown): [string, Objeto] | null {
  if (!ehObjeto(valor)) return null;
  const chaves = Object.keys(valor);
  if (chaves.length !== 1 || chaves[0][0] < "A" || chaves[0][0] > "Z") return null;
  const conteudo = valor[chaves[0]];
  return ehObjeto(conteudo) ? [chaves[0], conteudo] : null;
}

function textos(lista: unknown): string[] {
  if (!Array.isArray(lista)) return [];
  return lista.map((item) => {
    const no = lerNo(item);
    if (!no || no[0] !== "String" || typeof no[1].sval !== "string") recusar("nome em formato inesperado");
    return no[1].sval as string;
  });
}

function nomeSemCatalogo(partes: string[], oQue: string): string {
  if (partes.length === 1) return partes[0];
  if (partes.length === 2 && partes[0] === "pg_catalog") return partes[1];
  return recusar(`${oQue} fora da lista permitida: ${partes.join(".")}`);
}

function inteiroConstante(valor: unknown): number | null {
  const no = lerNo(valor);
  if (!no || no[0] !== "A_Const" || no[1].isnull || !ehObjeto(no[1].ival)) return null;
  const numero = no[1].ival.ival ?? 0;
  return typeof numero === "number" ? numero : null;
}

function validarReferenciaTabela(rangeVar: Objeto, escopo: ReadonlySet<string>) {
  const relname = rangeVar.relname;
  if (typeof relname !== "string") recusar("tabela sem nome");
  if (rangeVar.catalogname !== undefined) recusar(`tabela fora do catálogo: ${rangeVar.catalogname}.${rangeVar.schemaname}.${relname}`);
  if (typeof rangeVar.schemaname === "string") {
    const nomeCompleto = `${rangeVar.schemaname}.${relname}`;
    if (!tabelasPermitidas.has(nomeCompleto)) recusar(`tabela fora do catálogo: ${nomeCompleto}`);
    return;
  }
  // Sem schema, só vale nome de CTE visível neste ponto; qualquer outro nome cairia no pg_catalog.
  if (!escopo.has(relname)) recusar(`tabela fora do catálogo: ${relname}`);
}

function validarFuncao(chamada: Objeto) {
  const nome = nomeSemCatalogo(textos(chamada.funcname), "função");
  if (!funcoesPermitidas.has(nome)) recusar(`função fora da lista permitida: ${nome}`);
}

function validarTipo(tipo: unknown) {
  if (!ehObjeto(tipo)) recusar("tipo em formato inesperado");
  if (tipo.setof || tipo.pct_type || tipo.arrayBounds !== undefined) recusar("tipo fora da lista permitida");
  const nome = nomeSemCatalogo(textos(tipo.names), "tipo");
  if (!tiposPermitidos.has(nome)) recusar(`tipo fora da lista permitida: ${nome}`);
}

function validarOperador(nomes: unknown) {
  const operador = textos(nomes);
  if (operador.length !== 1 || !operadoresPermitidos.has(operador[0])) {
    recusar(`operador fora da lista permitida: ${operador.join(".")}`);
  }
}

function validarExpressao(expressao: Objeto) {
  const tipo = String(expressao.kind);
  if (tiposExpressaoIntervalo.has(tipo)) return;
  if (!tiposExpressaoComOperador.has(tipo)) recusar(`operação fora da lista permitida: ${tipo}`);
  validarOperador(expressao.name);
}

function validarCte(cte: unknown, escopo: ReadonlySet<string>, profundidade: number): string {
  const no = lerNo(cte);
  if (!no || no[0] !== "CommonTableExpr") recusar("CTE em formato inesperado");
  const conteudo = no[1];
  if (conteudo.search_clause !== undefined || conteudo.cycle_clause !== undefined) recusar("CTE recursiva não é permitida");
  if (typeof conteudo.ctename !== "string") recusar("CTE sem nome");
  percorrer(conteudo.ctequery, escopo, profundidade + 1);
  percorrerCampo("aliascolnames", conteudo.aliascolnames, escopo, profundidade + 1);
  return conteudo.ctename;
}

function validarSelect(select: Objeto, escopo: ReadonlySet<string>, profundidade: number) {
  for (const campo of Object.keys(select)) {
    if (!camposSelect.has(campo)) recusar(`cláusula não permitida: ${campo}`);
  }

  let escopoInterno = escopo;
  const clausulaWith = select.withClause;
  if (clausulaWith !== undefined) {
    if (!ehObjeto(clausulaWith) || !Array.isArray(clausulaWith.ctes)) recusar("WITH em formato inesperado");
    if (clausulaWith.recursive) recusar("CTE recursiva não é permitida");
    // Sem recursive, cada CTE enxerga só as anteriores; nome posterior resolveria para tabela de verdade.
    for (const cte of clausulaWith.ctes) {
      const nome = validarCte(cte, escopoInterno, profundidade);
      escopoInterno = new Set([...escopoInterno, nome]);
    }
  }

  for (const [campo, valor] of Object.entries(select)) {
    if (campo === "withClause") continue;
    if (campo === "larg" || campo === "rarg") {
      if (!ehObjeto(valor)) recusar("união em formato inesperado");
      validarSelect(valor, escopoInterno, profundidade + 1);
      continue;
    }
    percorrerCampo(campo, valor, escopoInterno, profundidade + 1);
  }
}

function percorrerCampo(campo: string, valor: unknown, escopo: ReadonlySet<string>, profundidade: number) {
  if (Array.isArray(valor)) {
    for (const item of valor) percorrer(item, escopo, profundidade);
    return;
  }
  if (!ehObjeto(valor)) return;
  if (lerNo(valor)) {
    percorrer(valor, escopo, profundidade);
    return;
  }
  if (!estruturasInternas.has(campo)) recusar(`estrutura não permitida: ${campo}`);
  for (const [subcampo, subvalor] of Object.entries(valor)) percorrerCampo(subcampo, subvalor, escopo, profundidade + 1);
}

function percorrer(valor: unknown, escopo: ReadonlySet<string>, profundidade: number) {
  if (profundidade > profundidadeMaxima) recusar("consulta aninhada demais");
  if (Array.isArray(valor)) {
    for (const item of valor) percorrer(item, escopo, profundidade + 1);
    return;
  }
  // DISTINCT sem ON vem como lista com um objeto vazio.
  if (ehObjeto(valor) && Object.keys(valor).length === 0) return;
  const no = lerNo(valor);
  if (!no) recusar("trecho da consulta em formato inesperado");
  const [tipo, conteudo] = no;
  if (!nosPermitidos.has(tipo)) recusar(`construção não permitida: ${tipo}`);

  switch (tipo) {
    case "SelectStmt":
      validarSelect(conteudo, escopo, profundidade);
      return;
    case "RangeVar":
      validarReferenciaTabela(conteudo, escopo);
      break;
    case "FuncCall":
      validarFuncao(conteudo);
      break;
    case "TypeCast":
      validarTipo(conteudo.typeName);
      break;
    case "A_Expr":
      validarExpressao(conteudo);
      break;
    case "SubLink":
      if (conteudo.operName !== undefined) validarOperador(conteudo.operName);
      break;
    case "SortBy":
      if (conteudo.useOp !== undefined) recusar("ordenação com operador próprio não é permitida");
      break;
    case "SQLValueFunction":
      if (!funcoesDeValorPermitidas.has(String(conteudo.op))) recusar(`função fora da lista permitida: ${conteudo.op}`);
      break;
  }

  for (const [campo, subvalor] of Object.entries(conteudo)) {
    if (tipo === "FuncCall" && campo === "funcname") continue;
    if (tipo === "TypeCast" && campo === "typeName") {
      percorrerCampo("typmods", (subvalor as Objeto).typmods, escopo, profundidade + 1);
      continue;
    }
    if ((tipo === "A_Expr" && campo === "name") || (tipo === "SubLink" && campo === "operName")) continue;
    percorrerCampo(campo, subvalor, escopo, profundidade + 1);
  }
}

const colunasDoCatalogo = new Set([
  ...catalogoViews.flatMap((view) => view.colunas),
  "id",
  "nome",
  "tenant_id",
  "id_origem",
  "empresa_id",
]);
// Nome que o Postgres dá à coluna de saída quando a expressão não tem apelido.
const nomesDeSaidaImplicitos = new Set(["?column?", "case", "coalesce", "greatest", "least", "nullif", "exists", "array"]);

function coletarApelidosEColunas(valor: unknown, apelidos: Set<string>, colunasQualificadas: string[]) {
  if (Array.isArray(valor)) {
    for (const item of valor) coletarApelidosEColunas(item, apelidos, colunasQualificadas);
    return;
  }
  if (!ehObjeto(valor)) return;
  for (const [chave, subvalor] of Object.entries(valor)) {
    if (chave === "ColumnRef" && ehObjeto(subvalor) && Array.isArray(subvalor.fields) && subvalor.fields.length > 1) {
      const ultimo = lerNo(subvalor.fields[subvalor.fields.length - 1]);
      if (ultimo?.[0] === "String" && typeof ultimo[1].sval === "string") colunasQualificadas.push(ultimo[1].sval);
    }
    if (chave === "ResTarget" && ehObjeto(subvalor) && typeof subvalor.name === "string") apelidos.add(subvalor.name);
    if (chave === "colnames" || chave === "aliascolnames") {
      for (const nome of textos(subvalor)) apelidos.add(nome);
    }
    coletarApelidosEColunas(subvalor, apelidos, colunasQualificadas);
  }
}

// Em "v.funcao" o Postgres chama funcao(v) quando v não tem essa coluna. Só passa nome qualificado
// que seja coluna conhecida, apelido definido na própria consulta ou nome de saída de função permitida.
function validarColunasQualificadas(arvore: unknown) {
  const apelidos = new Set<string>();
  const colunasQualificadas: string[] = [];
  coletarApelidosEColunas(arvore, apelidos, colunasQualificadas);
  for (const coluna of colunasQualificadas) {
    const conhecida =
      colunasDoCatalogo.has(coluna) || apelidos.has(coluna) || funcoesPermitidas.has(coluna) || nomesDeSaidaImplicitos.has(coluna);
    if (!conhecida) recusar(`coluna desconhecida: ${coluna}`);
  }
}

function aplicarLimite(select: Objeto) {
  const opcao = select.limitOption;
  if (opcao === "LIMIT_OPTION_DEFAULT" || opcao === undefined) {
    select.limitCount = { A_Const: { ival: { ival: limiteLinhas } } };
    select.limitOption = "LIMIT_OPTION_COUNT";
    return;
  }
  if (opcao !== "LIMIT_OPTION_COUNT") recusar("limite em formato não permitido");
  const limite = inteiroConstante(select.limitCount);
  if (limite === null || limite < 0) recusar("limite precisa ser um número inteiro positivo");
  if (limite > limiteLinhas) recusar(`limite acima de ${limiteLinhas} linhas`);
  if (select.limitOffset !== undefined) {
    const deslocamento = inteiroConstante(select.limitOffset);
    if (deslocamento === null || deslocamento < 0) recusar("offset precisa ser um número inteiro positivo");
  }
}

const camposDePosicao = new Set(["location", "stmt_len", "stmt_location"]);

// Posição no texto muda com a reescrita e não entra na comparação; ordem das chaves também não.
function mesmaArvore(a: unknown, b: unknown): boolean {
  if (Array.isArray(a) || Array.isArray(b)) {
    if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length) return false;
    return a.every((item, indice) => mesmaArvore(item, b[indice]));
  }
  if (!ehObjeto(a) || !ehObjeto(b)) return a === b;
  const chavesA = Object.keys(a).filter((chave) => !camposDePosicao.has(chave));
  const chavesB = new Set(Object.keys(b).filter((chave) => !camposDePosicao.has(chave)));
  if (chavesA.length !== chavesB.size) return false;
  return chavesA.every((chave) => chavesB.has(chave) && mesmaArvore(a[chave], b[chave]));
}

// O(t) no tamanho do texto: um parse, uma caminhada na árvore, uma reescrita e um parse de conferência.
export async function validarSql(sql: string): Promise<ResultadoValidacao> {
  if (sql.length > tamanhoMaximoSql) return { ok: false, motivo: "consulta longa demais" };

  let arvore: { stmts?: { stmt?: unknown }[] };
  try {
    arvore = await parse(sql);
  } catch {
    return { ok: false, motivo: "SQL inválido" };
  }

  try {
    const instrucoes = arvore.stmts ?? [];
    if (instrucoes.length !== 1) recusar("é permitida uma única instrução");
    const no = lerNo(instrucoes[0].stmt);
    if (!no || no[0] !== "SelectStmt") recusar("só select é permitido");
    const select = no[1];

    percorrer(instrucoes[0].stmt, new Set(), 0);
    validarColunasQualificadas(instrucoes[0].stmt);
    aplicarLimite(select);

    const sqlReescrito = await deparse(arvore as Parameters<typeof deparse>[0]);
    const arvoreConferida = await parse(sqlReescrito);
    // A reescrita precisa voltar à mesma árvore; se o deparser errar, o que roda seria outra consulta.
    if (!mesmaArvore(arvoreConferida, arvore)) {
      recusar("a consulta não pôde ser reescrita com segurança");
    }
    return { ok: true, sql: sqlReescrito };
  } catch (erro) {
    if (erro instanceof ConsultaRecusada) return { ok: false, motivo: erro.message };
    return { ok: false, motivo: "a consulta não pôde ser validada" };
  }
}
