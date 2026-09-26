import { Explicacao } from "@/componentes/planejamento/Explicacao";

// Número principal no topo, rótulo curto acima e o contexto (origem, mês, natureza) embaixo.
export function CartaoPlanejamento({
  rotulo,
  explicacao,
  valor,
  contexto,
  selo,
}: {
  rotulo: string;
  explicacao: string;
  valor: React.ReactNode;
  contexto?: React.ReactNode;
  selo?: React.ReactNode;
}) {
  return (
    <div className="flex min-w-0 flex-col gap-1.5 rounded-xl border border-borda bg-superficie p-5">
      <p className="flex items-center gap-1.5 text-sm text-suave">
        {rotulo}
        <Explicacao texto={explicacao} rotulo={rotulo} />
      </p>
      <p className="text-2xl font-semibold break-words tabular-nums">{valor}</p>
      {selo}
      {contexto && <p className="text-xs leading-snug text-suave">{contexto}</p>}
    </div>
  );
}
