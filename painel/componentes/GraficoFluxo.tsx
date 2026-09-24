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
import { formatarMes, formatarReal, formatarRealCompacto } from "@/lib/formatar";
import type { PontoFluxo } from "@/lib/serie-fluxo";

// Cópia dos tokens de globals.css para os atributos SVG do recharts. Mudou a paleta lá, muda aqui.
const cores = {
  entrada: "#2f5d46",
  repasse: "#9cbf8c",
  saida: "#4a4543",
  atencao: "#8a5a0b",
  superficie: "#ffffff",
  borda: "#dccbc6",
  suave: "#6a5552",
  texto: "#221a19",
};

type Serie = {
  chave: keyof PontoFluxo;
  rotulo: string;
  pilha: "entradas" | "saidas";
  preenchimento: string;
  cor: string;
};

const seriesEntradaDireta: Serie[] = [
  { chave: "entradaDiretaRealizada", rotulo: "Entrada direta realizada", pilha: "entradas", preenchimento: cores.entrada, cor: cores.entrada },
  { chave: "entradaDiretaPrevista", rotulo: "Entrada direta prevista", pilha: "entradas", preenchimento: "url(#fluxo-hachura-entrada)", cor: cores.entrada },
];

const seriesRepasseSemAtraso: Serie[] = [
  { chave: "repasseRealizado", rotulo: "Repasse realizado", pilha: "entradas", preenchimento: cores.repasse, cor: cores.repasse },
  { chave: "repassePrevisto", rotulo: "Repasse previsto", pilha: "entradas", preenchimento: "url(#fluxo-hachura-repasse)", cor: cores.repasse },
];

const seriesRepasseComAtraso: Serie[] = [
  { chave: "repasseCenario", rotulo: "Repasse no cenário (realizado e previsto)", pilha: "entradas", preenchimento: "url(#fluxo-hachura-repasse-cenario)", cor: cores.repasse },
];

const seriesSaida: Serie[] = [
  { chave: "saidaRealizada", rotulo: "Saída realizada", pilha: "saidas", preenchimento: cores.saida, cor: cores.saida },
  { chave: "saidaPrevista", rotulo: "Saída prevista", pilha: "saidas", preenchimento: "url(#fluxo-hachura-saida)", cor: cores.saida },
  { chave: "saidaVencida", rotulo: "Saída vencida", pilha: "saidas", preenchimento: cores.atencao, cor: cores.atencao },
];

function montarSeries(comAtraso: boolean): Serie[] {
  return [...seriesEntradaDireta, ...(comAtraso ? seriesRepasseComAtraso : seriesRepasseSemAtraso), ...seriesSaida];
}

function Hachura({ id, cor, angulo }: { id: string; cor: string; angulo: number }) {
  return (
    <pattern id={id} width="6" height="6" patternUnits="userSpaceOnUse" patternTransform={`rotate(${angulo})`}>
      <rect width="6" height="6" fill={cores.superficie} />
      <line x1="0" y1="0" x2="0" y2="6" stroke={cor} strokeWidth="3" />
    </pattern>
  );
}

// Os padrões ficam num SVG à parte para servir às barras e às amostras da legenda.
function DefinicoesHachura() {
  return (
    <svg width="0" height="0" className="absolute" aria-hidden="true" focusable="false">
      <defs>
        <Hachura id="fluxo-hachura-entrada" cor={cores.entrada} angulo={45} />
        <Hachura id="fluxo-hachura-repasse" cor={cores.repasse} angulo={45} />
        <Hachura id="fluxo-hachura-repasse-cenario" cor={cores.repasse} angulo={135} />
        <Hachura id="fluxo-hachura-saida" cor={cores.saida} angulo={45} />
      </defs>
    </svg>
  );
}

function Legenda({ series }: { series: Serie[] }) {
  return (
    <ul className="flex flex-wrap gap-x-5 gap-y-2 text-sm text-texto">
      {series.map((serie) => (
        <li key={serie.chave} className="flex items-center gap-2">
          <svg width="14" height="14" aria-hidden="true" focusable="false">
            <rect width="14" height="14" rx="3" fill={serie.preenchimento} stroke={serie.cor} strokeWidth="1" />
          </svg>
          {serie.rotulo}
        </li>
      ))}
      <li className="flex items-center gap-2">
        <svg width="18" height="14" aria-hidden="true" focusable="false">
          <line x1="0" y1="7" x2="18" y2="7" stroke={cores.texto} strokeWidth="2" />
        </svg>
        Saldo acumulado (gráfico de baixo)
      </li>
    </ul>
  );
}

function valorCelula(valor: PontoFluxo[keyof PontoFluxo]): string {
  return typeof valor === "number" ? formatarReal(valor) : "sem dado";
}

