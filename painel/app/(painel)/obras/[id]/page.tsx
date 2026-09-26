import type { Metadata } from "next";
import Link from "next/link";
import { CartaoIndicador, IndicadoresObra, type AporteProjetado } from "@/componentes/CartaoIndicador";
import { GraficoFluxo } from "@/componentes/GraficoFluxo";
import { SeletorCenario } from "@/componentes/SeletorCenario";
import { cenariosAtraso, listarFluxoCenario, listarFluxoMensal, type MesesAtraso } from "@/lib/consultas/fluxo";
import { buscarPosicaoObra } from "@/lib/consultas/posicao";
import { listarResumoProjecao } from "@/lib/consultas/fluxo";
import { janelaDoHorizonte } from "@/lib/configuracao";
import { buscarPreferenciasTenant } from "@/lib/consultas/configuracao";
import { mensagens, textoSemMovimentoObra } from "@/lib/mensagens";
import { mesCorrente, montarSerieFluxo } from "@/lib/serie-fluxo";

export const metadata: Metadata = { title: "Obra" };

const formatoUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function lerCenario(valor: string | string[] | undefined): MesesAtraso {
  const meses = Number(Array.isArray(valor) ? valor[0] : valor);
  return cenariosAtraso.find((opcao) => opcao === meses) ?? 0;
}

// Aporte da projeção, a mesma fonte da visão geral, da tela de fluxo e do assistente. Se a projeção
// falhar, o cartão mostra "não carregado" e o resto da tela continua.
async function buscarAporte(centroCustoId: string): Promise<AporteProjetado> {
  try {
    const [linha] = await listarResumoProjecao(centroCustoId);
    return linha ? { valor: linha.exposicao_maxima_projetada, parcial: linha.exposicao_parcial } : null;
  } catch {
    return null;
  }
}

// Quatro consultas no máximo, em paralelo: posição, aporte projetado, fluxo mensal e, só com atraso, o cenário.
async function carregarObra(centroCustoId: string, mesesAtraso: MesesAtraso) {
  try {
    const [posicao, aporte, fluxoMensal, fluxoCenario] = await Promise.all([
      buscarPosicaoObra(centroCustoId),
      buscarAporte(centroCustoId),
      listarFluxoMensal(centroCustoId),
      mesesAtraso > 0 ? listarFluxoCenario(centroCustoId, mesesAtraso) : Promise.resolve(null),
    ]);
    return { posicao, aporte, fluxoMensal, fluxoCenario };
  } catch {
    return null;
  }
}

function ObraNaoEncontrada() {
  return (
    <>
      <h1 className="font-serif text-[34px] font-semibold">{mensagens.obra.naoEncontrada}</h1>
      <p>
        <Link href="/" className="underline underline-offset-4 hover:text-menu">
          Voltar para a visão geral
        </Link>
      </p>
    </>
  );
}

export default async function PaginaObra({ params, searchParams }: PageProps<"/obras/[id]">) {
  const { id } = await params;
  const mesesAtraso = lerCenario((await searchParams).cenario);
  if (!formatoUuid.test(id)) return <ObraNaoEncontrada />;

  const [obra, preferencias] = await Promise.all([carregarObra(id, mesesAtraso), buscarPreferenciasTenant()]);
  if (obra === null) {
    return (
      <>
        <h1 className="font-serif text-[34px] font-semibold">Obra</h1>
        <p role="alert" className="text-alerta">
          {mensagens.obra.indisponivel}
        </p>
      </>
    );
  }
  if (!obra.posicao) return <ObraNaoEncontrada />;

  const { posicao, aporte } = obra;
  const mesAtual = mesCorrente();
  // exibicao.meses_grafico: um terço para trás, o resto para frente; 36 meses dão os 12 e 24 de antes.
  const janela = janelaDoHorizonte(preferencias.mesesGrafico);
  const serie = montarSerieFluxo(obra.fluxoMensal, obra.fluxoCenario, mesAtual, janela);

  return (
    <>
      <div className="flex flex-col gap-2">
        <Link href="/" className="text-sm text-suave underline underline-offset-4 hover:text-texto">
          Visão geral
        </Link>
        <h1 className="font-serif text-[34px] font-semibold">{posicao.obra}</h1>
        <Link
          href={`/obras/${posicao.centro_custo_id}/unidades`}
          className="w-fit text-sm font-semibold underline underline-offset-4 hover:text-menu"
        >
          Ver o mapa de unidades
        </Link>
      </div>

      <section aria-label="Resumo da obra" className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <IndicadoresObra posicao={posicao} aporte={aporte} emCartao />
      </section>

      <section aria-labelledby="titulo-fluxo" className="flex flex-col gap-5 rounded-xl border border-borda bg-superficie p-5">
        <div className="flex flex-col gap-1">
          <h2 id="titulo-fluxo" className="font-serif text-2xl font-semibold">
            Fluxo de caixa por mês
          </h2>
          <p className="text-sm text-suave">
            {janela.antes} meses para trás e {janela.depois} para frente, a partir do mês atual.
          </p>
        </div>
        <SeletorCenario mesesAtraso={mesesAtraso} />
        {serie.length === 0 ? (
          <p>{textoSemMovimentoObra(preferencias.mesesGrafico)}</p>
        ) : (
          <GraficoFluxo serie={serie} comAtraso={mesesAtraso > 0} mesAtual={mesAtual} />
        )}
      </section>

      <section aria-labelledby="titulo-vencidos" className="flex flex-col gap-4 rounded-xl border border-borda bg-superficie p-5">
        <h2 id="titulo-vencidos" className="font-serif text-2xl font-semibold">
          Vencidos
        </h2>
        <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
          <CartaoIndicador
            rotulo="Entrada direta vencida"
            chave="vencido_direto"
            valores={[{ valor: Number(posicao.vencido_direto) }]}
          />
          <CartaoIndicador
            rotulo="Repasse atrasado"
            chave="repasse_atrasado"
            valores={[{ valor: Number(posicao.repasse_atrasado) }]}
          />
        </div>
      </section>
    </>
  );
}
