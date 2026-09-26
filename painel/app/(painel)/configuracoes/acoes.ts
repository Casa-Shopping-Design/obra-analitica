"use server";

import type { EstadoAcao } from "@/componentes/planejamento/estado-acao";
import {
  codigosComposicao,
  leitorDoFormulario,
  mensagensConfiguracao,
  validarComposicao,
  validarMapaCodigo,
  validarObservacao,
  validarRotulo,
  validarSubcategoria,
  validarValorParametro,
  type Parametro,
  type ValorCodigoOrigem,
} from "@/lib/configuracao";
import { listarCatalogo, objetoAusente } from "@/lib/consultas/configuracao";
import {
  executarConfiguracao,
  falhaBanco,
  falhaValidacao,
  lerEscopoDoFormulario,
  sucesso,
  type ContextoConfiguracao,
} from "./gravacao";

// Cada ação confere usuário e perfil em executarConfiguracao, valida a entrada aqui no servidor a partir do
// catálogo e grava com o JWT do usuário. Autor e auditoria são gravados pelos gatilhos do banco.

const ehComposicao = (codigo: string) => (codigosComposicao as readonly string[]).includes(codigo);

async function parametroDoCatalogo(codigo: string): Promise<Parametro | null> {
  const catalogo = await listarCatalogo();
  return catalogo.find((parametro) => parametro.codigo === codigo) ?? null;
}

// Confirmação e observação para parâmetro que exige validação do financeiro.
function conferirValidacaoFinanceira(
  parametros: Parametro[],
  valores: Record<string, string>,
): { ok: true; observacao: string | null } | { ok: false; erros: Record<string, string> } {
  const exige = parametros.some((parametro) => parametro.exige_validacao_financeira);
  const erros: Record<string, string> = {};
  const observacao = validarObservacao(valores.observacao, exige);
  if (!observacao.ok) erros.observacao = observacao.erro;
  if (exige && valores.confirmacao !== "sim") erros.confirmacao = mensagensConfiguracao.confirmeValidacao;
  if (Object.keys(erros).length > 0 || !observacao.ok) return { ok: false, erros };
  return { ok: true, observacao: observacao.observacao };
}

// Id do valor já gravado em cada código no nível escolhido, para a gravação atualizar em vez de duplicar.
async function idsNoNivel(
  contexto: ContextoConfiguracao,
  codigos: string[],
  centroId: string | null,
): Promise<{ ok: true; ids: Map<string, string> } | { ok: false; codigo: string | undefined }> {
  let consulta = contexto.supabase
    .schema("app")
    .from("parametro_valor")
    .select("id, codigo")
    .eq("tenant_id", contexto.tenantId)
    .in("codigo", codigos);
  consulta = centroId ? consulta.eq("centro_custo_id", centroId) : consulta.is("centro_custo_id", null);
  const { data, error } = await consulta;
  if (error) return { ok: false, codigo: error.code };
  return { ok: true, ids: new Map((data ?? []).map((linha) => [linha.codigo as string, linha.id as string])) };
}

// Grava os valores de um nível num único comando (insert com on conflict no id), para o banco conferir
// a soma das frações da simulação com as três já gravadas.
async function gravarValores(
  contexto: ContextoConfiguracao,
  centroId: string | null,
  itens: { codigo: string; valor: string | number | boolean }[],
  observacao: string | null,
): Promise<string | null | undefined> {
  const existentes = await idsNoNivel(
    contexto,
    itens.map((item) => item.codigo),
    centroId,
  );
  if (!existentes.ok) return existentes.codigo ?? "erro";
  const linhas = itens.map((item) => {
    const id = existentes.ids.get(item.codigo);
    return {
      ...(id ? { id } : {}),
      tenant_id: contexto.tenantId,
      centro_custo_id: centroId,
      codigo: item.codigo,
      valor: item.valor,
      observacao,
      autor: contexto.usuarioId,
    };
  });
  const { error } = await contexto.supabase
    .schema("app")
    .from("parametro_valor")
    .upsert(linhas, { onConflict: "id", defaultToNull: false });
  return error ? (error.code ?? "erro") : null;
}

