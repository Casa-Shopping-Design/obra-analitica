import type { Metadata } from "next";
import { AvisoTelaObra, CabecalhoTelaObra } from "@/componentes/CabecalhoTelaObra";
import { GraficoLeadsOrigem } from "@/componentes/GraficoLeadsOrigem";
import { QuadroRepasse } from "@/componentes/QuadroRepasse";
import { TabelaFunil } from "@/componentes/TabelaFunil";
import { TabelaLeadsOrigem } from "@/componentes/TabelaLeadsOrigem";
import { TabelaRepasseBanco } from "@/componentes/TabelaRepasseBanco";
import { listarFunilObra, mesesFunil } from "@/lib/consultas/funil";
import { listarLeadsOrigem } from "@/lib/consultas/leads-origem";
import { buscarRepasseObra } from "@/lib/consultas/repasse";
import { listarRepasseBanco } from "@/lib/consultas/repasse-banco";
import { mensagensOrigem, somarLeadsPorOrigem } from "@/lib/consultas/resumo-origem";
import { buscarObra, idObraValido } from "@/lib/consultas/unidades";

export const metadata: Metadata = { title: "Vendas e repasse" };

const tela = "Vendas e repasse";

// Cinco leituras em paralelo, todas filtradas pela obra; o RLS devolve vazio se ela não é do usuário.
async function carregar(id: string) {
  try {
    const [obra, repasse, bancos, funil, leads] = await Promise.all([
      buscarObra(id),
      buscarRepasseObra(id),
      listarRepasseBanco(id),
      listarFunilObra(id),
      listarLeadsOrigem(id),
    ]);
    return { obra, repasse, bancos, funil, leads };
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

  const semCrm = !dados.repasse && dados.funil.length === 0 && dados.leads.length === 0;
  const origens = somarLeadsPorOrigem(dados.leads);
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
            {dados.repasse && dados.bancos.length > 0 && (
              <div className="flex flex-col gap-2">
                <h3 className="text-lg font-semibold">Por banco</h3>
                <p className="text-sm text-suave">
                  Mesmas etapas do quadro acima, separadas pelo banco do financiamento no CRM. Parado em análise é o
                  repasse ainda sem assinatura cuja situação no CRM não muda há mais de 60 dias.
                </p>
                <TabelaRepasseBanco linhas={dados.bancos} diasMediosObra={dados.repasse.dias_medios_assinatura_liberacao} />
              </div>
            )}
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
          <section aria-labelledby="titulo-leads" className="flex flex-col gap-4 rounded-xl border border-borda bg-superficie p-5">
            <div className="flex flex-col gap-1">
              <h2 id="titulo-leads" className="font-serif text-2xl font-semibold">
                De onde vêm os leads
              </h2>
              <p className="text-sm text-suave">
                Últimos {mesesFunil} meses, por origem e mídia do CRM. Descartado é o lead cancelado, descartado ou perdido.
                O CRM não liga o lead à reserva, então esta seção mostra volume e descarte, não conversão em venda.
              </p>
            </div>
            {dados.leads.length === 0 ? (
              <p>{mensagensOrigem.semLeads}</p>
            ) : (
              <>
                <GraficoLeadsOrigem origens={origens} />
                <TabelaLeadsOrigem linhas={dados.leads} />
              </>
            )}
          </section>
        </>
      )}
    </>
  );
}
