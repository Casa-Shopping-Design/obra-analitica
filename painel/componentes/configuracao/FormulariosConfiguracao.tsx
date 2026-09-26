"use client";

import { useActionState } from "react";
import {
  gravarComposicao,
  gravarMapaCodigo,
  gravarParametro,
  gravarRotulo,
  gravarSubcategoria,
  voltarAoPadrao,
} from "@/app/(painel)/configuracoes/acoes";
import { BotaoAcao, CampoAcao, MensagemAcao } from "@/componentes/planejamento/CamposAcao";
import { estadoInicial, type EstadoAcao } from "@/componentes/planejamento/estado-acao";
import { fusosBrasil, textoFaixa, type Parametro } from "@/lib/configuracao";

type Opcao = { valor: string; rotulo: string };

// Controle certo para o tipo do parâmetro. O servidor valida de novo a partir do catálogo.
function CampoValor({
  prefixo,
  nome,
  rotulo,
  parametro,
  valor,
  estado,
}: {
  prefixo: string;
  nome: string;
  rotulo: string;
  parametro: Parametro;
  valor: string;
  estado: EstadoAcao;
}) {
  const faixa = textoFaixa(parametro);
  const comum = { prefixo, nome, rotulo, estado, padrao: valor, obrigatorio: true };
  switch (parametro.tipo) {
    case "opcao":
      return (
        <CampoAcao
          {...comum}
          opcoes={(parametro.opcoes ?? []).map((opcao) => ({ valor: opcao.valor, rotulo: opcao.rotulo }))}
        />
      );
    case "booleano":
      return (
        <CampoAcao
          {...comum}
          opcoes={[
            { valor: "true", rotulo: "Sim" },
            { valor: "false", rotulo: "Não" },
          ]}
        />
      );
    case "fuso": {
      const fusos: string[] = [...fusosBrasil];
      if (valor && !fusos.includes(valor)) fusos.unshift(valor);
      return <CampoAcao {...comum} opcoes={fusos.map((fuso) => ({ valor: fuso, rotulo: fuso.replace(/_/g, " ") }))} />;
    }
    case "data":
      return <CampoAcao {...comum} tipo="date" />;
    case "fracao":
      return (
        <CampoAcao
          {...comum}
          rotulo={`${rotulo} (%)`}
          tipo="decimal"
          ajuda={`Em percentual${faixa ? `, ${faixa}` : ""}. Use vírgula para decimais.`}
        />
      );
    case "inteiro":
    case "numero":
      return <CampoAcao {...comum} tipo="decimal" ajuda={faixa ? `Aceita ${faixa}.` : undefined} />;
    default:
      return <CampoAcao {...comum} />;
  }
}

// Com validação do financeiro: observação obrigatória e confirmação marcada. Sem ela, observação opcional.
function CamposValidacao({ prefixo, exige, estado }: { prefixo: string; exige: boolean; estado: EstadoAcao }) {
  return (
    <>
      <CampoAcao
        prefixo={prefixo}
        nome="observacao"
        rotulo={exige ? "Com quem e quando foi validado" : "Observação (opcional)"}
        tipo="textarea"
        estado={estado}
        obrigatorio={exige}
        ajuda={exige ? "Por exemplo: validado com o contador em 20/09/2026." : "Fica no histórico junto com a alteração."}
      />
      {exige && (
        <CampoAcao
          prefixo={prefixo}
          nome="confirmacao"
          rotulo="Confirmo que esta regra foi validada pelo financeiro responsável. Meu usuário fica registrado."
          tipo="checkbox"
          estado={estado}
        />
      )}
    </>
  );
}

function CamposEscopo({ codigo, escopo }: { codigo?: string; escopo: string }) {
  return (
    <>
      {codigo && <input type="hidden" name="codigo" value={codigo} />}
      <input type="hidden" name="escopo" value={escopo} />
    </>
  );
}

export function FormularioParametro({
  parametro,
  valor,
  escopo,
  rotuloEscopo,
}: {
  parametro: Parametro;
  valor: string;
  escopo: string;
  rotuloEscopo: string;
}) {
  const [estado, enviar, enviando] = useActionState(gravarParametro, estadoInicial);
  const prefixo = `parametro-${parametro.codigo.replace(/\./g, "-")}`;
  return (
    <form action={enviar} noValidate aria-label={`Alterar ${parametro.nome} para ${rotuloEscopo}`} className="flex flex-col gap-3">
      <CamposEscopo codigo={parametro.codigo} escopo={escopo} />
      <CampoValor
        key={valor}
        prefixo={prefixo}
        nome="valor"
        rotulo={`Novo valor para ${rotuloEscopo}`}
        parametro={parametro}
        valor={valor}
        estado={estado}
      />
      <CamposValidacao prefixo={prefixo} exige={parametro.exige_validacao_financeira} estado={estado} />
      <BotaoAcao enviando={enviando} texto="Gravar valor" textoEnviando="Gravando..." />
      <MensagemAcao estado={estado} />
    </form>
  );
}

