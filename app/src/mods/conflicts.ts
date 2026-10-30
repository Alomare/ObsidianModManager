// Conflicts as people read them: who overrides whom. `winners` works them out for an order that
// is not saved yet (a drag under way), so the view follows the rows as they move.
import type { ConflictRow } from "../types";

/** Each conflict with its mods in `order` and the last one as the winner. */
export function winners(rows: ConflictRow[], order: string[]): ConflictRow[] {
  const pos = (id: string) => order.indexOf(id);
  return rows.map((r) => {
    const mods = [...r.mods].sort((a, b) => pos(a) - pos(b));
    return { ...r, mods, winner: mods[mods.length - 1] };
  });
}

export type Override = { winner: string; loser: string; resources: string[] };

/** Who overrides whom: one entry per winner and loser, with the files the winner takes. */
export function overrides(rows: ConflictRow[]): Override[] {
  const pairs = new Map<string, Override>();
  for (const r of rows) {
    for (const loser of r.mods) {
      if (loser === r.winner) continue;
      const k = `${r.winner}
${loser}`;
      const o = pairs.get(k) ?? { winner: r.winner, loser, resources: [] };
      o.resources.push(r.resource);
      pairs.set(k, o);
    }
  }
  return [...pairs.values()];
}

/** For one mod: the mods it overrides and the mods that override it, each with a file count. */
export function conflictsOf(id: string, rows: ConflictRow[]) {
  const all = overrides(rows);
  return {
    overrides: all.filter((o) => o.winner === id).map((o): [string, number] => [o.loser, o.resources.length]),
    overriddenBy: all.filter((o) => o.loser === id).map((o): [string, number] => [o.winner, o.resources.length]),
  };
}
