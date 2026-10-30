// A right-click menu. Items run and close it; an item with `sub` opens a menu to the side on
// hover or Enter, and `colors` is a row of swatches to pick from. Esc, a click outside, a scroll
// or leaving the window closes it.
import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { ChevronIcon } from "./Icons";

export type MenuItem =
  | { label: string; icon?: ReactNode; danger?: boolean; disabled?: boolean; hint?: string; run?: () => void; sub?: MenuItem[]; swatch?: string }
  | { colors: string[]; current: string | null; pick: (color: string) => void }
  | "sep";

export function ContextMenu({ x, y, items, onClose }: { x: number; y: number; items: MenuItem[]; onClose: () => void }) {
  const close = useRef(onClose);
  close.current = onClose;
  useEffect(() => {
    const away = (e: PointerEvent) => !(e.target as Element).closest?.(".ctx") && close.current();
    const key = (e: KeyboardEvent) => e.key === "Escape" && close.current();
    const gone = () => close.current();
    document.addEventListener("pointerdown", away, true);
    window.addEventListener("keydown", key);
    window.addEventListener("blur", gone);
    window.addEventListener("resize", gone);
    document.addEventListener("scroll", gone, true);
    return () => {
      document.removeEventListener("pointerdown", away, true);
      window.removeEventListener("keydown", key);
      window.removeEventListener("blur", gone);
      window.removeEventListener("resize", gone);
      document.removeEventListener("scroll", gone, true);
    };
  }, []);
  return <Menu x={x} y={y} items={items} onClose={onClose} root />;
}

function Menu({ x, y, items, onClose, root, keys }: { x: number; y: number; items: MenuItem[]; onClose: () => void; root?: boolean; keys?: boolean }) {
  const box = useRef<HTMLDivElement>(null);
  const [pos, setPos] = useState({ x, y });
  const [open, setOpen] = useState<{ i: number; x: number; y: number; keys?: boolean } | null>(null);
  // Kept inside the window: a menu near the right or bottom edge opens the other way.
  useLayoutEffect(() => {
    const r = box.current!.getBoundingClientRect();
    const nx = x + r.width > innerWidth - 4 ? (root ? x - r.width : x - r.width * 2 - 4) : x;
    const ny = y + r.height > innerHeight - 4 ? Math.max(4, innerHeight - r.height - 4) : y;
    setPos({ x: Math.max(4, nx), y: ny });
    if (root || keys) box.current!.querySelector<HTMLElement>("button:not(:disabled)")?.focus();
  }, [x, y, root, keys]);

  const openSub = (i: number, el: HTMLElement, keys?: boolean) => {
    const r = el.getBoundingClientRect();
    setOpen({ i, x: r.right + 2, y: r.top - 5, keys });
  };
  const step = (all: HTMLElement[], from: Element | null | undefined, forward: boolean) => {
    const at = all.indexOf(from as HTMLElement);
    all[(at + (forward ? 1 : all.length - 1)) % all.length]?.focus();
  };
  const key = (e: React.KeyboardEvent) => {
    // A row of colors is one stop going up and down; left and right move along it.
    const row = (e.target as Element).closest(".ctx-colors");
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      const stops = box.current!.querySelectorAll<HTMLElement>(":scope > button:not(:disabled), .ctx-colors > :first-child");
      step([...stops], row ? row.firstElementChild : document.activeElement, e.key === "ArrowDown");
    } else if (row && (e.key === "ArrowLeft" || e.key === "ArrowRight")) {
      e.preventDefault();
      step([...row.children] as HTMLElement[], document.activeElement, e.key === "ArrowRight");
    }
  };
  return (
    <>
      <div ref={box} className="ctx" role="menu" style={{ left: pos.x, top: pos.y }} onKeyDown={key} onContextMenu={(e) => e.preventDefault()}>
        {items.map((it, i) =>
          it === "sep" ? (
            <hr key={i} />
          ) : "colors" in it ? (
            <div key={i} className="ctx-colors" role="group">
              {it.colors.map((c) => (
                <button key={c} role="menuitemradio" aria-checked={c === it.current} aria-label={c} className={c === it.current ? "swatch on" : "swatch"} style={{ background: c }}
                  onClick={() => {
                    onClose();
                    it.pick(c);
                  }} />
              ))}
            </div>
          ) : (
            <button key={i} role="menuitem" className={it.danger ? "danger" : undefined} disabled={it.disabled} aria-haspopup={it.sub ? "menu" : undefined}
              aria-expanded={it.sub ? open?.i === i : undefined}
              onPointerEnter={(e) => (it.sub ? openSub(i, e.currentTarget) : setOpen(null))}
              onKeyDown={(e) => it.sub && (e.key === "ArrowRight" || e.key === "Enter") && (e.preventDefault(), openSub(i, e.currentTarget, true))}
              onClick={(e) => {
                if (it.sub) return openSub(i, e.currentTarget);
                onClose();
                it.run?.();
              }}>
              <span className="ctx-ico">{it.swatch ? <i className="ctx-swatch" style={{ background: it.swatch }} /> : it.icon}</span>
              <span className="ctx-label">{it.label}</span>
              {it.hint && <span className="ctx-hint">{it.hint}</span>}
              {it.sub && <span className="ctx-more"><ChevronIcon /></span>}
            </button>
          ),
        )}
      </div>
      {open && (items[open.i] as { sub?: MenuItem[] }).sub && <Menu x={open.x} y={open.y} items={(items[open.i] as { sub: MenuItem[] }).sub} onClose={onClose} keys={open.keys} />}
    </>
  );
}
