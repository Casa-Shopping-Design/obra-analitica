// Validação dos formulários de complemento manual de financiamento (operação, etapa, medição e
// liberação), feita no servidor antes de gravar. O banco confere tudo de novo (checks e gatilhos da 0012).
import { lerData } from "../../lib/periodo";
import {
  ehUuid,
  fracaoDeMilionesimos,
  lerInteiroNaoNegativo,
  lerReais,
  lerTexto,
  limitesPlanejamento,
  milionesimosDePercentual,
  type ErrosCampos,
  type LerCampo,
} from "./regras-planejamento";

export const modalidadesCredito = ["credito_producao", "plano_empresario", "credito_associativo", "outra"] as const;
export const etapasFinanciamento = ["contratacao", "aprovacao", "elegivel", "liberado"] as const;
export const situacoesMedicao = ["apresentada", "aprovada", "reprovada"] as const;
export const niveisLiberacao = ["contrato", "empreendimento", "lote"] as const;
export const situacoesLiberacao = ["prevista", "pendente", "recebida", "cancelada"] as const;
export const vinculosLiberacao = ["recebimento", "lancamento_manual"] as const;

type Resultado<T> = { ok: true; dados: T } | { ok: false; erros: ErrosCampos };

function escolha<T extends string>(texto: string, opcoes: readonly T[]): T | null {
  return opcoes.find((opcao) => opcao === texto) ?? null;
}

// Data dentro de um intervalo plausível; o resto é digitação errada.
function lerDataPlausivel(texto: string): string | null {
  const data = lerData(texto);
  if (!data || data < "2000-01-01" || data > "2100-12-31") return null;
  return data;
}

type Fonte = { fonte: string; referencia_documento: string | null };

function lerFonte(ler: LerCampo, erros: ErrosCampos): Fonte {
  const fonte = lerTexto(ler("fonte"), limitesPlanejamento.textoCurto, true);
  if (!fonte) erros.fonte = "Informe a fonte (por exemplo: RAE, contrato com o banco, extrato), em até 200 caracteres.";
  const referencia = lerTexto(ler("referencia_documento"), limitesPlanejamento.textoCurto, false);
  if (referencia === undefined) erros.referencia_documento = "Use até 200 caracteres.";
  return { fonte: fonte ?? "", referencia_documento: referencia ?? null };
}

export type DadosOperacao = Fonte & {
  modalidade: (typeof modalidadesCredito)[number];
  instituicao: string;
  numero_contrato: string | null;
  valor_contratado: number;
  percentual_retencao: number | null;
  data_contratacao: string | null;
  observacao: string | null;
};

export function validarOperacao(ler: LerCampo): Resultado<DadosOperacao> {
  const erros: ErrosCampos = {};
  const modalidade = escolha(ler("modalidade"), modalidadesCredito);
  if (!modalidade) erros.modalidade = "Escolha a modalidade.";
  const instituicao = lerTexto(ler("instituicao"), 120, true);
  if (!instituicao) erros.instituicao = "Informe o banco, em até 120 caracteres.";
  const numeroContrato = lerTexto(ler("numero_contrato"), 60, false);
  if (numeroContrato === undefined) erros.numero_contrato = "Use até 60 caracteres.";
  const valor = lerReais(ler("valor_contratado"));
  if (valor === null || valor <= 0) erros.valor_contratado = "Informe o valor contratado em reais, maior que zero.";
  const retencaoTexto = ler("percentual_retencao");
  const retencao = retencaoTexto === "" ? null : milionesimosDePercentual(retencaoTexto);
  if (retencaoTexto !== "" && retencao === null) erros.percentual_retencao = "Informe um percentual de 0% a 100%.";
  const dataTexto = ler("data_contratacao");
  const dataContratacao = dataTexto === "" ? null : lerDataPlausivel(dataTexto);
  if (dataTexto !== "" && !dataContratacao) erros.data_contratacao = "Informe uma data válida.";
  const observacao = lerTexto(ler("observacao"), limitesPlanejamento.textoLongo, false);
  if (observacao === undefined) erros.observacao = "Use até 1.000 caracteres.";
  const fonte = lerFonte(ler, erros);
  if (Object.keys(erros).length > 0) return { ok: false, erros };
  return {
    ok: true,
    dados: {
      modalidade: modalidade as DadosOperacao["modalidade"],
      instituicao: instituicao as string,
      numero_contrato: numeroContrato ?? null,
      valor_contratado: valor as number,
      percentual_retencao: retencao === null ? null : fracaoDeMilionesimos(retencao),
      data_contratacao: dataContratacao,
      observacao: observacao ?? null,
      ...fonte,
    },
  };
}

