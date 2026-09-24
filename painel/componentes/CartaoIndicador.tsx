import { ExplicacaoIndicador } from "@/componentes/ExplicacaoIndicador";
import type { PosicaoObra } from "@/lib/consultas/posicao";
import type { ChaveExplicacao } from "@/lib/explicacoes";
import { formatarReal } from "@/lib/formatar";

type ValorIndicador = { rotulo?: string; valor: number };

// Com um valor, ele vem grande no topo; com mais de um (vencido do comprador e do banco), cada um
// ganha sua linha com rótulo, sem somar nada aqui.
export function CartaoIndicador({
  rotulo,
  chave,
  valores,
  emCartao = false,
}: {
  rotulo: string;
  chave: ChaveExplicacao;
  valores: ValorIndicador[];
  emCartao?: boolean;
}) {
  const moldura = emCartao ? "rounded-xl border border-borda bg-superficie p-5" : "";
  return (
    <div className={`flex min-w-0 flex-col gap-1.5 ${moldura}`}>
      <p className="flex items-center gap-1.5 text-sm text-suave">
        {rotulo}
        <ExplicacaoIndicador chave={chave} rotulo={rotulo} />
      </p>
      {valores.length === 1 ? (
        <p className="text-2xl font-semibold break-words">{formatarReal(valores[0].valor)}</p>
      ) : (
        <dl className="flex flex-col gap-0.5">
          {valores.map((item) => (
            <div key={item.rotulo} className="flex flex-wrap items-baseline justify-between gap-x-3">
              <dt className="text-sm text-suave">{item.rotulo}</dt>
              <dd className="text-lg font-semibold">{formatarReal(item.valor)}</dd>
            </div>
          ))}
        </dl>
      )}
    </div>
  );
}

// Os quatro números que resumem uma obra, na visão geral e no cabeçalho da tela da obra.
export function IndicadoresObra({ posicao, emCartao = false }: { posicao: PosicaoObra; emCartao?: boolean }) {
  return (
    <>
      <CartaoIndicador rotulo="Caixa atual" chave="caixa_atual" emCartao={emCartao} valores={[{ valor: Number(posicao.caixa_atual) }]} />
      <CartaoIndicador
        rotulo="Exposição máxima"
        chave="exposicao_maxima"
        emCartao={emCartao}
        valores={[{ valor: Number(posicao.exposicao_maxima) }]}
      />
      <CartaoIndicador
        rotulo="Resultado projetado"
        chave="resultado_projetado"
        emCartao={emCartao}
        valores={[{ valor: Number(posicao.resultado_projetado) }]}
      />
      <CartaoIndicador
        rotulo="Vencido"
        chave="vencido"
        emCartao={emCartao}
        valores={[
          { rotulo: "Do comprador", valor: Number(posicao.vencido_direto) },
          { rotulo: "Repasse atrasado", valor: Number(posicao.repasse_atrasado) },
        ]}
      />
    </>
  );
}
