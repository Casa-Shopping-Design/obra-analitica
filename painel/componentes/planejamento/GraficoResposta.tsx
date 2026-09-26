"use client";

import { useSyncExternalStore } from "react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  Line,
  LineChart,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import type { GraficoResposta as DadosGrafico } from "@/componentes/planejamento/respostas-perguntas";
import { formatarMes, formatarReal, formatarRealCompacto } from "@/lib/formatar";

// Cópia dos tokens de globals.css (entrada, repasse, saída, atenção) para os atributos SVG do recharts.
// A ordem é fixa: a série n sempre recebe a cor n. Tracejado ganha hachura, para a cor não ser o único sinal.
const coresBarras = ["#2f5d46", "#9cbf8c", "#4a4543", "#8a5a0b"];
const coresLinhas = ["#221a19", "#b5462f"];
const superficie = "#ffffff";
const borda = "#dccbc6";
const suave = "#6a5552";

const assinarNada = () => () => {};

// Recharts escreve style inline no HTML do servidor e a CSP com nonce bloqueia; desenha só no navegador.
function useNoNavegador(): boolean {
  return useSyncExternalStore(
    assinarNada,
    () => true,
    () => false,
  );
}

function formatarDica(valor: unknown, nome: unknown): [string, string] {
  return [typeof valor === "number" ? formatarReal(valor) : "sem valor", String(nome)];
}

const eixoComum = { tick: { fill: suave, fontSize: 12 }, tickLine: false, axisLine: { stroke: borda } };

// O gráfico é aria-hidden: a tabela da mesma resposta, logo acima, traz os mesmos números para leitor de tela.
export function GraficoResposta({ grafico, idBase }: { grafico: DadosGrafico; idBase: string }) {
  const noNavegador = useNoNavegador();
  const formatarEixo = (valor: unknown) =>
    grafico.formatoEixo === "mes" ? formatarMes(String(valor)) : String(valor).slice(0, 18);
  const cores = grafico.tipo === "linhas" ? coresLinhas : coresBarras;
  const preenchimento = (indice: number, estilo: string) =>
    estilo === "tracejado" ? `url(#${idBase}-hachura-${indice})` : cores[indice % cores.length];

  return (
    <figure className="flex flex-col gap-3">
      <figcaption className="text-sm font-medium">{grafico.titulo}</figcaption>
      <svg width="0" height="0" className="absolute" aria-hidden="true" focusable="false">
        <defs>
          {grafico.series.map((serie, indice) => (
            <pattern
              key={serie.chave}
              id={`${idBase}-hachura-${indice}`}
              width="6"
              height="6"
              patternUnits="userSpaceOnUse"
              patternTransform="rotate(45)"
            >
              <rect width="6" height="6" fill={superficie} />
              <line x1="0" y1="0" x2="0" y2="6" stroke={cores[indice % cores.length]} strokeWidth="3" />
            </pattern>
          ))}
        </defs>
      </svg>
      <ul className="flex flex-wrap gap-x-5 gap-y-2 text-sm">
        {grafico.series.map((serie, indice) => (
          <li key={serie.chave} className="flex items-center gap-2">
            <svg width="18" height="14" aria-hidden="true" focusable="false">
              {grafico.tipo === "linhas" ? (
                <line
                  x1="0"
                  y1="7"
                  x2="18"
                  y2="7"
                  stroke={cores[indice % cores.length]}
                  strokeWidth="2"
                  strokeDasharray={serie.estilo === "tracejado" ? "4 3" : undefined}
                />
              ) : (
                <rect width="14" height="14" rx="3" fill={preenchimento(indice, serie.estilo)} stroke={cores[indice % cores.length]} />
              )}
            </svg>
            {serie.rotulo}
          </li>
        ))}
      </ul>
      <div aria-hidden="true" className="h-[280px] w-full">
        {noNavegador && (
          <ResponsiveContainer width="100%" height="100%">
            {grafico.tipo === "linhas" ? (
              <LineChart data={grafico.pontos} accessibilityLayer={false} margin={{ top: 8, right: 8, bottom: 0, left: 8 }}>
                <CartesianGrid vertical={false} stroke={borda} />
                <XAxis dataKey={grafico.eixo} tickFormatter={formatarEixo} minTickGap={16} {...eixoComum} />
                <YAxis tickFormatter={formatarRealCompacto} width={72} {...eixoComum} />
                <Tooltip formatter={formatarDica} labelFormatter={(rotulo) => formatarEixo(rotulo)} />
                <ReferenceLine y={0} stroke={suave} />
                {grafico.series.map((serie, indice) => (
                  <Line
                    key={serie.chave}
                    dataKey={serie.chave}
                    name={serie.rotulo}
                    type="linear"
                    stroke={cores[indice % cores.length]}
                    strokeWidth={2}
                    strokeDasharray={serie.estilo === "tracejado" ? "6 4" : undefined}
                    dot={false}
                    activeDot={{ r: 4, stroke: superficie, strokeWidth: 2 }}
                    connectNulls
                    isAnimationActive={false}
                  />
                ))}
              </LineChart>
            ) : (
              <BarChart data={grafico.pontos} accessibilityLayer={false} margin={{ top: 8, right: 8, bottom: 0, left: 8 }}>
                <CartesianGrid vertical={false} stroke={borda} />
                <XAxis dataKey={grafico.eixo} tickFormatter={formatarEixo} interval={0} {...eixoComum} />
                <YAxis tickFormatter={formatarRealCompacto} width={72} {...eixoComum} />
                <Tooltip formatter={formatarDica} labelFormatter={(rotulo) => formatarEixo(rotulo)} />
                {grafico.series.map((serie, indice) => (
                  <Bar
                    key={serie.chave}
                    dataKey={serie.chave}
                    name={serie.rotulo}
                    stackId={grafico.empilhar ? "pilha" : undefined}
                    fill={preenchimento(indice, serie.estilo)}
                    stroke={superficie}
                    strokeWidth={2}
                    maxBarSize={40}
                    isAnimationActive={false}
                  />
                ))}
              </BarChart>
            )}
          </ResponsiveContainer>
        )}
      </div>
    </figure>
  );
}
