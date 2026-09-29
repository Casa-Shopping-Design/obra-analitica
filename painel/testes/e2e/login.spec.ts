import { expect, test, type Page } from "@playwright/test";
import { caminhoCadastrar, caminhoVerificar, passarSegundoFator } from "./segundo-fator";

// Usuários do Supabase local, criados pelo CI a cada execução. Nunca apontar para o projeto remoto.
const diretor = { email: process.env.E2E_EMAIL_DIRETOR ?? "", senha: process.env.E2E_SENHA_DIRETOR ?? "" };
const gerente = { email: process.env.E2E_EMAIL_GERENTE ?? "", senha: process.env.E2E_SENHA_GERENTE ?? "" };

test.skip(!diretor.email || !gerente.email, "E2E_EMAIL_DIRETOR e E2E_EMAIL_GERENTE não definidas");

// O diretor cadastra o aparelho num teste e os seguintes dependem desse cadastro.
test.describe.configure({ mode: "serial" });

async function entrar(pagina: Page, credenciais: { email: string; senha: string }) {
  await pagina.goto("/entrar");
  await pagina.getByLabel("E-mail").fill(credenciais.email);
  await pagina.getByLabel("Senha").fill(credenciais.senha);
  await pagina.getByRole("button", { name: "Entrar" }).click();
  await pagina.waitForURL((url) => url.pathname !== "/entrar");
}

async function entrarComoDiretor(pagina: Page) {
  await entrar(pagina, diretor);
  await passarSegundoFator(pagina);
}

test("quem não entrou é levado para a tela de entrada", async ({ page }) => {
  await page.goto("/obras");
  await expect(page).toHaveURL(/\/entrar$/);
});

test("senha errada mostra o que fazer, sem detalhe técnico", async ({ page }) => {
  await page.goto("/entrar");
  await page.getByLabel("E-mail").fill(diretor.email);
  await page.getByLabel("Senha").fill(`${diretor.senha}-errada`);
  await page.getByRole("button", { name: "Entrar" }).click();
  // O anunciador de rota do Next também tem role="alert", então o seletor filtra pelo texto.
  const aviso = page.getByRole("alert").filter({ hasText: "E-mail ou senha incorretos" });
  await expect(aviso).toHaveText("E-mail ou senha incorretos. Confira e tente de novo.");
});

test("diretor só com a senha não chega ao painel nem ao assistente", async ({ page }) => {
  await entrar(page, diretor);
  await expect(page).toHaveURL(new RegExp(`${caminhoCadastrar}$`));

  for (const caminho of ["/", "/obras", "/assistente"]) {
    await page.goto(caminho);
    await expect(page).toHaveURL(new RegExp(`${caminhoCadastrar}$`));
  }

  const resposta = await page.request.post("/api/assistente", {
    data: { pergunta: "Quanto dinheiro próprio cada obra precisa no pior momento?" },
  });
  expect(resposta.status()).toBe(403);
});

test("diretor cadastra o aplicativo, vê as três obras e a data da carga", async ({ page }) => {
  await entrarComoDiretor(page);
  await page.goto("/obras");
  for (const obra of ["Residencial Aurora", "Parque das Aguas", "Torre Comercial Sul"]) {
    await expect(page.getByRole("link", { name: obra })).toBeVisible();
  }
  await expect(page.getByText(/Dados carregados em \d{2}\/\d{2}\/\d{4} \d{2}:\d{2}/)).toBeVisible();
});

test("diretor com aparelho cadastrado não entra com código errado", async ({ page }) => {
  await entrar(page, diretor);
  await expect(page).toHaveURL(new RegExp(`${caminhoVerificar}$`));

  await page.getByLabel("Código do aplicativo").fill("000000");
  await page.getByRole("button", { name: "Confirmar", exact: true }).click();
  const aviso = page.getByRole("alert").filter({ hasText: "Código incorreto" });
  await expect(aviso).toHaveText("Código incorreto ou vencido. Espere o aplicativo gerar um código novo e tente de novo.");

  await page.goto("/obras");
  await expect(page).toHaveURL(new RegExp(`${caminhoVerificar}$`));
  await page.goto(caminhoCadastrar);
  await expect(page).toHaveURL(new RegExp(`${caminhoVerificar}$`));
});

test("gerente da Aurora entra sem segundo fator e não vê a Parque das Aguas, nem pelo endereço direto", async ({ browser }) => {
  const contextoDiretor = await browser.newContext();
  const paginaDiretor = await contextoDiretor.newPage();
  await entrarComoDiretor(paginaDiretor);
  await paginaDiretor.goto("/obras");
  const enderecoParque = await paginaDiretor.getByRole("link", { name: "Parque das Aguas" }).getAttribute("href");
  await contextoDiretor.close();
  expect(enderecoParque).toMatch(/^\/obras\/[0-9a-f-]{36}$/);

  const contextoGerente = await browser.newContext();
  const paginaGerente = await contextoGerente.newPage();
  await entrar(paginaGerente, gerente);
  expect(new URL(paginaGerente.url()).pathname.startsWith("/seguranca")).toBe(false);

  // Com uma obra só, a lista leva direto à Aurora.
  await paginaGerente.goto("/obras");
  await expect(paginaGerente.getByRole("heading", { level: 1 })).toContainText("Residencial Aurora");

  await paginaGerente.goto("/");
  await expect(paginaGerente.getByText("Parque das Aguas")).toHaveCount(0);

  await paginaGerente.goto(enderecoParque ?? "/");
  await expect(paginaGerente.getByRole("heading", { level: 1 })).toHaveText("Obra não encontrada ou sem permissão.");
  await expect(paginaGerente.getByText("Parque das Aguas")).toHaveCount(0);
  await contextoGerente.close();
});
