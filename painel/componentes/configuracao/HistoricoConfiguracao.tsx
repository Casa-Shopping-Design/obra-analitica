import {
  descreverAlteracao,
  mensagensConfiguracao,
  quemAlterou,
  type AlteracaoConfiguracao,
  type Parametro,
  type ValorCodigoOrigem,
} from "@/lib/configuracao";
import { formatarData } from "@/lib/formatar";
import { horaEmSaoPaulo } from "@/lib/periodo";

export function HistoricoConfiguracao({
  alteracoes,
  catalogo,
  nomesObra,
  valoresCodigo,
  usuarioId,
}: {
  alteracoes: AlteracaoConfiguracao[];
  catalogo: Parametro[];
  nomesObra: Map<string, string>;
  valoresCodigo: ValorCodigoOrigem[];
  usuarioId: string;
}) {
  if (alteracoes.length === 0) return <p className="text-sm">{mensagensConfiguracao.semHistorico}</p>;
  const porCodigo = new Map(catalogo.map((parametro) => [parametro.codigo, parametro]));
  return (
    <ol className="flex flex-col gap-2 text-sm">
      {alteracoes.map((alteracao) => {
        const { titulo, detalhe } = descreverAlteracao(alteracao, porCodigo, nomesObra, valoresCodigo);
        return (
          <li key={alteracao.id} className="rounded-lg border border-borda p-3">
            <p className="font-semibold">{titulo}</p>
            <p>{detalhe}</p>
            <p className="text-suave">
              {formatarData(alteracao.alterado_em)} às {horaEmSaoPaulo(alteracao.alterado_em)}, por{" "}
              {quemAlterou(alteracao.autor, usuarioId)}
            </p>
          </li>
        );
      })}
    </ol>
  );
}
