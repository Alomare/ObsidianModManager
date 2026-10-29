// Along the bottom: the Discord link on the left; on the right the version (it leads to the updates
// in Settings), About, and the notifications shown so far.
import { openUrl } from "@tauri-apps/plugin-opener";
import { useEffect, useRef, useState } from "react";
import { AboutDialog } from "./About";
import { BellIcon, DiscordIcon, InfoIcon } from "./Icons";
import { language, t } from "./i18n";
import { LINKS } from "./links";
import { useNoticeLog } from "./noticeLog";

/** The time today, the date and time before. */
function shownTime(at: number) {
  const d = new Date(at);
  const time = d.toLocaleTimeString(language(), { hour: "2-digit", minute: "2-digit" });
  return d.toDateString() === new Date().toDateString() ? time : `${d.toLocaleDateString(language(), { month: "short", day: "numeric" })} ${time}`;
}

export function StatusBar({ version, onUpdates }: { version: string | null; onUpdates: () => void }) {
  const [about, setAbout] = useState(false);
  const [log, setLog] = useState(false);
  return (
    <footer className="statusbar">
      <button className="sb-btn" onClick={() => openUrl(LINKS.discord).catch(() => {})} title={t("app.status.discordHint")}>
        <DiscordIcon />
        <span>dsc.gg/hd1modding</span>
      </button>
      <span className="spacer" />
      {version && (
        <button className="sb-btn" onClick={onUpdates} title={t("app.status.updates")}>v{version}</button>
      )}
      <button className={about ? "sb-btn round on" : "sb-btn round"} onClick={() => setAbout(true)} aria-label={t("app.about.title")} title={t("app.about.title")}>
        <InfoIcon />
      </button>
      <button className={log ? "sb-btn round on" : "sb-btn round"} data-pop onClick={() => setLog((v) => !v)} aria-expanded={log}
        aria-label={t("app.status.notifications")} title={t("app.status.notifications")}>
        <BellIcon />
      </button>
      {log && <NotificationList onClose={() => setLog(false)} />}
      {about && version && <AboutDialog version={version} onClose={() => setAbout(false)} />}
    </footer>
  );
}

/** The notices shown so far, newest first. Esc, a click outside or the bell again closes it. */
function NotificationList({ onClose }: { onClose: () => void }) {
  const log = useNoticeLog();
  const box = useRef<HTMLDivElement>(null);
  const close = useRef(onClose);
  close.current = onClose;
  useEffect(() => {
    box.current?.focus();
    const away = (e: PointerEvent) => {
      const el = e.target as Element;
      if (!box.current?.contains(el) && !el.closest?.("[data-pop]")) close.current();
    };
    const key = (e: KeyboardEvent) => e.key === "Escape" && close.current();
    document.addEventListener("pointerdown", away, true);
    window.addEventListener("keydown", key);
    return () => {
      document.removeEventListener("pointerdown", away, true);
      window.removeEventListener("keydown", key);
    };
  }, []);
  return (
    <div className="sb-pop" role="dialog" aria-label={t("app.status.notifications")} ref={box} tabIndex={-1}>
      <h2 className="cap">{t("app.status.notifications")}</h2>
      {log.length ? (
        <ol className="note-log">
          {[...log].reverse().map((n) => (
            <li key={n.id} className={`note-row ${n.kind}`}>
              <span className="note-time">{shownTime(n.at)}</span>
              <span>{n.text}</span>
            </li>
          ))}
        </ol>
      ) : (
        <p className="muted">{t("app.status.noNotifications")}</p>
      )}
    </div>
  );
}
