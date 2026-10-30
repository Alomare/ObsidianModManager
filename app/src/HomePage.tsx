// Home: the game's cover under a blur and a dark gradient that come from the top left corner, the
// name at the top left and links at the bottom left. Each link opens in the browser; the tooltip
// shows where. The button beside the links tucks them away for a clear view of the cover, and
// brings them back; the choice is remembered.
import { openUrl } from "@tauri-apps/plugin-opener";
import { useLayoutEffect, useRef, useState, type ReactNode } from "react";
import cover from "./assets/home-cover.webp";
import logo from "./assets/logo-shaded.png";
import { ChevronIcon, DiscordIcon, GitHubIcon, KofiIcon, OutboundIcon, SearchIcon } from "./Icons";
import { t } from "./i18n";
import { LINKS } from "./links";

const TUCK_KEY = "obsidian.homeLinksTucked";

function Link({ url, cls, icon, label, i, hidden }: { url: string; cls: string; icon: ReactNode; label: string; i: number; hidden: boolean }) {
  return (
    <button className={`btn ${cls}`} style={{ ["--i" as string]: i }} tabIndex={hidden ? -1 : undefined} aria-hidden={hidden}
      onClick={() => openUrl(url).catch(() => {})} data-tip-title={label} data-tip={url}>
      {icon}
      {label}
      <OutboundIcon />
    </button>
  );
}

function readTucked(): boolean {
  try {
    return localStorage.getItem(TUCK_KEY) === "1";
  } catch {
    return false;
  }
}

export function HomePage() {
  const [tucked, setTucked] = useState(readTucked);
  const list = useRef<HTMLDivElement>(null);
  // Each link flies to and from the toggle button, so each needs to know how far away it is.
  useLayoutEffect(() => {
    for (const el of list.current?.children ?? []) {
      const b = el as HTMLElement;
      b.style.setProperty("--off", `${b.offsetLeft + b.offsetWidth / 2}px`);
    }
  });
  const toggle = () =>
    setTucked((v) => {
      try { localStorage.setItem(TUCK_KEY, v ? "0" : "1"); } catch { /* remembered for this visit only */ }
      return !v;
    });
  const label = tucked ? t("app.home.showLinks") : t("app.home.hideLinks");
  return (
    <div className="home" style={{ backgroundImage: `url(${cover})` }}>
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
        <div className={tucked ? "home-links tucked" : "home-links"}>
          <button className="btn home-tuck" onClick={toggle} aria-expanded={!tucked} aria-label={label} data-tip={label}>
            <ChevronIcon />
          </button>
          <div className="home-link-list" ref={list} style={{ ["--n" as string]: 4 }}>
            <Link i={0} hidden={tucked} url={LINKS.nexus} cls="play" icon={<SearchIcon />} label={t("app.home.nexus")} />
            <Link i={1} hidden={tucked} url={LINKS.discord} cls="discord" icon={<DiscordIcon />} label={t("app.home.discord")} />
            <Link i={2} hidden={tucked} url={LINKS.kofi} cls="" icon={<KofiIcon />} label={t("app.home.sponsor")} />
            <Link i={3} hidden={tucked} url={LINKS.repo} cls="" icon={<GitHubIcon />} label={t("app.home.github")} />
          </div>
        </div>
      </div>
    </div>
  );
}
