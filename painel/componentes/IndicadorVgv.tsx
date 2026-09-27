import { ExplicacaoIndicador } from "@/componentes/ExplicacaoIndicador";
import type { ValoresVgv } from "@/lib/consultas/posicao";
import { formatarPercentual, formatarReal } from "@/lib/formatar";

// A barra é SVG com largura em atributo: a CSP de produção barra style inline vindo do servidor.
function BarraVendido({ fracao }: { fracao: number }) {
  const largura = Math.min(Math.max(fracao, 0), 1) * 1000;
  return (
    <svg viewBox="0 0 1000 10" preserveAspectRatio="none" className="h-2.5 w-full overflow-hidden rounded-full" aria-hidden="true" focusable="false">
      <rect width="1000" height="10" className="fill-[#dcebe1]" />
      <rect width={largura} height="10" className="fill-saida" />
    </svg>
  );
}

function Amostra({ classe }: { classe: string }) {
  return <span aria-hidden="true" className={`inline-block size-2.5 shrink-0 rounded-sm ${classe}`} />;
}

// VGV total em destaque, a parte já vendida na barra e as duas parcelas que somam o total.
// Nada é somado aqui: os três valores vêm prontos de marts.posicao_financeira_obra.
export function IndicadorVgv({ valores, emCartao = false }: { valores: ValoresVgv; emCartao?: boolean }) {
  const moldura = emCartao ? "rounded-xl border border-borda bg-superficie p-5" : "";
  const fracao = valores.pct_vgv_vendido === null ? null : Number(valores.pct_vgv_vendido);

  return (
    <div className={`flex min-w-0 flex-col gap-2.5 ${moldura}`}>
      <div className="flex flex-wrap items-end justify-between gap-x-6 gap-y-1">
        <div className="flex flex-col gap-1.5">
          <p className="flex items-center gap-1.5 text-sm text-suave">
            VGV
            <ExplicacaoIndicador chave="vgv_total" rotulo="VGV" />
          </p>
          <p className="text-2xl font-semibold break-words">{formatarReal(Number(valores.vgv_total))}</p>
        </div>
        <p className="text-sm text-suave">
          {fracao === null ? "Sem unidade com preço" : `${formatarPercentual(fracao)} vendido`}
        </p>
      </div>
      {fracao !== null && <BarraVendido fracao={fracao} />}
      <dl className="flex flex-wrap gap-x-6 gap-y-1 text-sm">
        <div className="flex items-center gap-1.5">
          <Amostra classe="bg-saida" />
          <dt className="text-suave">Vendido</dt>
          <dd className="font-medium tabular-nums">{formatarReal(Number(valores.vgv_vendido))}</dd>
        </div>
        <div className="flex items-center gap-1.5">
          <Amostra classe="border border-entrada bg-[#dcebe1]" />
          <dt className="text-suave">Em estoque</dt>
          <dd className="font-medium tabular-nums">{formatarReal(Number(valores.estoque_a_vender))}</dd>
        </div>
      </dl>
    </div>
  );
}
