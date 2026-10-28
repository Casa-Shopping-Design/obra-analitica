"use client";

import { AvisoErro, type ErroTela } from "@/componentes/AvisoErro";

// Dentro do grupo (painel) o menu continua na tela, para a pessoa seguir para outra tela sem recarregar.
export default function ErroPainel({ error, retry }: { error: ErroTela; retry: () => void }) {
  return <AvisoErro erro={error} tentarDeNovo={retry} />;
}
