// Short messages at the bottom of the window: results of imports and actions, and errors.
import { useSyncExternalStore } from "react";
import { logNotice } from "./noticeLog";

export type Notice = { id: number; kind: "info" | "error"; text: string };
const LIFETIME_MS = 6000;

let list: Notice[] = [];
let next = 1;
const listeners = new Set<() => void>();
const emit = () => listeners.forEach((f) => f());

export function dismiss(id: number) {
  list = list.filter((n) => n.id !== id);
  emit();
}

export function notify(kind: Notice["kind"], text: string) {
  const n = { id: next++, kind, text };
  list = [...list.slice(-4), n];
  logNotice(kind, text);
  emit();
  setTimeout(() => dismiss(n.id), LIFETIME_MS);
}

export const useNotices = () =>
  useSyncExternalStore((f) => { listeners.add(f); return () => { listeners.delete(f); }; }, () => list);
