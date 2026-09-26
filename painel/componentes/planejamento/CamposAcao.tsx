import type { EstadoAcao } from "@/componentes/planejamento/estado-acao";

const classeCampo = "min-h-11 w-full min-w-0 rounded-lg border bg-superficie px-3";

// Campo com rótulo, ajuda e erro ligados por aria-describedby. Valor inicial vem do que a pessoa já
// digitou (quando a ação devolveu erro) ou do padrão da tela.
export function CampoAcao({
  prefixo,
  nome,
  rotulo,
  estado,
  padrao = "",
  tipo = "text",
  opcoes,
  ajuda,
  obrigatorio = false,
  rotuloOculto = false,
}: {
  prefixo: string;
  nome: string;
  rotulo: string;
  estado: EstadoAcao;
  padrao?: string;
  tipo?: "text" | "date" | "month" | "decimal" | "textarea" | "checkbox";
  opcoes?: { valor: string; rotulo: string }[];
  ajuda?: string;
  obrigatorio?: boolean;
  rotuloOculto?: boolean;
}) {
  const id = `${prefixo}-${nome}`;
  const erro = estado.erros[nome];
  const valor = estado.situacao === "erro" ? (estado.valores[nome] ?? "") : padrao;
  const descricoes = [ajuda ? `${id}-ajuda` : null, erro ? `${id}-erro` : null].filter(Boolean).join(" ") || undefined;
  const comum = {
    id,
    name: nome,
    "aria-invalid": erro ? true : undefined,
    "aria-describedby": descricoes,
    "aria-required": obrigatorio || undefined,
  };
  const borda = erro ? "border-alerta" : "border-borda";

  if (tipo === "checkbox") {
    return (
      <div className="flex min-w-0 flex-col gap-1.5">
        <label htmlFor={id} className="flex min-h-11 items-center gap-2 text-sm font-medium">
          <input {...comum} type="checkbox" value="sim" defaultChecked={valor === "sim"} className="size-5" />
          {rotulo}
        </label>
        {erro && (
          <p id={`${id}-erro`} className="text-sm text-alerta">
            {erro}
          </p>
        )}
      </div>
    );
  }

  return (
    <div className="flex min-w-0 flex-col gap-1.5">
      <label htmlFor={id} className={rotuloOculto ? "sr-only" : "text-sm font-medium"}>
        {rotulo}
        {obrigatorio && <span className="text-suave"> (obrigatório)</span>}
      </label>
      {opcoes ? (
        <select {...comum} defaultValue={valor} className={`${classeCampo} ${borda}`}>
          {opcoes.map((opcao) => (
            <option key={opcao.valor} value={opcao.valor}>
              {opcao.rotulo}
            </option>
          ))}
        </select>
      ) : tipo === "textarea" ? (
        <textarea {...comum} defaultValue={valor} rows={2} className={`${classeCampo} ${borda} py-2`} />
      ) : (
        <input
          {...comum}
          type={tipo === "decimal" ? "text" : tipo}
          inputMode={tipo === "decimal" ? "decimal" : undefined}
          defaultValue={valor}
          className={`${classeCampo} ${borda} ${tipo === "decimal" ? "text-right tabular-nums" : ""}`}
        />
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

// Região sempre presente: leitor de tela anuncia sucesso e erro quando o texto muda.
export function MensagemAcao({ estado }: { estado: EstadoAcao }) {
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

export function BotaoAcao({ enviando, texto, textoEnviando }: { enviando: boolean; texto: string; textoEnviando: string }) {
  return (
    <button
      type="submit"
      disabled={enviando}
      className="min-h-11 w-fit cursor-pointer rounded-lg bg-menu px-5 font-semibold text-menu-texto hover:bg-menu-ativo disabled:cursor-wait disabled:opacity-70"
    >
      {enviando ? textoEnviando : texto}
    </button>
  );
}
