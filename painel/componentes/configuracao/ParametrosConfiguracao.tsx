import Link from "next/link";
import { Bloco } from "@/componentes/financeiro/Aviso";
import {
  FormularioComposicao,
  FormularioParametro,
  FormularioVoltarPadrao,
} from "@/componentes/configuracao/FormulariosConfiguracao";
import {
  escopoConstrutora,
  quemAlterou,
  rotulosOrigem,
  textoDoFormulario,
  textoDoValor,
  type GrupoTela,
  type ItemComposicao,
  type ItemParametro,
  type Parametro,
  type ValorEmVigor,
} from "@/lib/configuracao";
import { formatarData } from "@/lib/formatar";

type Escopo = { valor: string; rotulo: string; ehObra: boolean };

function Origem({ emVigor, usuarioId }: { emVigor: ValorEmVigor; usuarioId: string }) {
  const registro = emVigor.registro;
  return (
    <p className="text-xs text-suave">
      {rotulosOrigem[emVigor.origem]}
      {registro?.atualizado_em && (
        <>
          , alterado por {quemAlterou(registro.autor, usuarioId)} em {formatarData(registro.atualizado_em)}
        </>
      )}
      {registro?.observacao && <>. Observação: {registro.observacao}</>}
    </p>
  );
}

function OpcoesExplicadas({ parametro }: { parametro: Parametro }) {
  const comDescricao = (parametro.opcoes ?? []).filter((opcao) => opcao.descricao);
  if (comDescricao.length === 0) return null;
  return (
    <dl className="grid gap-x-4 gap-y-1 text-xs sm:grid-cols-[auto_1fr]">
      {comDescricao.map((opcao) => (
        <div key={opcao.valor} className="contents">
          <dt className="font-semibold">{opcao.rotulo}</dt>
          <dd className="text-suave">{opcao.descricao}</dd>
        </div>
      ))}
    </dl>
  );
}

// Texto do botão que exclui o nível: na obra volta ao valor da construtora; na construtora, ao do produto.
function textoVoltar(escopo: Escopo): string {
  return escopo.ehObra ? "Usar o valor da construtora" : "Voltar ao padrão do produto";
}

function SoConstrutora({ codigo }: { codigo: string }) {
  return (
    <p className="text-sm text-suave">
      Vale para a construtora inteira, sem valor por obra.{" "}
      <Link
        href={`/configuracoes?escopo=${escopoConstrutora}#${codigo}`}
        className="underline underline-offset-4 hover:text-menu"
      >
        Alterar no escopo da construtora
      </Link>
    </p>
  );
}

function CartaoParametro({
  item,
  escopo,
  podeGravar,
  usuarioId,
}: {
  item: ItemParametro;
  escopo: Escopo;
  podeGravar: boolean;
  usuarioId: string;
}) {
  const { parametro, emVigor, noNivel, editavel } = item;
  return (
    <li id={parametro.codigo} className="flex scroll-mt-4 flex-col gap-3 rounded-lg border border-borda p-4">
      <div className="flex flex-col gap-1">
        <h3 className="font-semibold">
          {parametro.nome}
          {parametro.escopo === "tenant_e_obra" && (
            <span className="ml-2 text-xs font-normal text-suave">aceita valor por obra</span>
          )}
        </h3>
        <p className="text-sm text-suave">{parametro.descricao}</p>
        <OpcoesExplicadas parametro={parametro} />
      </div>
      <div className="flex flex-col gap-0.5">
        <p className="text-sm">
          Em vigor: <strong>{textoDoValor(parametro, emVigor.valor)}</strong>
        </p>
        <Origem emVigor={emVigor} usuarioId={usuarioId} />
        {emVigor.origem !== "padrao" && (
          <p className="text-xs text-suave">Padrão do produto: {textoDoValor(parametro, parametro.padrao)}</p>
        )}
      </div>
      {parametro.exige_validacao_financeira && (
        <p className="text-sm">
          <span aria-hidden="true" className="font-semibold text-atencao">
            !{" "}
          </span>
          Muda números do DRE ou do caixa. Só grave depois de validar com o financeiro responsável.
        </p>
      )}
      {podeGravar && !editavel && <SoConstrutora codigo={parametro.codigo} />}
      {podeGravar && editavel && (
        <>
          <FormularioParametro
            parametro={parametro}
            valor={textoDoFormulario(parametro, emVigor.valor)}
            escopo={escopo.valor}
            rotuloEscopo={escopo.rotulo}
          />
          {noNivel && (
            <FormularioVoltarPadrao
              codigo={parametro.codigo}
              escopo={escopo.valor}
              exige={parametro.exige_validacao_financeira}
              texto={textoVoltar(escopo)}
              descricao={`Excluir o valor de ${parametro.nome} gravado para ${escopo.rotulo}`}
            />
          )}
        </>
      )}
    </li>
  );
}

