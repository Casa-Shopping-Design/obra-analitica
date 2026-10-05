import { defineConfig } from "vitest/config";

// testes/e2e é do Playwright, que precisa do painel e do Supabase no ar.
export default defineConfig({
  // Os componentes importam com "@/", como no Next; sem isto o teste que desenha a tela não acha o módulo.
  resolve: { tsconfigPaths: true },
  test: {
    include: ["testes/**/*.test.ts"],
    exclude: ["testes/e2e/**", "node_modules/**"],
  },
});
