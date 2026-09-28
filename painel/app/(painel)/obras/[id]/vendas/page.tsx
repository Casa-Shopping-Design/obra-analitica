import type { Metadata } from "next";
import { AvisoTelaObra, CabecalhoTelaObra } from "@/componentes/CabecalhoTelaObra";
import { QuadroRepasse } from "@/componentes/QuadroRepasse";
import { TabelaFunil } from "@/componentes/TabelaFunil";
import { listarFunilObra, mesesFunil } from "@/lib/consultas/funil";
import { buscarRepasseObra } from "@/lib/consultas/repasse";
import { mensagensOrigem } from "@/lib/consultas/resumo-origem";
import { buscarObra, idObraValido } from "@/lib/consultas/unidades";

export const metadata: Metadata = { title: "Vendas e repasse" };

const tela = "Vendas e repasse";

// Três leituras em paralelo, todas filtradas pela obra; o RLS devolve vazio se ela não é do usuário.
async function carregar(id: string) {
  try {
    const [obra, repasse, funil] = await Promise.all([buscarObra(id), buscarRepasseObra(id), listarFunilObra(id)]);
    return { obra, repasse, funil };
  } catch {
    return null;
  }
}

export default async function PaginaVendasObra({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!idObraValido(id)) return <AvisoTelaObra tela={tela} mensagem={mensagensOrigem.obraNaoEncontrada} />;

  const dados = await carregar(id);
  if (dados === null) return <AvisoTelaObra tela={tela} mensagem={mensagensOrigem.indisponivel} erro />;
  if (!dados.obra) return <AvisoTelaObra tela={tela} mensagem={mensagensOrigem.obraNaoEncontrada} />;

  const semCrm = !dados.repasse && dados.funil.length === 0;
  return (
    <>
      <CabecalhoTelaObra id={id} tela={tela} obra={dados.obra.nome} nota="Lead, reserva e repasse vêm do CRM; venda, distrato e parcela do banco vêm do ERP." />
      {semCrm ? (
        <p>{mensagensOrigem.semCrm}</p>
      ) : (
        <>
          <section aria-labelledby="titulo-repasse" className="flex flex-col gap-4">
            <h2 id="titulo-repasse" className="font-serif text-2xl font-semibold">
              Repasse do financiamento
            </h2>
            {dados.repasse ? <QuadroRepasse repasse={dados.repasse} /> : <p>{mensagensOrigem.semRepasse}</p>}
          </section>
          <section aria-labelledby="titulo-funil" className="flex flex-col gap-4 rounded-xl border border-borda bg-superficie p-5">
            <div className="flex flex-col gap-1">
              <h2 id="titulo-funil" className="font-serif text-2xl font-semibold">
                Funil de vendas
              </h2>
              <p className="text-sm text-suave">
                Últimos {mesesFunil} meses. Venda e distrato seguem a mesma regra do VSO. A conversão compara contagens do
                mesmo mês: a reserva de março pode ter vindo de um lead de janeiro.
              </p>
            </div>
            <TabelaFunil linhas={dados.funil} />
          </section>
        </>
      )}
    </>
  );
}
