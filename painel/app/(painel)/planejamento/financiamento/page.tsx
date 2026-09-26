import type { Metadata } from "next";
import Link from "next/link";
import { Aviso, Bloco, ErroBloco } from "@/componentes/financeiro/Aviso";
import { AvisoCarga } from "@/componentes/financeiro/AvisoCarga";
import { Selo } from "@/componentes/financeiro/Selo";
import {
  FormularioAtualizarLiberacao,
  FormularioEtapa,
  FormularioLiberacao,
  FormularioMedicao,
  FormularioOperacao,
} from "@/componentes/planejamento/FormulariosFinanciamento";
import { TabelaPlanejamento } from "@/componentes/planejamento/TabelaPlanejamento";
import { Inteiro, Percentual, Valor } from "@/componentes/planejamento/Valor";
import {
  listarFinanciamentoContratos,
  listarHistoricoComplemento,
  listarLiberacoes,
  listarMedicoes,
  listarSaldoOperacoes,
  type AlteracaoRegistro,
  type FinanciamentoContrato,
  type LinhaLiberacao,
  type MedicaoBancaria,
  type SaldoOperacaoCredito,
} from "@/lib/consultas/financiamento";
import { exigirIdentidade } from "@/lib/consultas/identidade";
import { carregarReferencia, listarCentrosCusto, tentarConsulta } from "@/lib/consultas/referencia";
import { formatarData, formatarReal } from "@/lib/formatar";
import { mensagens } from "@/lib/mensagens";
import {
  explicacoesPlanejamento,
  mensagensPlanejamento,
  rotulosClassificacao,
  rotulosEtapa,
  rotulosModalidade,
  rotulosNivelLiberacao,
  rotulosSituacaoLiberacao,
  rotulosSituacaoMedicao,
} from "@/lib/mensagens-planejamento";
import { horaEmSaoPaulo, lerIdCentro } from "@/lib/periodo";
import { atualizarLiberacao, registrarEtapa, registrarLiberacao, registrarMedicao, registrarOperacao } from "./acoes";

export const metadata: Metadata = { title: "Financiamento e medições" };

function TabelaOperacoes({ operacoes, nomes }: { operacoes: SaldoOperacaoCredito[]; nomes: Record<string, string> }) {
  return (
    <TabelaPlanejamento
      legenda="Operações de crédito da obra e saldo"
      rotuloPrimeira="Banco"
      colunas={[
        { chave: "obra", rotulo: "Obra", texto: true },
        { chave: "modalidade", rotulo: "Modalidade", texto: true },
        { chave: "contratado", rotulo: "Contratado" },
        { chave: "retencao", rotulo: "Retenção" },
        { chave: "liberado", rotulo: "Liberado e recebido" },
        { chave: "previsto", rotulo: "Previsto em aberto" },
        { chave: "liberavel", rotulo: "Saldo liberável", explicacao: explicacoesPlanejamento.saldo_liberavel },
        { chave: "nao_programado", rotulo: "Sem liberação programada" },
        { chave: "medido", rotulo: "Medido e elegível", explicacao: explicacoesPlanejamento.medido_elegivel },
        { chave: "elegivel", rotulo: "Elegível não liberado" },
      ]}
      linhas={operacoes.map((operacao) => ({
        chave: operacao.operacao_credito_id,
        rotulo: (
          <span className="inline-flex flex-col gap-1">
            {operacao.instituicao}
            {operacao.excede_limite && <Selo tipo="alerta">passa do limite</Selo>}
          </span>
        ),
        celulas: {
          obra: nomes[operacao.centro_custo_id] ?? "",
          modalidade: rotulosModalidade[operacao.modalidade] ?? operacao.modalidade,
          contratado: <Valor valor={operacao.valor_contratado} />,
          retencao: (
            <span className="inline-flex flex-col items-end">
              <Percentual fracao={operacao.percentual_retencao} />
              <Valor valor={operacao.retencao_prevista} ausente="" />
            </span>
          ),
          liberado: <Valor valor={operacao.liberado_recebido} />,
          previsto: <Valor valor={operacao.previsto_aberto} />,
          liberavel: <Valor valor={operacao.saldo_liberavel} />,
          nao_programado: <Valor valor={operacao.saldo_nao_programado} />,
          medido: <Valor valor={operacao.medido_elegivel} />,
          elegivel: <Valor valor={operacao.elegivel_nao_liberado} />,
        },
      }))}
    />
  );
}

