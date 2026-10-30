// What the app is working on, shown in the status bar ("Importing X…"). Several tasks can run at
// once; the newest one shows. A locking task (deploy, import) also locks Purge, Deploy and Play.
import { useSyncExternalStore } from "react";

type Task = { id: number; text: string; lock: boolean };
type State = { text: string | null; locked: boolean };

let tasks: Task[] = [];
let state: State = { text: null, locked: false };
let next = 1;
const listeners = new Set<() => void>();

function publish() {
  state = { text: tasks.at(-1)?.text ?? null, locked: tasks.some((t) => t.lock) };
  listeners.forEach((f) => f());
}

/** Shows `text` until the returned function is called. */
export function startTask(text: string, lock = false): () => void {
  const task = { id: next++, text, lock };
  tasks = [...tasks, task];
  publish();
  return () => {
    tasks = tasks.filter((t) => t.id !== task.id);
    publish();
  };
}

/** Runs `work`, showing `text` only when it takes longer than a blink. */
export async function withTask<T>(text: string, work: () => Promise<T>, lock = false): Promise<T> {
  let end: (() => void) | null = null;
  const timer = setTimeout(() => (end = startTask(text, lock)), lock ? 0 : 120);
  try {
    return await work();
  } finally {
    clearTimeout(timer);
    (end as (() => void) | null)?.();
  }
}

const subscribe = (f: () => void) => {
  listeners.add(f);
  return () => {
    listeners.delete(f);
  };
};
export const useBusy = () => useSyncExternalStore(subscribe, () => state).text;
export const useLocked = () => useSyncExternalStore(subscribe, () => state).locked;
