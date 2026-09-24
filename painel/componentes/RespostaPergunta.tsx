import { formatarData, formatarReal } from "@/lib/formatar";
import type { LinhaResposta } from "@/lib/consultas/perguntas-prontas";
import type { ColunaResposta, PerguntaPronta } from "@/lib/perguntas-prontas";

const formatoInteiro = new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 0 });
const formatoArea = new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 2 });

// Só formata; nenhum número é somado ou derivado aqui, a resposta é o que o banco devolveu.
function formatarCelula(valor: string | number | null | undefined, coluna: ColunaResposta): string {
  if (valor === null || valor === undefined || valor === "") return "sem valor";
  switch (coluna.formato) {
    case "real":
      return formatarReal(Number(valor));
    case "inteiro":
      return formatoInteiro.format(Number(valor));
    case "area":
      return `${formatoArea.format(Number(valor))} m²`;
    case "data":
      return formatarData(String(valor));
    case "mes":
      return formatarData(String(valor)).slice(3);
    case "texto":
      return String(valor);
  }
}

const alinhamento = (coluna: ColunaResposta) => (coluna.formato === "texto" ? "text-left" : "text-right");

export function RespostaPergunta({
  pergunta,
  linhas,
  consultadoEm,
  limiteLinhas,
}: {
  pergunta: PerguntaPronta;
  linhas: LinhaResposta[];
  consultadoEm: string;
  limiteLinhas: number;
}) {
  const quantidade = linhas.length === 1 ? "1 linha" : `${linhas.length} linhas`;

  return (
    <section aria-labelledby="titulo-resposta" className="flex flex-col gap-3 rounded-xl border border-borda bg-superficie p-4 md:p-5">
      <h2 id="titulo-resposta" className="font-serif text-xl font-semibold">
        {pergunta.pergunta}
      </h2>

      {linhas.length === 0 ? (
        <p>{pergunta.semResultado}</p>
      ) : (
        <>
          <table className="hidden w-full text-sm tabular-nums md:table">
            <caption className="sr-only">Resposta: {pergunta.pergunta}</caption>
            <thead>
              <tr className="border-b border-borda text-suave">
                {pergunta.colunas.map((coluna) => (
                  <th key={coluna.chave} scope="col" className={`px-3 py-2 font-medium ${alinhamento(coluna)}`}>
                    {coluna.rotulo}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {linhas.map((linha, indice) => (
                <tr key={indice} className="border-b border-borda last:border-b-0">
                  {pergunta.colunas.map((coluna) => (
                    <td key={coluna.chave} className={`px-3 py-2 whitespace-nowrap ${alinhamento(coluna)}`}>
                      {formatarCelula(linha[coluna.chave], coluna)}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>

          <ul className="flex flex-col gap-2 md:hidden">
            {linhas.map((linha, indice) => (
              <li key={indice} className="rounded-lg border border-borda p-3">
                <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-sm">
                  {pergunta.colunas.map((coluna) => (
                    <div key={coluna.chave} className="contents">
                      <dt className="text-suave">{coluna.rotulo}</dt>
                      <dd className="text-right tabular-nums">{formatarCelula(linha[coluna.chave], coluna)}</dd>
                    </div>
                  ))}
                </dl>
              </li>
            ))}
          </ul>
        </>
      )}

      <p className="text-sm text-suave">
        Resposta calculada a partir de {quantidade}, dados de {formatarData(consultadoEm)}.
        {linhas.length >= limiteLinhas && ` Mostrando só as primeiras ${limiteLinhas} linhas.`}
      </p>
    </section>
  );
}
