import type { Metadata } from "next";
import Link from "next/link";
import { AvisoTelaObra, CabecalhoTelaObra } from "@/componentes/CabecalhoTelaObra";
import { GraficoVso } from "@/componentes/GraficoVso";
import { ResumoEstoque } from "@/componentes/ResumoEstoque";
import { TabelaEstoqueTipologia } from "@/componentes/TabelaEstoqueTipologia";
import {
  buscarCobertura,
  buscarEstoqueObra,
  listarEstoqueTipologia,
  listarVsoObra,
  mesesVso,
} from "@/lib/consultas/estoque";
import { buscarObra, idObraValido } from "@/lib/consultas/unidades";
import { mensagens } from "@/lib/mensagens";

export const metadata: Metadata = { title: "Estoque e vendas" };

const tela = "Estoque e vendas";

// Cinco consultas em paralelo, todas filtradas pela obra e somadas no banco (migrations 0015 e 0024).
async function carregar(id: string) {
  try {
    const [obra, estoque, tipologias, vso, cobertura] = await Promise.all([
      buscarObra(id),
      buscarEstoqueObra(id),
      listarEstoqueTipologia(id),
      listarVsoObra(id),
      buscarCobertura(id),
    ]);
    return { obra, estoque, tipologias, vso, cobertura };
  } catch {
    return null;
  }
}

export default async function PaginaEstoqueObra({ params }: PageProps<"/obras/[id]/estoque">) {
  const { id } = await params;
  if (!idObraValido(id)) return <AvisoTelaObra tela={tela} mensagem={mensagens.unidades.obraNaoEncontrada} />;

  const dados = await carregar(id);
  if (dados === null) return <AvisoTelaObra tela={tela} mensagem={mensagens.estoque.indisponivel} erro />;
  if (!dados.obra || !dados.estoque) return <AvisoTelaObra tela={tela} mensagem={mensagens.unidades.obraNaoEncontrada} />;

  const { estoque } = dados;

  return (
    <>
      <CabecalhoTelaObra
        id={id}
        tela={tela}
        obra={dados.obra.nome}
        nota="Estoque é disponível, reservada e em proposta, pelo preço de tabela de hoje. O ritmo é a média de vendas menos distratos dos últimos seis meses."
      />

      {dados.tipologias.length === 0 ? (
        <p>{mensagens.estoque.semUnidades}</p>
      ) : (
        <>
          <ResumoEstoque estoque={estoque} cobertura={dados.cobertura} />

          <section aria-labelledby="titulo-tipologia" className="flex flex-col gap-4 rounded-xl border border-borda bg-superficie p-5">
            <h2 id="titulo-tipologia" className="font-serif text-2xl font-semibold">
              Estoque por tipologia
            </h2>
            <TabelaEstoqueTipologia linhas={dados.tipologias} />
          </section>
        </>
      )}

      <section aria-labelledby="titulo-vso" className="flex flex-col gap-4 rounded-xl border border-borda bg-superficie p-5">
        <div className="flex flex-col gap-1">
          <h2 id="titulo-vso" className="font-serif text-2xl font-semibold">
            Vendas e VSO por mês
          </h2>
          <p className="text-sm text-suave">
            Últimos {mesesVso} meses. VSO é a venda líquida do mês sobre o estoque do início do mês; distrato sem data
            de cancelamento cai no mês da venda.
          </p>
        </div>
        {dados.vso.length === 0 ? <p>{mensagens.estoque.semVendas}</p> : <GraficoVso linhas={dados.vso} />}
      </section>

      {estoque.unidades_estoque > 0 && (
        <p>
          <Link
            href={`/obras/${id}/simulacao`}
            className="inline-flex min-h-11 items-center rounded-lg bg-menu px-4 font-semibold text-menu-texto hover:bg-menu-ativo"
          >
            Simular a venda do estoque
          </Link>
        </p>
      )}
    </>
  );
}
