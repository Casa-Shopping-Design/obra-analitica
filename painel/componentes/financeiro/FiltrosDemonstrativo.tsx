import type { CentroCusto } from "@/lib/consultas/referencia";
import { mesesDoFiltro, rotulosTipoPeriodo, tiposPeriodo, type Periodo } from "@/lib/periodo";

const classeCampo = "min-h-11 w-full min-w-0 rounded-lg border border-borda bg-superficie px-3";

// Formulário GET comum: funciona sem JavaScript e a URL guarda o recorte, que a página valida de novo.
export function FiltrosDemonstrativo({
  acao,
  centros,
  centroSelecionado,
  periodo,
  dataReferencia,
  incluirSemObra = false,
  camposOcultos = {},
  children,
}: {
  acao: string;
  centros: CentroCusto[];
  centroSelecionado: string | null;
  periodo: Periodo;
  dataReferencia: string;
  incluirSemObra?: boolean;
  camposOcultos?: Record<string, string>;
  children?: React.ReactNode;
}) {
  const obras = centros.filter((centro) => centro.tipo === "obra");
  const semObra = incluirSemObra ? centros.filter((centro) => centro.tipo === "empresa") : [];

  return (
    <form
      action={acao}
      method="get"
      aria-label="Filtros"
      className="grid grid-cols-1 gap-3 rounded-xl border border-borda bg-superficie p-4 sm:grid-cols-2 lg:grid-cols-4 lg:items-end"
    >
      {Object.entries(camposOcultos).map(([nome, valor]) => (
        <input key={nome} type="hidden" name={nome} value={valor} />
      ))}
      <div className="flex min-w-0 flex-col gap-1.5">
        <label htmlFor="filtro-obra" className="text-sm font-medium">
          Obra
        </label>
        <select id="filtro-obra" name="obra" defaultValue={centroSelecionado ?? ""} className={classeCampo}>
          <option value="">Todas as obras liberadas (consolidado)</option>
          {obras.map((obra) => (
            <option key={obra.id} value={obra.id}>
              {obra.nome}
            </option>
          ))}
          {semObra.map((centro) => (
            <option key={centro.id} value={centro.id}>
              {centro.nome}
            </option>
          ))}
        </select>
      </div>
      <div className="flex min-w-0 flex-col gap-1.5">
        <label htmlFor="filtro-periodo" className="text-sm font-medium">
          Período
        </label>
        <select id="filtro-periodo" name="periodo" defaultValue={periodo.tipo} className={classeCampo}>
          {tiposPeriodo.map((tipo) => (
            <option key={tipo} value={tipo}>
              {rotulosTipoPeriodo[tipo]}
            </option>
          ))}
        </select>
      </div>
      <div className="flex min-w-0 flex-col gap-1.5">
        <label htmlFor="filtro-mes" className="text-sm font-medium">
          Até o mês
        </label>
        <select id="filtro-mes" name="mes" defaultValue={periodo.mes.slice(0, 7)} className={classeCampo}>
          {mesesDoFiltro(dataReferencia).map((mes) => (
            <option key={mes.valor} value={mes.valor}>
              {mes.rotulo}
            </option>
          ))}
        </select>
      </div>
      {children}
      <button
        type="submit"
        className="min-h-11 cursor-pointer rounded-lg bg-menu px-4 font-semibold text-menu-texto hover:bg-menu-ativo"
      >
        Aplicar filtros
      </button>
    </form>
  );
}
