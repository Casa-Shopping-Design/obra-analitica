// Regras da tela de configurações e das preferências lidas pelas outras telas: tipos do catálogo
// (app.parametro), validação a partir dele, valor em vigor (obra, construtora, produto) e montagem dos grupos.
// Tudo puro; consulta e gravação ficam em lib/consultas/configuracao.ts e nas Server Actions.
import { lerData, mesDaData, somarMeses, tipoPeriodoDaPreferencia, type TipoPeriodo } from "./periodo";

export type TipoParametro = "opcao" | "booleano" | "numero" | "inteiro" | "fracao" | "texto" | "data" | "fuso";
export type EscopoParametro = "tenant" | "tenant_e_obra";
export type ValorParametro = string | number | boolean | null;
export type OrigemValor = "padrao" | "tenant" | "obra";
export type OpcaoParametro = { valor: string; rotulo: string; descricao?: string | null };

// Linha de app.parametro, com minimo e maximo já convertidos para número.
export type Parametro = {
  codigo: string;
  grupo: string;
  nome: string;
  descricao: string;
  tipo: TipoParametro;
  opcoes: OpcaoParametro[] | null;
  minimo: number | null;
  maximo: number | null;
  padrao: ValorParametro;
  aceita_nulo: boolean;
  escopo: EscopoParametro;
  ordem: number;
  exige_validacao_financeira: boolean;
};

// Linha de app.parametro_valor. Centro nulo é o valor da construtora.
export type RegistroValor = {
  id: string;
  centro_custo_id: string | null;
  codigo: string;
  valor: ValorParametro;
  observacao: string | null;
  autor: string | null;
  atualizado_em: string | null;
};

export const mensagensConfiguracao = {
  semPermissaoLeitura:
    "Seu perfil vê os valores em vigor. Só diretor ou financeiro da construtora pode alterar a configuração.",
  corrijaCampos: "Confira os campos marcados e tente de novo.",
  semSessao: "Sua sessão terminou. Entre de novo para gravar.",
  semPermissao: "Só diretor ou financeiro da construtora pode alterar a configuração.",
  parametroDesconhecido: "Este parâmetro não existe mais. Recarregue a página.",
  obraNaoEncontrada: "Obra não encontrada ou sem permissão para o seu perfil.",
  soConstrutora: "Este parâmetro vale para a construtora inteira. Troque o escopo para Construtora para alterar.",
  gravado: "Valor gravado. As telas e os números passam a usar o novo valor.",
  voltouPadrao: "Valor excluído. Passa a valer o nível de cima.",
  nadaParaVoltar: "Não há valor gravado neste nível. Nada foi alterado.",
  confirmeValidacao: "Marque a confirmação para gravar este parâmetro.",
  observacaoObrigatoria: "Escreva com quem e quando a regra foi validada.",
  codigoGravado: "Código mapeado. O novo valor vale a partir da próxima carga de dados.",
  rotuloGravado: "Rótulo gravado. As telas passam a mostrar o novo nome.",
  rotuloExcluido: "Rótulo excluído. A tela volta a mostrar o nome do produto.",
  subcategoriaGravada: "Subcategoria gravada.",
  subcategoriaAusente:
    "As subcategorias ainda não estão disponíveis neste ambiente. Elas aparecem quando o banco for atualizado.",
  semHistorico: "Nenhuma alteração registrada, ou o seu perfil não pode ver o histórico.",
  semPendenciasCodigo: "Todo código visto na origem já tem valor mapeado.",
  semCodigos: "Nenhum código mapeado para este domínio.",
  semRotulos: "Nenhum rótulo personalizado. As telas mostram os nomes do produto.",
  semSubcategorias: "Nenhuma subcategoria cadastrada.",
  catalogoIndisponivel:
    "Não foi possível carregar os parâmetros agora. Recarregue a página em alguns minutos.",
} as const;

export const gruposParametro = [
  "reconhecimento",
  "dre",
  "caixa",
  "financiamento",
  "comercial",
  "simulacao",
  "negocio",
  "alerta",
  "exibicao",
] as const;

export const rotulosGrupo: Record<string, { titulo: string; descricao: string }> = {
  reconhecimento: {
    titulo: "Reconhecimento de receita e custo",
    descricao: "Como a fração vendida e o percentual de conclusão são calculados para o DRE.",
  },
  dre: { titulo: "DRE gerencial", descricao: "Em que mês cada título entra no DRE e nas despesas." },
  caixa: {
    titulo: "Fluxo de caixa projetado",
    descricao: "O que entra no caixa previsto: vencidos, financiamento pendente, liberações e custo sem título.",
  },
  financiamento: { titulo: "Financiamento", descricao: "Leitura das datas do banco e retenção padrão." },
  comercial: { titulo: "Metas comerciais", descricao: "Como a meta de vendas é calculada." },
  simulacao: {
    titulo: "Padrões da simulação",
    descricao: "Valores que já vêm preenchidos no formulário de simulação de cada obra.",
  },
  negocio: { titulo: "Negócio", descricao: "Fuso horário que define a data de referência." },
  alerta: { titulo: "Alertas", descricao: "Quando a tela avisa que os dados estão desatualizados." },
  exibicao: { titulo: "Exibição", descricao: "Período inicial dos demonstrativos e horizonte dos gráficos." },
};

