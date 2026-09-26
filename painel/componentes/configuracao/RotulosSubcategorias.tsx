import { FormularioRotulo, FormularioSubcategoria } from "@/componentes/configuracao/FormulariosConfiguracao";
import { contextosRotulo, linhasDre, mensagensConfiguracao, type RotuloPersonalizado } from "@/lib/configuracao";
import type { ListaSubcategorias } from "@/lib/consultas/configuracao";

type Categoria = { codigo: string; nome: string };

const celula = "border-b border-borda px-3 py-2 text-left align-top";
const cabecalho = `${celula} font-semibold text-suave`;

export function Rotulos({
  rotulos,
  categorias,
  podeGravar,
}: {
  rotulos: RotuloPersonalizado[];
  categorias: Categoria[];
  podeGravar: boolean;
}) {
  const nomeProduto = (rotulo: RotuloPersonalizado) =>
    rotulo.contexto === "linha_dre"
      ? (linhasDre.find((linha) => linha.chave === rotulo.chave)?.nome ?? rotulo.chave)
      : (categorias.find((categoria) => categoria.codigo === rotulo.chave)?.nome ?? rotulo.chave);
  return (
    <div className="flex flex-col gap-4">
      {rotulos.length === 0 && <p className="text-sm">{mensagensConfiguracao.semRotulos}</p>}
      {rotulos.length > 0 && (
        <div className="overflow-x-auto">
          <table className="w-full min-w-[480px] border-collapse text-sm">
            <caption className="sr-only">Rótulos personalizados da construtora</caption>
            <thead>
              <tr>
                <th scope="col" className={cabecalho}>
                  Onde aparece
                </th>
                <th scope="col" className={cabecalho}>
                  Nome do produto
                </th>
                <th scope="col" className={cabecalho}>
                  Nome da construtora
                </th>
              </tr>
            </thead>
            <tbody>
              {rotulos.map((rotulo) => (
                <tr key={`${rotulo.contexto}-${rotulo.chave}`}>
                  <td className={celula}>
                    {contextosRotulo[rotulo.contexto as keyof typeof contextosRotulo] ?? rotulo.contexto}
                  </td>
                  <th scope="row" className={`${celula} font-normal`}>
                    {nomeProduto(rotulo)}
                  </th>
                  <td className={`${celula} font-semibold`}>{rotulo.rotulo}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {podeGravar && (
        <div className="grid grid-cols-1 gap-4 xl:grid-cols-2">
          <FormularioRotulo
            contexto="linha_dre"
            rotuloContexto={contextosRotulo.linha_dre}
            itens={linhasDre.map((linha) => ({ valor: linha.chave, rotulo: linha.nome }))}
            prefixo="rotulo-dre"
          />
          <FormularioRotulo
            contexto="categoria"
            rotuloContexto={contextosRotulo.categoria}
            itens={categorias.map((categoria) => ({ valor: categoria.codigo, rotulo: categoria.nome }))}
            prefixo="rotulo-categoria"
          />
        </div>
      )}
    </div>
  );
}

export function Subcategorias({
  lista,
  categorias,
  podeGravar,
}: {
  lista: ListaSubcategorias;
  categorias: Categoria[];
  podeGravar: boolean;
}) {
  if (!lista.disponivel) return <p className="text-sm">{mensagensConfiguracao.subcategoriaAusente}</p>;
  const nomes = new Map(categorias.map((categoria) => [categoria.codigo, categoria.nome]));
  const opcoes = categorias.map((categoria) => ({ valor: categoria.codigo, rotulo: categoria.nome }));
  return (
    <div className="flex flex-col gap-4">
      {lista.linhas.length === 0 && <p className="text-sm">{mensagensConfiguracao.semSubcategorias}</p>}
      {lista.linhas.length > 0 && (
        <div className="overflow-x-auto">
          <table className="w-full min-w-[480px] border-collapse text-sm">
            <caption className="sr-only">Subcategorias da construtora</caption>
            <thead>
              <tr>
                <th scope="col" className={cabecalho}>
                  Subcategoria
                </th>
                <th scope="col" className={cabecalho}>
                  Código
                </th>
                <th scope="col" className={cabecalho}>
                  Soma em
                </th>
                <th scope="col" className={cabecalho}>
                  Em uso
                </th>
              </tr>
            </thead>
            <tbody>
              {lista.linhas.map((linha) => (
                <tr key={linha.id}>
                  <th scope="row" className={`${celula} font-semibold`}>
                    {linha.nome}
                  </th>
                  <td className={`${celula} font-mono`}>{linha.codigo}</td>
                  <td className={celula}>{nomes.get(linha.categoria_codigo) ?? linha.categoria_codigo}</td>
                  <td className={celula}>{linha.ativa ? "Sim" : "Não"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {podeGravar && (
        <>
          <FormularioSubcategoria categorias={opcoes} prefixo="subcategoria-nova" />
          {lista.linhas.map((linha) => (
            <details key={linha.id} className="rounded-lg border border-borda p-3">
              <summary className="min-h-11 cursor-pointer content-center font-semibold">Alterar {linha.nome}</summary>
              <div className="pt-3">
                <FormularioSubcategoria categorias={opcoes} subcategoria={linha} prefixo={`subcategoria-${linha.id}`} />
              </div>
            </details>
          ))}
        </>
      )}
      <p className="text-sm text-suave">
        O DRE continua somando pela categoria gerencial. A subcategoria só abre o detalhe das despesas.
      </p>
    </div>
  );
}
