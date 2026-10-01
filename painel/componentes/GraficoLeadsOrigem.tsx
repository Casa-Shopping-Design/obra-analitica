"use client";

import { Bar, BarChart, CartesianGrid, LabelList, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { cores } from "@/lib/cores-grafico";
import type { TotalLeadOrigem } from "@/lib/consultas/resumo-origem";
import { useNoNavegador } from "@/lib/no-navegador";

const inteiro = new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 0 });
const alturaBarra = 34;

function formatarDica(valor: unknown): [string, string] {
  return [typeof valor === "number" ? inteiro.format(valor) : "sem dado", "Leads"];
}

// Barras deitadas, uma por origem, porque o nome da origem é longo e no celular não cabe embaixo da barra.
// A tabela abaixo traz os mesmos números para leitor de tela.
export function GraficoLeadsOrigem({ origens }: { origens: TotalLeadOrigem[] }) {
  const noNavegador = useNoNavegador();
  return (
    <div aria-hidden="true" className="w-full">
      {/* A altura depende do número de origens; o style só nasce no navegador, onde a CSP não barra. */}
      {noNavegador && (
        <div style={{ height: origens.length * alturaBarra + 32 }}>
          <ResponsiveContainer width="100%" height="100%">
            <BarChart
              data={origens}
              layout="vertical"
              accessibilityLayer={false}
              barCategoryGap={6}
              margin={{ top: 0, right: 40, bottom: 0, left: 0 }}
            >
              <CartesianGrid horizontal={false} stroke={cores.borda} strokeWidth={1} />
              <XAxis type="number" allowDecimals={false} tick={{ fill: cores.suave, fontSize: 12 }} tickLine={false} axisLine={{ stroke: cores.borda }} />
              <YAxis
                type="category"
                dataKey="origem"
                width={130}
                tick={{ fill: cores.texto, fontSize: 12 }}
                tickLine={false}
                axisLine={{ stroke: cores.borda }}
              />
              <Tooltip formatter={formatarDica} cursor={{ fill: cores.borda, fillOpacity: 0.4 }} />
              <Bar dataKey="leads" name="Leads" fill={cores.entrada} radius={[0, 4, 4, 0]} isAnimationActive={false}>
                <LabelList dataKey="leads" position="right" fill={cores.texto} fontSize={12} formatter={(valor: unknown) => inteiro.format(Number(valor))} />
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        </div>
      )}
    </div>
  );
}