export type DadosEtapa = Fonte & {
  contrato_id_origem: number;
  etapa: (typeof etapasFinanciamento)[number];
  pendencia: boolean;
  motivo_pendencia: string | null;
  data_etapa: string;
  data_prevista_liberacao: string | null;
  observacao: string | null;
};

// contratosDaObra: os contratos com financiamento que a tela listou para a obra; outro número é recusado.
export function validarEtapa(ler: LerCampo, contratosDaObra: ReadonlySet<number>): Resultado<DadosEtapa> {
  const erros: ErrosCampos = {};
  const contrato = lerInteiroNaoNegativo(ler("contrato_id_origem"), 2_147_483_647);
  if (contrato === null || !contratosDaObra.has(contrato)) erros.contrato_id_origem = "Escolha um contrato da lista.";
  const etapa = escolha(ler("etapa"), etapasFinanciamento);
  if (!etapa) erros.etapa = "Escolha a etapa.";
  const pendencia = ler("pendencia") === "sim";
  const motivo = lerTexto(ler("motivo_pendencia"), limitesPlanejamento.textoCurto, pendencia);
  if (pendencia && !motivo) erros.motivo_pendencia = "Com pendência, informe o motivo.";
  if (motivo === undefined && !pendencia) erros.motivo_pendencia = "Use até 200 caracteres.";
  const dataEtapa = lerDataPlausivel(ler("data_etapa"));
  if (!dataEtapa) erros.data_etapa = "Informe a data da etapa.";
  const previstaTexto = ler("data_prevista_liberacao");
  const prevista = previstaTexto === "" ? null : lerDataPlausivel(previstaTexto);
  if (previstaTexto !== "" && !prevista) erros.data_prevista_liberacao = "Informe uma data válida.";
  const observacao = lerTexto(ler("observacao"), limitesPlanejamento.textoLongo, false);
  if (observacao === undefined) erros.observacao = "Use até 1.000 caracteres.";
  const fonte = lerFonte(ler, erros);
  if (Object.keys(erros).length > 0) return { ok: false, erros };
  return {
    ok: true,
    dados: {
      contrato_id_origem: contrato as number,
      etapa: etapa as DadosEtapa["etapa"],
      pendencia,
      motivo_pendencia: pendencia ? (motivo as string) : null,
      data_etapa: dataEtapa as string,
      data_prevista_liberacao: prevista,
      observacao: observacao ?? null,
      ...fonte,
    },
  };
}

export type DadosMedicao = Fonte & {
  operacao_credito_id: string;
  numero: number;
  data_vistoria: string;
  avanco_fisico_informado: number;
  data_apresentacao: string | null;
  situacao: (typeof situacoesMedicao)[number];
  data_aprovacao: string | null;
  valor_medido: number | null;
  valor_elegivel: number | null;
  valor_retido: number | null;
};

