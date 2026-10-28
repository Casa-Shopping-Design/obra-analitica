import { ExplicacaoIndicador } from "@/componentes/ExplicacaoIndicador";
import type { ChaveExplicacao } from "@/lib/explicacoes";
import { classeValorGrande } from "@/lib/valor-grande";

// Cartão para número que não é real (unidades, meses, percentual) ou que precisa de uma linha de contexto.
// O valor chega já formatado; o cartão não faz conta.
export function CartaoValor({
  rotulo,
  valor,
  nota,
  chave,
  emCartao = true,
}: {
  rotulo: string;
  valor: string;
  nota?: string;
  chave?: ChaveExplicacao;
  emCartao?: boolean;
}) {
  const moldura = emCartao ? "figura" : "";
  return (
    <div className={`@container flex min-w-0 flex-col gap-1.5 ${moldura}`}>
      <p className="flex items-center gap-1.5 text-sm text-suave">
        {rotulo}
        {chave && <ExplicacaoIndicador chave={chave} rotulo={rotulo} />}
      </p>
      <p className={classeValorGrande}>{valor}</p>
      {nota && <p className="text-sm text-suave">{nota}</p>}
    </div>
  );
}
