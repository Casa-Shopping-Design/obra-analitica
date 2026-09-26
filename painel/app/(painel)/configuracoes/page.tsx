import type { Metadata } from "next";
import Link from "next/link";
import { CodigosOrigem } from "@/componentes/configuracao/CodigosOrigem";
import { HistoricoConfiguracao } from "@/componentes/configuracao/HistoricoConfiguracao";
import { ParametrosConfiguracao } from "@/componentes/configuracao/ParametrosConfiguracao";
import { Rotulos, Subcategorias } from "@/componentes/configuracao/RotulosSubcategorias";
import { Aviso, Bloco, ErroBloco } from "@/componentes/financeiro/Aviso";
import { escopoConstrutora, lerEscopo, mensagensConfiguracao, montarGrupos } from "@/lib/configuracao";
import {
  listarCatalogo,
  listarHistoricoConfiguracao,
  listarMapaCodigos,
  listarPendenciasCodigo,
  listarRotulos,
  listarSubcategorias,
  listarValoresCodigo,
  listarValoresParametro,
} from "@/lib/consultas/configuracao";
import { listarCategoriasGerenciais } from "@/lib/consultas/dre";
import { exigirIdentidade } from "@/lib/consultas/identidade";
import {
  buscarPerfilAtual,
  listarCentrosCusto,
  podeGravarFinanceiro,
  tentarConsulta,
} from "@/lib/consultas/referencia";

export const metadata: Metadata = { title: "Configurações" };

const secoes = [
  { id: "parametros", rotulo: "Parâmetros" },
  { id: "codigos", rotulo: "Códigos da origem" },
  { id: "rotulos", rotulo: "Rótulos" },
  { id: "subcategorias", rotulo: "Subcategorias" },
  { id: "criterio-contas", rotulo: "Critério e contas" },
  { id: "historico", rotulo: "Histórico" },
];

