// Shown when the last launch stopped while a mod was loading (spec 4.1), or when the game stopped later
// without closing normally. Nothing names a mod then, so it offers the report instead, and goes away
// for good once dismissed, until the next time.
import { useState } from "react";
import { run } from "../api";
import { CloseIcon, WarnIcon } from "../Icons";
import { pick, t } from "../i18n";
import { copyReport } from "../report";
import type { Snapshot } from "../types";

const DISMISSED_KEY = "obsidian.crashDismissed";

function readDismissed(): string | null {
  try {
    return localStorage.getItem(DISMISSED_KEY);
  } catch {
    return null;
  }
}

export function CrashBanner({ snap }: { snap: Snapshot }) {
  const [dismissed, setDismissed] = useState(readDismissed);
  const row = snap.mods.find((m) => m.id === snap.crashCulprit);
  if (snap.crashCulprit && (!row || row.on)) {
    const name = row ? pick(row.name, row.id) : snap.crashCulprit;
    return (
      <div className="banner" role="alert">
        <WarnIcon />
        <span>{t("app.crash.text", name)}</span>
        {row && (
          <button className="btn small" onClick={() => run("set_enabled", { ids: [row.id], on: false })}>
            {t("app.crash.turnOff", name)}
          </button>
        )}
      </div>
    );
  }
  const end = snap.uncleanEnd;
  if (!end || snap.crashCulprit || String(end.stamp) === dismissed) return null;
  const dismiss = () => {
    setDismissed(String(end.stamp));
    try { localStorage.setItem(DISMISSED_KEY, String(end.stamp)); } catch { /* it comes back next time */ }
  };
  return (
    <div className="banner" role="alert">
      <WarnIcon />
      <span>{t("app.crash.unclean")}</span>
      <button className="btn small" onClick={copyReport}>{t("app.crash.copyReport")}</button>
      <button className="bare" onClick={dismiss} aria-label={t("app.crash.dismiss")} data-tip={t("app.crash.dismiss")}><CloseIcon /></button>
    </div>
  );
}
