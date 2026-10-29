import { classeCelulaValor, classeLinha, classeRotulo, textoValor } from "@/componentes/TabelaDemonstrativo";
import type { LinhaGrade } from "@/lib/empresa";
import { formatarMes } from "@/lib/formatar";

type Propriedades = {
  id: string;
  titulo: string;
  legenda: string;
  meses: string[];
  linhas: LinhaGrade[];
};

// Uma coluna por mês, até doze. O nome da linha fica fixo e a tabela rola para o lado dentro do contêiner.
export function TabelaDemonstrativoMensal({ id, titulo, legenda, meses, linhas }: Propriedades) {
  return (
    <section aria-labelledby={id} className="flex flex-col gap-3">
      <h2 id={id} className="font-serif text-xl font-semibold">
        {titulo}
      </h2>
      <p className="text-sm text-suave print:hidden">Arraste a tabela para o lado para ver todos os meses.</p>
      <div className="relative overflow-x-auto quadro print:overflow-visible print:rounded-none print:border-0">
        <table className="w-full min-w-[960px] border-collapse text-sm tabular-nums print:min-w-0 print:text-[7pt]">
          <caption className="sr-only">{legenda}</caption>
          <thead>
            <tr className="text-suave">
              <th
                scope="col"
                className="sticky left-0 z-10 border-b border-borda bg-superficie px-3 py-3 text-left align-bottom font-medium print:static"
              >
                Linha
              </th>
              {meses.map((mes) => (
                <th key={mes} scope="col" className="border-b border-borda px-3 py-3 text-right align-bottom font-medium">
                  {formatarMes(mes)}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {linhas.map((linha) => (
              <tr key={linha.linha} className={`border-b border-borda last:border-b-0 ${classeLinha(linha.tipo)}`}>
                <th scope="row" className={`${classeRotulo(linha.nivel, linha.tipo)} min-w-64`}>
                  {linha.rotulo}
                </th>
                {linha.valores.map((valor, indice) => (
                  <td key={meses[indice]} className={classeCelulaValor}>
                    {textoValor(valor)}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}
