import { defineConfig, devices } from "@playwright/test";

// Roda contra o build de produção servido localmente, com o Supabase local do CI.
export default defineConfig({
  testDir: "./testes/e2e",
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [["list"], ["html", { open: "never" }]] : "list",
  use: {
    baseURL: "http://localhost:3000",
    trace: "retain-on-failure",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  webServer: {
    command: "npm run start",
    url: "http://localhost:3000/entrar",
    reuseExistingServer: !process.env.CI,
    timeout: 60_000,
  },
});
