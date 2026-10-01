import type { Metadata } from "next";
import Link from "next/link";
import { IndicadoresObra } from "@/componentes/CartaoIndicador";
import { FaixaCarteira } from "@/componentes/FaixaCarteira";
import { IndicadorVgv } from "@/componentes/IndicadorVgv";
import { SecaoAlertas } from "@/componentes/ListaAlertas";
import { TabelaObras } from "@/componentes/TabelaObras";
import type { AlertaObra } from "@/lib/alertas";
import { buscarCarteira, listarAlertas, type PosicaoCarteira } from "@/lib/consultas/carteira";
import { listarPosicaoObras, type PosicaoObra } from "@/lib/consultas/posicao";
import { mensagens } from "@/lib/mensagens";

export const metadata: Metadata = { title: "Visão geral" };

// Cada bloco falha sozinho: sem alertas ou sem carteira, as obras continuam na tela.
async function carregarVisaoGeral(): Promise<{
  obras: PosicaoObra[] | null;
  carteira: PosicaoCarteira | null;
  alertas: AlertaObra[] | null;
}> {
  const [obras, carteira, alertas] = await Promise.all([
    listarPosicaoObras().catch(() => null),
    buscarCarteira().catch(() => null),
    listarAlertas().catch(() => null),
  ]);
  return { obras, carteira, alertas };
}

// Três consultas em paralelo, todas em views somadas no banco; o fluxo mensal fica para a tela de cada obra.
export default async function PaginaVisaoGeral() {
  const { obras, carteira, alertas } = await carregarVisaoGeral();

  return (
    <>
      <h1 className="font-serif text-[34px] font-semibold">Visão geral</h1>
      {obras === null && (
        <p role="alert" className="text-alerta">
          {mensagens.posicao.indisponivel}
        </p>
      )}
      {obras?.length === 0 && <p>{mensagens.posicao.semObras}</p>}
      {obras && obras.length > 0 && (
        <>
          {carteira && carteira.obras > 1 && <FaixaCarteira carteira={carteira} />}
          <SecaoAlertas alertas={alertas} mostrarObra={obras.length > 1} />
          <ul aria-label="Obras" className="grid grid-cols-1 gap-4 xl:grid-cols-2 2xl:grid-cols-3">
            {obras.map((obra) => (
              <li key={obra.centro_custo_id}>
                <article
                  aria-labelledby={`obra-${obra.centro_custo_id}`}
                  className="flex h-full flex-col gap-5 rounded-xl border border-borda bg-superficie p-5"
                >
                  <h2 id={`obra-${obra.centro_custo_id}`} className="font-serif text-xl font-semibold">
                    <Link href={`/obras/${obra.centro_custo_id}`} className="underline underline-offset-4 hover:text-menu">
                      {obra.obra}
                    </Link>
                  </h2>
                  <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
                    <div className="sm:col-span-2">
                      <IndicadorVgv valores={obra} />
                    </div>
                    <IndicadoresObra posicao={obra} />
                  </div>
                </article>
              </li>
            ))}
          </ul>
          <TabelaObras obras={obras} />
        </>
      )}
    </>
  );
}
