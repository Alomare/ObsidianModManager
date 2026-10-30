// Importing mods: folders and .zip files dropped on the window or picked with the dialog.
import { getCurrentWebview } from "@tauri-apps/api/webview";
import { open } from "@tauri-apps/plugin-dialog";
import { call, errorText, setSnapshot } from "../api";
import { setBusy } from "../busy";
import { pick, t } from "../i18n";
import { notify } from "../notices";
import type { ImportBatch, ImportResult } from "../types";

/** The notice for one result: "Installed X 1.0.0", "Updated X 1.0.0 → 1.1.0", "Reinstalled X". */
export function importMessage(r: ImportResult): string {
  if (!r.ok) return t("app.import.failed", r.file, errorText(r.error));
  const name = pick(r.name, r.file);
  if (r.kind === "updated") return t("app.import.updated", name, r.oldVersion ?? "", r.version ?? "");
  if (r.kind === "reinstalled") return t("app.import.reinstalled", name);
  return t("app.import.installed", r.version ? `${name} ${r.version}` : name);
}

export async function importPaths(paths: string[]) {
  if (!paths.length) return;
  setBusy(t("app.import.working", paths.map((p) => p.split(/[\/]/).pop()).join(", ")));
  try {
    const b = await call<ImportBatch>("import_paths", { paths });
    setSnapshot(b.snapshot);
    for (const r of b.results) notify(r.ok ? "info" : "error", importMessage(r));
  } catch (e) {
    notify("error", errorText(e));
  } finally {
    setBusy(null);
  }
}

export async function pickAndImport(folder: boolean) {
  const picked = await open(folder ? { directory: true, multiple: true } : { multiple: true, filters: [{ name: t("app.mods.zipFilter"), extensions: ["zip"] }] });
  if (picked) await importPaths(Array.isArray(picked) ? picked : [picked]);
}

/** Calls `onHover` while files are dragged over the window, and imports them on drop. */
export function listenForDrops(onHover: (over: boolean) => void): () => void {
  let stop: (() => void) | null = null;
  let gone = false;
  getCurrentWebview()
    .onDragDropEvent((e) => {
      const p = e.payload;
      if (p.type === "enter" || p.type === "over") onHover(true);
      else onHover(false);
      if (p.type === "drop") importPaths(p.paths);
    })
    .then((f) => (gone ? f() : (stop = f)));
  return () => {
    gone = true;
    stop?.();
  };
}
