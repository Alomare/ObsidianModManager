import { listen } from "@tauri-apps/api/event";
import { useEffect, useState } from "react";
import { deploy, play, purge } from "./actions";
import { loadSnapshot, refresh, useSnapshot } from "./api";
import { useLocked } from "./busy";
import { Confirm } from "./Confirm";
import { t } from "./i18n";
import { listenForDrops, type DropState } from "./mods/dropImport";
import { HomePage } from "./HomePage";
import { ModsPage } from "./mods/ModsPage";
import { NavBar } from "./NavBar";
import { go as setTab, useNav } from "./nav";
import { WikiPage } from "./WikiPage";
import { SettingsPage, type SettingsTab } from "./SettingsPage";
import { Notices } from "./NoticeList";
import { loadSettings, useAppSettings } from "./settings";
import { StatusBar } from "./StatusBar";
import { Tooltip } from "./Tooltip";
import { installUpdate, startupUpdate, useUpdates } from "./updates";

export default function App() {
  const snap = useSnapshot();
  const settings = useAppSettings();
  const busy = useLocked();
  const { tab } = useNav();
  const [dropping, setDropping] = useState<DropState>(null);
  const [askPurge, setAskPurge] = useState(false);
  const [settingsTab, setSettingsTab] = useState<SettingsTab>("system");
  const [askUpdate, setAskUpdate] = useState(false);
  const update = useUpdates();
  const ready = !!snap && !!settings;
  // The update check runs once per launch, as soon as the window knows whether it is a portable copy.
  useEffect(() => {
    if (snap && settings) startupUpdate(settings.updates, snap.portable).then((a) => setAskUpdate(a === "ask"));
  }, [ready]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    loadSettings();
    loadSnapshot();
    // The browser menu (Back, Reload, Inspect) has no place in the app; text fields keep theirs.
    const menu = (e: MouseEvent) => !(e.target as Element).closest?.("input, textarea") && e.preventDefault();
    document.addEventListener("contextmenu", menu);
    // Files dragged in bring the Mods tab forward, since only the mod list takes them.
    const stopDrops = listenForDrops(() => document.querySelector(".mods .list"), () => setTab("mods"), setDropping);
    // The Rust side says when the game starts or stops; the snapshot then locks or frees the buttons.
    const game = listen("game-state", () => refresh());
    return () => {
      stopDrops();
      game.then((f) => f());
      document.removeEventListener("contextmenu", menu);
    };
  }, []);

  if (!settings) return null;
  return (
    <div className="app">
      <NavBar tab={tab} onTab={setTab} snap={snap} busy={busy} onPurge={() => setAskPurge(true)} onDeploy={deploy} onPlay={play} />
      <main className={tab === "home" || tab === "wiki" ? "page bleed" : "page"}>
        {tab === "home" && <div className="view" key="home"><HomePage /></div>}
        {/* Mods stays mounted while hidden: a long list then costs nothing to come back to. */}
        {snap && <div className="view" hidden={tab !== "mods"}><ModsPage snap={snap} /></div>}
        {tab === "wiki" && <div className="view" key="wiki"><WikiPage /></div>}
        {snap && tab === "settings" && <div className="view" key="settings"><SettingsPage snap={snap} tab={settingsTab} onTab={setSettingsTab} /></div>}
      </main>
      <StatusBar version={snap?.version ?? null} updateFound={update.phase === "found"} onUpdates={() => { setSettingsTab("system"); setTab("settings"); }} />
      {dropping && (
        <div className={dropping.inside ? "dropzone cap over" : "dropzone cap"}
          style={{ left: dropping.rect.left, top: dropping.rect.top, width: dropping.rect.width, height: dropping.rect.height }}>
          {t("app.mods.dropHere")}
        </div>
      )}
      {askPurge && (
        <Confirm title={t("app.purge.title")} text={t("app.purge.text")} confirm={t("app.action.purge")}
          onCancel={() => setAskPurge(false)} onConfirm={() => { setAskPurge(false); purge(); }} />
      )}
      {askUpdate && (
        <Confirm title={t("app.update.title", update.version ?? "")} text={t("app.update.text")} confirm={t("app.update.install")}
          tone="go" onCancel={() => setAskUpdate(false)} onConfirm={() => { setAskUpdate(false); installUpdate(); }} />
      )}
      <Notices />
      <Tooltip />
    </div>
  );
}
