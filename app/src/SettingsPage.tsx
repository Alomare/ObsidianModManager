// Settings (spec 4.4): System (game, multiplayer, language, updates, data) and Theme (colours,
// navigation bar, size, animations). App settings save to app.json at once.
import { open } from "@tauri-apps/plugin-dialog";
import { openUrl } from "@tauri-apps/plugin-opener";
import { useEffect, useState } from "react";
import { call, errorText, run } from "./api";
import { ExternalIcon } from "./Icons";
import { LANGUAGES, language, t } from "./i18n";
import { LINKS } from "./links";
import { notify } from "./notices";
import { Select } from "./Select";
import { updateSettings, useAppSettings } from "./settings";
import { motionOn, systemReducesMotion } from "./theme";
import type { AppSettings, Snapshot } from "./types";
import { checkForUpdate, installUpdate, useUpdates } from "./updates";

type SystemInfo = { dataDir: string; backups: { name: string; path: string }[]; chosenGameDir: string | null };

export type SettingsTab = "system" | "theme";

export function SettingsPage({ snap, tab, onTab }: { snap: Snapshot; tab: SettingsTab; onTab: (t: SettingsTab) => void }) {
  return (
    <div className="settings">
      <div className="head">
        <h1 className="cap">{t("app.nav.settings")}</h1>
        <div className="subtabs" role="tablist">
          {(["system", "theme"] as const).map((id) => (
            <button key={id} role="tab" aria-selected={tab === id} className={tab === id ? "cur" : undefined} onClick={() => onTab(id)}>
              {t(`app.settings.${id}`)}
            </button>
          ))}
        </div>
      </div>
      <div className="view" key={tab}>{tab === "system" ? <SystemTab snap={snap} /> : <ThemeTab />}</div>
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="set-section">
      <h2 className="cap">{title}</h2>
      {children}
    </section>
  );
}

/** One row: what it is (and a line about it) on the left, the control on the right. */
function Row({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return (
    <div className="set-row">
      <div className="set-text">
        <div className="l">{label}</div>
        {hint && <div className="d">{hint}</div>}
      </div>
      <div className="set-ctl">{children}</div>
    </div>
  );
}

function Segmented<T extends string | number>({ value, options, onChange, label }: { value: T; options: [T, string][]; onChange: (v: T) => void; label: string }) {
  return (
    <div className="seg" role="radiogroup" aria-label={label}>
      {options.map(([v, text]) => (
        <button key={String(v)} role="radio" aria-checked={v === value} className={v === value ? "on" : undefined} onClick={() => v !== value && onChange(v)}>
          {text}
        </button>
      ))}
    </div>
  );
}

function stamp(name: string) {
  const m = /^(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})/.exec(name);
  if (!m) return name;
  const d = new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]);
  return d.toLocaleString(language(), { dateStyle: "medium", timeStyle: "short" });
}

function SystemTab({ snap }: { snap: Snapshot }) {
  const settings = useAppSettings()!;
  const [info, setInfo] = useState<SystemInfo | null>(null);
  const [checking, setChecking] = useState(false);
  useEffect(() => {
    call<SystemInfo>("system_info").then(setInfo).catch((e) => notify("error", errorText(e)));
  }, [snap]);
  const openFolder = (path: string) => call("open_folder", { path }).catch((e) => notify("error", errorText(e)));
  const change = async () => {
    const picked = await open({ directory: true, defaultPath: snap.gameDir ?? undefined, title: t("app.settings.pickGame") });
    if (typeof picked === "string") run("set_game_dir", { path: picked });
  };
  const check = async () => {
    setChecking(true);
    await run("check_game");
    setChecking(false);
  };
  const gameLine = t(`app.settings.build.${snap.game}`);

  return (
    <>
      <Section title={t("app.settings.game")}>
        <Row label={snap.gameDir ?? t("app.game.notFound")} hint={`${gameLine}${info?.chosenGameDir ? "" : snap.gameDir ? ` ${t("app.settings.foundSteam")}` : ""}`}>
          {snap.gameDir && <button className="btn small" onClick={() => openFolder(snap.gameDir!)}>{t("app.settings.open")}</button>}
          <button className="btn small" onClick={change}>{t("app.settings.change")}</button>
          {info?.chosenGameDir && <button className="btn small" onClick={() => run("set_game_dir", { path: null })} data-tip={t("app.settings.useSteamHint")}>{t("app.settings.useSteam")}</button>}
          <button className="btn small" onClick={check} disabled={checking || !snap.gameDir}>{t("app.settings.checkAgain")}</button>
        </Row>
      </Section>

      <Section title={t("app.settings.multiplayer")}>
        <Row label={t("app.settings.consent", snap.profile)} hint={t("app.settings.consentHint")}>
          <button role="switch" aria-checked={snap.consent} aria-label={t("app.settings.consent", snap.profile)} className={snap.consent ? "sw on" : "sw"}
            onClick={() => run("set_consent", { on: !snap.consent })} />
        </Row>
      </Section>

      <Section title={t("app.settings.language")}>
        <Row label={t("app.settings.languageLabel")}>
          <Select value={settings.language ?? ""} label={t("app.settings.language")}
            options={[{ value: "", label: t("app.settings.systemLanguage") }, ...LANGUAGES.map(([value, label]) => ({ value, label }))]}
            onChange={(v) => updateSettings({ language: v || null })} />
        </Row>
      </Section>

      <Section title={t("app.settings.updates")}>
        <UpdateRow snap={snap} />
        {!snap.portable && (
          <Row label={t("app.settings.updateMode")} hint={t(`app.settings.updates.${settings.updates}Hint`)}>
            <Select<AppSettings["updates"]> value={settings.updates} label={t("app.settings.updateMode")}
              options={(["manual", "prompt", "auto"] as const).map((v) => ({ value: v, label: t(`app.settings.updates.${v}`) }))}
              onChange={(v) => updateSettings({ updates: v })} />
          </Row>
        )}
      </Section>

      <Section title={t("app.settings.data")}>
        <Row label={info?.dataDir ?? ""} hint={snap.portable ? t("app.settings.portable") : t("app.settings.dataHint")}>
          {info && <button className="btn small" onClick={() => openFolder(info.dataDir)}>{t("app.settings.open")}</button>}
        </Row>
        <Row label={t("app.settings.backups")} hint={t("app.settings.backupsHint")}>
          <span />
        </Row>
        {info && info.backups.length === 0 && <p className="muted set-note">{t("app.settings.noBackups")}</p>}
        {info && info.backups.length > 0 && (
          <ul className="backups">
            {info.backups.map((b) => (
              <li key={b.name}>
                <span>{stamp(b.name)}</span>
                <button className="link small" onClick={() => openFolder(b.path)}>{t("app.settings.open")}</button>
              </li>
            ))}
          </ul>
        )}
      </Section>
    </>
  );
}

