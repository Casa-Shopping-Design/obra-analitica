import { describe, expect, it } from "vitest";
import {
  aplicarRotulos,
  descreverAlteracao,
  indexarValores,
  janelaDoHorizonte,
  lerEscopo,
  lerPadroesSimulacao,
  lerPreferenciasTenant,
  limitesDoHorizonte,
  montarGrupos,
  preferenciasProduto,
  quemAlterou,
  registroNoNivel,
  somarPendenciasPorCodigo,
  resolverValor,
  textoDoFormulario,
  textoDoValor,
  validarComposicao,
  validarMapaCodigo,
  validarObservacao,
  validarRotulo,
  validarSubcategoria,
  validarValorParametro,
  type Parametro,
  type RegistroValor,
} from "../lib/configuracao";
import { lerPeriodo, tipoPeriodoDaPreferencia } from "../lib/periodo";
import { formularioPadrao, lerFormularioSimulacao, validarPremissas } from "../lib/simulacao";

function parametro(mudancas: Partial<Parametro> & Pick<Parametro, "codigo" | "tipo">): Parametro {
  return {
    grupo: mudancas.codigo.split(".")[0],
    nome: mudancas.codigo,
    descricao: "",
    opcoes: null,
    minimo: null,
    maximo: null,
    padrao: null,
    aceita_nulo: false,
    escopo: "tenant",
    ordem: 1,
    exige_validacao_financeira: false,
    ...mudancas,
  };
}

const baseFracao = parametro({
  codigo: "reconhecimento.base_fracao_vendida",
  tipo: "opcao",
  escopo: "tenant_e_obra",
  padrao: "unidades",
  exige_validacao_financeira: true,
  opcoes: [
    { valor: "unidades", rotulo: "Unidades" },
    { valor: "area_privativa", rotulo: "Área privativa" },
    { valor: "valor_tabela", rotulo: "Valor de tabela" },
  ],
});
const incluirTerreno = parametro({
  codigo: "reconhecimento.incluir_terreno",
  tipo: "booleano",
  escopo: "tenant_e_obra",
  padrao: true,
});
const horasCarga = parametro({
  codigo: "alerta.carga_desatualizada_horas",
  tipo: "inteiro",
  minimo: 1,
  maximo: 168,
  padrao: 26,
});
const cobertura = parametro({
  codigo: "reconhecimento.cobertura_minima",
  tipo: "fracao",
  minimo: 0.5,
  maximo: 1,
  padrao: 1,
  escopo: "tenant_e_obra",
});
const retencao = parametro({
  codigo: "financiamento.retencao_padrao",
  tipo: "fracao",
  minimo: 0,
  maximo: 0.5,
  padrao: null,
  aceita_nulo: true,
  escopo: "tenant_e_obra",
});
const dataHorizonte = parametro({ codigo: "comercial.meta_data_horizonte", tipo: "data", escopo: "tenant_e_obra" });
const fuso = parametro({ codigo: "negocio.fuso_horario", tipo: "fuso", padrao: "America/Sao_Paulo" });
const nota = parametro({ codigo: "negocio.nota", tipo: "texto", padrao: "" });
const fator = parametro({ codigo: "negocio.fator", tipo: "numero", minimo: -1, maximo: 2, padrao: 1 });
const fracaoEntrada = parametro({
  codigo: "simulacao.fracao_entrada",
  tipo: "fracao",
  minimo: 0,
  maximo: 1,
  padrao: 0.1,
  escopo: "tenant_e_obra",
  ordem: 2,
});
const fracaoParcelas = parametro({ ...fracaoEntrada, codigo: "simulacao.fracao_parcelas", padrao: 0.3, ordem: 3 });
const fracaoFinanciamento = parametro({
  ...fracaoEntrada,
  codigo: "simulacao.fracao_financiamento",
  padrao: 0.6,
  ordem: 4,
});
const desconto = parametro({
  codigo: "simulacao.desconto",
  tipo: "fracao",
  minimo: 0,
  maximo: 0.5,
  padrao: 0,
  escopo: "tenant_e_obra",
  ordem: 1,
});
const periodoPadrao = parametro({
  codigo: "exibicao.periodo_padrao",
  tipo: "opcao",
  padrao: "ano_ate_mes",
  opcoes: [
    { valor: "mes", rotulo: "Mês" },
    { valor: "ano_ate_mes", rotulo: "Ano até o mês" },
  ],
});
const compensa = parametro({ codigo: "caixa.consolidado_compensa_obras", tipo: "booleano", padrao: false, ordem: 9 });
const receberVencido = parametro({
  codigo: "caixa.receber_vencido",
  tipo: "opcao",
  escopo: "tenant_e_obra",
  padrao: "excluir",
  ordem: 1,
  opcoes: [
    { valor: "excluir", rotulo: "Fica fora" },
    { valor: "mes_referencia", rotulo: "Entra no mês de referência" },
  ],
});

