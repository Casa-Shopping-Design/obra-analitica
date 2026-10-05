import { CartaoIndicador } from "@/componentes/CartaoIndicador";
import { CartaoValor } from "@/componentes/CartaoValor";
import { percentualOuSemBase, textoDesvioPontos, type ResumoCarteiraDre } from "@/lib/dre";
import { formatarReal } from "@/lib/formatar";

// Os oito números do deck, somados no banco (marts.dre_resumo_carteira). A margem é a operacional até o
// lucro líquido ter definição, e o desvio da margem aparece em texto, sem depender de cor.
export function FaixaResultado({ resumo }: { resumo: ResumoCarteiraDre }) {
  return (
    <section aria-labelledby="titulo-resultado" className="flex flex-col gap-5 rounded-xl border border-borda bg-superficie p-5">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 id="titulo-resultado" className="font-serif text-2xl font-semibold">
          Resultado
        </h2>
        <p className="text-sm text-suave">
          {resumo.obras === 1 ? "1 obra com estudo de viabilidade" : `${resumo.obras} obras com estudo de viabilidade`}
        </p>
      </div>
      <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 xl:grid-cols-4">
        <CartaoIndicador rotulo="VGV bruto" chave="vgv_bruto_resultado" valores={[{ valor: resumo.vgvBrutoTendencia }]} />
        <CartaoValor rotulo="POC" chave="poc_resultado" valor={percentualOuSemBase(resumo.poc)} emCartao={false} />
        <CartaoValor
          rotulo="% vendido"
          chave="pct_vendido_resultado"
          valor={percentualOuSemBase(resumo.pctVendido)}
          nota={`${formatarReal(resumo.vgvVendido)} vendidos`}
          emCartao={false}
        />
        <CartaoValor
          rotulo="Margem operacional no estudo"
          chave="margem_operacional_viabilidade_carteira"
          valor={percentualOuSemBase(resumo.margemOperacionalViabilidade)}
          emCartao={false}
        />
        <CartaoValor
          rotulo="Lucro operacional na tendência"
          chave="lucro_operacional_tendencia"
          valor={formatarReal(resumo.lucroOperacionalTendencia)}
          nota={`No estudo: ${formatarReal(resumo.lucroOperacionalViabilidade)}`}
          emCartao={false}
        />
        <CartaoIndicador rotulo="Custo apropriado" chave="custo_apropriado" valores={[{ valor: resumo.custoApropriado }]} />
        <CartaoIndicador
          rotulo="Recebimentos acumulados"
          chave="recebido_acumulado"
          valores={[{ valor: resumo.recebidoAcumulado }]}
        />
        <CartaoValor
          rotulo="Margem operacional na tendência"
          chave="margem_operacional_tendencia_carteira"
          valor={percentualOuSemBase(resumo.margemOperacionalTendencia)}
          nota={textoDesvioPontos(resumo.desvioMargemOperacional)}
          emCartao={false}
        />
      </div>
    </section>
  );
}
