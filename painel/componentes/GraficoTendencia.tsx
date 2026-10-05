"use client";

import { CartesianGrid, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { cores } from "@/lib/cores-grafico";
import { formatarMes, formatarPercentual } from "@/lib/formatar";
import { mensagens } from "@/lib/mensagens";
import { useNoNavegador } from "@/lib/no-navegador";
import { formatarMargem, resumoSerie, type PontoTendencia } from "@/lib/serie-tendencia";

// A cor nunca vai sozinha: o estudo é tracejado e as duas linhas têm nome na legenda e na dica.
const linhas = [
  { chave: "margemTendencia", rotulo: "Margem na tendência", cor: cores.menu, traco: undefined },
  { chave: "margemViabilidade", rotulo: "Margem no estudo", cor: cores.referencia, traco: "6 4" },
] as const;

const eixo = {
  tick: { fill: cores.suave, fontSize: 12 },
  tickLine: false,
  axisLine: { stroke: cores.borda },
};

function formatarDica(valor: unknown, nome: unknown): [string, string] {
  return [typeof valor === "number" ? formatarMargem(valor) : "sem base", String(nome)];
}

function ChaveLinha({ cor, traco }: { cor: string; traco?: string }) {
  return (
    <svg width="22" height="10" aria-hidden="true" focusable="false">
      <line x1="1" y1="5" x2="21" y2="5" stroke={cor} strokeWidth="2" strokeDasharray={traco} strokeLinecap="round" />
    </svg>
  );
}

// sr-only vai num div porque a tabela ignora a largura de 1px e vazaria para o lado em tela estreita.
function TabelaEquivalente({ pontos }: { pontos: PontoTendencia[] }) {
  return (
    <div className="sr-only">
      <table>
        <caption>Margem operacional da obra por mês, no estudo e na tendência</caption>
        <thead>
          <tr>
            <th scope="col">Mês</th>
            <th scope="col">Margem no estudo</th>
            <th scope="col">Margem na tendência</th>
          </tr>
        </thead>
        <tbody>
          {pontos.map((ponto) => (
            <tr key={ponto.competencia}>
              <th scope="row">{formatarMes(ponto.competencia)}</th>
              <td>{formatarMargem(ponto.margemViabilidade)}</td>
              <td>{formatarMargem(ponto.margemTendencia)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// Margem da tendência contra a do estudo, mês a mês, num eixo só de percentual.
export function GraficoTendencia({ pontos }: { pontos: PontoTendencia[] }) {
  const noNavegador = useNoNavegador();
  if (pontos.length === 0) return <p className="text-suave">{mensagens.dre.serieVazia}</p>;

  const ultimo = pontos[pontos.length - 1];
  // Com um mês só não há segmento para desenhar; o ponto aparece no lugar da linha.
  const ponto = pontos.length === 1 ? { r: 4, stroke: cores.superficie, strokeWidth: 2 } : false;

  return (
    <div className="flex flex-col gap-3">
      <ul className="flex flex-wrap gap-x-5 gap-y-2 text-sm text-texto">
        {linhas.map((linha) => (
          <li key={linha.chave} className="flex items-center gap-2">
            <ChaveLinha cor={linha.cor} traco={linha.traco} />
            {linha.rotulo}
          </li>
        ))}
      </ul>
      <p className="text-sm text-suave">
        Em {formatarMes(ultimo.competencia)}: tendência{" "}
        <span className="font-semibold text-texto tabular-nums">{formatarMargem(ultimo.margemTendencia)}</span>, estudo{" "}
        <span className="font-semibold text-texto tabular-nums">{formatarMargem(ultimo.margemViabilidade)}</span>.
      </p>
      <div aria-hidden="true" className="h-[240px] w-full">
        {noNavegador && (
          <ResponsiveContainer width="100%" height="100%">
            <LineChart data={pontos} accessibilityLayer={false} margin={{ top: 8, right: 16, bottom: 0, left: 0 }}>
              <CartesianGrid vertical={false} stroke={cores.borda} strokeWidth={1} />
              <XAxis dataKey="competencia" tickFormatter={formatarMes} minTickGap={16} {...eixo} />
              <YAxis domain={["auto", "auto"]} tickFormatter={formatarPercentual} width={56} {...eixo} />
              <Tooltip
                formatter={formatarDica}
                labelFormatter={(rotulo) => formatarMes(String(rotulo))}
                cursor={{ stroke: cores.borda, strokeWidth: 1 }}
              />
              {linhas.map((linha) => (
                <Line
                  key={linha.chave}
                  dataKey={linha.chave}
                  name={linha.rotulo}
                  type="linear"
                  stroke={linha.cor}
                  strokeWidth={2}
                  strokeDasharray={linha.traco}
                  dot={ponto && { ...ponto, fill: linha.cor }}
                  activeDot={{ r: 4, fill: linha.cor, stroke: cores.superficie, strokeWidth: 2 }}
                  isAnimationActive={false}
                />
              ))}
            </LineChart>
          </ResponsiveContainer>
        )}
      </div>
      <TabelaEquivalente pontos={pontos} />
    </div>
  );
}

// A mesma série em miniatura, para a lista de obras. Quem não vê o desenho ouve o primeiro e o último mês.
export function MiniaturaTendencia({ pontos }: { pontos: PontoTendencia[] }) {
  const noNavegador = useNoNavegador();
  const resumo = resumoSerie(pontos);
  if (resumo === null) return <span className="text-xs text-suave">{mensagens.dre.serieVazia}</span>;

  return (
    <>
      <span className="sr-only">{resumo}</span>
      <span aria-hidden="true" className="inline-block h-9 w-32 align-middle">
        {noNavegador && (
          <LineChart width={128} height={36} data={pontos} accessibilityLayer={false} margin={{ top: 4, right: 4, bottom: 4, left: 4 }}>
            <YAxis hide domain={["auto", "auto"]} />
            {linhas.map((linha) => (
              <Line
                key={linha.chave}
                dataKey={linha.chave}
                type="linear"
                stroke={linha.cor}
                strokeWidth={2}
                strokeDasharray={linha.traco}
                dot={pontos.length === 1 ? { r: 3, fill: linha.cor, stroke: cores.superficie, strokeWidth: 1 } : false}
                isAnimationActive={false}
              />
            ))}
          </LineChart>
        )}
      </span>
    </>
  );
}
