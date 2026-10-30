// The navigation bar: the tabs (Home, Mods, Settings), then the "prepare to play" area: the multiplayer consent of the active
// profile, and Purge, Deploy and Play (spec section 3). Deploy turns green while changes wait.
import type { ComponentType } from "react";
import { run } from "./api";
import { CogIcon, DeployIcon, HomeIcon, ModsIcon, PlayIcon, PurgeIcon, WarnIcon } from "./Icons";
import { t } from "./i18n";
import type { Snapshot } from "./types";

export type Tab = "home" | "mods" | "settings";

type Props = {
  tab: Tab;
  onTab: (t: Tab) => void;
  snap: Snapshot | null;
  busy: boolean;
  onPurge: () => void;
  onDeploy: () => void;
  onPlay: () => void;
};

const TABS: [Tab, ComponentType][] = [["home", HomeIcon], ["mods", ModsIcon], ["settings", CogIcon]];

export function NavBar({ tab, onTab, snap, busy, onPurge, onDeploy, onPlay }: Props) {
  const running = snap?.game === "running";
  const missing = snap?.game === "notFound";
  const locked = busy || running || !snap || missing;
  const why = running ? t("app.action.closeGameFirst") : missing ? t("app.error.GameNotFound") : undefined;
  const waiting = snap?.changes === "Waiting";
  // HD1 gets no more updates, so only a missing game or an unknown build needs a word here.
  const warn = snap && (missing || snap.game === "unknown") ? t(`app.game.${snap.game}`) : null;
  return (
    <nav className="nav">
      <div className="tabs" role="tablist">
        {TABS.map(([id, Icon]) => (
          <button key={id} role="tab" aria-selected={tab === id} className={tab === id ? "tab cur" : "tab"} onClick={() => onTab(id)}>
            <Icon />
            <span className="cap">{t(`app.nav.${id}`)}</span>
          </button>
        ))}
      </div>
      <div className="nav-end">
        {warn && (
          <span className="nav-warn" data-tip-title={warn} data-tip={t(`app.settings.build.${snap!.game}`)}>
            <WarnIcon />
            {warn}
          </span>
        )}
        {snap && (
          <label className="consent" data-tip-title={t("app.nav.consentTitle", snap.profile)} data-tip={t("app.nav.consentHint")}>
            <span>{t("app.nav.consent")}</span>
            <button role="switch" aria-checked={snap.consent} aria-label={t("app.nav.consentTitle", snap.profile)} className={snap.consent ? "sw on" : "sw"}
              onClick={() => run("set_consent", { on: !snap.consent })} />
          </label>
        )}
        <div className="actions">
          <button className="btn icon" onClick={onPurge} disabled={locked} data-tip-title={t("app.action.purge")} data-tip={why ?? t("app.action.purgeHint")} aria-label={t("app.action.purge")}>
            <PurgeIcon />
          </button>
          <button className={waiting ? "btn icon go" : "btn icon"} onClick={onDeploy} disabled={locked} data-tip-title={t("app.action.deploy")}
            data-tip={why ?? (waiting ? t("app.action.deployWaiting") : t(`app.action.deploy${snap?.changes ?? "UpToDate"}`))} aria-label={t("app.action.deploy")}>
            <DeployIcon />
          </button>
          <button className="btn play" onClick={onPlay} disabled={locked} data-tip={why ?? t("app.action.playHint")}>
            <PlayIcon />
            <span>{t("app.action.play")}</span>
          </button>
        </div>
      </div>
    </nav>
  );
}
