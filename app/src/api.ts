// Calls into the Rust side, and the one snapshot of the library and profile the UI renders.
import { invoke } from "@tauri-apps/api/core";
import { useSyncExternalStore } from "react";
import { withTask } from "./busy";
import { t } from "./i18n";
import { notify } from "./notices";
import type { CmdError, Snapshot } from "./types";

export const call = <T,>(cmd: string, args?: Record<string, unknown>) => invoke<T>(cmd, args);

const isCmdError = (e: unknown): e is CmdError => typeof e === "object" && e !== null && "code" in e && "message" in e;

/** A core error in the UI language when the catalog has it (`app.error.<code>`), else the English text. */
export function errorText(e: unknown): string {
  if (!isCmdError(e)) return String(e);
  const key = `app.error.${e.code}`;
  const text = t(key);
  return text === key ? e.message : text;
}

let snap: Snapshot | null = null;
const listeners = new Set<() => void>();
export function setSnapshot(s: Snapshot) {
  snap = s;
  listeners.forEach((f) => f());
}
export const useSnapshot = () =>
  useSyncExternalStore((f) => { listeners.add(f); return () => { listeners.delete(f); }; }, () => snap);

export async function refresh() {
  try { setSnapshot(await call<Snapshot>("snapshot")); } catch (e) { notify("error", errorText(e)); }
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** Asks for the first snapshot until one arrives: right after a start a call can hang. */
export async function loadSnapshot() {
  while (!snap) {
    refresh();
    await sleep(2500);
  }
}

/** The status bar line while a command runs (`app.task.<cmd>`), "Working" for the others. */
export function taskText(cmd: string): string {
  const text = t(`app.task.${cmd}`);
  return text === `app.task.${cmd}` ? t("app.task.working") : text;
}

/** Runs a command that returns a snapshot. Errors become a notice; the result says whether it worked.
 * A command that takes longer than a blink shows in the status bar. */
export async function run(cmd: string, args?: Record<string, unknown>): Promise<boolean> {
  try {
    setSnapshot(await withTask(taskText(cmd), () => call<Snapshot>(cmd, args)));
    return true;
  } catch (e) {
    notify("error", errorText(e));
    return false;
  }
}
