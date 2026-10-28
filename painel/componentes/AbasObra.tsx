import { ListaAbasObra } from "@/componentes/ListaAbasObra";
import { abasObra } from "@/lib/abas-obra";
import { perfilVeDre } from "@/lib/dre";
import { lerPerfilAtual } from "@/lib/consultas/perfil";
import { perfilVeConferencia } from "@/lib/consultas/resumo-origem";

// Uma leitura do perfil, reaproveitada na mesma requisição quando a tela já perguntou.
export async function AbasObra({ id }: { id: string }) {
  const perfil = await lerPerfilAtual().catch(() => null);
  return <ListaAbasObra abas={abasObra(id, { verDre: perfilVeDre(perfil), verConferencia: perfilVeConferencia(perfil) })} />;
}
