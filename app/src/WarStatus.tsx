// The Galactic War panel on Home: each enemy front, the events running now and how many players are
// fighting. Read from the official API when Home opens and every five minutes while it stays open;
// a visit within a minute of the last read shows what was read then.
import { openUrl } from "@tauri-apps/plugin-opener";
import { useEffect, useState } from "react";
import { call } from "./api";
import { t } from "./i18n";
import { OutboundIcon } from "./Icons";
import { LINKS } from "./links";
import { ENEMIES, readWar, timeLeft, type War } from "./war";

const EVERY_MS = 5 * 60_000;
const FRESH_MS = 60_000;
let last: { at: number; war: War } | null = null;

function Bar({ pct, enemy }: { pct: number; enemy: number }) {
  return <div className={`war-bar e${enemy}`}><i style={{ width: `${(pct * 100).toFixed(1)}%` }} /></div>;
}

function left(end: number) {
  const l = timeLeft(end);
  return t("app.war.left", t(l.days ? "app.war.dh" : "app.war.hm", l.big, l.small));
}

export function WarStatus() {
  const [war, setWar] = useState<War | null>(last?.war ?? null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let gone = false;
    const read = () =>
      call<string>("war_status")
        .then((json) => {
          last = { at: Date.now(), war: readWar(json) };
          if (!gone) { setWar(last.war); setFailed(false); }
        })
        .catch(() => !gone && setFailed(true));
    if (!last || Date.now() - last.at > FRESH_MS) read();
    const timer = setInterval(read, EVERY_MS);
    return () => { gone = true; clearInterval(timer); };
  }, []);

  return (
    <section className="war" aria-label={t("app.war.title")}>
      <header>
        <h2 data-tip={t("app.war.source")}>{t("app.war.title")}</h2>
        {war && <span>{t("app.war.season", war.season, war.day)}</span>}
      </header>
      {!war && <p className="war-note">{failed ? t("app.war.unavailable") : t("app.war.loading")}</p>}
      {war && (
        <>
          <ul className="war-fronts">
            {war.fronts.map((f) => (
              <li key={f.enemy} className={`e${f.enemy} ${f.status}`}>
                <div className="war-line">
                  <b>{t(`app.war.${ENEMIES[f.enemy]}`)}</b>
                  <span className="war-state">{t(`app.war.${f.status}`) === `app.war.${f.status}` ? f.status : t(`app.war.${f.status}`)}</span>
                </div>
                {f.region && (
                  <>
                    <div className="war-line sub">
                      <span>{f.region} · {f.capital}</span>
                      <span>{Math.floor(f.pct * 100)}%</span>
                    </div>
                    <Bar pct={f.pct} enemy={f.enemy} />
                  </>
                )}
              </li>
            ))}
          </ul>
          {war.events.map((e) => (
            <div key={`${e.kind}${e.enemy}`} className={`war-event e${e.enemy}`}>
              <div className="war-line">
                <b>{t(`app.war.${e.kind}`, e.place)}</b>
                <span>{left(e.ends)}</span>
              </div>
              <div className="war-line sub">
                <span>{t(`app.war.${ENEMIES[e.enemy]}`)}</span>
                <span>{Math.floor(e.pct * 100)}%</span>
              </div>
              <Bar pct={e.pct} enemy={e.enemy} />
            </div>
          ))}
          <footer>
            <span>{t("app.war.players", war.players.toLocaleString())}</span>
            <button className="bare war-more" onClick={() => openUrl(LINKS.warHistory).catch(() => {})} data-tip-title={t("app.war.more")} data-tip={t("app.war.moreHint")}>
              helldivers.bot <OutboundIcon />
            </button>
          </footer>
        </>
      )}
    </section>
  );
}
