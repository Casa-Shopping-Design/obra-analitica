import "server-only";
import { cache } from "react";
import {
  colunasPreferencias,
  colunasSimulacao,
  lerPadroesSimulacao,
  lerPreferenciasTenant,
  preferenciasProduto,
  tabelasConfiguracao,
  type AlteracaoConfiguracao,
  type OpcaoParametro,
  type PadroesSimulacao,
  type Parametro,
  type PreferenciasTenant,
  type RegistroValor,
  type RotuloPersonalizado,
  type Subcategoria,
  type ValorCodigoOrigem,
} from "@/lib/configuracao";
import { ErroConsulta } from "@/lib/consultas/posicao";
import { paraNumeroOuNulo } from "@/lib/consultas/referencia";
import { criarClienteServidor } from "@/lib/supabase/servidor";

// Tabela ou view que ainda não existe no banco: 42P01 no Postgres, PGRST205 no cache de esquema da API.
export function objetoAusente(codigo: string | undefined): boolean {
  return codigo === "42P01" || codigo === "PGRST205";
}

type LinhaParametro = Omit<Parametro, "minimo" | "maximo" | "opcoes"> & {
  minimo: unknown;
  maximo: unknown;
  opcoes: unknown;
};

function lerOpcoes(bruto: unknown): OpcaoParametro[] | null {
  if (!Array.isArray(bruto)) return null;
  return bruto
    .filter((item): item is Record<string, unknown> => typeof item === "object" && item !== null)
    .map((item) => ({
      valor: String(item.valor),
      rotulo: typeof item.rotulo === "string" ? item.rotulo : String(item.valor),
      descricao: typeof item.descricao === "string" ? item.descricao : null,
    }));
}

// Catálogo global, algumas dezenas de linhas; o cache vale por requisição (página e ação pedem o mesmo).
export const listarCatalogo = cache(async (): Promise<Parametro[]> => {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("app")
    .from("parametro")
    .select(
      "codigo, grupo, nome, descricao, tipo, opcoes, minimo, maximo, padrao, aceita_nulo, escopo, ordem, exige_validacao_financeira",
    )
    .order("ordem");
  if (error) throw new ErroConsulta(error.code);
  return ((data ?? []) as LinhaParametro[]).map((linha) => ({
    ...linha,
    opcoes: lerOpcoes(linha.opcoes),
    minimo: paraNumeroOuNulo(linha.minimo),
    maximo: paraNumeroOuNulo(linha.maximo),
    ordem: Number(linha.ordem),
    aceita_nulo: Boolean(linha.aceita_nulo),
    exige_validacao_financeira: Boolean(linha.exige_validacao_financeira),
  }));
});

const formatoUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Valores da construtora e, com obra escolhida, os da obra. O RLS devolve só o tenant do JWT e as obras
// liberadas. O id entra no texto do filtro .or(), por isso só passa no formato de UUID.
export async function listarValoresParametro(centroId: string | null): Promise<RegistroValor[]> {
  const supabase = await criarClienteServidor();
  let consulta = supabase
    .schema("app")
    .from("parametro_valor")
    .select("id, centro_custo_id, codigo, valor, observacao, autor, atualizado_em");
  consulta =
    centroId && formatoUuid.test(centroId)
      ? consulta.or(`centro_custo_id.is.null,centro_custo_id.eq.${centroId}`)
      : consulta.is("centro_custo_id", null);
  const { data, error } = await consulta.order("codigo");
  if (error) throw new ErroConsulta(error.code);
  return (data ?? []) as RegistroValor[];
}

// Uma linha por tenant, já resolvida no banco (construtora e padrão). Qualquer falha devolve o comportamento
// anterior à configuração, para a tela nunca quebrar por causa de uma preferência.
export const buscarPreferenciasTenant = cache(async (): Promise<PreferenciasTenant> => {
  try {
    const supabase = await criarClienteServidor();
    const { data, error } = await supabase
      .schema("app")
      .from("parametros_tenant")
      .select(colunasPreferencias.join(", "))
      .limit(1)
      .maybeSingle<Record<string, unknown>>();
    if (error) return preferenciasProduto;
    return lerPreferenciasTenant(data);
  } catch {
    return preferenciasProduto;
  }
});

// Colunas de app.parametros_obra já resolvidas para uma obra (obra, construtora, produto). Nulo quando a
// leitura falha ou a obra não é visível; quem chama cai então no comportamento anterior à configuração.
export async function buscarParametrosObra(
  centroId: string,
  colunas: readonly string[],
): Promise<Record<string, unknown> | null> {
  try {
    const supabase = await criarClienteServidor();
    const { data, error } = await supabase
      .schema("app")
      .from("parametros_obra")
      .select(colunas.join(", "))
      .eq("centro_custo_id", centroId)
      .maybeSingle<Record<string, unknown>>();
    return error ? null : data;
  } catch {
    return null;
  }
}

