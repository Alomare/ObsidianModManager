import { describe, expect, it } from "vitest";
import { changes, dropSpot, flatten, folderDropIndex, lines, moveFolder, moveMods, nudge, toEnd, toTree } from "../mods/layout";
import type { Folder } from "../types";

const F = (id: string, collapsed = false, locked = false): Folder => ({ id, name: id.toUpperCase(), color: "#fff", collapsed, locked });
const e = (id: string, folder: string | null = null) => ({ id, folder });
// a, [f1: b c], d, [f2: empty]
const tree = () => toTree([e("a"), e("b", "f1"), e("c", "f1"), e("d")], [F("f1"), F("f2")]);

describe("folder layout", () => {
  it("builds the tree with empty folders last", () => {
    const t = tree();
    expect(t.map((n) => (n.kind === "mod" ? n.id : n.folder.id))).toEqual(["a", "f1", "d", "f2"]);
    expect(flatten(t)).toEqual(["a", "b", "c", "d"]);
    expect(lines(t).length).toBe(6);
    expect(lines(toTree([e("b", "f1")], [F("f1", true)]))).toEqual([{ kind: "folder", folder: F("f1", true), count: 1 }]);
  });

  it("moves mods into folders and reports what changed", () => {
    const t = tree();
    const into = moveMods(t, ["d", "a"], { folder: "f2", index: 0 });
    expect(changes(t, into)).toEqual({ ids: ["b", "c", "a", "d"], moves: [["a", "f2"], ["d", "f2"]] });
    expect(flatten(toEnd(t, ["c"], "top"))).toEqual(["c", "a", "b", "d"]);
    expect(changes(t, toEnd(t, ["c"], "top")).moves).toEqual([["c", null]]);
  });

  it("nudges inside a folder and past a whole folder at the top level", () => {
    expect(flatten(nudge(tree(), "c", -1))).toEqual(["a", "c", "b", "d"]);
    expect(flatten(nudge(tree(), "a", 1))).toEqual(["b", "c", "a", "d"]);
    expect(flatten(moveFolder(tree(), "f1", 0))).toEqual(["b", "c", "a", "d"]);
  });

  it("finds where a dragged mod lands", () => {
    const t = tree();
    const shown = lines(t).filter((l) => !(l.kind === "mod" && l.id === "d"));
    // a | f1 | b | c | f2
    expect(dropSpot(t, shown, 0, null, ["d"])).toEqual({ folder: null, index: 0 });
    expect(dropSpot(t, shown, 2, null, ["d"])).toEqual({ folder: "f1", index: 0 });
    expect(dropSpot(t, shown, 4, null, ["d"])).toEqual({ folder: "f1", index: 2 });
    expect(dropSpot(t, shown, 5, null, ["d"])).toEqual({ folder: null, index: 3 });
    expect(dropSpot(t, shown, 1, "f2", ["d"])).toEqual({ folder: "f2", index: 0 });
  });

  it("keeps locked folders in place, whole and closed to new mods", () => {
    // [obsidian: q] a [f1 (locked): b c] d
    const t = toTree([e("q", "obsidian"), e("a"), e("b", "f1"), e("c", "f1"), e("d")], [F("obsidian", false, true), F("f1", false, true)]);
    expect(flatten(toEnd(t, ["d"], "top"))).toEqual(["q", "d", "a", "b", "c"]);
    expect(flatten(moveMods(t, ["b"], { folder: null, index: 0 }))).toEqual(flatten(t));
    expect(flatten(moveMods(t, ["a"], { folder: "f1", index: 0 }))).toEqual(flatten(t));
    expect(flatten(moveFolder(t, "f1", 0))).toEqual(flatten(t));
    expect(flatten(nudge(t, "a", -1))).toEqual(flatten(t)); // nothing goes above the Obsidian folder
    const shown = lines(t).filter((l) => !(l.kind === "mod" && l.id === "d"));
    // obsidian | q | a | f1 | b | c
    expect(dropSpot(t, shown, 5, null, ["d"])).toEqual({ folder: null, index: 3 });
    expect(dropSpot(t, shown, 1, "f1", ["d"])).toEqual({ folder: null, index: 3 });
  });

  it("drops a folder only between top-level items", () => {
    // Lines without f1: a | d | f2. A gap inside f1 is not possible; gap 1 is after a.
    expect(folderDropIndex(tree(), 1, "f1")).toBe(1);
    // With f2 moving, a gap inside f1 (after b) rounds to after f1.
    expect(folderDropIndex(tree(), 3, "f2")).toBe(2);
  });
});