export const rotulosOrigem: Record<OrigemValor, string> = {
  padrao: "Padrão do produto",
  tenant: "Valor da construtora",
  obra: "Valor desta obra",
};

// Entrada, parcelas e financiamento são gravados juntos: a soma é conferida no nível gravado.
export const codigosComposicao = [
  "simulacao.fracao_entrada",
  "simulacao.fracao_parcelas",
  "simulacao.fracao_financiamento",
] as const;

// Fusos do Brasil oferecidos na lista; o banco confere de novo em pg_timezone_names.
export const fusosBrasil = [
  "America/Sao_Paulo",
  "America/Bahia",
  "America/Fortaleza",
  "America/Recife",
  "America/Maceio",
  "America/Belem",
  "America/Araguaina",
  "America/Santarem",
  "America/Manaus",
  "America/Cuiaba",
  "America/Campo_Grande",
  "America/Porto_Velho",
  "America/Boa_Vista",
  "America/Rio_Branco",
  "America/Eirunepe",
  "America/Noronha",
] as const;

// Código do parâmetro vira nome de coluna em app.parametros_obra e app.parametros_tenant.
export function colunaDoParametro(codigo: string): string {
  return codigo.replace(/\./g, "__");
}

// Chave do registro no índice: código e nível (centro vazio = construtora).
function chaveNivel(codigo: string, centroId: string | null): string {
  return `${codigo}|${centroId ?? ""}`;
}

export type IndiceValores = Map<string, RegistroValor>;

// O(n) sobre os registros lidos (até parâmetros x (1 + obras), poucas centenas).
export function indexarValores(registros: readonly RegistroValor[]): IndiceValores {
  return new Map(registros.map((registro) => [chaveNivel(registro.codigo, registro.centro_custo_id), registro]));
}

export type ValorEmVigor = { valor: ValorParametro; origem: OrigemValor; registro: RegistroValor | null };

// A obra vence a construtora e a construtora vence o padrão. Parâmetro só de construtora ignora valor por obra.
export function resolverValor(parametro: Parametro, indice: IndiceValores, centroId: string | null): ValorEmVigor {
  if (centroId && parametro.escopo === "tenant_e_obra") {
    const daObra = indice.get(chaveNivel(parametro.codigo, centroId));
    if (daObra) return { valor: daObra.valor, origem: "obra", registro: daObra };
  }
  const daConstrutora = indice.get(chaveNivel(parametro.codigo, null));
  if (daConstrutora) return { valor: daConstrutora.valor, origem: "tenant", registro: daConstrutora };
  return { valor: parametro.padrao, origem: "padrao", registro: null };
}

// Valor gravado exatamente no nível escolhido, o que "voltar ao padrão" exclui.
export function registroNoNivel(
  parametro: Parametro,
  indice: IndiceValores,
  centroId: string | null,
): RegistroValor | null {
  if (centroId && parametro.escopo !== "tenant_e_obra") return null;
  return indice.get(chaveNivel(parametro.codigo, centroId)) ?? null;
}

export type ItemParametro = {
  tipo: "parametro";
  parametro: Parametro;
  emVigor: ValorEmVigor;
  noNivel: RegistroValor | null;
  editavel: boolean;
};

export type ItemComposicao = {
  tipo: "composicao";
  parametros: Parametro[];
  emVigor: ValorEmVigor[];
  noNivel: (RegistroValor | null)[];
  editavel: boolean;
};

export type GrupoTela = { grupo: string; titulo: string; descricao: string; itens: (ItemParametro | ItemComposicao)[] };

