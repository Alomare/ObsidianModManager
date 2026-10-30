// What a mod needs and what needs it, for the Dependencies tab. Only direct links: each row opens
// the next mod.
import type { ModRow } from "../types";

export type Dep = { id: string; state: "on" | "off" | "missing" };

export function dependencies(mod: ModRow, mods: ModRow[]): { needs: Dep[]; neededBy: Dep[] } {
  const on = new Map(mods.map((m) => [m.id, m.on]));
  const state = (id: string): Dep["state"] => (!on.has(id) ? "missing" : on.get(id) ? "on" : "off");
  return {
    needs: mod.requires.map((id) => ({ id, state: state(id) })),
    neededBy: mods.filter((m) => m.requires.includes(mod.id)).map((m) => ({ id: m.id, state: state(m.id) })),
  };
}
