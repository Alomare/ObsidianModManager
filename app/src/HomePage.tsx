// Home: the game's cover behind a progressive blur and a dark gradient, the name at the top left
// and links at the bottom left. Each link opens in the browser; the tooltip shows where.
import { openUrl } from "@tauri-apps/plugin-opener";
import type { ReactNode } from "react";
import cover from "./assets/home-cover.webp";
import logo from "./assets/logo-shaded.png";
import { DiscordIcon, GitHubIcon, KofiIcon, OutboundIcon, SearchIcon } from "./Icons";
import { t } from "./i18n";
import { LINKS } from "./links";

function Link({ url, cls, icon, label }: { url: string; cls: string; icon: ReactNode; label: string }) {
  return (
    <button className={`btn ${cls}`} onClick={() => openUrl(url).catch(() => {})} data-tip-title={label} data-tip={url}>
      {icon}
      {label}
      <OutboundIcon />
    </button>
  );
}

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
          <Link url={LINKS.nexus} cls="play" icon={<SearchIcon />} label={t("app.home.nexus")} />
          <Link url={LINKS.discord} cls="discord" icon={<DiscordIcon />} label={t("app.home.discord")} />
          <Link url={LINKS.kofi} cls="" icon={<KofiIcon />} label={t("app.home.sponsor")} />
          <Link url={LINKS.repo} cls="" icon={<GitHubIcon />} label={t("app.home.github")} />
        </div>
      </div>
    </div>
  );
}
