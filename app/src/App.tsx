import { listen } from "@tauri-apps/api/event";
import { useEffect, useState } from "react";
import { deploy, play, purge } from "./actions";
import { loadSnapshot, refresh, useSnapshot } from "./api";
import { useBusy } from "./busy";
import { Confirm } from "./Confirm";
import { t } from "./i18n";
import { listenForDrops } from "./mods/dropImport";
import { ModsPage } from "./mods/ModsPage";
import { NavBar, type Tab } from "./NavBar";
import { ProfilesPage } from "./ProfilesPage";
import { SettingsPage, type SettingsTab } from "./SettingsPage";
import { Notices } from "./NoticeList";
import { loadSettings, useAppSettings } from "./settings";
import { StatusBar } from "./StatusBar";
import { Tooltip } from "./Tooltip";

export default function App() {
  const snap = useSnapshot();
  const settings = useAppSettings();
  const busy = useBusy() !== null;
  const [tab, setTab] = useState<Tab>("mods");
  const [dropping, setDropping] = useState(false);
  const [askPurge, setAskPurge] = useState(false);
  const [settingsTab, setSettingsTab] = useState<SettingsTab>("system");

  useEffect(() => {
    loadSettings();
    loadSnapshot();
    // The browser menu (Back, Reload, Inspect) has no place in the app; text fields keep theirs.
    const menu = (e: MouseEvent) => !(e.target as Element).closest?.("input, textarea") && e.preventDefault();
    document.addEventListener("contextmenu", menu);
    const stopDrops = listenForDrops(setDropping);
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
      <main className="page">
        <div className="view" key={tab}>
          {snap && tab === "mods" && <ModsPage snap={snap} />}
          {snap && tab === "profiles" && <ProfilesPage snap={snap} />}
          {snap && tab === "settings" && <SettingsPage snap={snap} tab={settingsTab} onTab={setSettingsTab} />}
        </div>
      </main>
      <StatusBar version={snap?.version ?? null} onUpdates={() => { setSettingsTab("system"); setTab("settings"); }} />
      {dropping && <div className="dropzone cap">{t("app.mods.dropHere")}</div>}
      {askPurge && (
        <Confirm title={t("app.purge.title")} text={t("app.purge.text")} confirm={t("app.action.purge")}
          onCancel={() => setAskPurge(false)} onConfirm={() => { setAskPurge(false); purge(); }} />
      )}
      <Notices />
      <Tooltip />
    </div>
  );
}
