// Lê os formulários do estudo e da alíquota antes da chamada ao banco. Regra pura, sem Supabase nem Next:
// a Server Action só passa o FormData e recebe os valores prontos ou a recusa.
import { linhasDigitaveis, type LinhaDigitavel } from "./dre";
import { lerAliquotaDigitada, lerNumeroDigitado } from "./numero-digitado";

export const tamanhoMaximoDescricao = 120;

const formatoUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const formatoDataIso = /^\d{4}-\d{2}-\d{2}$/;

export type EstudoDigitado = {
  centroCustoId: string;
  descricao: string | null;
  dataBase: string;
  linhas: Record<LinhaDigitavel, number>;
};

export type AliquotaDigitada = { centroCustoId: string; vigenciaInicio: string; aliquota: number };

export type LeituraFormulario<T> = { ok: true; valores: T } | { ok: false; motivo: "obra" | "valor" };

// "aaaa-mm-dd" no fuso de Brasília: a data-base de hoje à noite não pode cair em amanhã por causa do UTC.
export function hojeEmBrasilia(): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Sao_Paulo" }).format(new Date());
}

export function lerIdObraDigitado(valor: unknown): string | null {
  return typeof valor === "string" && formatoUuid.test(valor) ? valor.toLowerCase() : null;
}

// Aceita só o formato do input type="date" e recusa data que não existe ou que está no futuro.
export function lerDataDigitada(valor: unknown, hoje: string = hojeEmBrasilia()): string | null {
  if (typeof valor !== "string" || !formatoDataIso.test(valor)) return null;
  const [ano, mes, dia] = valor.split("-").map(Number);
  const data = new Date(Date.UTC(ano, mes - 1, dia));
  const existe = data.getUTCFullYear() === ano && data.getUTCMonth() === mes - 1 && data.getUTCDate() === dia;
  return existe && valor <= hoje ? valor : null;
}

function lerDescricao(valor: unknown): string | null | undefined {
  if (typeof valor !== "string") return null;
  const limpa = valor.trim();
  if (limpa === "") return null;
  return limpa.length <= tamanhoMaximoDescricao ? limpa : undefined;
}

export function lerFormularioEstudo(formulario: FormData, hoje?: string): LeituraFormulario<EstudoDigitado> {
  const centroCustoId = lerIdObraDigitado(formulario.get("centro_custo_id"));
  if (centroCustoId === null) return { ok: false, motivo: "obra" };

  const descricao = lerDescricao(formulario.get("descricao"));
  const dataBase = lerDataDigitada(formulario.get("data_base"), hoje);
  if (descricao === undefined || dataBase === null) return { ok: false, motivo: "valor" };

  const linhas = {} as Record<LinhaDigitavel, number>;
  for (const linha of linhasDigitaveis) {
    const valor = lerNumeroDigitado(formulario.get(linha));
    if (valor === null) return { ok: false, motivo: "valor" };
    linhas[linha] = valor;
  }
  return { ok: true, valores: { centroCustoId, descricao, dataBase, linhas } };
}

export function lerFormularioAliquota(formulario: FormData, hoje?: string): LeituraFormulario<AliquotaDigitada> {
  const centroCustoId = lerIdObraDigitado(formulario.get("centro_custo_id"));
  if (centroCustoId === null) return { ok: false, motivo: "obra" };

  const aliquota = lerAliquotaDigitada(formulario.get("aliquota"));
  const vigenciaInicio = lerDataDigitada(formulario.get("vigencia_inicio"), hoje);
  if (aliquota === null || vigenciaInicio === null) return { ok: false, motivo: "valor" };
  return { ok: true, valores: { centroCustoId, vigenciaInicio, aliquota } };
}