export async function buscarPadroesSimulacao(centroId: string): Promise<PadroesSimulacao | null> {
  return lerPadroesSimulacao(await buscarParametrosObra(centroId, colunasSimulacao));
}

export type MapaCodigo = {
  dominio: string;
  codigo_origem: string;
  valor: string;
  rotulo: string | null;
  observacao: string | null;
  autor: string | null;
  atualizado_em: string | null;
};

// Poucos códigos por tenant (dezenas); a chave (tenant, domínio, código) ordena.
export async function listarMapaCodigos(): Promise<MapaCodigo[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("app")
    .from("mapa_codigo_origem")
    .select("dominio, codigo_origem, valor, rotulo, observacao, autor, atualizado_em")
    .order("dominio")
    .order("codigo_origem");
  if (error) throw new ErroConsulta(error.code);
  return (data ?? []) as MapaCodigo[];
}

// Valores aceitos em cada domínio e o que vale sem mapa; lista global de dez linhas.
export async function listarValoresCodigo(): Promise<ValorCodigoOrigem[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("app")
    .from("valor_codigo_origem")
    .select("dominio, valor, rotulo, ordem, valor_sem_mapa")
    .order("dominio")
    .order("ordem");
  if (error) throw new ErroConsulta(error.code);
  return ((data ?? []) as ValorCodigoOrigem[]).map((linha) => ({ ...linha, ordem: Number(linha.ordem) }));
}

export type PendenciaCodigo = {
  dominio: string;
  codigo_origem: string | null;
  quantidade_registros: number;
  valor_envolvido: number | null;
  valor_aplicado: string;
};

// Códigos vistos no staging sem mapa. A view agrega no banco por obra e código (poucas linhas: códigos
// desconhecidos x obras); a tela só soma as obras de cada código. Teto de linhas por segurança.
export async function listarPendenciasCodigo(): Promise<PendenciaCodigo[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("marts")
    .from("pendencia_codigo_origem")
    .select("dominio, codigo_origem, quantidade_registros, valor_envolvido, valor_aplicado")
    .order("dominio")
    .order("codigo_origem")
    .limit(500);
  if (error) throw new ErroConsulta(error.code);
  return ((data ?? []) as Record<string, unknown>[]).map((linha) => ({
    dominio: String(linha.dominio),
    codigo_origem: typeof linha.codigo_origem === "string" ? linha.codigo_origem : null,
    quantidade_registros: Number(linha.quantidade_registros),
    valor_envolvido: paraNumeroOuNulo(linha.valor_envolvido),
    valor_aplicado: String(linha.valor_aplicado),
  }));
}

// Rótulos próprios da construtora; poucas linhas. O cache serve o DRE e a configuração na mesma requisição.
export const listarRotulos = cache(async (): Promise<RotuloPersonalizado[]> => {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("app")
    .from("rotulo_personalizado")
    .select("contexto, chave, rotulo")
    .order("contexto")
    .order("chave");
  if (error) throw new ErroConsulta(error.code);
  return (data ?? []) as RotuloPersonalizado[];
});

export type ListaSubcategorias = { disponivel: boolean; linhas: Subcategoria[] };

// app.categoria_tenant nasce na 0011 revisada. Enquanto o banco não tiver a tabela, a tela avisa e segue.
export async function listarSubcategorias(): Promise<ListaSubcategorias> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("app")
    .from("categoria_tenant")
    .select("id, categoria_codigo, codigo, nome, ativa")
    .order("categoria_codigo")
    .order("codigo");
  if (error) {
    if (objetoAusente(error.code)) return { disponivel: false, linhas: [] };
    throw new ErroConsulta(error.code);
  }
  return { disponivel: true, linhas: (data ?? []) as Subcategoria[] };
}

// Últimas alterações de configuração. Só diretor e financeiro enxergam a auditoria; os demais recebem
// lista vazia pelo RLS. Filtro em tenant (RLS) e tabela, ordem por data, teto de linhas.
export async function listarHistoricoConfiguracao(limite = 30): Promise<AlteracaoConfiguracao[]> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("app")
    .from("auditoria_alteracao")
    .select("id, tabela, registro_id, operacao, antes, depois, autor, alterado_em")
    .in("tabela", tabelasConfiguracao)
    .order("alterado_em", { ascending: false })
    .limit(limite);
  if (error) throw new ErroConsulta(error.code);
  return (data ?? []) as AlteracaoConfiguracao[];
}
