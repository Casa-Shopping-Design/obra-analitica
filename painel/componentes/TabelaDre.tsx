import { ExplicacaoIndicador } from "@/componentes/ExplicacaoIndicador";
import {
  colunasDre,
  percentualComSinal,
  textoDesvio,
  textoSituacao,
  type ColunaDre,
  type LinhaTabelaDre,
  type SituacaoDesvio,
} from "@/lib/dre";
import { formatarPercentual, formatarReal } from "@/lib/formatar";

// Classes fixas porque o Tailwind só gera a classe que aparece escrita inteira no código.
const recuoPorNivel = ["pl-3", "pl-7", "pl-11"];

const corSituacao: Record<SituacaoDesvio, string> = {
  favoravel: "text-entrada",
  desfavoravel: "text-alerta",
  neutro: "",
};

const celula = "px-3 py-2.5 text-right align-top whitespace-nowrap print:px-1 print:py-1";
const fundoEntrada = "bg-fundo print:[print-color-adjust:exact]";

function valorCelula(linha: LinhaTabelaDre, coluna: ColunaDre): string {
  const valor = linha[coluna.chave];
  if (coluna.chave === "desvio") return textoDesvio(linha.desvio);
  if (coluna.chave === "desvioPct") return percentualComSinal(linha.desvioPct);
  if (coluna.percentual) return valor === null ? "sem base" : formatarPercentual(valor);
  return formatarReal(valor ?? 0);
}

function CelulaDre({ linha, coluna }: { linha: LinhaTabelaDre; coluna: ColunaDre }) {
  const ehDesvio = coluna.chave === "desvio" || coluna.chave === "desvioPct";
  const classes = [
    celula,
    coluna.chave === "viabilidade" ? fundoEntrada : "",
    ehDesvio ? corSituacao[linha.situacao] : "",
  ].join(" ");
  const situacao = coluna.chave === "desvio" ? textoSituacao(linha.situacao) : null;
  return (
    <td className={classes}>
      {valorCelula(linha, coluna)}
      {situacao && <span className="block text-xs">{situacao}</span>}
    </td>
  );
}

// Só leitura. No celular rola para o lado dentro do próprio contêiner, com o nome da linha fixo.
export function TabelaDre({ linhas }: { linhas: LinhaTabelaDre[] }) {
  return (
    <section aria-labelledby="titulo-dre" className="flex flex-col gap-3">
      <h2 id="titulo-dre" className="sr-only">
        DRE de viabilidade da obra
      </h2>
      <p className="text-sm text-suave md:hidden print:hidden">Arraste a tabela para o lado para ver todas as colunas.</p>
      {/* relative segura dentro da rolagem os textos sr-only, que são absolutos e alargariam a página no celular */}
      <div className="relative overflow-x-auto rounded-xl border border-borda bg-superficie print:overflow-visible print:rounded-none print:border-0">
        <table className="w-full min-w-[1320px] border-collapse text-sm tabular-nums print:min-w-0 print:text-[8pt]">
          <caption className="sr-only">
            Cada linha do resultado no estudo de viabilidade, no realizado e na tendência, com o desvio contra o estudo.
          </caption>
          <thead>
            <tr className="text-suave">
              <th
                scope="col"
                className="sticky left-0 z-10 border-b border-borda bg-superficie px-3 py-3 text-left align-bottom font-medium print:static print:px-1"
              >
                Linha
              </th>
              {colunasDre.map((coluna) => (
                <th
                  key={coluna.chave}
                  scope="col"
                  className={`border-b border-borda px-3 py-3 text-right align-bottom font-medium print:px-1 print:whitespace-normal ${
                    coluna.chave === "viabilidade" ? fundoEntrada : ""
                  }`}
                >
                  <span className="inline-flex items-center justify-end gap-1.5">
                    {coluna.rotulo}
                    <ExplicacaoIndicador chave={coluna.explicacao} rotulo={coluna.rotulo} alinhamento="direita" />
                  </span>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {linhas.map((linha) => (
              <tr
                key={linha.linha}
                className={`border-b border-borda last:border-b-0 ${linha.linhaDeTotal ? "font-semibold" : ""}`}
              >
                <th
                  scope="row"
                  className={`sticky left-0 z-10 bg-superficie py-2.5 pr-3 text-left align-top whitespace-nowrap print:static print:py-1 ${
                    recuoPorNivel[linha.nivel] ?? recuoPorNivel[recuoPorNivel.length - 1]
                  } ${linha.linhaDeTotal ? "font-semibold" : "font-normal"}`}
                >
                  {linha.rotulo}
                  {linha.semRealizado && (
                    <span className="block text-xs font-normal text-suave">sem realizado carregado</span>
                  )}
                </th>
                {colunasDre.map((coluna) => (
                  <CelulaDre key={coluna.chave} linha={linha} coluna={coluna} />
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}
