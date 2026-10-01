"use client";

import { useSyncExternalStore } from "react";

const assinarNada = () => () => {};

// Recharts escreve style inline no HTML do servidor, e a CSP com nonce bloqueia esse atributo.
// Desenhado só no navegador, o React aplica o estilo pelo DOM e a CSP não barra.
export function useNoNavegador(): boolean {
  return useSyncExternalStore(
    assinarNada,
    () => true,
    () => false,
  );
}
