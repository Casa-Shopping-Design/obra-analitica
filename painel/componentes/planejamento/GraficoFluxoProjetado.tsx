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
import type { PontoFluxoProjetado } from "@/componentes/planejamento/serie-projetada";
import { formatarMes, formatarReal, formatarRealCompacto } from "@/lib/formatar";

// Cópia dos tokens de globals.css para os atributos SVG do recharts. Mudou a paleta lá, muda aqui.
const cores = {
  entrada: "#2f5d46",
  saida: "#4a4543",
  texto: "#221a19",
  tijolo: "#b5462f",
  superficie: "#ffffff",
  borda: "#dccbc6",
  suave: "#6a5552",
};

const assinarNada = () => () => {};

// Recharts escreve style inline no HTML do servidor e a CSP com nonce bloqueia; desenha só no navegador.
function useNoNavegador(): boolean {
  return useSyncExternalStore(
    assinarNada,
    () => true,
    () => false,
  );
}

const eixoComum = { tick: { fill: cores.suave, fontSize: 12 }, tickLine: false, axisLine: { stroke: cores.borda } };

function formatarDica(valor: unknown, nome: unknown): [string, string] {
  return [typeof valor === "number" ? formatarReal(valor) : "sem valor", String(nome)];
}

function Hachura({ id, cor }: { id: string; cor: string }) {
  return (
    <pattern id={id} width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
      <rect width="6" height="6" fill={cores.superficie} />
      <line x1="0" y1="0" x2="0" y2="6" stroke={cor} strokeWidth="3" />
    </pattern>
  );
}

const barras = [
  { chave: "entradasRealizadas", rotulo: "Entradas realizadas", fill: cores.entrada, pilha: "entradas" },
  { chave: "entradasPrevistas", rotulo: "Entradas do mês de referência em diante", fill: "url(#projetado-hachura-entrada)", pilha: "entradas" },
  { chave: "saidasRealizadas", rotulo: "Saídas realizadas", fill: cores.saida, pilha: "saidas" },
  { chave: "saidasPrevistas", rotulo: "Saídas do mês de referência em diante", fill: "url(#projetado-hachura-saida)", pilha: "saidas" },
] as const;

// aria-hidden: a tabela mês a mês da mesma página traz todos os números para leitor de tela.
export function GraficoFluxoProjetado({ serie, mesReferencia }: { serie: PontoFluxoProjetado[]; mesReferencia: string }) {
  const noNavegador = useNoNavegador();
  const temMes = serie.some((ponto) => ponto.competencia === mesReferencia);

  return (
    <div className="flex flex-col gap-4">
      <svg width="0" height="0" className="absolute" aria-hidden="true" focusable="false">
        <defs>
          <Hachura id="projetado-hachura-entrada" cor={cores.entrada} />
          <Hachura id="projetado-hachura-saida" cor={cores.saida} />
        </defs>
      </svg>
      <ul className="flex flex-wrap gap-x-5 gap-y-2 text-sm">
        {barras.map((barra) => (
          <li key={barra.chave} className="flex items-center gap-2">
            <svg width="14" height="14" aria-hidden="true" focusable="false">
              <rect width="14" height="14" rx="3" fill={barra.fill} stroke={barra.chave.startsWith("entrada") ? cores.entrada : cores.saida} />
            </svg>
            {barra.rotulo}
          </li>
        ))}
        <li className="flex items-center gap-2">
          <svg width="18" height="14" aria-hidden="true" focusable="false">
            <line x1="0" y1="7" x2="18" y2="7" stroke={cores.texto} strokeWidth="2" />
          </svg>
          Caixa gerado acumulado
        </li>
        <li className="flex items-center gap-2">
          <svg width="18" height="14" aria-hidden="true" focusable="false">
            <line x1="0" y1="7" x2="18" y2="7" stroke={cores.tijolo} strokeWidth="2" strokeDasharray="4 3" />
          </svg>
          Sem financiamento pendente
        </li>
      </ul>
      <div aria-hidden="true" className="flex flex-col gap-2">
        <div className="h-[300px] w-full">
          {noNavegador && (
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={serie} syncId="fluxo-projetado" accessibilityLayer={false} barGap={2} margin={{ top: 8, right: 8, bottom: 0, left: 8 }}>
                <CartesianGrid vertical={false} stroke={cores.borda} />
                <XAxis dataKey="competencia" tickFormatter={formatarMes} minTickGap={16} {...eixoComum} />
                <YAxis tickFormatter={formatarRealCompacto} width={72} {...eixoComum} />
                <Tooltip formatter={formatarDica} labelFormatter={(rotulo) => formatarMes(String(rotulo))} />
                {temMes && <ReferenceLine x={mesReferencia} stroke={cores.texto} label={{ value: "referência", position: "insideTopLeft", fill: cores.texto, fontSize: 12 }} />}
                {barras.map((barra) => (
                  <Bar key={barra.chave} dataKey={barra.chave} name={barra.rotulo} stackId={barra.pilha} fill={barra.fill} stroke={cores.superficie} strokeWidth={1} maxBarSize={24} isAnimationActive={false} />
                ))}
              </BarChart>
            </ResponsiveContainer>
          )}
        </div>
        <p className="text-sm font-medium">Caixa gerado acumulado (não é saldo bancário)</p>
        <div className="h-[200px] w-full">
          {noNavegador && (
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={serie} syncId="fluxo-projetado" accessibilityLayer={false} margin={{ top: 8, right: 8, bottom: 0, left: 8 }}>
                <CartesianGrid vertical={false} stroke={cores.borda} />
                <XAxis dataKey="competencia" tickFormatter={formatarMes} minTickGap={16} {...eixoComum} />
                <YAxis tickFormatter={formatarRealCompacto} width={72} {...eixoComum} />
                <Tooltip formatter={formatarDica} labelFormatter={(rotulo) => formatarMes(String(rotulo))} />
                <ReferenceLine y={0} stroke={cores.suave} />
                {temMes && <ReferenceLine x={mesReferencia} stroke={cores.texto} />}
                <Line dataKey="caixa" name="Caixa gerado acumulado" type="linear" stroke={cores.texto} strokeWidth={2} dot={false} isAnimationActive={false} />
                <Line dataKey="caixaConservador" name="Sem financiamento pendente" type="linear" stroke={cores.tijolo} strokeWidth={2} strokeDasharray="6 4" dot={false} isAnimationActive={false} />
              </LineChart>
            </ResponsiveContainer>
          )}
        </div>
      </div>
    </div>
  );
}
