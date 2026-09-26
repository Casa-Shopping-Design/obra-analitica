"use client";

import { useActionState } from "react";
import { BotaoAcao, CampoAcao, MensagemAcao } from "@/componentes/planejamento/CamposAcao";
import { estadoInicial, type EstadoAcao } from "@/componentes/planejamento/estado-acao";
import type { AcaoFormulario } from "@/componentes/planejamento/FormulariosPlanejamento";
import {
  rotulosEtapa,
  rotulosModalidade,
  rotulosNivelLiberacao,
  rotulosSituacaoLiberacao,
  rotulosSituacaoMedicao,
} from "@/lib/mensagens-planejamento";

type Opcao = { valor: string; rotulo: string };

const opcoesDe = (rotulos: Record<string, string>, vazio?: string): Opcao[] => [
  ...(vazio !== undefined ? [{ valor: "", rotulo: vazio }] : []),
  ...Object.entries(rotulos).map(([valor, rotulo]) => ({ valor, rotulo })),
];

function CamposFonte({ prefixo, estado }: { prefixo: string; estado: EstadoAcao }) {
  return (
    <>
      <CampoAcao
        prefixo={prefixo}
        nome="fonte"
        rotulo="Fonte da informação"
        estado={estado}
        obrigatorio
        ajuda="Por exemplo: RAE, contrato com o banco, extrato, e-mail do gerente."
      />
      <CampoAcao prefixo={prefixo} nome="referencia_documento" rotulo="Número do documento" estado={estado} />
    </>
  );
}

function Moldura({
  titulo,
  acao,
  obraId,
  textoBotao,
  children,
}: {
  titulo: string;
  acao: AcaoFormulario;
  obraId: string;
  textoBotao: string;
  children: (estado: EstadoAcao) => React.ReactNode;
}) {
  const [estado, enviar, enviando] = useActionState(acao, estadoInicial);
  return (
    <details className="rounded-xl border border-borda bg-superficie p-4 open:pb-5">
      <summary className="min-h-11 cursor-pointer content-center font-semibold">{titulo}</summary>
      <form action={enviar} className="mt-3 flex flex-col gap-3" aria-label={titulo} noValidate>
        <input type="hidden" name="obra" value={obraId} />
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">{children(estado)}</div>
        <BotaoAcao enviando={enviando} texto={textoBotao} textoEnviando="Registrando..." />
        <MensagemAcao estado={estado} />
      </form>
    </details>
  );
}

export function FormularioOperacao({ acao, obraId }: { acao: AcaoFormulario; obraId: string }) {
  return (
    <Moldura titulo="Cadastrar operação de crédito" acao={acao} obraId={obraId} textoBotao="Registrar operação">
      {(estado) => (
        <>
          <CampoAcao prefixo="operacao" nome="modalidade" rotulo="Modalidade" estado={estado} opcoes={opcoesDe(rotulosModalidade, "Escolha")} obrigatorio />
          <CampoAcao prefixo="operacao" nome="instituicao" rotulo="Banco" estado={estado} obrigatorio />
          <CampoAcao prefixo="operacao" nome="numero_contrato" rotulo="Número do contrato" estado={estado} />
          <CampoAcao prefixo="operacao" nome="valor_contratado" rotulo="Valor contratado (R$)" tipo="decimal" estado={estado} obrigatorio />
          <CampoAcao
            prefixo="operacao"
            nome="percentual_retencao"
            rotulo="Retenção até o habite-se (%)"
            tipo="decimal"
            estado={estado}
            ajuda="Como está no contrato com o banco. Em branco quando não se sabe."
          />
          <CampoAcao prefixo="operacao" nome="data_contratacao" rotulo="Data da contratação" tipo="date" estado={estado} />
          <CampoAcao prefixo="operacao" nome="observacao" rotulo="Observação" tipo="textarea" estado={estado} />
          <CamposFonte prefixo="operacao" estado={estado} />
        </>
      )}
    </Moldura>
  );
}