function TabelaContratos({ contratos }: { contratos: FinanciamentoContrato[] }) {
  return (
    <TabelaPlanejamento
      legenda="Etapa do financiamento por contrato"
      rotuloPrimeira="Contrato"
      colunas={[
        { chave: "unidade", rotulo: "Unidade", texto: true },
        { chave: "classificacao", rotulo: "Classificação", texto: true },
        { chave: "etapa", rotulo: "Etapa no banco", texto: true },
        { chave: "prevista", rotulo: "Liberação prevista" },
        { chave: "financiado", rotulo: "Valor financiado" },
        { chave: "aberto", rotulo: "Financiamento em aberto" },
        { chave: "recebido", rotulo: "Financiamento recebido" },
        { chave: "banco", rotulo: "Banco na origem", texto: true },
      ]}
      linhas={contratos.map((contrato) => ({
        chave: String(contrato.contrato_id_origem),
        rotulo: contrato.contrato_numero ?? String(contrato.contrato_id_origem),
        celulas: {
          unidade: contrato.unidade ?? "Não informado",
          classificacao: (
            <Selo tipo={contrato.classificacao === "financiamento_pendente" ? "parcial" : "informativo"}>
              {rotulosClassificacao[contrato.classificacao]}
            </Selo>
          ),
          etapa: contrato.etapa ? (
            <span className="flex flex-col text-xs">
              <span className="text-sm">{rotulosEtapa[contrato.etapa]}</span>
              {contrato.data_etapa && <span className="text-suave">em {formatarData(contrato.data_etapa)}</span>}
              {contrato.pendencia && <span className="text-atencao">Pendência: {contrato.motivo_pendencia}</span>}
            </span>
          ) : (
            <span className="text-suave">Sem etapa cadastrada</span>
          ),
          prevista: contrato.data_prevista_liberacao ? (
            formatarData(contrato.data_prevista_liberacao)
          ) : (
            <span className="text-suave">Não informada</span>
          ),
          financiado: <Valor valor={contrato.valor_financiado} />,
          aberto: <Valor valor={contrato.saldo_financiamento_aberto} />,
          recebido: <Valor valor={contrato.recebido_financiamento} />,
          banco: contrato.instituicao_financeira ?? "Não informado",
        },
      }))}
    />
  );
}

function TabelaMedicoes({ medicoes, bancos }: { medicoes: MedicaoBancaria[]; bancos: Record<string, string> }) {
  return (
    <TabelaPlanejamento
      legenda="Medições do banco"
      rotuloPrimeira="Medição"
      colunas={[
        { chave: "operacao", rotulo: "Operação", texto: true },
        { chave: "vistoria", rotulo: "Vistoria" },
        { chave: "avanco", rotulo: "Avanço informado" },
        { chave: "situacao", rotulo: "Situação", texto: true },
        { chave: "medido", rotulo: "Medido" },
        { chave: "elegivel", rotulo: "Elegível" },
        { chave: "retido", rotulo: "Retido" },
        { chave: "fonte", rotulo: "Fonte", texto: true },
      ]}
      linhas={medicoes.map((medicao) => ({
        chave: medicao.id,
        rotulo: `Nº ${medicao.numero}`,
        celulas: {
          operacao: bancos[medicao.operacao_credito_id] ?? "Operação",
          vistoria: formatarData(medicao.data_vistoria),
          avanco: <Percentual fracao={medicao.avanco_fisico_informado} />,
          situacao: `${rotulosSituacaoMedicao[medicao.situacao] ?? medicao.situacao}${medicao.data_aprovacao ? ` em ${formatarData(medicao.data_aprovacao)}` : ""}`,
          medido: <Valor valor={medicao.valor_medido} />,
          elegivel: <Valor valor={medicao.valor_elegivel} />,
          retido: <Valor valor={medicao.valor_retido} />,
          fonte: `${medicao.fonte}${medicao.referencia_documento ? ` (${medicao.referencia_documento})` : ""}`,
        },
      }))}
    />
  );
}

function descricaoLiberacao(liberacao: LinhaLiberacao, bancos: Record<string, string>): string {
  if (liberacao.nivel === "contrato") return `Contrato ${liberacao.contrato_numero ?? liberacao.contrato_id_origem}`;
  const banco = liberacao.operacao_credito_id ? bancos[liberacao.operacao_credito_id] : undefined;
  const nivel =
    liberacao.nivel === "lote" ? `Lote ${liberacao.descricao_lote ?? ""}` : rotulosNivelLiberacao.empreendimento;
  return banco ? `${nivel} (${banco})` : nivel;
}

