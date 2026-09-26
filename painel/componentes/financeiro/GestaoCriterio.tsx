import { registrarCriterio } from "@/app/(painel)/dre/acoes";
import { FormularioCriterio } from "@/componentes/financeiro/FormulariosDre";
import { rotulosMetodo } from "@/componentes/financeiro/regras-classificacao";
import type { CriterioReconhecimento } from "@/lib/consultas/dre";
import type { CentroCusto } from "@/lib/consultas/referencia";
import { formatarData } from "@/lib/formatar";

// Situação atual do critério (padrão da construtora e exceções por obra) e, para diretor e financeiro,
// o formulário. Quem valida fica gravado pelo banco com o usuário da sessão.
export function GestaoCriterio({
  criterios,
  obras,
  podeGravar,
}: {
  criterios: CriterioReconhecimento[] | null;
  obras: CentroCusto[];
  podeGravar: boolean;
}) {
  const nomes = new Map(obras.map((obra) => [obra.id, obra.nome]));
  const padrao = criterios?.find((criterio) => criterio.centro_custo_id === null);
  const porObra = criterios?.filter((criterio) => criterio.centro_custo_id !== null) ?? [];
  const descrever = (criterio: CriterioReconhecimento | undefined) => {
    if (!criterio || criterio.metodo === "nao_definido") return rotulosMetodo.nao_definido;
    const quando = criterio.validado_em ? `, validado em ${formatarData(criterio.validado_em)}` : "";
    return `${rotulosMetodo[criterio.metodo]}${quando}`;
  };
  return (
    <div className="flex flex-col gap-4">
      {criterios && (
        <dl className="flex flex-col gap-1.5 text-sm">
          <div className="flex flex-wrap justify-between gap-x-3">
            <dt className="text-suave">Padrão da construtora</dt>
            <dd className="font-medium">{descrever(padrao)}</dd>
          </div>
          {porObra.map((criterio) => (
            <div key={criterio.id} className="flex flex-wrap justify-between gap-x-3">
              <dt className="text-suave">{nomes.get(criterio.centro_custo_id as string) ?? "Obra"}</dt>
              <dd className="font-medium">{descrever(criterio)}</dd>
            </div>
          ))}
        </dl>
      )}
      <p className="rounded-lg border-2 border-atencao p-3 text-sm">
        <span aria-hidden="true" className="font-semibold text-atencao">
          !{" "}
        </span>
        Só o financeiro responsável pela contabilidade deve validar o critério, depois de conferir com o contador. Ligar
        o percentual de conclusão faz aparecer receita reconhecida e resultado no DRE de todas as telas e no assistente.
      </p>
      {podeGravar ? (
        <FormularioCriterio
          acao={registrarCriterio}
          obras={obras.filter((obra) => obra.tipo === "obra").map((obra) => ({ valor: obra.id, rotulo: obra.nome }))}
        />
      ) : (
        <p className="text-sm text-suave">Só diretor ou financeiro da construtora pode registrar o critério.</p>
      )}
    </div>
  );
}
