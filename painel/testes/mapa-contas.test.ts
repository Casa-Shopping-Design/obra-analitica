import { describe, expect, it } from "vitest";
import {
  enderecoMapa,
  grupoContaDe,
  lerContaMapa,
  lerFiltroMapa,
  lerFormularioMapa,
  lerLinhaCatalogo,
  maximoItensMapa,
  mensagemErroMapa,
  mensagemRecusaMapa,
  mudancasMapa,
  opcoesPorGrupo,
  resultadoErroMapa,
  validarItensMapa,
} from "../lib/mapa-contas";
import { mensagensMapa } from "../lib/mensagens-empresa";

function formulario(itens: string | null): FormData {
  const dados = new FormData();
  if (itens !== null) dados.set("itens", itens);
  return dados;
}

describe("validarItensMapa", () => {
  it("aceita conta com máscara e linha do catálogo, e linha nula para desligar", () => {
    expect(
      validarItensMapa([
        { conta: "1.1.1.02.0001", linha: "bancos" },
        { conta: "2.1.3", linha: null },
      ]),
    ).toEqual({
      ok: true,
      itens: [
        { conta: "1.1.1.02.0001", linha: "bancos" },
        { conta: "2.1.3", linha: null },
      ],
    });
  });

  it.each([
    ["lista vazia", [], "vazio"],
    ["objeto no lugar da lista", { conta: "1", linha: "bancos" }, "vazio"],
    ["conta com letra", [{ conta: "1.1.a", linha: "bancos" }], "formato"],
    ["conta terminando em ponto", [{ conta: "1.1.", linha: "bancos" }], "formato"],
    ["conta numérica", [{ conta: 11101, linha: "bancos" }], "formato"],
    ["linha com maiúscula", [{ conta: "1.1", linha: "Bancos" }], "formato"],
    ["linha com aspas", [{ conta: "1.1", linha: "bancos'; drop" }], "formato"],
    ["linha vazia", [{ conta: "1.1", linha: "" }], "formato"],
    ["linha ausente", [{ conta: "1.1" }], "formato"],
    ["campo a mais", [{ conta: "1.1", linha: "bancos", tenant_id: "x" }], "formato"],
    ["item nulo", [null], "formato"],
    ["conta repetida", [{ conta: "1.1", linha: "bancos" }, { conta: "1.1", linha: "caixa" }], "repetida"],
  ])("recusa %s", (_caso, entrada, motivo) => {
    expect(validarItensMapa(entrada)).toEqual({ ok: false, motivo });
  });

  it("recusa mais de 500 itens antes de olhar cada um", () => {
    const itens = Array.from({ length: maximoItensMapa + 1 }, (_, indice) => ({ conta: `1.${indice}`, linha: "bancos" }));
    expect(validarItensMapa(itens)).toEqual({ ok: false, motivo: "limite" });
    expect(validarItensMapa(itens.slice(0, maximoItensMapa)).ok).toBe(true);
  });
});

describe("lerFormularioMapa", () => {
  it("lê o campo itens em JSON", () => {
    expect(lerFormularioMapa(formulario('[{"conta":"1.1.1","linha":"caixa"}]'))).toEqual({
      ok: true,
      itens: [{ conta: "1.1.1", linha: "caixa" }],
    });
  });

  it("sem campo, campo vazio ou JSON quebrado é recusado", () => {
    expect(lerFormularioMapa(formulario(null))).toEqual({ ok: false, motivo: "vazio" });
    expect(lerFormularioMapa(formulario("  "))).toEqual({ ok: false, motivo: "vazio" });
    expect(lerFormularioMapa(formulario("[{conta:"))).toEqual({ ok: false, motivo: "formato" });
  });

  it("texto gigante é recusado sem passar pelo parser", () => {
    expect(lerFormularioMapa(formulario("[" + " ".repeat(maximoItensMapa * 120) + "]"))).toEqual({ ok: false, motivo: "limite" });
  });
});

describe("mensagens do mapa", () => {
  it("traduz o código do banco sem repassar o texto", () => {
    expect(mensagemErroMapa("42501")).toBe(mensagensMapa.semPermissao);
    expect(mensagemErroMapa("22023")).toBe(mensagensMapa.foraDoCatalogo);
    expect(mensagemErroMapa("57014")).toBe(mensagensMapa.gravacaoIndisponivel);
    expect(mensagemErroMapa(undefined)).toBe(mensagensMapa.gravacaoIndisponivel);
    expect(resultadoErroMapa("42501")).toBe("negado");
    expect(resultadoErroMapa("22023")).toBe("recusada");
    expect(resultadoErroMapa("XX000")).toBe("erro");
  });

  it("diz o que fazer em cada recusa do formulário", () => {
    expect(mensagemRecusaMapa("vazio")).toBe(mensagensMapa.semMudancas);
    expect(mensagemRecusaMapa("limite")).toBe(mensagensMapa.limite);
    expect(mensagemRecusaMapa("formato")).toBe(mensagensMapa.formato);
    expect(mensagemRecusaMapa("repetida")).toBe(mensagensMapa.formato);
  });

  it("nenhuma mensagem cita tabela, função ou SQL", () => {
    for (const texto of Object.values(mensagensMapa)) {
      expect(texto).not.toMatch(/app\.|marts\.|gravar_mapa|select|mapa_conta_linha/i);
    }
  });
});

