import { ExplicacaoIndicador } from "@/componentes/ExplicacaoIndicador";
import type { EstadoValor } from "@/componentes/financeiro/montar-dre";
import { ValorEstado } from "@/componentes/financeiro/ValorEstado";
import type { ChaveExplicacao } from "@/lib/explicacoes";

type ValorCartao = { rotulo?: string; estado: EstadoValor };

// Número principal no topo, rótulo curto acima e, embaixo, o período e a origem do número.
// Com mais de um valor (entrada direta e financiamento), cada um ganha sua linha, sem somar nada aqui.
export function CartaoFinanceiro({
  rotulo,
  chave,
  valores,
  contexto,
  selo,
  textoAusente,
  destaque,
}: {
  rotulo: string;
  chave: ChaveExplicacao;
  valores: ValorCartao[];
  destaque?: React.ReactNode;
  contexto?: React.ReactNode;
  selo?: React.ReactNode;
  textoAusente?: string;
}) {
  return (
    <div className="flex min-w-0 flex-col gap-1.5 rounded-xl border border-borda bg-superficie p-5">
      <p className="flex items-center gap-1.5 text-sm text-suave">
        {rotulo}
        <ExplicacaoIndicador chave={chave} rotulo={rotulo} />
      </p>
      {destaque !== undefined ? (
        <p className="text-2xl font-semibold break-words tabular-nums">{destaque}</p>
      ) : valores.length === 1 ? (
        <p className="text-2xl font-semibold break-words tabular-nums">
          <ValorEstado estado={valores[0].estado} textoAusente={textoAusente} />
        </p>
      ) : (
        <dl className="flex flex-col gap-0.5">
          {valores.map((item) => (
            <div key={item.rotulo} className="flex flex-wrap items-baseline justify-between gap-x-3">
              <dt className="text-sm text-suave">{item.rotulo}</dt>
              <dd className="text-lg font-semibold tabular-nums">
                <ValorEstado estado={item.estado} textoAusente={textoAusente} />
              </dd>
            </div>
          ))}
        </dl>
      )}
      {selo}
      {contexto && <p className="text-xs leading-snug text-suave">{contexto}</p>}
    </div>
  );
}
