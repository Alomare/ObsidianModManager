import { useEffect, useState } from "react";
import { refresh, useSnapshot } from "./api";
import { t } from "./i18n";
import { listenForDrops } from "./mods/dropImport";
import { ModsPage } from "./mods/ModsPage";
import { NavBar, type Tab } from "./NavBar";
import { Notices } from "./NoticeList";
import { loadSettings, useAppSettings } from "./settings";
import { StatusBar } from "./StatusBar";

export default function App() {
  const snap = useSnapshot();
  const settings = useAppSettings();
  const [tab, setTab] = useState<Tab>("mods");
  const [busy] = useState(false);
  const [dropping, setDropping] = useState(false);

  useEffect(() => {
    loadSettings().then(refresh);
    return listenForDrops(setDropping);
  }, []);

  if (!settings) return null;
  return (
    <div className="app">
      <NavBar tab={tab} onTab={setTab} snap={snap} busy={busy} onPurge={() => {}} onDeploy={() => {}} onPlay={() => {}} />
      <main className="page">
        <div className="view" key={tab}>
          {snap && tab === "mods" && <ModsPage snap={snap} />}
          {tab !== "mods" && <h1 className="cap">{t(`app.nav.${tab}`)}</h1>}
        </div>
      </main>
      <StatusBar version={snap?.version ?? null} onUpdates={() => setTab("settings")} />
      {dropping && <div className="dropzone cap">{t("app.mods.dropHere")}</div>}
      <Notices />
    </div>
  );
}
