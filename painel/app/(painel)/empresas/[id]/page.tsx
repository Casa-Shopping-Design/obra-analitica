import type { Metadata } from "next";
import { AbasEmpresa, AvisoTelaEmpresa, CabecalhoEmpresa } from "@/componentes/CabecalhoEmpresa";
import { CartaoValor } from "@/componentes/CartaoValor";
import { ListaContasSemMapa, QuadrosControle } from "@/componentes/ConferenciaEmpresa";
import { SeletorPeriodoEmpresa } from "@/componentes/SeletorPeriodoEmpresa";
import { TabelaDemonstrativo } from "@/componentes/TabelaDemonstrativo";
import { TabelaDemonstrativoMensal } from "@/componentes/TabelaDemonstrativoMensal";
import {
  buscarControle,
  buscarEmpresa,
  lerAcessoEmpresas,
  listarContasSemMapa,
  listarDemonstrativo,
  listarDemonstrativoMensal,
  type Demonstrativo,
} from "@/lib/consultas/empresas";
import {
  ehLinhaIndicador,
  idEmpresaValido,
  montarGradeMensal,
  nomeExibido,
  separarIndicadoresCusto,
  type ResumoEmpresa,
} from "@/lib/empresa";
import {
  descreverPeriodo,
  lerPeriodo,
  mesDe,
  mesesDaGrade,
  mesesDisponiveis,
  rotuloMes,
  type PeriodoEmpresa,
} from "@/lib/empresa-periodo";
import { formatarPercentual } from "@/lib/formatar";
import { mensagensEmpresa } from "@/lib/mensagens-empresa";

export const metadata: Metadata = { title: "Empresa" };

const tela = "Empresa";

type Relatorio = {
  demonstrativo: Demonstrativo;
  titulo: string;
  legenda: string;
  rotuloPercentual?: string;
};

const relatorios: Record<Exclude<PeriodoEmpresa["aba"], "conferencia">, Relatorio> = {
  "fontes-usos": {
    demonstrativo: "fontes_usos",
    titulo: "Fontes e Usos",
    legenda: "Fontes e usos de recursos da empresa, na ordem e com os rótulos da planilha. Valor positivo é fonte.",
  },
  dre: {
    demonstrativo: "dre_societaria",
    titulo: "DRE",
    legenda: "Demonstração de resultado da empresa, com o percentual de cada linha sobre a receita líquida.",
    rotuloPercentual: "% sobre a receita líquida",
  },
  custo: {
    demonstrativo: "custo_incorrido",
    titulo: "Custo incorrido",
    legenda: "Custo incorrido da empresa por natureza, com o percentual de cada linha sobre o custo incorrido.",
    rotuloPercentual: "% do custo incorrido",
  },
};

function AvisoAba({ mensagem, erro = false }: { mensagem: string; erro?: boolean }) {
  return (
    <p role={erro ? "alert" : undefined} className={erro ? "text-alerta" : undefined}>
      {mensagem}
    </p>
  );
}

function textoObras(obras: number): string {
  if (obras === 0) return "Sem obra no painel (holding)";
  return obras === 1 ? "1 obra no painel" : `${obras} obras no painel`;
}

// Uma consulta à view mensal para os até doze meses. O banco devolve cada valor pronto; aqui só se transpõe.
async function RelatorioMensal({ relatorio, empresaId, periodo }: { relatorio: Relatorio; empresaId: string; periodo: PeriodoEmpresa }) {
  const meses = mesesDaGrade(periodo);
  let linhas;
  try {
    linhas = await listarDemonstrativoMensal(relatorio.demonstrativo, empresaId, meses);
  } catch {
    return <AvisoAba mensagem={mensagensEmpresa.relatorioIndisponivel} erro />;
  }
  const grade = montarGradeMensal(linhas.filter((linha) => !ehLinhaIndicador(linha)), meses, periodo.acumulado);
  if (grade.length === 0) return <AvisoAba mensagem={mensagensEmpresa.relatorioVazio} />;
  return (
    <TabelaDemonstrativoMensal
      id="titulo-relatorio"
      titulo={`${relatorio.titulo} mês a mês`}
      legenda={`${relatorio.legenda} Uma coluna por mês, ${periodo.acumulado ? "com o acumulado no fim de cada mês" : "com o movimento de cada mês"}.`}
      meses={meses}
      linhas={grade}
    />
  );
}

