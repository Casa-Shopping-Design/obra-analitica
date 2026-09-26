"use client";

import { useActionState } from "react";
import {
  escopoTenant,
  estadoGravacaoInicial,
  metodosReconhecimento,
  rotulosMetodo,
  rotulosTipoOrigem,
  tiposOrigemConta,
  type EstadoGravacao,
  type TipoOrigemConta,
} from "@/componentes/financeiro/regras-classificacao";

type Acao = (estado: EstadoGravacao, formulario: FormData) => Promise<EstadoGravacao>;
type Opcao = { valor: string; rotulo: string };

const classeCampo = "min-h-11 w-full min-w-0 rounded-lg border bg-superficie px-3";

// Rótulo, ajuda e erro ligados por aria-describedby; com erro, o valor digitado volta para o campo.
function Campo({
  id,
  nome,
  rotulo,
  estado,
  opcoes,
  padrao = "",
  ajuda,
  multilinha = false,
}: {
  id: string;
  nome: string;
  rotulo: string;
  estado: EstadoGravacao;
  opcoes?: Opcao[];
  padrao?: string;
  ajuda?: string;
  multilinha?: boolean;
}) {
  const erro = estado.erros[nome];
  const valor = estado.situacao === "erro" ? (estado.valores[nome] ?? padrao) : padrao;
  const descricoes = [ajuda ? `${id}-ajuda` : null, erro ? `${id}-erro` : null].filter(Boolean).join(" ") || undefined;
  const comum = { id, name: nome, "aria-invalid": erro ? true : undefined, "aria-describedby": descricoes };
  const borda = erro ? "border-alerta" : "border-borda";
  return (
    <div className="flex min-w-0 flex-col gap-1.5">
      <label htmlFor={id} className="text-sm font-medium">
        {rotulo}
      </label>
      {opcoes ? (
        <select {...comum} key={valor} defaultValue={valor} className={`${classeCampo} ${borda}`}>
          {opcoes.map((opcao) => (
            <option key={opcao.valor} value={opcao.valor}>
              {opcao.rotulo}
            </option>
          ))}
        </select>
      ) : multilinha ? (
        <textarea {...comum} key={valor} defaultValue={valor} rows={2} className={`${classeCampo} ${borda} py-2`} />
      ) : (
        <input {...comum} key={valor} type="text" defaultValue={valor} className={`${classeCampo} ${borda}`} />
      )}
      {ajuda && (
        <p id={`${id}-ajuda`} className="text-xs text-suave">
          {ajuda}
        </p>
      )}
      {erro && (
        <p id={`${id}-erro`} className="text-sm text-alerta">
          {erro}
        </p>
      )}
    </div>
  );
}

// Região sempre presente: o leitor de tela anuncia sucesso e erro quando o texto muda.
function Mensagem({ estado }: { estado: EstadoGravacao }) {
  return (
    <div aria-live="polite" aria-atomic="true" className="min-h-6 text-sm">
      {estado.situacao === "sucesso" && (
        <p className="rounded-lg border border-entrada px-3 py-2 text-entrada">{estado.mensagem}</p>
      )}
      {estado.situacao === "erro" && (
        <p className="rounded-lg border border-alerta px-3 py-2 text-alerta">
          <span aria-hidden="true">! </span>
          {estado.mensagem}
        </p>
      )}
    </div>
  );
}

function Botao({ enviando, texto }: { enviando: boolean; texto: string }) {
  return (
    <button
      type="submit"
      disabled={enviando}
      className="min-h-11 w-fit cursor-pointer rounded-lg bg-menu px-5 font-semibold text-menu-texto hover:bg-menu-ativo disabled:cursor-wait disabled:opacity-70"
    >
      {enviando ? "Gravando..." : texto}
    </button>
  );
}

export type CategoriaOpcao = { codigo: string; nome: string; tipos: TipoOrigemConta[] };

