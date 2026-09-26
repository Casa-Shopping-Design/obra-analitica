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

// Maior aporte da projeção (marts.resumo_projecao_obra), a mesma fonte da tela de fluxo e do assistente.
// Nulo quando a projeção não carregou para a obra.
export type AporteProjetado = { valor: number; parcial: boolean } | null;

// Os quatro números que resumem uma obra, na visão geral e no cabeçalho da tela da obra. Com aporte
// informado, o aporte vem da projeção; sem ele (tela da obra ainda não migrada), da posição.
export function IndicadoresObra({
  posicao,
  aporte,
  emCartao = false,
}: {
  posicao: PosicaoObra;
  aporte?: AporteProjetado;
  emCartao?: boolean;
}) {
  return (
    <>
      <CartaoIndicador
        rotulo="Caixa realizado acumulado"
        chave="caixa_atual"
        emCartao={emCartao}
        valores={[{ valor: Number(posicao.caixa_atual) }]}
      />
      {aporte === undefined ? (
        <CartaoIndicador
          rotulo="Exposição máxima"
          chave="exposicao_maxima"
          emCartao={emCartao}
          valores={[{ valor: Number(posicao.exposicao_maxima) }]}
        />
      ) : (
        <CartaoAporte aporte={aporte} emCartao={emCartao} />
      )}
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

function CartaoAporte({ aporte, emCartao }: { aporte: AporteProjetado; emCartao: boolean }) {
  const rotulo = "Maior aporte necessário";
  const moldura = emCartao ? "rounded-xl border border-borda bg-superficie p-5" : "";
  return (
    <div className={`flex min-w-0 flex-col gap-1.5 ${moldura}`}>
      <p className="flex items-center gap-1.5 text-sm text-suave">
        {rotulo}
        <ExplicacaoIndicador chave="exposicao_maxima_projetada" rotulo={rotulo} />
      </p>
      {aporte ? (
        <>
          <p className="text-2xl font-semibold break-words">{formatarReal(aporte.valor)}</p>
          {aporte.parcial && (
            <p className="text-sm text-atencao">
              <span aria-hidden="true">! </span>Parcial: há custo sem título sem meses definidos.
            </p>
          )}
        </>
      ) : (
        <p className="text-lg text-suave">Não carregado</p>
      )}
    </div>
  );
}
