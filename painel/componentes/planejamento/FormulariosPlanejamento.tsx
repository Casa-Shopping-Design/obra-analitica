"use client";

import { useActionState } from "react";
import { BotaoAcao, CampoAcao, MensagemAcao } from "@/componentes/planejamento/CamposAcao";
import { estadoInicial, type EstadoAcao } from "@/componentes/planejamento/estado-acao";

export type AcaoFormulario = (estado: EstadoAcao, formulario: FormData) => Promise<EstadoAcao>;
type Opcao = { valor: string; rotulo: string };

export function FormularioVersaoProjecao({ acao, obraId }: { acao: AcaoFormulario; obraId: string }) {
  const [estado, enviar, enviando] = useActionState(acao, estadoInicial);
  return (
    <form action={enviar} className="flex flex-col gap-3" aria-label="Registrar versão da projeção" noValidate>
      <input type="hidden" name="obra" value={obraId} />
      <CampoAcao
        prefixo="versao-projecao"
        nome="descricao"
        rotulo="Descrição da versão"
        tipo="textarea"
        estado={estado}
        obrigatorio
        ajuda="Por exemplo: fechamento de setembro, revisão depois da reunião com o banco."
      />
      <BotaoAcao enviando={enviando} texto="Registrar versão da projeção" textoEnviando="Registrando..." />
      <MensagemAcao estado={estado} />
    </form>
  );
}

export type LinhaMetaFormulario = {
  mes: string;
  unidades: string;
  valor: string;
  fracao: string;
  recebimento: string;
  limite: string;
};

const camposMeta = [
  { nome: "unidades", rotulo: "Unidades" },
  { nome: "valor", rotulo: "Valor contratado (R$)" },
  { nome: "fracao", rotulo: "Financiado (%)" },
  { nome: "recebimento", rotulo: "Recebimento esperado (R$)" },
  { nome: "limite", rotulo: "Limite de aporte próprio (R$)" },
] as const;

// Uma linha por mês. Linha em branco é ignorada; o servidor confere mês repetido e valores.
export function FormularioMetas({
  acao,
  obraId,
  linhas,
  meses,
}: {
  acao: AcaoFormulario;
  obraId: string;
  linhas: LinhaMetaFormulario[];
  meses: Opcao[];
}) {
  const [estado, enviar, enviando] = useActionState(acao, estadoInicial);
  const opcoesMes = [{ valor: "", rotulo: "Sem mês" }, ...meses];
  return (
    <form action={enviar} className="flex flex-col gap-4" aria-label="Registrar nova versão das metas" noValidate>
      <input type="hidden" name="obra" value={obraId} />
      <CampoAcao prefixo="metas" nome="descricao" rotulo="Descrição da versão" estado={estado} obrigatorio />
      <div className="flex flex-col gap-3">
        {linhas.map((linha, indice) => (
          <fieldset key={indice} className="grid grid-cols-2 gap-2 rounded-lg border border-borda p-3 md:grid-cols-6">
            <legend className="px-1 text-sm font-medium">Linha {indice + 1}</legend>
            <CampoAcao prefixo="metas" nome={`mes_${indice}`} rotulo="Mês" estado={estado} padrao={linha.mes} opcoes={opcoesMes} />
            {camposMeta.map((campo) => (
              <CampoAcao
                key={campo.nome}
                prefixo="metas"
                nome={`${campo.nome}_${indice}`}
                rotulo={campo.rotulo}
                estado={estado}
                padrao={linha[campo.nome]}
                tipo="decimal"
              />
            ))}
          </fieldset>
        ))}
      </div>
      <BotaoAcao enviando={enviando} texto="Registrar nova versão das metas" textoEnviando="Registrando..." />
      <MensagemAcao estado={estado} />
    </form>
  );
}

export function FormularioPremissa({
  acao,
  obraId,
  linhas,
  meses,
}: {
  acao: AcaoFormulario;
  obraId: string;
  linhas: { mes: string; percentual: string }[];
  meses: Opcao[];
}) {
  const [estado, enviar, enviando] = useActionState(acao, estadoInicial);
  const opcoesMes = [{ valor: "", rotulo: "Sem mês" }, ...meses];
  return (
    <form action={enviar} className="flex flex-col gap-4" aria-label="Registrar premissa de meses do custo sem título" noValidate>
      <input type="hidden" name="obra" value={obraId} />
      <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
        <CampoAcao
          prefixo="premissa"
          nome="fonte"
          rotulo="Fonte"
          estado={estado}
          obrigatorio
          ajuda="De onde veio a curva: cronograma físico-financeiro, planilha do engenheiro, reunião."
        />
        <CampoAcao prefixo="premissa" nome="observacao" rotulo="Observação" tipo="textarea" estado={estado} />
      </div>
      <p className="text-sm text-suave">Método: percentual do custo sem título em cada mês. Os percentuais somam 100%.</p>
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-3">
        {linhas.map((linha, indice) => (
          <fieldset key={indice} className="grid grid-cols-2 gap-2 rounded-lg border border-borda p-3">
            <legend className="px-1 text-sm font-medium">Mês {indice + 1}</legend>
            <CampoAcao prefixo="premissa" nome={`mes_${indice}`} rotulo="Mês" estado={estado} padrao={linha.mes} opcoes={opcoesMes} />
            <CampoAcao
              prefixo="premissa"
              nome={`percentual_${indice}`}
              rotulo="Percentual (%)"
              estado={estado}
              padrao={linha.percentual}
              tipo="decimal"
            />
          </fieldset>
        ))}
      </div>
      {estado.erros.soma && (
        <p id="premissa-soma-erro" className="text-sm text-alerta">
          {estado.erros.soma}
        </p>
      )}
      <BotaoAcao enviando={enviando} texto="Registrar premissa" textoEnviando="Registrando..." />
      <MensagemAcao estado={estado} />
    </form>
  );
}
