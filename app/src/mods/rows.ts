// Pure helpers for the mod table: search and drag reorder.
import type { ModRow } from "../types";

/** Rows whose name (in any language) or an author contains the query, ignoring case. */
export function filterMods(rows: ModRow[], query: string): ModRow[] {
  const q = query.trim().toLowerCase();
  if (!q) return rows;
  return rows.filter((r) => [...Object.values(r.name), ...r.authors].some((s) => s.toLowerCase().includes(q)));
}

/** The ids with the one at `from` moved to `to` (clamped to the list). */
export function moveRow(ids: string[], from: number, to: number): string[] {
  if (from < 0 || from >= ids.length) return ids;
  const out = [...ids];
  const [id] = out.splice(from, 1);
  out.splice(Math.max(0, Math.min(to, out.length)), 0, id);
  return out;
}
