import type { ReactNode } from "react";
import { IndicadorVgv } from "@/componentes/IndicadorVgv";
import type { ValoresVgv } from "@/lib/consultas/posicao";
import { formatarData, formatarReal } from "@/lib/formatar";
import {
  montarGrade,
  rotuloAndar,
  rotulosOrigemValor,
  rotulosSituacao,
  situacoesUnidade,
  type SituacaoUnidade,
  type UnidadeMapa,
} from "@/lib/grade-unidades";

// Fundo claro com texto escuro em todas as situações; cada uma tem também ícone de forma própria
// e rótulo escrito, porque cor sozinha não identifica a situação (WCAG 1.4.1).
const estiloSituacao: Record<SituacaoUnidade, { fundo: string; icone: string }> = {
  disponivel: { fundo: "bg-[#e4efd3] border-entrada", icone: "text-entrada" },
  reservada: { fundo: "bg-[#f5e6c6] border-atencao", icone: "text-atencao" },
  proposta: { fundo: "bg-[#d9e8ee] border-[#0b6a8c]", icone: "text-[#0b6a8c]" },
  vendida: { fundo: "bg-[#e3e6e3] border-saida", icone: "text-saida" },
  indisponivel: {
    fundo: "bg-[image:repeating-linear-gradient(135deg,#eef0ee_0_6px,#d5dcd6_6px_8px)] border-suave",
    icone: "text-suave",
  },
};

function IconeSituacao({ situacao }: { situacao: SituacaoUnidade }) {
  const classe = `size-3.5 shrink-0 ${estiloSituacao[situacao].icone}`;
  const formas: Record<SituacaoUnidade, ReactNode> = {
    disponivel: <circle cx="7" cy="7" r="5" fill="none" stroke="currentColor" strokeWidth="2" />,
    reservada: (
      <>
        <circle cx="7" cy="7" r="5" fill="none" stroke="currentColor" strokeWidth="2" />
        <path d="M7 2a5 5 0 0 1 0 10z" fill="currentColor" />
      </>
    ),
    proposta: <path d="M7 1.5 12.5 7 7 12.5 1.5 7z" fill="none" stroke="currentColor" strokeWidth="2" />,
    vendida: <circle cx="7" cy="7" r="6" fill="currentColor" />,
    indisponivel: <path d="M2 12 12 2" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" />,
  };
  return (
    <svg viewBox="0 0 14 14" className={classe} aria-hidden="true" focusable="false">
      {formas[situacao]}
    </svg>
  );
}

function valorOuAviso(valor: number | null, formatar: (numero: number) => string): string {
  return valor === null ? "sem valor" : formatar(Number(valor));
}

function DetalheUnidade({ unidade, id, alinharDireita }: { unidade: UnidadeMapa; id: string; alinharDireita: boolean }) {
  return (
    <div
      id={id}
      role="tooltip"
      className={`absolute top-full z-20 mt-1 hidden w-60 rounded-lg border border-borda bg-superficie p-3 text-left text-[13px] leading-snug font-normal text-texto shadow-lg group-focus-within:block group-hover:block ${
        alinharDireita ? "right-0" : "left-0"
      }`}
    >
      <p className="font-semibold">
        {unidade.unidade}, {rotulosSituacao[unidade.situacao].nome.toLowerCase()}
      </p>
      <dl className="mt-1.5 grid grid-cols-[auto_1fr] gap-x-2 gap-y-0.5">
        <dt className="text-suave">Valor hoje</dt>
        <dd className="text-right tabular-nums">{valorOuAviso(unidade.valor, formatarReal)}</dd>
        <dt className="text-suave">Por m²</dt>
        <dd className="text-right tabular-nums">{valorOuAviso(unidade.valor_m2, formatarReal)}</dd>
        {unidade.area_privativa !== null && (
          <>
            <dt className="text-suave">Área</dt>
            <dd className="text-right tabular-nums">{Number(unidade.area_privativa).toLocaleString("pt-BR")} m²</dd>
          </>
        )}
      </dl>
      <p className="mt-1.5 text-suave">
        {unidade.origem_valor ? rotulosOrigemValor[unidade.origem_valor] : "Sem preço cadastrado."}
      </p>
      {unidade.origem_valor === "tabela" && unidade.indice && (
        <p className="text-suave">
          {unidade.indice}
          {unidade.indice_valor !== null && ` ${Number(unidade.indice_valor).toLocaleString("pt-BR")}`}
          {unidade.indice_referencia && `, referência ${formatarData(unidade.indice_referencia)}`}
          {unidade.tabela && `. Tabela de preço: ${unidade.tabela}`}.
        </p>
      )}
    </div>
  );
}

// Na grade a tipologia já está no título da seção, então a célula mostra só andar e posição;
// o leitor de tela recebe o nome inteiro.
function CelulaUnidade({
  unidade,
  rotuloVisivel,
  alinharDireita,
}: {
  unidade: UnidadeMapa;
  rotuloVisivel: string;
  alinharDireita: boolean;
}) {
  const idDetalhe = `unidade-${unidade.unidade_id}`;
  const rotulo = rotulosSituacao[unidade.situacao];
  return (
    <div className="group relative">
      <div
        tabIndex={0}
        aria-describedby={idDetalhe}
        className={`flex min-h-12 flex-col justify-center gap-0.5 rounded-md border-l-4 px-1 py-1 ${estiloSituacao[unidade.situacao].fundo}`}
      >
        <span className="text-[13px] font-semibold whitespace-nowrap tabular-nums">
          <span aria-hidden="true">{rotuloVisivel}</span>
          <span className="sr-only">{unidade.unidade}</span>
        </span>
        <span className="flex items-center gap-0.5 text-[12px] whitespace-nowrap">
          <IconeSituacao situacao={unidade.situacao} />
          <span aria-hidden="true">{rotulo.abreviado}</span>
          <span className="sr-only">{rotulo.nome}</span>
        </span>
      </div>
      <DetalheUnidade unidade={unidade} id={idDetalhe} alinharDireita={alinharDireita} />
    </div>
  );
}

