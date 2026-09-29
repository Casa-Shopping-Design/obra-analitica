import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { expect, test, type Page } from "@playwright/test";
import { gerarCodigoTotp } from "./codigo-totp";

export const caminhoCadastrar = "/seguranca/segundo-fator/cadastrar";
export const caminhoVerificar = "/seguranca/segundo-fator/verificar";

// A chave fica na pasta de saída do Playwright, que ele limpa no começo de cada execução. Em memória ela
// se perderia quando uma falha reinicia o processo, e a nova tentativa cairia na verificação sem a chave.
function arquivoChave(): string {
  return path.join(test.info().project.outputDir, "chave-diretor.txt");
}

function lerChave(): string | null {
  try {
    return readFileSync(arquivoChave(), "utf8");
  } catch {
    return null;
  }
}

function gravarChave(chave: string) {
  mkdirSync(path.dirname(arquivoChave()), { recursive: true });
  writeFileSync(arquivoChave(), chave, { mode: 0o600 });
}

export async function cadastrarAparelho(pagina: Page) {
  await expect(pagina).toHaveURL(new RegExp(`${caminhoCadastrar}$`));
  await pagina.getByRole("button", { name: "Gerar código QR" }).click();
  await pagina.getByText("Não consegue ler o código? Digite a chave").click();
  const chave = (await pagina.locator("details code").innerText()).replace(/\s/g, "");
  gravarChave(chave);

  await pagina.locator("#codigo").fill(gerarCodigoTotp(chave));
  await pagina.getByRole("button", { name: "Confirmar e entrar" }).click();
  await pagina.waitForURL((url) => !url.pathname.startsWith("/seguranca"));
}

export async function confirmarCodigo(pagina: Page) {
  await expect(pagina).toHaveURL(new RegExp(`${caminhoVerificar}$`));
  const chave = lerChave();
  if (!chave) {
    throw new Error("O diretor de teste já tem aparelho cadastrado e a chave não é desta execução. Recrie os usuários de teste.");
  }
  await pagina.getByLabel("Código do aplicativo").fill(gerarCodigoTotp(chave));
  await pagina.getByRole("button", { name: "Confirmar", exact: true }).click();
  await pagina.waitForURL((url) => !url.pathname.startsWith("/seguranca"));
}

// Depois da senha o diretor cai no cadastro, na primeira vez, ou na verificação, nas seguintes.
export async function passarSegundoFator(pagina: Page) {
  await pagina.waitForURL((url) => url.pathname.startsWith("/seguranca"));
  if (new URL(pagina.url()).pathname === caminhoCadastrar) await cadastrarAparelho(pagina);
  else await confirmarCodigo(pagina);
}
