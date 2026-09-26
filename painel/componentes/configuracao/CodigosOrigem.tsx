import { FormularioMapaCodigo } from "@/componentes/configuracao/FormulariosConfiguracao";
import { Selo } from "@/componentes/financeiro/Selo";
import {
  dominiosCodigo,
  listaDominios,
  mensagensConfiguracao,
  quemAlterou,
  rotuloValorMapeado,
  somarPendenciasPorCodigo,
  type ValorCodigoOrigem,
} from "@/lib/configuracao";
import type { MapaCodigo, PendenciaCodigo } from "@/lib/consultas/configuracao";
import { formatarData, formatarReal } from "@/lib/formatar";

const celula = "border-b border-borda px-3 py-2 text-left align-top";
const cabecalho = `${celula} font-semibold text-suave`;

// Um bloco por domínio: códigos já mapeados, pendências vistas na carga e o formulário de mapeamento.
export function CodigosOrigem({
  mapa,
  pendencias,
  valoresCodigo,
  podeGravar,
  usuarioId,
}: {
  mapa: MapaCodigo[] | null;
  pendencias: PendenciaCodigo[] | null;
  valoresCodigo: ValorCodigoOrigem[];
  podeGravar: boolean;
  usuarioId: string;
}) {
  const somadas = somarPendenciasPorCodigo(pendencias ?? []);
  return (
    <div className="flex flex-col gap-6">
      {listaDominios.map((dominio) => {
        const titulo = dominiosCodigo[dominio];
        const aceitos = valoresCodigo.filter((item) => item.dominio === dominio);
        const valores = aceitos.map((item) => ({ valor: item.valor, rotulo: item.rotulo }));
        const semMapa = aceitos.find((item) => item.valor_sem_mapa);
        const doDominio = (mapa ?? []).filter((linha) => linha.dominio === dominio);
        const pendentes = somadas.filter((linha) => linha.dominio === dominio);
        const rotulo = (valor: string) => rotuloValorMapeado(valoresCodigo, dominio, valor);
        return (
          <section key={dominio} aria-labelledby={`dominio-${dominio}`} className="flex flex-col gap-3">
            <h3 id={`dominio-${dominio}`} className="text-lg font-semibold">
              {titulo}
            </h3>
            {semMapa && (
              <p className="text-sm text-suave">
                Código sem mapa vale como &quot;{semMapa.rotulo}&quot; e aparece como pendência.
              </p>
            )}
            {pendencias !== null && pendentes.length > 0 && (
              <div className="flex flex-col gap-2 rounded-lg border-2 border-atencao p-3">
                <p className="flex flex-wrap items-center gap-2 text-sm font-semibold">
                  <Selo tipo="parcial">
                    {pendentes.length === 1 ? "1 código sem mapa" : `${pendentes.length} códigos sem mapa`}
                  </Selo>
                  Vistos na última carga e ainda sem valor.
                </p>
                <div className="overflow-x-auto">
                  <table className="w-full min-w-[420px] border-collapse text-sm">
                    <caption className="sr-only">Códigos sem mapa em {titulo.toLowerCase()}</caption>
                    <thead>
                      <tr>
                        <th scope="col" className={cabecalho}>
                          Código
                        </th>
                        <th scope="col" className={`${cabecalho} text-right`}>
                          Registros
                        </th>
                        <th scope="col" className={`${cabecalho} text-right`}>
                          Valor envolvido
                        </th>
                        <th scope="col" className={cabecalho}>
                          Vale hoje como
                        </th>
                      </tr>
                    </thead>
                    <tbody>
                      {pendentes.map((linha) => (
                        <tr key={linha.codigo_origem ?? "sem-codigo"}>
                          <th scope="row" className={`${celula} font-mono`}>
                            {linha.codigo_origem ?? <span className="font-sans text-suave">Sem código na origem</span>}
                          </th>
                          <td className={`${celula} text-right tabular-nums`}>
                            {linha.quantidade_registros}
                            {linha.obras > 1 && <span className="block text-xs text-suave">em {linha.obras} obras</span>}
                          </td>
                          <td className={`${celula} text-right tabular-nums`}>
                            {linha.valor_envolvido === null ? "Sem valor" : formatarReal(linha.valor_envolvido)}
                          </td>
                          <td className={celula}>{rotulo(linha.valor_aplicado)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
                {pendentes.some((linha) => linha.codigo_origem === null) && (
                  <p className="text-sm text-suave">
                    Registro sem código na origem não tem como ser mapeado. Corrija o cadastro na origem.
                  </p>
                )}
                {podeGravar &&
                  pendentes.map(
                    (linha, posicao) =>
                      linha.codigo_origem !== null && (
                        <FormularioMapaCodigo
                          key={linha.codigo_origem}
                          dominio={dominio}
                          valores={valores}
                          codigo={linha.codigo_origem}
                          prefixo={`pendencia-${dominio}-${posicao}`}
                        />
                      ),
                  )}
              </div>
            )}
            {mapa !== null && doDominio.length === 0 && <p className="text-sm">{mensagensConfiguracao.semCodigos}</p>}
            {doDominio.length > 0 && (
              <div className="overflow-x-auto">
                <table className="w-full min-w-[560px] border-collapse text-sm">
                  <caption className="sr-only">Códigos mapeados em {titulo.toLowerCase()}</caption>
                  <thead>
                    <tr>
                      <th scope="col" className={cabecalho}>
                        Código na origem
                      </th>
                      <th scope="col" className={cabecalho}>
                        Valor
                      </th>
                      <th scope="col" className={cabecalho}>
                        Nome na tela
                      </th>
                      <th scope="col" className={cabecalho}>
                        Última alteração
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    {doDominio.map((linha) => (
                      <tr key={linha.codigo_origem}>
                        <th scope="row" className={`${celula} font-mono`}>
                          {linha.codigo_origem}
                        </th>
                        <td className={celula}>{rotulo(linha.valor)}</td>
                        <td className={celula}>{linha.rotulo ?? <span className="text-suave">Sem nome próprio</span>}</td>
                        <td className={`${celula} text-suave`}>
                          {linha.autor && linha.atualizado_em
                            ? `${formatarData(linha.atualizado_em)}, por ${quemAlterou(linha.autor, usuarioId)}`
                            : "Padrão do produto"}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
            {podeGravar && (
              <details className="rounded-lg border border-borda p-3">
                <summary className="min-h-11 cursor-pointer content-center font-semibold">
                  Mapear ou corrigir um código
                </summary>
                <div className="pt-3">
                  <FormularioMapaCodigo dominio={dominio} valores={valores} prefixo={`mapa-${dominio}`} />
                </div>
              </details>
            )}
          </section>
        );
      })}
      <p className="text-sm text-suave">
        A mudança de um código vale a partir da próxima carga de dados. Os números carregados antes continuam iguais
        até lá.
      </p>
    </div>
  );
}
