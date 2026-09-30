"use client";

import {
  CartesianGrid,
  Line,
  LineChart,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { cores } from "@/lib/cores-grafico";
import type { PontoSimulacao } from "@/lib/consultas/simulacao";
import { formatarMes, formatarReal, formatarRealCompacto } from "@/lib/formatar";
import { useNoNavegador } from "@/lib/no-navegador";

function formatarDica(valor: unknown, nome: unknown): [string, string] {
  return [typeof valor === "number" ? formatarReal(valor) : "sem dado", String(nome)];
}

// Duas linhas do saldo acumulado da obra: como está hoje e com as vendas simuladas. A tabela
// escondida repete a série para leitor de tela.
export function GraficoSimulacao({ serie, mesAtual }: { serie: PontoSimulacao[]; mesAtual: string }) {
  const noNavegador = useNoNavegador();
  const temMesAtual = serie.some((ponto) => ponto.competencia === mesAtual);

  return (
    <div className="flex flex-col gap-3">
      <ul className="flex flex-wrap gap-x-5 gap-y-2 text-sm" aria-hidden="true">
        <li className="flex items-center gap-2">
          <svg width="18" height="14" focusable="false">
            <line x1="0" y1="7" x2="18" y2="7" stroke={cores.suave} strokeWidth="2" strokeDasharray="4 3" />
          </svg>
          Saldo acumulado de hoje
        </li>
        <li className="flex items-center gap-2">
          <svg width="18" height="14" focusable="false">
            <line x1="0" y1="7" x2="18" y2="7" stroke={cores.entrada} strokeWidth="3" />
          </svg>
          Com as vendas simuladas
        </li>
      </ul>
      <div aria-hidden="true" className="h-[320px] w-full">
        {noNavegador && (
          <ResponsiveContainer width="100%" height="100%">
            <LineChart data={serie} accessibilityLayer={false} margin={{ top: 8, right: 8, bottom: 0, left: 8 }}>
              <CartesianGrid vertical={false} stroke={cores.borda} strokeWidth={1} />
              <XAxis
                dataKey="competencia"
                tickFormatter={formatarMes}
                minTickGap={16}
                tick={{ fill: cores.suave, fontSize: 12 }}
                tickLine={false}
                axisLine={{ stroke: cores.borda }}
              />
              <YAxis
                tickFormatter={formatarRealCompacto}
                width={72}
                tick={{ fill: cores.suave, fontSize: 12 }}
                tickLine={false}
                axisLine={{ stroke: cores.borda }}
              />
              <Tooltip formatter={formatarDica} labelFormatter={(rotulo) => formatarMes(String(rotulo))} />
              <ReferenceLine y={0} stroke={cores.suave} strokeWidth={1} />
              {temMesAtual && (
                <ReferenceLine
                  x={mesAtual}
                  stroke={cores.texto}
                  strokeWidth={1}
                  label={{ value: "hoje", position: "insideTopLeft", fill: cores.texto, fontSize: 12 }}
                />
              )}
              <Line
                dataKey="saldoAtual"
                name="Saldo acumulado de hoje"
                type="linear"
                stroke={cores.suave}
                strokeWidth={2}
                strokeDasharray="4 3"
                dot={false}
                isAnimationActive={false}
              />
              <Line
                dataKey="saldoSimulado"
                name="Com as vendas simuladas"
                type="linear"
                stroke={cores.entrada}
                strokeWidth={3}
                dot={false}
                activeDot={{ r: 4, stroke: cores.superficie, strokeWidth: 2 }}
                isAnimationActive={false}
              />
            </LineChart>
          </ResponsiveContainer>
        )}
      </div>
      <div className="sr-only">
        <table>
          <caption>Saldo acumulado da obra por mês, hoje e com as vendas simuladas, em reais</caption>
          <thead>
            <tr>
              <th scope="col">Mês</th>
              <th scope="col">Entrada direta simulada</th>
              <th scope="col">Repasse simulado</th>
              <th scope="col">Saldo acumulado de hoje</th>
              <th scope="col">Saldo com as vendas simuladas</th>
            </tr>
          </thead>
          <tbody>
            {serie.map((ponto) => (
              <tr key={ponto.competencia}>
                <th scope="row">{formatarMes(ponto.competencia)}</th>
                <td>{formatarReal(ponto.entradaDireta)}</td>
                <td>{formatarReal(ponto.repasse)}</td>
                <td>{formatarReal(ponto.saldoAtual)}</td>
                <td>{formatarReal(ponto.saldoSimulado)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
