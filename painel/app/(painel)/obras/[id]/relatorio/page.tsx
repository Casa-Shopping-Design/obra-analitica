import type { Metadata } from "next";
import Link from "next/link";
import { BotaoImprimir } from "@/componentes/BotaoImprimir";
import { AvisoTelaObra } from "@/componentes/CabecalhoTelaObra";
import { IndicadoresObra } from "@/componentes/CartaoIndicador";
import { GraficoFluxo } from "@/componentes/GraficoFluxo";
import { GraficoVso } from "@/componentes/GraficoVso";
import { IndicadorVgv } from "@/componentes/IndicadorVgv";
import { SecaoAlertas } from "@/componentes/ListaAlertas";
import { ResumoEstoque } from "@/componentes/ResumoEstoque";
import { TabelaEstoqueTipologia } from "@/componentes/TabelaEstoqueTipologia";
import { listarAlertas } from "@/lib/consultas/carteira";
import { buscarCobertura, buscarEstoqueObra, listarEstoqueTipologia, listarVsoObra } from "@/lib/consultas/estoque";
import { listarFluxoMensal } from "@/lib/consultas/fluxo";
import { buscarPosicaoObra } from "@/lib/consultas/posicao";
import { idObraValido } from "@/lib/consultas/unidades";
import { formatarData } from "@/lib/formatar";
import { mensagens } from "@/lib/mensagens";
import { mesCorrente, montarSerieFluxo } from "@/lib/serie-fluxo";

export const metadata: Metadata = { title: "Relatório da obra" };

const tela = "Relatório da obra";
const classeSecao = "flex flex-col gap-4 rounded-xl border border-borda bg-superficie p-5 break-inside-avoid";

// Sete consultas em paralelo, as mesmas das telas da obra e do estoque; nada é calculado aqui.
async function carregar(id: string) {
  try {
    const [posicao, fluxo, alertas, estoque, tipologias, vso, cobertura] = await Promise.all([
      buscarPosicaoObra(id),
      listarFluxoMensal(id),
      listarAlertas(id).catch(() => null),
      buscarEstoqueObra(id),
      listarEstoqueTipologia(id),
      listarVsoObra(id),
      buscarCobertura(id),
    ]);
    return { posicao, fluxo, alertas, estoque, tipologias, vso, cobertura };
  } catch {
    return null;
  }
}

export default async function PaginaRelatorioObra({ params }: PageProps<"/obras/[id]/relatorio">) {
  const { id } = await params;
  if (!idObraValido(id)) return <AvisoTelaObra tela={tela} mensagem={mensagens.obra.naoEncontrada} />;

  const dados = await carregar(id);
  if (dados === null) return <AvisoTelaObra tela={tela} mensagem={mensagens.obra.indisponivel} erro />;
  if (!dados.posicao) return <AvisoTelaObra tela={tela} mensagem={mensagens.obra.naoEncontrada} />;

  const { posicao } = dados;
  const mesAtual = mesCorrente();
  const serie = montarSerieFluxo(dados.fluxo, null, mesAtual);
  const hoje = new Date().toISOString();

  // Largura de folha A4 também na tela: o gráfico mede a largura quando desenha e não redesenha na impressão.
  return (
    <div className="mx-auto flex w-full max-w-[700px] flex-col gap-7">
      <header className="flex flex-col gap-3">
        <Link
          href={`/obras/${id}`}
          className="w-fit text-sm text-suave underline underline-offset-4 hover:text-texto print:hidden"
        >
          Voltar para a obra
        </Link>
        <div className="flex flex-wrap items-end justify-between gap-4">
          <div className="flex flex-col gap-1">
            <p className="text-sm text-suave">{tela}</p>
            <h1 className="font-serif text-[34px] leading-tight font-semibold">{posicao.obra}</h1>
            <p className="text-sm text-suave">Emitido em {formatarData(hoje)}. A data dos dados está no rodapé.</p>
          </div>
          <BotaoImprimir />
        </div>
      </header>

      <section aria-label="Resumo da obra" className={classeSecao}>
        <IndicadorVgv valores={posicao} />
        <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
          <IndicadoresObra posicao={posicao} />
        </div>
      </section>

      <SecaoAlertas alertas={dados.alertas} mostrarObra={false} comLinks={false} />

      <section aria-labelledby="titulo-fluxo" className={classeSecao}>
        <div className="flex flex-col gap-1">
          <h2 id="titulo-fluxo" className="font-serif text-2xl font-semibold">
            Fluxo de caixa por mês
          </h2>
          <p className="text-sm text-suave">12 meses para trás e 24 para frente, a partir do mês atual, sem atraso de repasse.</p>
        </div>
        {serie.length === 0 ? (
          <p>{mensagens.obra.semMovimento}</p>
        ) : (
          <GraficoFluxo serie={serie} comAtraso={false} mesAtual={mesAtual} />
        )}
      </section>

      {dados.estoque && dados.tipologias.length > 0 && (
        <>
          <ResumoEstoque estoque={dados.estoque} cobertura={dados.cobertura} estreito />
          <section aria-labelledby="titulo-tipologia" className={classeSecao}>
            <h2 id="titulo-tipologia" className="font-serif text-2xl font-semibold">
              Estoque por tipologia
            </h2>
            <TabelaEstoqueTipologia linhas={dados.tipologias} />
          </section>
        </>
      )}

      {dados.vso.length > 0 && (
        <section aria-labelledby="titulo-vso" className={classeSecao}>
          <h2 id="titulo-vso" className="font-serif text-2xl font-semibold">
            Vendas e VSO dos últimos 12 meses
          </h2>
          <GraficoVso linhas={dados.vso} />
        </section>
      )}
    </div>
  );
}
