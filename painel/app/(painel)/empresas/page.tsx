import type { Metadata } from "next";
import Link from "next/link";
import { AvisoTelaEmpresa } from "@/componentes/CabecalhoEmpresa";
import { lerAcessoEmpresas, listarEmpresas } from "@/lib/consultas/empresas";
import { nomeExibido, situacaoIdentidade, type ResumoEmpresa } from "@/lib/empresa";
import { mesDe, rotuloMes } from "@/lib/empresa-periodo";
import { formatarReal } from "@/lib/formatar";
import { mensagensEmpresa } from "@/lib/mensagens-empresa";

export const metadata: Metadata = { title: "Empresas" };

const titulo = "Empresas";

async function carregar(): Promise<ResumoEmpresa[] | null> {
  try {
    return await listarEmpresas();
  } catch {
    return null;
  }
}

function textoObras(obras: number): string {
  if (obras === 0) return "Sem obra (holding)";
  return obras === 1 ? "1 obra" : `${obras} obras`;
}

function valorOuTraco(valor: number | null): string {
  return valor === null ? "sem dado" : formatarReal(valor);
}

function SeloIdentidade({ empresa }: { empresa: ResumoEmpresa }) {
  const situacao = situacaoIdentidade(empresa.diferencaIdentidade);
  if (situacao === "sem_dado") return null;
  const fecha = situacao === "fecha";
  return (
    <span
      className={`w-fit rounded-sm border px-2 py-0.5 text-sm font-semibold ${
        fecha ? "border-entrada text-entrada" : "border-atencao text-atencao"
      }`}
    >
      {fecha ? "Fecha com o caixa" : `Diferença de ${formatarReal(empresa.diferencaIdentidade ?? 0)}`}
    </span>
  );
}

function CartaoEmpresa({ empresa }: { empresa: ResumoEmpresa }) {
  const idTitulo = `empresa-${empresa.empresaId}`;
  const carregada = empresa.ultimaCompetencia !== null;
  return (
    <article aria-labelledby={idTitulo} className="flex h-full flex-col gap-4 secao">
      <header className="flex flex-col gap-1">
        <h2 id={idTitulo} className="font-serif text-xl font-semibold">
          <Link href={`/empresas/${empresa.empresaId}`} className="underline underline-offset-4 hover:text-menu">
            {nomeExibido(empresa)}
          </Link>
        </h2>
        <p className="text-sm text-suave">
          {textoObras(empresa.obras)}
          {carregada && empresa.ultimaCompetencia && `. Contabilidade até ${rotuloMes(mesDe(empresa.ultimaCompetencia))}`}
        </p>
      </header>
      {carregada ? (
        <>
          <dl className="grid grid-cols-1 gap-3 sm:grid-cols-3">
            <div className="flex flex-col gap-1">
              <dt className="text-sm text-suave">Caixa e equivalentes</dt>
              <dd className="text-lg font-semibold tabular-nums">{valorOuTraco(empresa.caixaEquivalentes)}</dd>
            </div>
            <div className="flex flex-col gap-1">
              <dt className="text-sm text-suave">Fluxo operacional</dt>
              <dd className="text-lg font-semibold tabular-nums">{valorOuTraco(empresa.fluxoOperacional)}</dd>
            </div>
            <div className="flex flex-col gap-1">
              <dt className="text-sm text-suave">Lucro líquido</dt>
              <dd className="text-lg font-semibold tabular-nums">{valorOuTraco(empresa.lucroLiquido)}</dd>
            </div>
          </dl>
          <div className="flex flex-wrap items-center gap-3">
            <SeloIdentidade empresa={empresa} />
            {empresa.contasSemMapa > 0 && (
              <span className="text-sm text-atencao">
                {empresa.contasSemMapa === 1 ? "1 conta sem mapa" : `${empresa.contasSemMapa} contas sem mapa`}
              </span>
            )}
          </div>
        </>
      ) : (
        <p>{mensagensEmpresa.semContabilidade}</p>
      )}
    </article>
  );
}

// O perfil é conferido antes da leitura; o RLS também esconderia as empresas, mas a tela diz por quê.
export default async function PaginaEmpresas() {
  const acesso = await lerAcessoEmpresas();
  if (!acesso.ver) return <AvisoTelaEmpresa tela={titulo} mensagem={mensagensEmpresa.restrita} />;

  const empresas = await carregar();

  return (
    <>
      <header className="flex flex-col gap-2">
        <h1 className="font-serif text-[28px] font-semibold">{titulo}</h1>
        <p className="max-w-3xl text-suave">
          Fontes e Usos, DRE e custo incorrido de cada empresa, montados a partir do balancete do ERP, com as mesmas
          linhas da planilha. Os valores são acumulados até o último mês carregado.
        </p>
        {acesso.editarMapa && (
          <Link href="/empresas/mapa-contas" className="w-fit text-sm font-semibold underline underline-offset-4 hover:text-menu">
            Mapa de contas
          </Link>
        )}
      </header>
      {empresas === null && (
        <p role="alert" className="text-alerta">
          {mensagensEmpresa.indisponivel}
        </p>
      )}
      {empresas?.length === 0 && <p>{mensagensEmpresa.semEmpresas}</p>}
      {empresas && empresas.length > 0 && (
        <ul aria-label="Empresas" className="grid grid-cols-1 gap-x-10 gap-y-10 xl:grid-cols-2">
          {empresas.map((empresa) => (
            <li key={empresa.empresaId}>
              <CartaoEmpresa empresa={empresa} />
            </li>
          ))}
        </ul>
      )}
    </>
  );
}