// Um bloco por grupo na ordem do contrato, parâmetros pela coluna ordem. Grupo novo no catálogo entra no fim
// sem código novo. Com obra escolhida, parâmetro só de construtora aparece sem formulário.
// O(p log p) pela ordenação, com p na casa de dezenas.
export function montarGrupos(
  catalogo: readonly Parametro[],
  registros: readonly RegistroValor[],
  centroId: string | null,
): GrupoTela[] {
  const indice = indexarValores(registros);
  const posicaoGrupo = (grupo: string) => {
    const posicao = (gruposParametro as readonly string[]).indexOf(grupo);
    return posicao === -1 ? gruposParametro.length : posicao;
  };
  const ordenados = [...catalogo].sort(
    (a, b) =>
      posicaoGrupo(a.grupo) - posicaoGrupo(b.grupo) ||
      a.grupo.localeCompare(b.grupo) ||
      a.ordem - b.ordem ||
      a.codigo.localeCompare(b.codigo),
  );
  const porCodigo = new Map(catalogo.map((parametro) => [parametro.codigo, parametro]));
  const composicao = codigosComposicao.map((codigo) => porCodigo.get(codigo));
  const temComposicao = composicao.every((parametro) => parametro !== undefined);
  const editavel = (parametro: Parametro) => centroId === null || parametro.escopo === "tenant_e_obra";

  const grupos = new Map<string, GrupoTela>();
  for (const parametro of ordenados) {
    let grupo = grupos.get(parametro.grupo);
    if (!grupo) {
      const rotulo = rotulosGrupo[parametro.grupo];
      grupo = {
        grupo: parametro.grupo,
        titulo: rotulo?.titulo ?? parametro.grupo.charAt(0).toUpperCase() + parametro.grupo.slice(1),
        descricao: rotulo?.descricao ?? "",
        itens: [],
      };
      grupos.set(parametro.grupo, grupo);
    }
    const posicaoComposicao = (codigosComposicao as readonly string[]).indexOf(parametro.codigo);
    if (temComposicao && posicaoComposicao !== -1) {
      if (grupo.itens.some((item) => item.tipo === "composicao")) continue;
      const parametros = composicao as Parametro[];
      grupo.itens.push({
        tipo: "composicao",
        parametros,
        emVigor: parametros.map((item) => resolverValor(item, indice, centroId)),
        noNivel: parametros.map((item) => registroNoNivel(item, indice, centroId)),
        editavel: parametros.every(editavel),
      });
      continue;
    }
    grupo.itens.push({
      tipo: "parametro",
      parametro,
      emVigor: resolverValor(parametro, indice, centroId),
      noNivel: registroNoNivel(parametro, indice, centroId),
      editavel: editavel(parametro),
    });
  }
  return [...grupos.values()];
}

const formatoNumero = new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 6 });
const formatoPercentual = new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 4 });

export function percentualDaFracao(fracao: number): string {
  return `${formatoPercentual.format(Number((fracao * 100).toFixed(4)))}%`;
}

// Texto do valor na tela: opção pelo rótulo, fração em percentual, data no formato brasileiro.
export function textoDoValor(parametro: Pick<Parametro, "tipo" | "opcoes">, valor: ValorParametro): string {
  if (valor === null || valor === undefined) return "Sem valor";
  switch (parametro.tipo) {
    case "opcao":
      return parametro.opcoes?.find((opcao) => opcao.valor === valor)?.rotulo ?? String(valor);
    case "booleano":
      return valor === true ? "Sim" : "Não";
    case "fracao":
      return typeof valor === "number" ? percentualDaFracao(valor) : String(valor);
    case "inteiro":
    case "numero":
      return typeof valor === "number" ? formatoNumero.format(valor) : String(valor);
    case "data": {
      const data = lerData(String(valor));
      return data ? `${data.slice(8, 10)}/${data.slice(5, 7)}/${data.slice(0, 4)}` : String(valor);
    }
    default:
      return String(valor);
  }
}

// Valor que o campo do formulário mostra: fração em percentual com vírgula, booleano como "true"/"false".
export function textoDoFormulario(parametro: Pick<Parametro, "tipo">, valor: ValorParametro): string {
  if (valor === null || valor === undefined) return "";
  if (parametro.tipo === "fracao" && typeof valor === "number") {
    return String(Number((valor * 100).toFixed(4))).replace(".", ",");
  }
  if (parametro.tipo === "numero" && typeof valor === "number") return String(valor).replace(".", ",");
  return String(valor);
}

// Faixa aceita, para a ajuda do campo e para a mensagem de erro.
export function textoFaixa(parametro: Pick<Parametro, "tipo" | "minimo" | "maximo">): string | null {
  const { minimo, maximo } = parametro;
  if (minimo === null && maximo === null) return null;
  const formatar = (valor: number) =>
    parametro.tipo === "fracao" ? percentualDaFracao(valor) : formatoNumero.format(valor);
  if (minimo !== null && maximo !== null) return `de ${formatar(minimo)} a ${formatar(maximo)}`;
  if (minimo !== null) return `a partir de ${formatar(minimo)}`;
  return `até ${formatar(maximo as number)}`;
}

export type ResultadoValor = { ok: true; valor: ValorParametro } | { ok: false; erro: string };

