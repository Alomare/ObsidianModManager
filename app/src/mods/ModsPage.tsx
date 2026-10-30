// The Mods page: header, crash banner, the table and the drawer (spec 4.1 and 4.2).
import { useMemo, useState } from "react";
import { run } from "../api";
import { ChevronIcon, CloseIcon, ProfilesIcon, SearchIcon, WarnIcon } from "../Icons";
import { pick, t } from "../i18n";
import { ProfilesDialog } from "../ProfilesDialog";
import type { Snapshot } from "../types";
import { winners } from "./conflicts";
import { CrashBanner } from "./CrashBanner";
import { Drawer } from "./Drawer";
import { pickAndImport } from "./dropImport";
import { ModTable } from "./ModTable";
import { filterMods } from "./rows";

export type DrawerView = { kind: "mod"; id: string } | { kind: "conflicts" } | null;

export function ModsPage({ snap }: { snap: Snapshot }) {
  const [query, setQuery] = useState("");
  const [pending, setPending] = useState<string[] | null>(null);
  const [view, setView] = useState<DrawerView>(null);
  const [profiles, setProfiles] = useState(false);

  const byId = useMemo(() => new Map(snap.mods.map((m) => [m.id, m])), [snap.mods]);
  const names = useMemo(() => new Map(snap.mods.map((m) => [m.id, pick(m.name, m.id)])), [snap.mods]);
  const order = pending ?? snap.mods.map((m) => m.id);
  const rows = filterMods(order.flatMap((id) => byId.get(id) ?? []), query);
  const searching = query.trim() !== "";
  const conflicts = snap.conflicts.length;
  const shownConflicts = useMemo(() => (pending ? winners(snap.conflicts, pending) : snap.conflicts), [snap.conflicts, pending]);

  const drop = async (ids: string[]) => {
    setPending(ids);
    await run("set_order", { ids });
    setPending(null);
  };

  return (
    <div className="mods">
      <div className="head">
        <h1 className="cap">{t("app.nav.mods")}</h1>
        <button className="select-btn profile-btn" onClick={() => setProfiles(true)} data-tip-title={t("app.mods.profile")} data-tip={t("app.mods.profileHint")}>
          <ProfilesIcon />
          <span className="select-prefix">{t("app.mods.profile")}</span>
          <span className="select-value">{snap.profile}</span>
          <ChevronIcon />
        </button>
        <button className={conflicts ? "cbtn hot" : "cbtn"} data-tip-title={t("app.drawer.conflicts")} data-tip={t("app.mods.conflictsHint")} aria-pressed={view?.kind === "conflicts"} onClick={() => setView({ kind: "conflicts" })}>
          <WarnIcon />
          {t("app.mods.conflicts", conflicts)}
        </button>
        <label className="search">
          <SearchIcon />
          <input type="text" value={query} placeholder={t("app.mods.search")} aria-label={t("app.mods.search")} onChange={(e) => setQuery(e.target.value)}
            onKeyDown={(e) => e.key === "Escape" && setQuery("")} />
          {query && <button className="bare" onClick={() => setQuery("")} aria-label={t("app.mods.clearSearch")} data-tip={t("app.mods.clearSearch")}><CloseIcon /></button>}
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
        {profiles && <ProfilesDialog snap={snap} onClose={() => setProfiles(false)} />}
        <Drawer view={view} mods={snap.mods} conflicts={shownConflicts} order={order} names={names} onClose={() => setView(null)} />
      </div>
    </div>
  );
}
