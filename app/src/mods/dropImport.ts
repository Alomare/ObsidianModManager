// Importing mods: folders and .zip files dropped on the window or picked with the dialog.
import { getCurrentWebview } from "@tauri-apps/api/webview";
import { open } from "@tauri-apps/plugin-dialog";
import { call, errorText, setSnapshot } from "../api";
import { withTask } from "../busy";
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
  const names = paths.map((p) => p.split(/[\\/]/).pop()).join(", ");
  try {
    const b = await withTask(t("app.import.working", names), () => call<ImportBatch>("import_paths", { paths }), true);
    setSnapshot(b.snapshot);
    for (const r of b.results) notify(r.ok ? "info" : "error", importMessage(r));
  } catch (e) {
    notify("error", errorText(e));
  }
}

export async function pickAndImport(folder: boolean) {
  const picked = await open(folder ? { directory: true, multiple: true } : { multiple: true, filters: [{ name: t("app.mods.zipFilter"), extensions: ["zip"] }] });
  if (picked) await importPaths(Array.isArray(picked) ? picked : [picked]);
}

/** Where the drop zone sits while files are dragged over the window, and whether the pointer is in it. */
export type DropState = { rect: DOMRect; inside: boolean } | null;

/**
 * Calls `onState` while files are dragged over the window, and imports them when they are dropped
 * on the element `zone` returns (the mod list). Drops anywhere else are ignored.
 */
export function listenForDrops(zone: () => Element | null, onEnter: () => void, onState: (s: DropState) => void): () => void {
  let stop: (() => void) | null = null;
  let gone = false;
  const at = (x: number, y: number) => {
    const rect = zone()?.getBoundingClientRect();
    if (!rect || !rect.width) return null;
    // Tauri reports the pointer in physical pixels.
    const px = x / devicePixelRatio, py = y / devicePixelRatio;
    return { rect, inside: px >= rect.left && px <= rect.right && py >= rect.top && py <= rect.bottom };
  };
  getCurrentWebview()
    .onDragDropEvent((e) => {
      const p = e.payload;
      if (p.type === "enter") onEnter();
      if (p.type === "enter" || p.type === "over") return onState(at(p.position.x, p.position.y));
      onState(null);
      if (p.type === "drop" && at(p.position.x, p.position.y)?.inside) importPaths(p.paths);
    })
    .then((f) => (gone ? f() : (stop = f)));
  return () => {
    gone = true;
    stop?.();
  };
}