export function FormularioComposicao({
  parametros,
  valores,
  escopo,
  rotuloEscopo,
}: {
  parametros: Parametro[];
  valores: string[];
  escopo: string;
  rotuloEscopo: string;
}) {
  const [estado, enviar, enviando] = useActionState(gravarComposicao, estadoInicial);
  const exige = parametros.some((parametro) => parametro.exige_validacao_financeira);
  return (
    <form
      action={enviar}
      noValidate
      aria-label={`Alterar a composição do pagamento para ${rotuloEscopo}`}
      className="flex flex-col gap-3"
    >
      <CamposEscopo escopo={escopo} />
      <fieldset className="flex flex-col gap-2">
        <legend className="text-sm font-medium">Novos percentuais para {rotuloEscopo}. Os três somam 100%.</legend>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
          {parametros.map((parametro, posicao) => (
            <CampoValor
              key={`${parametro.codigo}-${valores[posicao]}`}
              prefixo="composicao"
              nome={parametro.codigo}
              rotulo={parametro.nome}
              parametro={parametro}
              valor={valores[posicao]}
              estado={estado}
            />
          ))}
        </div>
      </fieldset>
      <CamposValidacao prefixo="composicao" exige={exige} estado={estado} />
      <BotaoAcao enviando={enviando} texto="Gravar composição" textoEnviando="Gravando..." />
      <MensagemAcao estado={estado} />
    </form>
  );
}

// Exclui o valor do nível escolhido. Parâmetro que exige validação pede a mesma confirmação da gravação.
export function FormularioVoltarPadrao({
  codigo,
  escopo,
  exige,
  texto,
  descricao,
}: {
  codigo: string;
  escopo: string;
  exige: boolean;
  texto: string;
  descricao: string;
}) {
  const [estado, enviar, enviando] = useActionState(voltarAoPadrao, estadoInicial);
  return (
    <form action={enviar} noValidate aria-label={descricao} className="flex flex-col gap-2">
      <CamposEscopo codigo={codigo} escopo={escopo} />
      {exige && (
        <CampoAcao
          prefixo={`voltar-${codigo.replace(/\./g, "-")}`}
          nome="confirmacao"
          rotulo="Confirmo a volta ao valor de cima, validada pelo financeiro."
          tipo="checkbox"
          estado={estado}
        />
      )}
      <button
        type="submit"
        disabled={enviando}
        className="min-h-11 w-fit cursor-pointer rounded-lg border border-borda bg-superficie px-4 text-sm font-semibold hover:border-texto disabled:cursor-wait disabled:opacity-70"
      >
        {enviando ? "Excluindo..." : texto}
      </button>
      <MensagemAcao estado={estado} />
    </form>
  );
}

// Com domínio e código fixos (linha de pendência ou código já mapeado), só o valor muda.
export function FormularioMapaCodigo({
  dominio,
  valores,
  codigo,
  valorAtual = "",
  rotuloAtual = "",
  prefixo,
}: {
  dominio: string;
  valores: Opcao[];
  codigo?: string;
  valorAtual?: string;
  rotuloAtual?: string;
  prefixo: string;
}) {
  const [estado, enviar, enviando] = useActionState(gravarMapaCodigo, estadoInicial);
  const fixo = codigo !== undefined;
  return (
    <form
      action={enviar}
      noValidate
      aria-label={fixo ? `Mapear o código ${codigo}` : "Mapear ou corrigir um código"}
      className="flex flex-col gap-3"
    >
      <input type="hidden" name="dominio" value={dominio} />
      {fixo && <input type="hidden" name="codigo_origem" value={codigo} />}
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
        {!fixo && (
          <CampoAcao
            prefixo={prefixo}
            nome="codigo_origem"
            rotulo="Código na origem"
            estado={estado}
            obrigatorio
            ajuda="Exatamente como aparece na origem, por exemplo FI."
          />
        )}
        <CampoAcao
          key={valorAtual}
          prefixo={prefixo}
          nome="valor"
          rotulo={fixo ? `Valor do código ${codigo}` : "Valor"}
          estado={estado}
          padrao={valorAtual}
          opcoes={[{ valor: "", rotulo: "Escolha o valor" }, ...valores]}
          obrigatorio
        />
        <CampoAcao
          key={`rotulo-${rotuloAtual}`}
          prefixo={prefixo}
          nome="rotulo"
          rotulo="Nome na tela (opcional)"
          estado={estado}
          padrao={rotuloAtual}
        />
      </div>
      <CampoAcao prefixo={prefixo} nome="observacao" rotulo="Observação (opcional)" tipo="textarea" estado={estado} />
      <BotaoAcao enviando={enviando} texto={fixo ? "Gravar mapeamento" : "Mapear código"} textoEnviando="Gravando..." />
      <MensagemAcao estado={estado} />
    </form>
  );
}