// Uma chamada à função do banco, que devolve as linhas da planilha com totais e percentuais já calculados.
async function RelatorioPeriodo({ relatorio, empresaId, periodo }: { relatorio: Relatorio; empresaId: string; periodo: PeriodoEmpresa }) {
  let linhas;
  try {
    linhas = await listarDemonstrativo(relatorio.demonstrativo, empresaId, periodo);
  } catch {
    return <AvisoAba mensagem={mensagensEmpresa.relatorioIndisponivel} erro />;
  }
  const { linhas: linhasTabela, indicadores } = separarIndicadoresCusto(linhas);
  if (linhasTabela.length === 0) return <AvisoAba mensagem={mensagensEmpresa.relatorioVazio} />;
  return (
    <>
      {relatorio.demonstrativo === "custo_incorrido" && (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <CartaoValor
            rotulo="Percentual levado ao resultado"
            valor={indicadores.pctLevadoAoResultado === null ? "sem base" : formatarPercentual(indicadores.pctLevadoAoResultado)}
            nota="Custo das unidades vendidas sobre o custo incorrido. Não é o POC."
          />
          <CartaoValor
            rotulo="Taxa de encargos"
            valor={indicadores.taxaEncargos === null ? "sem base" : formatarPercentual(indicadores.taxaEncargos)}
            nota="Encargos sociais e complementares sobre salários e proventos."
          />
        </div>
      )}
      <TabelaDemonstrativo
        id="titulo-relatorio"
        titulo={relatorio.titulo}
        legenda={relatorio.legenda}
        linhas={linhasTabela}
        rotuloPercentual={relatorio.rotuloPercentual}
      />
    </>
  );
}

// O controle é sempre a posição acumulada no fim do mês final, que é o que a planilha confere.
async function Conferencia({ empresaId, periodo, podeMapear }: { empresaId: string; periodo: PeriodoEmpresa; podeMapear: boolean }) {
  const [controle, contas] = await Promise.all([
    buscarControle(empresaId, periodo.fim).catch(() => undefined),
    listarContasSemMapa(empresaId).catch(() => null),
  ]);
  return (
    <>
      {controle === undefined && <AvisoAba mensagem={mensagensEmpresa.conferenciaIndisponivel} erro />}
      {controle === null && <AvisoAba mensagem={mensagensEmpresa.semControle} />}
      {controle && <QuadrosControle controle={controle} />}
      <ListaContasSemMapa contas={contas} podeMapear={podeMapear} />
    </>
  );
}

async function carregarEmpresa(id: string): Promise<ResumoEmpresa | null | undefined> {
  try {
    return await buscarEmpresa(id);
  } catch {
    return undefined;
  }
}

// O perfil é conferido antes de qualquer leitura; o RLS (app.empresas_permitidas) também esconde a empresa de
// quem não vê todas as obras dela. Só a aba aberta consulta o banco.
export default async function PaginaEmpresa({ params, searchParams }: PageProps<"/empresas/[id]">) {
  const { id } = await params;
  const acesso = await lerAcessoEmpresas();
  if (!acesso.ver) return <AvisoTelaEmpresa tela={tela} mensagem={mensagensEmpresa.restrita} />;
  if (!idEmpresaValido(id)) return <AvisoTelaEmpresa tela={tela} mensagem={mensagensEmpresa.naoEncontrada} />;

  const empresa = await carregarEmpresa(id);
  if (empresa === undefined) return <AvisoTelaEmpresa tela={tela} mensagem={mensagensEmpresa.indisponivel} erro />;
  if (empresa === null) return <AvisoTelaEmpresa tela={tela} mensagem={mensagensEmpresa.naoEncontrada} />;

  const subtitulo = empresa.nomeFantasia && empresa.nomeFantasia !== empresa.nome ? empresa.nome : undefined;
  if (!empresa.primeiraCompetencia || !empresa.ultimaCompetencia) {
    return (
      <>
        <CabecalhoEmpresa nome={nomeExibido(empresa)} subtitulo={subtitulo} nota={textoObras(empresa.obras)} />
        <p>{mensagensEmpresa.semContabilidade}</p>
      </>
    );
  }

  const limites = { primeira: empresa.primeiraCompetencia, ultima: empresa.ultimaCompetencia };
  const lido = lerPeriodo(await searchParams, limites);
  const periodo = lido.aba === "conferencia" && !acesso.editarMapa ? { ...lido, aba: "fontes-usos" as const } : lido;
  const relatorio = periodo.aba === "conferencia" ? null : relatorios[periodo.aba];

  return (
    <>
      <CabecalhoEmpresa
        nome={nomeExibido(empresa)}
        subtitulo={subtitulo}
        nota={`${textoObras(empresa.obras)}. Contabilidade carregada de ${rotuloMes(mesDe(limites.primeira))} a ${rotuloMes(mesDe(limites.ultima))}.`}
      />
      <SeletorPeriodoEmpresa periodo={periodo} meses={mesesDisponiveis(limites)} />
      <AbasEmpresa id={id} periodo={periodo} comConferencia={acesso.editarMapa} />
      <p className="text-sm text-suave">
        {relatorio ? descreverPeriodo(periodo) : `Posição acumulada no fim de ${rotuloMes(periodo.fim)}.`}
        {relatorio && periodo.mensal && " Mês a mês, até 12 colunas."}
      </p>
      {relatorio === null ? (
        <Conferencia empresaId={id} periodo={periodo} podeMapear={acesso.editarMapa} />
      ) : periodo.mensal ? (
        <RelatorioMensal relatorio={relatorio} empresaId={id} periodo={periodo} />
      ) : (
        <RelatorioPeriodo relatorio={relatorio} empresaId={id} periodo={periodo} />
      )}
    </>
  );
}
