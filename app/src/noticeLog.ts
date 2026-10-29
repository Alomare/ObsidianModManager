// Every notice shown, kept to read again from the status bar: the last 100, oldest first, also after
// a restart (browser storage of this window). The log never shows anything by itself.
import { useSyncExternalStore } from "react";

export type Logged = { id: number; at: number; kind: "info" | "error"; text: string };
const KEY = "obsidian.notifications";
const MAX = 100;
/** The same text again this soon (a button pressed twice) updates the last entry instead. */
const SAME_MS = 5000;

/** The log with one more notice, at most MAX long. */
export function addTo(log: Logged[], kind: Logged["kind"], text: string, at: number): Logged[] {
  const last = log[log.length - 1];
  if (last && last.text === text && last.kind === kind && at - last.at < SAME_MS) return [...log.slice(0, -1), { ...last, at }];
  return [...log, { id: (last?.id ?? 0) + 1, at, kind, text }].slice(-MAX);
}

function load(): Logged[] {
  try {
    const v = JSON.parse(localStorage.getItem(KEY) ?? "[]");
    return Array.isArray(v) ? v.filter((x) => x && typeof x.text === "string" && typeof x.at === "number") : [];
  } catch {
    return [];
  }
}

let entries: Logged[] = load();
const listeners = new Set<() => void>();

export function logNotice(kind: Logged["kind"], text: string) {
  entries = addTo(entries, kind, text, Date.now());
  try { localStorage.setItem(KEY, JSON.stringify(entries)); } catch { /* storage off: this session keeps them */ }
  listeners.forEach((f) => f());
}

export const useNoticeLog = () =>
  useSyncExternalStore((f) => { listeners.add(f); return () => { listeners.delete(f); }; }, () => entries);
