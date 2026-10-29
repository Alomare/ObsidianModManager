// The Mods page: header, crash banner, the table and (Task 6) the drawer (spec 4.1).
import { useMemo, useState } from "react";
import { run } from "../api";
import { SearchIcon, WarnIcon } from "../Icons";
import { pick, t } from "../i18n";
import type { Snapshot } from "../types";
import { CrashBanner } from "./CrashBanner";
import { pickAndImport } from "./dropImport";
import { ModTable } from "./ModTable";
import { filterMods } from "./rows";

export type DrawerView = { kind: "mod"; id: string } | { kind: "conflicts" } | null;

export function ModsPage({ snap }: { snap: Snapshot }) {
  const [query, setQuery] = useState("");
  const [pending, setPending] = useState<string[] | null>(null);
  const [view, setView] = useState<DrawerView>(null);

  const byId = useMemo(() => new Map(snap.mods.map((m) => [m.id, m])), [snap.mods]);
  const names = useMemo(() => new Map(snap.mods.map((m) => [m.id, pick(m.name, m.id)])), [snap.mods]);
  const order = pending ?? snap.mods.map((m) => m.id);
  const rows = filterMods(order.flatMap((id) => byId.get(id) ?? []), query);
  const searching = query.trim() !== "";
  const conflicts = snap.conflicts.length;

  const drop = async (ids: string[]) => {
    setPending(ids);
    await run("set_order", { ids });
    setPending(null);
  };

  return (
    <div className="mods">
      <div className="head">
        <h1 className="cap">{t("app.nav.mods")}</h1>
        <label className="pick">
          <span>{t("app.mods.profile")}</span>
          <select value={snap.profile} onChange={(e) => run("use_profile", { name: e.target.value })}>
            {snap.profiles.map((p) => <option key={p} value={p}>{p}</option>)}
          </select>
        </label>
        <button className={conflicts ? "cbtn hot" : "cbtn"} aria-pressed={view?.kind === "conflicts"} onClick={() => setView({ kind: "conflicts" })}>
          <WarnIcon />
          {t("app.mods.conflicts", conflicts)}
        </button>
        <label className="search">
          <SearchIcon />
          <input type="search" value={query} placeholder={t("app.mods.search")} aria-label={t("app.mods.search")} onChange={(e) => setQuery(e.target.value)} />
        </label>
      </div>
      <CrashBanner snap={snap} />
      <div className="mods-body">
        <section className="list">
          <ModTable rows={rows} order={order} names={names} canDrag={!searching}
            selected={view?.kind === "mod" ? view.id : null}
            onSelect={(id) => setView({ kind: "mod", id })}
            onToggle={(id, on) => run("set_enabled", { id, on })}
            onDrag={setPending} onDrop={drop} />
          {rows.length === 0 && searching && <p className="empty">{t("app.mods.noMatch")}</p>}
          <div className="drop">
            <span>{t("app.mods.dropHint")}</span>
            <button className="link" onClick={() => pickAndImport(false)}>{t("app.mods.importZip")}</button>
            <button className="link" onClick={() => pickAndImport(true)}>{t("app.mods.importFolder")}</button>
          </div>
        </section>
      </div>
    </div>
  );
}
