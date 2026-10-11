import { linhaEmDestaque, type LinhaDemonstrativo } from "@/lib/empresa";
import { formatarPercentual, formatarReal } from "@/lib/formatar";

// Classes fixas porque o Tailwind só gera a classe que aparece escrita inteira no código.
export const recuoPorNivel = ["pl-3", "pl-7", "pl-11"];

export function classeLinha(tipo: string): string {
  if (tipo === "total") return "bg-fundo font-semibold print:[print-color-adjust:exact]";
  return linhaEmDestaque(tipo) ? "font-semibold" : "";
}

export function classeRotulo(nivel: number, tipo: string): string {
  const recuo = recuoPorNivel[nivel] ?? recuoPorNivel[recuoPorNivel.length - 1];
  const fundo = tipo === "total" ? "bg-fundo" : "bg-superficie";
  return `sticky left-0 z-10 ${fundo} py-2.5 pr-3 text-left align-top print:static print:py-1 ${recuo} ${
    linhaEmDestaque(tipo) ? "font-semibold" : "font-normal"
  }`;
}

export const classeCelulaValor = "px-3 py-2.5 text-right align-top whitespace-nowrap print:px-1 print:py-1";

// Negativo sai com o sinal na frente e sem cor: na planilha todo uso de recurso já é negativo por convenção.
export function textoValor(valor: number | null): string {
  return valor === null ? "" : formatarReal(valor);
}

type Propriedades = {
  id: string;
  titulo: string;
  legenda: string;
  linhas: LinhaDemonstrativo[];
  rotuloPercentual?: string;
};

// Só leitura: a ordem, o rótulo, o nível e o valor vêm prontos da função do banco.
export function TabelaDemonstrativo({ id, titulo, legenda, linhas, rotuloPercentual }: Propriedades) {
  return (
    <section aria-labelledby={id} className="flex flex-col gap-3">
      <h2 id={id} className="font-serif text-2xl font-semibold">
        {titulo}
      </h2>
      {/* relative segura dentro da rolagem os textos sr-only, que são absolutos e alargariam a página no celular */}
      <div className="relative overflow-x-auto rounded-xl border border-borda bg-superficie print:overflow-visible print:rounded-none print:border-0">
        <table className="w-full min-w-[560px] border-collapse text-sm tabular-nums print:min-w-0 print:text-[8pt]">
          <caption className="sr-only">{legenda}</caption>
          <thead>
            <tr className="text-suave">
              <th
                scope="col"
                className="sticky left-0 z-10 border-b border-borda bg-superficie px-3 py-3 text-left align-bottom font-medium print:static"
              >
                Linha
              </th>
              <th scope="col" className="border-b border-borda px-3 py-3 text-right align-bottom font-medium">
                Valor
              </th>
              {rotuloPercentual && (
                <th scope="col" className="border-b border-borda px-3 py-3 text-right align-bottom font-medium">
                  {rotuloPercentual}
                </th>
              )}
            </tr>
          </thead>
          <tbody>
            {linhas.map((linha) => (
              <tr key={linha.linha} className={`border-b border-borda last:border-b-0 ${classeLinha(linha.tipo)}`}>
                <th scope="row" className={classeRotulo(linha.nivel, linha.tipo)}>
                  {linha.rotulo}
                </th>
                <td className={classeCelulaValor}>{textoValor(linha.valor)}</td>
                {rotuloPercentual && (
                  <td className={classeCelulaValor}>{linha.percentual === null ? "" : formatarPercentual(linha.percentual)}</td>
                )}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}