const obraA = "4c22f713-0217-4230-bf04-8581b4bf6a7b";
const obraB = "9d4b1a0e-7c55-4e7f-8f0a-2b1c3d4e5f60";

function registro(codigo: string, centro: string | null, valor: RegistroValor["valor"]): RegistroValor {
  return {
    id: `${codigo}-${centro ?? "tenant"}`,
    centro_custo_id: centro,
    codigo,
    valor,
    observacao: null,
    autor: "11111111-1111-1111-1111-111111111111",
    atualizado_em: "2026-09-20T13:00:00Z",
  };
}

describe("validação a partir do catálogo", () => {
  it("opção aceita só valor da lista", () => {
    expect(validarValorParametro(baseFracao, "area_privativa")).toEqual({ ok: true, valor: "area_privativa" });
    expect(validarValorParametro(baseFracao, "metros")).toMatchObject({ ok: false });
    expect(validarValorParametro(baseFracao, "")).toMatchObject({ ok: false, erro: "Preencha o valor." });
  });

  it("booleano vira verdadeiro ou falso", () => {
    expect(validarValorParametro(incluirTerreno, "true")).toEqual({ ok: true, valor: true });
    expect(validarValorParametro(incluirTerreno, "false")).toEqual({ ok: true, valor: false });
    expect(validarValorParametro(incluirTerreno, "sim")).toMatchObject({ ok: false });
  });

  it("inteiro confere a faixa e recusa decimal", () => {
    expect(validarValorParametro(horasCarga, "48")).toEqual({ ok: true, valor: 48 });
    expect(validarValorParametro(horasCarga, "1")).toEqual({ ok: true, valor: 1 });
    expect(validarValorParametro(horasCarga, "168")).toEqual({ ok: true, valor: 168 });
    expect(validarValorParametro(horasCarga, "0")).toEqual({ ok: false, erro: "Informe um número inteiro de 1 a 168." });
    expect(validarValorParametro(horasCarga, "169")).toMatchObject({ ok: false });
    expect(validarValorParametro(horasCarga, "12,5")).toMatchObject({ ok: false });
    expect(validarValorParametro(horasCarga, "1e2")).toMatchObject({ ok: false });
  });

  it("fração é digitada em percentual e gravada como fração exata", () => {
    expect(validarValorParametro(cobertura, "95")).toEqual({ ok: true, valor: 0.95 });
    expect(validarValorParametro(cobertura, "97,5")).toEqual({ ok: true, valor: 0.975 });
    expect(validarValorParametro(cobertura, "50%")).toEqual({ ok: true, valor: 0.5 });
    expect(validarValorParametro(cobertura, "33,3333")).toEqual({
      ok: false,
      erro: "Informe um percentual de 50% a 100%, com até 4 casas.",
    });
    expect(validarValorParametro(cobertura, "49,99")).toMatchObject({ ok: false });
    expect(validarValorParametro(cobertura, "100,01")).toMatchObject({ ok: false });
    expect(validarValorParametro(cobertura, "95,12345")).toMatchObject({ ok: false });
    expect(validarValorParametro(retencao, "5")).toEqual({ ok: true, valor: 0.05 });
    expect(validarValorParametro(retencao, "51")).toMatchObject({ ok: false });
  });

  it("valor vazio nunca é gravado, nem quando o padrão é nulo", () => {
    const vazio = validarValorParametro(retencao, " ");
    expect(vazio.ok).toBe(false);
    expect(vazio.ok ? "" : vazio.erro).toContain("voltar ao padrão");
  });

  it("número aceita vírgula e sinal dentro da faixa", () => {
    expect(validarValorParametro(fator, "-0,25")).toEqual({ ok: true, valor: -0.25 });
    expect(validarValorParametro(fator, "2.5")).toMatchObject({ ok: false });
    expect(validarValorParametro(fator, "abc")).toMatchObject({ ok: false });
  });

  it("data precisa existir no calendário", () => {
    expect(validarValorParametro(dataHorizonte, "2028-06-30")).toEqual({ ok: true, valor: "2028-06-30" });
    expect(validarValorParametro(dataHorizonte, "2028-02-30")).toMatchObject({ ok: false });
    expect(validarValorParametro(dataHorizonte, "30/06/2028")).toMatchObject({ ok: false });
  });

  it("fuso precisa ser um fuso horário conhecido", () => {
    expect(validarValorParametro(fuso, "America/Manaus")).toEqual({ ok: true, valor: "America/Manaus" });
    expect(validarValorParametro(fuso, "America/Atlantida")).toMatchObject({ ok: false });
    expect(validarValorParametro(fuso, "'; drop table x")).toMatchObject({ ok: false });
  });

  it("texto recusa quebra de linha e excesso", () => {
    expect(validarValorParametro(nota, "Regra combinada")).toEqual({ ok: true, valor: "Regra combinada" });
    expect(validarValorParametro(nota, "linha\nnova")).toMatchObject({ ok: false });
    expect(validarValorParametro(nota, "x".repeat(501))).toMatchObject({ ok: false });
  });

  it("observação é obrigatória quando o parâmetro exige validação", () => {
    expect(validarObservacao("", true)).toMatchObject({ ok: false });
    expect(validarObservacao("Validado com o contador em 20/09/2026", true)).toEqual({
      ok: true,
      observacao: "Validado com o contador em 20/09/2026",
    });
    expect(validarObservacao("  ", false)).toEqual({ ok: true, observacao: null });
    expect(validarObservacao("x".repeat(501), false)).toMatchObject({ ok: false });
  });
});