export function FormularioEtapa({ acao, obraId, contratos }: { acao: AcaoFormulario; obraId: string; contratos: Opcao[] }) {
  return (
    <Moldura titulo="Registrar etapa do financiamento de um contrato" acao={acao} obraId={obraId} textoBotao="Registrar etapa">
      {(estado) => (
        <>
          <CampoAcao prefixo="etapa" nome="contrato_id_origem" rotulo="Contrato" estado={estado} opcoes={[{ valor: "", rotulo: "Escolha" }, ...contratos]} obrigatorio />
          <CampoAcao prefixo="etapa" nome="etapa" rotulo="Etapa no banco" estado={estado} opcoes={opcoesDe(rotulosEtapa, "Escolha")} obrigatorio />
          <CampoAcao prefixo="etapa" nome="data_etapa" rotulo="Data da etapa" tipo="date" estado={estado} obrigatorio />
          <CampoAcao prefixo="etapa" nome="pendencia" rotulo="Tem pendência" tipo="checkbox" estado={estado} />
          <CampoAcao prefixo="etapa" nome="motivo_pendencia" rotulo="Motivo da pendência" estado={estado} ajuda="Obrigatório quando há pendência." />
          <CampoAcao prefixo="etapa" nome="data_prevista_liberacao" rotulo="Liberação prevista para" tipo="date" estado={estado} />
          <CampoAcao prefixo="etapa" nome="observacao" rotulo="Observação" tipo="textarea" estado={estado} />
          <CamposFonte prefixo="etapa" estado={estado} />
        </>
      )}
    </Moldura>
  );
}

export function FormularioMedicao({ acao, obraId, operacoes }: { acao: AcaoFormulario; obraId: string; operacoes: Opcao[] }) {
  return (
    <Moldura titulo="Registrar medição do banco" acao={acao} obraId={obraId} textoBotao="Registrar medição">
      {(estado) => (
        <>
          <CampoAcao prefixo="medicao" nome="operacao_credito_id" rotulo="Operação de crédito" estado={estado} opcoes={[{ valor: "", rotulo: "Escolha" }, ...operacoes]} obrigatorio />
          <CampoAcao prefixo="medicao" nome="numero" rotulo="Número da medição" tipo="decimal" estado={estado} obrigatorio />
          <CampoAcao prefixo="medicao" nome="data_vistoria" rotulo="Data da vistoria" tipo="date" estado={estado} obrigatorio />
          <CampoAcao prefixo="medicao" nome="avanco_fisico_informado" rotulo="Avanço acumulado informado (%)" tipo="decimal" estado={estado} obrigatorio />
          <CampoAcao prefixo="medicao" nome="data_apresentacao" rotulo="Data de apresentação" tipo="date" estado={estado} />
          <CampoAcao prefixo="medicao" nome="situacao" rotulo="Situação" estado={estado} opcoes={opcoesDe(rotulosSituacaoMedicao, "Escolha")} obrigatorio />
          <CampoAcao prefixo="medicao" nome="data_aprovacao" rotulo="Data de aprovação" tipo="date" estado={estado} ajuda="Obrigatória quando aprovada." />
          <CampoAcao prefixo="medicao" nome="valor_medido" rotulo="Valor medido (R$)" tipo="decimal" estado={estado} />
          <CampoAcao prefixo="medicao" nome="valor_elegivel" rotulo="Valor elegível (R$)" tipo="decimal" estado={estado} />
          <CampoAcao prefixo="medicao" nome="valor_retido" rotulo="Valor retido (R$)" tipo="decimal" estado={estado} />
          <CamposFonte prefixo="medicao" estado={estado} />
        </>
      )}
    </Moldura>
  );
}