// Percentual com até 4 casas vira fração em milionésimos inteiros, sem erro de ponto flutuante.
function milionesimosDePercentual(texto: string): number | null {
  const partes = /^(\d{1,3})(?:[.,](\d{1,4}))?$/.exec(texto);
  if (!partes) return null;
  return Number(partes[1]) * 10_000 + Number((partes[2] ?? "").padEnd(4, "0"));
}

function lerNumero(texto: string): number | null {
  const partes = /^(-?)(\d{1,12})(?:[.,](\d{1,6}))?$/.exec(texto.replace(/\s/g, ""));
  if (!partes) return null;
  return Number(`${partes[1]}${partes[2]}.${partes[3] ?? "0"}`);
}

function dentroDaFaixa(valor: number, parametro: Pick<Parametro, "minimo" | "maximo">): boolean {
  return (parametro.minimo === null || valor >= parametro.minimo) && (parametro.maximo === null || valor <= parametro.maximo);
}

function fusoExiste(fuso: string): boolean {
  if (!/^[A-Za-z_]+(\/[A-Za-z0-9_+-]+){0,2}$/.test(fuso)) return false;
  try {
    new Intl.DateTimeFormat("pt-BR", { timeZone: fuso });
    return true;
  } catch {
    return false;
  }
}

const tamanhoMaximoTexto = 500;

// Validação feita no servidor a partir da linha do catálogo; o gatilho do banco confere de novo (23514).
// Valor gravado nunca é vazio: a coluna é not null e "sem valor" se consegue excluindo o nível.
export function validarValorParametro(parametro: Parametro, entrada: string | null | undefined): ResultadoValor {
  const texto = (entrada ?? "").trim();
  const faixa = textoFaixa(parametro);
  if (texto === "") {
    return {
      ok: false,
      erro:
        parametro.aceita_nulo
          ? "Preencha o valor. Para ficar sem valor, use o botão de voltar ao padrão."
          : "Preencha o valor.",
    };
  }
  switch (parametro.tipo) {
    case "opcao":
      return parametro.opcoes?.some((opcao) => opcao.valor === texto)
        ? { ok: true, valor: texto }
        : { ok: false, erro: "Escolha uma das opções da lista." };
    case "booleano":
      if (texto === "true") return { ok: true, valor: true };
      if (texto === "false") return { ok: true, valor: false };
      return { ok: false, erro: "Escolha sim ou não." };
    case "inteiro": {
      const inteiro = /^-?\d{1,9}$/.test(texto) ? Number(texto) : null;
      if (inteiro === null || !dentroDaFaixa(inteiro, parametro)) {
        return { ok: false, erro: `Informe um número inteiro${faixa ? ` ${faixa}` : ""}.` };
      }
      return { ok: true, valor: inteiro };
    }
    case "numero": {
      const numero = lerNumero(texto);
      if (numero === null || !dentroDaFaixa(numero, parametro)) {
        return { ok: false, erro: `Informe um número${faixa ? ` ${faixa}` : ""}.` };
      }
      return { ok: true, valor: numero };
    }
    case "fracao": {
      const milionesimos = milionesimosDePercentual(texto.replace(/\s|%/g, ""));
      const fracao = milionesimos === null ? null : milionesimos / 1_000_000;
      if (fracao === null || fracao > 1 || !dentroDaFaixa(fracao, parametro)) {
        return { ok: false, erro: `Informe um percentual${faixa ? ` ${faixa}` : " de 0% a 100%"}, com até 4 casas.` };
      }
      return { ok: true, valor: fracao };
    }
    case "texto":
      return texto.length <= tamanhoMaximoTexto && !/[\u0000-\u001f]/.test(texto)
        ? { ok: true, valor: texto }
        : { ok: false, erro: `Escreva até ${tamanhoMaximoTexto} caracteres, sem quebra de linha.` };
    case "data":
      return lerData(texto) ? { ok: true, valor: texto } : { ok: false, erro: "Informe uma data válida." };
    case "fuso":
      return fusoExiste(texto) ? { ok: true, valor: texto } : { ok: false, erro: "Escolha um fuso horário da lista." };
    default:
      return { ok: false, erro: "Tipo de parâmetro desconhecido. Recarregue a página." };
  }
}

export type ResultadoComposicao =
  | { ok: true; valores: number[] }
  | { ok: false; erros: Record<string, string> };

