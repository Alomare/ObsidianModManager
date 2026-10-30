// The mod table in load order (spec 4.1), with folders. Mods and folders drag to a new place: a
// line shows where they land, and a folder's name lights up when they would go in at the end of that folder.
// Dragging a checked mod takes every checked mod. After a move the rows slide to their places.
// Alt+Up and Alt+Down move the focused mod or folder from the keyboard. A warning icon marks
// mods in a conflict and opens the conflicts; a right click opens the menu.
import { useLayoutEffect, useRef, useState, type CSSProperties, type KeyboardEvent, type MouseEvent, type PointerEvent } from "react";
import { CheckIcon, ChevronIcon, WarnIcon } from "../Icons";
import { pick, t } from "../i18n";
import { Thumb } from "../Thumb";
import type { ConflictRow, ModRow } from "../types";
import { conflictsOf } from "./conflicts";
import { dropSpot, folderDropIndex, lines, moveFolder, moveMods, nudge, type Line, type Node } from "./layout";

export type MenuTarget = { kind: "mod"; id: string } | { kind: "folder"; id: string };

type Props = {
  /** The tree to show, or null while searching: then `rows` show flat and nothing drags. */
  tree: Node[] | null;
  rows: ModRow[];
  byId: Map<string, ModRow>;
  /** Every mod id in load order, for the position numbers. */
  order: string[];
  names: Map<string, string>;
  conflicts: ConflictRow[];
  selected: string | null;
  checked: Set<string>;
  onCheck: (ids: string[], on: boolean) => void;
  onSelect: (id: string) => void;
  onToggle: (ids: string[], on: boolean) => void;
  onConflicts: (id: string) => void;
  onArrange: (tree: Node[]) => void;
  onCollapse: (folder: string, collapsed: boolean) => void;
  onMenu: (x: number, y: number, target: MenuTarget) => void;
};

type Drag = { key: string; folder: string | null; ids: string[]; x0: number; y0: number; moved: boolean; gap: number; onto: string | null };
type Shown = { key: string; el: HTMLElement; line: Line };
type Marker = { y: number; indent: boolean; onto: string | null; x: number; py: number; label: string };
const THRESHOLD_PX = 5;
const EDGE_PX = 36;

const keyOf = (l: Line) => (l.kind === "folder" ? `folder:${l.folder.id}` : l.id);
/** Clicks on these do their own thing and never start a drag. */
const stop = { onPointerDown: (e: PointerEvent) => e.stopPropagation(), onKeyDown: (e: KeyboardEvent) => e.stopPropagation() };

function Check({ state, label, onChange }: { state: boolean | "mixed"; label: string; onChange: (on: boolean, shift: boolean) => void }) {
  return (
    <button role="checkbox" aria-checked={state} aria-label={label} className={state ? "ck on" : "ck"} {...stop}
      onClick={(e) => onChange(state !== true, e.shiftKey)}>
      {state === "mixed" ? <i className="ck-dash" /> : state ? <CheckIcon /> : null}
    </button>
  );
}

