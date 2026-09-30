import type { Metadata } from "next";
import { AvisoTelaObra, CabecalhoTelaObra } from "@/componentes/CabecalhoTelaObra";
import { CartaoValor } from "@/componentes/CartaoValor";
import { GraficoSimulacao } from "@/componentes/GraficoSimulacao";
import { SeletorSimulacao } from "@/componentes/SeletorSimulacao";
import { buscarEstoqueObra } from "@/lib/consultas/estoque";
import { buscarResumoSimulacao, listarSimulacao, type ResumoSimulacao } from "@/lib/consultas/simulacao";
import { buscarObra, idObraValido } from "@/lib/consultas/unidades";
import { formatarDecimal, formatarMes, formatarReal } from "@/lib/formatar";
import { mensagens } from "@/lib/mensagens";
import { mesCorrente } from "@/lib/serie-fluxo";
import { lerDesconto, lerRitmo, recortarSerie, ritmoMaisProximo, type DescontoPercentual, type Ritmo } from "@/lib/simulacao";

export const metadata: Metadata = { title: "Simulação de vendas" };

const tela = "Simulação de vendas";

// Duas idas ao banco: a obra e o estoque primeiro, porque o ritmo padrão sai do ritmo real da obra;
// depois a série e o resumo da simulação em paralelo.
async function carregar(id: string, ritmoUrl: string | string[] | undefined, descontoUrl: string | string[] | undefined) {
  try {
    const [obra, estoque] = await Promise.all([buscarObra(id), buscarEstoqueObra(id)]);
    if (!obra || !estoque) return "sem_obra" as const;
    const ritmo = lerRitmo(ritmoUrl, ritmoMaisProximo(estoque.vendas_media_6m));
    const desconto = lerDesconto(descontoUrl);
    const [serie, resumo] = await Promise.all([
      listarSimulacao(id, ritmo, desconto),
      buscarResumoSimulacao(id, ritmo, desconto),
    ]);
    return { obra, estoque, ritmo, desconto, serie, resumo };
  } catch {
    return null;
  }
}

function mesOuNada(mes: string | null, texto: string): string {
  return mes ? `${texto} ${formatarMes(mes)}.` : "";
}

function Resumo({ resumo }: { resumo: ResumoSimulacao }) {
  const reducao = resumo.exposicao_atual - resumo.exposicao_simulada;
  return (
    <section aria-label="Resultado da simulação" className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
      <CartaoValor
        rotulo="Exposição máxima hoje"
        chave="exposicao_maxima"
        valor={formatarReal(resumo.exposicao_atual)}
        nota={mesOuNada(resumo.mes_exposicao_atual, "Pior mês:")}
      />
      <CartaoValor
        rotulo="Exposição com as vendas"
        chave="exposicao_simulada"
        valor={formatarReal(resumo.exposicao_simulada)}
        nota={`${reducao > 0 ? `${formatarReal(reducao)} a menos de dinheiro próprio. ` : "Não muda o pior mês. "}${mesOuNada(resumo.mes_exposicao_simulada, "Pior mês:")}`}
      />
      <CartaoValor
        rotulo="Receita do estoque"
        chave="receita_simulada"
        valor={formatarReal(resumo.receita_simulada)}
        nota={`${resumo.unidades_estoque} unidades. ${mesOuNada(resumo.mes_ultima_venda, "Última venda em")}`}
      />
      <CartaoValor
        rotulo="Saldo volta a ficar positivo"
        valor={resumo.mes_saldo_positivo ? formatarMes(resumo.mes_saldo_positivo) : "Não volta"}
        nota={
          resumo.mes_saldo_positivo
            ? "Primeiro mês depois do pior em que o saldo acumulado com as vendas fica positivo."
            : "Mesmo vendendo todo o estoque, o saldo acumulado fica negativo até o fim do fluxo."
        }
      />
    </section>
  );
}

function Premissas({ ritmo, desconto, vendasMedia }: { ritmo: Ritmo; desconto: DescontoPercentual; vendasMedia: number | null }) {
  return (
    <section aria-labelledby="titulo-premissas" className="flex flex-col gap-3 rounded-xl border border-borda bg-superficie p-5">
      <h2 id="titulo-premissas" className="font-serif text-xl font-semibold">
        Como a simulação calcula
      </h2>
      <ul className="flex list-disc flex-col gap-1.5 pl-5 text-sm">
        <li>
          Vende {ritmo} {ritmo === 1 ? "unidade" : "unidades"} por mês a partir do mês que vem. Nos últimos seis meses a
          obra vendeu {vendasMedia === null ? "nenhuma unidade líquida" : `${formatarDecimal(vendasMedia)} por mês`}.
        </li>
        <li>
          Preço de tabela de hoje{desconto > 0 ? `, com ${desconto}% de desconto` : ", sem desconto"}. Proposta e reserva
          vendem primeiro; depois, a unidade mais barata.
        </li>
        <li>
          Cada venda recebe do banco a mesma fração que o repasse tem nos contratos ativos da obra. A parte do comprador
          entra em parcelas iguais até o mês anterior à entrega; o repasse, nas chaves.
        </li>
        <li>Depois da entrega, a parte do comprador entra no mês da venda e o repasse dois meses depois.</li>
        <li>
          O ponto de partida é o fluxo de hoje: o que já entrou, o que falta receber dos contratos e os títulos a pagar.
          Custo do orçamento que ainda não virou título não entra, como no fluxo de caixa da obra.
        </li>
      </ul>
    </section>
  );
}

export default async function PaginaSimulacaoObra({ params, searchParams }: PageProps<"/obras/[id]/simulacao">) {
  const { id } = await params;
  if (!idObraValido(id)) return <AvisoTelaObra tela={tela} mensagem={mensagens.unidades.obraNaoEncontrada} />;
  const busca = await searchParams;

  const dados = await carregar(id, busca.ritmo, busca.desconto);
  if (dados === null) return <AvisoTelaObra tela={tela} mensagem={mensagens.simulacao.indisponivel} erro />;
  if (dados === "sem_obra") return <AvisoTelaObra tela={tela} mensagem={mensagens.unidades.obraNaoEncontrada} />;

  const mesAtual = mesCorrente();
  const serie = recortarSerie(dados.serie, mesAtual);

  return (
    <>
      <CabecalhoTelaObra
        id={id}
        tela={tela}
        obra={dados.obra.nome}
        nota="E se o estoque vendesse neste ritmo? A simulação soma as vendas ao fluxo de caixa de hoje e mostra quanto dinheiro próprio a obra ainda exige."
      />

      {dados.estoque.unidades_estoque === 0 || !dados.resumo ? (
        <p>{mensagens.simulacao.semEstoque}</p>
      ) : (
        <>
          <section aria-labelledby="titulo-simulacao" className="flex flex-col gap-5 rounded-xl border border-borda bg-superficie p-5">
            <h2 id="titulo-simulacao" className="font-serif text-2xl font-semibold">
              Saldo acumulado da obra
            </h2>
            <SeletorSimulacao ritmo={dados.ritmo} desconto={dados.desconto} />
            <GraficoSimulacao serie={serie} mesAtual={mesAtual} />
          </section>
          <Resumo resumo={dados.resumo} />
          <Premissas ritmo={dados.ritmo} desconto={dados.desconto} vendasMedia={dados.estoque.vendas_media_6m} />
        </>
      )}
    </>
  );
}
