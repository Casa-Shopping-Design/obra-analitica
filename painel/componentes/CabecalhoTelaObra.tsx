import Link from "next/link";

// Topo comum das telas de detalhe da obra: volta para a obra, diz a tela e o nome da obra.
export function CabecalhoTelaObra({ id, tela, obra, nota }: { id: string; tela: string; obra: string; nota?: string }) {
  return (
    <header className="flex flex-col gap-1">
      <Link href={`/obras/${id}`} className="w-fit text-sm text-suave underline underline-offset-4 hover:text-texto">
        Voltar para a obra
      </Link>
      <p className="text-sm text-suave">{tela}</p>
      <h1 className="font-serif text-[34px] leading-tight font-semibold">{obra}</h1>
      {nota && <p className="text-sm text-suave">{nota}</p>}
    </header>
  );
}

// Erro de carga ou obra fora do perfil: título da tela, o aviso e o caminho de volta para a lista.
export function AvisoTelaObra({ tela, mensagem, erro = false }: { tela: string; mensagem: string; erro?: boolean }) {
  return (
    <>
      <h1 className="font-serif text-[34px] font-semibold">{tela}</h1>
      <p role={erro ? "alert" : undefined} className={erro ? "text-alerta" : undefined}>
        {mensagem}
      </p>
      <Link href="/obras" className="w-fit text-sm underline underline-offset-4 hover:text-menu">
        Ver a lista de obras
      </Link>
    </>
  );
}
