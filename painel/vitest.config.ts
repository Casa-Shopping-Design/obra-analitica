import { defineConfig } from "vitest/config";

// testes/e2e é do Playwright, que precisa do painel e do Supabase no ar.
export default defineConfig({
  test: {
    include: ["testes/**/*.test.ts"],
    exclude: ["testes/e2e/**", "node_modules/**"],
  },
});
