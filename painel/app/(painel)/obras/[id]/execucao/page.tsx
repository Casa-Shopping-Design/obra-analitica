import type { Metadata } from "next";
import { AvisoTelaObra, CabecalhoTelaObra } from "@/componentes/CabecalhoTelaObra";
import { TabelaExecucao } from "@/componentes/TabelaExecucao";
import { listarExecucaoObra, mesesExecucao } from "@/lib/consultas/execucao";
import { mensagensOrigem } from "@/lib/consultas/resumo-origem";
import { buscarObra, idObraValido } from "@/lib/consultas/unidades";

export const metadata: Metadata = { title: "Execução física" };

const tela = "Execução física";

async function carregar(id: string) {
  try {
    const [obra, execucao] = await Promise.all([buscarObra(id), listarExecucaoObra(id)]);
    return { obra, execucao };
  } catch {
    return null;
  }
}

export default async function PaginaExecucaoObra({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!idObraValido(id)) return <AvisoTelaObra tela={tela} mensagem={mensagensOrigem.obraNaoEncontrada} />;

  const dados = await carregar(id);
  if (dados === null) return <AvisoTelaObra tela={tela} mensagem={mensagensOrigem.indisponivel} erro />;
  if (!dados.obra) return <AvisoTelaObra tela={tela} mensagem={mensagensOrigem.obraNaoEncontrada} />;

  return (
    <>
      <CabecalhoTelaObra
        id={id}
        tela={tela}
        obra={dados.obra.nome}
        nota={`Últimos ${mesesExecucao} meses. Físico é o valor medido sobre o planejado, só com medição aprovada no ERP.`}
      />
      {dados.execucao.length === 0 ? <p>{mensagensOrigem.semExecucao}</p> : <TabelaExecucao linhas={dados.execucao} />}
    </>
  );
}
