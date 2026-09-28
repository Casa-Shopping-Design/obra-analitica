import type { RepasseObra } from "@/lib/consultas/repasse";
import { formatarReal } from "@/lib/formatar";

const inteiro = new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 0 });
const umaCasa = new Intl.NumberFormat("pt-BR", { minimumFractionDigits: 1, maximumFractionDigits: 1 });

function Etapa({ rotulo, quantidade, valor, destaque }: { rotulo: string; quantidade: number; valor: number; destaque?: boolean }) {
  return (
    <div className="flex min-w-0 flex-col gap-1 rounded-xl border border-borda bg-superficie p-5">
      <p className="text-sm text-suave">{rotulo}</p>
      <p className={`text-2xl font-semibold break-words ${destaque ? "text-alerta" : ""}`}>{formatarReal(valor)}</p>
      <p className="text-sm text-suave">
        {inteiro.format(quantidade)} {quantidade === 1 ? "contrato" : "contratos"}
      </p>
    </div>
  );
}

function Linha({ rotulo, valor }: { rotulo: string; valor: string }) {
  return (
    <div className="flex flex-wrap items-baseline justify-between gap-x-3 border-b border-borda py-2 last:border-b-0">
      <dt className="text-sm text-suave">{rotulo}</dt>
      <dd className="font-semibold">{valor}</dd>
    </div>
  );
}

// Etapa real do repasse no CRM ao lado do que o ERP ainda espera receber do banco.
export function QuadroRepasse({ repasse }: { repasse: RepasseObra }) {
  const dias = repasse.dias_medios_assinatura_liberacao;
  return (
    <div className="flex flex-col gap-5">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Etapa rotulo="Em análise no banco" quantidade={repasse.repasses_em_analise} valor={repasse.valor_em_analise} />
        <Etapa rotulo="Contrato assinado" quantidade={repasse.repasses_assinados} valor={repasse.valor_assinado} />
        <Etapa rotulo="Recurso liberado" quantidade={repasse.repasses_liberados} valor={repasse.valor_liberado} />
        <Etapa
          rotulo="Atrasado"
          quantidade={repasse.repasses_atrasados}
          valor={repasse.valor_atrasado}
          destaque={repasse.repasses_atrasados > 0}
        />
      </div>
      <p className="text-sm text-suave">
        A etapa vem das datas do CRM. Atrasado é o repasse ainda sem recurso liberado cuja parcela do financiamento já
        venceu no ERP; ele também aparece em análise ou assinado.
      </p>
      <dl className="rounded-xl border border-borda bg-superficie px-5 py-2">
        <Linha rotulo="Contratos financiados no ERP" valor={inteiro.format(repasse.contratos_financiados_origem)} />
        <Linha rotulo="Contratos com repasse no CRM" valor={inteiro.format(repasse.contratos_com_repasse)} />
        <Linha rotulo="Financiados sem repasse aberto no CRM" valor={inteiro.format(repasse.contratos_sem_repasse)} />
        <Linha
          rotulo="Dias médios da assinatura ao recurso liberado"
          valor={dias === null ? "Nenhum repasse liberado ainda" : `${umaCasa.format(dias)} dias`}
        />
        <Linha rotulo="Repasse a receber no ERP" valor={formatarReal(repasse.a_receber_repasse_origem)} />
        <Linha rotulo="Repasse vencido no ERP" valor={formatarReal(repasse.repasse_atrasado_origem)} />
        <Linha rotulo="Liberado no CRM e ainda sem baixa no ERP" valor={formatarReal(repasse.liberado_sem_baixa_origem)} />
      </dl>
    </div>
  );
}