// Com tipo e conta fixos (linha de pendência), só as categorias compatíveis aparecem. Sem eles, o formulário
// serve para classificar ou reclassificar qualquer conta; o servidor confere a compatibilidade.
export function FormularioClassificacao({
  acao,
  prefixo,
  categorias,
  tipoOrigem,
  conta,
}: {
  acao: Acao;
  prefixo: string;
  categorias: CategoriaOpcao[];
  tipoOrigem?: TipoOrigemConta;
  conta?: string;
}) {
  const [estado, enviar, enviando] = useActionState(acao, estadoGravacaoInicial);
  const fixo = tipoOrigem !== undefined && conta !== undefined;
  const opcoesCategoria = [
    { valor: "", rotulo: "Escolha a categoria" },
    ...categorias
      .filter((categoria) => !fixo || categoria.tipos.includes(tipoOrigem))
      .map((categoria) => ({
        valor: categoria.codigo,
        rotulo: fixo
          ? categoria.nome
          : `${categoria.nome} (${categoria.tipos.map((tipo) => rotulosTipoOrigem[tipo].toLowerCase()).join(", ")})`,
      })),
  ];
  return (
    <form
      action={enviar}
      noValidate
      aria-label={fixo ? `Classificar a conta ${conta}` : "Classificar ou reclassificar uma conta"}
      className="flex flex-col gap-3"
    >
      {fixo ? (
        <>
          <input type="hidden" name="tipo_origem" value={tipoOrigem} />
          <input type="hidden" name="conta_origem" value={conta} />
        </>
      ) : (
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <Campo
            id={`${prefixo}-tipo`}
            nome="tipo_origem"
            rotulo="Tipo de lançamento"
            estado={estado}
            opcoes={[
              { valor: "", rotulo: "Escolha o tipo" },
              ...tiposOrigemConta.map((tipo) => ({ valor: tipo, rotulo: rotulosTipoOrigem[tipo] })),
            ]}
          />
          <Campo
            id={`${prefixo}-conta`}
            nome="conta_origem"
            rotulo="Código da conta na origem"
            estado={estado}
            ajuda="Exatamente como aparece na lista, por exemplo 2.01.001."
          />
        </div>
      )}
      <Campo
        id={`${prefixo}-categoria`}
        nome="categoria_codigo"
        rotulo="Categoria gerencial"
        estado={estado}
        opcoes={opcoesCategoria}
      />
      <Campo id={`${prefixo}-observacao`} nome="observacao" rotulo="Observação (opcional)" estado={estado} multilinha />
      <Botao enviando={enviando} texto={fixo ? "Classificar conta" : "Gravar classificação"} />
      <Mensagem estado={estado} />
    </form>
  );
}

export function FormularioCriterio({ acao, obras }: { acao: Acao; obras: Opcao[] }) {
  const [estado, enviar, enviando] = useActionState(acao, estadoGravacaoInicial);
  const erroConfirmacao = estado.erros.confirmacao;
  return (
    <form
      action={enviar}
      noValidate
      aria-label="Registrar o critério de reconhecimento"
      className="flex flex-col gap-3"
    >
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <Campo
          id="criterio-escopo"
          nome="escopo"
          rotulo="Vale para"
          estado={estado}
          padrao={escopoTenant}
          opcoes={[{ valor: escopoTenant, rotulo: "Todas as obras (padrão da construtora)" }, ...obras]}
          ajuda="O critério de uma obra vale no lugar do padrão da construtora."
        />
        <Campo
          id="criterio-metodo"
          nome="metodo"
          rotulo="Critério"
          estado={estado}
          padrao="percentual_conclusao"
          opcoes={metodosReconhecimento.map((metodo) => ({ valor: metodo, rotulo: rotulosMetodo[metodo] }))}
        />
      </div>
      <Campo
        id="criterio-observacao"
        nome="observacao"
        rotulo="Com quem e quando foi validado"
        estado={estado}
        multilinha
        ajuda="Obrigatório para ligar o percentual de conclusão. Por exemplo: validado com o contador em 20/09/2026."
      />
      <div className="flex flex-col gap-1.5">
        <label htmlFor="criterio-confirmacao" className="flex min-h-11 items-start gap-2 text-sm font-medium">
          <input
            id="criterio-confirmacao"
            name="confirmacao"
            type="checkbox"
            value="sim"
            className="mt-0.5 size-5 shrink-0"
            aria-invalid={erroConfirmacao ? true : undefined}
            aria-describedby={erroConfirmacao ? "criterio-confirmacao-erro" : undefined}
          />
          Sou do financeiro responsável e validei este critério. Meu usuário fica registrado como quem validou.
        </label>
        {erroConfirmacao && (
          <p id="criterio-confirmacao-erro" className="text-sm text-alerta">
            {erroConfirmacao}
          </p>
        )}
      </div>
      <Botao enviando={enviando} texto="Registrar critério" />
      <Mensagem estado={estado} />
    </form>
  );
}
