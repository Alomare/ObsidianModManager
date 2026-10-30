// Pure helpers for the mod table: search.
import type { ModRow } from "../types";

/** Rows whose name (in any language) or an author contains the query, ignoring case. */
export function filterMods(rows: ModRow[], query: string): ModRow[] {
  const q = query.trim().toLowerCase();
  if (!q) return rows;
  return rows.filter((r) => [...Object.values(r.name), ...r.authors].some((s) => s.toLowerCase().includes(q)));
}