function UpdateRow({ snap }: { snap: Snapshot }) {
  const u = useUpdates();
  const busy = u.phase === "checking" || u.phase === "downloading" || u.phase === "installing";
  const pct = u.total ? Math.round((u.got / u.total) * 100) : 0;
  const line =
    u.phase === "checking" ? t("app.update.checking")
    : u.phase === "none" ? t("app.update.none")
    : u.phase === "found" ? t("app.update.found", u.version ?? "") + (u.error ? ` ${t("app.update.failedInstall", u.error)}` : "")
    : u.phase === "failed" ? t("app.update.failed")
    : u.phase === "downloading" ? t("app.update.downloading", pct)
    : u.phase === "installing" ? t("app.update.installing")
    : snap.portable ? t("app.settings.portableHint") : "";
  return (
    <Row label={t("app.settings.version", snap.version)} hint={line || undefined}>
      {u.phase === "found" && !snap.portable && <button className="btn small play" onClick={installUpdate}>{t("app.update.install")}</button>}
      <button className="btn small" disabled={busy} onClick={() => checkForUpdate()}>{t("app.update.checkNow")}</button>
      <button className="btn small" onClick={() => openUrl(LINKS.releases).catch(() => {})}>{t("app.settings.releases")} <ExternalIcon /></button>
    </Row>
  );
}

function ThemeTab() {
  const s = useAppSettings()!;
  const motion = motionOn(s.motion, systemReducesMotion());
  return (
    <Section title={t("app.settings.appearance")}>
      <Row label={t("app.settings.colours")}>
        <Segmented label={t("app.settings.colours")} value={s.theme} onChange={(theme) => updateSettings({ theme })}
          options={[["default", t("app.settings.theme.default")], ["dark", t("app.settings.theme.dark")], ["light", t("app.settings.theme.light")]]} />
      </Row>
      <Row label={t("app.settings.navBar")} hint={t("app.settings.navHint")}>
        <Segmented label={t("app.settings.navBar")} value={s.nav} onChange={(nav) => updateSettings({ nav })}
          options={[["top", t("app.settings.nav.top")], ["left", t("app.settings.nav.left")]]} />
      </Row>
      <Row label={t("app.settings.scale")}>
        <Segmented label={t("app.settings.scale")} value={s.scale} onChange={(scale) => updateSettings({ scale })}
          options={([90, 100, 110, 125] as const).map((v) => [v, `${v} %`])} />
      </Row>
      <Row label={t("app.settings.textSize")} hint={t("app.settings.textSizeHint")}>
        <Segmented label={t("app.settings.textSize")} value={s.text} onChange={(text) => updateSettings({ text })}
          options={[["small", t("app.settings.text.small")], ["normal", t("app.settings.text.normal")], ["large", t("app.settings.text.large")]]} />
      </Row>
      <Row label={t("app.settings.animations")} hint={s.motion === null && systemReducesMotion() ? t("app.settings.animationsSystem") : undefined}>
        <button role="switch" aria-checked={motion} aria-label={t("app.settings.animations")} className={motion ? "sw on" : "sw"}
          onClick={() => updateSettings({ motion: !motion })} />
      </Row>
    </Section>
  );
}