describe("frações da simulação", () => {
  const composicao = [fracaoEntrada, fracaoParcelas, fracaoFinanciamento];

  it("aceita as três somando exatamente 100%", () => {
    expect(validarComposicao(composicao, ["10", "30", "60"])).toEqual({ ok: true, valores: [0.1, 0.3, 0.6] });
    expect(validarComposicao(composicao, ["33,3333", "33,3333", "33,3334"])).toEqual({
      ok: true,
      valores: [0.333333, 0.333333, 0.333334],
    });
  });

  it("recusa soma diferente de 100% e diz quanto somou", () => {
    const resultado = validarComposicao(composicao, ["10", "30", "50"]);
    expect(resultado).toEqual({
      ok: false,
      erros: { "simulacao.fracao_financiamento": "Entrada, parcelas e financiamento precisam somar 100%. Hoje somam 90%." },
    });
  });

  it("aponta o campo inválido antes de somar", () => {
    const resultado = validarComposicao(composicao, ["10", "", "abc"]);
    expect(resultado.ok).toBe(false);
    expect(resultado.ok ? [] : Object.keys(resultado.erros).sort()).toEqual([
      "simulacao.fracao_financiamento",
      "simulacao.fracao_parcelas",
    ]);
  });
});

describe("valor em vigor", () => {
  const registros = [
    registro("reconhecimento.base_fracao_vendida", null, "area_privativa"),
    registro("reconhecimento.base_fracao_vendida", obraA, "valor_tabela"),
    registro("alerta.carga_desatualizada_horas", obraA, 48),
  ];
  const indice = indexarValores(registros);

  it("sem nada gravado vale o padrão do produto", () => {
    expect(resolverValor(incluirTerreno, indice, null)).toEqual({ valor: true, origem: "padrao", registro: null });
    expect(resolverValor(incluirTerreno, indice, obraA)).toMatchObject({ valor: true, origem: "padrao" });
  });

  it("a construtora vence o padrão e a obra vence a construtora", () => {
    expect(resolverValor(baseFracao, indice, null)).toMatchObject({ valor: "area_privativa", origem: "tenant" });
    expect(resolverValor(baseFracao, indice, obraA)).toMatchObject({ valor: "valor_tabela", origem: "obra" });
    expect(resolverValor(baseFracao, indice, obraB)).toMatchObject({ valor: "area_privativa", origem: "tenant" });
  });

  it("parâmetro só de construtora ignora valor por obra", () => {
    expect(resolverValor(horasCarga, indice, obraA)).toMatchObject({ valor: 26, origem: "padrao" });
    expect(registroNoNivel(horasCarga, indice, obraA)).toBeNull();
  });

  it("o nível escolhido mostra só o que foi gravado nele", () => {
    expect(registroNoNivel(baseFracao, indice, obraA)?.valor).toBe("valor_tabela");
    expect(registroNoNivel(baseFracao, indice, null)?.valor).toBe("area_privativa");
    expect(registroNoNivel(baseFracao, indice, obraB)).toBeNull();
  });
});

