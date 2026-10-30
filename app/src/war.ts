// The Galactic War status for Home: what the official Helldivers 1 API sends, read into what the
// widget shows. Each enemy holds ten regions and a homeworld; Super Earth takes them back in order.

/** Region and capital names per enemy (bugs, cyborgs, illuminate), regions 1 to 11; 11 is the homeworld. */
export const REGIONS: [string, string][][] = [
  [["Wise Region", "New New York"], ["Kruger System", "Liberty City"], ["Ross System", "Tiberia"], ["Struve Region", "Northman's Creek"], ["Xi Tauri Region", "New Haven"], ["Cancri System", "Freedom Fortress"], ["Higgs Region", "Martyr's Bay"], ["Hawking Region", "Segma Prime"], ["Rigel System", "Freedom Peak"], ["Aurigae Region", "Final Frontier"], ["Kepler System", "Kepler Prime"]],
  [["Sirius Region", "Stockholm City"], ["Polaris Region", "Thunder Head"], ["Pictor Sector", "New Moscow"], ["Sagan Region", "Highwind"], ["Horolium System", "Providence"], ["Gellert Region", "Gellert City"], ["Lacaille Region", "Bahia Democracia"], ["Indi System", "Winter Hold"], ["Ceti System", "Doral Creek"], ["Cygni Region", "New Berlin"], ["Cyberstan Region", "Cyberstan"]],
  [["Centaury Region", "New Hanover"], ["Barnard Region", "Iron Tower"], ["Procyon Region", "White Landing"], ["Castor System", "Justice Bay"], ["Orionis Region", "New Alexandria"], ["Prometheus System", "Ribatishiti"], ["Cassiopaiae Region", "Dal Rage"], ["Ursa Region", "Ultima"], ["Canes Region", "Jiyu Toshi"], ["Arcturus Region", "Hawk Nest"], ["Squ'bai System", "Squ'bai Shrine"]],
];
export const ENEMIES = ["bugs", "cyborgs", "illuminate"] as const;

/** `index`: how many regions Super Earth holds on this front (0 to 10), 11 once the enemy is defeated. */
export type Front = { enemy: number; status: string; index: number; region: string | null; capital: string | null; pct: number };
/** `region`: 0 is Super Earth, 1 to 10 the regions of the enemy, 11 the homeworld. */
export type WarEvent = { kind: "defend" | "attack"; enemy: number; region: number; place: string; pct: number; ends: number };
export type War = { season: number; day: number; players: number; fronts: Front[]; events: WarEvent[] };

type Campaign = { points: number; points_max: number; status: string };
type Event = { enemy: number; region?: number; points: number; points_max: number; status: string; end_time: number };
type Stat = { season: number; season_duration: number; players: number };
type Raw = { campaign_status?: Campaign[]; defend_event?: Event | null; attack_events?: Event[]; statistics?: Stat[] };

const share = (n: number, max: number) => (max > 0 ? Math.max(0, Math.min(1, n / max)) : 0);

/** Where Super Earth stands against one enemy: the region being fought over and how far along it is. */
function front(c: Campaign, enemy: number): Front {
  if (c.status !== "active") return { enemy, status: c.status, index: c.status === "defeated" ? 11 : 0, region: null, capital: null, pct: c.status === "defeated" ? 1 : 0 };
  const per = c.points_max / 10;
  const i = per > 0 ? Math.min(10, Math.floor(c.points / per)) : 0;
  const [region, capital] = REGIONS[enemy]?.[i] ?? [null, null];
  return { enemy, status: c.status, index: i, region, capital, pct: i === 10 ? 1 : share(c.points - i * per, per) };
}

function event(e: Event, kind: WarEvent["kind"]): WarEvent {
  // Defend events name a region by number, 0 being Super Earth; attacks go for the homeworld.
  const place = kind === "attack" ? REGIONS[e.enemy]?.[10][1] : e.region ? REGIONS[e.enemy]?.[e.region - 1]?.[0] : "Super Earth";
  return { kind, enemy: e.enemy, region: kind === "attack" ? 11 : e.region ?? 0, place: place ?? "?", pct: share(e.points, e.points_max), ends: e.end_time };
}

/** Reads the API answer (JSON text). Throws when it holds no campaign. */
export function readWar(json: string): War {
  const raw = JSON.parse(json) as Raw;
  const campaign = raw.campaign_status ?? [];
  if (!campaign.length) throw new Error("no campaign in the answer");
  const stats = raw.statistics ?? [];
  const events: WarEvent[] = [];
  if (raw.defend_event?.status === "active") events.push(event(raw.defend_event, "defend"));
  for (const a of raw.attack_events ?? []) if (a.status === "active") events.push(event(a, "attack"));
  return {
    season: stats[0]?.season ?? 0,
    day: Math.floor((stats[0]?.season_duration ?? 0) / 86400) + 1,
    players: stats.reduce((n, s) => n + (s.players ?? 0), 0),
    fronts: campaign.slice(0, 3).map(front),
    events,
  };
}

/** Days and hours, or hours and minutes, until `end` (Unix seconds). */
export function timeLeft(end: number, now = Date.now() / 1000): { big: number; small: number; days: boolean } {
  const s = Math.max(0, end - now);
  return s >= 86400 ? { big: Math.floor(s / 86400), small: Math.floor((s % 86400) / 3600), days: true } : { big: Math.floor(s / 3600), small: Math.floor((s % 3600) / 60), days: false };
}