// Identidade, perfil e centros primeiro (o escopo depende das obras liberadas); depois nove consultas em
// paralelo, todas pequenas (catálogo, valores, códigos, pendências, rótulos, categorias, subcategorias, auditoria).
export default async function PaginaConfiguracoes({ searchParams }: PageProps<"/configuracoes">) {
  const identidade = await exigirIdentidade();
  const filtros = await searchParams;
  const [perfil, centros] = await Promise.all([
    tentarConsulta(buscarPerfilAtual()),
    tentarConsulta(listarCentrosCusto()),
  ]);
  const podeGravar = podeGravarFinanceiro(perfil);
  const obras = (centros ?? []).filter((centro) => centro.tipo === "obra");
  const nomesObra = new Map(obras.map((obra) => [obra.id, obra.nome]));
  const escopoPedido = lerEscopo(Array.isArray(filtros.escopo) ? filtros.escopo[0] : filtros.escopo);
  const obra =
    escopoPedido.ok && escopoPedido.centroId
      ? (obras.find((item) => item.id === escopoPedido.centroId) ?? null)
      : null;
  const obraNaoEncontrada = !escopoPedido.ok || (escopoPedido.centroId !== null && centros !== null && obra === null);
  const centroId = obra?.id ?? null;
  const escopo = obra
    ? { valor: obra.id, rotulo: `a obra ${obra.nome}`, ehObra: true }
    : { valor: escopoConstrutora, rotulo: "a construtora", ehObra: false };

  const [catalogo, valores, mapa, valoresCodigo, pendencias, rotulos, categorias, subcategorias, historico] =
    await Promise.all([
      tentarConsulta(listarCatalogo()),
      tentarConsulta(listarValoresParametro(centroId)),
      tentarConsulta(listarMapaCodigos()),
      tentarConsulta(listarValoresCodigo()),
      tentarConsulta(listarPendenciasCodigo()),
      tentarConsulta(listarRotulos()),
      tentarConsulta(listarCategoriasGerenciais()),
      tentarConsulta(listarSubcategorias()),
      tentarConsulta(listarHistoricoConfiguracao()),
    ]);
  const grupos = catalogo && valores ? montarGrupos(catalogo, valores, centroId) : null;
  const rotulosCategoria = (categorias ?? []).map((categoria) => ({ codigo: categoria.codigo, nome: categoria.nome }));

  return (
    <>
      <header className="flex flex-col gap-2">
        <h1 className="font-serif text-[34px] font-semibold">Configurações</h1>
        <p className="max-w-3xl text-suave">
          Regras e preferências da construtora. Cada parâmetro mostra o valor em vigor e de onde ele vem: padrão do
          produto, valor da construtora ou valor da obra. A obra vence a construtora, e a construtora vence o padrão.
        </p>
        {!podeGravar && <p className="max-w-3xl text-sm">{mensagensConfiguracao.semPermissaoLeitura}</p>}
        <nav aria-label="Seções da página" className="flex flex-wrap gap-x-5 gap-y-2 pt-1 text-sm font-semibold">
          {secoes.map((secao) => (
            <a key={secao.id} href={`#${secao.id}`} className="underline underline-offset-4 hover:text-menu">
              {secao.rotulo}
            </a>
          ))}
        </nav>
      </header>

      {podeGravar && (
        <Aviso titulo="Antes de mudar uma regra">
          Parâmetros de reconhecimento, DRE e caixa mudam números que outras pessoas já viram. Registre na observação
          com quem a mudança foi combinada; ela fica no histórico com o seu usuário.
        </Aviso>
      )}

      <section id="parametros" aria-labelledby="titulo-parametros" className="flex scroll-mt-4 flex-col gap-4">
        <h2 id="titulo-parametros" className="font-serif text-2xl font-semibold">
          Parâmetros
        </h2>
        <form
          action="/configuracoes"
          method="get"
          aria-label="Escolher o escopo"
          className="flex flex-col gap-3 rounded-xl border border-borda bg-superficie p-4 sm:flex-row sm:items-end"
        >
          <div className="flex min-w-0 flex-1 flex-col gap-1.5">
            <label htmlFor="configuracao-escopo" className="text-sm font-medium">
              Ver e alterar valores de
            </label>
            <select
              id="configuracao-escopo"
              name="escopo"
              defaultValue={escopo.valor}
              aria-describedby="configuracao-escopo-ajuda"
              className="min-h-11 w-full rounded-lg border border-borda bg-superficie px-3"
            >
              <option value={escopoConstrutora}>Construtora (todas as obras)</option>
              {obras.map((item) => (
                <option key={item.id} value={item.id}>
                  Obra {item.nome}
                </option>
              ))}
            </select>
            <p id="configuracao-escopo-ajuda" className="text-xs text-suave">
              Só os parâmetros que aceitam valor por obra mudam numa obra. Os demais valem para a construtora inteira.
            </p>
          </div>
          <button
            type="submit"
            className="min-h-11 cursor-pointer rounded-lg bg-menu px-4 font-semibold text-menu-texto hover:bg-menu-ativo"
          >
            Mostrar
          </button>
        </form>
        {obraNaoEncontrada && <p role="alert">{mensagensConfiguracao.obraNaoEncontrada}</p>}
        {obra && (
          <p className="text-sm">
            Mostrando os valores em vigor na obra <strong>{obra.nome}</strong>.
          </p>
        )}
        {grupos === null && (
          <p role="alert" className="text-alerta">
            {mensagensConfiguracao.catalogoIndisponivel}
          </p>
        )}
        {grupos && (
          <ParametrosConfiguracao
            grupos={grupos}
            escopo={escopo}
            podeGravar={podeGravar}
            usuarioId={identidade.usuarioId}
          />
        )}
      </section>

      <Bloco
        id="codigos"
        titulo="Códigos da origem"
        contexto="Como os códigos do sistema de origem viram condição de pagamento e situação de unidade e de contrato. Valem para a construtora inteira."
      >
        {(mapa === null || pendencias === null || valoresCodigo === null) && <ErroBloco />}
        <CodigosOrigem
          mapa={mapa}
          pendencias={pendencias}
          valoresCodigo={valoresCodigo ?? []}
          podeGravar={podeGravar && valoresCodigo !== null}
          usuarioId={identidade.usuarioId}
        />
      </Bloco>

      <Bloco
        id="rotulos"
        titulo="Rótulos personalizados"
        contexto="Troca o nome que aparece nas telas pelo nome que a construtora usa. A definição do número continua a do produto."
      >
        {rotulos === null ? (
          <ErroBloco />
        ) : (
          <Rotulos rotulos={rotulos} categorias={rotulosCategoria} podeGravar={podeGravar} />
        )}
      </Bloco>

      <Bloco
        id="subcategorias"
        titulo="Subcategorias de despesa"
        contexto="Detalhe próprio da construtora dentro de uma categoria gerencial, para abrir as despesas."
      >
        {subcategorias === null || categorias === null ? (
          <ErroBloco />
        ) : (
          <Subcategorias lista={subcategorias} categorias={rotulosCategoria} podeGravar={podeGravar} />
        )}
      </Bloco>

      <Bloco
        id="criterio-contas"
        titulo="Critério de reconhecimento e contas"
        contexto="Ficam no DRE gerencial, perto dos números que mudam com eles."
      >
        <ul className="flex flex-col gap-2 text-sm">
          <li>
            <Link href="/dre#criterio" className="font-semibold underline underline-offset-4 hover:text-menu">
              Critério de reconhecimento de receita e custo
            </Link>{" "}
            <span className="text-suave">validado pelo financeiro, por construtora ou por obra.</span>
          </li>
          <li>
            <Link href="/dre#pendencias" className="font-semibold underline underline-offset-4 hover:text-menu">
              Mapeamento das contas da origem para as categorias
            </Link>{" "}
            <span className="text-suave">e a lista de contas ainda sem categoria.</span>
          </li>
        </ul>
      </Bloco>

      <Bloco
        id="historico"
        titulo="Últimas alterações"
        contexto="Parâmetros, códigos, rótulos e subcategorias, da mais recente para a mais antiga. Só diretor e financeiro veem o histórico."
      >
        {historico === null && <ErroBloco />}
        {historico && (
          <HistoricoConfiguracao
            alteracoes={historico}
            catalogo={catalogo ?? []}
            nomesObra={nomesObra}
            valoresCodigo={valoresCodigo ?? []}
            usuarioId={identidade.usuarioId}
          />
        )}
      </Bloco>

    </>
  );
}
