"use client";

import { AvisoErro, type ErroTela } from "@/componentes/AvisoErro";
import { MolduraAcesso } from "@/componentes/MolduraAcesso";

// Erro nas telas fora do painel (entrar, segundo fator, manutenção).
export default function ErroRaiz({ error, retry }: { error: ErroTela; retry: () => void }) {
  return (
    <MolduraAcesso>
      <AvisoErro erro={error} tentarDeNovo={retry} />
    </MolduraAcesso>
  );
}
