import type { LinhaPendenciaClassificacao } from "@/lib/consultas/dre";
import { formatarMes, formatarPercentual, formatarReal } from "@/lib/formatar";

const rotulosTipo: Record<LinhaPendenciaClassificacao["tipo_origem"], string> = {
  titulo_pagar: "Título a pagar",
  parcela_receber: "Parcela a receber",
  orcamento: "Item de orçamento",
};

function periodoPendencia(linha: LinhaPendenciaClassificacao): string {
  if (!linha.primeira_competencia) return "Sem data";
  if (!linha.ultima_competencia || linha.ultima_competencia === linha.primeira_competencia) {
    return formatarMes(linha.primeira_competencia);
  }
  return `${formatarMes(linha.primeira_competencia)} a ${formatarMes(linha.ultima_competencia)}`;
}

function Impacto({ linha }: { linha: LinhaPendenciaClassificacao }) {
  return <>{linha.participacao === null ? "Não informado" : `${formatarPercentual(linha.participacao)} do tipo`}</>;
}

// Tabela em tela larga; em tela estreita, um cartão por conta com os mesmos campos.
export function TabelaPendencias({ linhas }: { linhas: LinhaPendenciaClassificacao[] }) {
  const chave = (linha: LinhaPendenciaClassificacao) => `${linha.tipo_origem}-${linha.conta_origem ?? "sem-codigo"}`;
  const conta = (linha: LinhaPendenciaClassificacao) => linha.conta_origem ?? "Sem código na origem";
  return (
    <>
      <div className="hidden md:block">
        <table className="w-full text-sm">
          <caption className="sr-only">
            Contas da origem sem categoria gerencial, da de maior valor para a de menor, com o impacto no total do mesmo
            tipo
          </caption>
          <thead>
            <tr className="border-b border-borda text-suave">
              <th scope="col" className="px-3 py-2 text-left font-medium">
                Conta na origem
              </th>
              <th scope="col" className="px-3 py-2 text-left font-medium">
                Tipo
              </th>
              <th scope="col" className="px-3 py-2 text-right font-medium">
                Lançamentos
              </th>
              <th scope="col" className="px-3 py-2 text-right font-medium">
                Valor envolvido
              </th>
              <th scope="col" className="px-3 py-2 text-right font-medium">
                Impacto
              </th>
              <th scope="col" className="px-3 py-2 text-left font-medium">
                Competências
              </th>
            </tr>
          </thead>
          <tbody>
            {linhas.map((linha) => (
              <tr key={chave(linha)} className="border-b border-borda last:border-b-0">
                <th scope="row" className="px-3 py-2.5 text-left font-semibold">
                  {conta(linha)}
                </th>
                <td className="px-3 py-2.5">{rotulosTipo[linha.tipo_origem]}</td>
                <td className="px-3 py-2.5 text-right tabular-nums">{linha.quantidade_lancamentos}</td>
                <td className="px-3 py-2.5 text-right tabular-nums">{formatarReal(linha.valor_envolvido)}</td>
                <td className="px-3 py-2.5 text-right tabular-nums">
                  <Impacto linha={linha} />
                </td>
                <td className="px-3 py-2.5">{periodoPendencia(linha)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <ul aria-label="Contas sem categoria" className="flex flex-col gap-3 md:hidden">
        {linhas.map((linha) => (
          <li key={chave(linha)} className="rounded-lg border border-borda p-3">
            <p className="font-semibold">{conta(linha)}</p>
            <dl className="mt-1.5 flex flex-col gap-1 text-sm">
              {[
                ["Tipo", rotulosTipo[linha.tipo_origem]],
                ["Lançamentos", String(linha.quantidade_lancamentos)],
                ["Valor envolvido", formatarReal(linha.valor_envolvido)],
                ["Competências", periodoPendencia(linha)],
              ].map(([rotulo, valor]) => (
                <div key={rotulo} className="flex flex-wrap justify-between gap-x-3">
                  <dt className="text-suave">{rotulo}</dt>
                  <dd className="tabular-nums">{valor}</dd>
                </div>
              ))}
              <div className="flex flex-wrap justify-between gap-x-3">
                <dt className="text-suave">Impacto</dt>
                <dd className="tabular-nums">
                  <Impacto linha={linha} />
                </dd>
              </div>
            </dl>
          </li>
        ))}
      </ul>
    </>
  );
}
