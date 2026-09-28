import type { Metadata } from "next";
import { AvisoTelaObra, CabecalhoTelaObra } from "@/componentes/CabecalhoTelaObra";
import { TabelaConferencia } from "@/componentes/TabelaConferencia";
import { buscarConferenciaObra, podeVerConferencia } from "@/lib/consultas/conferencia";
import { mensagensOrigem } from "@/lib/consultas/resumo-origem";
import { buscarObra, idObraValido } from "@/lib/consultas/unidades";
import { formatarMes } from "@/lib/formatar";

export const metadata: Metadata = { title: "Conferência com o ERP" };

const tela = "Conferência com o ERP";

async function carregar(id: string) {
  try {
    const [obra, conferencia] = await Promise.all([buscarObra(id), buscarConferenciaObra(id)]);
    return { obra, conferencia };
  } catch {
    return null;
  }
}

// O perfil é conferido antes de qualquer leitura; esconder o link na obra não basta.
export default async function PaginaConferenciaObra({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const permitido = await podeVerConferencia().catch(() => false);
  if (!permitido) return <AvisoTelaObra tela={tela} mensagem={mensagensOrigem.conferenciaRestrita} />;
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
        nota={
          dados.conferencia
            ? `Painel contra o mapa imobiliário do ERP no último mês fechado: ${formatarMes(dados.conferencia.competenciaOrigem)}.`
            : undefined
        }
      />
      {dados.conferencia ? <TabelaConferencia conferencia={dados.conferencia} /> : <p>{mensagensOrigem.semConferencia}</p>}
    </>
  );
}
