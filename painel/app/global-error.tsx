"use client";

import { AvisoErro, type ErroTela } from "@/componentes/AvisoErro";
import { MolduraAcesso } from "@/componentes/MolduraAcesso";
import { mensagens } from "@/lib/mensagens";
import "./globals.css";

// Só aparece quando o próprio layout raiz falha. Monta o documento inteiro, sem as fontes do layout; o
// texto cai na fonte do sistema e continua legível.
export default function ErroGlobal({ error, retry }: { error: ErroTela; retry: () => void }) {
  return (
    <html lang="pt-BR">
      <body className="min-h-full font-sans text-base antialiased">
        <title>{`${mensagens.paginas.erroTitulo} | APO`}</title>
        <MolduraAcesso>
          <AvisoErro erro={error} tentarDeNovo={retry} />
        </MolduraAcesso>
      </body>
    </html>
  );
}
