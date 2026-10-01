import type { RepasseBanco } from "@/lib/consultas/repasse-banco";
import { formatarReal } from "@/lib/formatar";

const inteiro = new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 0 });
const umaCasa = new Intl.NumberFormat("pt-BR", { minimumFractionDigits: 1, maximumFractionDigits: 1 });
const celula = "px-3 py-2 text-right tabular-nums align-top";

// Destaca o banco cujo prazo passa a média da obra em mais de 50%.
const fatorPrazoLento = 1.5;

function ValorEQuantidade({ valor, quantidade, alerta }: { valor: number; quantidade: number; alerta?: boolean }) {
  if (quantidade === 0) return <span className="text-suave">nenhum</span>;
  return (
    <>
      <span className={`block ${alerta ? "font-semibold text-alerta" : ""}`}>{formatarReal(valor)}</span>
      <span className="block text-xs text-suave">
        {inteiro.format(quantidade)} {quantidade === 1 ? "contrato" : "contratos"}
      </span>
    </>
  );
}

function Prazo({ dias, lento }: { dias: number | null; lento: boolean }) {
  if (dias === null) return <span className="text-suave">sem liberação</span>;
  return (
    <span className={lento ? "font-semibold text-alerta" : ""}>
      {umaCasa.format(dias)} dias
      {lento && <span className="block text-xs font-normal">acima da média da obra</span>}
    </span>
  );
}

// Mesmas etapas do quadro de repasse, aberto por banco. A soma das linhas fecha com o quadro.
export function TabelaRepasseBanco({ linhas, diasMediosObra }: { linhas: RepasseBanco[]; diasMediosObra: number | null }) {
  return (
    <div className="overflow-x-auto rounded-xl border border-borda bg-superficie">
      <table className="w-full min-w-[820px] border-collapse text-sm">
        <caption className="sr-only">Repasse do financiamento por banco</caption>
        <thead>
          <tr className="border-b border-borda text-suave">
            <th scope="col" className="px-3 py-2 text-left font-semibold">Banco</th>
            <th scope="col" className={`${celula} font-semibold`}>Contratos</th>
            <th scope="col" className={`${celula} font-semibold`}>Em análise</th>
            <th scope="col" className={`${celula} font-semibold`}>Assinado</th>
            <th scope="col" className={`${celula} font-semibold`}>Liberado</th>
            <th scope="col" className={`${celula} font-semibold`}>Atrasado</th>
            <th scope="col" className={`${celula} font-semibold`}>Assinatura até liberação</th>
            <th scope="col" className={`${celula} font-semibold`}>Parado em análise há mais de 60 dias</th>
          </tr>
        </thead>
        <tbody>
          {linhas.map((linha) => {
            const dias = linha.dias_medios_assinatura_liberacao;
            const lento = dias !== null && diasMediosObra !== null && linhas.length > 1 && dias > diasMediosObra * fatorPrazoLento;
            return (
              <tr key={linha.banco} className="border-b border-borda last:border-b-0">
                <th scope="row" className="px-3 py-2 text-left align-top font-semibold">{linha.banco}</th>
                <td className={celula}>{inteiro.format(linha.contratos_com_repasse)}</td>
                <td className={celula}>
                  <ValorEQuantidade valor={linha.valor_em_analise} quantidade={linha.repasses_em_analise} />
                </td>
                <td className={celula}>
                  <ValorEQuantidade valor={linha.valor_assinado} quantidade={linha.repasses_assinados} />
                </td>
                <td className={celula}>
                  <ValorEQuantidade valor={linha.valor_liberado} quantidade={linha.repasses_liberados} />
                </td>
                <td className={celula}>
                  <ValorEQuantidade valor={linha.valor_atrasado} quantidade={linha.repasses_atrasados} alerta />
                </td>
                <td className={celula}>
                  <Prazo dias={dias} lento={lento} />
                </td>
                <td className={celula}>
                  <ValorEQuantidade valor={linha.valor_parado_analise} quantidade={linha.repasses_parados_analise} />
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