function TabelaLiberacoes({ liberacoes, bancos }: { liberacoes: LinhaLiberacao[]; bancos: Record<string, string> }) {
  return (
    <TabelaPlanejamento
      legenda="Liberações previstas, recebidas e pendentes"
      rotuloPrimeira="Liberação"
      colunas={[
        { chave: "prevista", rotulo: "Data prevista" },
        { chave: "valor", rotulo: "Valor previsto" },
        { chave: "situacao", rotulo: "Situação", texto: true },
        { chave: "recebido", rotulo: "Recebido" },
        { chave: "vinculo", rotulo: "Dinheiro no caixa", texto: true },
        { chave: "fonte", rotulo: "Fonte", texto: true },
      ]}
      linhas={liberacoes.map((liberacao) => ({
        chave: liberacao.id,
        rotulo: descricaoLiberacao(liberacao, bancos),
        celulas: {
          prevista: formatarData(liberacao.data_prevista),
          valor: <Valor valor={liberacao.valor_previsto} />,
          situacao: (
            <span className="flex flex-col gap-0.5">
              <Selo
                tipo={
                  liberacao.situacao_efetiva === "atrasada"
                    ? "alerta"
                    : liberacao.situacao_efetiva === "pendente"
                      ? "parcial"
                      : "informativo"
                }
              >
                {rotulosSituacaoLiberacao[liberacao.situacao_efetiva]}
              </Selo>
              {liberacao.dias_atraso !== null && (
                <span className="text-xs text-suave">{liberacao.dias_atraso} dias de atraso</span>
              )}
              {liberacao.motivo && <span className="text-xs">{liberacao.motivo}</span>}
            </span>
          ),
          recebido:
            liberacao.valor_recebido === null ? (
              <span className="text-suave">Não recebido</span>
            ) : (
              <span className="inline-flex flex-col items-end">
                <Valor valor={liberacao.valor_recebido} />
                {liberacao.data_recebimento && (
                  <span className="text-xs text-suave">{formatarData(liberacao.data_recebimento)}</span>
                )}
              </span>
            ),
          vinculo:
            liberacao.vinculo_tipo === "recebimento"
              ? "Já contado nos recebimentos da origem"
              : liberacao.vinculo_tipo === "lancamento_manual"
                ? "Contado pelo extrato"
                : liberacao.nivel === "contrato"
                  ? "Vem da parcela de financiamento"
                  : "Ainda não",
          fonte: `${liberacao.fonte}${liberacao.referencia_documento ? ` (${liberacao.referencia_documento})` : ""}`,
        },
      }))}
    />
  );
}

const rotulosTabela: Record<string, string> = {
  "app.operacao_credito_obra": "Operação de crédito",
  "app.etapa_financiamento_contrato": "Etapa de financiamento",
  "app.medicao_bancaria": "Medição",
  "app.liberacao_financiamento": "Liberação",
};
const rotulosOperacao: Record<string, string> = { insert: "Cadastro", update: "Alteração", delete: "Exclusão" };

function textoDoCampo(campo: string, valor: unknown): string {
  if (campo.startsWith("valor_")) return formatarReal(Number(valor));
  if (campo.startsWith("data_")) return formatarData(String(valor));
  if (campo === "situacao")
    return rotulosSituacaoLiberacao[String(valor)] ?? rotulosSituacaoMedicao[String(valor)] ?? String(valor);
  if (campo === "etapa") return rotulosEtapa[String(valor)] ?? String(valor);
  return String(valor);
}

// Resume a alteração pelo que o gestor procura: situação, valores e fonte. Nada de JSON cru na tela.
function resumoAlteracao(alteracao: AlteracaoRegistro): string {
  const depois = alteracao.depois ?? {};
  const antes = alteracao.antes ?? {};
  const partes: string[] = [];
  for (const campo of [
    "situacao",
    "etapa",
    "valor_previsto",
    "valor_recebido",
    "data_prevista",
    "valor_contratado",
    "valor_elegivel",
  ]) {
    if (depois[campo] === undefined || depois[campo] === null) continue;
    if (alteracao.operacao === "update" && antes[campo] === depois[campo]) continue;
    const anterior =
      alteracao.operacao === "update" && antes[campo] !== undefined && antes[campo] !== null
        ? `${textoDoCampo(campo, antes[campo])} para `
        : "";
    partes.push(`${campo.replace(/_/g, " ")}: ${anterior}${textoDoCampo(campo, depois[campo])}`);
  }
  if (typeof depois.fonte === "string") partes.push(`fonte: ${depois.fonte}`);
  return partes.join("; ");
}