describe("montagem dos grupos", () => {
  const catalogo = [compensa, fracaoFinanciamento, periodoPadrao, desconto, fracaoEntrada, receberVencido, fracaoParcelas, baseFracao];

  it("segue a ordem dos grupos do contrato e a ordem do catálogo", () => {
    const grupos = montarGrupos(catalogo, [], null);
    expect(grupos.map((grupo) => grupo.grupo)).toEqual(["reconhecimento", "caixa", "simulacao", "exibicao"]);
    expect(grupos[1].itens.map((item) => (item.tipo === "parametro" ? item.parametro.codigo : "composicao"))).toEqual([
      "caixa.receber_vencido",
      "caixa.consolidado_compensa_obras",
    ]);
    expect(grupos[0].titulo).toBe("Reconhecimento de receita e custo");
  });

  it("junta as três frações da simulação num item só", () => {
    const simulacao = montarGrupos(catalogo, [registro("simulacao.fracao_entrada", obraA, 0.2)], obraA)[2];
    expect(simulacao.itens.map((item) => item.tipo)).toEqual(["parametro", "composicao"]);
    const composicao = simulacao.itens[1];
    if (composicao.tipo !== "composicao") throw new Error("esperava composição");
    expect(composicao.emVigor.map((valor) => valor.valor)).toEqual([0.2, 0.3, 0.6]);
    expect(composicao.emVigor.map((valor) => valor.origem)).toEqual(["obra", "padrao", "padrao"]);
    expect(composicao.editavel).toBe(true);
  });

  it("com obra escolhida, parâmetro só de construtora fica sem formulário", () => {
    const grupos = montarGrupos(catalogo, [], obraA);
    const itens = grupos.flatMap((grupo) => grupo.itens);
    const editaveis = Object.fromEntries(
      itens.map((item) => [item.tipo === "parametro" ? item.parametro.codigo : "composicao", item.editavel]),
    );
    expect(editaveis).toMatchObject({
      "caixa.consolidado_compensa_obras": false,
      "caixa.receber_vencido": true,
      "exibicao.periodo_padrao": false,
      composicao: true,
    });
  });

  it("grupo novo no catálogo entra no fim sem código novo", () => {
    const novo = parametro({ codigo: "obra.prazo", tipo: "inteiro", padrao: 12 });
    const grupos = montarGrupos([novo, compensa], [], null);
    expect(grupos.map((grupo) => grupo.titulo)).toEqual(["Fluxo de caixa projetado", "Obra"]);
  });
});

describe("texto do valor", () => {
  it("mostra opção pelo rótulo, fração em percentual e data brasileira", () => {
    expect(textoDoValor(baseFracao, "area_privativa")).toBe("Área privativa");
    expect(textoDoValor(cobertura, 0.975)).toBe("97,5%");
    expect(textoDoValor(incluirTerreno, false)).toBe("Não");
    expect(textoDoValor(dataHorizonte, "2028-06-30")).toBe("30/06/2028");
    expect(textoDoValor(retencao, null)).toBe("Sem valor");
  });

  it("devolve ao formulário o que a pessoa digitaria", () => {
    expect(textoDoFormulario(cobertura, 0.975)).toBe("97,5");
    expect(textoDoFormulario(incluirTerreno, true)).toBe("true");
    expect(textoDoFormulario(retencao, null)).toBe("");
  });
});