export async function gravarParametro(_estado: EstadoAcao, formulario: FormData): Promise<EstadoAcao> {
  return executarConfiguracao(formulario, async (contexto) => {
    const { valores } = contexto;
    const parametro = await parametroDoCatalogo(valores.codigo ?? "");
    if (!parametro || ehComposicao(parametro.codigo)) {
      return falhaBanco(undefined, valores, mensagensConfiguracao.parametroDesconhecido);
    }
    const escopo = await lerEscopoDoFormulario(contexto);
    if (!escopo.ok) return escopo.estado;
    if (escopo.centroId && parametro.escopo !== "tenant_e_obra") {
      return falhaBanco(undefined, valores, mensagensConfiguracao.soConstrutora);
    }
    const valor = validarValorParametro(parametro, valores.valor);
    const validacao = conferirValidacaoFinanceira([parametro], valores);
    const erros = { ...(valor.ok ? {} : { valor: valor.erro }), ...(validacao.ok ? {} : validacao.erros) };
    if (!valor.ok || !validacao.ok || valor.valor === null) return falhaValidacao(erros, valores);
    const codigo = await gravarValores(
      contexto,
      escopo.centroId,
      [{ codigo: parametro.codigo, valor: valor.valor }],
      validacao.observacao,
    );
    return codigo ? falhaBanco(codigo, valores) : sucesso(mensagensConfiguracao.gravado);
  });
}

// Entrada, parcelas e financiamento da simulação vão juntos: sozinhos, a soma de 100% não fecha.
export async function gravarComposicao(_estado: EstadoAcao, formulario: FormData): Promise<EstadoAcao> {
  return executarConfiguracao(formulario, async (contexto) => {
    const { valores } = contexto;
    const catalogo = await listarCatalogo();
    const parametros = codigosComposicao.map((codigo) => catalogo.find((parametro) => parametro.codigo === codigo));
    if (parametros.some((parametro) => !parametro)) {
      return falhaBanco(undefined, valores, mensagensConfiguracao.parametroDesconhecido);
    }
    const lista = parametros as Parametro[];
    const escopo = await lerEscopoDoFormulario(contexto);
    if (!escopo.ok) return escopo.estado;
    if (escopo.centroId && lista.some((parametro) => parametro.escopo !== "tenant_e_obra")) {
      return falhaBanco(undefined, valores, mensagensConfiguracao.soConstrutora);
    }
    const composicao = validarComposicao(
      lista,
      lista.map((parametro) => valores[parametro.codigo]),
    );
    const validacao = conferirValidacaoFinanceira(lista, valores);
    if (!composicao.ok || !validacao.ok) {
      return falhaValidacao(
        { ...(composicao.ok ? {} : composicao.erros), ...(validacao.ok ? {} : validacao.erros) },
        valores,
      );
    }
    const codigo = await gravarValores(
      contexto,
      escopo.centroId,
      lista.map((parametro, posicao) => ({ codigo: parametro.codigo, valor: composicao.valores[posicao] })),
      validacao.observacao,
    );
    return codigo ? falhaBanco(codigo, valores) : sucesso(mensagensConfiguracao.gravado);
  });
}

// Exclui o valor do nível escolhido; passa a valer o de cima (construtora ou padrão do produto).
export async function voltarAoPadrao(_estado: EstadoAcao, formulario: FormData): Promise<EstadoAcao> {
  return executarConfiguracao(formulario, async (contexto) => {
    const { valores } = contexto;
    const parametro = await parametroDoCatalogo(valores.codigo ?? "");
    if (!parametro) return falhaBanco(undefined, valores, mensagensConfiguracao.parametroDesconhecido);
    const escopo = await lerEscopoDoFormulario(contexto);
    if (!escopo.ok) return escopo.estado;
    if (parametro.exige_validacao_financeira && valores.confirmacao !== "sim") {
      return falhaValidacao({ confirmacao: mensagensConfiguracao.confirmeValidacao }, valores);
    }
    const codigos = ehComposicao(parametro.codigo) ? [...codigosComposicao] : [parametro.codigo];
    let exclusao = contexto.supabase
      .schema("app")
      .from("parametro_valor")
      .delete()
      .eq("tenant_id", contexto.tenantId)
      .in("codigo", codigos);
    exclusao = escopo.centroId ? exclusao.eq("centro_custo_id", escopo.centroId) : exclusao.is("centro_custo_id", null);
    const { data, error } = await exclusao.select("id");
    if (error) return falhaBanco(error.code, valores);
    if (!data || data.length === 0) return falhaBanco(undefined, valores, mensagensConfiguracao.nadaParaVoltar);
    return sucesso(mensagensConfiguracao.voltouPadrao);
  });
}

