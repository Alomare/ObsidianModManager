// What the library couldn't read: mods that stay out of the game until they're fixed or removed, and
// profiles that were set aside. A damaged profile is news once, so it can be dismissed.
import { useState } from "react";
import { run } from "../api";
import { CloseIcon, WarnIcon } from "../Icons";
import { t } from "../i18n";
import type { Snapshot } from "../types";

const DISMISSED_KEY = "obsidian.damagedDismissed";

function readDismissed(): string {
  try {
    return localStorage.getItem(DISMISSED_KEY) ?? "";
  } catch {
    return "";
  }
}

export function Problems({ snap }: { snap: Snapshot }) {
  const [dismissed, setDismissed] = useState(readDismissed);
  const damaged = snap.damagedProfiles.join(", ");
  const dismiss = () => {
    setDismissed(damaged);
    try { localStorage.setItem(DISMISSED_KEY, damaged); } catch { /* it comes back next time */ }
  };
  return (
    <>
      {snap.broken.length > 0 && (
        <div className="banner" role="alert">
          <WarnIcon />
          <span data-tip={snap.broken.map((b) => `${b.folder}: ${b.reason}`).join("\n")}>{t("app.problem.broken", snap.broken.map((b) => b.folder).join(", "))}</span>
          <button className="btn small" onClick={() => run("remove_mods", { ids: snap.broken.map((b) => b.folder) })}>{t("app.problem.remove")}</button>
        </div>
      )}
      {damaged && damaged !== dismissed && (
        <div className="banner" role="alert">
          <WarnIcon />
          <span>{t("app.problem.damaged", damaged)}</span>
          <button className="bare" onClick={dismiss} aria-label={t("app.crash.dismiss")} data-tip={t("app.crash.dismiss")}><CloseIcon /></button>
        </div>
      )}
    </>
  );
}