export function FormularioRotulo({
  contexto,
  rotuloContexto,
  itens,
  prefixo,
}: {
  contexto: string;
  rotuloContexto: string;
  itens: Opcao[];
  prefixo: string;
}) {
  const [estado, enviar, enviando] = useActionState(gravarRotulo, estadoInicial);
  return (
    <form action={enviar} noValidate aria-label={`Rótulo de ${rotuloContexto.toLowerCase()}`} className="flex flex-col gap-3">
      <input type="hidden" name="contexto" value={contexto} />
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <CampoAcao
          prefixo={prefixo}
          nome="chave"
          rotulo={rotuloContexto}
          estado={estado}
          opcoes={[{ valor: "", rotulo: "Escolha da lista" }, ...itens]}
          obrigatorio
        />
        <CampoAcao
          prefixo={prefixo}
          nome="rotulo"
          rotulo="Nome que a construtora usa"
          estado={estado}
          ajuda="Deixe vazio para voltar ao nome do produto. Só o texto muda; o cálculo continua o mesmo."
        />
      </div>
      <BotaoAcao enviando={enviando} texto="Gravar rótulo" textoEnviando="Gravando..." />
      <MensagemAcao estado={estado} />
    </form>
  );
}

// Sem id cria; com id altera nome, código e uso, sem trocar a categoria global.
export function FormularioSubcategoria({
  categorias,
  subcategoria,
  prefixo,
}: {
  categorias: Opcao[];
  subcategoria?: { id: string; categoria_codigo: string; codigo: string; nome: string; ativa: boolean };
  prefixo: string;
}) {
  const [estado, enviar, enviando] = useActionState(gravarSubcategoria, estadoInicial);
  const edicao = subcategoria !== undefined;
  return (
    <form
      action={enviar}
      noValidate
      aria-label={edicao ? `Alterar a subcategoria ${subcategoria.nome}` : "Nova subcategoria"}
      className="flex flex-col gap-3"
    >
      {edicao && (
        <>
          <input type="hidden" name="id" value={subcategoria.id} />
          <input type="hidden" name="categoria_codigo" value={subcategoria.categoria_codigo} />
        </>
      )}
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
        {!edicao && (
          <CampoAcao
            prefixo={prefixo}
            nome="categoria_codigo"
            rotulo="Soma na categoria"
            estado={estado}
            opcoes={[{ valor: "", rotulo: "Escolha a categoria" }, ...categorias]}
            obrigatorio
          />
        )}
        <CampoAcao
          key={`codigo-${subcategoria?.codigo ?? ""}`}
          prefixo={prefixo}
          nome="codigo"
          rotulo="Código"
          estado={estado}
          padrao={subcategoria?.codigo ?? ""}
          obrigatorio
          ajuda="Minúsculas, números, ponto ou hífen. Ex.: materiais.eletrica"
        />
        <CampoAcao
          key={`nome-${subcategoria?.nome ?? ""}`}
          prefixo={prefixo}
          nome="nome"
          rotulo="Nome"
          estado={estado}
          padrao={subcategoria?.nome ?? ""}
          obrigatorio
        />
        <CampoAcao
          key={`ativa-${String(subcategoria?.ativa ?? true)}`}
          prefixo={prefixo}
          nome="ativa"
          rotulo="Em uso"
          estado={estado}
          padrao={subcategoria?.ativa === false ? "nao" : "sim"}
          opcoes={[
            { valor: "sim", rotulo: "Sim" },
            { valor: "nao", rotulo: "Não" },
          ]}
        />
      </div>
      <BotaoAcao enviando={enviando} texto={edicao ? "Gravar alteração" : "Criar subcategoria"} textoEnviando="Gravando..." />
      <MensagemAcao estado={estado} />
    </form>
  );
}
