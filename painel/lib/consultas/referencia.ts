import "server-only";
import { cache } from "react";
import { ErroConsulta } from "@/lib/consultas/posicao";
import { hojeEmSaoPaulo } from "@/lib/periodo";
import { criarClienteServidor } from "@/lib/supabase/servidor";

export type SituacaoCarga = {
  data_referencia: string;
  ultima_carga_em: string | null;
  horas_desde_carga: number | null;
  desatualizada: boolean;
};

export type CentroCusto = { id: string; nome: string; tipo: "obra" | "empresa" };

// O que a tela usa como data de referência: a do banco, ou a de hoje quando a consulta falhou.
export type Referencia = { situacao: SituacaoCarga | null; dataReferencia: string; doBanco: boolean };

// O PostgREST pode devolver numeric como texto; converter não arredonda.
export function paraNumero(valor: unknown): number {
  return Number(valor);
}

export function paraNumeroOuNulo(valor: unknown): number | null {
  return valor === null || valor === undefined ? null : Number(valor);
}

// Converte as colunas de valor de cada linha, sem mexer nas demais. O(linhas x colunas).
// A resposta de rpc chega tipada como linha ou lista; as funções de período sempre devolvem lista.
export function converterColunas<T>(
  resposta: unknown,
  colunas: readonly string[],
  anulaveis: readonly string[] = [],
): T[] {
  const linhas: unknown[] = Array.isArray(resposta) ? resposta : resposta ? [resposta] : [];
  return linhas.map((linha) => {
    const copia = { ...(linha as Record<string, unknown>) };
    for (const coluna of colunas) copia[coluna] = paraNumero(copia[coluna]);
    for (const coluna of anulaveis) copia[coluna] = paraNumeroOuNulo(copia[coluna]);
    return copia as T;
  });
}

// cache do React: o rodapé e a página pedem a mesma coisa na mesma requisição e o banco responde uma vez.
export const buscarSituacaoCarga = cache(async (): Promise<SituacaoCarga | null> => {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase.schema("app").rpc("situacao_carga").maybeSingle<SituacaoCarga>();
  if (error) throw new ErroConsulta(error.code);
  if (!data) return null;
  return {
    data_referencia: data.data_referencia,
    ultima_carga_em: data.ultima_carga_em,
    horas_desde_carga: paraNumeroOuNulo(data.horas_desde_carga),
    desatualizada: Boolean(data.desatualizada),
  };
});

export async function carregarReferencia(): Promise<Referencia> {
  try {
    const situacao = await buscarSituacaoCarga();
    if (situacao?.data_referencia) return { situacao, dataReferencia: situacao.data_referencia, doBanco: true };
    return { situacao, dataReferencia: hojeEmSaoPaulo(), doBanco: false };
  } catch {
    return { situacao: null, dataReferencia: hojeEmSaoPaulo(), doBanco: false };
  }
}

// Obras e o centro "Despesas sem obra" que o RLS libera, para os filtros. Poucas linhas por tenant.
export const listarCentrosCusto = cache(async (): Promise<CentroCusto[]> => {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("app")
    .from("centro_custo")
    .select("id, nome, tipo")
    .order("tipo", { ascending: false })
    .order("nome");
  if (error) throw new ErroConsulta(error.code);
  return data as CentroCusto[];
});

// Cada bloco da tela falha sozinho: erro vira nulo e a página mostra a mensagem daquele bloco.
export async function tentarConsulta<T>(consulta: Promise<T>): Promise<T | null> {
  try {
    return await consulta;
  } catch {
    return null;
  }
}

// Perfil do usuário no tenant do JWT, pela mesma função que o RLS usa. Só decide o que a tela oferece;
// quem autoriza a gravação é o RLS.
export const buscarPerfilAtual = cache(async (): Promise<string | null> => {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase.schema("app").rpc("perfil_atual");
  if (error) throw new ErroConsulta(error.code);
  return typeof data === "string" ? data : null;
});

export function podeGravarFinanceiro(perfil: string | null): boolean {
  return perfil === "diretor" || perfil === "financeiro";
}
