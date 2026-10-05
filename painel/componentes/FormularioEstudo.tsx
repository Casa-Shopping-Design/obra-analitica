"use client";

import { useActionState } from "react";
import { salvarEstudo, type EstadoEstudo } from "@/app/(painel)/obras/[id]/dre/estudo/acoes";

export type CampoEstudo = { linha: string; rotulo: string; valor: string };

type Propriedades = {
  centroCustoId: string;
  descricao: string;
  dataBase: string;
  hoje: string;
  campos: CampoEstudo[];
};

const estadoInicial: EstadoEstudo = { erro: null, sucesso: null, versao: null };

const classeCampo =
  "min-h-11 rounded-lg border border-borda bg-superficie px-3.5 text-[15px] text-texto focus-visible:border-texto";
const classeValor = `${classeCampo} text-right tabular-nums`;

// Campos sem controle de estado: o navegador guarda o que foi digitado e a Server Action lê o FormData.
// Toda gravação cria uma versão nova; não existe salvar por cima.
export function FormularioEstudo({ centroCustoId, descricao, dataBase, hoje, campos }: Propriedades) {
  const [estado, acao, enviando] = useActionState(salvarEstudo, estadoInicial);
  const idAviso = estado.erro ? "erro-estudo" : estado.sucesso ? "sucesso-estudo" : undefined;

  return (
    <form action={acao} className="flex flex-col gap-5" noValidate aria-describedby={idAviso}>
      <input type="hidden" name="centro_custo_id" value={centroCustoId} />

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div className="flex flex-col gap-1.5">
          <label htmlFor="descricao" className="text-sm font-medium">
            Descrição da versão
          </label>
          <input
            id="descricao"
            name="descricao"
            type="text"
            maxLength={120}
            defaultValue={descricao}
            placeholder="Ex.: revisão do orçamento de setembro"
            className={classeCampo}
          />
          <p className="text-xs text-suave">Opcional, até 120 caracteres. Fica só na lista de versões.</p>
        </div>
        <div className="flex flex-col gap-1.5">
          <label htmlFor="data_base" className="text-sm font-medium">
            Data-base do estudo
          </label>
          <input id="data_base" name="data_base" type="date" required max={hoje} defaultValue={dataBase} className={classeCampo} />
          <p className="text-xs text-suave">Data a que os valores se referem. Hoje ou anterior.</p>
        </div>
      </div>

      <fieldset className="flex flex-col gap-3">
        <legend className="mb-2 text-sm font-medium">Valores do estudo, em reais</legend>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {campos.map((campo) => (
            <div key={campo.linha} className="flex flex-col gap-1.5">
              <label htmlFor={`linha-${campo.linha}`} className="text-sm">
                {campo.rotulo}
              </label>
              <input
                id={`linha-${campo.linha}`}
                name={campo.linha}
                type="text"
                inputMode="decimal"
                autoComplete="off"
                required
                defaultValue={campo.valor}
                placeholder="0,00"
                className={classeValor}
              />
            </div>
          ))}
        </div>
        <p className="text-xs text-suave">Só números, com vírgula para os centavos. Linha que não se aplica fica 0,00.</p>
      </fieldset>

      {estado.erro && (
        <p id="erro-estudo" role="alert" className="rounded-lg border border-alerta px-3.5 py-2.5 text-sm text-alerta">
          {estado.erro}
        </p>
      )}
      {estado.sucesso && (
        <p id="sucesso-estudo" role="status" className="rounded-lg border border-entrada px-3.5 py-2.5 text-sm text-entrada">
          {estado.versao !== null ? `Versão ${estado.versao}. ` : ""}
          {estado.sucesso}
        </p>
      )}

      <button
        type="submit"
        disabled={enviando}
        className="min-h-12 w-fit cursor-pointer rounded-lg bg-menu px-6 text-base font-semibold text-menu-texto disabled:cursor-wait disabled:opacity-70"
      >
        {enviando ? "Gravando..." : "Gravar versão nova"}
      </button>
    </form>
  );
}
