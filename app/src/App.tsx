import { useEffect, useState } from "react";
import { refresh, useSnapshot } from "./api";
import { NavBar, type Tab } from "./NavBar";
import { Notices } from "./NoticeList";
import { loadSettings, useAppSettings } from "./settings";

export default function App() {
  const snap = useSnapshot();
  const settings = useAppSettings();
  const [tab, setTab] = useState<Tab>("mods");
  const [busy] = useState(false);

  useEffect(() => {
    loadSettings().then(refresh);
  }, []);

  if (!settings) return null;
  return (
    <div className="app">
      <NavBar tab={tab} onTab={setTab} snap={snap} busy={busy} onPurge={() => {}} onDeploy={() => {}} onPlay={() => {}} />
      <main className="page">
        <h1 className="cap">{tab}</h1>
        <p>{snap ? `${snap.mods.length} mods` : ""}</p>
      </main>
      <Notices />
    </div>
  );
}
