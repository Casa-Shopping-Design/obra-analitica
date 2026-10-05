import type { Metadata } from "next";
import Link from "next/link";
import { AvisoTelaObra, CabecalhoTelaObra } from "@/componentes/CabecalhoTelaObra";
import { ExplicacaoIndicador } from "@/componentes/ExplicacaoIndicador";
import { GraficoTendencia } from "@/componentes/GraficoTendencia";
import { TabelaDre } from "@/componentes/TabelaDre";
import { podeVerConferencia } from "@/lib/consultas/conferencia";
import { listarDreObra, listarTendenciaMensal, podeVerDre } from "@/lib/consultas/dre";
import { mensagensOrigem } from "@/lib/consultas/resumo-origem";
import { buscarObra, idObraValido } from "@/lib/consultas/unidades";
import { notaDre, prepararLinhasDre } from "@/lib/dre";
import { mensagens } from "@/lib/mensagens";

export const metadata: Metadata = { title: "DRE de viabilidade" };

const tela = "DRE de viabilidade";

async function carregar(id: string) {
  try {
    // A série falha sozinha: sem ela a DRE do mês continua de pé.
    const [obra, dre, serie] = await Promise.all([
      buscarObra(id),
      listarDreObra(id),
      listarTendenciaMensal(id).catch(() => null),
    ]);
    return { obra, dre, serie };
  } catch {
    return null;
  }
}

// O perfil é conferido antes de qualquer leitura; esconder o link na obra não basta. O link de edição só
// aparece para diretor e financeiro, e a tela de edição confere de novo.
export default async function PaginaDreObra({ params }: PageProps<"/obras/[id]/dre">) {
  const { id } = await params;
  const [permitido, podeEditar] = await Promise.all([
    podeVerDre().catch(() => false),
    podeVerConferencia().catch(() => false),
  ]);
  if (!permitido) return <AvisoTelaObra tela={tela} mensagem={mensagens.dre.restrita} />;
  if (!idObraValido(id)) return <AvisoTelaObra tela={tela} mensagem={mensagensOrigem.obraNaoEncontrada} />;

  const dados = await carregar(id);
  if (dados === null) return <AvisoTelaObra tela={tela} mensagem={mensagens.dre.indisponivel} erro />;
  if (!dados.obra) return <AvisoTelaObra tela={tela} mensagem={mensagensOrigem.obraNaoEncontrada} />;

  return (
    <>
      <CabecalhoTelaObra
        id={id}
        tela={tela}
        obra={dados.obra.nome}
        nota={dados.dre ? notaDre(dados.dre.cabecalho) : undefined}
      />
      {podeEditar && (
        <p className="print:hidden">
          <Link href={`/obras/${id}/dre/estudo`} className="text-sm font-semibold underline underline-offset-4 hover:text-menu">
            {dados.dre ? "Editar estudo" : "Cadastrar estudo"}
          </Link>
        </p>
      )}
      {dados.dre ? (
        <>
          <section
            aria-labelledby="titulo-tendencia-mensal"
            className="flex flex-col gap-4 rounded-xl border border-borda bg-superficie p-5"
          >
            <div className="flex flex-col gap-1">
              <h2 id="titulo-tendencia-mensal" className="flex items-center gap-1.5 font-serif text-2xl font-semibold">
                Margem operacional mês a mês
                <ExplicacaoIndicador chave="tendencia_margem_mensal" rotulo="Margem operacional mês a mês" />
              </h2>
              <p className="text-sm text-suave">Até 24 meses. O mês corrente muda a cada carga; os anteriores ficam como foram gravados.</p>
            </div>
            {dados.serie === null ? (
              <p role="alert" className="text-alerta">
                {mensagens.dre.serieIndisponivel}
              </p>
            ) : (
              <GraficoTendencia pontos={dados.serie} />
            )}
          </section>
          <TabelaDre linhas={prepararLinhasDre(dados.dre.linhas)} />
        </>
      ) : (
        <p>{mensagens.dre.semEstudo}</p>
      )}
    </>
  );
}
