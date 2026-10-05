"use client";

import { useActionState } from "react";
import { salvarAliquota, type EstadoAliquota } from "@/app/(painel)/obras/[id]/dre/estudo/acoes";

type Propriedades = { centroCustoId: string; aliquota: string; hoje: string; aviso: string };

const estadoInicial: EstadoAliquota = { erro: null, sucesso: null };

const classeCampo =
  "min-h-11 rounded-lg border border-borda bg-superficie px-3.5 text-[15px] text-texto focus-visible:border-texto";

// A alíquota entra em percentual, como a construtora fala ("6,32%"); a Server Action converte em fração.
export function FormularioAliquota({ centroCustoId, aliquota, hoje, aviso }: Propriedades) {
  const [estado, acao, enviando] = useActionState(salvarAliquota, estadoInicial);
  const idAviso = estado.erro ? "erro-aliquota" : estado.sucesso ? "sucesso-aliquota" : undefined;

  return (
    <form action={acao} className="flex flex-col gap-4" noValidate aria-describedby={idAviso}>
      <input type="hidden" name="centro_custo_id" value={centroCustoId} />
      <p className="text-sm text-suave">{aviso}</p>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div className="flex flex-col gap-1.5">
          <label htmlFor="aliquota" className="text-sm font-medium">
            Alíquota sobre a receita (%)
          </label>
          <input
            id="aliquota"
            name="aliquota"
            type="text"
            inputMode="decimal"
            autoComplete="off"
            required
            defaultValue={aliquota}
            placeholder="0,00"
            className={`${classeCampo} text-right tabular-nums`}
          />
          <p className="text-xs text-suave">De 0 a 20, com até quatro casas depois da vírgula.</p>
        </div>
        <div className="flex flex-col gap-1.5">
          <label htmlFor="vigencia_inicio" className="text-sm font-medium">
            Vale a partir de
          </label>
          <input
            id="vigencia_inicio"
            name="vigencia_inicio"
            type="date"
            required
            max={hoje}
            defaultValue={hoje}
            className={classeCampo}
          />
          <p className="text-xs text-suave">Hoje ou anterior. A alíquota mais recente em vigor é a que a DRE usa.</p>
        </div>
      </div>

      {estado.erro && (
        <p id="erro-aliquota" role="alert" className="rounded-lg border border-alerta px-3.5 py-2.5 text-sm text-alerta">
          {estado.erro}
        </p>
      )}
      {estado.sucesso && (
        <p id="sucesso-aliquota" role="status" className="rounded-lg border border-entrada px-3.5 py-2.5 text-sm text-entrada">
          {estado.sucesso}
        </p>
      )}

      <button
        type="submit"
        disabled={enviando}
        className="min-h-12 w-fit cursor-pointer rounded-lg bg-menu px-6 text-base font-semibold text-menu-texto disabled:cursor-wait disabled:opacity-70"
      >
        {enviando ? "Gravando..." : "Gravar alíquota"}
      </button>
    </form>
  );
}
