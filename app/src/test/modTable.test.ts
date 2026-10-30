import { describe, expect, it } from "vitest";
import { filterMods, moveRow } from "../mods/rows";
import type { ModRow } from "../types";

const row = (id: string, name: string, authors: string[]): ModRow => ({
  id, name: { en: name }, description: {}, authors, version: "1.0.0", scope: "client", bundled: false, on: true,
  options: [], keybinds: [], files: [], import: null, source: null,
});
const rows = [row("a", "Helldivers Rework", ["Bia"]), row("b", "HD2CAM", ["camdev"]), row("c", "Third Person Camera", ["Zed"])];

describe("filterMods", () => {
  it("matches names and authors, ignoring case", () => {
    expect(filterMods(rows, "rework").map((r) => r.id)).toEqual(["a"]);
    expect(filterMods(rows, "CAM").map((r) => r.id)).toEqual(["b", "c"]);
    expect(filterMods(rows, "zed").map((r) => r.id)).toEqual(["c"]);
  });
  it("keeps everything for an empty or blank query", () => {
    expect(filterMods(rows, "")).toEqual(rows);
    expect(filterMods(rows, "  ")).toEqual(rows);
  });
  it("finds nothing when nothing matches", () => {
    expect(filterMods(rows, "trainer")).toEqual([]);
  });
});

describe("moveRow", () => {
  const ids = ["a", "b", "c", "d"];
  it("moves down and up", () => {
    expect(moveRow(ids, 0, 2)).toEqual(["b", "c", "a", "d"]);
    expect(moveRow(ids, 3, 1)).toEqual(["a", "d", "b", "c"]);
  });
  it("moves to the ends", () => {
    expect(moveRow(ids, 1, 3)).toEqual(["a", "c", "d", "b"]);
    expect(moveRow(ids, 2, 0)).toEqual(["c", "a", "b", "d"]);
  });
  it("leaves the list alone for a move in place or out of range", () => {
    expect(moveRow(ids, 1, 1)).toEqual(ids);
    expect(moveRow(ids, 5, 0)).toEqual(ids);
    expect(moveRow(ids, 0, 9)).toEqual(["b", "c", "d", "a"]);
  });
  it("does not change the list it was given", () => {
    const copy = [...ids];
    moveRow(copy, 0, 3);
    expect(copy).toEqual(ids);
  });
});
