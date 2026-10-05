// Leitura do que o usuário digita em real e em percentual. Sem Supabase nem Next, para o vitest cobrir os
// casos de borda. O banco repete os mesmos limites em app.gravar_viabilidade e app.gravar_aliquota_imposto.

export const tetoValorDigitado = 99999999999.99;
export const tetoAliquotaPercentual = 20;

// Ponto só como separador de milhar, em grupos de três, para "1.5" não virar 15 sem ninguém perceber.
const formatoReal = /^(\d{1,3}(\.\d{3})*|\d+)(,\d{1,2})?$/;
const formatoPercentual = /^\d{1,2}(,\d{1,4})?$/;

const formatoValor = new Intl.NumberFormat("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const formatoAliquota = new Intl.NumberFormat("pt-BR", { minimumFractionDigits: 0, maximumFractionDigits: 4 });

function limpar(texto: unknown): string | null {
  if (typeof texto !== "string") return null;
  const limpo = texto.replace(/\s|R\$|%/g, "");
  return limpo === "" ? null : limpo;
}

// "1.234.567,89" vira 1234567.89. Recusa sinal, letras, mais de dois centavos e o que passa do teto da tabela.
export function lerNumeroDigitado(texto: unknown): number | null {
  const limpo = limpar(texto);
  if (limpo === null || !formatoReal.test(limpo)) return null;
  const numero = Number(limpo.replace(/\./g, "").replace(",", "."));
  return Number.isFinite(numero) && numero <= tetoValorDigitado ? numero : null;
}

// Na tela a alíquota é percentual ("6,32"); no banco é fração (0.0632), com seis casas no máximo.
export function lerAliquotaDigitada(texto: unknown): number | null {
  const limpo = limpar(texto);
  if (limpo === null || !formatoPercentual.test(limpo)) return null;
  const percentual = Number(limpo.replace(",", "."));
  if (!Number.isFinite(percentual) || percentual > tetoAliquotaPercentual) return null;
  return Math.round(percentual * 10000) / 1000000;
}

export function formatarNumeroDigitado(valor: number): string {
  return formatoValor.format(valor);
}

// Fração do banco de volta para o percentual da tela: 0.0632 vira "6,32".
export function formatarAliquotaDigitada(fracao: number): string {
  return formatoAliquota.format(Math.round(fracao * 1000000) / 10000);
}
