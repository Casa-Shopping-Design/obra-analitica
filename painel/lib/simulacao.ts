import { deslocarMes } from "./serie-fluxo";

// Parâmetros da simulação de venda do estoque. Vêm da URL, então só passam valores da lista;
// qualquer outra coisa volta ao padrão antes de chegar ao banco.

export const opcoesRitmo = [1, 2, 4, 6, 8] as const;
export const opcoesDesconto = [0, 5, 10] as const;

export type Ritmo = (typeof opcoesRitmo)[number];
export type DescontoPercentual = (typeof opcoesDesconto)[number];

function primeiroValor(valor: string | string[] | undefined): number {
  return Number(Array.isArray(valor) ? valor[0] : valor);
}

export function lerRitmo(valor: string | string[] | undefined, padrao: Ritmo): Ritmo {
  const numero = primeiroValor(valor);
  return opcoesRitmo.find((opcao) => opcao === numero) ?? padrao;
}

export function lerDesconto(valor: string | string[] | undefined): DescontoPercentual {
  const numero = primeiroValor(valor);
  return opcoesDesconto.find((opcao) => opcao === numero) ?? 0;
}

// Opção de ritmo mais próxima do que a obra vendeu nos últimos 6 meses, para a tela abrir perto da realidade.
export function ritmoMaisProximo(vendasMedia6m: number | null): Ritmo {
  if (vendasMedia6m === null || vendasMedia6m <= 0) return opcoesRitmo[0];
  return opcoesRitmo.reduce((melhor, opcao) =>
    Math.abs(opcao - vendasMedia6m) < Math.abs(melhor - vendasMedia6m) ? opcao : melhor,
  );
}

// O gráfico começa 12 meses antes de hoje e vai até o último mês com movimento, que pode passar de quatro
// anos quando o ritmo é baixo. Só recorta; os saldos já vêm acumulados do banco desde o início da obra.
export function recortarSerie<T extends { competencia: string }>(serie: T[], mesAtual: string, mesesAntes = 12): T[] {
  const inicio = deslocarMes(mesAtual, -mesesAntes);
  return serie.filter((ponto) => ponto.competencia.slice(0, 7) >= inicio);
}
