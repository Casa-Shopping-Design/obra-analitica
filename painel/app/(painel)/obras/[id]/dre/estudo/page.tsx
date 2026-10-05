import type { Metadata } from "next";
import Link from "next/link";
import { AvisoTelaObra, CabecalhoTelaObra } from "@/componentes/CabecalhoTelaObra";
import { FormularioAliquota } from "@/componentes/FormularioAliquota";
import { FormularioEstudo, type CampoEstudo } from "@/componentes/FormularioEstudo";
import { ListaVersoesEstudo } from "@/componentes/ListaVersoesEstudo";
import { podeVerConferencia } from "@/lib/consultas/conferencia";
import { buscarAliquotaVigente, buscarEstudoVigente, listarVersoesEstudo } from "@/lib/consultas/dre";
import { exigirIdentidade } from "@/lib/consultas/identidade";
import { mensagensOrigem } from "@/lib/consultas/resumo-origem";
import { buscarObra, idObraValido } from "@/lib/consultas/unidades";
import { linhasDigitaveis, rotuloLinha, type EstudoVigente } from "@/lib/dre";
import { hojeEmBrasilia } from "@/lib/estudo-digitado";
import { formatarData } from "@/lib/formatar";
import { mensagens } from "@/lib/mensagens";
import { formatarAliquotaDigitada, formatarNumeroDigitado } from "@/lib/numero-digitado";

export const metadata: Metadata = { title: "Editar estudo de viabilidade" };

const tela = "Estudo de viabilidade";

function lerPagina(valor: string | string[] | undefined): number {
  const numero = Number(Array.isArray(valor) ? valor[0] : valor);
  return Number.isInteger(numero) && numero > 0 ? numero : 1;
}

// Quatro leituras em paralelo: obra, estudo vigente, página de versões e alíquota em vigor.
async function carregar(id: string, pagina: number) {
  try {
    const [obra, estudo, versoes, aliquota] = await Promise.all([
      buscarObra(id),
      buscarEstudoVigente(id),
      listarVersoesEstudo(id, pagina),
      buscarAliquotaVigente(id),
    ]);
    return { obra, estudo, versoes, aliquota };
  } catch {
    return null;
  }
}

// Sem estudo o formulário abre zerado, com a data-base de hoje, e a primeira gravação cria a versão 1.
function montarCampos(estudo: EstudoVigente | null): CampoEstudo[] {
  return linhasDigitaveis.map((linha) => ({
    linha,
    rotulo: rotuloLinha(linha),
    valor: formatarNumeroDigitado(estudo?.linhas[linha] ?? 0),
  }));
}

// Diretor e financeiro editam; leitura e gerente recebem a recusa antes de qualquer leitura. A Server Action
// e a função do banco repetem a conferência, com o segundo fator.
export default async function PaginaEstudoObra({ params, searchParams }: PageProps<"/obras/[id]/dre/estudo">) {
  const { id } = await params;
  const permitido = await podeVerConferencia().catch(() => false);
  if (!permitido) return <AvisoTelaObra tela={tela} mensagem={mensagens.estudo.semPermissao} />;
  if (!idObraValido(id)) return <AvisoTelaObra tela={tela} mensagem={mensagensOrigem.obraNaoEncontrada} />;

  const pagina = lerPagina((await searchParams).pagina);
  const [identidade, dados] = await Promise.all([exigirIdentidade(), carregar(id, pagina)]);
  if (dados === null) return <AvisoTelaObra tela={tela} mensagem={mensagens.dre.indisponivel} erro />;
  if (!dados.obra) return <AvisoTelaObra tela={tela} mensagem={mensagensOrigem.obraNaoEncontrada} />;

  const hoje = hojeEmBrasilia();
  const { estudo, aliquota } = dados;

  return (
    <>
      <CabecalhoTelaObra
        id={id}
        tela={tela}
        obra={dados.obra.nome}
        nota={
          estudo
            ? `Versão vigente: ${estudo.versao}, de ${formatarData(estudo.dataBase)}. Gravar cria uma versão nova; a anterior fica guardada.`
            : mensagens.estudo.semVersoes
        }
      />
      <p>
        <Link href={`/obras/${id}/dre`} className="text-sm underline underline-offset-4 hover:text-menu">
          Ver a DRE de viabilidade
        </Link>
      </p>

      <section aria-labelledby="titulo-estudo" className="flex flex-col gap-5 rounded-xl border border-borda bg-superficie p-5">
        <h2 id="titulo-estudo" className="font-serif text-2xl font-semibold">
          Estudo de viabilidade
        </h2>
        <FormularioEstudo
          centroCustoId={id}
          descricao={estudo?.descricao ?? ""}
          dataBase={estudo?.dataBase ?? hoje}
          hoje={hoje}
          campos={montarCampos(estudo)}
        />
      </section>

      <section aria-labelledby="titulo-versoes" className="flex flex-col gap-4">
        <h2 id="titulo-versoes" className="font-serif text-2xl font-semibold">
          Versões gravadas
        </h2>
        <ListaVersoesEstudo centroCustoId={id} usuarioId={identidade.usuarioId} pagina={dados.versoes} />
      </section>

      <section aria-labelledby="titulo-aliquota" className="flex flex-col gap-4 rounded-xl border border-borda bg-superficie p-5">
        <div className="flex flex-col gap-1">
          <h2 id="titulo-aliquota" className="font-serif text-2xl font-semibold">
            Alíquota de imposto
          </h2>
          <p className="text-sm text-suave">
            {aliquota
              ? `Em vigor: ${formatarAliquotaDigitada(aliquota.aliquota)}% desde ${formatarData(aliquota.vigenciaInicio)}.`
              : mensagens.estudo.semAliquota}
          </p>
        </div>
        <FormularioAliquota
          centroCustoId={id}
          aliquota={aliquota ? formatarAliquotaDigitada(aliquota.aliquota) : ""}
          hoje={hoje}
          aviso={mensagens.estudo.avisoAliquota}
        />
      </section>
    </>
  );
}
