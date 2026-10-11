// Regras puras do mapa conta contábil para linha de relatório: leitura das views, opções por grupo,
// validação do lote antes da Server Action chamar o banco e tradução do erro.

import { numeroOuNulo } from "./consultas/resumo-origem";
import { mensagensMapa } from "./mensagens-empresa";

export type ContaMapa = {
  conta: string;
  contaReduzida: number | null;
  nome: string;
  grupo: string;
  analitica: boolean;
  linha: string | null;
  linhaEfetiva: string | null;
  demonstrativos: string | null;
};

export const colunasMapaContas = "conta, conta_reduzida, nome, grupo, analitica, linha, linha_efetiva, demonstrativos";

function textoOuNulo(valor: unknown): string | null {
  return valor === null || valor === undefined || valor === "" ? null : String(valor);
}

export function lerContaMapa(linha: Record<string, unknown>): ContaMapa {
  return {
    conta: String(linha.conta),
    contaReduzida: numeroOuNulo(linha.conta_reduzida),
    nome: String(linha.nome ?? ""),
    grupo: String(linha.grupo ?? ""),
    analitica: linha.analitica === true,
    linha: textoOuNulo(linha.linha),
    linhaEfetiva: textoOuNulo(linha.linha_efetiva),
    demonstrativos: textoOuNulo(linha.demonstrativos),
  };
}

export type LinhaCatalogo = { linha: string; rotulo: string; grupoConta: string; demonstrativo: string };

export const colunasLinhaCatalogo = "linha, rotulo, grupo_conta, demonstrativo, ordem";

export function lerLinhaCatalogo(linha: Record<string, unknown>): LinhaCatalogo {
  return {
    linha: String(linha.linha),
    rotulo: String(linha.rotulo ?? linha.linha),
    grupoConta: String(linha.grupo_conta ?? ""),
    demonstrativo: String(linha.demonstrativo ?? ""),
  };
}

const rotulosDemonstrativo: Record<string, string> = {
  fontes_usos: "Fontes e Usos",
  dre: "DRE",
  custo_incorrido: "Custo incorrido",
  fora: "Fora dos relatórios",
};

export function rotuloDemonstrativo(demonstrativo: string): string {
  return rotulosDemonstrativo[demonstrativo] ?? demonstrativo;
}

export type OpcaoLinha = { linha: string; rotulo: string };

// O grupo da conta é o primeiro dígito do código ("1.1.1.02.0001" é do grupo 1), o mesmo critério de
// grupo_conta no catálogo de linhas.
export function grupoContaDe(conta: string): string {
  const primeiro = conta.trim().charAt(0);
  return /\d/.test(primeiro) ? primeiro : "";
}

// Uma lista de opções por grupo. A mesma linha aparece em mais de um demonstrativo (estoque e CMV entram também
// no custo incorrido), mas o mapa guarda só o id, então a opção sai uma vez, com os demonstrativos no rótulo.
// O(n) sobre o catálogo, com dicionário.
export function opcoesPorGrupo(catalogo: LinhaCatalogo[]): Map<string, OpcaoLinha[]> {
  const porLinha = new Map<string, { rotulo: string; grupoConta: string; demonstrativos: string[] }>();
  for (const item of catalogo) {
    const existente = porLinha.get(item.linha);
    if (existente) {
      existente.demonstrativos.push(rotuloDemonstrativo(item.demonstrativo));
      continue;
    }
    porLinha.set(item.linha, {
      rotulo: item.rotulo,
      grupoConta: item.grupoConta,
      demonstrativos: [rotuloDemonstrativo(item.demonstrativo)],
    });
  }
  const grupos = new Map<string, OpcaoLinha[]>();
  for (const [linha, item] of porLinha) {
    const opcoes = grupos.get(item.grupoConta) ?? [];
    opcoes.push({ linha, rotulo: `${item.rotulo} (${item.demonstrativos.join(", ")})` });
    grupos.set(item.grupoConta, opcoes);
  }
  return grupos;
}

export type ItemMapa = { conta: string; linha: string | null };

export const maximoItensMapa = 500;

// Mesmo formato que o banco aceita: código com dígitos e pontos, linha com o id do catálogo.
const formatoConta = /^\d+(\.\d+)*$/;
const formatoLinha = /^[a-z][a-z0-9_]{0,62}$/;

export type MotivoRecusaMapa = "vazio" | "limite" | "formato" | "repetida";
export type LeituraItensMapa = { ok: true; itens: ItemMapa[] } | { ok: false; motivo: MotivoRecusaMapa };

function itemValido(entrada: unknown): ItemMapa | null {
  if (typeof entrada !== "object" || entrada === null || Array.isArray(entrada)) return null;
  const { conta, linha, ...sobra } = entrada as Record<string, unknown>;
  if (Object.keys(sobra).length > 0) return null;
  if (typeof conta !== "string" || conta.length > 40 || !formatoConta.test(conta)) return null;
  if (linha === null) return { conta, linha: null };
  if (typeof linha !== "string" || !formatoLinha.test(linha)) return null;
  return { conta, linha };
}

