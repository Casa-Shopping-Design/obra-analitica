import "server-only";
import { ErroConsulta } from "@/lib/consultas/posicao";
import { criarClienteServidor } from "@/lib/supabase/servidor";

export type MotivoRecusaReserva = "limite" | "teto";

export type Reserva = { ok: true; idPergunta: number } | { ok: false; motivo: MotivoRecusaReserva };

// A contagem por hora, a soma do dia e a gravação da linha 'pendente' acontecem numa função só do banco,
// sob bloqueio por usuário: duas perguntas ao mesmo tempo não passam do limite. A função levanta P0001
// com a mensagem 'limite' ou 'teto'; qualquer outro erro vira ErroConsulta, e não permissão.
export async function reservarPergunta(idRequisicao: string, pergunta: string): Promise<Reserva> {
  const supabase = await criarClienteServidor();
  const { data, error } = await supabase
    .schema("app")
    .rpc("reservar_pergunta", { p_id_requisicao: idRequisicao, p_pergunta: pergunta });

  if (error) {
    if (error.code === "P0001" && (error.message === "limite" || error.message === "teto")) {
      return { ok: false, motivo: error.message };
    }
    throw new ErroConsulta(error.code ?? "reserva_falhou");
  }
  if (typeof data !== "number") throw new ErroConsulta("reserva_sem_id");
  return { ok: true, idPergunta: data };
}