function Legenda() {
  return (
    <ul className="flex flex-wrap gap-x-4 gap-y-1.5 text-sm" aria-label="Legenda das situações">
      {situacoesUnidade.map((situacao) => (
        <li key={situacao} className="flex items-center gap-1.5">
          <IconeSituacao situacao={situacao} />
          {rotulosSituacao[situacao].nome}
        </li>
      ))}
    </ul>
  );
}

function TotaisObra({ totais, vgv }: { totais: Record<SituacaoUnidade, number>; vgv: ValoresVgv | null }) {
  return (
    <section
      aria-labelledby="titulo-totais"
      className="flex flex-col gap-4 rounded-xl border border-borda bg-superficie p-4 md:p-5 xl:sticky xl:top-6"
    >
      <h2 id="titulo-totais" className="font-serif text-xl font-semibold">
        Totais da obra
      </h2>
      {vgv ? <IndicadorVgv valores={vgv} /> : <p className="text-sm text-suave">VGV sem valor para esta obra.</p>}
      <dl className="grid grid-cols-1 gap-x-8 gap-y-1.5 border-t border-borda pt-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-1">
        {situacoesUnidade.map((situacao) => (
          <div key={situacao} className="flex items-center justify-between gap-3">
            <dt className="flex items-center gap-1.5 text-sm text-suave">
              <IconeSituacao situacao={situacao} />
              {rotulosSituacao[situacao].nome}
            </dt>
            <dd className="font-mono text-lg tabular-nums">{totais[situacao]}</dd>
          </div>
        ))}
      </dl>
      <p className="text-sm text-suave">
        O VGV soma as vendidas pelo valor do contrato e o estoque (disponíveis, reservadas e em proposta) pelo valor
        de hoje. Fora de venda não entra.
      </p>
    </section>
  );
}

export function MapaUnidades({ unidades, vgv }: { unidades: UnidadeMapa[]; vgv: ValoresVgv | null }) {
  const grade = montarGrade(unidades);

  // Em tela larga os totais ficam ao lado da grade e acompanham a rolagem, no lugar da faixa vazia à direita.
  return (
    <div className="grid grid-cols-1 gap-8 xl:grid-cols-[minmax(0,56rem)_minmax(20rem,26rem)] xl:items-start">
      <div className="flex min-w-0 flex-col gap-6">
        <Legenda />
        <p className="text-sm text-suave">
          Passe o mouse ou use a tecla Tab sobre uma unidade para ver o valor de hoje e de onde ele vem.
        </p>

        {grade.blocos.map((bloco) => (
          <section key={bloco.tipologia} className="flex flex-col gap-2">
            <h2 className="font-serif text-xl font-semibold">Tipologia {bloco.tipologia}</h2>
            <table className="w-full max-w-3xl table-fixed border-separate border-spacing-0 text-left xl:max-w-none">
              <caption className="sr-only">
                Unidades da tipologia {bloco.tipologia} por andar e posição, com a situação de cada uma
              </caption>
              <thead>
                <tr>
                  <th scope="col" className="w-[4.5rem] text-xs font-medium text-suave">
                    <span className="sr-only">Andar</span>
                  </th>
                  {bloco.posicoes.map((posicao) => (
                    <th key={posicao} scope="col" className="px-0.5 pb-1 text-xs font-medium text-suave">
                      <span className="sr-only">Posição </span>
                      {String(posicao).padStart(2, "0")}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {bloco.andares.map((linha) => (
                  <tr key={linha.andar}>
                    <th scope="row" className="pr-1 text-xs font-medium whitespace-nowrap text-suave">
                      {rotuloAndar(linha.andar)}
                    </th>
                    {linha.celulas.map((unidade, indice) =>
                      unidade ? (
                        <td key={unidade.unidade_id} className="p-0.5">
                          <CelulaUnidade
                            unidade={unidade}
                            rotuloVisivel={`${String(linha.andar).padStart(2, "0")}${String(bloco.posicoes[indice]).padStart(2, "0")}`}
                            alinharDireita={indice >= linha.celulas.length / 2}
                          />
                        </td>
                      ) : (
                        <td key={`vazio-${bloco.posicoes[indice]}`} className="p-0.5">
                          <span className="sr-only">Sem unidade</span>
                        </td>
                      ),
                    )}
                  </tr>
                ))}
              </tbody>
            </table>
          </section>
        ))}

        {grade.foraDoPadrao.length > 0 && (
          <section className="flex flex-col gap-2">
            <h2 className="font-serif text-xl font-semibold">Outras unidades</h2>
            <p className="text-sm text-suave">Unidades cujo nome não segue o padrão tipologia, andar e posição.</p>
            <ul className="grid max-w-3xl grid-cols-3 gap-1 sm:grid-cols-4 xl:max-w-none">
              {grade.foraDoPadrao.map((unidade, indice) => (
                <li key={unidade.unidade_id}>
                  <CelulaUnidade unidade={unidade} rotuloVisivel={unidade.unidade} alinharDireita={indice % 3 === 2} />
                </li>
              ))}
            </ul>
          </section>
        )}
      </div>

      <TotaisObra totais={grade.totais} vgv={vgv} />
    </div>
  );
}
