"use client";

import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { cores } from "@/lib/cores-grafico";
import type { LinhaVso } from "@/lib/consultas/estoque";
import { formatarMes, formatarPercentual } from "@/lib/formatar";
import { useNoNavegador } from "@/lib/no-navegador";

const inteiro = new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 0 });
const celula = "px-3 py-2 text-right tabular-nums";

function formatarDica(valor: unknown, nome: unknown): [string, string] {
  return [typeof valor === "number" ? inteiro.format(valor) : "sem dado", String(nome)];
}

// Barras de vendas e distratos por mês e, embaixo, a mesma série em tabela com o VSO.
export function GraficoVso({ linhas }: { linhas: LinhaVso[] }) {
  const noNavegador = useNoNavegador();
  return (
    <div className="flex flex-col gap-4">
      <ul className="flex flex-wrap gap-x-5 gap-y-2 text-sm" aria-hidden="true">
        <li className="flex items-center gap-2">
          <span className="inline-block size-3.5 rounded-sm bg-entrada" />
          Vendas
        </li>
        <li className="flex items-center gap-2">
          <span className="inline-block size-3.5 rounded-sm bg-atencao" />
          Distratos
        </li>
      </ul>
      <div aria-hidden="true" className="h-[220px] w-full">
        {noNavegador && (
          <ResponsiveContainer width="100%" height="100%">
            <BarChart data={linhas} accessibilityLayer={false} barGap={2} margin={{ top: 8, right: 8, bottom: 0, left: 0 }}>
              <CartesianGrid vertical={false} stroke={cores.borda} strokeWidth={1} />
              <XAxis
                dataKey="competencia"
                tickFormatter={formatarMes}
                tick={{ fill: cores.suave, fontSize: 12 }}
                tickLine={false}
                axisLine={{ stroke: cores.borda }}
              />
              <YAxis allowDecimals={false} width={32} tick={{ fill: cores.suave, fontSize: 12 }} tickLine={false} axisLine={{ stroke: cores.borda }} />
              <Tooltip formatter={formatarDica} labelFormatter={(rotulo) => formatarMes(String(rotulo))} />
              <Bar dataKey="vendas" name="Vendas" fill={cores.entrada} isAnimationActive={false} />
              <Bar dataKey="distratos" name="Distratos" fill={cores.atencao} isAnimationActive={false} />
            </BarChart>
          </ResponsiveContainer>
        )}
      </div>
      <div className="overflow-x-auto">
        <table className="w-full min-w-[560px] border-collapse text-sm">
          <caption className="sr-only">Vendas, distratos e VSO por mês</caption>
          <thead>
            <tr className="border-b border-borda text-suave">
              <th scope="col" className="px-3 py-2 text-left font-semibold">Mês</th>
              <th scope="col" className={`${celula} font-semibold`}>Vendas</th>
              <th scope="col" className={`${celula} font-semibold`}>Distratos</th>
              <th scope="col" className={`${celula} font-semibold`}>Vendas líquidas</th>
              <th scope="col" className={`${celula} font-semibold`}>Estoque no início do mês</th>
              <th scope="col" className={`${celula} font-semibold`}>VSO</th>
            </tr>
          </thead>
          <tbody>
            {linhas.map((linha) => (
              <tr key={linha.competencia} className="border-b border-borda">
                <th scope="row" className="px-3 py-2 text-left font-normal">{formatarMes(linha.competencia)}</th>
                <td className={celula}>{inteiro.format(linha.vendas)}</td>
                <td className={celula}>{inteiro.format(linha.distratos)}</td>
                <td className={celula}>{inteiro.format(linha.vendas_liquidas)}</td>
                <td className={celula}>{inteiro.format(linha.estoque_inicio_mes)}</td>
                <td className={celula}>{linha.vso_pct === null ? "sem estoque" : formatarPercentual(linha.vso_pct)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
