// The mod table in load order (spec 4.1). Rows drag to reorder with pointer events; the dragged
// row follows the pointer and the others slide out of its way. Alt+Up and Alt+Down do the same
// from the keyboard. A warning icon marks mods in a conflict and opens the conflicts.
import { useLayoutEffect, useRef, useState, type KeyboardEvent, type PointerEvent } from "react";
import { WarnIcon } from "../Icons";
import { pick, t } from "../i18n";
import type { ConflictRow, ModRow } from "../types";
import { conflictsOf } from "./conflicts";
import { moveRow } from "./rows";

type Props = {
  /** The rows to show, in the order to show them. */
  rows: ModRow[];
  /** Every mod id in load order, for the position numbers. */
  order: string[];
  names: Map<string, string>;
  /** Conflicts for the order on screen. */
  conflicts: ConflictRow[];
  canDrag: boolean;
  selected: string | null;
  onSelect: (id: string) => void;
  onToggle: (id: string, on: boolean) => void;
  onConflicts: (id: string) => void;
  /** The order while a drag is under way, or null when it ends without a change. */
  onDrag: (ids: string[] | null) => void;
  onDrop: (ids: string[]) => void;
};

type Drag = { id: string; from: number; to: number; y0: number; top0: number; dy: number; mids: number[]; ids: string[]; moved: boolean };
const THRESHOLD_PX = 5;

/** Moves the dragged row under the pointer, wherever the current order has put it. */
const follow = (el: HTMLElement, d: Drag) => {
  el.style.transform = `translateY(${d.dy - (el.offsetTop - d.top0)}px)`;
};

