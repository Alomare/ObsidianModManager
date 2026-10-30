// Shown when the last launch stopped while a mod was loading (spec 4.1).
import { run } from "../api";
import { WarnIcon } from "../Icons";
import { pick, t } from "../i18n";
import type { Snapshot } from "../types";

export function CrashBanner({ snap }: { snap: Snapshot }) {
  const row = snap.mods.find((m) => m.id === snap.crashCulprit);
  if (!snap.crashCulprit || (row && !row.on)) return null;
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
