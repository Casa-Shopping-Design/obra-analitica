"use client";

import { useActionState, useMemo, useState } from "react";
import { gravarMapaContas, type EstadoMapa } from "@/app/(painel)/empresas/mapa-contas/acoes";
import { maximoItensMapa, mudancasMapa, type OpcaoLinha } from "@/lib/mapa-contas";

export type ContaFormulario = {
  conta: string;
  nome: string;
  analitica: boolean;
  grupoConta: string;
  linha: string | null;
  linhaEfetiva: string | null;
};

type Propriedades = {
  contas: ContaFormulario[];
  opcoesPorGrupo: Record<string, OpcaoLinha[]>;
  rotulosLinha: Record<string, string>;
};

const estadoInicial: EstadoMapa = { erro: null, sucesso: null };

const classeCampo =
  "min-h-10 w-full min-w-56 rounded-lg border border-borda bg-superficie px-2.5 text-sm text-texto focus-visible:border-texto";

function textoLinhaAtual(conta: ContaFormulario, rotulosLinha: Record<string, string>): string {
  if (conta.linhaEfetiva === null) return "Sem mapa";
  const rotulo = rotulosLinha[conta.linhaEfetiva] ?? conta.linhaEfetiva;
  return conta.linha === null ? `${rotulo} (herdada da conta sintética)` : rotulo;
}

// Só as contas alteradas vão para a Server Action, num campo JSON; a validação e o banco repetem as regras.
export function FormularioMapaContas({ contas, opcoesPorGrupo, rotulosLinha }: Propriedades) {
  const [estado, acao, enviando] = useActionState(gravarMapaContas, estadoInicial);
  const originais = useMemo(() => new Map(contas.map((conta) => [conta.conta, conta.linha])), [contas]);
  const [escolhas, mudarEscolhas] = useState(() => new Map(contas.map((conta) => [conta.conta, conta.linha ?? ""])));
  const mudancas = useMemo(() => mudancasMapa(originais, escolhas), [originais, escolhas]);
  const contasAlteradas = useMemo(() => new Set(mudancas.map((item) => item.conta)), [mudancas]);
  const idAviso = estado.erro ? "erro-mapa" : estado.sucesso ? "sucesso-mapa" : undefined;

  function escolher(conta: string, linha: string) {
    mudarEscolhas((anteriores) => new Map(anteriores).set(conta, linha));
  }

  return (
    <form action={acao} className="flex flex-col gap-4" noValidate aria-describedby={idAviso}>
      <input type="hidden" name="itens" value={JSON.stringify(mudancas)} />
      <div className="relative overflow-x-auto quadro">
        <table className="w-full min-w-[900px] border-collapse text-sm">
          <caption className="sr-only">
            Plano de contas com a linha de relatório em vigor e o seletor para escolher outra linha.
          </caption>
          <thead>
            <tr className="text-suave">
              <th scope="col" className="border-b border-borda px-3 py-3 text-left font-medium">
                Conta
              </th>
              <th scope="col" className="border-b border-borda px-3 py-3 text-left font-medium">
                Nome
              </th>
              <th scope="col" className="border-b border-borda px-3 py-3 text-left font-medium">
                Linha em vigor
              </th>
              <th scope="col" className="border-b border-borda px-3 py-3 text-left font-medium">
                Linha própria
              </th>
            </tr>
          </thead>
          <tbody>
            {contas.map((conta) => {
              const idSeletor = `linha-${conta.conta}`;
              const opcoes = opcoesPorGrupo[conta.grupoConta] ?? [];
              const alterada = contasAlteradas.has(conta.conta);
              return (
                <tr key={conta.conta} className={`border-b border-borda last:border-b-0 ${alterada ? "bg-fundo" : ""}`}>
                  <th scope="row" className="px-3 py-2 text-left align-middle font-normal whitespace-nowrap tabular-nums">
                    {conta.conta}
                    {!conta.analitica && <span className="block text-xs text-suave">sintética</span>}
                  </th>
                  <td className="px-3 py-2 align-middle">
                    <label htmlFor={idSeletor}>{conta.nome}</label>
                  </td>
                  <td className={`px-3 py-2 align-middle ${conta.linhaEfetiva === null ? "text-atencao" : ""}`}>
                    {textoLinhaAtual(conta, rotulosLinha)}
                  </td>
                  <td className="px-3 py-2 align-middle">
                    <select
                      id={idSeletor}
                      value={escolhas.get(conta.conta) ?? conta.linha ?? ""}
                      onChange={(evento) => escolher(conta.conta, evento.target.value)}
                      className={classeCampo}
                    >
                      <option value="">Sem linha própria</option>
                      {opcoes.map((opcao) => (
                        <option key={opcao.linha} value={opcao.linha}>
                          {opcao.rotulo}
                        </option>
                      ))}
                    </select>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {estado.erro && (
        <p id="erro-mapa" role="alert" className="rounded-lg border border-alerta px-3.5 py-2.5 text-sm text-alerta">
          {estado.erro}
        </p>
      )}
      {estado.sucesso && (
        <p id="sucesso-mapa" role="status" className="rounded-lg border border-entrada px-3.5 py-2.5 text-sm text-entrada">
          {estado.sucesso}
        </p>
      )}

      <div className="flex flex-wrap items-center gap-4">
        <button
          type="submit"
          disabled={enviando || mudancas.length === 0 || mudancas.length > maximoItensMapa}
          className="min-h-12 w-fit cursor-pointer rounded-lg bg-menu px-6 text-base font-semibold text-menu-texto disabled:cursor-not-allowed disabled:opacity-60"
        >
          {enviando ? "Gravando..." : "Gravar mapa"}
        </button>
        <p aria-live="polite" className="text-sm text-suave">
          {mudancas.length === 0
            ? "Nenhuma conta alterada."
            : mudancas.length === 1
              ? "1 conta alterada."
              : `${mudancas.length} contas alteradas.`}
        </p>
      </div>
    </form>
  );
}
