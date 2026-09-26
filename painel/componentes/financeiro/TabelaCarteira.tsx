import Link from "next/link";
import { rotulosOrigem, rotulosSituacao } from "@/componentes/financeiro/receitas-tela";
import { Selo } from "@/componentes/financeiro/Selo";
import type { LinhaCarteiraRecebiveis } from "@/lib/consultas/receitas";
import { formatarData, formatarReal } from "@/lib/formatar";
import type { Paginacao } from "@/lib/periodo";

function Situacao({ linha }: { linha: LinhaCarteiraRecebiveis }) {
  return (
    <span className="inline-flex flex-wrap items-center justify-end gap-1">
      {rotulosSituacao[linha.situacao] ?? linha.situacao}
      {linha.parcial && <Selo tipo="informativo">pagamento parcial</Selo>}
    </span>
  );
}

function diasAtraso(linha: LinhaCarteiraRecebiveis): string {
  if (linha.dias_atraso === null) return "Não se aplica";
  return linha.dias_atraso === 1 ? "1 dia" : `${linha.dias_atraso} dias`;
}

function parcela(linha: LinhaCarteiraRecebiveis): string {
  return linha.numero_parcela ?? String(linha.parcela_id_origem);
}

const colunas: { rotulo: string; direita?: boolean; valor: (linha: LinhaCarteiraRecebiveis) => React.ReactNode }[] = [
  { rotulo: "Unidade", valor: (linha) => linha.unidade ?? "Não informada" },
  { rotulo: "Parcela", valor: parcela },
  { rotulo: "Condição", valor: (linha) => linha.tipo_condicao ?? "Não informada" },
  { rotulo: "Origem", valor: (linha) => rotulosOrigem[linha.origem] ?? linha.origem },
  { rotulo: "Vencimento", valor: (linha) => formatarData(linha.vencimento) },
  { rotulo: "Valor original", direita: true, valor: (linha) => formatarReal(linha.valor_original) },
  { rotulo: "Recebido", direita: true, valor: (linha) => formatarReal(linha.valor_recebido) },
  { rotulo: "Saldo", direita: true, valor: (linha) => formatarReal(linha.saldo) },
  { rotulo: "Situação", direita: true, valor: (linha) => <Situacao linha={linha} /> },
  { rotulo: "Atraso", direita: true, valor: diasAtraso },
];

function contrato(linha: LinhaCarteiraRecebiveis): string {
  return linha.contrato_numero ?? String(linha.contrato_id_origem);
}

// Sem nome de comprador: a view não traz e a tela não pede. Tabela em tela larga, cartões em tela estreita.
export function TabelaCarteira({ linhas, legenda }: { linhas: LinhaCarteiraRecebiveis[]; legenda: string }) {
  const chave = (linha: LinhaCarteiraRecebiveis) =>
    `${linha.centro_custo_id}-${linha.contrato_id_origem}-${linha.parcela_id_origem}`;
  return (
    <>
      <div className="hidden overflow-auto rounded-xl border border-borda md:block">
        <table className="w-full text-sm tabular-nums">
          <caption className="sr-only">{legenda}</caption>
          <thead>
            <tr className="text-suave">
              <th scope="col" className="border-b border-borda px-3 py-2 text-left font-medium">
                Contrato
              </th>
              {colunas.map((coluna) => (
                <th
                  key={coluna.rotulo}
                  scope="col"
                  className={`border-b border-borda px-3 py-2 font-medium ${coluna.direita ? "text-right" : "text-left"}`}
                >
                  {coluna.rotulo}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {linhas.map((linha) => (
              <tr key={chave(linha)} className="border-b border-borda last:border-b-0">
                <th scope="row" className="px-3 py-2 text-left font-semibold whitespace-nowrap">
                  {contrato(linha)}
                </th>
                {colunas.map((coluna) => (
                  <td
                    key={coluna.rotulo}
                    className={`px-3 py-2 whitespace-nowrap ${coluna.direita ? "text-right" : ""}`}
                  >
                    {coluna.valor(linha)}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <ul aria-label={legenda} className="flex flex-col gap-3 md:hidden">
        {linhas.map((linha) => (
          <li key={chave(linha)} className="rounded-xl border border-borda p-4">
            <p className="font-semibold">Contrato {contrato(linha)}</p>
            <dl className="mt-2 flex flex-col gap-1 text-sm">
              {colunas.map((coluna) => (
                <div key={coluna.rotulo} className="flex flex-wrap justify-between gap-x-3">
                  <dt className="text-suave">{coluna.rotulo}</dt>
                  <dd className="text-right tabular-nums">{coluna.valor(linha)}</dd>
                </div>
              ))}
            </dl>
          </li>
        ))}
      </ul>
    </>
  );
}

// Anterior e próxima como links: a página nova vem do servidor, com o mesmo filtro na URL.
export function NavegacaoPaginas({
  paginacao,
  endereco,
}: {
  paginacao: Paginacao;
  endereco: (pagina: number) => string;
}) {
  const classeLink = "flex min-h-11 items-center rounded-lg border border-borda bg-superficie px-3 hover:border-texto";
  return (
    <nav aria-label="Páginas da carteira" className="flex flex-wrap items-center gap-3 text-sm">
      {paginacao.anterior !== null && (
        <Link href={endereco(paginacao.anterior)} scroll={false} className={classeLink}>
          Página anterior
        </Link>
      )}
      <p aria-live="polite">
        Página {paginacao.pagina} de {paginacao.totalPaginas} ·{" "}
        {paginacao.totalLinhas === 1 ? "1 parcela" : `${paginacao.totalLinhas.toLocaleString("pt-BR")} parcelas`}
      </p>
      {paginacao.proxima !== null && (
        <Link href={endereco(paginacao.proxima)} scroll={false} className={classeLink}>
          Próxima página
        </Link>
      )}
    </nav>
  );
}