describe("opções de linha por grupo", () => {
  const catalogo = [
    { linha: "bancos", rotulo: "Bancos c/movimento", grupo_conta: "1", demonstrativo: "fontes_usos" },
    { linha: "estoque_imoveis_construcao", rotulo: "Estoque - Incorporação Imov. Em Construção", grupo_conta: "1", demonstrativo: "fontes_usos" },
    { linha: "estoque_imoveis_construcao", rotulo: "Estoque - Incorporação Imov. Em Construção", grupo_conta: "1", demonstrativo: "custo_incorrido" },
    { linha: "fornecedores", rotulo: "Fornecedores e Credores Diversos", grupo_conta: "2", demonstrativo: "fontes_usos" },
    { linha: "apuracao_resultado", rotulo: "Lucro do Exercício", grupo_conta: "6", demonstrativo: "fora" },
  ].map(lerLinhaCatalogo);

  it("agrupa pelo primeiro dígito e mostra uma vez a linha que está em dois demonstrativos", () => {
    const grupos = opcoesPorGrupo(catalogo);
    expect(grupos.get("1")).toEqual([
      { linha: "bancos", rotulo: "Bancos c/movimento (Fontes e Usos)" },
      { linha: "estoque_imoveis_construcao", rotulo: "Estoque - Incorporação Imov. Em Construção (Fontes e Usos, Custo incorrido)" },
    ]);
    expect(grupos.get("2")?.map((opcao) => opcao.linha)).toEqual(["fornecedores"]);
    expect(grupos.get("6")?.[0].rotulo).toBe("Lucro do Exercício (Fora dos relatórios)");
    expect(grupos.get("3")).toBeUndefined();
  });

  it("acha o grupo da conta pelo primeiro dígito", () => {
    expect(grupoContaDe("1.1.1.02.0001")).toBe("1");
    expect(grupoContaDe("51101")).toBe("5");
    expect(grupoContaDe("x.1")).toBe("");
  });
});

describe("mudancasMapa", () => {
  const originais = new Map<string, string | null>([
    ["1.1.1", "bancos"],
    ["1.1.2", null],
    ["2.1.1", "fornecedores"],
  ]);

  it("manda só o que mudou, com vazio virando nulo", () => {
    const escolhas = new Map([
      ["1.1.1", "bancos"],
      ["1.1.2", "caixa"],
      ["2.1.1", ""],
    ]);
    expect(mudancasMapa(originais, escolhas)).toEqual([
      { conta: "1.1.2", linha: "caixa" },
      { conta: "2.1.1", linha: null },
    ]);
  });

  it("ignora conta que saiu da página depois de gravar", () => {
    expect(mudancasMapa(originais, new Map([["9.9.9", "caixa"], ["1.1.2", ""]]))).toEqual([]);
  });
});

describe("filtro do mapa", () => {
  it("lê o filtro da URL e ignora grupo desconhecido e página inválida", () => {
    expect(lerFiltroMapa({ sem_mapa: "1", grupo: "ativo", pagina: "3" })).toEqual({ semMapa: true, grupo: "ativo", pagina: 3 });
    expect(lerFiltroMapa({ grupo: "1' or '1", pagina: "-2" })).toEqual({ semMapa: false, grupo: null, pagina: 1 });
  });

  it("monta o endereço sem os valores padrão", () => {
    expect(enderecoMapa({ semMapa: false, grupo: null, pagina: 1 })).toBe("/empresas/mapa-contas");
    expect(enderecoMapa({ semMapa: true, grupo: "passivo", pagina: 1 }, { pagina: 2 })).toBe(
      "/empresas/mapa-contas?sem_mapa=1&grupo=passivo&pagina=2",
    );
  });

  it("lê a conta do mapa com linha própria e herdada", () => {
    expect(
      lerContaMapa({
        conta: "1.1.1.02.0001", conta_reduzida: 12, nome: "Banco conta movimento", grupo: "ativo", analitica: true,
        linha: null, linha_efetiva: "bancos", demonstrativos: "fontes_usos",
      }),
    ).toMatchObject({ linha: null, linhaEfetiva: "bancos", analitica: true });
  });
});
