// Obsidian's own updates through the updater plugin: it reads latest.json from the newest GitHub
// release, compares versions, downloads the installer, checks the signature and runs it (the app
// closes while it installs and opens again on the new version). Portable copies never install:
// they show the new version with a link to the releases page.
import { check, type Update } from "@tauri-apps/plugin-updater";
import { useSyncExternalStore } from "react";
import type { AppSettings } from "./types";

export type UpdateState = {
  phase: "idle" | "checking" | "none" | "found" | "failed" | "downloading" | "installing";
  version: string | null;
  /** What the new version changes, from its release. */
  notes: string | null;
  error: string | null;
  got: number;
  total: number;
};

let state: UpdateState = { phase: "idle", version: null, notes: null, error: null, got: 0, total: 0 };
let found: Update | null = null;
const listeners = new Set<() => void>();
const set = (patch: Partial<UpdateState>) => {
  state = { ...state, ...patch };
  listeners.forEach((f) => f());
};

export async function checkForUpdate(): Promise<boolean> {
  if (state.phase === "checking" || state.phase === "downloading" || state.phase === "installing") return state.phase !== "checking" && !!found;
  set({ phase: "checking", error: null });
  try {
    found = await check({ timeout: 20000 });
    set(found ? { phase: "found", version: found.version, notes: found.body?.trim() || null } : { phase: "none", version: null, notes: null });
    return !!found;
  } catch (e) {
    set({ phase: "failed", error: e instanceof Error ? e.message : String(e) });
    return false;
  }
}

export async function installUpdate() {
  if (!found) return;
  set({ phase: "downloading", got: 0, total: 0, error: null });
  try {
    await found.downloadAndInstall((ev) => {
      if (ev.event === "Started") set({ total: ev.data.contentLength ?? 0 });
      else if (ev.event === "Progress") set({ got: state.got + ev.data.chunkLength });
      else set({ phase: "installing" });
    });
  } catch (e) {
    set({ phase: "found", error: e instanceof Error ? e.message : String(e) });
  }
}

/** The check at startup. Returns "ask" when the window should ask before installing. */
export async function startupUpdate(mode: AppSettings["updates"], portable: boolean): Promise<"ask" | null> {
  if (!(await checkForUpdate()) || portable || mode === "manual") return null;
  if (mode === "auto") {
    await installUpdate();
    return null;
  }
  return "ask";
}

export const useUpdates = () =>
  useSyncExternalStore((f) => { listeners.add(f); return () => { listeners.delete(f); }; }, () => state);
