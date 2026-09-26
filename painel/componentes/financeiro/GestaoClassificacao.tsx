import { classificarConta } from "@/app/(painel)/dre/acoes";
import { FormularioClassificacao, type CategoriaOpcao } from "@/componentes/financeiro/FormulariosDre";
import {
  categoriaServeParaOrigem,
  rotulosTipoOrigem,
  tiposOrigemConta,
} from "@/componentes/financeiro/regras-classificacao";
import type { CategoriaGerencial, LinhaPendenciaClassificacao, MapeamentoConta } from "@/lib/consultas/dre";
import { formatarData } from "@/lib/formatar";

export function opcoesCategoria(categorias: CategoriaGerencial[]): CategoriaOpcao[] {
  return categorias
    .map((categoria) => ({
      codigo: categoria.codigo,
      nome: categoria.nome,
      tipos: tiposOrigemConta.filter((tipo) => categoriaServeParaOrigem(tipo, categoria)),
    }))
    .filter((categoria) => categoria.tipos.length > 0);
}

// Uma caixa por conta pendente com código (sem código na origem não há o que mapear), mais um formulário
// livre para reclassificar e a lista das contas já classificadas.
export function GestaoClassificacao({
  pendencias,
  categorias,
  mapeamentos,
}: {
  pendencias: LinhaPendenciaClassificacao[];
  categorias: CategoriaGerencial[];
  mapeamentos: { linhas: MapeamentoConta[]; total: number } | null;
}) {
  const opcoes = opcoesCategoria(categorias);
  const nomes = new Map(categorias.map((categoria) => [categoria.codigo, categoria.nome]));
  const classificaveis = pendencias.filter((linha) => linha.conta_origem !== null);
  return (
    <div className="flex flex-col gap-4">
      {classificaveis.length > 0 && (
        <div className="flex flex-col gap-2">
          <h3 className="font-semibold">Classificar as contas da lista</h3>
          <ul className="flex flex-col gap-2">
            {classificaveis.map((linha, posicao) => (
              <li key={`${linha.tipo_origem}-${linha.conta_origem}`}>
                <details className="rounded-lg border border-borda p-3">
                  <summary className="min-h-11 cursor-pointer content-center font-medium">
                    {rotulosTipoOrigem[linha.tipo_origem]} {linha.conta_origem}
                  </summary>
                  <div className="pt-3">
                    <FormularioClassificacao
                      acao={classificarConta}
                      prefixo={`pendencia-${posicao}`}
                      categorias={opcoes}
                      tipoOrigem={linha.tipo_origem}
                      conta={linha.conta_origem as string}
                    />
                  </div>
                </details>
              </li>
            ))}
          </ul>
        </div>
      )}
      <details className="rounded-lg border border-borda p-3">
        <summary className="min-h-11 cursor-pointer content-center font-medium">
          Reclassificar uma conta já classificada
        </summary>
        <div className="flex flex-col gap-4 pt-3">
          <FormularioClassificacao acao={classificarConta} prefixo="reclassificar" categorias={opcoes} />
          {mapeamentos && mapeamentos.total > 0 && (
            <table className="w-full text-sm">
              <caption className="pb-2 text-left text-suave">
                Contas já classificadas, da alteração mais recente para a mais antiga
                {mapeamentos.total > mapeamentos.linhas.length &&
                  ` (mostrando ${mapeamentos.linhas.length} de ${mapeamentos.total})`}
              </caption>
              <thead>
                <tr className="border-b border-borda text-suave">
                  <th scope="col" className="py-2 pr-3 text-left font-medium">
                    Conta
                  </th>
                  <th scope="col" className="py-2 pr-3 text-left font-medium">
                    Categoria
                  </th>
                  <th scope="col" className="py-2 text-left font-medium">
                    Alterada em
                  </th>
                </tr>
              </thead>
              <tbody>
                {mapeamentos.linhas.map((linha) => (
                  <tr
                    key={`${linha.tipo_origem}-${linha.conta_origem}`}
                    className="border-b border-borda last:border-b-0"
                  >
                    <th scope="row" className="py-2 pr-3 text-left font-normal break-all">
                      {linha.conta_origem}
                      <span className="block text-xs text-suave">{rotulosTipoOrigem[linha.tipo_origem]}</span>
                    </th>
                    <td className="py-2 pr-3">{nomes.get(linha.categoria_codigo) ?? linha.categoria_codigo}</td>
                    <td className="py-2">{formatarData(linha.atualizado_em)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </details>
    </div>
  );
}