// As três frações da simulação são validadas uma a uma e depois pela soma exata, em milionésimos.
export function validarComposicao(parametros: readonly Parametro[], textos: readonly (string | undefined)[]): ResultadoComposicao {
  const erros: Record<string, string> = {};
  const valores: number[] = [];
  parametros.forEach((parametro, posicao) => {
    const resultado = validarValorParametro(parametro, textos[posicao]);
    if (!resultado.ok) erros[parametro.codigo] = resultado.erro;
    else if (typeof resultado.valor !== "number") erros[parametro.codigo] = "Preencha o valor.";
    else valores.push(resultado.valor);
  });
  if (Object.keys(erros).length > 0) return { ok: false, erros };
  const soma = valores.reduce((total, valor) => total + Math.round(valor * 1_000_000), 0);
  if (soma !== 1_000_000) {
    const ultimo = parametros[parametros.length - 1].codigo;
    return {
      ok: false,
      erros: { [ultimo]: `Entrada, parcelas e financiamento precisam somar 100%. Hoje somam ${percentualDaFracao(soma / 1_000_000)}.` },
    };
  }
  return { ok: true, valores };
}

const tamanhoMaximoObservacao = 500;

export function validarObservacao(
  texto: string | null | undefined,
  obrigatoria: boolean,
): { ok: true; observacao: string | null } | { ok: false; erro: string } {
  const limpo = (texto ?? "").trim();
  if (limpo.length > tamanhoMaximoObservacao) {
    return { ok: false, erro: `Escreva até ${tamanhoMaximoObservacao} caracteres.` };
  }
  if (obrigatoria && limpo.length < 5) return { ok: false, erro: mensagensConfiguracao.observacaoObrigatoria };
  return { ok: true, observacao: limpo === "" ? null : limpo };
}

const formatoUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const escopoConstrutora = "construtora";

// "construtora" é o nível do tenant; qualquer outro valor precisa ser o id de uma obra.
export function lerEscopo(texto: string | null | undefined): { ok: true; centroId: string | null } | { ok: false } {
  if (!texto || texto === escopoConstrutora) return { ok: true, centroId: null };
  return formatoUuid.test(texto) ? { ok: true, centroId: texto.toLowerCase() } : { ok: false };
}

// Mapa de códigos da origem (seção 2.4 do contrato de configuração). Os valores aceitos e o que vale sem
// mapa vêm de app.valor_codigo_origem; aqui ficam só os títulos da tela.
export const dominiosCodigo = {
  condicao_pagamento: "Condição de pagamento das parcelas",
  situacao_unidade: "Situação da unidade",
  situacao_contrato: "Situação do contrato de venda",
} as const;

export type DominioCodigo = keyof typeof dominiosCodigo;
export const listaDominios = Object.keys(dominiosCodigo) as DominioCodigo[];

export type ValorCodigoOrigem = {
  dominio: string;
  valor: string;
  rotulo: string;
  ordem: number;
  valor_sem_mapa: boolean;
};

export function rotuloValorMapeado(valores: readonly ValorCodigoOrigem[], dominio: string, valor: string): string {
  return valores.find((item) => item.dominio === dominio && item.valor === valor)?.rotulo ?? valor;
}

// Soma as pendências de cada código entre as obras (a view abre por obra). O(n) sobre poucas linhas.
export function somarPendenciasPorCodigo<
  T extends { dominio: string; codigo_origem: string | null; quantidade_registros: number; valor_envolvido: number | null },
>(linhas: readonly T[]): (T & { obras: number })[] {
  const porCodigo = new Map<string, T & { obras: number }>();
  for (const linha of linhas) {
    const chave = `${linha.dominio}|${linha.codigo_origem ?? ""}`;
    const atual = porCodigo.get(chave);
    if (!atual) {
      porCodigo.set(chave, { ...linha, obras: 1 });
      continue;
    }
    atual.obras += 1;
    atual.quantidade_registros += linha.quantidade_registros;
    atual.valor_envolvido =
      atual.valor_envolvido === null && linha.valor_envolvido === null
        ? null
        : (atual.valor_envolvido ?? 0) + (linha.valor_envolvido ?? 0);
  }
  return [...porCodigo.values()].sort(
    (a, b) => a.dominio.localeCompare(b.dominio) || (b.valor_envolvido ?? 0) - (a.valor_envolvido ?? 0),
  );
}

type Leitor = (nome: string) => string;

export function leitorDoFormulario(formulario: FormData): Leitor {
  return (nome) => {
    const valor = formulario.get(nome);
    return typeof valor === "string" ? valor.trim() : "";
  };
}

// Código como a origem manda: até 40 caracteres, sem controle nem espaço nas pontas.
const formatoCodigoOrigem = /^[^\u0000-\u001f\s](?:[^\u0000-\u001f]{0,38}[^\u0000-\u001f\s])?$/;

export type DadosMapaCodigo = {
  dominio: DominioCodigo;
  codigo_origem: string;
  valor: string;
  rotulo: string | null;
  observacao: string | null;
};

