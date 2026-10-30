// The profiles dialog, opened from the Profile button on the Mods page: every profile with what it
// holds, and New, Import, Duplicate, Rename, Export, Delete and Use. A profile keeps the load order, which mods are
// on, option values, keys and consent.
import { useEffect, useState } from "react";
import { run } from "./api";
import { Confirm } from "./Confirm";
import { CloseIcon, CopyIcon, ExportIcon, ImportIcon, PenIcon, PlusIcon, TrashIcon } from "./Icons";
import { t } from "./i18n";
import { exportProfile, importProfile } from "./profileZip";
import { Prompt } from "./Prompt";
import { Thumb } from "./Thumb";
import type { ProfileRow, Snapshot } from "./types";

type Ask = { kind: "new" } | { kind: "duplicate" | "rename" | "delete"; name: string } | null;

export function ProfilesDialog({ snap, onClose }: { snap: Snapshot; onClose: () => void }) {
  const [ask, setAsk] = useState<Ask>(null);
  const close = () => setAsk(null);
  const last = snap.profileRows.length <= 1;
  useEffect(() => {
    // Esc closes the question on top first, then the dialog.
    const key = (e: KeyboardEvent) => e.key === "Escape" && !ask && onClose();
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, [ask, onClose]);

  return (
    <div className="modal-back" onPointerDown={(e) => e.target === e.currentTarget && onClose()}>
    <div className="modal profiles" role="dialog" aria-modal="true" aria-label={t("app.profiles.title")}>
      <div className="head">
        <h2 className="cap">{t("app.profiles.title")}</h2>
        <div className="profiles-tools">
          <button className="btn small" onClick={() => setAsk({ kind: "new" })}><PlusIcon />{t("app.profiles.new")}</button>
          <button className="btn small" onClick={importProfile} data-tip={t("app.profiles.importHint")}><ImportIcon />{t("app.profiles.import")}</button>
        </div>
        <button className="bare close" onClick={onClose} aria-label={t("app.close")} data-tip={t("app.close")}><CloseIcon /></button>
      </div>
      <p className="muted lead">{t("app.profiles.lead")}</p>
      <ul className="profile-list">
        {snap.profileRows.map((p: ProfileRow) => {
          const active = p.name === snap.profile;
          return (
            <li key={p.name} className={active ? "profile active" : "profile"}>
              <Thumb image={p.image} name={p.name} pick={{ owner: "profile", key: p.name, custom: !!p.image }} />
              <div className="profile-text">
                <div className="nm">
                  {p.name}
                  {active && <span className="tag">{t("app.profiles.active")}</span>}
                </div>
                <div className="sub">{t(p.on === 1 ? "app.profiles.oneOn" : "app.profiles.on", p.on)}</div>
                <div className="sub">{t(p.consent ? "app.profiles.consentOn" : "app.profiles.consentOff")}</div>
              </div>
              <div className="profile-actions">
                {!active && <button className="btn small play" onClick={() => run("use_profile", { name: p.name })}>{t("app.profiles.use")}</button>}
                <button className="btn small icon" onClick={() => setAsk({ kind: "duplicate", name: p.name })} aria-label={t("app.profiles.duplicate")}
                  data-tip-title={t("app.profiles.duplicate")} data-tip={t("app.profiles.duplicateHint")}><CopyIcon /></button>
                <button className="btn small icon" onClick={() => setAsk({ kind: "rename", name: p.name })} aria-label={t("app.profiles.rename")}
                  data-tip={t("app.profiles.rename")}><PenIcon /></button>
                <button className="btn small icon" onClick={() => exportProfile(p.name)} aria-label={t("app.profiles.export")}
                  data-tip-title={t("app.profiles.export")} data-tip={t("app.profiles.exportHint")}><ExportIcon /></button>
                <button className="btn small icon danger" disabled={last} aria-label={t("app.profiles.delete")}
                  data-tip-title={t("app.profiles.delete")} data-tip={last ? t("app.error.LastProfile") : undefined}
                  onClick={() => setAsk({ kind: "delete", name: p.name })}><TrashIcon /></button>
              </div>
            </li>
          );
        })}
      </ul>

      {ask?.kind === "new" && (
        <Prompt title={t("app.profiles.newTitle")} label={t("app.profiles.name")} confirm={t("app.profiles.create")} onCancel={close}
          onConfirm={async (name) => { const ok = await run("create_profile", { name, copyOf: null }); if (ok) close(); return ok; }} />
      )}
      {ask?.kind === "duplicate" && (
        <Prompt title={t("app.profiles.duplicateTitle", ask.name)} label={t("app.profiles.name")} initial={t("app.profiles.copyName", ask.name)}
          confirm={t("app.profiles.duplicate")} onCancel={close}
          onConfirm={async (name) => { const ok = await run("create_profile", { name, copyOf: ask.name }); if (ok) close(); return ok; }} />
      )}
      {ask?.kind === "rename" && (
        <Prompt title={t("app.profiles.renameTitle", ask.name)} label={t("app.profiles.name")} initial={ask.name} confirm={t("app.profiles.rename")}
          onCancel={close} onConfirm={async (to) => { const ok = to === ask.name || (await run("rename_profile", { from: ask.name, to })); if (ok) close(); return ok; }} />
      )}
      {ask?.kind === "delete" && (
        <Confirm title={t("app.profiles.deleteTitle", ask.name)} text={t("app.profiles.deleteText")} confirm={t("app.profiles.delete")}
          onCancel={close} onConfirm={() => { close(); run("delete_profile", { name: ask.name }); }} />
      )}
    </div>
    </div>
  );
}
