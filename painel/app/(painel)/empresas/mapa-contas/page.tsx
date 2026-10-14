import type { Metadata } from "next";
import Link from "next/link";
import { AvisoTelaEmpresa } from "@/componentes/CabecalhoEmpresa";
import { FormularioMapaContas, type ContaFormulario } from "@/componentes/FormularioMapaContas";
import { lerAcessoEmpresas } from "@/lib/consultas/empresas";
import { listarLinhasConta, listarMapaContas } from "@/lib/consultas/mapa-contas";
import {
  contasPorPagina,
  enderecoMapa,
  grupoContaDe,
  gruposConta,
  lerFiltroMapa,
  opcoesPorGrupo,
  type FiltroMapa,
} from "@/lib/mapa-contas";
import { mensagensMapa } from "@/lib/mensagens-empresa";

export const metadata: Metadata = { title: "Mapa de contas" };

const tela = "Mapa de contas";

const classeCampo =
  "min-h-11 rounded-lg border border-borda bg-superficie px-3 text-[15px] text-texto focus-visible:border-texto";

// Duas leituras em paralelo: a página do plano de contas e o catálogo de linhas do tipo conta.
async function carregar(filtro: FiltroMapa) {
  try {
    const [pagina, catalogo] = await Promise.all([listarMapaContas(filtro), listarLinhasConta()]);
    return { pagina, catalogo };
  } catch {
    return null;
  }
}

// Formulário GET: o filtro fica na URL e a página refaz a consulta no servidor.
function FiltroContas({ filtro }: { filtro: FiltroMapa }) {
  return (
    <form method="get" className="flex flex-wrap items-end gap-4 rounded-xl border border-borda bg-superficie p-5">
      <div className="flex flex-col gap-1.5">
        <label htmlFor="filtro-grupo" className="text-sm font-medium">
          Grupo
        </label>
        <select id="filtro-grupo" name="grupo" defaultValue={filtro.grupo ?? ""} className={classeCampo}>
          <option value="">Todos</option>
          {gruposConta.map((grupo) => (
            <option key={grupo.id} value={grupo.id}>
              {grupo.rotulo}
            </option>
          ))}
        </select>
      </div>
      <label className="flex min-h-11 cursor-pointer items-center gap-2 rounded-lg border border-borda px-3">
        <input type="checkbox" name="sem_mapa" value="1" defaultChecked={filtro.semMapa} className="size-4 accent-menu" />
        Só contas sem mapa
      </label>
      <button type="submit" className="min-h-11 cursor-pointer rounded-lg bg-menu px-5 text-base font-semibold text-menu-texto">
        Filtrar
      </button>
    </form>
  );
}

function Paginacao({ filtro, total }: { filtro: FiltroMapa; total: number }) {
  const paginas = Math.max(1, Math.ceil(total / contasPorPagina));
  if (paginas === 1) return null;
  return (
    <nav aria-label="Páginas do plano de contas" className="flex flex-wrap items-center gap-4 text-sm">
      {filtro.pagina > 1 && (
        <Link href={enderecoMapa(filtro, { pagina: filtro.pagina - 1 })} className="underline underline-offset-4 hover:text-menu">
          Página anterior
        </Link>
      )}
      <span className="text-suave">
        Página {filtro.pagina} de {paginas}
      </span>
      {filtro.pagina < paginas && (
        <Link href={enderecoMapa(filtro, { pagina: filtro.pagina + 1 })} className="underline underline-offset-4 hover:text-menu">
          Próxima página
        </Link>
      )}
    </nav>
  );
}

// Só diretor e financeiro; os outros perfis recebem o aviso antes de qualquer leitura. A Server Action e a
// função do banco conferem de novo, com o segundo fator.
export default async function PaginaMapaContas({ searchParams }: PageProps<"/empresas/mapa-contas">) {
  const acesso = await lerAcessoEmpresas();
  if (!acesso.editarMapa) return <AvisoTelaEmpresa tela={tela} mensagem={mensagensMapa.restrita} />;

  const filtro = lerFiltroMapa(await searchParams);
  const dados = await carregar(filtro);

  const opcoes = dados ? Object.fromEntries(opcoesPorGrupo(dados.catalogo)) : {};
  const rotulosLinha = dados ? Object.fromEntries(dados.catalogo.map((item) => [item.linha, item.rotulo])) : {};
  const contas: ContaFormulario[] =
    dados?.pagina.contas.map((conta) => ({
      conta: conta.conta,
      nome: conta.nome,
      analitica: conta.analitica,
      grupoConta: grupoContaDe(conta.conta),
      linha: conta.linha,
      linhaEfetiva: conta.linhaEfetiva,
    })) ?? [];

  return (
    <>
      <header className="flex flex-col gap-2">
        <Link href="/empresas" className="w-fit text-sm text-suave underline underline-offset-4 hover:text-texto">
          Voltar para as empresas
        </Link>
        <h1 className="font-serif text-[34px] font-semibold">{tela}</h1>
        <p className="max-w-3xl text-suave">
          Em que linha das Fontes e Usos, da DRE ou do custo incorrido cada conta contábil entra. O mapa vale para todas
          as empresas da construtora. Conta analítica com linha própria vence; sem ela, vale a linha da conta sintética
          mais próxima. Cada gravação cria uma versão nova e a anterior fica guardada.
        </p>
      </header>
      <FiltroContas filtro={filtro} />
      {dados === null && (
        <p role="alert" className="text-alerta">
          {mensagensMapa.indisponivel}
        </p>
      )}
      {dados && contas.length === 0 && <p>{mensagensMapa.semContas}</p>}
      {dados && contas.length > 0 && (
        <>
          <p className="text-sm text-suave">
            {dados.pagina.total === 1 ? "1 conta" : `${dados.pagina.total} contas`} neste filtro. As opções de cada conta
            são as linhas do mesmo grupo contábil.
          </p>
          <FormularioMapaContas
            key={enderecoMapa(filtro)}
            contas={contas}
            opcoesPorGrupo={opcoes}
            rotulosLinha={rotulosLinha}
          />
          <Paginacao filtro={filtro} total={dados.pagina.total} />
        </>
      )}
    </>
  );
}
