import { describe, expect, it } from "vitest";
import { filterMods } from "../mods/rows";
import type { ModRow } from "../types";

const row = (id: string, name: string, authors: string[]): ModRow => ({
  id, name: { en: name }, description: {}, authors, version: "1.0.0", scope: "client", bundled: false, on: true,
  options: [], keybinds: [], files: [], import: null, source: null, image: null, customImage: false, folder: null,
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
