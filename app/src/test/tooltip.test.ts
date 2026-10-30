import { describe, expect, it } from "vitest";
import { tipPlace } from "../Tooltip";

const win = { width: 1000, height: 600 };
const tip = { width: 200, height: 80 };
const at = (top: number, left = 400) => ({ left, right: left + 40, top, bottom: top + 30 });

describe("tipPlace", () => {
  it("sits above the element, centred on it", () => {
    expect(tipPlace(at(300), tip, win, false)).toEqual({ x: 320, y: 212, below: false });
  });

  it("goes by the tooltip's real height, not a fixed line near the top", () => {
    expect(tipPlace(at(70), tip, win, false)).toEqual({ x: 320, y: 108, below: true });
    expect(tipPlace(at(100), tip, win, false)).toEqual({ x: 320, y: 12, below: false });
    expect(tipPlace(at(70), { width: 200, height: 40 }, win, false).below).toBe(false);
  });

  it("stays inside the sides of the window", () => {
    expect(tipPlace(at(300, 0), tip, win, false).x).toBe(8);
    expect(tipPlace(at(300, 960), tip, win, false).x).toBe(792);
  });

  it("goes below by choice, unless it doesn't fit there", () => {
    expect(tipPlace(at(300), tip, win, true)).toEqual({ x: 320, y: 338, below: true });
    expect(tipPlace(at(520), tip, win, true)).toEqual({ x: 320, y: 432, below: false });
  });

  it("stays on screen in a window too short for either side", () => {
    expect(tipPlace(at(20), tip, { width: 1000, height: 100 }, false).y).toBe(12);
  });
});