function Historico({ alteracoes, usuarioId }: { alteracoes: AlteracaoRegistro[]; usuarioId: string }) {
  if (alteracoes.length === 0) return <p>{mensagensPlanejamento.financiamento.semHistorico}</p>;
  return (
    <ol className="flex flex-col gap-2 text-sm">
      {alteracoes.map((alteracao) => (
        <li key={alteracao.id} className="rounded-lg border border-borda p-3">
          <p className="font-semibold">
            {rotulosOperacao[alteracao.operacao] ?? alteracao.operacao} de{" "}
            {(rotulosTabela[alteracao.tabela] ?? "registro").toLowerCase()}
          </p>
          <p className="text-suave">
            {formatarData(alteracao.alterado_em)} às {horaEmSaoPaulo(alteracao.alterado_em)}, por{" "}
            {alteracao.autor === null
              ? "carga automática"
              : alteracao.autor === usuarioId
                ? "você"
                : "outro usuário da construtora"}
          </p>
          {resumoAlteracao(alteracao) && <p>{resumoAlteracao(alteracao)}</p>}
        </li>
      ))}
    </ol>
  );
}

export default async function PaginaFinanciamento({ searchParams }: PageProps<"/planejamento/financiamento">) {
  const filtros = await searchParams;
  const [referencia, centros] = await Promise.all([carregarReferencia(), tentarConsulta(listarCentrosCusto())]);
  const obras = (centros ?? []).filter((centro) => centro.tipo === "obra");
  const nomes = Object.fromEntries(obras.map((obra) => [obra.id, obra.nome]));
  const centroPedido = lerIdCentro(filtros.obra);
  const obra = obras.find((item) => item.id === centroPedido) ?? null;
  const naoEncontrada = centroPedido !== null && centros !== null && !obra;
  const centroId = obra?.id ?? null;

  const [operacoes, contratos, liberacoes, medicoes, historico, identidade] = await Promise.all([
    tentarConsulta(listarSaldoOperacoes(centroId)),
    centroId ? tentarConsulta(listarFinanciamentoContratos(centroId)) : Promise.resolve(null),
    tentarConsulta(listarLiberacoes({ centroCustoId: centroId })),
    centroId ? tentarConsulta(listarMedicoes(centroId)) : Promise.resolve(null),
    centroId ? tentarConsulta(listarHistoricoComplemento(centroId)) : Promise.resolve(null),
    exigirIdentidade(),
  ]);
  const bancos = Object.fromEntries(
    (operacoes ?? []).map((operacao) => [operacao.operacao_credito_id, operacao.instituicao]),
  );

  return (
    <>
      <header className="flex flex-col gap-2">
        {obra && (
          <Link
            href={`/planejamento?obra=${obra.id}`}
            className="text-sm text-suave underline underline-offset-4 hover:text-texto"
          >
            Planejamento da {obra.nome}
          </Link>
        )}
        <h1 className="font-serif text-[34px] font-semibold">Financiamento e medições</h1>
        <p className="max-w-3xl text-suave">{mensagensPlanejamento.financiamento.complementoManual}</p>
        <AvisoCarga referencia={referencia} />
      </header>

      <form
        action="/planejamento/financiamento"
        method="get"
        aria-label="Escolher obra"
        className="flex flex-col gap-3 rounded-xl border border-borda bg-superficie p-4 sm:flex-row sm:items-end"
      >
        <div className="flex min-w-0 flex-1 flex-col gap-1.5">
          <label htmlFor="financiamento-obra" className="text-sm font-medium">
            Obra
          </label>
          <select
            id="financiamento-obra"
            name="obra"
            defaultValue={obra?.id ?? ""}
            className="min-h-11 w-full rounded-lg border border-borda bg-superficie px-3"
          >
            <option value="">Todas as obras liberadas</option>
            {obras.map((item) => (
              <option key={item.id} value={item.id}>
                {item.nome}
              </option>
            ))}
          </select>
        </div>
        <button
          type="submit"
          className="min-h-11 cursor-pointer rounded-lg bg-menu px-4 font-semibold text-menu-texto hover:bg-menu-ativo"
        >
          Mostrar
        </button>
      </form>

      {naoEncontrada && <p role="alert">{mensagens.obra.naoEncontrada}</p>}
      {!obra && (
        <p className="text-sm text-suave">
          Escolha uma obra para ver contratos, medições, histórico e cadastrar informações.
        </p>
      )}

      <Aviso titulo="Sem rateio por unidade">
        {mensagensPlanejamento.financiamento.semRateio} {mensagensPlanejamento.financiamento.medicaoNaoECaixa}
      </Aviso>

      <Bloco
        id="operacoes"
        titulo="Crédito à produção e outras operações"
        contexto={`Posição em ${formatarData(referencia.dataReferencia)}. Complemento manual.`}
      >
        {operacoes === null && <ErroBloco />}
        {operacoes?.length === 0 && <p>{mensagensPlanejamento.financiamento.semOperacoes}</p>}
        {operacoes && operacoes.length > 0 && <TabelaOperacoes operacoes={operacoes} nomes={nomes} />}
        {obra && <FormularioOperacao acao={registrarOperacao} obraId={obra.id} />}
      </Bloco>

      {obra && (
        <Bloco
          id="contratos"
          titulo="Financiamento dos compradores"
          contexto="Contratos ativos com financiamento. Dinheiro vem da parcela de financiamento da origem; a etapa só classifica prazo e elegibilidade."
        >
          {contratos === null && <ErroBloco />}
          {contratos?.length === 0 && <p>{mensagensPlanejamento.financiamento.semContratos}</p>}
          {contratos && contratos.length > 0 && <TabelaContratos contratos={contratos} />}
          <FormularioEtapa
            acao={registrarEtapa}
            obraId={obra.id}
            contratos={(contratos ?? []).map((contrato) => ({
              valor: String(contrato.contrato_id_origem),
              rotulo: `${contrato.contrato_numero ?? contrato.contrato_id_origem}${contrato.unidade ? `, unidade ${contrato.unidade}` : ""}`,
            }))}
          />
        </Bloco>
      )}

      {obra && (
        <Bloco id="medicoes" titulo="Medições do banco" contexto={mensagensPlanejamento.financiamento.medicaoNaoECaixa}>
          {medicoes === null && <ErroBloco />}
          {medicoes?.length === 0 && <p>{mensagensPlanejamento.financiamento.semMedicoes}</p>}
          {medicoes && medicoes.length > 0 && <TabelaMedicoes medicoes={medicoes} bancos={bancos} />}
          <FormularioMedicao
            acao={registrarMedicao}
            obraId={obra.id}
            operacoes={(operacoes ?? []).map((operacao) => ({
              valor: operacao.operacao_credito_id,
              rotulo: operacao.instituicao,
            }))}
          />
        </Bloco>
      )}

      <Bloco id="liberacoes" titulo="Liberações" contexto="Previstas, recebidas, pendentes e canceladas, com o motivo.">
        {liberacoes === null && <ErroBloco />}
        {liberacoes?.length === 0 && <p>{mensagensPlanejamento.financiamento.semLiberacoes}</p>}
        {liberacoes && liberacoes.length > 0 && <TabelaLiberacoes liberacoes={liberacoes} bancos={bancos} />}
        {obra && (
          <>
            <FormularioLiberacao
              acao={registrarLiberacao}
              obraId={obra.id}
              operacoes={(operacoes ?? []).map((operacao) => ({
                valor: operacao.operacao_credito_id,
                rotulo: operacao.instituicao,
              }))}
              contratos={(contratos ?? []).map((contrato) => ({
                valor: String(contrato.contrato_id_origem),
                rotulo: contrato.contrato_numero ?? String(contrato.contrato_id_origem),
              }))}
              medicoes={(medicoes ?? []).map((medicao) => ({
                valor: medicao.id,
                rotulo: `Nº ${medicao.numero}, ${bancos[medicao.operacao_credito_id] ?? ""}`,
              }))}
            />
            <FormularioAtualizarLiberacao
              acao={atualizarLiberacao}
              obraId={obra.id}
              liberacoes={(liberacoes ?? []).map((liberacao) => ({
                valor: liberacao.id,
                rotulo: `${descricaoLiberacao(liberacao, bancos)}, ${formatarData(liberacao.data_prevista)}, ${rotulosSituacaoLiberacao[liberacao.situacao_efetiva]}`,
              }))}
            />
          </>
        )}
      </Bloco>

      {obra && (
        <Bloco
          id="historico"
          titulo="Histórico das alterações"
          contexto="Últimas 30 alterações de complemento manual desta obra. Visível para diretor e financeiro."
        >
          {historico === null ? <ErroBloco /> : <Historico alteracoes={historico} usuarioId={identidade.usuarioId} />}
          <p className="text-sm text-suave">
            <Inteiro valor={historico?.length ?? 0} /> registros mostrados.
          </p>
        </Bloco>
      )}
    </>
  );
}
