import { describe, expect, it } from "vitest";
import { readWar, timeLeft } from "../war";

// Trimmed from a real get_campaign_status answer (season 161).
const ANSWER = JSON.stringify({
  time: 1793339199,
  error_code: 0,
  campaign_status: [
    { season: 161, points: 1063, points_taken: 936752, points_max: 319290, status: "active", introduction_order: 1 },
    { season: 161, points: 250490, points_taken: 203451, points_max: 250490, status: "defeated", introduction_order: 0 },
    { season: 161, points: 133780, points_taken: 224198, points_max: 133780, status: "defeated", introduction_order: 2 },
  ],
  defend_event: { season: 161, event_id: 5236, start_time: 1793230682, end_time: 1793403482, region: 0, enemy: 0, points_max: 38732, points: 22652, status: "active" },
  attack_events: [
    { season: 161, event_id: 933, start_time: 1790801221, end_time: 1790931361, enemy: 1, points_max: 12009, points: 12009, status: "success" },
    { season: 161, event_id: 937, start_time: 1793300000, end_time: 1793400000, enemy: 2, points_max: 10000, points: 2500, status: "active" },
  ],
  statistics: [
    { season: 161, season_duration: 3695834, enemy: 0, players: 148 },
    { season: 161, season_duration: 3695834, enemy: 1, players: 5 },
    { season: 161, season_duration: 3695834, enemy: 2, players: 0 },
  ],
});

describe("readWar", () => {
  it("reads the season, the day and the players", () => {
    const w = readWar(ANSWER);
    expect([w.season, w.day, w.players]).toEqual([161, 43, 153]);
  });

  it("finds the region being fought over on an active front", () => {
    const [bugs, cyborgs] = readWar(ANSWER).fronts;
    expect(bugs).toMatchObject({ status: "active", index: 0, region: "Wise Region", capital: "New New York" });
    expect(bugs.pct).toBeCloseTo(1063 / 31929);
    expect(cyborgs).toMatchObject({ status: "defeated", index: 11, region: null, pct: 1 });
  });

  it("lists only the events running now; a defend of region 0 is Super Earth, an attack the homeworld", () => {
    const events = readWar(ANSWER).events;
    expect(events.map((e) => [e.kind, e.region, e.place])).toEqual([["defend", 0, "Super Earth"], ["attack", 11, "Squ'bai Shrine"]]);
    expect(events[1].pct).toBe(0.25);
  });

  it("refuses an answer with no campaign", () => {
    expect(() => readWar(JSON.stringify({ error_code: 1 }))).toThrow();
  });
});

describe("timeLeft", () => {
  it("gives days and hours past a day, else hours and minutes", () => {
    expect(timeLeft(1000 + 86400 + 3 * 3600, 1000)).toEqual({ big: 1, small: 3, days: true });
    expect(timeLeft(1000 + 2 * 3600 + 5 * 60, 1000)).toEqual({ big: 2, small: 5, days: false });
    expect(timeLeft(0, 1000)).toEqual({ big: 0, small: 0, days: false });
  });
});
