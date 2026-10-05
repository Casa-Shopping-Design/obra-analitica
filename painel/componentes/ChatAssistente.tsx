"use client";

import { useRef, useEffect, useState } from "react";

type Mensagem = { tipo: "usuario" | "assistente"; texto: string; erro?: boolean };

export function ChatAssistente() {
  const [aberto, setAberto] = useState(false);
  const [mensagens, setMensagens] = useState<Mensagem[]>([]);
  const [carregando, setCarregando] = useState(false);
  const [entrada, setEntrada] = useState("");
  const containerRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (aberto) inputRef.current?.focus();
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
        setMensagens((prev) => [
          ...prev,
          { tipo: "assistente", texto: dados.erro || "Erro ao processar pergunta", erro: true },
        ]);
      } else {
        const resposta = dados.resposta || "Sem resposta disponível";
        setMensagens((prev) => [...prev, { tipo: "assistente", texto: resposta }]);
      }
    } catch (erro) {
      setMensagens((prev) => [
        ...prev,
        {
          tipo: "assistente",
          texto: erro instanceof Error ? erro.message : "Erro de conexão",
          erro: true,
        },
      ]);
    } finally {
      setCarregando(false);
      inputRef.current?.focus();
    }
  }

  return (
    <>
      {/* Botão flutuante */}
      <button
        onClick={() => setAberto(!aberto)}
        className="fixed bottom-6 right-6 z-40 bg-blue-600 text-white rounded-full w-14 h-14 flex items-center justify-center shadow-lg hover:bg-blue-700 transition-colors"
        aria-label="Abrir chat do assistente"
        title="Pergunte ao assistente"
      >
        <span className="text-2xl">💬</span>
      </button>

      {/* Widget */}
      {aberto && (
        <div className="fixed bottom-24 right-6 z-50 w-96 max-w-[calc(100vw-24px)] h-96 bg-white rounded-lg shadow-2xl border border-cinza-200 flex flex-col overflow-hidden">
          {/* Cabeçalho */}
          <div className="bg-blue-600 text-white p-4 flex justify-between items-center">
            <h2 className="text-lg font-semibold">APO Assistente</h2>
            <button
              onClick={() => setAberto(false)}
              className="text-white hover:bg-blue-700 p-1 rounded"
              aria-label="Fechar"
            >
              ✕
            </button>
          </div>

          {/* Mensagens */}
          <div
            ref={containerRef}
            className="flex-1 overflow-y-auto p-4 space-y-3 bg-cinza-50"
          >
            {mensagens.length === 0 && (
              <p className="text-cinza-500 text-sm">
                Olá! Faça uma pergunta sobre as obras, vendas, custos ou recebíveis.
              </p>
            )}

            {mensagens.map((msg, i) => (
              <div
                key={i}
                className={`flex ${msg.tipo === "usuario" ? "justify-end" : "justify-start"}`}
              >
                <div
                  className={`max-w-xs px-4 py-2 rounded-lg text-sm ${
                    msg.tipo === "usuario"
                      ? "bg-blue-600 text-white rounded-br-none"
                      : msg.erro
                        ? "bg-vermelho-100 text-vermelho-800 rounded-bl-none"
                        : "bg-cinza-200 text-cinza-900 rounded-bl-none"
                  }`}
                >
                  {msg.texto}
                </div>
              </div>
            ))}

            {carregando && (
              <div className="flex justify-start">
                <div className="bg-cinza-200 text-cinza-900 px-4 py-2 rounded-lg rounded-bl-none text-sm">
                  <span className="animate-pulse">Processando...</span>
                </div>
              </div>
            )}
          </div>

          {/* Input */}
          <form onSubmit={enviarPergunta} className="border-t border-cinza-200 p-4 flex gap-2">
            <input
              ref={inputRef}
              type="text"
              placeholder="Sua pergunta..."
              value={entrada}
              onChange={(e) => setEntrada(e.target.value)}
              disabled={carregando}
              className="flex-1 px-3 py-2 border border-cinza-300 rounded text-sm focus:outline-none focus:border-blue-500 disabled:bg-cinza-100"
            />
            <button
              type="submit"
              disabled={carregando || !entrada.trim()}
              className="bg-blue-600 text-white px-4 py-2 rounded text-sm hover:bg-blue-700 disabled:bg-cinza-400 transition-colors"
            >
              Enviar
            </button>
          </form>
        </div>
      )}
    </>
  );
}
