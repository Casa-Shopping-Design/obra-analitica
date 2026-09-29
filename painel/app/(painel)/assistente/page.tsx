import type { Metadata } from "next";
import { PerguntaLivre } from "@/componentes/PerguntaLivre";
import { RespostaPergunta } from "@/componentes/RespostaPergunta";
import { listarHistorico, type Historico } from "@/lib/consultas/historico-assistente";
import {
  limiteLinhas,
  responderPerguntaPronta,
  type RespostaPerguntaPronta,
} from "@/lib/consultas/perguntas-prontas";
import { mensagens } from "@/lib/mensagens";
import { buscarPerguntaPronta, perguntasProntas, type IdPerguntaPronta } from "@/lib/perguntas-prontas";
import { formatarData } from "@/lib/formatar";

export const metadata: Metadata = { title: "Assistente" };

async function responder(id: IdPerguntaPronta): Promise<RespostaPerguntaPronta | null> {
  try {
    return await responderPerguntaPronta(id);
  } catch {
    return null;
  }
}

async function lerHistorico(): Promise<Historico | null> {
  try {
    return await listarHistorico();
  } catch {
    return null;
  }
}

const situacaoPergunta: Record<string, string> = {
  pendente: "Em andamento",
  ok: "Respondida",
  recusada: "Recusada",
  erro: "Não executada",
};

function HistoricoPerguntas({ historico }: { historico: Historico | null }) {
  return (
    <section aria-labelledby="titulo-historico" className="flex flex-col gap-2">
      <h2 id="titulo-historico" className="font-serif text-xl font-semibold">
        Suas últimas perguntas
      </h2>
      {!historico && <p role="alert">{mensagens.assistente.historicoIndisponivel}</p>}
      {historico && historico.perguntas.length === 0 && (
        <p className="text-suave">Você ainda não fez perguntas com suas palavras.</p>
      )}
      {historico && historico.perguntas.length > 0 && (
        <ul className="flex flex-col gap-2">
          {historico.perguntas.map((registro) => (
            <li key={registro.id} className="rounded-lg border border-borda bg-superficie p-3">
              <p className="font-medium">{registro.pergunta}</p>
              <p className="text-sm text-suave">
                {formatarData(registro.criado_em)}, {situacaoPergunta[registro.resultado] ?? registro.resultado}
                {registro.resultado === "ok" && registro.linhas_devolvidas !== null &&
                  `, ${registro.linhas_devolvidas === 1 ? "1 linha" : `${registro.linhas_devolvidas} linhas`}`}
              </p>
              {historico.diretor && registro.sql_executado && (
                <details className="mt-2">
                  <summary className="cursor-pointer text-sm font-medium">Ver a consulta</summary>
                  <pre className="mt-2 overflow-x-auto text-xs whitespace-pre-wrap">{registro.sql_executado}</pre>
                </details>
              )}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

// A pergunta escolhida vem na URL só como id; qualquer valor fora da lista é ignorado
// e nunca chega a uma consulta.
export default async function PaginaAssistente({
  searchParams,
}: {
  searchParams: Promise<{ [chave: string]: string | string[] | undefined }>;
}) {
  const { pergunta: idPedido } = await searchParams;
  const idTexto = typeof idPedido === "string" ? idPedido : undefined;
  const pergunta = buscarPerguntaPronta(idTexto);
  const [resposta, historico] = await Promise.all([pergunta ? responder(pergunta.id) : null, lerHistorico()]);

  return (
    <>
      <header className="flex flex-col gap-2">
        <h1 className="font-serif text-[34px] font-semibold">Assistente</h1>
        <p className="max-w-2xl text-suave">
          Escolha uma pergunta pronta ou escreva a sua. A resposta sai direto das tabelas do painel, só com as obras
          liberadas para o seu perfil.
        </p>
      </header>

      <form action="/assistente" method="get" className="flex flex-col gap-3">
        <fieldset className="flex flex-col gap-2">
          <legend className="mb-2 font-semibold">Perguntas prontas</legend>
          <div className="grid gap-2 md:grid-cols-2">
            {perguntasProntas.map((opcao) => {
              const escolhida = opcao.id === pergunta?.id;
              return (
                <button
                  key={opcao.id}
                  type="submit"
                  name="pergunta"
                  value={opcao.id}
                  aria-pressed={escolhida}
                  className={`min-h-12 cursor-pointer rounded-xl border px-4 py-2.5 text-left text-[15px] ${
                    escolhida
                      ? "border-menu bg-menu font-semibold text-menu-texto"
                      : "border-borda bg-superficie hover:border-texto"
                  }`}
                >
                  {opcao.pergunta}
                </button>
              );
            })}
          </div>
        </fieldset>
      </form>

      {idTexto !== undefined && !pergunta && <p role="alert">{mensagens.assistente.perguntaDesconhecida}</p>}

      {pergunta && !resposta && (
        <p role="alert" className="text-alerta">
          {mensagens.assistente.indisponivel}
        </p>
      )}

      {pergunta && resposta && (
        <RespostaPergunta
          pergunta={pergunta}
          linhas={resposta.linhas}
          consultadoEm={resposta.consultadoEm}
          limiteLinhas={limiteLinhas}
        />
      )}

      <PerguntaLivre limiteLinhas={limiteLinhas} semDados={mensagens.assistente.semDados} />

      <HistoricoPerguntas historico={historico} />
    </>
  );
}
