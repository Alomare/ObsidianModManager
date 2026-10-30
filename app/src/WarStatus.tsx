// The Galactic War on Home, drawn as the war map of the game: Super Earth in the middle, a wedge per
// enemy, ten rings of regions from Super Earth out to the enemy homeworld at the rim. Regions Super
// Earth holds are light, enemy regions take the enemy color, and the ring being fought over fills
// with gold as players liberate it. Events pulse where they happen. Read from the official API when
// Home opens and every five minutes while it stays open; a visit within a minute of the last read
// shows what was read then. The button beside the panel tucks it away; the choice is remembered.
import { openUrl } from "@tauri-apps/plugin-opener";
import { useEffect, useState } from "react";
import { call } from "./api";
import { t } from "./i18n";
import { ChevronIcon, OutboundIcon } from "./Icons";
import { LINKS } from "./links";
import { ENEMIES, REGIONS, readWar, timeLeft, type Front, type War, type WarEvent } from "./war";

const EVERY_MS = 5 * 60_000;
const FRESH_MS = 60_000;
const TUCK_KEY = "obsidian.homeWarTucked";
let last: { at: number; war: War } | null = null;

// Map geometry, in the units of the SVG view box (-110 to 110).
const CORE = 15; // Super Earth
const RING0 = 22; // inner edge of region 1
const STEP = 7.1; // one ring of regions
const BAND = 5.8; // the drawn width of a ring
const CELLS = 6; // cells per ring, across the wedge
const HALF = 56; // half the angle of a wedge, in degrees
const HOME_R = 100; // where the homeworld sits

const rad = (deg: number) => (deg * Math.PI) / 180;
const pt = (r: number, deg: number) => `${(r * Math.cos(rad(deg))).toFixed(2)} ${(r * Math.sin(rad(deg))).toFixed(2)}`;
/** A ring segment between radii r1 and r2, from angle a1 to a2 (degrees, clockwise). */
const arc = (r1: number, r2: number, a1: number, a2: number) =>
  `M${pt(r1, a1)}L${pt(r2, a1)}A${r2} ${r2} 0 0 1 ${pt(r2, a2)}L${pt(r1, a2)}A${r1} ${r1} 0 0 0 ${pt(r1, a1)}Z`;
const hex = (r: number, cx = 0, cy = 0) =>
  `M${[0, 1, 2, 3, 4, 5].map((i) => { const a = rad(60 * i - 90); return `${(cx + r * Math.cos(a)).toFixed(2)} ${(cy + r * Math.sin(a)).toFixed(2)}`; }).join("L")}Z`;
/** The middle of each wedge: bugs at the top, then clockwise. */
const AXIS = [-90, 30, 150];

function Wedge({ f, event }: { f: Front; event: WarEvent | undefined }) {
  const axis = AXIS[f.enemy];
  const names = REGIONS[f.enemy] ?? [];
  const hidden = f.status !== "active" && f.status !== "defeated";
  const span = (2 * HALF) / CELLS;
  const rings = [];
  for (let k = 1; k <= 10; k++) {
    const r1 = RING0 + (k - 1) * STEP;
    const held = k <= f.index;
    const front = !held && k === f.index + 1 && f.status === "active";
    const state = hidden ? "fog" : held ? "held" : front ? "front" : "enemy";
    const [region, capital] = names[k - 1] ?? ["", ""];
    const cells = [];
    for (let c = 0; c < CELLS; c++) {
      const a1 = axis - HALF + c * span + 0.9;
      const a2 = axis - HALF + (c + 1) * span - 0.9;
      cells.push(<path key={c} d={arc(r1, r1 + BAND, a1, a2)} />);
      // The front fills cell by cell, from the left edge of the wedge.
      if (front) {
        const fill = Math.max(0, Math.min(1, f.pct * CELLS - c));
        if (fill > 0) cells.push(<path key={`g${c}`} className="won" d={arc(r1, r1 + BAND, a1, a1 + (a2 - a1) * fill)} />);
      }
    }
    const tip = hidden ? t("app.war.hidden") : held ? t("app.war.held") : front ? t("app.war.frontTip", Math.floor(f.pct * 100)) : t("app.war.enemyHeld");
    const hit = event?.kind === "defend" && event.region === k;
    rings.push(
      <g key={k} className={`ring ${state}${hit ? " hit" : ""}`} data-tip-title={`${region} · ${capital}`} data-tip={tip}>{cells}</g>,
    );
  }
  const [hx, hy] = pt(HOME_R, axis).split(" ").map(Number);
  const homeState = hidden ? "fog" : f.index >= 11 ? "held" : "enemy";
  const attack = event?.kind === "attack";
  const [home, homeCapital] = names[10] ?? ["", ""];
  return (
    <g className={`wedge e${f.enemy}`}>
      {rings}
      <g className={`homeworld ${homeState}${attack ? " hit" : ""}`} data-tip-title={`${homeCapital} · ${home}`}
        data-tip={attack ? t("app.war.attackTip", Math.floor((event?.pct ?? 0) * 100)) : homeState === "held" ? t("app.war.defeatedTip", t(`app.war.${ENEMIES[f.enemy]}`)) : t("app.war.homeworld")}>
        <path d={hex(6.5, hx, hy)} />
        {attack && <circle className="event-ring" cx={hx} cy={hy} r={10} pathLength={100} strokeDasharray={`${(event?.pct ?? 0) * 100} 100`} />}
      </g>
    </g>
  );
}

