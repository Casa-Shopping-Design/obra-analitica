import type { Metadata } from "next";
import { AvisoTelaObra, CabecalhoTelaObra } from "@/componentes/CabecalhoTelaObra";
import { TabelaInadimplencia } from "@/componentes/TabelaInadimplencia";
import { listarInadimplenciaObra } from "@/lib/consultas/inadimplencia";
import { mensagensOrigem } from "@/lib/consultas/resumo-origem";
import { buscarObra, idObraValido } from "@/lib/consultas/unidades";
import { formatarData } from "@/lib/formatar";

export const metadata: Metadata = { title: "Inadimplência" };

const tela = "Inadimplência";

async function carregar(id: string) {
  try {
    const [obra, faixas] = await Promise.all([buscarObra(id), listarInadimplenciaObra(id)]);
    return { obra, faixas };
  } catch {
    return null;
  }
}

export default async function PaginaInadimplenciaObra({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!idObraValido(id)) return <AvisoTelaObra tela={tela} mensagem={mensagensOrigem.obraNaoEncontrada} />;

  const dados = await carregar(id);
  if (dados === null) return <AvisoTelaObra tela={tela} mensagem={mensagensOrigem.indisponivel} erro />;
  if (!dados.obra) return <AvisoTelaObra tela={tela} mensagem={mensagensOrigem.obraNaoEncontrada} />;

  const posicao = dados.faixas[0]?.data_posicao;
  return (
    <>
      <CabecalhoTelaObra
        id={id}
        tela={tela}
        obra={dados.obra.nome}
        nota={posicao ? `Posição do ERP em ${formatarData(posicao)}, por título, sem identificar o comprador.` : undefined}
      />
      {dados.faixas.length === 0 ? <p>{mensagensOrigem.semInadimplencia}</p> : <TabelaInadimplencia linhas={dados.faixas} />}
    </>
  );
}
