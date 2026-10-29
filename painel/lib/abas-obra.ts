export type AbaObra = { rotulo: string; destino: string };

// Rótulo curto para a faixa caber numa linha; o nome inteiro está no título de cada tela. A DRE e o imposto
// aparecem para diretor, financeiro e leitura, e a conferência só para os dois primeiros; cada tela confere de
// novo o perfil. O relatório é aba, mas a tela dele não mostra a faixa: é a versão para imprimir.
export function abasObra(id: string, acesso: { verDre: boolean; verConferencia: boolean }): AbaObra[] {
  const raiz = `/obras/${id}`;
  const telas = [
    ...(acesso.verDre
      ? [
          { rotulo: "DRE de viabilidade", caminho: "dre" },
          { rotulo: "Imposto", caminho: "imposto" },
        ]
      : []),
    { rotulo: "Unidades", caminho: "unidades" },
    { rotulo: "Estoque", caminho: "estoque" },
    { rotulo: "Simulação", caminho: "simulacao" },
    { rotulo: "Vendas e repasse", caminho: "vendas" },
    { rotulo: "Execução física", caminho: "execucao" },
    { rotulo: "Inadimplência", caminho: "inadimplencia" },
    ...(acesso.verConferencia ? [{ rotulo: "Conferência", caminho: "conferencia" }] : []),
    { rotulo: "Relatório", caminho: "relatorio" },
  ];
  return [
    { rotulo: "Resumo", destino: raiz },
    ...telas.map((tela) => ({ rotulo: tela.rotulo, destino: `${raiz}/${tela.caminho}` })),
  ];
}

// O resumo só fica ativo na própria tela da obra; as outras abas também nas telas filhas (o estudo da DRE).
export function abaAtiva(caminho: string, destino: string, raiz: string): boolean {
  if (destino === raiz) return caminho === raiz;
  return caminho === destino || caminho.startsWith(`${destino}/`);
}
