import { CartaoValor } from "@/componentes/CartaoValor";
import { avisoEstimativa, formatarAliquota, type ImpostoObra } from "@/lib/imposto";
import { formatarReal } from "@/lib/formatar";

// Os nove cartões do deck, na ordem dele. Cada imposto chega pronto da view; a nota só repete a base de onde saiu.
export function CartoesImposto({ imposto }: { imposto: ImpostoObra }) {
  return (
    <section aria-labelledby="titulo-imposto" className="flex flex-col gap-5 rounded-xl border border-borda bg-superficie p-5">
      <div className="flex flex-col gap-1">
        <h2 id="titulo-imposto" className="font-serif text-2xl font-semibold">
          Projeção tributária
        </h2>
        <p className="text-sm text-alerta" role="note">
          {avisoEstimativa}
        </p>
      </div>
      <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 xl:grid-cols-3">
        <CartaoValor
          rotulo="VGV total do empreendimento"
          chave="vgv_total_imposto"
          valor={formatarReal(imposto.vgvTotal)}
          emCartao={false}
        />
        <CartaoValor
          rotulo="Imposto sobre receita apropriada"
          chave="imposto_receita_apropriada"
          valor={formatarReal(imposto.impostoReceitaApropriada)}
          nota={`Sobre ${formatarReal(imposto.receitaApropriada)} de receita apropriada`}
          emCartao={false}
        />
        <CartaoValor
          rotulo="Imposto sobre recebimentos"
          chave="imposto_recebimento"
          valor={formatarReal(imposto.impostoRecebimento)}
          nota={`Sobre ${formatarReal(imposto.recebidoAcumulado)} recebidos`}
          emCartao={false}
        />
        <CartaoValor
          rotulo="Imposto diferido sobre contas a receber"
          chave="imposto_diferido"
          valor={formatarReal(imposto.impostoDiferido)}
          emCartao={false}
        />
        <CartaoValor
          rotulo="Imposto sobre VGV em estoque"
          chave="imposto_vgv_estoque"
          valor={formatarReal(imposto.impostoVgvEstoque)}
          nota={`Sobre ${formatarReal(imposto.vgvEstoque)} em estoque`}
          emCartao={false}
        />
        <CartaoValor
          rotulo="Imposto sobre receita a apropriar"
          chave="imposto_receita_a_apropriar"
          valor={formatarReal(imposto.impostoReceitaAApropriar)}
          nota={`Sobre ${formatarReal(imposto.receitaAApropriar)} vendidos e ainda não apropriados`}
          emCartao={false}
        />
        <CartaoValor
          rotulo="Imposto sobre VGV total"
          chave="imposto_vgv_total"
          valor={formatarReal(imposto.impostoVgvTotal)}
          nota={imposto.impostoViabilidade === null ? undefined : `No estudo: ${formatarReal(imposto.impostoViabilidade)}`}
          emCartao={false}
        />
        <CartaoValor
          rotulo="Imposto devido a realizar"
          chave="imposto_a_realizar"
          valor={formatarReal(imposto.impostoARealizar)}
          emCartao={false}
        />
        <CartaoValor
          rotulo="% de imposto sobre VGV total"
          chave="aliquota_imposto"
          valor={formatarAliquota(imposto.aliquota)}
          emCartao={false}
        />
      </div>
    </section>
  );
}
