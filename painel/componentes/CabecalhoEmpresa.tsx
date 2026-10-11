import Link from "next/link";
import { abasEmpresa, enderecoEmpresa, type PeriodoEmpresa } from "@/lib/empresa-periodo";

// Topo das telas de uma empresa: volta para a lista, diz o nome e a nota de obras e competência.
export function CabecalhoEmpresa({ nome, subtitulo, nota }: { nome: string; subtitulo?: string; nota?: string }) {
  return (
    <header className="flex flex-col gap-1">
      <Link href="/empresas" className="w-fit text-sm text-suave underline underline-offset-4 hover:text-texto print:hidden">
        Voltar para as empresas
      </Link>
      <h1 className="font-serif text-[34px] leading-tight font-semibold">{nome}</h1>
      {subtitulo && <p className="text-sm text-suave">{subtitulo}</p>}
      {nota && <p className="text-sm text-suave">{nota}</p>}
    </header>
  );
}

// Perfil sem acesso, empresa fora do perfil ou erro de carga: o título, o aviso e o caminho de volta.
export function AvisoTelaEmpresa({ tela, mensagem, erro = false }: { tela: string; mensagem: string; erro?: boolean }) {
  return (
    <>
      <h1 className="font-serif text-[34px] font-semibold">{tela}</h1>
      <p role={erro ? "alert" : undefined} className={erro ? "text-alerta" : undefined}>
        {mensagem}
      </p>
      <Link href="/" className="w-fit text-sm underline underline-offset-4 hover:text-menu">
        Voltar para a visão geral
      </Link>
    </>
  );
}

// As abas são links: cada uma é um endereço próprio, que mantém o período escolhido.
// A conferência lê views restritas a diretor e financeiro; para os outros perfis a aba nem aparece.
export function AbasEmpresa({ id, periodo, comConferencia }: { id: string; periodo: PeriodoEmpresa; comConferencia: boolean }) {
  return (
    <nav aria-label="Relatórios da empresa" className="border-b border-borda print:hidden">
      <ul className="-mb-px flex flex-wrap gap-x-1">
        {abasEmpresa.filter((aba) => comConferencia || aba.id !== "conferencia").map((aba) => {
          const ativa = aba.id === periodo.aba;
          return (
            <li key={aba.id}>
              <Link
                href={enderecoEmpresa(id, periodo, { aba: aba.id })}
                aria-current={ativa ? "page" : undefined}
                scroll={false}
                className={`flex min-h-11 items-center border-b-2 px-3 text-[15px] ${
                  ativa ? "border-menu font-semibold text-texto" : "border-transparent text-suave hover:text-texto"
                }`}
              >
                {aba.rotulo}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
