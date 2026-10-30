// The mod table in load order (spec 4.1). Rows drag to reorder with pointer events; Alt+Up and
// Alt+Down do the same from the keyboard.
import { useRef, useState, type KeyboardEvent, type PointerEvent } from "react";
import { pick, t } from "../i18n";
import type { ModRow } from "../types";
import { moveRow } from "./rows";

type Props = {
  /** The rows to show, in the order to show them. */
  rows: ModRow[];
  /** Every mod id in load order, for the position numbers. */
  order: string[];
  names: Map<string, string>;
  canDrag: boolean;
  selected: string | null;
  onSelect: (id: string) => void;
  onToggle: (id: string, on: boolean) => void;
  /** The order while a drag is under way, or null when it ends without a change. */
  onDrag: (ids: string[] | null) => void;
  onDrop: (ids: string[]) => void;
};

type Drag = { id: string; from: number; to: number; y0: number; mids: number[]; ids: string[]; moved: boolean };
const THRESHOLD_PX = 5;

export function ModTable({ rows, order, names, canDrag, selected, onSelect, onToggle, onDrag, onDrop }: Props) {
  const body = useRef<HTMLDivElement>(null);
  const drag = useRef<Drag | null>(null);
  const [dragging, setDragging] = useState<string | null>(null);

  const down = (e: PointerEvent<HTMLDivElement>, id: string, i: number) => {
    if (e.button !== 0) return;
    const mids = [...(body.current?.querySelectorAll<HTMLElement>(".tr") ?? [])].map((el) => {
      const r = el.getBoundingClientRect();
      return r.top + r.height / 2;
    });
    drag.current = { id, from: i, to: i, y0: e.clientY, mids, ids: rows.map((r) => r.id), moved: false };
    e.currentTarget.setPointerCapture(e.pointerId);
  };
  const move = (e: PointerEvent<HTMLDivElement>) => {
    const d = drag.current;
    if (!d || !canDrag) return;
    if (!d.moved && Math.abs(e.clientY - d.y0) < THRESHOLD_PX) return;
    d.moved = true;
    setDragging(d.id);
    const to = d.mids.filter((m, j) => j !== d.from && m < e.clientY).length;
    if (to !== d.to) {
      d.to = to;
      onDrag(moveRow(d.ids, d.from, to));
    }
  };
  const up = () => {
    const d = drag.current;
    drag.current = null;
    setDragging(null);
    if (!d) return;
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
      if (to >= 0 && to < rows.length) onDrop(moveRow(rows.map((r) => r.id), i, to));
    }
  };

  return (
    <div className="table" role="table">
      <div className="th cap" role="row">
        <span data-tip={canDrag ? t("app.mods.orderHint") : t("app.mods.reorderOff")}>#</span>
        <span>{t("app.mods.colOn")}</span>
        <span>{t("app.mods.colMod")}</span>
        <span>{t("app.mods.colScope")}</span>
      </div>
      <div ref={body} className="tbody">
        {rows.map((m, i) => {
          const name = pick(m.name, m.id);
          const cls = ["tr", selected === m.id && "sel", dragging === m.id && "dragging"].filter(Boolean).join(" ");
          return (
            <div key={m.id} role="row" tabIndex={0} className={cls} aria-selected={selected === m.id}
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
                {m.overlaps.length > 0 ? (
                  <div className="sub warn">{t("app.mods.overlaps", m.overlaps.map((id) => names.get(id) ?? id).join(", "))}</div>
                ) : (
                  pick(m.description) && <div className="sub">{pick(m.description)}</div>
                )}
              </div>
              <span className={`scope ${m.scope}`} data-tip={t(`app.scope.${m.scope}Hint`)}><i />{t(`app.scope.${m.scope}`)}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}
