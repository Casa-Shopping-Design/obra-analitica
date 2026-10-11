import "server-only";
import type { criarClienteServidor } from "@/lib/supabase/servidor";
import { ErroConsulta } from "@/lib/consultas/posicao";
import { limiteLinhasConsulta } from "@/lib/validador-sql";

type Cliente = Awaited<ReturnType<typeof criarClienteServidor>>;
type LinhaResposta = Record<string, string | number | null>;
type ResultadoSupabase = { data: unknown; error: { code: string } | null };

function lerLinhas(resultado: ResultadoSupabase): LinhaResposta[] {
  if (resultado.error) throw new ErroConsulta(resultado.error.code);
  return (resultado.data ?? []) as LinhaResposta[];
}

function primeiroDiaDoAnoEmBrasilia(): string {
  const ano = new Intl.DateTimeFormat("en-CA", { timeZone: "America/Sao_Paulo", year: "numeric" }).format(new Date());
  return `${ano}-01-01`;
}

// Perguntas prontas da visão por empresa. Cada função devolve o mesmo que o sql de mesmo id em
// lib/perguntas-prontas.ts, com filtros do cliente Supabase e o RLS de quem está logado.
export const consultasEmpresa = {
  async "caixa-lucro-empresas"(supabase: Cliente) {
    return lerLinhas(
      await supabase
        .schema("marts")
        .from("empresa_resumo")
        .select("nome, ultima_competencia, caixa_equivalentes, fluxo_operacional, lucro_liquido")
        .not("ultima_competencia", "is", null)
        .order("nome")
        .limit(limiteLinhasConsulta),
    );
  },

  async "lucro-mensal-empresas"(supabase: Cliente) {
    return lerLinhas(
      await supabase
        .schema("marts")
        .from("dre_societaria_mensal")
        .select("empresa, competencia, valor_mes")
        .eq("linha", "lucro_liquido")
        .gte("competencia", primeiroDiaDoAnoEmBrasilia())
        .order("empresa")
        .order("competencia")
        .limit(limiteLinhasConsulta),
    );
  },

  async "empresas-sem-fechamento"(supabase: Cliente) {
    return lerLinhas(
      await supabase
        .schema("marts")
        .from("empresa_resumo")
        .select("nome, ultima_competencia, diferenca_identidade, contas_sem_mapa")
        .or("diferenca_identidade.neq.0,contas_sem_mapa.gt.0")
        .order("nome")
        .limit(limiteLinhasConsulta),
    );
  },
};
