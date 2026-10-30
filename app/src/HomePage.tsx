// Home: the game's cover behind a progressive blur and a dark gradient, the name at the top left
// and links at the bottom: Nexus and Sponsor on the left, and on the right the Discord button,
// which slides the server's widget (who is online, Join) up out of itself.
import { openUrl } from "@tauri-apps/plugin-opener";
import { useEffect, useState } from "react";
import { call } from "./api";
import cover from "./assets/home-cover.webp";
import logo from "./assets/logo-shaded.png";
import { ChevronIcon, DiscordIcon, KofiIcon, SearchIcon } from "./Icons";
import { t } from "./i18n";
import { LINKS } from "./links";

const go = (url: string) => () => openUrl(url).catch(() => {});

export function HomePage() {
  return (
    <div className="home" style={{ backgroundImage: `url(${cover})` }}>
      {/* Blur that grows toward the left edge, in layers, under a dark gradient. */}
      <div className="home-blur" aria-hidden="true"><i /><i /><i /><i /></div>
      <div className="home-shade" aria-hidden="true" />
      <div className="home-body">
        <div className="home-brand">
          <img src={logo} alt="" draggable={false} />
          <div>
            <h1>OBSIDIAN</h1>
            <p>{t("app.home.subtitle")}</p>
          </div>
        </div>
        <div className="home-links">
          <div className="home-left">
            <button className="btn play" onClick={go(LINKS.nexus)}><SearchIcon />{t("app.home.nexus")}</button>
            <button className="btn" onClick={go(LINKS.kofi)}><KofiIcon />{t("app.home.sponsor")}</button>
          </div>
          <DiscordDrawer />
        </div>
      </div>
    </div>
  );
}

type Member = { id: string; username: string; status: string; avatar_url: string };
type Widget = { name: string; instant_invite: string | null; presence_count: number; members: Member[] };

// One fetch per run of the app is enough for a glance at who is online.
let cached: Widget | null = null;

function DiscordDrawer() {
  const [open, setOpen] = useState(false);
  const [widget, setWidget] = useState<Widget | null>(cached);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    if (!open || widget) return;
    setFailed(false);
    call<Widget>("discord_widget").then((w) => setWidget((cached = w))).catch(() => setFailed(true));
  }, [open, widget]);

  return (
    <div className={open ? "dc open" : "dc"}>
      <div className="dc-slide" aria-hidden={!open} inert={!open}>
        <div className="dc-panel">
          {widget ? (
            <>
              <div className="dc-head">
                <b>{widget.name}</b>
                <span><i className="dc-dot online" />{t("app.home.online", widget.presence_count)}</span>
              </div>
              <ul className="dc-members">
                {widget.members.map((m) => (
                  <li key={m.id + m.username}>
                    <span className="dc-avatar"><img src={m.avatar_url} alt="" /><i className={`dc-dot ${m.status}`} /></span>
                    {m.username}
                  </li>
                ))}
              </ul>
            </>
          ) : (
            <p className="dc-note">{failed ? t("app.home.widgetError") : t("app.home.widgetLoading")}</p>
          )}
          <button className="btn dc-join" onClick={go(widget?.instant_invite ?? LINKS.discord)}>{t("app.home.join")}</button>
        </div>
      </div>
      <button className="btn discord" aria-expanded={open} onClick={() => setOpen((o) => !o)}>
        <DiscordIcon />
        {t("app.home.discord")}
        <span className="dc-arrow"><ChevronIcon /></span>
      </button>
    </div>
  );
}
