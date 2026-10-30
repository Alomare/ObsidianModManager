// UI text from the shared catalogs in locales/ (app.* keys). English fills any gap.
import en from "../../locales/en.json";
import ptBR from "../../locales/pt-BR.json";
import zhCN from "../../locales/zh-CN.json";
import type { Localized } from "./types";

type Catalog = Record<string, string>;
export const CATALOGS: Record<string, Catalog> = { en, "pt-BR": ptBR, "zh-CN": zhCN };
export const LANGUAGES: [string, string][] = [["en", "English"], ["pt-BR", "Português (Brasil)"], ["zh-CN", "中文 (简体)"]];

/** The saved choice if there is a catalog for it, else the first system language we have (by exact
 *  code, then by the first part, so "pt-PT" finds pt-BR), else English. */
export function pickLanguage(saved: string | null | undefined, system: readonly string[]): string {
  if (saved && CATALOGS[saved]) return saved;
  for (const s of system) {
    if (CATALOGS[s]) return s;
    const base = s.split("-")[0].toLowerCase();
    const hit = Object.keys(CATALOGS).find((c) => c.split("-")[0].toLowerCase() === base);
    if (hit) return hit;
  }
  return "en";
}

/** `%s` placeholders take the arguments in order. */
export function translate(catalogs: Record<string, Catalog>, lang: string, key: string, args: (string | number)[]): string {
  const text = catalogs[lang]?.[key] ?? catalogs.en?.[key] ?? key;
  let i = 0;
  return text.replace(/%s/g, () => String(args[i++] ?? ""));
}

let current = "en";
export const setLanguage = (lang: string) => { current = CATALOGS[lang] ? lang : "en"; document.documentElement.lang = current; };
export const language = () => current;
export const t = (key: string, ...args: (string | number)[]) => translate(CATALOGS, current, key, args);

/** A mod's own text in the UI language, then English, then whatever it has. */
export function pick(map: Localized | null | undefined, fallback = ""): string {
  if (!map) return fallback;
  return map[current] ?? map.en ?? Object.values(map)[0] ?? fallback;
}
