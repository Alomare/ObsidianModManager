import { act, type ReactNode } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, describe, expect, it, vi } from "vitest";
import { Confirm } from "../Confirm";
import { ContextMenu } from "../ContextMenu";
import { Prompt } from "../Prompt";
import { listPlace, Select } from "../Select";

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

let root: Root | undefined;
afterEach(() => {
  act(() => root?.unmount());
  document.body.replaceChildren();
});

/** Renders inside a box with a folded corner, as the drawer and the Settings sections are. */
function inMaskedBox(ui: ReactNode) {
  const box = document.createElement("div");
  box.className = "drawer";
  document.body.append(box);
  root = createRoot(box);
  act(() => root!.render(ui));
  return box;
}

const OPTIONS = [{ value: "a", label: "A" }, { value: "b", label: "B" }];
const pressOn = (el: Element) => act(() => {
  el.dispatchEvent(new MouseEvent("pointerdown", { bubbles: true }));
  el.dispatchEvent(new MouseEvent("click", { bubbles: true }));
});

describe("overlays", () => {
  it("sit on the body, so a mask can't cut them off", () => {
    const none = vi.fn();
    const box = inMaskedBox(
      <>
        <Confirm title="T" text="X" confirm="OK" onConfirm={none} onCancel={none} />
        <Prompt title="T" label="L" confirm="OK" onConfirm={async () => true} onCancel={none} />
        <ContextMenu x={1} y={1} items={[{ label: "M" }]} onClose={none} />
        <Select value="a" options={OPTIONS} onChange={none} label="S" />
      </>,
    );
    act(() => box.querySelector<HTMLButtonElement>(".select-btn")!.click());
    for (const sel of [".modal-back", ".ctx", ".select-list"]) {
      expect(document.body.querySelector(sel), sel).not.toBeNull();
      expect(box.querySelector(sel), sel).toBeNull();
    }
  });
});

describe("ContextMenu", () => {
  it("hangs above the point for a button low in the window", () => {
    const size = vi.spyOn(Element.prototype, "getBoundingClientRect").mockReturnValue({ width: 200, height: 120 } as DOMRect);
    inMaskedBox(<ContextMenu x={300} y={500} up items={[{ label: "M" }]} onClose={vi.fn()} />);
    expect(document.querySelector<HTMLElement>(".ctx")!.style.top).toBe("380px");
    size.mockRestore();
  });
});

describe("Select", () => {
  it("takes a pick from the list, though the list is outside the control", () => {
    const onChange = vi.fn();
    const box = inMaskedBox(<Select value="a" options={OPTIONS} onChange={onChange} label="S" />);
    act(() => box.querySelector<HTMLButtonElement>(".select-btn")!.click());
    pressOn(document.querySelectorAll(".select-list li")[1]);
    expect(onChange).toHaveBeenCalledWith("b");
    expect(document.querySelector(".select-list")).toBeNull();
  });

  it("closes on a click outside and when the page under it scrolls, but not when the list scrolls", () => {
    const box = inMaskedBox(<Select value="a" options={OPTIONS} onChange={vi.fn()} label="S" />);
    const button = box.querySelector<HTMLButtonElement>(".select-btn")!;
    act(() => button.click());
    act(() => { document.querySelector(".select-list")!.dispatchEvent(new Event("scroll")); });
    expect(document.querySelector(".select-list")).not.toBeNull();
    act(() => { document.body.dispatchEvent(new MouseEvent("pointerdown", { bubbles: true })); });
    expect(document.querySelector(".select-list")).toBeNull();
    act(() => button.click());
    act(() => { box.dispatchEvent(new Event("scroll")); });
    expect(document.querySelector(".select-list")).toBeNull();
  });
});

describe("listPlace", () => {
  const win = { width: 1000, height: 800 };
  const list = { width: 100, height: 200 };
  const at = (top: number, left = 100) => ({ left, top, bottom: top + 40, width: 120 });

  it("opens under the button", () => {
    expect(listPlace(at(100), list, win)).toEqual({ left: 100, minWidth: 120, maxHeight: 200, top: 144 });
  });
  it("opens over the button near the bottom of the window", () => {
    expect(listPlace(at(700), list, win)).toEqual({ left: 100, minWidth: 120, maxHeight: 200, bottom: 104 });
  });
  it("stays under when neither side fits and below has more room", () => {
    const short = { width: 1000, height: 300 };
    expect(listPlace(at(40), { width: 100, height: 400 }, short)).toEqual({ left: 100, minWidth: 120, maxHeight: 208, top: 84 });
  });
  it("stays inside the right edge", () => {
    expect(listPlace(at(100, 950), { width: 200, height: 100 }, win).left).toBe(792);
  });
});
