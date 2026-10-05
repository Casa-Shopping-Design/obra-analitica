import type { Metadata } from "next";
import { IBM_Plex_Mono, IBM_Plex_Sans, IBM_Plex_Sans_Condensed } from "next/font/google";
import { connection } from "next/server";
import "./globals.css";

// As fontes são baixadas no build e servidas pelo próprio painel, então a CSP fica em font-src 'self'.
const fonteTexto = IBM_Plex_Sans({ subsets: ["latin"], weight: ["400", "500", "600"], variable: "--fonte-texto" });
const fonteTitulo = IBM_Plex_Sans_Condensed({ subsets: ["latin"], weight: ["600"], variable: "--fonte-titulo" });
const fonteNumero = IBM_Plex_Mono({ subsets: ["latin"], weight: ["500"], variable: "--fonte-numero", preload: false });

export const metadata: Metadata = {
  title: { default: "APO", template: "%s | APO" },
  description: "Viabilidade, vendas, custos e resultado do empreendimento num só lugar.",
  robots: { index: false, follow: false },
};

export default async function LayoutRaiz({ children }: LayoutProps<"/">) {
  // Toda página renderiza por requisição, para receber o nonce da CSP gerado no proxy.
  await connection();
  return (
    <html lang="pt-BR" className={`${fonteTexto.variable} ${fonteTitulo.variable} ${fonteNumero.variable} h-full`}>
      <body className="min-h-full font-sans text-base antialiased">{children}</body>
    </html>
  );
}
