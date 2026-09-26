"use client";

import { useSyncExternalStore } from "react";
import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import type { PontoRecebimento } from "@/componentes/financeiro/receitas-tela";
import { formatarMes, formatarReal, formatarRealCompacto } from "@/lib/formatar";

// Cópia dos tokens de globals.css (mesma paleta do gráfico de fluxo). Mudou lá, muda aqui.
const cores = {
  entrada: "#2f5d46",
  repasse: "#9cbf8c",
  superficie: "#ffffff",
  borda: "#dccbc6",
  suave: "#6a5552",
};

type Serie = { chave: keyof PontoRecebimento; rotulo: string; pilha: string; preenchimento: string; cor: string };

// Cheio é dinheiro recebido; hachurado é o que o contrato previa para o mês. As duas pilhas ficam lado a lado.
const series: Serie[] = [
  {
    chave: "recebidoDireta",
    rotulo: "Entrada direta recebida",
    pilha: "recebido",
    preenchimento: cores.entrada,
    cor: cores.entrada,
  },
  {
    chave: "recebidoFinanciamento",
    rotulo: "Financiamento recebido",
    pilha: "recebido",
    preenchimento: cores.repasse,
    cor: cores.repasse,
  },
  {
    chave: "previstoDireta",
    rotulo: "Entrada direta prevista no contrato",
    pilha: "previsto",
    preenchimento: "url(#receitas-hachura-entrada)",
    cor: cores.entrada,
  },
  {
    chave: "previstoFinanciamento",
    rotulo: "Financiamento previsto no contrato",
    pilha: "previsto",
    preenchimento: "url(#receitas-hachura-repasse)",
    cor: cores.repasse,
  },
];

function Hachura({ id, cor }: { id: string; cor: string }) {
  return (
    <pattern id={id} width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
      <rect width="6" height="6" fill={cores.superficie} />
      <line x1="0" y1="0" x2="0" y2="6" stroke={cor} strokeWidth="3" />
    </pattern>
  );
}

function valorCelula(valor: number | null): string {
  return valor === null ? "sem lançamento" : formatarReal(valor);
}

const assinarNada = () => () => {};

// Recharts escreve style inline no HTML do servidor e a CSP com nonce barra; desenhado só no navegador, passa.
function useNoNavegador(): boolean {
  return useSyncExternalStore(
    assinarNada,
    () => true,
    () => false,
  );
}

const eixoComum = { tick: { fill: cores.suave, fontSize: 12 }, tickLine: false, axisLine: { stroke: cores.borda } };

function formatarDica(valor: unknown, nome: unknown): [string, string] {
  return [typeof valor === "number" ? formatarReal(valor) : "sem lançamento", String(nome)];
}

export function GraficoRecebimentos({ pontos, legenda }: { pontos: PontoRecebimento[]; legenda: string }) {
  const noNavegador = useNoNavegador();

  return (
    <div className="flex flex-col gap-4">
      <svg width="0" height="0" className="absolute" aria-hidden="true" focusable="false">
        <defs>
          <Hachura id="receitas-hachura-entrada" cor={cores.entrada} />
          <Hachura id="receitas-hachura-repasse" cor={cores.repasse} />
        </defs>
      </svg>
      <ul className="flex flex-wrap gap-x-5 gap-y-2 text-sm">
        {series.map((serie) => (
          <li key={serie.chave} className="flex items-center gap-2">
            <svg width="14" height="14" aria-hidden="true" focusable="false">
              <rect width="14" height="14" rx="3" fill={serie.preenchimento} stroke={serie.cor} strokeWidth="1" />
            </svg>
            {serie.rotulo}
          </li>
        ))}
      </ul>
      <p className="text-sm text-suave">
        Em cada mês, a barra da esquerda é o que entrou no caixa e a da direita, hachurada, o que as parcelas previam
        pelo vencimento.
      </p>
      <div aria-hidden="true" className="h-[300px] w-full">
        {noNavegador && (
          <ResponsiveContainer width="100%" height="100%">
            <BarChart
              data={pontos}
              accessibilityLayer={false}
              barGap={2}
              margin={{ top: 8, right: 8, bottom: 0, left: 8 }}
            >
              <CartesianGrid vertical={false} stroke={cores.borda} strokeWidth={1} />
              <XAxis dataKey="competencia" tickFormatter={formatarMes} minTickGap={16} {...eixoComum} />
              <YAxis tickFormatter={formatarRealCompacto} width={72} {...eixoComum} />
              <Tooltip formatter={formatarDica} labelFormatter={(rotulo) => formatarMes(String(rotulo))} />
              {series.map((serie) => (
                <Bar
                  key={serie.chave}
                  dataKey={serie.chave}
                  name={serie.rotulo}
                  stackId={serie.pilha}
                  fill={serie.preenchimento}
                  stroke={cores.superficie}
                  strokeWidth={1}
                  maxBarSize={24}
                  isAnimationActive={false}
                />
              ))}
            </BarChart>
          </ResponsiveContainer>
        )}
      </div>
      <div className="sr-only">
        <table>
          <caption>{legenda}</caption>
          <thead>
            <tr>
              <th scope="col">Mês</th>
              {series.map((serie) => (
                <th key={serie.chave} scope="col">
                  {serie.rotulo}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {pontos.map((ponto) => (
              <tr key={ponto.competencia}>
                <th scope="row">{formatarMes(ponto.competencia)}</th>
                {series.map((serie) => (
                  <td key={serie.chave}>{valorCelula(ponto[serie.chave] as number | null)}</td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