describe("escopo, códigos, rótulos e subcategorias", () => {
  const ler = (valores: Record<string, string>) => (nome: string) => valores[nome] ?? "";

  it("escopo é construtora ou uma obra em formato de UUID", () => {
    expect(lerEscopo("construtora")).toEqual({ ok: true, centroId: null });
    expect(lerEscopo(obraA.toUpperCase())).toEqual({ ok: true, centroId: obraA });
    expect(lerEscopo("1 or 1=1")).toEqual({ ok: false });
  });

  const aceitos = [
    { dominio: "condicao_pagamento", valor: "entrada_direta", rotulo: "Pago direto", ordem: 10, valor_sem_mapa: true },
    { dominio: "condicao_pagamento", valor: "financiamento_comprador", rotulo: "Financiamento", ordem: 20, valor_sem_mapa: false },
    { dominio: "situacao_unidade", valor: "vendida", rotulo: "Vendida", ordem: 40, valor_sem_mapa: false },
  ];

  it("mapa de códigos aceita só domínio e valor do catálogo de valores", () => {
    expect(
      validarMapaCodigo(ler({ dominio: "condicao_pagamento", codigo_origem: "FI", valor: "financiamento_comprador" }), aceitos),
    ).toEqual({
      ok: true,
      dados: { dominio: "condicao_pagamento", codigo_origem: "FI", valor: "financiamento_comprador", rotulo: null, observacao: null },
    });
    const errado = validarMapaCodigo(ler({ dominio: "situacao_unidade", codigo_origem: "X\tY", valor: "ativo" }), aceitos);
    expect(errado.ok ? [] : Object.keys(errado.erros).sort()).toEqual(["codigo_origem", "valor"]);
    expect(validarMapaCodigo(ler({ dominio: "situacao_unidade", codigo_origem: "V 2", valor: "vendida" }), aceitos).ok).toBe(
      true,
    );
    expect(validarMapaCodigo(ler({ dominio: "toString", codigo_origem: "A", valor: "x" }), aceitos).ok).toBe(false);
    expect(validarMapaCodigo(ler({ dominio: "situacao_unidade", codigo_origem: "x".repeat(41), valor: "vendida" }), aceitos).ok).toBe(
      false,
    );
  });

  it("pendência do mesmo código em várias obras vira uma linha", () => {
    const somadas = somarPendenciasPorCodigo([
      { dominio: "condicao_pagamento", codigo_origem: "XX", quantidade_registros: 3, valor_envolvido: 100 },
      { dominio: "condicao_pagamento", codigo_origem: "XX", quantidade_registros: 2, valor_envolvido: 50.5 },
      { dominio: "condicao_pagamento", codigo_origem: "YY", quantidade_registros: 1, valor_envolvido: 900 },
      { dominio: "situacao_unidade", codigo_origem: null, quantidade_registros: 4, valor_envolvido: null },
    ]);
    expect(somadas).toEqual([
      { dominio: "condicao_pagamento", codigo_origem: "YY", quantidade_registros: 1, valor_envolvido: 900, obras: 1 },
      { dominio: "condicao_pagamento", codigo_origem: "XX", quantidade_registros: 5, valor_envolvido: 150.5, obras: 2 },
      { dominio: "situacao_unidade", codigo_origem: null, quantidade_registros: 4, valor_envolvido: null, obras: 1 },
    ]);
  });

  it("rótulo vazio volta ao nome do produto e linha precisa existir", () => {
    expect(validarRotulo(ler({ contexto: "linha_dre", chave: "resultado_gerencial", rotulo: "" }))).toEqual({
      ok: true,
      dados: { contexto: "linha_dre", chave: "resultado_gerencial", rotulo: null },
    });
    expect(validarRotulo(ler({ contexto: "linha_dre", chave: "lucro", rotulo: "Lucro" })).ok).toBe(false);
    expect(validarRotulo(ler({ contexto: "indicador", chave: "vgv", rotulo: "VGV" })).ok).toBe(false);
  });

  it("rótulo troca só o nome exibido", () => {
    const linhas = [
      { codigo: "resultado_gerencial", nome: "Resultado gerencial do período", ordem: 90 },
      { codigo: "receita_bruta", nome: "Receita bruta reconhecida", ordem: 10 },
    ];
    const trocadas = aplicarRotulos(
      linhas,
      (linha) => linha.codigo,
      [
        { contexto: "linha_dre", chave: "resultado_gerencial", rotulo: "Resultado da operação" },
        { contexto: "categoria", chave: "receita_bruta", rotulo: "Não se aplica aqui" },
      ],
      "linha_dre",
    );
    expect(trocadas).toEqual([
      { codigo: "resultado_gerencial", nome: "Resultado da operação", ordem: 90 },
      { codigo: "receita_bruta", nome: "Receita bruta reconhecida", ordem: 10 },
    ]);
  });

  it("subcategoria exige categoria, código e nome", () => {
    expect(
      validarSubcategoria(ler({ categoria_codigo: "materiais", codigo: "materiais.eletrica", nome: "Elétrica", ativa: "sim" })),
    ).toEqual({
      ok: true,
      dados: { id: null, categoria_codigo: "materiais", codigo: "materiais.eletrica", nome: "Elétrica", ativa: true },
    });
    const errada = validarSubcategoria(ler({ categoria_codigo: "", codigo: "Com Espaço", nome: "", ativa: "talvez" }));
    expect(errada.ok ? [] : Object.keys(errada.erros).sort()).toEqual(["ativa", "categoria_codigo", "codigo", "nome"]);
  });
});