export function validarMapaCodigo(
  ler: Leitor,
  aceitos: readonly ValorCodigoOrigem[],
): { ok: true; dados: DadosMapaCodigo } | { ok: false; erros: Record<string, string> } {
  const erros: Record<string, string> = {};
  const dominio = ler("dominio");
  const codigo = ler("codigo_origem");
  const valor = ler("valor");
  const rotulo = ler("rotulo");
  const observacao = validarObservacao(ler("observacao"), false);
  const conhecido = (listaDominios as string[]).includes(dominio);
  if (!conhecido) erros.dominio = "Escolha um domínio da lista.";
  if (!formatoCodigoOrigem.test(codigo)) {
    erros.codigo_origem = "Informe o código exatamente como aparece na origem, com até 40 caracteres.";
  }
  if (conhecido && !aceitos.some((item) => item.dominio === dominio && item.valor === valor)) {
    erros.valor = "Escolha um valor da lista.";
  }
  if (rotulo.length > 80) erros.rotulo = "Escreva até 80 caracteres.";
  if (!observacao.ok) erros.observacao = observacao.erro;
  if (Object.keys(erros).length > 0 || !observacao.ok) return { ok: false, erros };
  return {
    ok: true,
    dados: {
      dominio: dominio as DominioCodigo,
      codigo_origem: codigo,
      valor,
      rotulo: rotulo === "" ? null : rotulo,
      observacao: observacao.observacao,
    },
  };
}

// Linhas do DRE que aceitam rótulo próprio, com o nome que o produto usa (marts.dre_mensal, 0011).
export const linhasDre: { chave: string; nome: string }[] = [
  { chave: "receita_bruta", nome: "Receita bruta reconhecida" },
  { chave: "deducoes", nome: "Deduções e tributos sobre a receita" },
  { chave: "receita_liquida", nome: "Receita líquida" },
  { chave: "custo_imovel_vendido", nome: "Custo reconhecido dos imóveis vendidos" },
  { chave: "resultado_bruto", nome: "Resultado bruto" },
  { chave: "despesas_comerciais", nome: "Despesas comerciais" },
  { chave: "despesas_administrativas", nome: "Despesas administrativas" },
  { chave: "resultado_financeiro", nome: "Resultado financeiro" },
  { chave: "resultado_gerencial", nome: "Resultado gerencial do período" },
  { chave: "custo_obra_incorrido", nome: "Custo de obra lançado no mês (vai para o estoque)" },
  { chave: "fora_do_resultado", nome: "Movimentos fora do resultado" },
  { chave: "sem_categoria", nome: "Lançamentos sem categoria" },
  { chave: "sem_data_competencia", nome: "Lançamentos sem data de competência" },
];

export const contextosRotulo = { linha_dre: "Linha do DRE", categoria: "Categoria gerencial" } as const;
export type ContextoRotulo = keyof typeof contextosRotulo;

export type RotuloPersonalizado = { contexto: string; chave: string; rotulo: string };

export type DadosRotulo = { contexto: ContextoRotulo; chave: string; rotulo: string | null };

// Rótulo vazio significa excluir e voltar ao nome do produto.
export function validarRotulo(ler: Leitor): { ok: true; dados: DadosRotulo } | { ok: false; erros: Record<string, string> } {
  const erros: Record<string, string> = {};
  const contexto = ler("contexto");
  const chave = ler("chave");
  const rotulo = ler("rotulo");
  if (!Object.hasOwn(contextosRotulo, contexto)) erros.contexto = "Escolha onde o rótulo aparece.";
  if (!/^[a-z0-9_]{1,60}$/.test(chave)) erros.chave = "Escolha a linha ou a categoria da lista.";
  else if (contexto === "linha_dre" && !linhasDre.some((linha) => linha.chave === chave)) {
    erros.chave = "Escolha a linha do DRE da lista.";
  }
  if (rotulo.length > 80 || /[\u0000-\u001f]/.test(rotulo)) erros.rotulo = "Escreva até 80 caracteres, sem quebra de linha.";
  if (Object.keys(erros).length > 0) return { ok: false, erros };
  return { ok: true, dados: { contexto: contexto as ContextoRotulo, chave, rotulo: rotulo === "" ? null : rotulo } };
}

// Troca só o texto exibido: a chave e a definição continuam as do produto. O(n + m).
export function aplicarRotulos<T extends { nome: string }>(
  itens: readonly T[],
  chaveDe: (item: T) => string,
  rotulos: readonly RotuloPersonalizado[],
  contexto: ContextoRotulo,
): T[] {
  const porChave = new Map(
    rotulos.filter((rotulo) => rotulo.contexto === contexto).map((rotulo) => [rotulo.chave, rotulo.rotulo]),
  );
  return itens.map((item) => {
    const rotulo = porChave.get(chaveDe(item));
    return rotulo ? { ...item, nome: rotulo } : item;
  });
}

