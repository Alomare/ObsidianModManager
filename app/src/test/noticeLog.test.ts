import { describe, expect, it } from "vitest";
import { addTo, type Logged } from "../noticeLog";

describe("addTo", () => {
  it("appends with the next id", () => {
    const a = addTo([], "info", "Installed A", 1000);
    const b = addTo(a, "error", "B failed", 2000);
    expect(b.map((n) => [n.id, n.kind, n.text])).toEqual([[1, "info", "Installed A"], [2, "error", "B failed"]]);
  });
  it("folds the same text within five seconds into one entry", () => {
    const a = addTo(addTo([], "info", "Saved", 1000), "info", "Saved", 4000);
    expect(a).toEqual([{ id: 1, at: 4000, kind: "info", text: "Saved" }]);
    expect(addTo(a, "info", "Saved", 9001)).toHaveLength(2);
  });
  it("keeps the last 100", () => {
    let log: Logged[] = [];
    for (let i = 0; i < 105; i++) log = addTo(log, "info", `n${i}`, i * 10_000);
    expect(log).toHaveLength(100);
    expect(log[0].text).toBe("n5");
    expect(log[99].id).toBe(105);
  });
});
