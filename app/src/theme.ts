// Appearance settings applied to the page: theme, navigation side, UI scale, text size, animations.
import type { AppSettings } from "./types";

export const TEXT_SIZES = { small: 0.9, normal: 1, large: 1.15 } as const;

const reducedQuery = () => (typeof matchMedia === "function" ? matchMedia("(prefers-reduced-motion: reduce)") : null);
export const systemReducesMotion = () => !!reducedQuery()?.matches;

/** Animations on unless switched off, or, with no choice made, unless Windows reduces motion. */
export const motionOn = (choice: boolean | null, reduced: boolean) => choice ?? !reduced;

export function applyAppearance(s: AppSettings, root: HTMLElement = document.documentElement, reduced = systemReducesMotion()) {
  root.dataset.theme = s.theme;
  root.dataset.nav = s.nav;
  root.dataset.motion = motionOn(s.motion, reduced) ? "on" : "off";
  root.style.setProperty("--scale", String(s.scale / 100));
  root.style.setProperty("--text", String(TEXT_SIZES[s.text]));
}
