// What the app is working on right now, shown in the status bar ("Importing X…").
import { useSyncExternalStore } from "react";

let current: string | null = null;
const listeners = new Set<() => void>();

export function setBusy(text: string | null) {
  current = text;
  listeners.forEach((f) => f());
}

export const useBusy = () =>
  useSyncExternalStore((f) => { listeners.add(f); return () => { listeners.delete(f); }; }, () => current);