describe("histórico", () => {
  const catalogo = new Map([[baseFracao.codigo, baseFracao]]);
  const nomes = new Map([[obraA, "Residencial Aurora"]]);
  const usuario = "11111111-1111-1111-1111-111111111111";

  it("descreve a troca de valor com o nível e sem mostrar id", () => {
    const frase = descreverAlteracao(
      {
        id: 1,
        tabela: "app.parametro_valor",
        registro_id: "x",
        operacao: "update",
        antes: { codigo: baseFracao.codigo, centro_custo_id: obraA, valor: "unidades" },
        depois: { codigo: baseFracao.codigo, centro_custo_id: obraA, valor: "valor_tabela", observacao: "Com o contador" },
        autor: usuario,
        alterado_em: "2026-09-20T13:00:00Z",
      },
      catalogo,
      nomes,
    );
    expect(frase).toEqual({
      titulo: `${baseFracao.nome}, obra Residencial Aurora`,
      detalhe: "De Unidades para Valor de tabela. Observação: Com o contador",
    });
  });

  it("exclusão volta ao nível de cima", () => {
    const frase = descreverAlteracao(
      {
        id: 2,
        tabela: "app.parametro_valor",
        registro_id: "x",
        operacao: "delete",
        antes: { codigo: baseFracao.codigo, centro_custo_id: null, valor: "area_privativa" },
        depois: null,
        autor: usuario,
        alterado_em: "2026-09-20T13:00:00Z",
      },
      catalogo,
      nomes,
    );
    expect(frase.titulo).toBe(`${baseFracao.nome}, construtora`);
    expect(frase.detalhe).toBe("Voltou ao nível de cima (era Área privativa).");
  });

  it("autor aparece como você, outro usuário ou carga", () => {
    expect(quemAlterou(usuario, usuario)).toBe("você");
    expect(quemAlterou("22222222-2222-2222-2222-222222222222", usuario)).toBe("outro usuário da construtora");
    expect(quemAlterou(null, usuario)).toBe("carga automática");
  });
});

