// The shapes the Rust side sends (app/src-tauri/src/snapshot.rs and app_settings.rs).

export type Localized = Record<string, string>;

export type OptionRow = {
  id: string; kind: "toggle" | "number" | "choice" | "key" | "color";
  label: Localized; description: Localized; default: unknown; value: unknown;
  min: number | null; max: number | null; step: number | null; choices: string[];
  deploy: boolean;
};
export type KeyRow = { id: string; label: Localized; default: string; key: string | null; clash: string[] };
export type ImportInfo = { date: string; file: string };
export type ModRow = {
  id: string; name: Localized; description: Localized; authors: string[];
  version: string | null; scope: "client" | "session"; bundled: boolean; on: boolean;
  options: OptionRow[]; keybinds: KeyRow[]; files: string[]; overlaps: string[];
  import: ImportInfo | null; source: string | null;
};
export type ConflictRow = { resource: string; mods: string[]; winner: string };
export type ChangesWaiting = "UpToDate" | "Waiting" | "Vanilla";
export type GameState = "supported" | "unknown" | "running" | "notFound";
export type Snapshot = {
  mods: ModRow[]; profile: string; profiles: string[]; consent: boolean; conflicts: ConflictRow[];
  changes: ChangesWaiting; game: GameState; gameDir: string | null; crashCulprit: string | null;
  portable: boolean; version: string;
};

export type AppSettings = {
  theme: "default" | "dark" | "light"; nav: "top" | "left"; scale: 90 | 100 | 110 | 125;
  text: "small" | "normal" | "large"; motion: boolean | null; language: string | null;
  updates: "manual" | "prompt" | "auto"; gameDir: string | null;
};

export type CmdError = { code: string; message: string };
