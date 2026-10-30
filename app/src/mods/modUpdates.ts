// Mod updates from GitHub (design: 2026-10-30-obsidian-mod-updates-design.md). A check runs only when
// the player asks, and what it finds lasts until the app closes.
import { useSyncExternalStore } from "react";
import { call, errorText, setSnapshot } from "../api";
import { withTask } from "../busy";
import { t } from "../i18n";
import { notify } from "../notices";
import type { CmdError, ImportBatch } from "../types";
import { importMessage } from "./dropImport";

type Checked = { id: string; version: string | null; error: CmdError | null };
export type ModUpdates = { checking: boolean; found: Record<string, string> };

let state: ModUpdates = { checking: false, found: {} };
const listeners = new Set<() => void>();
const set = (patch: Partial<ModUpdates>) => {
  state = { ...state, ...patch };
  listeners.forEach((f) => f());
};

/** The version to offer for a mod. A check goes stale once a newer copy has been imported by hand. */
export const offered = (found: ModUpdates["found"], mod: { id: string; version: string | null }): string | null =>
  found[mod.id] && found[mod.id] !== mod.version ? found[mod.id] : null;

/** The notice for a finished check. */
export function checkMessage(count: number): string {
  if (count === 0) return t("app.modUpdates.none");
  return count === 1 ? t("app.modUpdates.one") : t("app.modUpdates.many", count);
}

export async function checkModUpdates(names: Map<string, string>) {
  if (state.checking) return;
  set({ checking: true });
  try {
    const list = await withTask(t("app.task.check_mod_updates"), () => call<Checked[]>("check_mod_updates"));
    const found = Object.fromEntries(list.flatMap((c) => (c.version ? [[c.id, c.version]] : [])));
    set({ checking: false, found });
    const failed = list.filter((c) => c.error);
    if (failed.length < list.length) notify("info", checkMessage(Object.keys(found).length));
    for (const c of failed) notify("error", t("app.modUpdates.failed", names.get(c.id) ?? c.id, errorText(c.error)));
  } catch (e) {
    set({ checking: false });
    notify("error", errorText(e));
  }
}

export async function updateMod(id: string, name: string) {
  try {
    const b = await withTask(t("app.task.update_mod", name), () => call<ImportBatch>("update_mod", { id }), true);
    setSnapshot(b.snapshot);
    const found = { ...state.found };
    delete found[id];
    set({ found });
    for (const r of b.results) notify("info", importMessage(r));
  } catch (e) {
    notify("error", t("app.import.failed", name, errorText(e)));
  }
}

export const useModUpdates = () =>
  useSyncExternalStore((f) => { listeners.add(f); return () => { listeners.delete(f); }; }, () => state);