export type Subcategoria = {
  id: string;
  categoria_codigo: string;
  codigo: string;
  nome: string;
  ativa: boolean;
};

export type DadosSubcategoria = {
  id: string | null;
  categoria_codigo: string;
  codigo: string;
  nome: string;
  ativa: boolean;
};

export function validarSubcategoria(
  ler: Leitor,
): { ok: true; dados: DadosSubcategoria } | { ok: false; erros: Record<string, string> } {
  const erros: Record<string, string> = {};
  const id = ler("id");
  const categoria = ler("categoria_codigo");
  const codigo = ler("codigo");
  const nome = ler("nome");
  const ativa = ler("ativa");
  if (id !== "" && !formatoUuid.test(id)) erros.id = "Subcategoria não encontrada. Recarregue a página.";
  if (!/^[a-z0-9_]{1,60}$/.test(categoria)) erros.categoria_codigo = "Escolha a categoria gerencial.";
  if (!/^[a-z0-9_.-]{1,40}$/.test(codigo)) {
    erros.codigo = "Use letras minúsculas, números, ponto, hífen ou sublinhado, até 40.";
  }
  if (nome === "" || nome.length > 80 || /[\u0000-\u001f]/.test(nome)) erros.nome = "Escreva o nome, até 80 caracteres.";
  if (ativa !== "sim" && ativa !== "nao") erros.ativa = "Escolha se a subcategoria está em uso.";
  if (Object.keys(erros).length > 0) return { ok: false, erros };
  return {
    ok: true,
    dados: { id: id === "" ? null : id.toLowerCase(), categoria_codigo: categoria, codigo, nome, ativa: ativa === "sim" },
  };
}

// Preferências da construtora lidas por outras telas. Sem leitura do banco, vale o comportamento anterior.
export type PreferenciasTenant = { periodoPadrao: TipoPeriodo; mesesGrafico: number; consolidadoCompensaObras: boolean };

export const preferenciasProduto: PreferenciasTenant = {
  periodoPadrao: "ano",
  mesesGrafico: 36,
  consolidadoCompensaObras: false,
};

export const colunasPreferencias = [
  colunaDoParametro("exibicao.periodo_padrao"),
  colunaDoParametro("exibicao.meses_grafico"),
  colunaDoParametro("caixa.consolidado_compensa_obras"),
] as const;

// Recebe a linha de app.parametros_tenant; valor fora do esperado cai no comportamento anterior.
export function lerPreferenciasTenant(linha: Record<string, unknown> | null | undefined): PreferenciasTenant {
  if (!linha) return preferenciasProduto;
  const meses = Number(linha[colunasPreferencias[1]]);
  const compensa = linha[colunasPreferencias[2]];
  return {
    periodoPadrao: tipoPeriodoDaPreferencia(linha[colunasPreferencias[0]], preferenciasProduto.periodoPadrao),
    mesesGrafico: Number.isInteger(meses) && meses >= 12 && meses <= 120 ? meses : preferenciasProduto.mesesGrafico,
    consolidadoCompensaObras: compensa === true || compensa === "true",
  };
}

// Horizonte do gráfico: um terço antes do mês de referência e o resto depois. 36 meses dão 12 e 24,
// a janela que a tela usava antes da configuração.
export function janelaDoHorizonte(meses: number): { antes: number; depois: number; rotulo: string } {
  const antes = Math.round(meses / 3);
  const depois = meses - antes;
  return { antes, depois, rotulo: `${antes} meses antes e ${depois} depois` };
}

export function limitesDoHorizonte(meses: number, dataReferencia: string): { inicio: string; fim: string } {
  const { antes, depois } = janelaDoHorizonte(meses);
  const referencia = mesDaData(dataReferencia);
  return { inicio: somarMeses(referencia, -antes), fim: somarMeses(referencia, depois) };
}

// Padrões de simulação da obra (app.parametros_obra), em fração e meses.
export type PadroesSimulacao = {
  desconto: number | null;
  fracao_entrada: number | null;
  fracao_parcelas: number | null;
  fracao_financiamento: number | null;
  quantidade_parcelas: number | null;
  meses_ate_liberacao: number | null;
};

export const camposPadraoSimulacao = [
  "desconto",
  "fracao_entrada",
  "fracao_parcelas",
  "fracao_financiamento",
  "quantidade_parcelas",
  "meses_ate_liberacao",
] as const satisfies readonly (keyof PadroesSimulacao)[];

