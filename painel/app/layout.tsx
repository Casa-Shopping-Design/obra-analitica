import type { Metadata } from "next";
import { IBM_Plex_Mono, IBM_Plex_Sans, Source_Serif_4 } from "next/font/google";
import { connection } from "next/server";
import "./globals.css";

// As fontes são baixadas no build e servidas pelo próprio painel, então a CSP fica em font-src 'self'.
const fonteTexto = IBM_Plex_Sans({ subsets: ["latin"], weight: ["400", "500", "600"], variable: "--fonte-texto" });
const fonteTitulo = Source_Serif_4({ subsets: ["latin"], weight: ["600"], variable: "--fonte-titulo" });
const fonteNumero = IBM_Plex_Mono({ subsets: ["latin"], weight: ["500"], variable: "--fonte-numero", preload: false });

export const metadata: Metadata = {
  title: { default: "Obra Analítica", template: "%s | Obra Analítica" },
  description: "Caixa, obras e estoque da construtora numa tela só.",
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
