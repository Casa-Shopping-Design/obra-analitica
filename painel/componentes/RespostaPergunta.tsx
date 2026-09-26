import { Selo } from "@/componentes/financeiro/Selo";
import { GraficoResposta } from "@/componentes/planejamento/GraficoResposta";
import type { RespostaMontada, TabelaResposta, ValorCelula } from "@/componentes/planejamento/respostas-perguntas";
import { formatarData, formatarPercentual, formatarReal } from "@/lib/formatar";
import { fraseMotivo } from "@/lib/mensagens";
import { rotulosNatureza } from "@/lib/mensagens-planejamento";
import type { ColunaResposta, PerguntaPronta } from "@/lib/perguntas-prontas";

const formatoInteiro = new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 0 });
const formatoArea = new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 2 });

// Só formata; nenhum número é somado ou derivado aqui, a resposta é o que o banco devolveu.
function formatarCelula(valor: ValorCelula | undefined, coluna: ColunaResposta): string {
  if (coluna.formato === "motivo") return valor === null || valor === undefined ? "Disponível" : fraseMotivo(String(valor));
  if (valor === null || valor === undefined || valor === "") return "Não informado";
  switch (coluna.formato) {
    case "real":
      return formatarReal(Number(valor));
    case "inteiro":
      return formatoInteiro.format(Number(valor));
    case "area":
      return `${formatoArea.format(Number(valor))} m²`;
    case "percentual":
      return formatarPercentual(Number(valor));
    case "simnao":
      return valor === true ? "Sim" : "Não";
    case "data":
      return formatarData(String(valor));
    case "mes":
      return formatarData(String(valor).slice(0, 10)).slice(3);
    case "texto":
      return String(valor);
  }
}

const alinhamento = (coluna: ColunaResposta) =>
  coluna.formato === "texto" || coluna.formato === "motivo" ? "text-left" : "text-right";

function TabelaDaResposta({
  tabela,
  indice,
  semResultado,
  limiteLinhas,
}: {
  tabela: TabelaResposta;
  indice: number;
  semResultado: string;
  limiteLinhas: number;
}) {
  const natureza = rotulosNatureza[tabela.natureza];
  const linhas = tabela.linhas.slice(0, limiteLinhas);
  const idTitulo = `tabela-resposta-${indice}`;
  return (
    <section aria-labelledby={idTitulo} className="flex min-w-0 flex-col gap-2">
      <div className="flex flex-wrap items-center gap-2">
        <h3 id={idTitulo} className="font-semibold">
          {tabela.titulo}
        </h3>
        <Selo tipo={tabela.natureza === "simulacao" ? "parcial" : "informativo"}>{natureza.rotulo}</Selo>
      </div>
      <p className="text-xs text-suave">{natureza.descricao}</p>
      {linhas.length === 0 ? (
        <p className="text-sm">{semResultado}</p>
      ) : (
        <>
          <div className="hidden overflow-x-auto md:block">
            <table className="w-full text-sm tabular-nums">
              <caption className="sr-only">
                {tabela.titulo} ({natureza.rotulo})
              </caption>
              <thead>
                <tr className="border-b border-borda text-suave">
                  {tabela.colunas.map((coluna) => (
                    <th key={coluna.chave} scope="col" className={`px-3 py-2 font-medium ${alinhamento(coluna)}`}>
                      {coluna.rotulo}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {linhas.map((linha, posicao) => (
                  <tr key={posicao} className="border-b border-borda last:border-b-0">
                    {tabela.colunas.map((coluna) => (
                      <td key={coluna.chave} className={`px-3 py-2 ${alinhamento(coluna)} ${coluna.formato === "motivo" ? "" : "whitespace-nowrap"}`}>
                        {formatarCelula(linha[coluna.chave], coluna)}
                      </td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <ul className="flex flex-col gap-2 md:hidden">
            {linhas.map((linha, posicao) => (
              <li key={posicao} className="rounded-lg border border-borda p-3">
                <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-sm">
                  {tabela.colunas.map((coluna) => (
                    <div key={coluna.chave} className="contents">
                      <dt className="text-suave">{coluna.rotulo}</dt>
                      <dd className="text-right tabular-nums">{formatarCelula(linha[coluna.chave], coluna)}</dd>
                    </div>
                  ))}
                </dl>
              </li>
            ))}
          </ul>
          {tabela.linhas.length > limiteLinhas && (
            <p className="text-xs text-suave">Mostrando só as primeiras {limiteLinhas} linhas.</p>
          )}
        </>
      )}
    </section>
  );
}

export function RespostaPergunta({
  pergunta,
  resposta,
  dataReferencia,
  consultadoEm,
  nomeObra,
  limiteLinhas,
}: {
  pergunta: PerguntaPronta;
  resposta: RespostaMontada;
  dataReferencia: string;
  consultadoEm: string;
  nomeObra: string | null;
  limiteLinhas: number;
}) {
  const semLinhas = resposta.tabelas.every((tabela) => tabela.linhas.length === 0);

  return (
    <section
      aria-labelledby="titulo-resposta"
      className="flex min-w-0 flex-col gap-4 rounded-xl border border-borda bg-superficie p-4 md:p-5"
    >
      <div className="flex flex-col gap-1">
        <h2 id="titulo-resposta" className="font-serif text-xl font-semibold">
          {pergunta.pergunta}
        </h2>
        <p className="text-sm text-suave">
          Data de referência: {formatarData(dataReferencia)}
          {nomeObra && <> · Obra: {nomeObra}</>}
        </p>
      </div>

      {resposta.conclusao && <p className="max-w-3xl text-base font-medium">{resposta.conclusao}</p>}
      {!resposta.conclusao && semLinhas && <p>{pergunta.semResultado}</p>}

      {resposta.premissas && (
        <section aria-labelledby="premissas-resposta" className="flex flex-col gap-2 rounded-lg border border-borda p-3">
          <div className="flex flex-wrap items-center gap-2">
            <h3 id="premissas-resposta" className="font-semibold">
              Premissas da simulação
            </h3>
            <Selo tipo="parcial">{rotulosNatureza.simulacao.rotulo}</Selo>
          </div>
          <dl className="grid gap-x-4 gap-y-1 text-sm sm:grid-cols-[auto_1fr]">
            {resposta.premissas.map((item) => (
              <div key={item.rotulo} className="contents">
                <dt className="text-suave">{item.rotulo}</dt>
                <dd>{item.valor}</dd>
              </div>
            ))}
          </dl>
        </section>
      )}

      {resposta.avisos.map((aviso) => (
        <p key={aviso} className="text-sm text-atencao">
          <span aria-hidden="true">! </span>
          {aviso}
        </p>
      ))}

      {resposta.tabelas.map((tabela, indice) => (
        <TabelaDaResposta
          key={tabela.chave}
          tabela={tabela}
          indice={indice}
          semResultado={indice === 0 ? pergunta.semResultado : "Nenhuma linha nesta parte da resposta."}
          limiteLinhas={limiteLinhas}
        />
      ))}

      {resposta.grafico && resposta.grafico.pontos.length > 0 && (
        <GraficoResposta grafico={resposta.grafico} idBase={`resposta-${pergunta.id}`} />
      )}

      <p className="text-sm text-suave">
        Números consultados em {formatarData(consultadoEm)} com as funções das telas do painel, só nas obras liberadas
        para o seu perfil.
      </p>
    </section>
  );
}
