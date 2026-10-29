import { rotuloMes, type PeriodoEmpresa } from "@/lib/empresa-periodo";

const classeCampo =
  "min-h-11 rounded-lg border border-borda bg-superficie px-3 text-[15px] text-texto focus-visible:border-texto";
const classeOpcao =
  "flex min-h-11 cursor-pointer items-center gap-2 rounded-lg border border-borda bg-superficie px-3 has-checked:border-menu has-checked:bg-menu has-checked:text-menu-texto has-focus-visible:outline-3 has-focus-visible:outline-texto";

const modos = [
  { valor: "acumulado", rotulo: "Acumulado (como na planilha)" },
  { valor: "periodo", rotulo: "Movimento do período" },
] as const;

// Formulário GET: o período vai para a URL e a página refaz a consulta no servidor, com o token de quem vê.
// Funciona sem JavaScript e o endereço pode ser guardado ou mandado a outra pessoa.
export function SeletorPeriodoEmpresa({ periodo, meses }: { periodo: PeriodoEmpresa; meses: string[] }) {
  return (
    <form method="get" className="flex flex-col gap-4 secao print:hidden">
      {periodo.aba !== "fontes-usos" && <input type="hidden" name="aba" value={periodo.aba} />}
      <div className="flex flex-wrap items-end gap-4">
        <div className="flex flex-col gap-1.5">
          <label htmlFor="periodo-de" className="text-sm font-medium">
            Mês inicial
          </label>
          <select id="periodo-de" name="de" defaultValue={periodo.inicio} className={classeCampo}>
            {meses.map((mes) => (
              <option key={mes} value={mes}>
                {rotuloMes(mes)}
              </option>
            ))}
          </select>
        </div>
        <div className="flex flex-col gap-1.5">
          <label htmlFor="periodo-ate" className="text-sm font-medium">
            Mês final
          </label>
          <select id="periodo-ate" name="ate" defaultValue={periodo.fim} className={classeCampo}>
            {meses.map((mes) => (
              <option key={mes} value={mes}>
                {rotuloMes(mes)}
              </option>
            ))}
          </select>
        </div>
        <fieldset className="flex flex-col gap-1.5">
          <legend className="pb-1.5 text-sm font-medium">Modo</legend>
          <div className="flex flex-wrap gap-2">
            {modos.map((modo) => (
              <label key={modo.valor} className={classeOpcao}>
                <input
                  type="radio"
                  name="modo"
                  value={modo.valor}
                  defaultChecked={periodo.acumulado === (modo.valor === "acumulado")}
                  className="sr-only"
                />
                {modo.rotulo}
              </label>
            ))}
          </div>
        </fieldset>
        <label className={classeOpcao}>
          <input type="checkbox" name="visao" value="mensal" defaultChecked={periodo.mensal} className="size-4 accent-menu" />
          Mês a mês
        </label>
        <button
          type="submit"
          className="min-h-11 cursor-pointer rounded-lg bg-menu px-5 text-base font-semibold text-menu-texto"
        >
          Aplicar
        </button>
      </div>
      <p className="text-sm text-suave">
        No acumulado vale a posição no fim do mês final, desde o início da contabilidade; o mês inicial só limita a
        visão mês a mês, que mostra até 12 meses terminando no mês final.
      </p>
    </form>
  );
}
