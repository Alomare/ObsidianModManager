// The navigation bar: logo, tabs, game and deploy state, and Purge, Deploy and Play (spec section 3).
import type { ComponentType } from "react";
import { CogIcon, DeployIcon, Logo, ModsIcon, PlayIcon, ProfilesIcon, PurgeIcon } from "./Icons";
import { t } from "./i18n";
import type { Snapshot } from "./types";

export type Tab = "mods" | "profiles" | "settings";

type Props = {
  tab: Tab;
  onTab: (t: Tab) => void;
  snap: Snapshot | null;
  busy: boolean;
  onPurge: () => void;
  onDeploy: () => void;
  onPlay: () => void;
};

const TABS: [Tab, ComponentType][] = [["mods", ModsIcon], ["profiles", ProfilesIcon], ["settings", CogIcon]];

export function NavBar({ tab, onTab, snap, busy, onPurge, onDeploy, onPlay }: Props) {
  const running = snap?.game === "running";
  const locked = busy || running || !snap || snap.game === "notFound";
  const why = running ? t("app.action.closeGameFirst") : undefined;
  const waiting = snap?.changes === "Waiting";
  return (
    <nav className="nav">
      <div className="brand">
        <Logo className="brand-logo" />
        <span className="cap">Obsidian</span>
      </div>
      <div className="tabs" role="tablist">
        {TABS.map(([id, Icon]) => (
          <button key={id} role="tab" aria-selected={tab === id} className={tab === id ? "tab cur" : "tab"} onClick={() => onTab(id)}>
            <Icon />
            <span className="cap">{t(`app.nav.${id}`)}</span>
          </button>
        ))}
      </div>
      <div className="nav-end">
        <div className="state">
          {/* HD1 gets no more updates, so a supported build needs no label. */}
          {(!snap || snap.game !== "supported") && <span>{snap ? t(`app.game.${snap.game}`) : t("app.loading")}</span>}
          <b className={waiting ? "waiting" : undefined}>{snap ? t(`app.changes.${snap.changes}`) : ""}</b>
        </div>
        <div className="actions">
          <button className="btn icon" onClick={onPurge} disabled={locked} title={why ?? t("app.action.purgeHint")} aria-label={t("app.action.purge")}>
            <PurgeIcon />
          </button>
          <button className={waiting ? "btn icon go" : "btn icon"} onClick={onDeploy} disabled={locked} title={why ?? t("app.action.deployHint")} aria-label={t("app.action.deploy")}>
            <DeployIcon />
          </button>
          <button className="btn play" onClick={onPlay} disabled={locked} title={why}>
            <PlayIcon />
            <span>{t("app.action.play")}</span>
          </button>
        </div>
      </div>
    </nav>
  );
}
