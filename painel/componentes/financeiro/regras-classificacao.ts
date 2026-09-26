// Validação, no servidor, dos formulários do DRE: classificar conta de origem e registrar o critério de
// reconhecimento. Puro, para testar sem banco. O banco confere de novo (gatilhos e RLS da 0011).
import type { CategoriaGerencial } from "../../lib/consultas/dre";

export type EstadoGravacao = {
  situacao: "inicial" | "sucesso" | "erro";
  mensagem: string;
  erros: Record<string, string>;
  valores: Record<string, string>;
};

export const estadoGravacaoInicial: EstadoGravacao = { situacao: "inicial", mensagem: "", erros: {}, valores: {} };

export const tiposOrigemConta = ["titulo_pagar", "parcela_receber", "orcamento"] as const;
export type TipoOrigemConta = (typeof tiposOrigemConta)[number];

export const rotulosTipoOrigem: Record<TipoOrigemConta, string> = {
  titulo_pagar: "Título a pagar",
  parcela_receber: "Parcela a receber",
  orcamento: "Item de orçamento",
};

export const metodosReconhecimento = ["nao_definido", "percentual_conclusao"] as const;
export type MetodoReconhecimento = (typeof metodosReconhecimento)[number];

export const rotulosMetodo: Record<MetodoReconhecimento, string> = {
  nao_definido: "Não definido (receita e resultado ficam indisponíveis)",
  percentual_conclusao: "Percentual de conclusão da obra",
};

// Escopo do critério: o tenant inteiro ou uma obra.
export const escopoTenant = "tenant";

const tamanhoMaximoConta = 60;
const tamanhoMaximoObservacao = 500;
const formatoCategoria = /^[a-z_]{1,60}$/;
const formatoUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Mesma regra do gatilho app.validar_mapa_conta_origem: título só em saída, parcela só em entrada,
// orçamento só em custo do imóvel.
export function categoriaServeParaOrigem(
  tipo: TipoOrigemConta,
  categoria: Pick<CategoriaGerencial, "natureza" | "grupo_dre">,
): boolean {
  if (tipo === "titulo_pagar") return categoria.natureza === "saida";
  if (tipo === "parcela_receber") return categoria.natureza === "entrada";
  return categoria.grupo_dre === "custo_imovel";
}

export function categoriasPara<T extends Pick<CategoriaGerencial, "natureza" | "grupo_dre">>(
  tipo: TipoOrigemConta,
  categorias: T[],
): T[] {
  return categorias.filter((categoria) => categoriaServeParaOrigem(tipo, categoria));
}

type Leitor = (nome: string) => string;

export function leitorDoFormulario(formulario: FormData): Leitor {
  return (nome) => {
    const valor = formulario.get(nome);
    return typeof valor === "string" ? valor.trim() : "";
  };
}

export function valoresDoFormulario(formulario: FormData): Record<string, string> {
  const valores: Record<string, string> = {};
  formulario.forEach((valor, chave) => {
    if (typeof valor === "string" && !chave.startsWith("$ACTION")) valores[chave] = valor.slice(0, 1000);
  });
  return valores;
}

export type Classificacao = {
  tipo_origem: TipoOrigemConta;
  conta_origem: string;
  categoria_codigo: string;
  observacao: string | null;
};

export type Validacao<T> = { ok: true; dados: T } | { ok: false; erros: Record<string, string> };

// A compatibilidade com a categoria é conferida depois, com a categoria lida do banco.
export function validarClassificacao(ler: Leitor): Validacao<Classificacao> {
  const erros: Record<string, string> = {};
  const tipo = tiposOrigemConta.find((opcao) => opcao === ler("tipo_origem"));
  const conta = ler("conta_origem");
  const categoria = ler("categoria_codigo");
  const observacao = ler("observacao");
  if (!tipo) erros.tipo_origem = "Escolha o tipo de lançamento.";
  if (!conta) erros.conta_origem = "Informe o código da conta como aparece na origem.";
  else if (conta.length > tamanhoMaximoConta) erros.conta_origem = `Use no máximo ${tamanhoMaximoConta} caracteres.`;
  if (!formatoCategoria.test(categoria)) erros.categoria_codigo = "Escolha uma categoria da lista.";
  if (observacao.length > tamanhoMaximoObservacao)
    erros.observacao = `Use no máximo ${tamanhoMaximoObservacao} caracteres.`;
  if (Object.keys(erros).length > 0 || !tipo) return { ok: false, erros };
  return {
    ok: true,
    dados: { tipo_origem: tipo, conta_origem: conta, categoria_codigo: categoria, observacao: observacao || null },
  };
}

export type Criterio = {
  centro_custo_id: string | null;
  metodo: MetodoReconhecimento;
  observacao: string | null;
};

// Ligar o percentual de conclusão exige a confirmação de quem valida e uma observação com a fonte.
export function validarCriterio(ler: Leitor): Validacao<Criterio> {
  const erros: Record<string, string> = {};
  const escopo = ler("escopo");
  const metodo = metodosReconhecimento.find((opcao) => opcao === ler("metodo"));
  const observacao = ler("observacao");
  const centro = escopo === escopoTenant ? null : formatoUuid.test(escopo) ? escopo.toLowerCase() : undefined;
  if (centro === undefined) erros.escopo = "Escolha todas as obras ou uma obra da lista.";
  if (!metodo) erros.metodo = "Escolha o critério.";
  if (metodo === "percentual_conclusao") {
    if (ler("confirmacao") !== "sim")
      erros.confirmacao = "Só o financeiro responsável pode validar. Marque a confirmação para continuar.";
    if (!observacao) erros.observacao = "Diga com quem e quando o critério foi validado (por exemplo, o contador).";
  }
  if (observacao.length > tamanhoMaximoObservacao)
    erros.observacao = `Use no máximo ${tamanhoMaximoObservacao} caracteres.`;
  if (Object.keys(erros).length > 0 || !metodo || centro === undefined) return { ok: false, erros };
  return { ok: true, dados: { centro_custo_id: centro, metodo, observacao: observacao || null } };
}
