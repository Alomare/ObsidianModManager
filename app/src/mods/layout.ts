// The mod list as a tree: mods and folders at the top, mods inside folders. The load order is the
// tree read top to bottom. An empty folder has no place in the load order, so it comes last.
import type { Folder } from "../types";

export type Node = { kind: "mod"; id: string } | { kind: "folder"; folder: Folder; ids: string[] };
/** Where dropped mods go: a folder (or the top level, null) and the index inside it. */
export type Spot = { folder: string | null; index: number };
/** One line on screen. */
export type Line = { kind: "mod"; id: string; folder: string | null } | { kind: "folder"; folder: Folder; count: number };

export function toTree(entries: { id: string; folder: string | null }[], folders: Folder[]): Node[] {
  const out: Node[] = [];
  const open = new Map<string, Node & { kind: "folder" }>();
  for (const e of entries) {
    const f = e.folder && folders.find((x) => x.id === e.folder);
    if (!f) {
      out.push({ kind: "mod", id: e.id });
      continue;
    }
    let node = open.get(f.id);
    if (!node) {
      node = { kind: "folder", folder: f, ids: [] };
      open.set(f.id, node);
      out.push(node);
    }
    node.ids.push(e.id);
  }
  for (const f of folders) if (!open.has(f.id)) out.push({ kind: "folder", folder: f, ids: [] });
  return out;
}

export const flatten = (tree: Node[]): string[] => tree.flatMap((n) => (n.kind === "mod" ? [n.id] : n.ids));

/** The folder of every mod in the tree. */
export const folderOf = (tree: Node[]): Map<string, string | null> =>
  new Map(tree.flatMap((n): [string, string | null][] => (n.kind === "mod" ? [[n.id, null]] : n.ids.map((id) => [id, n.folder.id]))));

/** What `set_order` needs to turn `before` into `after`: the order, and the mods that changed folder. */
export function changes(before: Node[], after: Node[]): { ids: string[]; moves: [string, string | null][] } {
  const was = folderOf(before);
  return { ids: flatten(after), moves: [...folderOf(after)].filter(([id, f]) => was.get(id) !== f) };
}

/** The lines on screen: closed folders hide their mods. */
export const lines = (tree: Node[]): Line[] =>
  tree.flatMap((n): Line[] =>
    n.kind === "mod"
      ? [{ kind: "mod", id: n.id, folder: null }]
      : [{ kind: "folder", folder: n.folder, count: n.ids.length }, ...(n.folder.collapsed ? [] : n.ids.map((id): Line => ({ kind: "mod", id, folder: n.folder.id })))],
  );

const without = (tree: Node[], ids: string[]): Node[] =>
  tree.filter((n) => n.kind !== "mod" || !ids.includes(n.id)).map((n) => (n.kind === "folder" ? { ...n, ids: n.ids.filter((id) => !ids.includes(id)) } : n));

/** Moves `ids` (in their current order) to `spot`, counted in the tree without them. */
export function moveMods(tree: Node[], ids: string[], spot: Spot): Node[] {
  const moving = flatten(tree).filter((id) => ids.includes(id));
  const out = without(tree, moving);
  if (spot.folder === null) {
    out.splice(Math.max(0, Math.min(spot.index, out.length)), 0, ...moving.map((id): Node => ({ kind: "mod", id })));
    return out;
  }
  return out.map((n) => {
    if (n.kind !== "folder" || n.folder.id !== spot.folder) return n;
    const next = [...n.ids];
    next.splice(Math.max(0, Math.min(spot.index, next.length)), 0, ...moving);
    return { ...n, ids: next };
  });
}

/** Moves a folder, mods and all, to `index` among the top level without it. */
export function moveFolder(tree: Node[], id: string, index: number): Node[] {
  const node = tree.find((n) => n.kind === "folder" && n.folder.id === id);
  if (!node) return tree;
  const out = tree.filter((n) => n !== node);
  out.splice(Math.max(0, Math.min(index, out.length)), 0, node);
  return out;
}

/** Where a mod is: the folder (null at the top level) and index there. */
export function spotOf(tree: Node[], id: string): Spot {
  for (const [i, n] of tree.entries()) {
    if (n.kind === "mod" && n.id === id) return { folder: null, index: i };
    if (n.kind === "folder" && n.ids.includes(id)) return { folder: n.folder.id, index: n.ids.indexOf(id) };
  }
  return { folder: null, index: tree.length };
}

/** One step up or down inside the mod's folder, or at the top level, where a folder is one step. */
export function nudge(tree: Node[], id: string, by: -1 | 1): Node[] {
  const at = spotOf(tree, id);
  return moveMods(tree, [id], { folder: at.folder, index: Math.max(0, at.index + by) });
}

/** To the very top or bottom of the list, out of any folder. */
export const toEnd = (tree: Node[], ids: string[], end: "top" | "bottom"): Node[] => moveMods(tree, ids, { folder: null, index: end === "top" ? 0 : Infinity });

/**
 * Where a drop lands when the pointer is in gap `gap` of `shown` (the lines without the dragged
 * ones: gap 0 is above the first). After a folder's last mod counts as inside it, except at the
 * very bottom. `onto` is a folder whose name line the pointer is over: the mods go in at the end of that folder.
 */
export function dropSpot(tree: Node[], shown: Line[], gap: number, onto: string | null, moving: string[]): Spot {
  const rest = without(tree, moving);
  if (onto) {
    const f = rest.find((n) => n.kind === "folder" && n.folder.id === onto);
    return { folder: onto, index: f && f.kind === "folder" ? f.ids.length : 0 };
  }
  const above = shown[gap - 1];
  const topIndex = (line: Line | undefined) => {
    if (!line) return 0;
    const i = rest.findIndex((n) => (line.kind === "folder" ? n.kind === "folder" && n.folder.id === line.folder.id : n.kind === "mod" && n.id === line.id));
    return i + 1;
  };
  if (gap >= shown.length || !above) return { folder: null, index: gap >= shown.length ? rest.length : 0 };
  if (above.kind === "folder") return above.folder.collapsed ? { folder: null, index: topIndex(above) } : { folder: above.folder.id, index: 0 };
  if (above.folder) {
    const f = rest.find((n) => n.kind === "folder" && n.folder.id === above.folder)!;
    return { folder: above.folder, index: f.kind === "folder" ? f.ids.indexOf(above.id) + 1 : 0 };
  }
  return { folder: null, index: topIndex(above) };
}

/** The top-level index for a folder dropped in gap `gap` of the lines without it; a gap inside another
 * folder rounds to after that folder. */
export function folderDropIndex(tree: Node[], gap: number, moving: string): number {
  const rest = tree.filter((n) => !(n.kind === "folder" && n.folder.id === moving));
  // The line each top-level node starts at.
  let line = 0;
  let index = 0;
  for (const n of rest) {
    if (line >= gap) break;
    line += n.kind === "mod" ? 1 : 1 + (n.folder.collapsed ? 0 : n.ids.length);
    index++;
  }
  return index;
}