export function FormularioLiberacao({
  acao,
  obraId,
  operacoes,
  contratos,
  medicoes,
}: {
  acao: AcaoFormulario;
  obraId: string;
  operacoes: Opcao[];
  contratos: Opcao[];
  medicoes: Opcao[];
}) {
  return (
    <Moldura titulo="Cadastrar liberação prevista" acao={acao} obraId={obraId} textoBotao="Registrar liberação">
      {(estado) => (
        <>
          <CampoAcao prefixo="liberacao" nome="nivel" rotulo="Nível" estado={estado} opcoes={opcoesDe(rotulosNivelLiberacao, "Escolha")} obrigatorio />
          <CampoAcao
            prefixo="liberacao"
            nome="operacao_credito_id"
            rotulo="Operação de crédito"
            estado={estado}
            opcoes={[{ valor: "", rotulo: "Nenhuma" }, ...operacoes]}
            ajuda="Obrigatória para obra inteira e lote."
          />
          <CampoAcao
            prefixo="liberacao"
            nome="contrato_id_origem"
            rotulo="Contrato do comprador"
            estado={estado}
            opcoes={[{ valor: "", rotulo: "Nenhum" }, ...contratos]}
            ajuda="Só para liberação de contrato."
          />
          <CampoAcao prefixo="liberacao" nome="descricao_lote" rotulo="Lote" estado={estado} ajuda="Só para liberação de lote." />
          <CampoAcao prefixo="liberacao" nome="medicao_id" rotulo="Medição que originou" estado={estado} opcoes={[{ valor: "", rotulo: "Nenhuma" }, ...medicoes]} />
          <CampoAcao prefixo="liberacao" nome="valor_previsto" rotulo="Valor previsto (R$)" tipo="decimal" estado={estado} obrigatorio />
          <CampoAcao prefixo="liberacao" nome="data_prevista" rotulo="Data prevista" tipo="date" estado={estado} obrigatorio />
          <CampoAcao
            prefixo="liberacao"
            nome="situacao"
            rotulo="Situação"
            estado={estado}
            padrao="prevista"
            opcoes={[
              { valor: "prevista", rotulo: rotulosSituacaoLiberacao.prevista },
              { valor: "pendente", rotulo: rotulosSituacaoLiberacao.pendente },
            ]}
          />
          <CampoAcao prefixo="liberacao" nome="motivo" rotulo="Motivo" estado={estado} ajuda="Obrigatório quando pendente." />
          <CamposFonte prefixo="liberacao" estado={estado} />
        </>
      )}
    </Moldura>
  );
}

export function FormularioAtualizarLiberacao({
  acao,
  obraId,
  liberacoes,
}: {
  acao: AcaoFormulario;
  obraId: string;
  liberacoes: Opcao[];
}) {
  return (
    <Moldura titulo="Atualizar situação de uma liberação" acao={acao} obraId={obraId} textoBotao="Atualizar liberação">
      {(estado) => (
        <>
          <CampoAcao prefixo="atualizar" nome="id" rotulo="Liberação" estado={estado} opcoes={[{ valor: "", rotulo: "Escolha" }, ...liberacoes]} obrigatorio />
          <CampoAcao prefixo="atualizar" nome="situacao" rotulo="Nova situação" estado={estado} opcoes={opcoesDe({ prevista: "Prevista", pendente: "Pendente", recebida: "Recebida", cancelada: "Cancelada" }, "Escolha")} obrigatorio />
          <CampoAcao prefixo="atualizar" nome="motivo" rotulo="Motivo" estado={estado} ajuda="Obrigatório em pendente e cancelada." />
          <CampoAcao prefixo="atualizar" nome="valor_recebido" rotulo="Valor recebido (R$)" tipo="decimal" estado={estado} ajuda="Só quando recebida." />
          <CampoAcao prefixo="atualizar" nome="data_recebimento" rotulo="Data do recebimento" tipo="date" estado={estado} />
          <CampoAcao
            prefixo="atualizar"
            nome="vinculo_tipo"
            rotulo="Onde o dinheiro aparece"
            estado={estado}
            opcoes={[
              { valor: "", rotulo: "Escolha" },
              { valor: "recebimento", rotulo: "Já está nos recebimentos da origem" },
              { valor: "lancamento_manual", rotulo: "Só no extrato (não está na origem)" },
            ]}
            ajuda="Dinheiro que já está na origem não soma de novo no caixa."
          />
          <CampoAcao
            prefixo="atualizar"
            nome="vinculo_chave"
            rotulo="Identificador do recebimento ou do extrato"
            estado={estado}
            ajuda="Recebimento da origem: contrato|parcela|sequência. Extrato: o identificador do lançamento."
          />
          <CamposFonte prefixo="atualizar" estado={estado} />
        </>
      )}
    </Moldura>
  );
}
