"use client";

import { useRef, useEffect, useState } from "react";
import { createPortal } from "react-dom";

type Mensagem = { tipo: "usuario" | "assistente"; texto: string; erro?: boolean };

const semConexao = "Não foi possível falar com o assistente. Confira a conexão e tente de novo.";
const semResposta = "O assistente não conseguiu responder agora. Tente de novo em alguns minutos.";

export function ChatAssistente() {
  const [aberto, setAberto] = useState(false);
  const [mensagens, setMensagens] = useState<Mensagem[]>([]);
  const [carregando, setCarregando] = useState(false);
  const [entrada, setEntrada] = useState("");
  const containerRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const gatilhoRef = useRef<HTMLButtonElement>(null);

  // O foco volta ao campo só depois que ele deixa de estar desativado; antes disso o navegador ignora.
  useEffect(() => {
    if (aberto && !carregando) inputRef.current?.focus();
  }, [aberto, carregando]);

  useEffect(() => {
    if (!aberto) return;
    const fecharComEsc = (evento: KeyboardEvent) => {
      if (evento.key === "Escape") {
        setAberto(false);
        gatilhoRef.current?.focus();
      }
    };
    document.addEventListener("keydown", fecharComEsc);
    return () => document.removeEventListener("keydown", fecharComEsc);
  }, [aberto]);

  useEffect(() => {
    containerRef.current?.scrollTo({ top: containerRef.current.scrollHeight, behavior: "smooth" });
  }, [mensagens]);

  async function enviarPergunta(e: React.FormEvent) {
    e.preventDefault();
    if (!entrada.trim()) return;

    const pergunta = entrada.trim();
    setEntrada("");
    setMensagens((prev) => [...prev, { tipo: "usuario", texto: pergunta }]);
    setCarregando(true);

    try {
      const res = await fetch("/api/assistente", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ pergunta }),
      });

      const dados = await res.json();

      if (!res.ok || !dados.ok) {
        setMensagens((prev) => [...prev, { tipo: "assistente", texto: dados.erro || semResposta, erro: true }]);
      } else {
        const resposta = dados.resposta || semResposta;
        setMensagens((prev) => [...prev, { tipo: "assistente", texto: resposta }]);
      }
    } catch {
      // Mensagem do navegador ("Failed to fetch") ou JSON quebrado não dizem ao usuário o que fazer.
      setMensagens((prev) => [...prev, { tipo: "assistente", texto: semConexao, erro: true }]);
    } finally {
      setCarregando(false);
    }
  }

  function fechar() {
    setAberto(false);
    gatilhoRef.current?.focus();
  }

  // O gatilho fica no pé do menu, junto dos outros caminhos, e o painel abre colado na borda direita, na
  // altura toda. A conversa é lida como registro: quem falou em cima, o texto embaixo.
  // O painel vai para o body: o menu é sticky e prenderia o z-index dele abaixo das tabelas da tela.
  return (
    <div className="print:hidden">
      <button
        ref={gatilhoRef}
        type="button"
        onClick={() => (aberto ? fechar() : setAberto(true))}
        aria-expanded={aberto}
        aria-controls="chat-assistente"
        className="flex min-h-11 w-full cursor-pointer items-center gap-2 px-4 text-left text-suave hover:text-texto hover:underline hover:underline-offset-4 md:px-5"
      >
        <svg aria-hidden="true" viewBox="0 0 20 20" className="size-4 shrink-0" fill="none" stroke="currentColor" strokeWidth="1.8">
          <path d="M3 4h14v9H8l-5 4z" strokeLinejoin="round" />
        </svg>
        Pergunta rápida
      </button>

      {aberto &&
        createPortal(
          <div
            id="chat-assistente"
            role="dialog"
            aria-labelledby="titulo-chat-assistente"
            className="fixed inset-y-0 right-0 z-50 flex w-full flex-col border-l border-borda bg-superficie text-texto shadow-[-12px_0_32px_rgb(22_33_31/0.10)] sm:w-[420px]"
          >
            <div className="flex items-center justify-between border-b border-borda px-5 py-3">
              <div>
                <h2 id="titulo-chat-assistente" className="font-serif text-lg font-semibold">
                  Pergunta rápida
                </h2>
                <p className="text-sm text-suave">Usa só os números que o seu perfil pode ver.</p>
              </div>
              <button
                type="button"
                onClick={fechar}
                className="flex size-11 cursor-pointer items-center justify-center rounded-lg text-suave hover:bg-trilho hover:text-texto"
                aria-label="Fechar a pergunta rápida"
              >
                <svg aria-hidden="true" viewBox="0 0 20 20" className="size-4" fill="none" stroke="currentColor" strokeWidth="2">
                  <path d="M5 5l10 10M15 5L5 15" strokeLinecap="round" />
                </svg>
              </button>
            </div>
  
            <div ref={containerRef} aria-live="polite" className="flex flex-1 flex-col gap-5 overflow-y-auto px-5 py-4">
              {mensagens.length === 0 && (
                <p className="text-sm text-suave">Pergunte sobre as obras, vendas, custos ou recebíveis.</p>
              )}
  
              {mensagens.map((msg, i) => (
                <div key={i} className={`flex flex-col gap-1 ${msg.tipo === "usuario" ? "border-l-2 border-menu pl-3" : ""}`}>
                  <p className="text-xs font-semibold text-suave">{msg.tipo === "usuario" ? "Você" : "Assistente"}</p>
                  <p className={`text-[15px] leading-relaxed ${msg.erro ? "text-alerta" : ""}`}>{msg.texto}</p>
                </div>
              ))}
  
              {carregando && (
                <p role="status" className="text-sm text-suave">
                  Consultando os números...
                </p>
              )}
            </div>
  
            <form onSubmit={enviarPergunta} className="flex gap-2 border-t border-borda px-5 py-4">
              <label htmlFor="pergunta-chat" className="sr-only">
                Sua pergunta
              </label>
              <input
                id="pergunta-chat"
                ref={inputRef}
                type="text"
                placeholder="Sua pergunta"
                value={entrada}
                onChange={(e) => setEntrada(e.target.value)}
                disabled={carregando}
                className="min-h-11 min-w-0 flex-1 rounded-lg border border-borda px-3 text-[15px] disabled:bg-trilho"
              />
              <button
                type="submit"
                disabled={carregando || !entrada.trim()}
                className="min-h-11 cursor-pointer rounded-lg bg-menu px-4 text-sm font-semibold text-menu-texto hover:bg-menu-ativo disabled:cursor-not-allowed disabled:bg-trilho disabled:text-suave"
              >
                Enviar
              </button>
            </form>
          </div>,
          document.body,
        )}
    </div>
  );
}
