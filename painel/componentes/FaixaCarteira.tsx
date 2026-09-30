import { CartaoIndicador } from "@/componentes/CartaoIndicador";
import { ExplicacaoIndicador } from "@/componentes/ExplicacaoIndicador";
import { IndicadorVgv } from "@/componentes/IndicadorVgv";
import type { PosicaoCarteira } from "@/lib/consultas/carteira";
import { formatarMes, formatarReal } from "@/lib/formatar";

// As somas vêm prontas de marts.posicao_carteira; a exposição é a das obras juntas, com o mês do pior saldo.
export function FaixaCarteira({ carteira }: { carteira: PosicaoCarteira }) {
  return (
    <section aria-labelledby="titulo-carteira" className="flex flex-col gap-5 rounded-xl border border-borda bg-superficie p-5">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 id="titulo-carteira" className="font-serif text-2xl font-semibold">
          Carteira
        </h2>
        <p className="text-sm text-suave">{carteira.obras} obras somadas</p>
      </div>
      <IndicadorVgv valores={carteira} />
      <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 xl:grid-cols-4">
        <CartaoIndicador rotulo="Caixa atual" chave="caixa_atual" valores={[{ valor: carteira.caixa_atual }]} />
        <div className="flex min-w-0 flex-col gap-1.5">
          <p className="flex items-center gap-1.5 text-sm text-suave">
            Exposição máxima da carteira
            <ExplicacaoIndicador chave="exposicao_carteira" rotulo="Exposição máxima da carteira" />
          </p>
          <p className="text-2xl font-semibold break-words">{formatarReal(carteira.exposicao_maxima)}</p>
          <p className="text-sm text-suave">
            {carteira.mes_exposicao_maxima ? `Pior mês: ${formatarMes(carteira.mes_exposicao_maxima)}. ` : ""}
            Somando as obras uma a uma daria {formatarReal(carteira.soma_exposicao_obras)}.
          </p>
        </div>
        <CartaoIndicador
          rotulo="Resultado projetado"
          chave="resultado_projetado"
          valores={[{ valor: carteira.resultado_projetado }]}
        />
        <CartaoIndicador
          rotulo="Vencido"
          chave="vencido"
          valores={[
            { rotulo: "Do comprador", valor: carteira.vencido_direto },
            { rotulo: "Repasse atrasado", valor: carteira.repasse_atrasado },
          ]}
        />
      </div>
    </section>
  );
}
