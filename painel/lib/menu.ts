import { perfilVeEmpresas } from "./empresa";

export type ItemMenu = { rotulo: string; destino: string };

const itensObra: ItemMenu[] = [
  { rotulo: "Visão geral", destino: "/" },
  { rotulo: "DRE de viabilidade", destino: "/dre" },
  { rotulo: "Obras", destino: "/obras" },
  { rotulo: "Mapa de unidades", destino: "/unidades" },
];

const itemEmpresas: ItemMenu = { rotulo: "Empresas", destino: "/empresas" };
const itemAssistente: ItemMenu = { rotulo: "Assistente", destino: "/assistente" };

// perfil é o código cru (diretor, financeiro, leitura, gerente_obra). Esconder o item não protege a rota:
// cada tela de empresa confere o perfil de novo e o RLS filtra as linhas.
export function itensMenu(perfil: string | null): ItemMenu[] {
  return [...itensObra, ...(perfilVeEmpresas(perfil) ? [itemEmpresas] : []), itemAssistente];
}

export function itemAtivo(caminho: string, destino: string): boolean {
  return destino === "/" ? caminho === "/" : caminho === destino || caminho.startsWith(`${destino}/`);
}
