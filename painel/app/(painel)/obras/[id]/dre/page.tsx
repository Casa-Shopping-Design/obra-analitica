import type { Metadata } from "next";
import { AvisoTelaObra, CabecalhoTelaObra } from "@/componentes/CabecalhoTelaObra";
import { TabelaDre } from "@/componentes/TabelaDre";
import { podeVerConferencia } from "@/lib/consultas/conferencia";
import { listarDreObra } from "@/lib/consultas/dre";
import { mensagensOrigem } from "@/lib/consultas/resumo-origem";
import { buscarObra, idObraValido } from "@/lib/consultas/unidades";
import { notaDre, prepararLinhasDre } from "@/lib/dre";
import { mensagens } from "@/lib/mensagens";

export const metadata: Metadata = { title: "DRE de viabilidade" };

const tela = "DRE de viabilidade";

async function carregar(id: string) {
  try {
    const [obra, dre] = await Promise.all([buscarObra(id), listarDreObra(id)]);
    return { obra, dre };
  } catch {
    return null;
  }
}

// O perfil é conferido antes de qualquer leitura; esconder o link na obra não basta.
export default async function PaginaDreObra({ params }: PageProps<"/obras/[id]/dre">) {
  const { id } = await params;
  const permitido = await podeVerConferencia().catch(() => false);
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
      {dados.dre ? <TabelaDre linhas={prepararLinhasDre(dados.dre.linhas)} /> : <p>{mensagens.dre.semEstudo}</p>}
    </>
  );
}
