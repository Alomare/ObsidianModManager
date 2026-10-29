// The app settings (app.json through the Rust side), applied to the page as they change.
import { useSyncExternalStore } from "react";
import { call, errorText } from "./api";
import { pickLanguage, setLanguage } from "./i18n";
import { notify } from "./notices";
import { applyAppearance } from "./theme";
import type { AppSettings } from "./types";

let current: AppSettings | null = null;
const listeners = new Set<() => void>();

function apply(s: AppSettings) {
  current = s;
  applyAppearance(s);
  setLanguage(pickLanguage(s.language, navigator.languages ?? [navigator.language]));
  listeners.forEach((f) => f());
}

export async function loadSettings() {
  apply(await call<AppSettings>("get_app_settings"));
}

export async function updateSettings(patch: Partial<AppSettings>) {
  if (!current) return;
  try { apply(await call<AppSettings>("set_app_settings", { settings: { ...current, ...patch } })); } catch (e) { notify("error", errorText(e)); }
}

export const useAppSettings = () =>
  useSyncExternalStore((f) => { listeners.add(f); return () => { listeners.delete(f); }; }, () => current);