function WarMap({ war }: { war: War }) {
  const at = (enemy: number) => war.events.find((e) => e.enemy === enemy && e.region > 0);
  const home = war.events.find((e) => e.kind === "defend" && e.region === 0);
  return (
    <svg className="war-map" viewBox="-110 -110 220 220" role="img" aria-label={t("app.war.title")}>
      {/* Faint rings behind the map, as on the war table of the ship */}
      <g className="grid" aria-hidden="true">
        {[40, 70, 100].map((r) => <circle key={r} r={r} />)}
        {AXIS.map((a) => <path key={a} d={`M${pt(CORE + 2, a + 60)}L${pt(106, a + 60)}`} />)}
      </g>
      {war.fronts.map((f) => <Wedge key={f.enemy} f={f} event={at(f.enemy)} />)}
      <g className={home ? "core hit" : "core"} data-tip-title="Super Earth"
        data-tip={home ? t("app.war.defendTip", t(`app.war.${ENEMIES[home.enemy]}`), Math.floor(home.pct * 100)) : t("app.war.core")}>
        <path d={hex(CORE)} />
        {home && <circle className="event-ring" r={CORE + 4} pathLength={100} strokeDasharray={`${home.pct * 100} 100`} />}
      </g>
    </svg>
  );
}

function left(end: number) {
  const l = timeLeft(end);
  return t(l.days ? "app.war.dh" : "app.war.hm", l.big, l.small);
}

function readTucked(): boolean {
  try {
    return localStorage.getItem(TUCK_KEY) === "1";
  } catch {
    return false;
  }
}

export function WarStatus() {
  const [war, setWar] = useState<War | null>(last?.war ?? null);
  const [failed, setFailed] = useState(false);
  const [tucked, setTucked] = useState(readTucked);
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
  const toggle = () =>
    setTucked((v) => {
      try { localStorage.setItem(TUCK_KEY, v ? "0" : "1"); } catch { /* remembered for this visit only */ }
      return !v;
    });
  const label = tucked ? t("app.war.show") : t("app.war.hide");

  return (
    <div className={tucked ? "home-war tucked" : "home-war"}>
      <div className="war-clip">
        <section className="war" aria-label={t("app.war.title")} aria-hidden={tucked}>
          <header>
            <h2 className="cap" data-tip={t("app.war.source")}>{t("app.war.title")}</h2>
            {war && <span>{t("app.war.season", war.season, war.day)}</span>}
          </header>
          {war ? <WarMap war={war} /> : <p className="war-note">{failed ? t("app.war.unavailable") : t("app.war.loading")}</p>}
          {war && (
            <>
              <ul className="war-legend">
                {war.fronts.map((f) => (
                  <li key={f.enemy} className={`e${f.enemy} ${f.status}`}>
                    <i aria-hidden="true" />
                    <span className="cap">{t(`app.war.${ENEMIES[f.enemy]}`)}</span>
                    <b>{f.status === "active" ? `${Math.floor(((f.index + f.pct) / 11) * 100)}%` : f.status === "defeated" ? "✓" : "?"}</b>
                  </li>
                ))}
              </ul>
              {war.events.map((e) => (
                <div key={`${e.kind}${e.enemy}`} className={`war-event e${e.enemy}`}>
                  <i aria-hidden="true" />
                  <span className="cap">{t(`app.war.${e.kind}`, e.place)}</span>
                  <b>{left(e.ends)}</b>
                </div>
              ))}
              <footer>
                <span>{t("app.war.players", war.players.toLocaleString())}</span>
                <button className="bare war-more" tabIndex={tucked ? -1 : undefined} onClick={() => openUrl(LINKS.warHistory).catch(() => {})}
                  data-tip-title={t("app.war.more")} data-tip={t("app.war.moreHint")}>
                  helldivers.bot <OutboundIcon />
                </button>
              </footer>
            </>
          )}
        </section>
      </div>
      <button className="btn war-tuck" onClick={toggle} aria-expanded={!tucked} aria-label={label} data-tip={label}>
        <ChevronIcon />
      </button>
    </div>
  );
}