export function ModTable({ tree, rows, byId, order, names, conflicts, selected, checked, onCheck, onSelect, onToggle, onConflicts, onArrange, onCollapse, onMenu }: Props) {
  const body = useRef<HTMLDivElement>(null);
  const drag = useRef<Drag | null>(null);
  const before = useRef<Map<string, number> | null>(null);
  const lastCheck = useRef<string | null>(null);
  const [marker, setMarker] = useState<Marker | null>(null);
  const all: Line[] = tree ? lines(tree) : rows.map((r) => ({ kind: "mod", id: r.id, folder: null }));
  const visibleMods = all.flatMap((l) => (l.kind === "mod" ? [l.id] : []));

  const rowEls = () => [...(body.current?.querySelectorAll<HTMLElement>("[data-key]") ?? [])];
  /** Where every row is now, so the next render can slide them from there. */
  const measure = () => {
    before.current = new Map(rowEls().map((el) => [el.dataset.key!, el.getBoundingClientRect().top]));
  };
  useLayoutEffect(() => {
    const old = before.current;
    before.current = null;
    if (!old) return;
    for (const el of rowEls()) {
      const prev = old.get(el.dataset.key!);
      if (prev === undefined) continue;
      const dy = prev - el.getBoundingClientRect().top;
      if (!dy) continue;
      el.style.transition = "none";
      el.style.transform = `translateY(${dy}px)`;
      el.getBoundingClientRect();
      el.style.transition = "";
      el.style.transform = "";
    }
  });

  const arrange = (next: Node[]) => {
    measure();
    onArrange(next);
  };

  /** The rows still in place while `d` is dragged. */
  const shownFor = (d: Drag): Shown[] => {
    const els = new Map(rowEls().map((el) => [el.dataset.key!, el]));
    return all
      .filter((l) => (d.folder ? !(l.kind === "folder" && l.folder.id === d.folder) && !(l.kind === "mod" && l.folder === d.folder) : !(l.kind === "mod" && d.ids.includes(l.id))))
      .flatMap((line) => {
        const el = els.get(keyOf(line));
        return el ? [{ key: keyOf(line), el, line }] : [];
      });
  };

  const down = (e: PointerEvent<HTMLDivElement>, line: Line) => {
    if (e.button !== 0) return;
    const ids = line.kind === "folder" ? [] : checked.has(line.id) ? order.filter((id) => checked.has(id)) : [line.id];
    drag.current = { key: keyOf(line), folder: line.kind === "folder" ? line.folder.id : null, ids, x0: e.clientX, y0: e.clientY, moved: false, gap: -1, onto: null };
    e.currentTarget.setPointerCapture(e.pointerId);
  };
  const move = (e: PointerEvent<HTMLDivElement>) => {
    const d = drag.current;
    if (!d || !tree) return;
    if (!d.moved && Math.abs(e.clientY - d.y0) < THRESHOLD_PX) return;
    d.moved = true;
    // Near the top or bottom edge the list scrolls.
    const box = body.current!.getBoundingClientRect();
    if (e.clientY < box.top + EDGE_PX) body.current!.scrollTop -= 14;
    else if (e.clientY > box.bottom - EDGE_PX) body.current!.scrollTop += 14;
    const shown = shownFor(d);
    const rects = shown.map((s) => s.el.getBoundingClientRect());
    d.onto = null;
    if (!d.folder) {
      const i = shown.findIndex((s, j) => s.line.kind === "folder" && e.clientY > rects[j].top + rects[j].height * 0.25 && e.clientY < rects[j].bottom - rects[j].height * 0.25);
      if (i >= 0) d.onto = (shown[i].line as Line & { kind: "folder" }).folder.id;
    }
    d.gap = rects.filter((r) => r.top + r.height / 2 < e.clientY).length;
    const at = shown[d.gap];
    const last = shown.at(-1);
    const y = at ? at.el.offsetTop : last ? last.el.offsetTop + last.el.offsetHeight : 0;
    const indent = !d.folder && !d.onto && dropSpot(tree, shown.map((s) => s.line), d.gap, null, d.ids).folder !== null;
    const label = d.folder
      ? (tree.find((n) => n.kind === "folder" && n.folder.id === d.folder) as Node & { kind: "folder" }).folder.name
      : d.ids.length === 1 ? names.get(d.ids[0]) ?? d.ids[0] : t("app.mods.nMods", d.ids.length);
    setMarker({ y, indent, onto: d.onto, x: e.clientX, py: e.clientY, label });
  };
  const up = (e: PointerEvent<HTMLDivElement>) => {
    const d = drag.current;
    drag.current = null;
    setMarker(null);
    if (!d || e.type === "pointercancel") return;
    if (!d.moved) {
      if (d.folder) {
        const f = tree?.find((n) => n.kind === "folder" && n.folder.id === d.folder);
        if (f?.kind === "folder") onCollapse(f.folder.id, !f.folder.collapsed);
      } else onSelect(d.key);
      return;
    }
    if (!tree || d.gap < 0) return;
    const shown = shownFor(d).map((s) => s.line);
    arrange(d.folder ? moveFolder(tree, d.folder, folderDropIndex(tree, d.gap, d.folder)) : moveMods(tree, d.ids, dropSpot(tree, shown, d.gap, d.onto, d.ids)));
  };
  const key = (e: KeyboardEvent<HTMLDivElement>, line: Line) => {
    if (e.key === "Enter" || e.key === " ") {
      e.preventDefault();
      if (line.kind === "folder") onCollapse(line.folder.id, !line.folder.collapsed);
      else onSelect(line.id);
    } else if (tree && e.altKey && (e.key === "ArrowUp" || e.key === "ArrowDown")) {
      e.preventDefault();
      const by = e.key === "ArrowUp" ? -1 : 1;
      if (line.kind === "mod") arrange(nudge(tree, line.id, by));
      else arrange(moveFolder(tree, line.folder.id, Math.max(0, tree.findIndex((n) => n.kind === "folder" && n.folder.id === line.folder.id) + by)));
    } else if (e.key === "ContextMenu" || (e.shiftKey && e.key === "F10")) {
      e.preventDefault();
      const r = e.currentTarget.getBoundingClientRect();
      onMenu(r.left + 40, r.top + r.height / 2, line.kind === "folder" ? { kind: "folder", id: line.folder.id } : { kind: "mod", id: line.id });
    }
  };
  const menu = (e: MouseEvent, target: MenuTarget) => {
    e.preventDefault();
    onMenu(e.clientX, e.clientY, target);
  };
  /** Checks one mod; with Shift, every mod between it and the one checked last. */
  const check = (id: string, on: boolean, shift: boolean) => {
    const a = lastCheck.current ? visibleMods.indexOf(lastCheck.current) : -1;
    const b = visibleMods.indexOf(id);
    lastCheck.current = id;
    onCheck(shift && a >= 0 ? visibleMods.slice(Math.min(a, b), Math.max(a, b) + 1) : [id], on);
  };

  const nameOf = (id: string) => names.get(id) ?? id;
  const withFiles = ([id, n]: [string, number]) => (n === 1 ? t("app.mods.withOneFile", nameOf(id)) : t("app.mods.withFiles", nameOf(id), n));
  const allState = visibleMods.length && visibleMods.every((id) => checked.has(id)) ? true : visibleMods.some((id) => checked.has(id)) ? "mixed" : false;
  const draggingKeys = new Set(drag.current?.moved ? (drag.current.folder ? [drag.current.key] : drag.current.ids) : []);

  return (
    <div className="table" role="table">
      <div className="th cap" role="row">
        <Check state={allState} label={t("app.mods.checkAll")} onChange={(on) => onCheck(visibleMods, on)} />
        <span data-tip-title={t("app.mods.orderTitle")} data-tip={tree ? t("app.mods.orderHint") : t("app.mods.reorderOff")}>#</span>
        <span>{t("app.mods.colOn")}</span>
        <span>{t("app.mods.colMod")}</span>
        <span />
        <span>{t("app.mods.colScope")}</span>
      </div>
      <div ref={body} className={marker ? "tbody dragging-list" : "tbody"}>
        {all.map((line) => {
          if (line.kind === "folder") {
            const f = line.folder;
            const node = tree?.find((n) => n.kind === "folder" && n.folder.id === f.id);
            const ids = node?.kind === "folder" ? node.ids : [];
            const on = ids.filter((id) => byId.get(id)?.on).length;
            const state = ids.length && ids.every((id) => checked.has(id)) ? true : ids.some((id) => checked.has(id)) ? "mixed" : false;
            const cls = ["tr", "fr", f.collapsed && "closed", marker?.onto === f.id && "onto", draggingKeys.has(keyOf(line)) && "lifted"].filter(Boolean).join(" ");
            return (
              <div key={keyOf(line)} data-key={keyOf(line)} role="row" tabIndex={0} className={cls} style={{ "--fc": f.color } as CSSProperties} aria-expanded={!f.collapsed}
                onPointerDown={(e) => down(e, line)} onPointerMove={move} onPointerUp={up} onPointerCancel={up} onKeyDown={(e) => key(e, line)} onContextMenu={(e) => menu(e, { kind: "folder", id: f.id })}>
                {ids.length ? <Check state={state} label={f.name} onChange={(v) => onCheck(ids, v)} /> : <span />}
                <span className="fr-chev"><ChevronIcon /></span>
                <span className="fr-name">{f.name}</span>
                <span className="fr-count">{ids.length ? t("app.folder.count", on, ids.length) : t("app.folder.empty")}</span>
              </div>
            );
          }
          const m = byId.get(line.id);
          if (!m) return null;
          const name = pick(m.name, m.id);
          const c = conflictsOf(m.id, conflicts);
          const tips = [
            c.overrides.length > 0 && t("app.mods.overridesList", c.overrides.map(withFiles).join(", ")),
            c.overriddenBy.length > 0 && t("app.mods.overriddenByList", c.overriddenBy.map(withFiles).join(", ")),
            t("app.mods.conflictsClick"),
          ].filter(Boolean);
          const color = line.folder ? tree?.find((n) => n.kind === "folder" && n.folder.id === line.folder) : undefined;
          const cls = ["tr", line.folder && "in", selected === m.id && "sel", checked.has(m.id) && "checked", draggingKeys.has(m.id) && "lifted"].filter(Boolean).join(" ");
          return (
            <div key={m.id} data-key={m.id} role="row" tabIndex={0} className={cls} aria-selected={selected === m.id}
              style={color?.kind === "folder" ? ({ "--fc": color.folder.color } as CSSProperties) : undefined}
              onPointerDown={(e) => down(e, line)} onPointerMove={move} onPointerUp={up} onPointerCancel={up} onKeyDown={(e) => key(e, line)} onContextMenu={(e) => menu(e, { kind: "mod", id: m.id })}>
              <Check state={checked.has(m.id)} label={name} onChange={(on, shift) => check(m.id, on, shift)} />
              <span className="num">{order.indexOf(m.id) + 1}</span>
              <button role="switch" aria-checked={m.on} aria-label={name} className={m.on ? "sw on" : "sw"} data-tip={t(m.on ? "app.mods.turnOff" : "app.mods.turnOn", name)}
                {...stop} onClick={() => onToggle([m.id], !m.on)} />
              <div className="mod-cell">
                <Thumb image={m.image} name={name} />
                <div className="who">
                  <div className="nm">
                    {name}
                    <span className="ver">{m.version ?? t("app.mods.imported")}</span>
                    {m.bundled && <span className="tag">{t("app.mods.bundled")}</span>}
                  </div>
                  {pick(m.description) && <div className="sub">{pick(m.description)}</div>}
                </div>
              </div>
              {tips.length > 1 ? (
                <button className={c.overriddenBy.length ? "bare cf-ico lose" : "bare cf-ico"} aria-label={t("app.drawer.conflicts")}
                  data-tip-title={t("app.drawer.conflicts")} data-tip={tips.join("\n")} {...stop} onClick={() => onConflicts(m.id)}>
                  <WarnIcon />
                </button>
              ) : <span />}
              <span className={`scope ${m.scope}`} data-tip-title={t(`app.scope.${m.scope}Mod`)} data-tip={t(`app.scope.${m.scope}Hint`)}><i />{t(`app.scope.${m.scope}`)}</span>
            </div>
          );
        })}
        {marker && !marker.onto && <div className={marker.indent ? "drop-line in" : "drop-line"} style={{ top: marker.y }} aria-hidden="true" />}
      </div>
      {marker && <div className="drag-ghost" style={{ left: marker.x + 14, top: marker.py + 10 }} aria-hidden="true">{marker.label}</div>}
    </div>
  );
}
