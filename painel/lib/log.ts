import pino from "pino";

export type NivelLog = "info" | "warn" | "error";
export type ResultadoLog = "ok" | "negado" | "erro" | "indisponivel";

// Tipo fechado de propósito: e-mail, token, cookie ou SQL não têm campo onde entrar.
export type CamposLog = {
  id_requisicao: string | null;
  rota: string;
  resultado: ResultadoLog;
  user_id?: string | null;
  tenant_id?: string | null;
  duracao_ms?: number;
  codigo_erro?: string;
};

const registrador = pino({
  base: null,
  messageKey: "mensagem",
  timestamp: pino.stdTimeFunctions.isoTime,
  formatters: { level: (rotulo) => ({ nivel: rotulo }) },
});

export function registrar(nivel: NivelLog, mensagem: string, campos: CamposLog): void {
  registrador[nivel]({ user_id: null, tenant_id: null, duracao_ms: null, ...campos }, mensagem);
}