// sr-only vai num div porque a tabela ignora a largura de 1px e vazaria para o lado em tela estreita.
function TabelaEquivalente({ serie, series }: { serie: PontoFluxo[]; series: Serie[] }) {
  return (
    <div className="sr-only">
      <table>
        <caption>Fluxo de caixa mensal da obra, em reais, com o saldo acumulado</caption>
        <thead>
          <tr>
            <th scope="col">Mês</th>
            {series.map((item) => (
              <th key={item.chave} scope="col">
                {item.rotulo}
              </th>
            ))}
            <th scope="col">Saldo acumulado</th>
          </tr>
        </thead>
        <tbody>
          {serie.map((ponto) => (
            <tr key={ponto.competencia}>
              <th scope="row">{formatarMes(ponto.competencia)}</th>
              {series.map((item) => (
                <td key={item.chave}>{valorCelula(ponto[item.chave])}</td>
              ))}
              <td>{valorCelula(ponto.saldoAcumulado)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

const assinarNada = () => () => {};

// Recharts escreve style inline no HTML do servidor, e a CSP com nonce bloqueia esse atributo.
// Desenhado só no navegador, o React aplica o estilo pelo DOM e a CSP não barra.
function useNoNavegador(): boolean {
  return useSyncExternalStore(
    assinarNada,
    () => true,
    () => false,
  );
}

const eixoComum = {
  tick: { fill: cores.suave, fontSize: 12 },
  tickLine: false,
  axisLine: { stroke: cores.borda },
};

function formatarDica(valor: unknown, nome: unknown): [string, string] {
  return [typeof valor === "number" ? formatarReal(valor) : "sem dado", String(nome)];
}

export function GraficoFluxo({
  serie,
  comAtraso,
  mesAtual,
}: {
  serie: PontoFluxo[];
  comAtraso: boolean;
  mesAtual: string;
}) {
  const noNavegador = useNoNavegador();
  const series = montarSeries(comAtraso);
  const temMesAtual = serie.some((ponto) => ponto.competencia === mesAtual);

  return (
    <div className="flex flex-col gap-4">
      <DefinicoesHachura />
      <Legenda series={series} />
      <p className="text-sm text-suave">
        Cheio é realizado; hachurado é previsto.
        {comAtraso &&
          " No cenário com atraso, o banco devolve o repasse de cada mês numa conta só, com o realizado e o previsto já deslocado."}
        {" "}Parcela a receber vencida não entra nas barras nem no saldo: ela aparece no bloco Vencidos.
      </p>

      <div aria-hidden="true" className="flex flex-col gap-2">
        <div className="h-[320px] w-full">
          {noNavegador && (
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={serie} syncId="fluxo-obra" accessibilityLayer={false} barGap={2} margin={{ top: 8, right: 8, bottom: 0, left: 8 }}>
                <CartesianGrid vertical={false} stroke={cores.borda} strokeWidth={1} />
                <XAxis dataKey="competencia" tickFormatter={formatarMes} minTickGap={16} {...eixoComum} />
                <YAxis tickFormatter={formatarRealCompacto} width={72} {...eixoComum} />
                <Tooltip formatter={formatarDica} labelFormatter={(rotulo) => formatarMes(String(rotulo))} />
                {temMesAtual && <ReferenceLine x={mesAtual} stroke={cores.texto} strokeWidth={1} label={{ value: "hoje", position: "insideTopLeft", fill: cores.texto, fontSize: 12 }} />}
                {series.map((item) => (
                  <Bar
                    key={item.chave}
                    dataKey={item.chave}
                    name={item.rotulo}
                    stackId={item.pilha}
                    fill={item.preenchimento}
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

        <p className="text-sm font-medium text-texto">Saldo acumulado</p>
        <div className="h-[180px] w-full">
          {noNavegador && (
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={serie} syncId="fluxo-obra" accessibilityLayer={false} margin={{ top: 8, right: 8, bottom: 0, left: 8 }}>
                <CartesianGrid vertical={false} stroke={cores.borda} strokeWidth={1} />
                <XAxis dataKey="competencia" tickFormatter={formatarMes} minTickGap={16} {...eixoComum} />
                <YAxis tickFormatter={formatarRealCompacto} width={72} {...eixoComum} />
                <Tooltip formatter={formatarDica} labelFormatter={(rotulo) => formatarMes(String(rotulo))} />
                <ReferenceLine y={0} stroke={cores.suave} strokeWidth={1} />
                {temMesAtual && <ReferenceLine x={mesAtual} stroke={cores.texto} strokeWidth={1} />}
                <Line
                  dataKey="saldoAcumulado"
                  name="Saldo acumulado"
                  type="linear"
                  stroke={cores.texto}
                  strokeWidth={2}
                  dot={false}
                  activeDot={{ r: 4, stroke: cores.superficie, strokeWidth: 2 }}
                  connectNulls
                  isAnimationActive={false}
                />
              </LineChart>
            </ResponsiveContainer>
          )}
        </div>
      </div>

      <TabelaEquivalente serie={serie} series={series} />
    </div>
  );
}
