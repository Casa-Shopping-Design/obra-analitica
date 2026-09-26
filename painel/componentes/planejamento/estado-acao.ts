// Estado devolvido pelas Server Actions de planejamento e financiamento. Os valores digitados voltam
// para o formulário não perder o que a pessoa escreveu quando algo precisa ser corrigido.
export type EstadoAcao = {
  situacao: "inicial" | "sucesso" | "erro";
  mensagem: string;
  erros: Record<string, string>;
  valores: Record<string, string>;
};

export const estadoInicial: EstadoAcao = { situacao: "inicial", mensagem: "", erros: {}, valores: {} };

export function valoresDoFormulario(formulario: FormData): Record<string, string> {
  const valores: Record<string, string> = {};
  formulario.forEach((valor, chave) => {
    if (typeof valor === "string" && !chave.startsWith("$ACTION")) valores[chave] = valor.slice(0, 1000);
  });
  return valores;
}
