import { catalogoViews } from "./catalogo-views";

// Aceita so um select sobre as views do catalogo (e app.centro_custo para resolver nomes de obra).
const permitidas = new Set([...catalogoViews.map((v) => v.nome), "app.centro_custo"]);
const proibidas = /\b(insert|update|delete|drop|alter|create|grant|truncate|copy|pg_|information_schema|auth\.)\b/i;

export function validarSql(sql: string): { ok: true; sql: string } | { ok: false; motivo: string } {
  const limpo = sql.trim().replace(/;+$/, "");
  if (!/^\s*(with\b|select\b)/i.test(limpo)) return { ok: false, motivo: "so select e permitido" };
  if (proibidas.test(limpo)) return { ok: false, motivo: "comando ou objeto proibido" };

  const referencias = [...limpo.matchAll(/\b(?:from|join)\s+([a-z_]+\.[a-z_]+)/gi)].map((m) => m[1].toLowerCase());
  const fora = referencias.filter((r) => !permitidas.has(r));
  if (fora.length) return { ok: false, motivo: `fora do catalogo: ${fora.join(", ")}` };

  const comLimite = /\blimit\s+\d+/i.test(limpo) ? limpo : `${limpo} limit 200`;
  return { ok: true, sql: comLimite };
}
