import type { Metadata } from "next";
import { RespostaPergunta } from "@/componentes/RespostaPergunta";
import {
  limiteLinhas,
  responderPerguntaPronta,
  type RespostaPerguntaPronta,
} from "@/lib/consultas/perguntas-prontas";
import { mensagens } from "@/lib/mensagens";
import { buscarPerguntaPronta, perguntasProntas, type IdPerguntaPronta } from "@/lib/perguntas-prontas";

export const metadata: Metadata = { title: "Assistente" };

async function responder(id: IdPerguntaPronta): Promise<RespostaPerguntaPronta | null> {
  try {
    return await responderPerguntaPronta(id);
  } catch {
    return null;
  }
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
  const resposta = pergunta ? await responder(pergunta.id) : null;

  return (
    <>
      <header className="flex flex-col gap-2">
        <h1 className="font-serif text-[34px] font-semibold">Assistente</h1>
        <p className="max-w-2xl text-suave">
          Escolha uma pergunta. A resposta sai direto das tabelas do painel, só com as obras liberadas para o seu
          perfil.
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

      <div className="flex max-w-2xl flex-col gap-1.5">
        <label htmlFor="pergunta-livre" className="text-sm font-medium">
          Pergunta com suas palavras
        </label>
        <input
          id="pergunta-livre"
          type="text"
          disabled
          aria-describedby="nota-pergunta-livre"
          className="min-h-12 cursor-not-allowed rounded-lg border border-borda bg-trilho px-3.5 text-[15px]"
        />
        <p id="nota-pergunta-livre" className="text-sm text-suave">
          Disponível na entrega 2.
        </p>
      </div>
    </>
  );
}
