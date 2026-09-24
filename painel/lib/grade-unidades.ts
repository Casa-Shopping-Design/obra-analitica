// Situações de marts.mapa_unidades (migration 0004). O banco já traduz o código do ERP de origem:
// D disponível, C reservada, P proposta, V/O/G vendida, o resto fora de venda.
export const situacoesUnidade = ["disponivel", "reservada", "proposta", "vendida", "indisponivel"] as const;
export type SituacaoUnidade = (typeof situacoesUnidade)[number];

export const rotulosSituacao: Record<SituacaoUnidade, { nome: string; abreviado: string }> = {
  disponivel: { nome: "Disponível", abreviado: "Disp." },
  reservada: { nome: "Reservada", abreviado: "Res." },
  proposta: { nome: "Proposta", abreviado: "Prop." },
  vendida: { nome: "Vendida", abreviado: "Vend." },
  indisponivel: { nome: "Fora de venda", abreviado: "Fora" },
};

export type OrigemValor = "contrato" | "tabela" | "cadastro";

export const rotulosOrigemValor: Record<OrigemValor, string> = {
  contrato: "Valor do contrato de venda.",
  tabela: "Valor da tabela de preço corrigido pelo índice do mês.",
  cadastro: "Valor sugerido no cadastro da unidade.",
};

export type UnidadeMapa = {
  unidade_id: number;
  unidade: string;
  tipologia: string | null;
  area_privativa: number | null;
  situacao: SituacaoUnidade;
  valor: number | null;
  origem_valor: OrigemValor | null;
  valor_m2: number | null;
  tabela: string | null;
  indice: string | null;
  indice_referencia: string | null;
  indice_valor: number | null;
};

export type BlocoTipologia = {
  tipologia: string;
  posicoes: number[];
  andares: { andar: number; celulas: (UnidadeMapa | null)[] }[];
};

export type GradeUnidades = {
  blocos: BlocoTipologia[];
  foraDoPadrao: UnidadeMapa[];
  totais: Record<SituacaoUnidade, number>;
};

export function normalizarSituacao(situacao: string | null): SituacaoUnidade {
  return situacoesUnidade.find((conhecida) => conhecida === situacao) ?? "indisponivel";
}

// Nome no padrão TIPO-AAPP: andar nos dois primeiros dígitos, posição nos dois últimos.
export function lerNomeUnidade(nome: string): { tipologia: string; andar: number; posicao: number } | null {
  const partes = /^(.+)-(\d{2})(\d{2})$/.exec(nome.trim());
  if (!partes) return null;
  return { tipologia: partes[1], andar: Number(partes[2]), posicao: Number(partes[3]) };
}

export function rotuloAndar(andar: number): string {
  return andar === 0 ? "Térreo" : `${andar}º andar`;
}

// O(u log u): uma passada para agrupar em dicionários e a ordenação de andares e posições.
// u é o número de unidades da obra, na casa de centenas.
export function montarGrade(unidades: UnidadeMapa[]): GradeUnidades {
  const totais = Object.fromEntries(situacoesUnidade.map((situacao) => [situacao, 0])) as Record<
    SituacaoUnidade,
    number
  >;
  const porTipologia = new Map<string, Map<number, Map<number, UnidadeMapa>>>();
  const foraDoPadrao: UnidadeMapa[] = [];

  for (const unidade of unidades) {
    totais[unidade.situacao] += 1;
    const nome = lerNomeUnidade(unidade.unidade);
    if (!nome) {
      foraDoPadrao.push(unidade);
      continue;
    }
    const andares = porTipologia.get(nome.tipologia) ?? new Map<number, Map<number, UnidadeMapa>>();
    porTipologia.set(nome.tipologia, andares);
    const posicoes = andares.get(nome.andar) ?? new Map<number, UnidadeMapa>();
    andares.set(nome.andar, posicoes);
    // Nome repetido não pode esconder uma unidade atrás da outra na mesma célula.
    if (posicoes.has(nome.posicao)) {
      foraDoPadrao.push(unidade);
      continue;
    }
    posicoes.set(nome.posicao, unidade);
  }

  const blocos = [...porTipologia.entries()]
    .sort(([a], [b]) => a.localeCompare(b, "pt-BR", { numeric: true }))
    .map(([tipologia, andares]) => {
      const posicoes = [...new Set([...andares.values()].flatMap((linha) => [...linha.keys()]))].sort((a, b) => a - b);
      return {
        tipologia,
        posicoes,
        // Andar mais alto em cima, como na fachada.
        andares: [...andares.entries()]
          .sort(([a], [b]) => b - a)
          .map(([andar, linha]) => ({ andar, celulas: posicoes.map((posicao) => linha.get(posicao) ?? null) })),
      };
    });

  return { blocos, foraDoPadrao, totais };
}