export function validarMedicao(ler: LerCampo, operacoesDaObra: ReadonlySet<string>): Resultado<DadosMedicao> {
  const erros: ErrosCampos = {};
  const operacao = ler("operacao_credito_id");
  if (!ehUuid(operacao) || !operacoesDaObra.has(operacao)) erros.operacao_credito_id = "Escolha a operação de crédito.";
  const numero = lerInteiroNaoNegativo(ler("numero"), 10_000);
  if (numero === null || numero < 1) erros.numero = "Informe o número da medição (1, 2, 3...).";
  const vistoria = lerDataPlausivel(ler("data_vistoria"));
  if (!vistoria) erros.data_vistoria = "Informe a data da vistoria.";
  const avanco = milionesimosDePercentual(ler("avanco_fisico_informado"));
  if (avanco === null) erros.avanco_fisico_informado = "Informe o avanço acumulado de 0% a 100%.";
  const apresentacaoTexto = ler("data_apresentacao");
  const apresentacao = apresentacaoTexto === "" ? null : lerDataPlausivel(apresentacaoTexto);
  if (apresentacaoTexto !== "" && !apresentacao) erros.data_apresentacao = "Informe uma data válida.";
  const situacao = escolha(ler("situacao"), situacoesMedicao);
  if (!situacao) erros.situacao = "Escolha a situação.";
  const aprovacaoTexto = ler("data_aprovacao");
  const aprovacao = aprovacaoTexto === "" ? null : lerDataPlausivel(aprovacaoTexto);
  if (aprovacaoTexto !== "" && !aprovacao) erros.data_aprovacao = "Informe uma data válida.";
  if (situacao === "aprovada" && !aprovacao) erros.data_aprovacao = "Medição aprovada precisa da data de aprovação.";
  const valores = (["valor_medido", "valor_elegivel", "valor_retido"] as const).map((campo) => {
    const texto = ler(campo);
    const valor = texto === "" ? null : lerReais(texto);
    if (texto !== "" && valor === null) erros[campo] = "Informe o valor em reais.";
    return valor;
  });
  const fonte = lerFonte(ler, erros);
  if (Object.keys(erros).length > 0) return { ok: false, erros };
  return {
    ok: true,
    dados: {
      operacao_credito_id: operacao,
      numero: numero as number,
      data_vistoria: vistoria as string,
      avanco_fisico_informado: fracaoDeMilionesimos(avanco as number),
      data_apresentacao: apresentacao,
      situacao: situacao as DadosMedicao["situacao"],
      data_aprovacao: aprovacao,
      valor_medido: valores[0],
      valor_elegivel: valores[1],
      valor_retido: valores[2],
      ...fonte,
    },
  };
}

export type DadosLiberacao = Fonte & {
  nivel: (typeof niveisLiberacao)[number];
  operacao_credito_id: string | null;
  contrato_id_origem: number | null;
  medicao_id: string | null;
  descricao_lote: string | null;
  valor_previsto: number;
  data_prevista: string;
  situacao: "prevista" | "pendente";
  motivo: string | null;
};

export function validarLiberacao(
  ler: LerCampo,
  permitidos: { operacoes: ReadonlySet<string>; contratos: ReadonlySet<number>; medicoes: ReadonlySet<string> },
): Resultado<DadosLiberacao> {
  const erros: ErrosCampos = {};
  const nivel = escolha(ler("nivel"), niveisLiberacao);
  if (!nivel) erros.nivel = "Escolha o nível da liberação.";
  const operacaoTexto = ler("operacao_credito_id");
  const operacao = operacaoTexto === "" ? null : operacaoTexto;
  const contratoTexto = ler("contrato_id_origem");
  const contrato = contratoTexto === "" ? null : lerInteiroNaoNegativo(contratoTexto, 2_147_483_647);
  if (nivel === "contrato") {
    if (contrato === null || !permitidos.contratos.has(contrato)) erros.contrato_id_origem = "Escolha o contrato do comprador.";
  } else if (nivel) {
    if (!operacao || !ehUuid(operacao) || !permitidos.operacoes.has(operacao)) {
      erros.operacao_credito_id = "Liberação da obra ou de lote precisa da operação de crédito.";
    }
    if (contratoTexto !== "") erros.contrato_id_origem = "Liberação da obra ou de lote não leva contrato de comprador.";
  }
  const medicaoTexto = ler("medicao_id");
  if (medicaoTexto !== "" && (!ehUuid(medicaoTexto) || !permitidos.medicoes.has(medicaoTexto))) {
    erros.medicao_id = "Escolha uma medição da lista ou deixe em branco.";
  }
  const lote = lerTexto(ler("descricao_lote"), 120, nivel === "lote");
  if (nivel === "lote" && !lote) erros.descricao_lote = "Descreva o lote (por exemplo, torre A).";
  const valor = lerReais(ler("valor_previsto"));
  if (valor === null || valor <= 0) erros.valor_previsto = "Informe o valor previsto em reais, maior que zero.";
  const dataPrevista = lerDataPlausivel(ler("data_prevista"));
  if (!dataPrevista) erros.data_prevista = "Informe a data prevista.";
  const situacao = escolha(ler("situacao"), ["prevista", "pendente"] as const);
  if (!situacao) erros.situacao = "Escolha prevista ou pendente.";
  const motivo = lerTexto(ler("motivo"), limitesPlanejamento.textoCurto, situacao === "pendente");
  if (situacao === "pendente" && !motivo) erros.motivo = "Liberação pendente precisa do motivo.";
  const fonte = lerFonte(ler, erros);
  if (Object.keys(erros).length > 0) return { ok: false, erros };
  return {
    ok: true,
    dados: {
      nivel: nivel as DadosLiberacao["nivel"],
      operacao_credito_id: nivel === "contrato" ? (operacao && ehUuid(operacao) && permitidos.operacoes.has(operacao) ? operacao : null) : operacao,
      contrato_id_origem: nivel === "contrato" ? contrato : null,
      medicao_id: medicaoTexto === "" ? null : medicaoTexto,
      descricao_lote: nivel === "lote" ? (lote as string) : null,
      valor_previsto: valor as number,
      data_prevista: dataPrevista as string,
      situacao: situacao as DadosLiberacao["situacao"],
      motivo: motivo ?? null,
      ...fonte,
    },
  };
}

