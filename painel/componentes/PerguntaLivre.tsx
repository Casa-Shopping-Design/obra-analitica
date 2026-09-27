"use client";

import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";
import { RespostaPergunta } from "@/componentes/RespostaPergunta";
import type { LinhaResposta } from "@/lib/consultas/perguntas-prontas";
import type { ColunaResposta } from "@/lib/perguntas-prontas";

type RespostaLivre = {
  pergunta: string;
  texto: string;
  tabela: { colunas: ColunaResposta[]; linhas: LinhaResposta[] };
  consultadoEm: string;
  sql?: string;
};

const falhaRede = "Não foi possível falar com o servidor. Confira a conexão e tente de novo.";

export function PerguntaLivre({ limiteLinhas, semDados }: { limiteLinhas: number; semDados: string }) {
  const router = useRouter();
  const [enviando, setEnviando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [resposta, setResposta] = useState<RespostaLivre | null>(null);

  async function enviar(evento: FormEvent<HTMLFormElement>) {
    evento.preventDefault();
    const pergunta = String(new FormData(evento.currentTarget).get("pergunta") ?? "");
    setEnviando(true);
    setErro(null);
    setResposta(null);
    try {
      const retorno = await fetch("/api/assistente", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ pergunta }),
      });
      const corpo = await retorno.json();
      if (corpo.ok) {
        setResposta(corpo as RespostaLivre);
        router.refresh();
      } else {
        setErro(typeof corpo.erro === "string" ? corpo.erro : falhaRede);
      }
    } catch {
      setErro(falhaRede);
    } finally {
      setEnviando(false);
    }
  }

  return (
    <section aria-labelledby="titulo-pergunta-livre" className="flex flex-col gap-3">
      <form onSubmit={enviar} className="flex max-w-2xl flex-col gap-1.5">
        <label id="titulo-pergunta-livre" htmlFor="pergunta-livre" className="font-semibold">
          Pergunta com suas palavras
        </label>
        <p id="nota-pergunta-livre" className="text-sm text-suave">
          Pergunte sobre caixa, recebimentos, pagamentos, vendas ou estoque das obras liberadas para o seu perfil.
        </p>
        <div className="flex flex-col gap-2 sm:flex-row">
          <input
            id="pergunta-livre"
            name="pergunta"
            type="text"
            required
            minLength={3}
            maxLength={500}
            aria-describedby="nota-pergunta-livre"
            className="min-h-12 flex-1 rounded-lg border border-borda bg-superficie px-3.5 text-[15px] text-texto focus-visible:border-texto"
          />
          <button
            type="submit"
            disabled={enviando}
            className="min-h-12 cursor-pointer rounded-lg bg-menu px-5 text-base font-semibold text-menu-texto disabled:cursor-wait disabled:opacity-70"
          >
            {enviando ? "Consultando..." : "Perguntar"}
          </button>
        </div>
      </form>

      <div aria-live="polite" aria-busy={enviando} className="flex flex-col gap-3">
        {enviando && (
          <div className="flex flex-col gap-2 rounded-xl border border-borda bg-superficie p-4" aria-label="Consultando os dados">
            <div className="h-5 w-2/3 animate-pulse rounded bg-trilho" />
            <div className="h-4 w-full animate-pulse rounded bg-trilho" />
            <div className="h-4 w-5/6 animate-pulse rounded bg-trilho" />
          </div>
        )}

        {erro && (
          <p role="alert" className="rounded-lg border border-alerta px-3.5 py-2.5 text-sm text-alerta">
            {erro}
          </p>
        )}

        {resposta && (
          <>
            <p className="max-w-2xl text-base">{resposta.texto}</p>
            <RespostaPergunta
              pergunta={{
                id: "livre",
                pergunta: resposta.pergunta,
                sql: "",
                colunas: resposta.tabela.colunas,
                semResultado: semDados,
              }}
              linhas={resposta.tabela.linhas}
              consultadoEm={resposta.consultadoEm}
              limiteLinhas={limiteLinhas}
            />
            {resposta.sql && (
              <details className="rounded-lg border border-borda bg-superficie p-3">
                <summary className="cursor-pointer text-sm font-medium">Ver a consulta</summary>
                <pre className="mt-2 overflow-x-auto text-xs whitespace-pre-wrap">{resposta.sql}</pre>
              </details>
            )}
          </>
        )}
      </div>
    </section>
  );
}
