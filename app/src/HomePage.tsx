// Home: the game's cover behind a progressive blur and a dark gradient, with the name and links
// aligned to the left.
import { openUrl } from "@tauri-apps/plugin-opener";
import cover from "./assets/home-cover.webp";
import logo from "./assets/logo-shaded.png";
import { DiscordIcon, KofiIcon, SearchIcon } from "./Icons";
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
          <button className="btn play" onClick={go(LINKS.nexus)}><SearchIcon />{t("app.home.nexus")}</button>
          <button className="btn discord" onClick={go(LINKS.discord)}><DiscordIcon />{t("app.home.discord")}</button>
          <button className="btn" onClick={go(LINKS.kofi)}><KofiIcon />{t("app.home.sponsor")}</button>
        </div>
      </div>
    </div>
  );
}
