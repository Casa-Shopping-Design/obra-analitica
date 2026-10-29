// Regra pura do modo de manutenção, para o proxy e os testes usarem a mesma decisão.
export const caminhoManutencao = "/manutencao";

// A saúde continua respondendo, para o monitor distinguir manutenção de queda.
const caminhosLiberados: ReadonlySet<string> = new Set([caminhoManutencao, "/api/saude"]);

export type DecisaoManutencao = "seguir" | "pagina" | "api";

// Só "1" liga. Valor vazio, ausente ou qualquer outro mantém o painel no ar, para um erro de digitação na
// variável não derrubar a produção.
export function manutencaoLigada(valor: string | undefined): boolean {
  return valor === "1";
}

export function decidirManutencao(caminho: string, ligada: boolean): DecisaoManutencao {
  if (!ligada || caminhosLiberados.has(caminho)) return "seguir";
  return caminho.startsWith("/api/") ? "api" : "pagina";
}
