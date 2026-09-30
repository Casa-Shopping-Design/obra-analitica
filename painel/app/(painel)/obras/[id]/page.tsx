import type { Metadata } from "next";
import Link from "next/link";
import { CartaoIndicador, IndicadoresObra } from "@/componentes/CartaoIndicador";
import { GraficoFluxo } from "@/componentes/GraficoFluxo";
import { IndicadorVgv } from "@/componentes/IndicadorVgv";
import { LinksObra } from "@/componentes/LinksObra";
import { SecaoAlertas } from "@/componentes/ListaAlertas";
import { SeletorCenario } from "@/componentes/SeletorCenario";
import { listarAlertas } from "@/lib/consultas/carteira";
import { cenariosAtraso, listarFluxoCenario, listarFluxoMensal, type MesesAtraso } from "@/lib/consultas/fluxo";
import { buscarPosicaoObra } from "@/lib/consultas/posicao";
import { mensagens } from "@/lib/mensagens";
import { mesCorrente, montarSerieFluxo } from "@/lib/serie-fluxo";

export const metadata: Metadata = { title: "Obra" };

const formatoUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function lerCenario(valor: string | string[] | undefined): MesesAtraso {
  const meses = Number(Array.isArray(valor) ? valor[0] : valor);
  return cenariosAtraso.find((opcao) => opcao === meses) ?? 0;
}

// Quatro consultas no máximo, em paralelo: posição da obra, alertas, fluxo mensal e, só com atraso, o cenário.
// Alerta que falha não derruba a tela; a seção mostra o aviso.
async function carregarObra(centroCustoId: string, mesesAtraso: MesesAtraso) {
  try {
    const [posicao, alertas, fluxoMensal, fluxoCenario] = await Promise.all([
      buscarPosicaoObra(centroCustoId),
      listarAlertas(centroCustoId).catch(() => null),
      listarFluxoMensal(centroCustoId),
      mesesAtraso > 0 ? listarFluxoCenario(centroCustoId, mesesAtraso) : Promise.resolve(null),
    ]);
    return { posicao, alertas, fluxoMensal, fluxoCenario };
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

  const obra = await carregarObra(id, mesesAtraso);
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

  const { posicao } = obra;
  const mesAtual = mesCorrente();
  const serie = montarSerieFluxo(obra.fluxoMensal, obra.fluxoCenario, mesAtual);

  return (
    <>
      <div className="flex flex-col gap-2">
        <Link href="/" className="text-sm text-suave underline underline-offset-4 hover:text-texto">
          Visão geral
        </Link>
        <h1 className="font-serif text-[34px] font-semibold">{posicao.obra}</h1>
        <LinksObra id={posicao.centro_custo_id} />
      </div>

      <section aria-label="Resumo da obra" className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <div className="sm:col-span-2 xl:col-span-4">
          <IndicadorVgv valores={posicao} emCartao />
        </div>
        <IndicadoresObra posicao={posicao} emCartao />
      </section>

      {obra.alertas?.length !== 0 && <SecaoAlertas alertas={obra.alertas} mostrarObra={false} />}

      <section aria-labelledby="titulo-fluxo" className="flex flex-col gap-5 rounded-xl border border-borda bg-superficie p-5">
        <div className="flex flex-col gap-1">
          <h2 id="titulo-fluxo" className="font-serif text-2xl font-semibold">
            Fluxo de caixa por mês
          </h2>
          <p className="text-sm text-suave">12 meses para trás e 24 para frente, a partir do mês atual.</p>
        </div>
        <SeletorCenario mesesAtraso={mesesAtraso} />
        {serie.length === 0 ? (
          <p>{mensagens.obra.semMovimento}</p>
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
