import type { Metadata } from "next";
import { AvisoTelaObra, CabecalhoTelaObra } from "@/componentes/CabecalhoTelaObra";
import { CartoesImposto } from "@/componentes/CartoesImposto";
import { podeVerDre } from "@/lib/consultas/dre";
import { buscarImpostoObra } from "@/lib/consultas/imposto";
import { mensagensOrigem } from "@/lib/consultas/resumo-origem";
import { buscarObra, idObraValido } from "@/lib/consultas/unidades";
import { notaImposto } from "@/lib/imposto";
import { mensagens } from "@/lib/mensagens";

export const metadata: Metadata = { title: "Gestão de imposto" };

const tela = "Gestão de imposto";

async function carregar(id: string) {
  try {
    const [obra, imposto] = await Promise.all([buscarObra(id), buscarImpostoObra(id)]);
    return { obra, imposto };
  } catch {
    return null;
  }
}

// O perfil é conferido antes de qualquer leitura; esconder o link na obra não basta.
export default async function PaginaImpostoObra({ params }: PageProps<"/obras/[id]/imposto">) {
  const { id } = await params;
  const permitido = await podeVerDre().catch(() => false);
  if (!permitido) return <AvisoTelaObra tela={tela} mensagem={mensagens.imposto.restrita} />;
  if (!idObraValido(id)) return <AvisoTelaObra tela={tela} mensagem={mensagensOrigem.obraNaoEncontrada} />;

  const dados = await carregar(id);
  if (dados === null) return <AvisoTelaObra tela={tela} mensagem={mensagens.imposto.indisponivel} erro />;
  if (!dados.obra) return <AvisoTelaObra tela={tela} mensagem={mensagensOrigem.obraNaoEncontrada} />;

  return (
    <>
      <CabecalhoTelaObra
        id={id}
        tela={tela}
        obra={dados.obra.nome}
        nota={dados.imposto ? notaImposto(dados.imposto) : undefined}
      />
      {dados.imposto ? <CartoesImposto imposto={dados.imposto} /> : <p>{mensagens.imposto.semAliquota}</p>}
    </>
  );
}
