-- Mission: objectives, extraction, waits, samples, and a practice drop from the ship.
local U = obsidian.module("pages/ui")
local api, t = U.api, U.t
local mission = api.mission

local practice = { time = 2, environment = 1, enemy = 1, kind = 1, difficulty = 5 }

local function choices(list)
	local out = {}
	for i, id in ipairs(list) do out[i] = { id = i, label = t("seed_" .. id) } end
	return out
end

local function pick(page, key, field, list)
	page:choice(t(key), { choices = choices(list), get = function() return practice[field] end, set = function(v) practice[field] = v end })
end

local function practice_page(page)
	pick(page, "seed_time", "time", mission.TIMES)
	pick(page, "seed_environment", "environment", mission.ENVIRONMENTS)
	pick(page, "seed_enemy", "enemy", mission.FACTIONS)
	pick(page, "seed_kind", "kind", mission.TYPES)
	page:number(t("seed_difficulty"), { min = 1, max = 15, step = 1, get = function() return practice.difficulty end, set = function(v) practice.difficulty = v end })
	page:action(t("practice_start"), U.act(mission.practice, practice), { help = U.help("practice_start") })
end

return function(page)
	page:label(function()
		local params, seed = mission.params()
		if not params then return t("no_mission") end
		return t("mission_info", tostring(seed), tostring(params.difficulty or "?"), tostring(params.enemy or "?"))
	end)

	page:header(t("objectives"))
	U.action(page, "finish_objectives", mission.finish_objectives)
	U.action(page, "restart_objectives", mission.restart_objectives)
	U.effect(page, "fast_extract", "fast_extract")
	U.action(page, "win", mission.win)
	U.action(page, "abort", mission.abort)

	page:header(t("waits"))
	U.effect(page, "skip_waits", "skip_waits")
	U.effect(page, "fast_mission_start", "fast_mission_start")

	page:header(t("reinforcements"))
	U.effect(page, "infinite_respawns", "infinite_respawns")
	U.effect(page, "no_game_over", "no_game_over")

	page:header(t("samples"))
	U.action(page, "spawn_samples", mission.spawn_samples)
	U.action(page, "collect_samples", mission.collect_samples)
	U.action(page, "reveal_map", mission.reveal_map)

	page:header(t("practice"))
	page:page(t("practice_setup"), practice_page, { help = U.help("practice_setup") })
end
