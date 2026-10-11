import Link from "next/link";
import type { ReactNode } from "react";
import { situacaoIdentidade, type ContaSemMapa, type ControleEmpresa } from "@/lib/empresa";
import { rotuloMes } from "@/lib/empresa-periodo";
import { formatarReal } from "@/lib/formatar";
import { mensagensEmpresa } from "@/lib/mensagens-empresa";

const celula = "px-3 py-2.5 text-right align-top whitespace-nowrap";
const rotulo = "py-2.5 pr-3 pl-3 text-left align-top font-normal";

function Selo({ fecha, textoFecha, textoDiferenca }: { fecha: boolean; textoFecha: string; textoDiferenca: string }) {
  return (
    <p
      className={`w-fit rounded-full border px-3 py-1 text-sm font-semibold ${
        fecha ? "border-entrada text-entrada" : "border-atencao text-atencao"
      }`}
    >
      {fecha ? textoFecha : textoDiferenca}
    </p>
  );
}

function Quadro({ id, titulo, children }: { id: string; titulo: string; children: ReactNode }) {
  return (
    <section aria-labelledby={id} className="flex flex-col gap-3 rounded-xl border border-borda bg-superficie p-5">
      <h2 id={id} className="font-serif text-2xl font-semibold">
        {titulo}
      </h2>
      {children}
    </section>
  );
}

// Os três números de cada quadro vêm prontos da view de controle; a tela não subtrai nada.
export function QuadrosControle({ controle }: { controle: ControleEmpresa }) {
  const fechaCaixa = situacaoIdentidade(controle.diferencaIdentidade) === "fecha";
  const semAjuste = situacaoIdentidade(controle.ajusteExerciciosAnteriores) === "fecha";
  return (
    <div className="grid grid-cols-1 gap-4 xl:grid-cols-2">
      <Quadro id="titulo-identidade" titulo="Fontes menos usos contra o caixa">
        <p className="text-sm text-suave">Posição acumulada no fim de {rotuloMes(controle.competencia.slice(0, 7))}.</p>
        <table className="w-full border-collapse text-sm tabular-nums">
          <caption className="sr-only">Saldo líquido do fluxo de caixa, caixa e equivalentes e a diferença entre os dois.</caption>
          <tbody>
            <tr className="border-b border-borda">
              <th scope="row" className={rotulo}>
                Saldo líquido do fluxo de caixa
              </th>
              <td className={celula}>{formatarReal(controle.saldoLiquidoAcumulado)}</td>
            </tr>
            <tr className="border-b border-borda">
              <th scope="row" className={rotulo}>
                Caixa e equivalentes de caixa
              </th>
              <td className={celula}>{formatarReal(controle.caixaEquivalentesAcumulado)}</td>
            </tr>
            <tr className="font-semibold">
              <th scope="row" className={`${rotulo} font-semibold`}>
                Diferença
              </th>
              <td className={celula}>{formatarReal(controle.diferencaIdentidade)}</td>
            </tr>
          </tbody>
        </table>
        <Selo
          fecha={fechaCaixa}
          textoFecha="Fecha com o caixa"
          textoDiferenca="Não fecha: confira as contas sem mapa abaixo"
        />
      </Quadro>
      <Quadro id="titulo-lucros" titulo="Lucro da DRE contra lucros acumulados">
        <p className="text-sm text-suave">A diferença fica como linha própria e não é corrigida.</p>
        <table className="w-full border-collapse text-sm tabular-nums">
          <caption className="sr-only">Lucro líquido acumulado da DRE, lucros acumulados no balanço e os ajustes de exercícios anteriores.</caption>
          <tbody>
            <tr className="border-b border-borda">
              <th scope="row" className={rotulo}>
                Lucro líquido da DRE
              </th>
              <td className={celula}>{formatarReal(controle.lucroLiquidoDre)}</td>
            </tr>
            <tr className="border-b border-borda">
              <th scope="row" className={rotulo}>
                Lucros acumulados
              </th>
              <td className={celula}>{formatarReal(controle.lucrosAcumulados)}</td>
            </tr>
            <tr className="font-semibold">
              <th scope="row" className={`${rotulo} font-semibold`}>
                Ajustes de exercícios anteriores
              </th>
              <td className={celula}>{formatarReal(controle.ajusteExerciciosAnteriores)}</td>
            </tr>
          </tbody>
        </table>
        <Selo
          fecha={semAjuste}
          textoFecha="Sem ajuste de exercícios anteriores"
          textoDiferenca="Há ajuste de exercícios anteriores"
        />
      </Quadro>
    </div>
  );
}

export function ListaContasSemMapa({ contas, podeMapear }: { contas: ContaSemMapa[] | null; podeMapear: boolean }) {
  return (
    <Quadro id="titulo-sem-mapa" titulo="Contas sem mapa">
      {contas === null && (
        <p role="alert" className="text-alerta">
          {mensagensEmpresa.contasSemMapaIndisponivel}
        </p>
      )}
      {contas?.length === 0 && <p>{mensagensEmpresa.semContasSemMapa}</p>}
      {contas && contas.length > 0 && (
        <>
          <p className="text-sm text-suave">
            Contas com saldo ou movimento que não caem em nenhuma linha dos relatórios. Enquanto ficarem assim, as Fontes
            e Usos podem não fechar com o caixa.
          </p>
          <div className="relative overflow-x-auto">
            <table className="w-full min-w-[640px] border-collapse text-sm tabular-nums">
              <caption className="sr-only">Contas contábeis com saldo ou movimento e sem linha de relatório.</caption>
              <thead>
                <tr className="text-suave">
                  <th scope="col" className="border-b border-borda px-3 py-2.5 text-left font-medium">
                    Conta
                  </th>
                  <th scope="col" className="border-b border-borda px-3 py-2.5 text-left font-medium">
                    Nome
                  </th>
                  <th scope="col" className="border-b border-borda px-3 py-2.5 text-right font-medium">
                    Saldo final
                  </th>
                  <th scope="col" className="border-b border-borda px-3 py-2.5 text-right font-medium">
                    Movimento
                  </th>
                </tr>
              </thead>
              <tbody>
                {contas.map((conta) => (
                  <tr key={conta.conta} className="border-b border-borda last:border-b-0">
                    <th scope="row" className="px-3 py-2.5 text-left align-top font-normal whitespace-nowrap">
                      {conta.conta}
                    </th>
                    <td className="px-3 py-2.5 align-top">{conta.nome}</td>
                    <td className={celula}>{formatarReal(conta.saldoFinal)}</td>
                    <td className={celula}>{formatarReal(conta.movimento)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {podeMapear ? (
            <Link
              href="/empresas/mapa-contas?sem_mapa=1"
              className="w-fit text-sm font-semibold underline underline-offset-4 hover:text-menu print:hidden"
            >
              Mapear estas contas
            </Link>
          ) : (
            <p className="text-sm text-suave">{mensagensEmpresa.pecaMapeamento}</p>
          )}
        </>
      )}
    </Quadro>
  );
}
