// The Galactic War on Home: Super Earth in the middle, a flat cone per enemy reaching out to the
// enemy homeworld, the war calendar and how many Helldivers are fighting. The part of a cone near
// Super Earth is the ground already liberated. Hovering a cone names the region being fought over,
// or says the enemy is defeated. Read from the official API when Home opens and every five minutes
// while it stays open; a visit within a minute of the last read shows what was read then. The
// button in the corner folds the panel down to itself; the choice is remembered.
import { useEffect, useState } from "react";
import { call } from "./api";
import { t } from "./i18n";
import { ChevronIcon } from "./Icons";
import { ENEMIES, readWar, timeLeft, type Front, type War } from "./war";

const EVERY_MS = 5 * 60_000;
const FRESH_MS = 60_000;
const TUCK_KEY = "obsidian.homeWarTucked";
let last: { at: number; war: War } | null = null;

// Map geometry, in the units of the SVG view box (-110 to 110).
const CORE = 15; // Super Earth
const INNER = 21; // where the cones start
const OUTER = 88; // where the cones end
const HALF = 54; // half the angle of a cone, in degrees
const HOME_R = 99; // where the homeworlds sit
/** The middle of each cone: bugs at the top, then clockwise. */
const AXIS = [-90, 30, 150];

const rad = (deg: number) => (deg * Math.PI) / 180;
const pt = (r: number, deg: number) => `${(r * Math.cos(rad(deg))).toFixed(2)} ${(r * Math.sin(rad(deg))).toFixed(2)}`;
/** A ring segment between radii r1 and r2, from angle a1 to a2 (degrees, clockwise). */
const arc = (r1: number, r2: number, a1: number, a2: number) =>
  `M${pt(r1, a1)}L${pt(r2, a1)}A${r2} ${r2} 0 0 1 ${pt(r2, a2)}L${pt(r1, a2)}A${r1} ${r1} 0 0 0 ${pt(r1, a1)}Z`;
const hex = (r: number, cx = 0, cy = 0) =>
  `M${[0, 1, 2, 3, 4, 5].map((i) => { const a = rad(60 * i - 90); return `${(cx + r * Math.cos(a)).toFixed(2)} ${(cy + r * Math.sin(a)).toFixed(2)}`; }).join("L")}Z`;

function Cone({ f }: { f: Front }) {
  const axis = AXIS[f.enemy];
  const name = t(`app.war.${ENEMIES[f.enemy]}`);
  const a1 = axis - HALF;
  const a2 = axis + HALF;
  // How far out Super Earth has pushed: ten regions, then the homeworld.
  const reach = f.status === "defeated" ? 1 : f.status === "active" ? Math.min(1, (f.index + f.pct) / 10) : 0;
  const edge = INNER + (OUTER - INNER) * reach;
  const tip = f.status === "defeated" ? t("app.war.defeated") : f.status === "active" ? `${f.region} · ${f.capital}` : t("app.war.hidden");
  const [hx, hy] = pt(HOME_R, axis).split(" ").map(Number);
  return (
    <g className={`cone e${f.enemy} ${f.status}`} data-tip-title={name} data-tip={tip}>
      <path className="enemy" d={arc(INNER, OUTER, a1, a2)} />
      {reach > 0 && <path className="held" d={arc(INNER, edge, a1, a2)} />}
      <path className="homeworld" d={hex(6.5, hx, hy)} />
    </g>
  );
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
  const defend = war?.events.find((e) => e.kind === "defend" && e.region === 0);
  const coreTip = defend
    ? t("app.war.defendTip", t(`app.war.${ENEMIES[defend.enemy]}`), (({ big, small, days }) => t(days ? "app.war.dh" : "app.war.hm", big, small))(timeLeft(defend.ends)))
    : t("app.war.core");

  return (
    <section className={tucked ? "war tucked" : "war"} aria-label={t("app.war.title")}>
      <header>
        <span className="war-calendar" aria-hidden={tucked} data-tip={t("app.war.source")}>
          {war ? t("app.war.season", war.season, war.day) : failed ? t("app.war.unavailable") : t("app.war.loading")}
        </span>
        <button className="bare war-tuck" onClick={toggle} aria-expanded={!tucked} aria-label={label} data-tip={label}><ChevronIcon /></button>
      </header>
      <div className="war-body" aria-hidden={tucked}>
        <div>
          {war && (
            <>
              <svg className="war-map" viewBox="-110 -110 220 220" role="img" aria-label={t("app.war.title")}>
                {war.fronts.map((f) => <Cone key={f.enemy} f={f} />)}
                <path className={defend ? "core hit" : "core"} d={hex(CORE)} data-tip-title="Super Earth" data-tip={coreTip} />
              </svg>
              <p className="war-players"><b>{war.players.toLocaleString()}</b> {t("app.war.players")}</p>
            </>
          )}
        </div>
      </div>
    </section>
  );
}