// Confere só o formato; se a linha existe no catálogo e vale para o grupo da conta, quem decide é a função do
// banco, que responde 22023. Conta repetida no mesmo lote é recusada para a última não vencer em silêncio.
export function validarItensMapa(entrada: unknown): LeituraItensMapa {
  if (!Array.isArray(entrada) || entrada.length === 0) return { ok: false, motivo: "vazio" };
  if (entrada.length > maximoItensMapa) return { ok: false, motivo: "limite" };
  const itens: ItemMapa[] = [];
  const contas = new Set<string>();
  for (const bruto of entrada) {
    const item = itemValido(bruto);
    if (!item) return { ok: false, motivo: "formato" };
    if (contas.has(item.conta)) return { ok: false, motivo: "repetida" };
    contas.add(item.conta);
    itens.push(item);
  }
  return { ok: true, itens };
}

// O formulário manda as mudanças num campo só, em JSON. Texto acima do teto nem passa pelo parser.
const tetoCaracteresItens = maximoItensMapa * 120;

export function lerFormularioMapa(formulario: FormData): LeituraItensMapa {
  const texto = formulario.get("itens");
  if (typeof texto !== "string" || texto.trim() === "") return { ok: false, motivo: "vazio" };
  if (texto.length > tetoCaracteresItens) return { ok: false, motivo: "limite" };
  let entrada: unknown;
  try {
    entrada = JSON.parse(texto);
  } catch {
    return { ok: false, motivo: "formato" };
  }
  return validarItensMapa(entrada);
}

export function mensagemRecusaMapa(motivo: MotivoRecusaMapa): string {
  if (motivo === "vazio") return mensagensMapa.semMudancas;
  if (motivo === "limite") return mensagensMapa.limite;
  return mensagensMapa.formato;
}

// Só o código decide a mensagem; o texto do banco nunca chega à tela.
export function mensagemErroMapa(codigo: string | undefined): string {
  if (codigo === "42501") return mensagensMapa.semPermissao;
  if (codigo === "22023") return mensagensMapa.foraDoCatalogo;
  return mensagensMapa.gravacaoIndisponivel;
}

export function resultadoErroMapa(codigo: string | undefined): "negado" | "recusada" | "erro" {
  if (codigo === "42501") return "negado";
  if (codigo === "22023") return "recusada";
  return "erro";
}

// Só as contas da página atual cuja escolha mudou em relação à linha própria gravada. Conta que saiu da
// página depois de gravar (filtro "sem mapa") não volta como mudança. "" no seletor é "sem linha própria".
export function mudancasMapa(originais: Map<string, string | null>, escolhas: Map<string, string>): ItemMapa[] {
  const itens: ItemMapa[] = [];
  for (const [conta, escolha] of escolhas) {
    if (!originais.has(conta)) continue;
    const linha = escolha === "" ? null : escolha;
    if (originais.get(conta) !== linha) itens.push({ conta, linha });
  }
  return itens;
}

export const gruposConta = [
  { id: "ativo", rotulo: "Ativo" },
  { id: "passivo", rotulo: "Passivo" },
  { id: "receita", rotulo: "Receita" },
  { id: "despesa", rotulo: "Despesa e custo" },
  { id: "transitoria", rotulo: "Transitória" },
] as const;

export type FiltroMapa = { semMapa: boolean; grupo: string | null; pagina: number };

export const contasPorPagina = 200;
// Um plano de contas real tem poucas páginas; número absurdo na URL volta para a primeira.
const paginaMaxima = 1000;

export function lerFiltroMapa(busca: Record<string, string | string[] | undefined>): FiltroMapa {
  const valor = (chave: string) => {
    const bruto = busca[chave];
    return Array.isArray(bruto) ? bruto[0] : bruto;
  };
  const grupo = valor("grupo");
  const pagina = Number(valor("pagina"));
  return {
    semMapa: valor("sem_mapa") === "1",
    grupo: gruposConta.some((item) => item.id === grupo) ? (grupo as string) : null,
    pagina: Number.isInteger(pagina) && pagina > 0 && pagina <= paginaMaxima ? pagina : 1,
  };
}

export function enderecoMapa(filtro: FiltroMapa, mudancas: Partial<FiltroMapa> = {}): string {
  const alvo = { ...filtro, ...mudancas };
  const busca = new URLSearchParams();
  if (alvo.semMapa) busca.set("sem_mapa", "1");
  if (alvo.grupo) busca.set("grupo", alvo.grupo);
  if (alvo.pagina > 1) busca.set("pagina", String(alvo.pagina));
  const texto = busca.toString();
  return texto ? `/empresas/mapa-contas?${texto}` : "/empresas/mapa-contas";
}