export async function gravarMapaCodigo(_estado: EstadoAcao, formulario: FormData): Promise<EstadoAcao> {
  return executarConfiguracao(formulario, async (contexto) => {
    const aceitos = await contexto.supabase
      .schema("app")
      .from("valor_codigo_origem")
      .select("dominio, valor, rotulo, ordem, valor_sem_mapa")
      .eq("dominio", contexto.valores.dominio ?? "");
    if (aceitos.error) return falhaBanco(aceitos.error.code, contexto.valores);
    const validacao = validarMapaCodigo(leitorDoFormulario(formulario), (aceitos.data ?? []) as ValorCodigoOrigem[]);
    if (!validacao.ok) return falhaValidacao(validacao.erros, contexto.valores);
    const { error } = await contexto.supabase
      .schema("app")
      .from("mapa_codigo_origem")
      .upsert(
        { tenant_id: contexto.tenantId, ...validacao.dados, autor: contexto.usuarioId },
        { onConflict: "tenant_id,dominio,codigo_origem" },
      );
    if (error) return falhaBanco(error.code, contexto.valores);
    return sucesso(mensagensConfiguracao.codigoGravado);
  });
}

async function categoriaExiste(contexto: ContextoConfiguracao, codigo: string): Promise<boolean | string> {
  const { data, error } = await contexto.supabase
    .schema("app")
    .from("categoria_gerencial")
    .select("codigo")
    .eq("codigo", codigo)
    .maybeSingle();
  if (error) return error.code ?? "erro";
  return data !== null;
}

// Rótulo vazio exclui o registro e a tela volta ao nome do produto.
export async function gravarRotulo(_estado: EstadoAcao, formulario: FormData): Promise<EstadoAcao> {
  return executarConfiguracao(formulario, async (contexto) => {
    const { valores } = contexto;
    const validacao = validarRotulo(leitorDoFormulario(formulario));
    if (!validacao.ok) return falhaValidacao(validacao.erros, valores);
    const { contexto: onde, chave, rotulo } = validacao.dados;
    if (onde === "categoria") {
      const existe = await categoriaExiste(contexto, chave);
      if (typeof existe === "string") return falhaBanco(existe, valores);
      if (!existe) return falhaValidacao({ chave: "Escolha a categoria da lista." }, valores);
    }
    const tabela = contexto.supabase.schema("app").from("rotulo_personalizado");
    if (rotulo === null) {
      const { error } = await tabela
        .delete()
        .eq("tenant_id", contexto.tenantId)
        .eq("contexto", onde)
        .eq("chave", chave);
      if (error) return falhaBanco(error.code, valores);
      return sucesso(mensagensConfiguracao.rotuloExcluido);
    }
    const { error } = await tabela.upsert(
      { tenant_id: contexto.tenantId, contexto: onde, chave, rotulo, autor: contexto.usuarioId },
      { onConflict: "tenant_id,contexto,chave" },
    );
    if (error) return falhaBanco(error.code, valores);
    return sucesso(mensagensConfiguracao.rotuloGravado);
  });
}

// Cria ou altera uma subcategoria. Na alteração, a categoria global não muda: contas já ligadas a ela
// precisam continuar na mesma categoria do DRE. O autor vem do gatilho app.definir_autor, pelo JWT.
export async function gravarSubcategoria(_estado: EstadoAcao, formulario: FormData): Promise<EstadoAcao> {
  return executarConfiguracao(formulario, async (contexto) => {
    const { valores } = contexto;
    const validacao = validarSubcategoria(leitorDoFormulario(formulario));
    if (!validacao.ok) return falhaValidacao(validacao.erros, valores);
    const { id, categoria_codigo, codigo, nome, ativa } = validacao.dados;
    const existe = await categoriaExiste(contexto, categoria_codigo);
    if (typeof existe === "string") return falhaBanco(existe, valores);
    if (!existe) return falhaValidacao({ categoria_codigo: "Escolha a categoria da lista." }, valores);
    const tabela = contexto.supabase.schema("app").from("categoria_tenant");
    const { error, data } = id
      ? await tabela
          .update({ codigo, nome, ativa })
          .eq("id", id)
          .eq("tenant_id", contexto.tenantId)
          .eq("categoria_codigo", categoria_codigo)
          .select("id")
      : await tabela
          .insert({ tenant_id: contexto.tenantId, categoria_codigo, codigo, nome, ativa })
          .select("id");
    if (error) {
      if (objetoAusente(error.code)) return falhaBanco(undefined, valores, mensagensConfiguracao.subcategoriaAusente);
      if (error.code === "23505") {
        return falhaValidacao({ codigo: "Já existe uma subcategoria com esse código." }, valores);
      }
      return falhaBanco(error.code, valores);
    }
    if (!data || data.length === 0) return falhaBanco("42501", valores);
    return sucesso(mensagensConfiguracao.subcategoriaGravada);
  });
}