export function ModTable({ rows, order, names, conflicts, canDrag, selected, onSelect, onToggle, onConflicts, onDrag, onDrop }: Props) {
  const body = useRef<HTMLDivElement>(null);
  const drag = useRef<Drag | null>(null);
  const before = useRef<Map<string, number> | null>(null);
  const [dragging, setDragging] = useState<string | null>(null);

  const rowEls = () => [...(body.current?.querySelectorAll<HTMLElement>(".tr") ?? [])];
  /** Where every row is on screen now, so the next render can slide them from there. */
  const measure = () => {
    before.current = new Map(rowEls().map((el) => [el.dataset.id!, el.getBoundingClientRect().top]));
  };

  // After a reorder, each row starts where it was and slides to its new place.
  useLayoutEffect(() => {
    const old = before.current;
    before.current = null;
    const d = drag.current;
    for (const el of rowEls()) {
      if (d?.moved && el.dataset.id === d.id) {
        follow(el, d);
        continue;
      }
      const prev = old?.get(el.dataset.id!);
      if (prev === undefined) continue;
      el.style.transition = "none";
      el.style.transform = "";
      const dy = prev - el.getBoundingClientRect().top;
      if (!dy) {
        el.style.transition = "";
        continue;
      }
      el.style.transform = `translateY(${dy}px)`;
      el.getBoundingClientRect();
      el.style.transition = "";
      el.style.transform = "";
    }
  });

  const down = (e: PointerEvent<HTMLDivElement>, id: string, i: number) => {
    if (e.button !== 0) return;
    const mids = rowEls().map((el) => {
      const r = el.getBoundingClientRect();
      return r.top + r.height / 2;
    });
    drag.current = { id, from: i, to: i, y0: e.clientY, top0: e.currentTarget.offsetTop, dy: 0, mids, ids: rows.map((r) => r.id), moved: false };
    e.currentTarget.setPointerCapture(e.pointerId);
  };
  const move = (e: PointerEvent<HTMLDivElement>) => {
    const d = drag.current;
    if (!d || !canDrag) return;
    if (!d.moved && Math.abs(e.clientY - d.y0) < THRESHOLD_PX) return;
    d.moved = true;
    d.dy = e.clientY - d.y0;
    setDragging(d.id);
    follow(e.currentTarget, d);
    const to = d.mids.filter((m, j) => j !== d.from && m < e.clientY).length;
    if (to !== d.to) {
      d.to = to;
      measure();
      onDrag(moveRow(d.ids, d.from, to));
    }
  };
  const up = (e: PointerEvent<HTMLDivElement>) => {
    const d = drag.current;
    drag.current = null;
    setDragging(null);
    if (!d) return;
    // The dropped row settles into its slot.
    const el = e.currentTarget;
    el.classList.remove("dragging");
    el.style.transition = "";
    el.style.transform = "";
    if (!d.moved) onSelect(d.id);
    else if (d.to !== d.from) onDrop(moveRow(d.ids, d.from, d.to));
    else onDrag(null);
  };
  const key = (e: KeyboardEvent<HTMLDivElement>, id: string, i: number) => {
    if (e.key === "Enter" || e.key === " ") {
      e.preventDefault();
      onSelect(id);
    } else if (canDrag && e.altKey && (e.key === "ArrowUp" || e.key === "ArrowDown")) {
      e.preventDefault();
      const to = i + (e.key === "ArrowUp" ? -1 : 1);
      if (to < 0 || to >= rows.length) return;
      measure();
      onDrop(moveRow(rows.map((r) => r.id), i, to));
    }
  };

  const nameOf = (id: string) => names.get(id) ?? id;
  const withFiles = ([id, n]: [string, number]) => (n === 1 ? t("app.mods.withOneFile", nameOf(id)) : t("app.mods.withFiles", nameOf(id), n));

  return (
    <div className="table" role="table">
      <div className="th cap" role="row">
        <span data-tip-title={t("app.mods.orderTitle")} data-tip={canDrag ? t("app.mods.orderHint") : t("app.mods.reorderOff")}>#</span>
        <span>{t("app.mods.colOn")}</span>
        <span>{t("app.mods.colMod")}</span>
        <span />
        <span>{t("app.mods.colScope")}</span>
      </div>
      <div ref={body} className="tbody">
        {rows.map((m, i) => {
          const name = pick(m.name, m.id);
          const c = conflictsOf(m.id, conflicts);
          const lines = [
            c.overrides.length > 0 && t("app.mods.overridesList", c.overrides.map(withFiles).join(", ")),
            c.overriddenBy.length > 0 && t("app.mods.overriddenByList", c.overriddenBy.map(withFiles).join(", ")),
            t("app.mods.conflictsClick"),
          ].filter(Boolean);
          const cls = ["tr", selected === m.id && "sel", dragging === m.id && "dragging"].filter(Boolean).join(" ");
          return (
            <div key={m.id} data-id={m.id} role="row" tabIndex={0} className={cls} aria-selected={selected === m.id}
              onPointerDown={(e) => down(e, m.id, i)} onPointerMove={move} onPointerUp={up} onPointerCancel={up} onKeyDown={(e) => key(e, m.id, i)}>
              <span className="num">{order.indexOf(m.id) + 1}</span>
              <button role="switch" aria-checked={m.on} aria-label={name} className={m.on ? "sw on" : "sw"} data-tip={t(m.on ? "app.mods.turnOff" : "app.mods.turnOn", name)}
                onPointerDown={(e) => e.stopPropagation()} onKeyDown={(e) => e.stopPropagation()} onClick={() => onToggle(m.id, !m.on)} />
              <div className="who">
                <div className="nm">
                  {name}
                  <span className="ver">{m.version ?? t("app.mods.imported")}</span>
                  {m.bundled && <span className="tag">{t("app.mods.bundled")}</span>}
                </div>
                {pick(m.description) && <div className="sub">{pick(m.description)}</div>}
              </div>
              {lines.length > 1 ? (
                <button className={c.overriddenBy.length ? "bare cf-ico lose" : "bare cf-ico"} aria-label={t("app.drawer.conflicts")}
                  data-tip-title={t("app.drawer.conflicts")} data-tip={lines.join("\n")}
                  onPointerDown={(e) => e.stopPropagation()} onKeyDown={(e) => e.stopPropagation()} onClick={() => onConflicts(m.id)}>
                  <WarnIcon />
                </button>
              ) : <span />}
              <span className={`scope ${m.scope}`} data-tip-title={t(`app.scope.${m.scope}Mod`)} data-tip={t(`app.scope.${m.scope}Hint`)}><i />{t(`app.scope.${m.scope}`)}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}