function CartaoComposicao({
  item,
  escopo,
  podeGravar,
  usuarioId,
}: {
  item: ItemComposicao;
  escopo: Escopo;
  podeGravar: boolean;
  usuarioId: string;
}) {
  const { parametros, emVigor, noNivel, editavel } = item;
  const exige = parametros.some((parametro) => parametro.exige_validacao_financeira);
  return (
    <li id="composicao" className="flex scroll-mt-4 flex-col gap-3 rounded-lg border border-borda p-4">
      <div className="flex flex-col gap-1">
        <h3 className="font-semibold">Composição do pagamento nas novas vendas</h3>
        <p className="text-sm text-suave">
          Quanto do preço vem de entrada, de parcelas mensais e de financiamento bancário. Os três somam 100% e são
          gravados juntos.
        </p>
      </div>
      <dl className="flex flex-col gap-2 text-sm">
        {parametros.map((parametro, posicao) => (
          <div key={parametro.codigo} className="flex flex-col gap-0.5">
            <dt>{parametro.nome}</dt>
            <dd>
              <strong>{textoDoValor(parametro, emVigor[posicao].valor)}</strong>
              <Origem emVigor={emVigor[posicao]} usuarioId={usuarioId} />
            </dd>
          </div>
        ))}
      </dl>
      {podeGravar && !editavel && <SoConstrutora codigo="composicao" />}
      {podeGravar && editavel && (
        <>
          <FormularioComposicao
            parametros={parametros}
            valores={parametros.map((parametro, posicao) => textoDoFormulario(parametro, emVigor[posicao].valor))}
            escopo={escopo.valor}
            rotuloEscopo={escopo.rotulo}
          />
          {noNivel.some((registro) => registro !== null) && (
            <FormularioVoltarPadrao
              codigo={parametros[0].codigo}
              escopo={escopo.valor}
              exige={exige}
              texto={textoVoltar(escopo)}
              descricao={`Excluir a composição do pagamento gravada para ${escopo.rotulo}`}
            />
          )}
        </>
      )}
    </li>
  );
}

export function ParametrosConfiguracao({
  grupos,
  escopo,
  podeGravar,
  usuarioId,
}: {
  grupos: GrupoTela[];
  escopo: Escopo;
  podeGravar: boolean;
  usuarioId: string;
}) {
  return (
    <>
      {grupos.map((grupo) => (
        <Bloco key={grupo.grupo} id={`grupo-${grupo.grupo}`} titulo={grupo.titulo} contexto={grupo.descricao}>
          <ul className="grid grid-cols-1 gap-3 xl:grid-cols-2">
            {grupo.itens.map((item) =>
              item.tipo === "composicao" ? (
                <CartaoComposicao
                  key="composicao"
                  item={item}
                  escopo={escopo}
                  podeGravar={podeGravar}
                  usuarioId={usuarioId}
                />
              ) : (
                <CartaoParametro
                  key={item.parametro.codigo}
                  item={item}
                  escopo={escopo}
                  podeGravar={podeGravar}
                  usuarioId={usuarioId}
                />
              ),
            )}
          </ul>
        </Bloco>
      ))}
    </>
  );
}
