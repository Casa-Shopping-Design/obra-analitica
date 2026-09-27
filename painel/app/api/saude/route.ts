import * as Sentry from "@sentry/nextjs";
import { NextResponse, type NextRequest } from "next/server";
import { buscarSaudeCarga } from "@/lib/consultas/carga";
import { avaliarIdadeCarga } from "@/lib/idade-carga";
import { registrar } from "@/lib/log";

const rota = "/api/saude";

// Pública de propósito: o monitor de disponibilidade chama sem login. Devolve só o commit e datas,
// nada que identifique tenant ou obra. 503 quando o banco não responde ou a carga está atrasada.
export async function GET(request: NextRequest) {
  const inicio = performance.now();
  const idRequisicao = request.headers.get("x-id-requisicao");
  const commit = process.env.VERCEL_GIT_COMMIT_SHA ?? "local";

  let ultimaCargaEm: string | null = null;
  let bancoResponde = true;
  try {
    ultimaCargaEm = await buscarSaudeCarga(5000);
  } catch (erro) {
    bancoResponde = false;
    Sentry.captureException(erro, { tags: { id_requisicao: idRequisicao ?? "ausente", rota } });
  }

  const { idadeHoras, atrasada } = avaliarIdadeCarga(ultimaCargaEm, new Date());
  const ok = bancoResponde && !atrasada;

  registrar(ok ? "info" : "error", ok ? "saude ok" : bancoResponde ? "carga atrasada" : "banco sem resposta", {
    id_requisicao: idRequisicao,
    rota,
    resultado: ok ? "ok" : "indisponivel",
    duracao_ms: Math.round(performance.now() - inicio),
  });

  return NextResponse.json(
    { ok, commit, ultima_carga_em: ultimaCargaEm, idade_horas: idadeHoras },
    { status: ok ? 200 : 503, headers: { "cache-control": "no-store" } },
  );
}