describe("preferências de exibição", () => {
  it("período padrão abre o filtro do demonstrativo", () => {
    expect(tipoPeriodoDaPreferencia("ano_ate_mes", "mes")).toBe("ano");
    expect(tipoPeriodoDaPreferencia("ultimos_12", "ano")).toBe("doze_meses");
    expect(tipoPeriodoDaPreferencia("semestre", "ano")).toBe("ano");
    expect(tipoPeriodoDaPreferencia("toString", "ano")).toBe("ano");
    const preferencias = lerPreferenciasTenant({ exibicao__periodo_padrao: "mes" });
    expect(lerPeriodo({}, "2026-09-26", preferencias.periodoPadrao)).toMatchObject({
      tipo: "mes",
      inicio: "2026-09-01",
      fim: "2026-09-01",
    });
    expect(lerPeriodo({ periodo: "trimestre" }, "2026-09-26", preferencias.periodoPadrao).tipo).toBe("trimestre");
  });

  it("sem leitura do banco vale o comportamento anterior", () => {
    expect(lerPreferenciasTenant(null)).toEqual(preferenciasProduto);
    expect(lerPreferenciasTenant({ exibicao__meses_grafico: 500, caixa__consolidado_compensa_obras: "sim" })).toEqual(
      preferenciasProduto,
    );
    expect(
      lerPreferenciasTenant({
        exibicao__periodo_padrao: "trimestre",
        exibicao__meses_grafico: 60,
        caixa__consolidado_compensa_obras: true,
      }),
    ).toEqual({ periodoPadrao: "trimestre", mesesGrafico: 60, consolidadoCompensaObras: true });
  });

  it("36 meses repetem a janela anterior de 12 antes e 24 depois", () => {
    expect(janelaDoHorizonte(36)).toEqual({ antes: 12, depois: 24, rotulo: "12 meses antes e 24 depois" });
    expect(limitesDoHorizonte(36, "2026-09-26")).toEqual({ inicio: "2025-09-01", fim: "2028-09-01" });
    expect(janelaDoHorizonte(12)).toMatchObject({ antes: 4, depois: 8 });
    expect(limitesDoHorizonte(120, "2026-12-15")).toEqual({ inicio: "2023-08-01", fim: "2033-08-01" });
  });
});

describe("formulário de simulação pré-preenchido", () => {
  const referencia = "2026-09-26";
  const linhaObra = {
    simulacao__desconto: 0.05,
    simulacao__fracao_entrada: 0.2,
    simulacao__fracao_parcelas: 0.125,
    simulacao__fracao_financiamento: 0.675,
    simulacao__quantidade_parcelas: 36,
    simulacao__meses_ate_liberacao: 6,
  };

  it("usa os padrões da obra no lugar dos números fixos", () => {
    const formulario = formularioPadrao(referencia, lerPadroesSimulacao(linhaObra));
    expect(formulario).toMatchObject({
      desconto: "5",
      entrada: "20",
      parcelas: "12,5",
      financiamento: "67,5",
      quantidade_parcelas: "36",
      meses_liberacao: "6",
    });
    const validacao = validarPremissas(formulario, { dataReferencia: referencia, estoque: 100 });
    expect(validacao.ok && validacao.premissas.composicao).toEqual({
      entrada: 0.2,
      parcelas_mensais: 0.125,
      quantidade_parcelas_mensais: 36,
      financiamento: 0.675,
    });
    expect(validacao.ok && validacao.premissas.desconto_tabela).toBe(0.05);
  });

  it("sem padrão da obra mantém os números anteriores", () => {
    expect(formularioPadrao(referencia, null)).toEqual(formularioPadrao(referencia));
    expect(formularioPadrao(referencia, lerPadroesSimulacao(null))).toMatchObject({
      entrada: "10",
      parcelas: "30",
      financiamento: "60",
      quantidade_parcelas: "24",
      meses_liberacao: "4",
    });
  });

  it("valor da URL continua valendo sobre o padrão da obra", () => {
    const lido = lerFormularioSimulacao({ entrada: "15" }, referencia, lerPadroesSimulacao(linhaObra));
    expect(lido.entrada).toBe("15");
    expect(lido.parcelas).toBe("12,5");
  });

  it("coluna ausente ou inválida cai no número fixo daquele campo", () => {
    const padroes = lerPadroesSimulacao({ simulacao__fracao_entrada: "abc", simulacao__quantidade_parcelas: 2.5 });
    expect(formularioPadrao(referencia, padroes)).toMatchObject({ entrada: "10", quantidade_parcelas: "24" });
  });
});