export type DadosAtualizacaoLiberacao = Fonte & {
  id: string;
  situacao: (typeof situacoesLiberacao)[number];
  motivo: string | null;
  valor_recebido: number | null;
  data_recebimento: string | null;
  vinculo_tipo: (typeof vinculosLiberacao)[number] | null;
  vinculo_chave: string | null;
};

// Recebimento só com data até a de referência, valor e vínculo único (seção 3.3.4).
export function validarAtualizacaoLiberacao(
  ler: LerCampo,
  liberacoesDaObra: ReadonlySet<string>,
  dataReferencia: string,
): Resultado<DadosAtualizacaoLiberacao> {
  const erros: ErrosCampos = {};
  const id = ler("id");
  if (!ehUuid(id) || !liberacoesDaObra.has(id)) erros.id = "Escolha a liberação da lista.";
  const situacao = escolha(ler("situacao"), situacoesLiberacao);
  if (!situacao) erros.situacao = "Escolha a nova situação.";
  const exigeMotivo = situacao === "pendente" || situacao === "cancelada";
  const motivo = lerTexto(ler("motivo"), limitesPlanejamento.textoCurto, exigeMotivo);
  if (exigeMotivo && !motivo) erros.motivo = "Informe o motivo da pendência ou do cancelamento.";
  let valorRecebido: number | null = null;
  let dataRecebimento: string | null = null;
  let vinculoTipo: DadosAtualizacaoLiberacao["vinculo_tipo"] = null;
  let vinculoChave: string | null = null;
  if (situacao === "recebida") {
    valorRecebido = lerReais(ler("valor_recebido"));
    if (valorRecebido === null || valorRecebido <= 0) erros.valor_recebido = "Informe o valor recebido em reais.";
    dataRecebimento = lerDataPlausivel(ler("data_recebimento"));
    if (!dataRecebimento || dataRecebimento > dataReferencia) {
      erros.data_recebimento = "Informe a data do recebimento, até a data de referência.";
    }
    vinculoTipo = escolha(ler("vinculo_tipo"), vinculosLiberacao);
    if (!vinculoTipo) erros.vinculo_tipo = "Diga se o dinheiro já está nos recebimentos da origem ou só no extrato.";
    vinculoChave = lerTexto(ler("vinculo_chave"), 120, true) ?? null;
    if (!vinculoChave) {
      erros.vinculo_chave = "Informe o identificador do recebimento ou do lançamento no extrato.";
    } else if (vinculoTipo === "recebimento" && !/^\d+\|\d+\|\d+$/.test(vinculoChave)) {
      erros.vinculo_chave = "Para recebimento da origem use contrato|parcela|sequência, como 5001|12|1.";
    }
  }
  const fonte = lerFonte(ler, erros);
  if (Object.keys(erros).length > 0) return { ok: false, erros };
  return {
    ok: true,
    dados: {
      id,
      situacao: situacao as DadosAtualizacaoLiberacao["situacao"],
      motivo: motivo ?? null,
      valor_recebido: valorRecebido,
      data_recebimento: dataRecebimento,
      vinculo_tipo: vinculoTipo,
      vinculo_chave: vinculoChave,
      ...fonte,
    },
  };
}
