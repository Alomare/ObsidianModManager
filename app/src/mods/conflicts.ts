// Conflicts for an order that is not saved yet (a drag under way), so the view shows the winner
// change as rows move.
import type { ConflictRow } from "../types";

/** Each conflict with its mods in `order` and the last one as the winner. */
export function winners(rows: ConflictRow[], order: string[]): ConflictRow[] {
  const pos = (id: string) => order.indexOf(id);
  return rows.map((r) => {
    const mods = [...r.mods].sort((a, b) => pos(a) - pos(b));
    return { ...r, mods, winner: mods[mods.length - 1] };
  });
}

export type ConflictGroup = { mods: string[]; winner: string; resources: string[] };

/** Conflicts between the same mods, with the same winner, as one entry listing the files. */
export function groupConflicts(rows: ConflictRow[]): ConflictGroup[] {
  const groups = new Map<string, ConflictGroup>();
  for (const r of rows) {
    const k = `${r.mods.join("\n")}\n${r.winner}`;
    const g = groups.get(k) ?? { mods: r.mods, winner: r.winner, resources: [] };
    g.resources.push(r.resource);
    groups.set(k, g);
  }
  return [...groups.values()];
}