export const colunasSimulacao = camposPadraoSimulacao.map((campo) => colunaDoParametro(`simulacao.${campo}`));

export function lerPadroesSimulacao(linha: Record<string, unknown> | null | undefined): PadroesSimulacao | null {
  if (!linha) return null;
  const padroes = {} as PadroesSimulacao;
  camposPadraoSimulacao.forEach((campo, posicao) => {
    const bruto = linha[colunasSimulacao[posicao]];
    const numero = bruto === null || bruto === undefined || bruto === "" ? NaN : Number(bruto);
    padroes[campo] = Number.isFinite(numero) && numero >= 0 ? numero : null;
  });
  return padroes;
}

// Quem gravou, sem expor o identificador: a tela não tem nome de usuário, só sabe se foi a própria pessoa.
export function quemAlterou(autor: string | null | undefined, usuarioId: string): string {
  if (!autor) return "carga automática";
  return autor === usuarioId ? "você" : "outro usuário da construtora";
}

export type AlteracaoConfiguracao = {
  id: number;
  tabela: string;
  registro_id: string;
  operacao: "insert" | "update" | "delete";
  antes: Record<string, unknown> | null;
  depois: Record<string, unknown> | null;
  autor: string | null;
  alterado_em: string;
};

export const tabelasConfiguracao = [
  "app.parametro_valor",
  "app.mapa_codigo_origem",
  "app.rotulo_personalizado",
  "app.categoria_tenant",
] as const;

function valorJson(valor: unknown): ValorParametro {
  return typeof valor === "string" || typeof valor === "number" || typeof valor === "boolean" ? valor : null;
}

// Uma frase por alteração, sem mostrar id, tabela nem JSON.
export function descreverAlteracao(
  alteracao: AlteracaoConfiguracao,
  catalogo: ReadonlyMap<string, Parametro>,
  nomesObra: ReadonlyMap<string, string>,
  valoresCodigo: readonly ValorCodigoOrigem[] = [],
): { titulo: string; detalhe: string } {
  const registro = alteracao.depois ?? alteracao.antes ?? {};
  const texto = (campo: string) => (typeof registro[campo] === "string" ? (registro[campo] as string) : "");
  const excluido = alteracao.operacao === "delete";
  if (alteracao.tabela === "app.parametro_valor") {
    const parametro = catalogo.get(texto("codigo"));
    const centro = texto("centro_custo_id");
    const nivel = centro ? `obra ${nomesObra.get(centro) ?? "sem acesso"}` : "construtora";
    const formatar = (valor: unknown) =>
      parametro ? textoDoValor(parametro, valorJson(valor)) : String(valorJson(valor) ?? "sem valor");
    const antes = alteracao.antes?.valor;
    const depois = alteracao.depois?.valor;
    let detalhe: string;
    if (excluido) detalhe = `Voltou ao nível de cima (era ${formatar(antes)}).`;
    else if (alteracao.operacao === "update") detalhe = `De ${formatar(antes)} para ${formatar(depois)}.`;
    else detalhe = `Passou a ${formatar(depois)}.`;
    const observacao = texto("observacao");
    return {
      titulo: `${parametro?.nome ?? "Parâmetro"}, ${nivel}`,
      detalhe: !excluido && observacao ? `${detalhe} Observação: ${observacao}` : detalhe,
    };
  }
  if (alteracao.tabela === "app.mapa_codigo_origem") {
    const dominio = texto("dominio");
    const onde = (dominiosCodigo as Record<string, string>)[dominio]?.toLowerCase() ?? "códigos da origem";
    return {
      titulo: `Código ${texto("codigo_origem")} em ${onde}`,
      detalhe: excluido
        ? "Mapeamento excluído."
        : `Mapeado para ${rotuloValorMapeado(valoresCodigo, dominio, texto("valor"))}.`,
    };
  }
  if (alteracao.tabela === "app.rotulo_personalizado") {
    const contexto = texto("contexto") as ContextoRotulo;
    const chave = texto("chave");
    const nomeLinha = linhasDre.find((linha) => linha.chave === chave)?.nome ?? chave.replace(/_/g, " ");
    return {
      titulo: `Rótulo: ${contextosRotulo[contexto]?.toLowerCase() ?? "texto"} ${nomeLinha}`,
      detalhe: excluido ? "Voltou ao nome do produto." : `Passou a aparecer como "${texto("rotulo")}".`,
    };
  }
  return {
    titulo: `Subcategoria ${texto("nome") || texto("codigo")}`,
    detalhe: excluido
      ? "Excluída."
      : registro.ativa === false
        ? "Fora de uso."
        : alteracao.operacao === "insert"
          ? "Criada."
          : "Alterada.",
  };
}
